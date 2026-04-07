## GoBuild EditorPlugin entry point.
##
## Registers the GoBuildMeshInstance custom type, adds the side-panel dock,
## and wires editor selection so the panel updates when a mesh is selected.
## All viewport mouse input (handle picking, drag, box-select, context menu)
## is delegated to [SelectionInputController].
##
## This script MUST remain GDScript — the plugin must work in every Godot 4
@tool
extends EditorPlugin

# ---------------------------------------------------------------------------
# Preloads — ORDER MATTERS.
# Each script is listed after the scripts it depends on so that class names
# are registered in the global registry before they are referenced by a later
# script in the chain.
# ---------------------------------------------------------------------------
const _DEBUG_SCRIPT         := preload("res://addons/go_build/core/go_build_debug.gd")
const _SEL_MGR_SCRIPT       := preload("res://addons/go_build/core/selection_manager.gd")
const _MESH_INSTANCE_SCRIPT := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _GIZMO_PLUGIN_SCRIPT  := preload("res://addons/go_build/core/go_build_gizmo_plugin.gd")
const _PICKING_HELPER_SCRIPT := preload("res://addons/go_build/core/picking_helper.gd")
const _PANEL_SCRIPT         := preload("res://addons/go_build/core/go_build_panel.gd")
const _CONTROLLER_SCRIPT    := preload(
		"res://addons/go_build/core/selection_input_controller.gd")
const _ICON                 := preload("res://icon.svg")

## EditorSettings keys for the four mode-switch shortcuts.
const _SHORTCUT_OBJECT := "gobuild/shortcuts/object_mode"
const _SHORTCUT_VERTEX := "gobuild/shortcuts/vertex_mode"
const _SHORTCUT_EDGE   := "gobuild/shortcuts/edge_mode"
const _SHORTCUT_FACE   := "gobuild/shortcuts/face_mode"

## Snap step presets shown in the toolbar picker.
## Index 0 is the "Editor" fallback (reads Godot editor grid step).
## All other values are in metres.
const _SNAP_PRESETS: Array[float] = [-1.0, 0.1, 0.25, 0.5, 1.0, 2.0]
const _SNAP_LABELS:  Array[String] = [
	"Editor", "0.1 m", "0.25 m", "0.5 m", "1 m", "2 m"
]

## Rotation snap presets (degrees).
const _ROT_SNAP_PRESETS: Array[float] = [5.0, 15.0, 30.0, 45.0, 60.0, 90.0]
const _ROT_SNAP_LABELS:  Array[String] = ["5", "15", "30", "45", "60", "90"]
const _ROT_SNAP_DEFAULT_IDX: int = 1   # 15

## Scale snap presets (ratio step).
const _SCALE_SNAP_PRESETS: Array[float] = [0.1, 0.2, 0.5, 1.0]
const _SCALE_SNAP_LABELS:  Array[String] = ["0.1", "0.2", "0.5", "1.0"]
const _SCALE_SNAP_DEFAULT_IDX: int = 0   # 0.1

var _panel: GoBuildPanel                         = null
var _edited_node: GoBuildMeshInstance            = null
var _gizmo_plugin: GoBuildGizmoPlugin            = null
var _input_controller: SelectionInputController  = null
var _toolbar: HBoxContainer                      = null
var _snap_btn: OptionButton                      = null
var _rot_snap_btn: OptionButton                  = null
var _scale_snap_btn: OptionButton                = null

# Mode-switch shortcuts (initialised in _enter_tree via EditorSettings).
var _shortcut_object: Shortcut
var _shortcut_vertex: Shortcut
var _shortcut_edge:   Shortcut
var _shortcut_face:   Shortcut


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _enter_tree() -> void:
	add_custom_type(
		"GoBuildMeshInstance",
		"MeshInstance3D",
		_MESH_INSTANCE_SCRIPT,
		_ICON,
	)
	_init_shortcuts()

	_panel = _PANEL_SCRIPT.new()
	add_control_to_dock(DOCK_SLOT_LEFT_BL, _panel)
	_panel.set_plugin(self)

	_gizmo_plugin = _GIZMO_PLUGIN_SCRIPT.new()
	_gizmo_plugin.setup(self)
	add_node_3d_gizmo_plugin(_gizmo_plugin)

	_input_controller = _CONTROLLER_SCRIPT.new()
	_input_controller.setup(_gizmo_plugin, _panel, self)

	_build_toolbar()


func _build_toolbar() -> void:
	_toolbar = HBoxContainer.new()
	_toolbar.add_child(VSeparator.new())

	var lbl := Label.new()
	lbl.text = "Snap:"
	_toolbar.add_child(lbl)

	_snap_btn = OptionButton.new()
	_snap_btn.flat = true
	for label: String in _SNAP_LABELS:
		_snap_btn.add_item(label)
	_snap_btn.select(0)  # default: "Editor"
	_snap_btn.item_selected.connect(_on_snap_selected)
	_toolbar.add_child(_snap_btn)

	_toolbar.add_child(VSeparator.new())

	var rot_lbl := Label.new()
	rot_lbl.text = "Rot:"
	_toolbar.add_child(rot_lbl)

	_rot_snap_btn = OptionButton.new()
	_rot_snap_btn.flat = true
	for label: String in _ROT_SNAP_LABELS:
		_rot_snap_btn.add_item(label)
	_rot_snap_btn.select(_ROT_SNAP_DEFAULT_IDX)
	_rot_snap_btn.item_selected.connect(_on_rot_snap_selected)
	_toolbar.add_child(_rot_snap_btn)

	_toolbar.add_child(VSeparator.new())

	var scale_lbl := Label.new()
	scale_lbl.text = "Scale:"
	_toolbar.add_child(scale_lbl)

	_scale_snap_btn = OptionButton.new()
	_scale_snap_btn.flat = true
	for label: String in _SCALE_SNAP_LABELS:
		_scale_snap_btn.add_item(label)
	_scale_snap_btn.select(_SCALE_SNAP_DEFAULT_IDX)
	_scale_snap_btn.item_selected.connect(_on_scale_snap_selected)
	_toolbar.add_child(_scale_snap_btn)

	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _toolbar)


func _exit_tree() -> void:
	remove_custom_type("GoBuildMeshInstance")

	if _toolbar:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _toolbar)
		_toolbar.queue_free()
		_toolbar = null
		_snap_btn = null
		_rot_snap_btn = null
		_scale_snap_btn = null

	if _panel:
		remove_control_from_docks(_panel)
		_panel.queue_free()
		_panel = null

	_disconnect_node_signals()
	_edited_node = null

	if _gizmo_plugin:
		remove_node_3d_gizmo_plugin(_gizmo_plugin)
		_gizmo_plugin = null

	_input_controller = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_on_editor_focus_regained()


func _on_editor_focus_regained() -> void:
	if _edited_node != null and not is_instance_valid(_edited_node):
		GoBuildDebug.log("[GoBuild] PLUGIN._on_editor_focus_regained  edited_node gone — clearing")
		_disconnect_node_signals()
		_edited_node = null
		if _panel:
			_panel.set_target(null)

	if _edited_node == null:
		return

	GoBuildDebug.log("[GoBuild] PLUGIN._on_editor_focus_regained  node=%s" % _edited_node.name)

	if _input_controller != null:
		_input_controller.cancel_drag(_edited_node)
		_input_controller.cancel_box_select(_edited_node)

	if _gizmo_plugin:
		remove_node_3d_gizmo_plugin(_gizmo_plugin)
		add_node_3d_gizmo_plugin(_gizmo_plugin)

	_force_gizmo_redraw_deferred(_edited_node)


# ---------------------------------------------------------------------------
# Selection / editing
# ---------------------------------------------------------------------------

func _handles(object: Object) -> bool:
	return object is GoBuildMeshInstance


func _edit(object: Object) -> void:
	# Clear the back-face override on the previously edited node before switching.
	if _edited_node != null and is_instance_valid(_edited_node):
		_edited_node.set_edit_cull_override(false)
	_disconnect_node_signals()

	_edited_node = object as GoBuildMeshInstance
	GoBuildDebug.log("[GoBuild] PLUGIN._edit  node=%s  is_null=%s" \
			% [str(object), str(_edited_node == null)])

	if _edited_node != null:
		_edited_node.selection.selection_changed.connect(_on_selection_changed)
		_edited_node.selection.mode_changed.connect(_on_mode_changed)
		_edited_node.tree_exiting.connect(_on_edited_node_removed)
		_force_gizmo_redraw_deferred(_edited_node)
		if _gizmo_plugin:
			remove_node_3d_gizmo_plugin(_gizmo_plugin)
			add_node_3d_gizmo_plugin(_gizmo_plugin)
		_edited_node.update_gizmos()
		_send_editor_tool_shortcut(KEY_Q)

	if _panel:
		_panel.set_target(_edited_node)


func _force_gizmo_redraw_deferred(node: Node3D) -> void:
	await get_tree().process_frame
	if not is_instance_valid(node) or node != _edited_node:
		return
	if _gizmo_plugin == null:
		return
	var has_gizmo: bool = _gizmo_plugin.has_our_gizmo(node)
	GoBuildDebug.log("[GoBuild] PLUGIN._force_gizmo_redraw_deferred  has_gizmo=%s" \
			% str(has_gizmo))
	if has_gizmo:
		node.update_gizmos()
		return
	GoBuildDebug.log("[GoBuild] PLUGIN._force_gizmo_redraw_deferred  no gizmo — force-creating")
	var gizmo: EditorNode3DGizmo = _gizmo_plugin._create_gizmo(node)
	if gizmo == null:
		return
	gizmo.set("_manual_plugin_ref", _gizmo_plugin)
	node.add_gizmo(gizmo)


func _make_visible(visible: bool) -> void:
	if not visible:
		if _input_controller != null and _edited_node != null:
			_input_controller.clear_hover(_edited_node)
		if _edited_node != null:
			_edited_node.set_edit_cull_override(false)
		_disconnect_node_signals()
		_edited_node = null
		if _panel:
			_panel.set_target(null)
		_send_editor_tool_shortcut(KEY_W)


# ---------------------------------------------------------------------------
# Viewport input — keyboard shortcuts
# ---------------------------------------------------------------------------

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if _edited_node == null:
		return 0
	var key_result: int = _handle_keyboard(event)
	if key_result != 0:
		return key_result
	if _input_controller == null:
		return 0
	return _input_controller.process_input(_edited_node, camera, event)


## Draw the box-select rect and the mode / modifier hint label.
func _forward_3d_draw_over_viewport(overlay: Control) -> void:
	if _input_controller != null:
		_input_controller.draw_overlay(overlay)
	_draw_mode_hint(overlay)


func _handle_keyboard(event: InputEvent) -> int:
	if not (event is InputEventKey):
		return 0
	var key := event as InputEventKey
	if key.echo:
		return 0
	# Refresh the overlay hint on any Shift / Ctrl / Alt state change.
	match key.keycode:
		KEY_SHIFT, KEY_CTRL, KEY_ALT:
			update_overlays()
			return 0
	if not key.pressed:
		return 0
	if key.keycode == KEY_ESCAPE:
		if _input_controller != null and \
				(_input_controller.has_active_drag() or _input_controller.has_active_press()):
			_input_controller.cancel_drag(_edited_node)
			if _edited_node:
				_edited_node.update_gizmos()
			return 1
	return _handle_keyboard_shortcut(key)


func _handle_keyboard_shortcut(key: InputEventKey) -> int:
	# Transform-mode keys and delete are handled inline; mode-switch shortcuts
	# go through the shared _set_mode / switch_mode path below.
	var handled: int = _handle_action_key(key.keycode)
	if handled != -1:
		return handled
	if _shortcut_object.matches_event(key):
		switch_mode(SelectionManager.Mode.OBJECT)
	elif _shortcut_vertex.matches_event(key):
		switch_mode(SelectionManager.Mode.VERTEX)
	elif _shortcut_edge.matches_event(key):
		switch_mode(SelectionManager.Mode.EDGE)
	elif _shortcut_face.matches_event(key):
		switch_mode(SelectionManager.Mode.FACE)
	else:
		return 0
	return 1


## Handle single-key action shortcuts (W/E/R transform modes, Delete/X).
## Returns 1 if consumed, 0 if passed through, -1 if not matched.
func _handle_action_key(keycode: Key) -> int:
	match keycode:
		KEY_W: return _set_transform_mode(GoBuildGizmoPlugin.TransformMode.TRANSLATE)
		KEY_E: return _set_transform_mode(GoBuildGizmoPlugin.TransformMode.ROTATE)
		KEY_R: return _set_transform_mode(GoBuildGizmoPlugin.TransformMode.SCALE)
		KEY_DELETE, KEY_X:
			# Only intercept Delete / X in sub-element modes.  In Object mode
			# the event passes through so Godot can delete the selected node.
			if _edited_node != null and _panel != null \
					and _edited_node.selection.get_mode() != SelectionManager.Mode.OBJECT:
				_panel.trigger_delete()
				return 1
			return 0
	return -1  # Not a recognised action key.


func _set_transform_mode(mode: GoBuildGizmoPlugin.TransformMode) -> int:
	if _gizmo_plugin == null:
		return 0
	if _input_controller != null:
		_input_controller.cancel_drag(_edited_node)
		_input_controller.clear_hover(_edited_node)
	_gizmo_plugin.transform_mode = mode
	if _edited_node:
		_edited_node.update_gizmos()
	update_overlays()
	return 1


# ---------------------------------------------------------------------------
# Shortcut initialisation
# ---------------------------------------------------------------------------

func _init_shortcuts() -> void:
	var es := EditorInterface.get_editor_settings()
	_shortcut_object = _require_shortcut(es, _SHORTCUT_OBJECT, KEY_1)
	_shortcut_vertex = _require_shortcut(es, _SHORTCUT_VERTEX, KEY_2)
	_shortcut_edge   = _require_shortcut(es, _SHORTCUT_EDGE,   KEY_3)
	_shortcut_face   = _require_shortcut(es, _SHORTCUT_FACE,   KEY_4)


func _require_shortcut(es: EditorSettings, setting: String, default_key: Key) -> Shortcut:
	if es.has_setting(setting):
		var existing: Variant = es.get_setting(setting)
		if existing is Shortcut:
			return existing as Shortcut
	var ev := InputEventKey.new()
	ev.keycode = default_key
	var sc := Shortcut.new()
	sc.events = [ev]
	es.set_setting(setting, sc)
	es.set_initial_value(setting, sc, false)
	return sc


func switch_mode(mode: SelectionManager.Mode) -> void:
	_set_mode(mode)


func _set_mode(mode: SelectionManager.Mode) -> void:
	if _edited_node == null:
		return
	GoBuildDebug.log("[GoBuild] PLUGIN._set_mode  mode=%d  node=%s" % [mode, _edited_node.name])
	_edited_node.selection.set_mode(mode)
	_edited_node.update_gizmos()


# ---------------------------------------------------------------------------
# Overlay hint
# ---------------------------------------------------------------------------

func _draw_mode_hint(overlay: Control) -> void:
	if _edited_node == null or _gizmo_plugin == null:
		return
	var hint: String = _build_overlay_hint()
	if hint.is_empty():
		return
	var font: Font = ThemeDB.fallback_font
	var fsize: int = 12
	var m: float   = 8.0
	var pos := Vector2(m, overlay.size.y - m)
	overlay.draw_string(font, pos + Vector2(1.0, 1.0), hint,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.0, 0.0, 0.0, 0.55))
	overlay.draw_string(font, pos, hint,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.9, 0.9, 0.9, 0.85))


func _build_overlay_hint() -> String:
	if _edited_node == null or _gizmo_plugin == null:
		return ""
	var mode: SelectionManager.Mode = _edited_node.selection.get_mode()
	if mode == SelectionManager.Mode.OBJECT:
		return ""
	var shift: bool = Input.is_key_pressed(KEY_SHIFT)
	var ctrl:  bool = Input.is_key_pressed(KEY_CTRL)
	var tmode := _gizmo_plugin.transform_mode

	var mode_label: String
	match mode:
		SelectionManager.Mode.VERTEX: mode_label = "Vertex"
		SelectionManager.Mode.EDGE:   mode_label = "Edge"
		_:                            mode_label = "Face"

	# Determine the active operation name given current gizmo + modifiers.
	var op: String
	match tmode:
		GoBuildGizmoPlugin.TransformMode.ROTATE:
			op = "Rotate"
		GoBuildGizmoPlugin.TransformMode.SCALE:
			if shift and mode == SelectionManager.Mode.FACE:
				op = "■ INSET"
			elif ctrl:
				op = "■ SNAP"
			else:
				op = "Scale    Shift+Centre: Uniform"
		_:  # TRANSLATE
			if shift:
				match mode:
					SelectionManager.Mode.FACE: op = "■ EXTRUDE"
					SelectionManager.Mode.EDGE: op = "■ EXTRUDE EDGE"
					_:                          op = "Move"
			elif ctrl:
				op = "■ SNAP"
			else:
				op = "Move"

	# Build available-shortcut hints when no overriding modifier is held.
	var hints: Array[String] = []
	if not shift and not ctrl:
		match tmode:
			GoBuildGizmoPlugin.TransformMode.TRANSLATE:
				if mode == SelectionManager.Mode.FACE:
					hints.append("Shift: Extrude")
				elif mode == SelectionManager.Mode.EDGE:
					hints.append("Shift: Extrude Edge")
				hints.append("Ctrl: Snap")
				hints.append("V: Vertex Snap")
			GoBuildGizmoPlugin.TransformMode.SCALE:
				if mode == SelectionManager.Mode.FACE:
					hints.append("Shift: Inset")
				hints.append("Ctrl: Snap")
	elif shift:
		hints.append("+Ctrl: Snap")

	if hints.is_empty():
		return "%s  ·  %s" % [mode_label, op]
	return "%s  ·  %s    %s" % [mode_label, op, "  ".join(hints)]


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_selection_changed() -> void:
	if _edited_node:
		_edited_node.update_gizmos()
	update_overlays()


func _on_snap_selected(index: int) -> void:
	if _gizmo_plugin == null:
		return
	_gizmo_plugin.snap_step_override = _SNAP_PRESETS[index]


func _on_rot_snap_selected(index: int) -> void:
	if _gizmo_plugin == null:
		return
	_gizmo_plugin.rot_snap_override = _ROT_SNAP_PRESETS[index]


func _on_scale_snap_selected(index: int) -> void:
	if _gizmo_plugin == null:
		return
	_gizmo_plugin.scale_snap_override = _SCALE_SNAP_PRESETS[index]


func _on_mode_changed(mode: SelectionManager.Mode) -> void:
	GoBuildDebug.log("[GoBuild] PLUGIN._on_mode_changed  mode=%d  edited_null=%s" \
			% [mode, str(_edited_node == null)])
	if _input_controller != null:
		_input_controller.cancel_drag(_edited_node)
		_input_controller.clear_hover(_edited_node)
		_input_controller.cancel_box_select(_edited_node)
	_send_editor_tool_shortcut(KEY_Q)


func _on_edited_node_removed() -> void:
	if _input_controller != null:
		_input_controller.cancel_drag(null)
		_input_controller.cancel_box_select(null)
	_edited_node = null
	if _panel:
		_panel.set_target(null)
	_send_editor_tool_shortcut(KEY_W)
	update_overlays()


func _disconnect_node_signals() -> void:
	if _edited_node == null:
		return
	if _edited_node.selection.selection_changed.is_connected(_on_selection_changed):
		_edited_node.selection.selection_changed.disconnect(_on_selection_changed)
	if _edited_node.selection.mode_changed.is_connected(_on_mode_changed):
		_edited_node.selection.mode_changed.disconnect(_on_mode_changed)
	if _edited_node.tree_exiting.is_connected(_on_edited_node_removed):
		_edited_node.tree_exiting.disconnect(_on_edited_node_removed)


# ---------------------------------------------------------------------------
# Editor tool shortcut helper
# ---------------------------------------------------------------------------

func _send_editor_tool_shortcut(keycode: Key) -> void:
	call_deferred("_do_send_editor_tool_shortcut", keycode)


func _do_send_editor_tool_shortcut(keycode: Key) -> void:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		return
	var sv: SubViewport = EditorInterface.get_editor_viewport_3d(0)
	if sv != null:
		var parent: Node = sv.get_parent()
		if parent is Control:
			(parent as Control).grab_focus()
	var ev_down := InputEventKey.new()
	ev_down.keycode          = keycode
	ev_down.physical_keycode = keycode
	ev_down.pressed          = true
	ev_down.echo             = false
	Input.parse_input_event(ev_down)
	var ev_up := InputEventKey.new()
	ev_up.keycode          = keycode
	ev_up.physical_keycode = keycode
	ev_up.pressed          = false
	ev_up.echo             = false
	Input.parse_input_event(ev_up)

