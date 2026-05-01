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


## Mode constants matching [GoBuildUvCanvas.UvTransformMode].
const MODE_MOVE: int = 0
const MODE_ROTATE: int = 1
const MODE_SCALE: int = 2


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
	if mesh != null:
		ds.snapshot = mesh.take_snapshot()
	return ds


## Apply one frame of the drag.  Mutates [param mesh] face UVs in-place.
## Returns true if any change was made.
static func apply(
		mesh: GoBuildMesh, sel_faces: Array[int],
		ds: DragState, canvas_uv: Vector2) -> bool:
	if mesh == null or sel_faces.is_empty():
		return false

	var changed := false
	match ds.mode:
		MODE_MOVE:
			var delta := canvas_uv - ds.prev_uv
			if delta.is_zero_approx():
				return false
			for fi: int in sel_faces:
				if fi < 0 or fi >= mesh.faces.size():
					continue
				var face: GoBuildFace = mesh.faces[fi]
				for i: int in face.uvs.size():
					face.uvs[i] = face.uvs[i] + delta
			changed = true

		MODE_ROTATE:
			var angle_start := (ds.start_uv - ds.pivot).angle()
			var angle_now := (canvas_uv - ds.pivot).angle()
			var delta_angle := angle_now - angle_start
			if is_zero_approx(delta_angle):
				return false
			var cos_a := cos(delta_angle)
			var sin_a := sin(delta_angle)
			for fi: int in sel_faces:
				if fi < 0 or fi >= mesh.faces.size():
					continue
				var face: GoBuildFace = mesh.faces[fi]
				for i: int in face.uvs.size():
					var rel := face.uvs[i] - ds.pivot
					face.uvs[i] = ds.pivot + Vector2(
						rel.x * cos_a - rel.y * sin_a,
						rel.x * sin_a + rel.y * cos_a
					)
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
			ds.scale_start = scale_ratio
			for fi: int in sel_faces:
				if fi < 0 or fi >= mesh.faces.size():
					continue
				var face: GoBuildFace = mesh.faces[fi]
				for i: int in face.uvs.size():
					var rel := face.uvs[i] - ds.pivot
					face.uvs[i] = ds.pivot + rel * factor
			changed = true

	if changed:
		ds.prev_uv = canvas_uv
	return changed