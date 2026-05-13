## Manages the begin / apply / commit / cancel lifecycle for vertex-level
## UV drag in the UV editor.
##
## Coincident UV vertices (those sharing the same position within epsilon)
## are automatically grouped during [method apply] so that shared corners
## move together.
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
	var cumulative_delta: Vector2 = Vector2.ZERO


const SENSITIVITY_MOVE: float = 1.0
const PRECISION_MULTIPLIER: float = 0.1


## Begin a new vertex drag.  Returns a [DragState] the caller should store.
static func begin(mesh: GoBuildMesh, canvas_uv: Vector2) -> DragState:
	var ds := DragState.new()
	ds.start_uv = canvas_uv
	ds.prev_uv = canvas_uv
	if mesh != null:
		ds.snapshot = mesh.take_snapshot()
	return ds


## Apply one frame of vertex drag.  Moves all selected UV verts and their
## coincident neighbours by the delta from the previous frame.
## Mutates [param mesh] face UVs in-place.
static func apply(
		mesh: GoBuildMesh,
		selected: Array[Vector2i],
		ds: DragState,
		canvas_uv: Vector2,
		precision: bool = false) -> bool:
	if mesh == null or selected.is_empty():
		return false
	var prec_mult: float = PRECISION_MULTIPLIER if precision else 1.0
	var raw_delta := canvas_uv - ds.prev_uv
	var delta := raw_delta * SENSITIVITY_MOVE * prec_mult
	if delta.is_zero_approx():
		return false

	ds.precision = precision

	var positions_to_move: Dictionary = {}
	for v: Vector2i in selected:
		var fi: int = v.x
		var vi: int = v.y
		if fi < 0 or fi >= mesh.faces.size():
			continue
		positions_to_move[mesh.faces[fi].uvs[vi]] = true

	var all_handles: Array[Vector2i] = []
	for fi: int in mesh.faces.size():
		var face: GoBuildFace = mesh.faces[fi]
		for vi: int in face.uvs.size():
			if positions_to_move.has(face.uvs[vi]):
				all_handles.append(Vector2i(fi, vi))

	for handle: Vector2i in all_handles:
		var hfi: int = handle.x
		var hvi: int = handle.y
		mesh.faces[hfi].uvs[hvi] = mesh.faces[hfi].uvs[hvi] + delta

	ds.cumulative_delta += delta
	ds.prev_uv = canvas_uv
	return true