## Manages the begin / apply / commit / cancel lifecycle for vertex-level
## UV drag in the UV editor.
##
## Coincident UV vertices (those sharing the same position within epsilon)
## are automatically grouped during [method apply] so that shared corners
## move together. When [param isolate_faces] is non-empty, only UV vertices
## on faces in that set are moved — coincident UVs on hidden faces are left
## untouched.
##
## When snap is active, each vertex's final position (original + cumulative
## delta) is snapped to the UV grid so vertices land exactly on grid
## intersections.
@tool
class_name UvVertexTransform
extends RefCounted

# Self-preloads — dependency order.
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")


class DragState:
	var start_uv: Vector2 = Vector2.ZERO
	var prev_uv: Vector2 = Vector2.ZERO
	var snapshot: Dictionary = {}
	var precision: bool = false
	## Cumulative freehand offset from the start position, without snap rounding.
	var cumulative_freehand: Vector2 = Vector2.ZERO
	## Original UV positions of all handles at drag start.
	## Key: Vector2i(face_index, uv_index), Value: Vector2(original_uv).
	## Populated on the first [method apply] call.
	var start_positions: Dictionary = {}


const SENSITIVITY_MOVE: float = 1.0
const PRECISION_MULTIPLIER: float = 0.1


## Begin a new vertex drag.  Returns a [DragState] the caller should store.
static func begin(mesh: GoBuildMesh, canvas_uv: Vector2) -> DragState:
	var ds := DragState.new()
	ds.start_uv = canvas_uv
	ds.prev_uv = canvas_uv
	if mesh != null:
		ds.snapshot = mesh.take_snapshot()
	ds.cumulative_freehand = Vector2.ZERO
	return ds


## Apply one frame of vertex drag.  Moves all selected UV verts and their
## coincident neighbours by the delta from the previous frame.
## Mutates [param mesh] face UVs in-place.
## When [param snap_size] > 0, each vertex's final position is snapped to
## the nearest UV grid point so vertices land exactly on grid intersections.
## When [param isolate_faces] is non-empty, only UV vertices on faces in that
## set are moved. Coincident UVs on faces outside the set are left untouched.
static func apply(
		mesh: GoBuildMesh,
		selected: Array[Vector2i],
		ds: DragState,
		canvas_uv: Vector2,
		precision: bool = false,
		snap_size: float = 0.0,
		isolate_faces: Dictionary = {}) -> bool:
	if mesh == null or selected.is_empty():
		return false

	var prec_mult: float = PRECISION_MULTIPLIER if precision else 1.0
	var raw_delta := canvas_uv - ds.prev_uv
	var freehand_delta := raw_delta * SENSITIVITY_MOVE * prec_mult
	if freehand_delta.is_zero_approx():
		return false

	ds.precision = precision
	ds.cumulative_freehand += freehand_delta

	# On first apply, record the starting positions of all handles
	# (selected + coincident neighbours restricted to isolate set).
	if ds.start_positions.is_empty():
		var positions_to_move: Dictionary = {}
		for v: Vector2i in selected:
			var fi: int = v.x
			var vi: int = v.y
			if fi < 0 or fi >= mesh.faces.size():
				continue
			positions_to_move[mesh.faces[fi].uvs[vi]] = true

		var isolate: bool = not isolate_faces.is_empty()
		for fi: int in mesh.faces.size():
			if isolate and not isolate_faces.has(fi):
				continue
			var face: GoBuildFace = mesh.faces[fi]
			for vi: int in face.uvs.size():
				if positions_to_move.has(face.uvs[vi]):
					ds.start_positions[Vector2i(fi, vi)] = face.uvs[vi]

	# When snap is active, each vertex's final position is snapped to the
	# nearest UV grid point. This ensures UVs land exactly on grid
	# intersections (e.g. 0.0, 0.0625, 0.125, ...).
	# Without snap, positions are the freehand offset from start.
	for handle_key: Vector2i in ds.start_positions:
		var hfi: int = handle_key.x
		var hvi: int = handle_key.y
		if hfi < 0 or hfi >= mesh.faces.size():
			continue
		var orig_pos: Vector2 = ds.start_positions[handle_key]
		var target_pos: Vector2 = orig_pos + ds.cumulative_freehand
		if snap_size > 0.0:
			target_pos = Vector2(
				round(target_pos.x / snap_size) * snap_size,
				round(target_pos.y / snap_size) * snap_size)
		mesh.faces[hfi].uvs[hvi] = target_pos

	ds.prev_uv = canvas_uv
	return true