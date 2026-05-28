## Manages the begin / apply / commit / cancel lifecycle for island-level
## UV transforms (Move, Rotate, Scale) in the UV editor.
##
## Stateless between operations — the canvas creates an instance, calls
## [method begin], then [method apply] per-frame, and finally
## [method commit] or [method cancel].
##
## Mode values match [GoBuildUvCanvas.UvTransformMode].
@tool
class_name UvIslandTransform
extends RefCounted

const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")

const _PICKER_SCRIPT := preload("res://addons/go_build/uv/uv_picker.gd")


class DragState:
	var mode: int = 0
	var start_uv: Vector2 = Vector2.ZERO
	var prev_uv: Vector2 = Vector2.ZERO
	var pivot: Vector2 = Vector2.ZERO
	var scale_start: float = 1.0
	var snapshot: Dictionary = {}
	var precision: bool = false
	## For MOVE: cumulative freehand delta (no snap rounding), used together
	## with start_positions to compute the final snapped position.
	var cumulative_freehand: Vector2 = Vector2.ZERO
	## Original UV positions recorded at drag start.
	## Key: Vector2i(face_index, uv_index), Value: Vector2(original_uv).
	## Used by MOVE, ROTATE, and SCALE to compute snapped final positions
	## from originals instead of accumulating per-frame deltas.
	var start_positions: Dictionary = {}
	## Cumulative angle from drag start (radians, no snap rounding).
	var cumulative_angle: float = 0.0
	## Cumulative scale from drag start (no snap rounding).
	var cumulative_scale: float = 1.0
	var prev_angle: float = 0.0


const MODE_MOVE: int = 0
const MODE_ROTATE: int = 1
const MODE_SCALE: int = 2

const SENSITIVITY_MOVE: float = 1.0
const SENSITIVITY_SCALE: float = 1.0
const PRECISION_MULTIPLIER: float = 0.1


## Begin a new island drag.  Returns a [DragState] the caller should store.
static func begin(
		mesh: GoBuildMesh, sel_faces: Array[int],
		canvas_uv: Vector2, mode: int) -> DragState:
	var ds := DragState.new()
	ds.mode = mode
	ds.start_uv = canvas_uv
	ds.prev_uv = canvas_uv
	ds.pivot = UvPicker.compute_pivot(mesh, sel_faces)
	ds.scale_start = 1.0
	ds.prev_angle = (canvas_uv - ds.pivot).angle()
	if mesh != null:
		ds.snapshot = mesh.take_snapshot()
	ds.cumulative_freehand = Vector2.ZERO
	ds.cumulative_scale = 1.0
	# Record original positions for all modes so we can compute the final
	# state from originals instead of accumulating per-frame rounding errors.
	for fi: int in sel_faces:
		if fi < 0 or fi >= mesh.faces.size():
			continue
		var face: GoBuildFace = mesh.faces[fi]
		for i: int in face.uvs.size():
			ds.start_positions[Vector2i(fi, i)] = face.uvs[i]
	return ds


## Apply one frame of the drag.  Mutates [param mesh] face UVs in-place.
## Returns true if any change was made.
## When [param snap_size] > 0:
##   - Move: snaps the pivot's final position to the UV grid, then applies
##     the same offset to all vertices — preserving shape while landing on
##     grid intersections.
##   - Rotate: snaps angle to 15° increments.
##   - Scale: snaps multiplier to 0.1 increments.
static func apply(
		mesh: GoBuildMesh, sel_faces: Array[int],
		ds: DragState, canvas_uv: Vector2,
		precision: bool = false,
		snap_size: float = 0.0) -> bool:
	if mesh == null or sel_faces.is_empty():
		return false

	ds.precision = precision
	var prec_mult: float = PRECISION_MULTIPLIER if precision else 1.0

	var changed := false
	match ds.mode:
		MODE_MOVE:
			var raw_delta := canvas_uv - ds.prev_uv
			var freehand_delta := raw_delta * SENSITIVITY_MOVE * prec_mult
			if freehand_delta.is_zero_approx():
				return false
			ds.cumulative_freehand += freehand_delta

			if snap_size > 0.0:
				# Snap the pivot's final position to the UV grid.
				# This lands the reference point on a grid intersection while
				# preserving the island shape — every vertex gets the same offset.
				var snapped_pivot: Vector2 = ds.pivot + ds.cumulative_freehand
				snapped_pivot = Vector2(
					round(snapped_pivot.x / snap_size) * snap_size,
					round(snapped_pivot.y / snap_size) * snap_size)
				var snapped_offset: Vector2 = snapped_pivot - ds.pivot
				for handle_key: Vector2i in ds.start_positions:
					var hfi: int = handle_key.x
					var hvi: int = handle_key.y
					if hfi < 0 or hfi >= mesh.faces.size():
						continue
					var orig_pos: Vector2 = ds.start_positions[handle_key]
					mesh.faces[hfi].uvs[hvi] = orig_pos + snapped_offset
			else:
				for handle_key: Vector2i in ds.start_positions:
					var hfi: int = handle_key.x
					var hvi: int = handle_key.y
					if hfi < 0 or hfi >= mesh.faces.size():
						continue
					var orig_pos: Vector2 = ds.start_positions[handle_key]
					mesh.faces[hfi].uvs[hvi] = orig_pos + ds.cumulative_freehand
			changed = true

		MODE_ROTATE:
			var angle_now := (canvas_uv - ds.pivot).angle()
			var raw_delta_angle := angle_now - ds.prev_angle
			if raw_delta_angle > PI:
				raw_delta_angle -= TAU
			elif raw_delta_angle < -PI:
				raw_delta_angle += TAU
			if is_zero_approx(raw_delta_angle):
				return false
			var delta_angle := raw_delta_angle * prec_mult
			ds.cumulative_angle += delta_angle
			if ds.cumulative_angle > TAU:
				ds.cumulative_angle -= TAU
			elif ds.cumulative_angle < -TAU:
				ds.cumulative_angle += TAU

			# Snap cumulative angle to 15° increments.
			var total_angle: float = ds.cumulative_angle
			if snap_size > 0.0:
				var snap_rad: float = deg_to_rad(15.0)
				total_angle = round(total_angle / snap_rad) * snap_rad

			# Apply the total rotation from start to all original positions.
			var cos_a := cos(total_angle)
			var sin_a := sin(total_angle)
			for handle_key: Vector2i in ds.start_positions:
				var hfi: int = handle_key.x
				var hvi: int = handle_key.y
				if hfi < 0 or hfi >= mesh.faces.size():
					continue
				var orig_pos: Vector2 = ds.start_positions[handle_key]
				var rel := orig_pos - ds.pivot
				mesh.faces[hfi].uvs[hvi] = ds.pivot + Vector2(
					rel.x * cos_a - rel.y * sin_a,
					rel.x * sin_a + rel.y * cos_a
				)
			ds.prev_angle = angle_now
			changed = true

		MODE_SCALE:
			var dist_start := (ds.start_uv - ds.pivot).length()
			var dist_now := (canvas_uv - ds.pivot).length()
			if is_zero_approx(dist_start):
				return false
			var scale_ratio := dist_now / dist_start
			if is_equal_approx(scale_ratio, ds.scale_start):
				return false
			var factor := scale_ratio / ds.scale_start
			factor = maxf(factor, 0.01)
			if precision:
				factor = 1.0 + (factor - 1.0) * PRECISION_MULTIPLIER
			ds.cumulative_scale *= factor
			# Snap cumulative scale to 0.1 increments.
			var total_scale: float = ds.cumulative_scale
			if snap_size > 0.0:
				total_scale = round(total_scale * 10.0) / 10.0
				total_scale = maxf(total_scale, 0.1)

			# Apply the total scale from start to all original positions.
			for handle_key: Vector2i in ds.start_positions:
				var hfi: int = handle_key.x
				var hvi: int = handle_key.y
				if hfi < 0 or hfi >= mesh.faces.size():
					continue
				var orig_pos: Vector2 = ds.start_positions[handle_key]
				var rel := orig_pos - ds.pivot
				mesh.faces[hfi].uvs[hvi] = ds.pivot + rel * total_scale
			ds.scale_start = scale_ratio
			changed = true

	if changed:
		ds.prev_uv = canvas_uv
	return changed