## Surface-mode operations drawer for the GoBuild editor panel.
##
## Manages smooth group assignment (Assign, Flat, Smooth) and Auto Smooth.
##
## Drop into any [VBoxContainer] with [method Node.add_child].  After adding:
##   - Call [method GoBuildDrawer.set_plugin] once.
##   - Call [method GoBuildDrawer.set_target] whenever the active
##     [GoBuildMeshInstance] changes.
##   - Call [method GoBuildDrawer.refresh_buttons] on selection-changed events.
@tool
class_name GoBuildSurfaceDrawer
extends GoBuildDrawer

# Self-preloads — dependency order.
const _SEL_MGR_SCRIPT_S     := preload("res://addons/go_build/core/selection_manager.gd")
const _MESH_INST_SCRIPT_S   := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _DRAWER_SCRIPT_S      := preload("res://addons/go_build/core/go_build_drawer.gd")
const _SMOOTH_GRP_SCRIPT_S  := \
		preload("res://addons/go_build/mesh/operations/smooth_group_operation.gd")
const _AUTO_SMOOTH_SCRIPT_S := \
		preload("res://addons/go_build/mesh/operations/auto_smooth_operation.gd")

# Widgets — exposed for tests.
var _smooth_group_spin:     SpinBox = null
var _assign_smooth_btn:     Button  = null
var _flat_btn:              Button  = null
var _smooth_btn:            Button  = null
var _auto_smooth_angle_spin: SpinBox = null
var _auto_smooth_btn:        Button  = null


func _ready() -> void:
	_setup_drawer("Surface")

	# ── Smooth Group row ─────────────────────────────────────────────────
	var surface_grid := GridContainer.new()
	surface_grid.columns = 2
	_content.add_child(surface_grid)

	var sg_lbl := Label.new()
	sg_lbl.text = "Group:"
	sg_lbl.add_theme_font_size_override("font_size", 11)
	surface_grid.add_child(sg_lbl)

	_smooth_group_spin = SpinBox.new()
	_smooth_group_spin.min_value = 0
	_smooth_group_spin.max_value = 31
	_smooth_group_spin.step = 1
	_smooth_group_spin.rounded = true
	_smooth_group_spin.value = 1
	_smooth_group_spin.tooltip_text = (
		"Smooth group ID to assign.  0 = flat-shaded (no smoothing).\n"
		+ "Faces sharing the same non-zero ID average normals at shared vertices."
	)
	_smooth_group_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	surface_grid.add_child(_smooth_group_spin)

	_assign_smooth_btn = _op_button("Assign",
		"Set selected face(s) to the smooth group shown in the Group spinner.\n"
		+ "Faces in the same non-zero group share averaged normals (smooth shading).\n"
		+ "Requires Face mode with \u22651 face selected.")
	_assign_smooth_btn.pressed.connect(_on_assign_smooth_group_pressed)
	surface_grid.add_child(_assign_smooth_btn)
	_register_op(_assign_smooth_btn, _cond_face_any)

	# Spacer to complete the two-column row.
	surface_grid.add_child(Control.new())

	# ── Quick-set row ────────────────────────────────────────────────────
	var sg_quick_grid := GridContainer.new()
	sg_quick_grid.columns = 2
	_content.add_child(sg_quick_grid)

	_flat_btn = _op_button("Flat",
		"Set selected face(s) to smooth group 0 (flat shading \u2014 each face uses\n"
		+ "its own face normal, no interpolation with neighbours).\n"
		+ "Requires Face mode with \u22651 face selected.")
	_flat_btn.pressed.connect(_on_flat_shading_pressed)
	sg_quick_grid.add_child(_flat_btn)
	_register_op(_flat_btn, _cond_face_any)

	_smooth_btn = _op_button("Smooth",
		"Set selected face(s) to smooth group 1, enabling normal averaging with\n"
		+ "all adjacent faces that also belong to group 1.\n"
		+ "Requires Face mode with \u22651 face selected.")
	_smooth_btn.pressed.connect(_on_smooth_shading_pressed)
	sg_quick_grid.add_child(_smooth_btn)
	_register_op(_smooth_btn, _cond_face_any)

	# ── Auto Smooth row ──────────────────────────────────────────────────
	var as_row := HBoxContainer.new()
	_content.add_child(as_row)

	_auto_smooth_angle_spin = SpinBox.new()
	_auto_smooth_angle_spin.min_value = 1.0
	_auto_smooth_angle_spin.max_value = 180.0
	_auto_smooth_angle_spin.step = 1.0
	_auto_smooth_angle_spin.value = 30.0
	_auto_smooth_angle_spin.suffix = "\u00b0"
	_auto_smooth_angle_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_auto_smooth_angle_spin.tooltip_text = (
		"Angle threshold for Auto Smooth.\n"
		+ "Adjacent faces below this angle share averaged normals;\n"
		+ "wider angles form hard creases.  30\u00b0 matches Blender's default."
	)
	as_row.add_child(_auto_smooth_angle_spin)

	_auto_smooth_btn = _op_button("Auto Smooth",
		"Assign smooth groups to ALL faces based on the dihedral angle threshold.\n"
		+ "No face selection needed \u2014 the entire mesh is processed at once.\n"
		+ "Requires a mesh to be selected.")
	_auto_smooth_btn.pressed.connect(_on_auto_smooth_pressed)
	as_row.add_child(_auto_smooth_btn)
	_register_op(_auto_smooth_btn, _cond_has_mesh)


# ---------------------------------------------------------------------------
# External trigger entry points
# ---------------------------------------------------------------------------

## Equivalent to pressing the Flat button.
func trigger_flat() -> void:
	_on_flat_shading_pressed()


## Equivalent to pressing the Smooth button.
func trigger_smooth() -> void:
	_on_smooth_shading_pressed()


## Equivalent to pressing the Auto Smooth button.
func trigger_auto_smooth() -> void:
	_on_auto_smooth_pressed()


# ---------------------------------------------------------------------------
# Conditions
# ---------------------------------------------------------------------------

func _cond_face_any() -> bool:
	return _target != null \
			and _target.selection.get_mode() == SelectionManager.Mode.FACE \
			and not _target.selection.get_selected_faces().is_empty()


func _cond_has_mesh() -> bool:
	return _target != null and _target.go_build_mesh != null


# ---------------------------------------------------------------------------
# Operation handlers
# ---------------------------------------------------------------------------

func _on_assign_smooth_group_pressed() -> void:
	if _target == null or _plugin == null:
		return
	if _target.selection.get_mode() != SelectionManager.Mode.FACE:
		return
	var sel_faces: Array[int] = _target.selection.get_selected_faces()
	if sel_faces.is_empty():
		return
	var faces: Array[int] = []
	faces.assign(sel_faces)
	var group_id: int = int(_smooth_group_spin.value)
	_run_op(
		"Assign Smooth Group %d" % group_id,
		func(): SmoothGroupOperation.apply(_target.go_build_mesh, faces, group_id),
		false,
	)


func _on_flat_shading_pressed() -> void:
	if _target == null or _plugin == null:
		return
	if _target.selection.get_mode() != SelectionManager.Mode.FACE:
		return
	var sel_faces: Array[int] = _target.selection.get_selected_faces()
	if sel_faces.is_empty():
		return
	var faces: Array[int] = []
	faces.assign(sel_faces)
	_run_op(
		"Flat Shading",
		func(): SmoothGroupOperation.apply(_target.go_build_mesh, faces, 0),
		false,
	)


func _on_smooth_shading_pressed() -> void:
	if _target == null or _plugin == null:
		return
	if _target.selection.get_mode() != SelectionManager.Mode.FACE:
		return
	var sel_faces: Array[int] = _target.selection.get_selected_faces()
	if sel_faces.is_empty():
		return
	var faces: Array[int] = []
	faces.assign(sel_faces)
	_run_op(
		"Smooth Shading",
		func(): SmoothGroupOperation.apply(_target.go_build_mesh, faces, 1),
		false,
	)


func _on_auto_smooth_pressed() -> void:
	if _target == null or _plugin == null or _target.go_build_mesh == null:
		return
	var angle_deg: float = _auto_smooth_angle_spin.value
	_run_op(
		"Auto Smooth",
		func(): AutoSmoothOperation.apply(_target.go_build_mesh, angle_deg),
		false,
	)
