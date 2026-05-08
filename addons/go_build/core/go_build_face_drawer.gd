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

	var preview := GoBuildParamPreview.new()
	preview.action_name = "Extrude Face"
	preview.param_label = "Distance"
	preview.param_start = _EXTRUDE_DEFAULT_DISTANCE
	preview.param_min   = -100.0
	preview.param_max   = 100.0
	preview.radial      = false
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
