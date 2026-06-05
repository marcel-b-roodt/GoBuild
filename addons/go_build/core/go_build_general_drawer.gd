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
const _UNDO_SPIN_SCRIPT_G   := preload("res://addons/go_build/core/go_build_undo_spin_box.gd")

# Widgets — exposed for tests where useful.
var _delete_btn:    Button    = null
var _cull_check:    CheckBox  = null
var _xray_check:    CheckBox  = null
var _auto_uv_option: OptionButton = null
var _auto_uv_scale_spin: GoBuildUndoSpinBox = null
var _auto_uv_u_offset_spin: GoBuildUndoSpinBox = null
var _auto_uv_v_offset_spin: GoBuildUndoSpinBox = null
var _auto_uv_seam_rot_spin: GoBuildUndoSpinBox = null
var _auto_uv_param_rows: VBoxContainer = null

# Auto UV parameter live-edit state.
var _auto_uv_editing: bool = false
var _auto_uv_committing: bool = false
var _auto_uv_snapshot: Dictionary = {}
var _auto_uv_old_scale: float = 1.0
var _auto_uv_old_offset: Vector2 = Vector2.ZERO
var _auto_uv_old_seam_rot: float = 0.0
var _auto_uv_commit_timer: Timer = null


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

	# ── X-Ray mode toggle ────────────────────────────────────────────────
	_xray_check = CheckBox.new()
	_xray_check.text = "X-Ray (show through mesh)"
	_xray_check.button_pressed = true
	_xray_check.add_theme_font_size_override("font_size", 11)
	_xray_check.tooltip_text = (
		"When on, vertex and edge handles are always visible through the mesh.\n"
		+ "When off, unselected handles are hidden behind the mesh surface.\n"
		+ "Selected elements remain visible regardless of this setting."
	)
	_xray_check.toggled.connect(_on_xray_check_toggled)
	_content.add_child(_xray_check)

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
	_auto_uv_scale_spin = GoBuildUndoSpinBox.new()
	_auto_uv_scale_spin.configure(0.01, 100.0, 0.01, 1.0)
	_auto_uv_scale_spin.add_theme_font_size_override("font_size", 11)
	_auto_uv_scale_spin.tooltip_text = "UV scale. Higher values tile smaller."
	_auto_uv_scale_spin.value_changed.connect(_on_auto_uv_param_changed)
	_auto_uv_scale_spin.spin_committed.connect(_on_auto_uv_spin_committed)
	scale_row.add_child(_auto_uv_scale_spin)

	var u_row := HBoxContainer.new()
	_auto_uv_param_rows.add_child(u_row)
	var u_lbl := Label.new()
	u_lbl.text = "U Offset:"
	u_lbl.add_theme_font_size_override("font_size", 11)
	u_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	u_row.add_child(u_lbl)
	_auto_uv_u_offset_spin = GoBuildUndoSpinBox.new()
	_auto_uv_u_offset_spin.configure(-1.0, 1.0, 0.01, 0.0)
	_auto_uv_u_offset_spin.add_theme_font_size_override("font_size", 11)
	_auto_uv_u_offset_spin.tooltip_text = "Horizontal UV offset."
	_auto_uv_u_offset_spin.value_changed.connect(_on_auto_uv_param_changed)
	_auto_uv_u_offset_spin.spin_committed.connect(_on_auto_uv_spin_committed)
	u_row.add_child(_auto_uv_u_offset_spin)

	var v_row := HBoxContainer.new()
	_auto_uv_param_rows.add_child(v_row)
	var v_lbl := Label.new()
	v_lbl.text = "V Offset:"
	v_lbl.add_theme_font_size_override("font_size", 11)
	v_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v_row.add_child(v_lbl)
	_auto_uv_v_offset_spin = GoBuildUndoSpinBox.new()
	_auto_uv_v_offset_spin.configure(-1.0, 1.0, 0.01, 0.0)
	_auto_uv_v_offset_spin.add_theme_font_size_override("font_size", 11)
	_auto_uv_v_offset_spin.tooltip_text = "Vertical UV offset."
	_auto_uv_v_offset_spin.value_changed.connect(_on_auto_uv_param_changed)
	_auto_uv_v_offset_spin.spin_committed.connect(_on_auto_uv_spin_committed)
	v_row.add_child(_auto_uv_v_offset_spin)

	var seam_row := HBoxContainer.new()
	_auto_uv_param_rows.add_child(seam_row)
	var seam_lbl := Label.new()
	seam_lbl.text = "Seam Rot:"
	seam_lbl.add_theme_font_size_override("font_size", 11)
	seam_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seam_row.add_child(seam_lbl)
	_auto_uv_seam_rot_spin = GoBuildUndoSpinBox.new()
	_auto_uv_seam_rot_spin.configure(-180.0, 180.0, 1.0, 0.0, "°")
	_auto_uv_seam_rot_spin.add_theme_font_size_override("font_size", 11)
	_auto_uv_seam_rot_spin.tooltip_text = "Seam rotation for Cylinder/Sphere modes (degrees)."
	_auto_uv_seam_rot_spin.value_changed.connect(_on_auto_uv_param_changed)
	_auto_uv_seam_rot_spin.spin_committed.connect(_on_auto_uv_spin_committed)
	seam_row.add_child(_auto_uv_seam_rot_spin)

	# Safety timer: if spin_committed is not emitted (unlikely edge case),
	# commit after 2 seconds of inactivity as a fallback.
	_auto_uv_commit_timer = Timer.new()
	_auto_uv_commit_timer.one_shot = true
	_auto_uv_commit_timer.wait_time = 2.0
	_auto_uv_commit_timer.timeout.connect(commit_auto_uv_params)
	add_child(_auto_uv_commit_timer)


# ---------------------------------------------------------------------------
# set_target override — syncs per-target UI state
# ---------------------------------------------------------------------------

## Override so the back-face and Auto UV widgets track the new target.
## Commits any active Auto UV param preview before switching.
func set_target(target: GoBuildMeshInstance) -> void:
	if _auto_uv_editing:
		commit_auto_uv_params()
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


func _on_xray_check_toggled(enabled: bool) -> void:
	if _plugin != null and _plugin.has_method("set_xray_mode"):
		_plugin.set_xray_mode(enabled)


## Write the new Auto UV mode to the active target.
## Commits any active param preview first, then triggers an immediate
## undoable re-projection of all unoverridden faces.
func _on_auto_uv_mode_selected(index: int) -> void:
	if _target == null:
		return
	if _auto_uv_editing:
		commit_auto_uv_params()
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
## Enters preview mode on first change, then live-updates without creating
## undo entries on every tick.  Undo is created once when the user commits
## (focus leaves the spinboxes or the drawer switches targets).
func _on_auto_uv_param_changed(_value: float) -> void:
	if _target == null or _plugin == null or _auto_uv_committing:
		return
	if not _auto_uv_editing:
		_auto_uv_editing = true
		_auto_uv_snapshot = _target.go_build_mesh.take_snapshot()
		_auto_uv_old_scale = _target.auto_uv_scale
		_auto_uv_old_offset = _target.auto_uv_offset
		_auto_uv_old_seam_rot = _target.auto_uv_seam_rotation
		_target.begin_preview()
	var new_scale: float = _auto_uv_scale_spin.value
	var new_offset: Vector2 = Vector2(
			_auto_uv_u_offset_spin.value,
			_auto_uv_v_offset_spin.value)
	var new_seam_rot: float = deg_to_rad(_auto_uv_seam_rot_spin.value)
	_target.auto_uv_scale = new_scale
	_target.auto_uv_offset = new_offset
	_target.auto_uv_seam_rotation = new_seam_rot
	_target.go_build_mesh.restore_snapshot(_auto_uv_snapshot)
	_target._apply_auto_uv()
	_target.bake_preview()
	# Restart the auto-commit timer — if the user stops adjusting for 0.8s,
	# the preview is committed as a single undoable action.
	_auto_uv_commit_timer.start()


## Called when any GoBuildUndoSpinBox emits spin_committed (mouse-up after drag
## or Enter in the LineEdit).  Commits the param preview immediately.
func _on_auto_uv_spin_committed(_value: float) -> void:
	if _auto_uv_editing:
		_auto_uv_commit_timer.stop()
		commit_auto_uv_params()


## Commit the Auto UV parameter preview as a single undoable action.
## The undo path restores both the mesh snapshot and the old param values,
## then re-projects UVs and bakes.  The do path re-applies the new params,
## re-projects, and bakes.  Both paths sync the sidebar spinboxes.
func commit_auto_uv_params() -> void:
	if not _auto_uv_editing or _target == null or _plugin == null:
		_auto_uv_commit_timer.stop()
		return
	_auto_uv_editing = false
	_auto_uv_committing = true
	_auto_uv_commit_timer.stop()
	_target.end_preview()
	# Restore pre-edit mesh state from the snapshot taken at the start of editing.
	_target.go_build_mesh.restore_snapshot(_auto_uv_snapshot)
	# We already have the pre-edit snapshot — use it directly.  No need to
	# re-apply old params and bake first; the do method will apply final params.
	var snapshot: Dictionary = _auto_uv_snapshot
	_auto_uv_snapshot = {}
	var old_scale: float = _auto_uv_old_scale
	var old_offset: Vector2 = _auto_uv_old_offset
	var old_seam_rot: float = _auto_uv_old_seam_rot
	var final_scale: float = _auto_uv_scale_spin.value
	var final_offset: Vector2 = Vector2(
			_auto_uv_u_offset_spin.value,
			_auto_uv_v_offset_spin.value)
	var final_seam_rot: float = deg_to_rad(_auto_uv_seam_rot_spin.value)
	var target_ref: GoBuildMeshInstance = _target
	var ur: EditorUndoRedoManager = _plugin.get_undo_redo()
	ur.create_action("Set Auto UV Params")
	# Tell Godot's undo system about the @export property changes so they are
	# tracked correctly and undo/redo restores them in the Inspector too.
	ur.add_do_property(target_ref, "auto_uv_scale", final_scale)
	ur.add_do_property(target_ref, "auto_uv_offset", final_offset)
	ur.add_do_property(target_ref, "auto_uv_seam_rotation", final_seam_rot)
	ur.add_undo_property(target_ref, "auto_uv_scale", old_scale)
	ur.add_undo_property(target_ref, "auto_uv_offset", old_offset)
	ur.add_undo_property(target_ref, "auto_uv_seam_rotation", old_seam_rot)
	ur.add_do_method(self, "_auto_uv_do_apply",
			target_ref, snapshot)
	ur.add_undo_method(self, "_auto_uv_undo_apply",
			target_ref, snapshot)
	ur.commit_action()
	_auto_uv_committing = false


## Do-path: restore pre-edit mesh, re-apply UVs with new params, and bake.
## [param target_ref] is captured at commit time so undo/redo always targets the
## correct node even if the drawer has since switched to a different instance.
## Properties (auto_uv_scale, auto_uv_offset, auto_uv_seam_rotation) are already
## set by EditorUndoRedoManager via add_do_property before this method runs.
func _auto_uv_do_apply(
		target_ref: GoBuildMeshInstance,
		snapshot: Dictionary,
) -> void:
	if target_ref == null or not is_instance_valid(target_ref):
		return
	target_ref.go_build_mesh.restore_snapshot(snapshot)
	if target_ref.auto_uv_mode != GoBuildFace.UvMode.NONE:
		target_ref._apply_auto_uv()
	target_ref.bake()
	target_ref.update_gizmos()
	if target_ref == _target:
		_sync_auto_uv_params(target_ref)


## Undo-path: restore pre-edit mesh, re-apply UVs with old params, and bake.
## Properties are already restored by add_undo_property before this method runs.
func _auto_uv_undo_apply(
		target_ref: GoBuildMeshInstance,
		snapshot: Dictionary,
) -> void:
	if target_ref == null or not is_instance_valid(target_ref):
		return
	target_ref.go_build_mesh.restore_snapshot(snapshot)
	if target_ref.auto_uv_mode != GoBuildFace.UvMode.NONE:
		target_ref._apply_auto_uv()
	target_ref.bake()
	target_ref.update_gizmos()
	if target_ref == _target:
		_sync_auto_uv_params(target_ref)


## Cancel the Auto UV parameter preview and restore the pre-edit state.
func cancel_auto_uv_params() -> void:
	if not _auto_uv_editing or _target == null:
		return
	_auto_uv_editing = false
	_target.end_preview()
	_target.go_build_mesh.restore_snapshot(_auto_uv_snapshot)
	_target.auto_uv_scale = _auto_uv_old_scale
	_target.auto_uv_offset = _auto_uv_old_offset
	_target.auto_uv_seam_rotation = _auto_uv_old_seam_rot
	_target._apply_auto_uv()
	_target.bake()
	_auto_uv_snapshot = {}
	_sync_auto_uv_params(_target)
