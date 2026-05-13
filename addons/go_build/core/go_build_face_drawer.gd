## Face-mode operations drawer for the GoBuild editor panel.
##
## Hosts Extrude, Inset, Subdivide, and Flip Normals buttons.
##
## Drop into any [VBoxContainer] with [method Node.add_child].  After adding:
##   - Call [method GoBuildDrawer.set_plugin] once.
##   - Call [method GoBuildDrawer.set_target] whenever the active
##     [GoBuildMeshInstance] changes.
##   - Call [method GoBuildDrawer.refresh_buttons] on selection-changed events.
@tool
class_name GoBuildFaceDrawer
extends GoBuildDrawer

# Self-preloads — dependency order.
const _FACE_SCRIPT_F           := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MESH_SCRIPT_F           := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _SEL_MGR_SCRIPT_F       := preload("res://addons/go_build/core/selection_manager.gd")
const _MESH_INST_SCRIPT_F     := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _DRAWER_SCRIPT_F        := preload("res://addons/go_build/core/go_build_drawer.gd")
const _PARAM_PREVIEW_SCRIPT_F := preload("res://addons/go_build/core/go_build_param_preview.gd")
const _EXTRUDE_SCRIPT_F       := \
		preload("res://addons/go_build/mesh/operations/extrude_operation.gd")
const _INSET_SCRIPT_F         := \
		preload("res://addons/go_build/mesh/operations/inset_operation.gd")
const _SUBDIVIDE_SCRIPT_F     := \
		preload("res://addons/go_build/mesh/operations/subdivide_operation.gd")
const _FNORMALS_SCRIPT_F      := \
		preload("res://addons/go_build/mesh/operations/flip_normals_operation.gd")

const _EXTRUDE_DEFAULT_DISTANCE: float = 0.5
const _INSET_DEFAULT_AMOUNT: float = 0.1

# Buttons — exposed for tests.
var _extrude_btn:   Button = null
var _inset_btn:     Button = null
var _subdivide_btn: Button = null
var _flip_btn:      Button = null


func _ready() -> void:
	_setup_drawer("Face")

	var grid := GridContainer.new()
	grid.columns = 2
	_content.add_child(grid)

	_extrude_btn = _op_button("Extrude",
		"Extrude selected face(s) by %.2f units along their normal.\n" % _EXTRUDE_DEFAULT_DISTANCE
		+ "Requires Face mode with \u22651 face selected.")
	_extrude_btn.pressed.connect(_on_extrude_pressed)
	grid.add_child(_extrude_btn)
	_register_op(_extrude_btn, _cond_face_any)

	_inset_btn = _op_button("Inset",
		"Inset selected face(s) toward their centroid (0 = none, 1 = collapse).\n"
		+ "Drag to adjust amount. Requires Face mode with \u22651 face selected.")
	_inset_btn.pressed.connect(_on_inset_pressed)
	grid.add_child(_inset_btn)
	_register_op(_inset_btn, _cond_face_any)

	_subdivide_btn = _op_button("Subdivide",
		"Subdivide selected face(s): each N-gon becomes N quads.\n"
		+ "Requires Face mode with \u22651 face selected.")
	_subdivide_btn.pressed.connect(_on_subdivide_pressed)
	grid.add_child(_subdivide_btn)
	_register_op(_subdivide_btn, _cond_face_any)

	_flip_btn = _op_button("Flip Normals",
		"Reverse the outward normal of selected face(s) by flipping winding order.\n"
		+ "Requires Face mode with \u22651 face selected.")
	_flip_btn.pressed.connect(_on_flip_normals_pressed)
	grid.add_child(_flip_btn)
	_register_op(_flip_btn, _cond_face_any)


# ---------------------------------------------------------------------------
# External trigger entry points
# ---------------------------------------------------------------------------

## Equivalent to pressing the Extrude button.
func trigger_extrude() -> void:
	_on_extrude_pressed()


## Equivalent to pressing the Inset button.
func trigger_inset() -> void:
	_on_inset_pressed()


## Equivalent to pressing the Subdivide button.
func trigger_subdivide() -> void:
	_on_subdivide_pressed()


## Equivalent to pressing the Flip Normals button.
func trigger_flip_normals() -> void:
	_on_flip_normals_pressed()


# ---------------------------------------------------------------------------
# Conditions
# ---------------------------------------------------------------------------

func _cond_face_any() -> bool:
	return _target != null \
			and _target.selection.get_mode() == SelectionManager.Mode.FACE \
			and not _target.selection.get_selected_faces().is_empty()


# ---------------------------------------------------------------------------
# Operation handlers
# ---------------------------------------------------------------------------

func _on_extrude_pressed() -> void:
	if _target == null or _plugin == null:
		return
	if _target.selection.get_mode() != SelectionManager.Mode.FACE:
		return
	var sel_faces: Array[int] = _target.selection.get_selected_faces()
	if sel_faces.is_empty():
		return
	var faces_to_extrude: Array[int] = []
	faces_to_extrude.assign(sel_faces)

	var screen_dir: Vector2 = Vector2(1.0, 0.0)
	var sv: SubViewport = EditorInterface.get_editor_viewport_3d(0)
	if sv != null:
		var cam: Camera3D = sv.get_camera_3d()
		if cam != null:
			var gbm: GoBuildMesh = _target.go_build_mesh
			var avg_normal: Vector3 = Vector3.ZERO
			var count: int = 0
			for fi: int in sel_faces:
				if fi < 0 or fi >= gbm.faces.size():
					continue
				var n: Vector3 = gbm.compute_face_normal(gbm.faces[fi])
				avg_normal += n
				count += 1
			if count > 0:
				avg_normal /= count
			var world_normal: Vector3 = _target.global_transform.basis * avg_normal
			var centroid: Vector3 = Vector3.ZERO
			var vcount: int = 0
			for fi: int in sel_faces:
				if fi < 0 or fi >= gbm.faces.size():
					continue
				var face: GoBuildFace = gbm.faces[fi]
				for vi: int in face.vertex_indices:
					centroid += gbm.vertices[vi]
					vcount += 1
			if vcount > 0:
				centroid /= vcount
			var world_pos: Vector3 = _target.global_transform * centroid
			var center_screen: Vector2 = cam.unproject_position(world_pos)
			var tip_screen: Vector2 = cam.unproject_position(world_pos + world_normal)
			var dir: Vector2 = tip_screen - center_screen
			if dir.length() > 1.0:
				screen_dir = dir.normalized()

	var preview := GoBuildParamPreview.new()
	preview.action_name = "Extrude Face"
	preview.param_label = "Distance"
	preview.param_start = _EXTRUDE_DEFAULT_DISTANCE
	preview.param_min   = -100.0
	preview.param_max   = 100.0
	preview.radial      = false
	preview.screen_direction = screen_dir
	preview.apply_fn    = func(p: float) -> void: \
			ExtrudeOperation.apply(_target.go_build_mesh, faces_to_extrude, p)
	_plugin.call("begin_param_preview", preview)


func _on_inset_pressed() -> void:
	if _target == null or _plugin == null:
		return
	if _target.selection.get_mode() != SelectionManager.Mode.FACE:
		return
	var sel_faces: Array[int] = _target.selection.get_selected_faces()
	if sel_faces.is_empty():
		return
	var faces_to_inset: Array[int] = []
	faces_to_inset.assign(sel_faces)

	var preview := GoBuildParamPreview.new()
	preview.action_name = "Inset Face"
	preview.param_label = "Amount"
	preview.param_start = _INSET_DEFAULT_AMOUNT
	preview.param_min   = 0.0
	preview.param_max   = 1.0
	preview.radial      = false
	preview.apply_fn    = func(p: float) -> void: \
			InsetOperation.apply(_target.go_build_mesh, faces_to_inset, p)
	_plugin.call("begin_param_preview", preview)


func _on_subdivide_pressed() -> void:
	if _target == null or _plugin == null:
		return
	if _target.selection.get_mode() != SelectionManager.Mode.FACE:
		return
	var sel_faces: Array[int] = _target.selection.get_selected_faces()
	if sel_faces.is_empty():
		return
	var faces_to_subdivide: Array[int] = []
	faces_to_subdivide.assign(sel_faces)
	_run_op("Subdivide Face",
			func(): SubdivideOperation.apply(_target.go_build_mesh, faces_to_subdivide))


func _on_flip_normals_pressed() -> void:
	if _target == null or _plugin == null:
		return
	if _target.selection.get_mode() != SelectionManager.Mode.FACE:
		return
	var sel_faces: Array[int] = _target.selection.get_selected_faces()
	if sel_faces.is_empty():
		return
	var faces_to_flip: Array[int] = []
	faces_to_flip.assign(sel_faces)
	_run_op("Flip Normals",
			func(): FlipNormalsOperation.apply(_target.go_build_mesh, faces_to_flip),
			false)
