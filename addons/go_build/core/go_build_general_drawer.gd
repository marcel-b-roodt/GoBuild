## General-purpose operations drawer for the GoBuild editor panel.
##
## Hosts the Delete button (mode-aware across Vertex / Edge / Face modes),
## the Debug logging toggle, the Show back-faces toggle, and the Auto UV
## mode selector.
##
## Drop into any [VBoxContainer] with [method Node.add_child].  After adding:
##   - Call [method GoBuildDrawer.set_plugin] once.
##   - Call [method GoBuildDrawer.set_target] whenever the active
##     [GoBuildMeshInstance] changes.
##   - Call [method GoBuildDrawer.refresh_buttons] on selection-changed events.
@tool
class_name GoBuildGeneralDrawer
extends GoBuildDrawer

# Self-preloads — dependency order.
const _SEL_MGR_SCRIPT_G     := preload("res://addons/go_build/core/selection_manager.gd")
const _MESH_INST_SCRIPT_G   := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _DRAWER_SCRIPT_G      := preload("res://addons/go_build/core/go_build_drawer.gd")
const _FACE_SCRIPT_G        := preload("res://addons/go_build/mesh/go_build_face.gd")
const _DELETE_SCRIPT_G      := \
		preload("res://addons/go_build/mesh/operations/delete_operation.gd")
const _DEBUG_SCRIPT_G       := preload("res://addons/go_build/core/go_build_debug.gd")

# Widgets — exposed for tests where useful.
var _delete_btn:    Button    = null
var _cull_check:    CheckBox  = null
var _auto_uv_option: OptionButton = null
var _auto_uv_scale_spin: SpinBox = null
var _auto_uv_u_offset_spin: SpinBox = null
var _auto_uv_v_offset_spin: SpinBox = null
var _auto_uv_seam_rot_spin: SpinBox = null
var _auto_uv_param_rows: VBoxContainer = null


func _ready() -> void:
	_setup_drawer("General", true)

	var general_grid := GridContainer.new()
	general_grid.columns = 2
	_content.add_child(general_grid)

	_delete_btn = _op_button("Delete",
		"Delete selected vertices, edges, or faces (Del / X).\n"
		+ "Orphaned vertices are removed automatically.")
	_delete_btn.pressed.connect(_on_delete_pressed)
	general_grid.add_child(_delete_btn)
	_register_op(_delete_btn, _cond_any_selection)

	# ── Debug logging toggle ─────────────────────────────────────────────
	var dbg_toggle := CheckBox.new()
	dbg_toggle.text = "Debug logging"
	dbg_toggle.button_pressed = GoBuildDebug.enabled
	dbg_toggle.add_theme_font_size_override("font_size", 11)
	dbg_toggle.toggled.connect(func(on: bool) -> void: GoBuildDebug.enabled = on)
	_content.add_child(dbg_toggle)

	# ── Back-face toggle ─────────────────────────────────────────────────
	_cull_check = CheckBox.new()
	_cull_check.text = "Show back-faces"
	_cull_check.button_pressed = false
	_cull_check.add_theme_font_size_override("font_size", 11)
	_cull_check.tooltip_text = (
		"Disable back-face culling on the mesh while editing.\n"
		+ "Useful for spotting flipped normals and inside-out geometry.\n"
		+ "Has no effect outside the editor."
	)
	_cull_check.toggled.connect(_on_cull_check_toggled)
	_content.add_child(_cull_check)

	# ── Auto UV mode selector ────────────────────────────────────────────
	var uv_row := HBoxContainer.new()
	_content.add_child(uv_row)

	var uv_lbl := Label.new()
	uv_lbl.text = "Auto UV:"
	uv_lbl.add_theme_font_size_override("font_size", 11)
	uv_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	uv_row.add_child(uv_lbl)

	_auto_uv_option = OptionButton.new()
	_auto_uv_option.flat = true
	_auto_uv_option.add_item("None",     GoBuildFace.UvMode.NONE)
	_auto_uv_option.add_item("Planar",   GoBuildFace.UvMode.PLANAR)
	_auto_uv_option.add_item("Box",      GoBuildFace.UvMode.BOX)
	_auto_uv_option.add_item("Cylinder", GoBuildFace.UvMode.CYLINDRICAL)
	_auto_uv_option.add_item("Sphere",   GoBuildFace.UvMode.SPHERICAL)
	_auto_uv_option.add_theme_font_size_override("font_size", 11)
	_auto_uv_option.tooltip_text = (
		"Automatically re-project UVs after every operation.\n"
		+ "None     \u2014 disabled; preserves any hand-edited UVs.\n"
		+ "Planar   \u2014 per-face dominant-axis projection (best for simple shapes).\n"
		+ "Box      \u2014 world-space box projection; adjacent faces share UV coords.\n"
		+ "Cylinder \u2014 cylindrical wrap around Y axis; U = angle, V = height.\n"
		+ "Sphere   \u2014 equirectangular (lat/lon) projection; U = longitude, V = latitude."
	)
	_auto_uv_option.item_selected.connect(_on_auto_uv_mode_selected)
	uv_row.add_child(_auto_uv_option)

	# ── Auto UV parameters (visible when mode != NONE) ──────────────────
	_auto_uv_param_rows = VBoxContainer.new()
	_content.add_child(_auto_uv_param_rows)

	var scale_row := HBoxContainer.new()
	_auto_uv_param_rows.add_child(scale_row)
	var scale_lbl := Label.new()
	scale_lbl.text = "Scale:"
	scale_lbl.add_theme_font_size_override("font_size", 11)
	scale_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_row.add_child(scale_lbl)
	_auto_uv_scale_spin = SpinBox.new()
	_auto_uv_scale_spin.min_value = 0.01
	_auto_uv_scale_spin.max_value = 100.0
	_auto_uv_scale_spin.step = 0.1
	_auto_uv_scale_spin.value = 1.0
	_auto_uv_scale_spin.add_theme_font_size_override("font_size", 11)
	_auto_uv_scale_spin.tooltip_text = "UV scale. Higher values tile smaller."
	_auto_uv_scale_spin.value_changed.connect(_on_auto_uv_param_changed)
	scale_row.add_child(_auto_uv_scale_spin)

	var u_row := HBoxContainer.new()
	_auto_uv_param_rows.add_child(u_row)
	var u_lbl := Label.new()
	u_lbl.text = "U Offset:"
	u_lbl.add_theme_font_size_override("font_size", 11)
	u_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	u_row.add_child(u_lbl)
	_auto_uv_u_offset_spin = SpinBox.new()
	_auto_uv_u_offset_spin.min_value = -1.0
	_auto_uv_u_offset_spin.max_value = 1.0
	_auto_uv_u_offset_spin.step = 0.01
	_auto_uv_u_offset_spin.value = 0.0
	_auto_uv_u_offset_spin.add_theme_font_size_override("font_size", 11)
	_auto_uv_u_offset_spin.tooltip_text = "Horizontal UV offset."
	_auto_uv_u_offset_spin.value_changed.connect(_on_auto_uv_param_changed)
	u_row.add_child(_auto_uv_u_offset_spin)

	var v_row := HBoxContainer.new()
	_auto_uv_param_rows.add_child(v_row)
	var v_lbl := Label.new()
	v_lbl.text = "V Offset:"
	v_lbl.add_theme_font_size_override("font_size", 11)
	v_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v_row.add_child(v_lbl)
	_auto_uv_v_offset_spin = SpinBox.new()
	_auto_uv_v_offset_spin.min_value = -1.0
	_auto_uv_v_offset_spin.max_value = 1.0
	_auto_uv_v_offset_spin.step = 0.01
	_auto_uv_v_offset_spin.value = 0.0
	_auto_uv_v_offset_spin.add_theme_font_size_override("font_size", 11)
	_auto_uv_v_offset_spin.tooltip_text = "Vertical UV offset."
	_auto_uv_v_offset_spin.value_changed.connect(_on_auto_uv_param_changed)
	v_row.add_child(_auto_uv_v_offset_spin)

	var seam_row := HBoxContainer.new()
	_auto_uv_param_rows.add_child(seam_row)
	var seam_lbl := Label.new()
	seam_lbl.text = "Seam Rot:"
	seam_lbl.add_theme_font_size_override("font_size", 11)
	seam_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seam_row.add_child(seam_lbl)
	_auto_uv_seam_rot_spin = SpinBox.new()
	_auto_uv_seam_rot_spin.min_value = -180.0
	_auto_uv_seam_rot_spin.max_value = 180.0
	_auto_uv_seam_rot_spin.step = 1.0
	_auto_uv_seam_rot_spin.value = 0.0
	_auto_uv_seam_rot_spin.suffix = "°"
	_auto_uv_seam_rot_spin.add_theme_font_size_override("font_size", 11)
	_auto_uv_seam_rot_spin.tooltip_text = "Seam rotation for Cylinder/Sphere modes (degrees)."
	_auto_uv_seam_rot_spin.value_changed.connect(_on_auto_uv_param_changed)
	seam_row.add_child(_auto_uv_seam_rot_spin)


# ---------------------------------------------------------------------------
# set_target override — syncs per-target UI state
# ---------------------------------------------------------------------------

## Override so the back-face and Auto UV widgets track the new target.
func set_target(target: GoBuildMeshInstance) -> void:
	# Clear the cull override on the old target before switching.
	if _target != null and is_instance_valid(_target):
		_target.set_edit_cull_override(false)
	super.set_target(target)
	if target != null:
		# Apply current checkbox state to the new target immediately.
		if _cull_check != null:
			target.set_edit_cull_override(_cull_check.button_pressed)
		# Sync Auto UV selector to reflect the new target's saved mode.
		if _auto_uv_option != null:
			_auto_uv_option.selected = target.auto_uv_mode
		# Sync Auto UV params and show/hide.
		_sync_auto_uv_params(target)


# ---------------------------------------------------------------------------
# External trigger entry points
# ---------------------------------------------------------------------------

## Equivalent to pressing the Delete button.
func trigger_delete() -> void:
	_on_delete_pressed()


# ---------------------------------------------------------------------------
# Conditions
# ---------------------------------------------------------------------------

func _cond_any_selection() -> bool:
	if _target == null:
		return false
	match _target.selection.get_mode():
		SelectionManager.Mode.VERTEX:
			return not _target.selection.get_selected_vertices().is_empty()
		SelectionManager.Mode.EDGE:
			return not _target.selection.get_selected_edges().is_empty()
		SelectionManager.Mode.FACE:
			return not _target.selection.get_selected_faces().is_empty()
	return false


# ---------------------------------------------------------------------------
# Operation handlers
# ---------------------------------------------------------------------------

func _on_delete_pressed() -> void:
	if _target == null or _plugin == null:
		return
	var mode: SelectionManager.Mode = _target.selection.get_mode()
	var ur: EditorUndoRedoManager = _plugin.get_undo_redo()

	match mode:
		SelectionManager.Mode.FACE:
			var sel: Array[int] = _target.selection.get_selected_faces()
			if sel.is_empty():
				return
			var to_delete: Array[int] = []
			to_delete.assign(sel)
			_target.apply_operation(
				"Delete Face",
				func(): DeleteOperation.apply_faces(_target.go_build_mesh, to_delete),
				ur,
			)

		SelectionManager.Mode.EDGE:
			var sel: Array[int] = _target.selection.get_selected_edges()
			if sel.is_empty():
				return
			var to_delete: Array[int] = []
			to_delete.assign(sel)
			_target.apply_operation(
				"Delete Edge",
				func(): DeleteOperation.apply_edges(_target.go_build_mesh, to_delete),
				ur,
			)

		SelectionManager.Mode.VERTEX:
			var sel: Array[int] = _target.selection.get_selected_vertices()
			if sel.is_empty():
				return
			var to_delete: Array[int] = []
			to_delete.assign(sel)
			_target.apply_operation(
				"Delete Vertex",
				func(): DeleteOperation.apply_vertices(_target.go_build_mesh, to_delete),
				ur,
			)

		_:
			return  # Object mode — nothing to delete here.

	# Clear selection after delete: indices are no longer valid after compaction.
	_target.selection.clear()
	_target.update_gizmos()


func _on_cull_check_toggled(enabled: bool) -> void:
	if _target != null:
		_target.set_edit_cull_override(enabled)


## Write the new Auto UV mode to the active target.
## Triggers an immediate undoable re-projection of all unoverridden faces.
func _on_auto_uv_mode_selected(index: int) -> void:
	if _target == null:
		return
	var new_mode := _auto_uv_option.get_item_id(index) as GoBuildFace.UvMode
	_target.auto_uv_mode = new_mode
	_sync_auto_uv_params_visibility()
	if new_mode != GoBuildFace.UvMode.NONE and _plugin != null:
		# Push a no-op action so _do_operation calls _apply_auto_uv() and
		# re-projects all unoverridden faces with the new mode.
		_run_op("Set Auto UV Mode", func(): pass, false)


## Show or hide the Auto UV parameter spinboxes based on the current mode.
## Also syncs the values from the target (without emitting signals).
func _sync_auto_uv_params(target: GoBuildMeshInstance) -> void:
	_auto_uv_scale_spin.set_value_no_signal(target.auto_uv_scale)
	_auto_uv_u_offset_spin.set_value_no_signal(target.auto_uv_offset.x)
	_auto_uv_v_offset_spin.set_value_no_signal(target.auto_uv_offset.y)
	_auto_uv_seam_rot_spin.set_value_no_signal(rad_to_deg(target.auto_uv_seam_rotation))
	_sync_auto_uv_params_visibility()


func _sync_auto_uv_params_visibility() -> void:
	var show_params: bool = _target != null and _target.auto_uv_mode != GoBuildFace.UvMode.NONE
	_auto_uv_param_rows.visible = show_params
	if show_params:
		var is_seam: bool = _target.auto_uv_mode == GoBuildFace.UvMode.CYLINDRICAL \
				or _target.auto_uv_mode == GoBuildFace.UvMode.SPHERICAL
		_auto_uv_seam_rot_spin.get_parent().visible = is_seam


## Called when any Auto UV parameter spinbox changes.
## Writes the new value to the target and triggers an immediate re-projection.
func _on_auto_uv_param_changed(_value: float) -> void:
	if _target == null or _plugin == null:
		return
	var new_scale: float = _auto_uv_scale_spin.value
	var new_offset: Vector2 = Vector2(
			_auto_uv_u_offset_spin.value,
			_auto_uv_v_offset_spin.value)
	var new_seam_rot: float = deg_to_rad(_auto_uv_seam_rot_spin.value)
	_target.auto_uv_scale = new_scale
	_target.auto_uv_offset = new_offset
	_target.auto_uv_seam_rotation = new_seam_rot
	_run_op("Set Auto UV Params", func(): pass, false)
