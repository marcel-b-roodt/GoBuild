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
const _FACE_SCRIPT          := preload("res://addons/go_build/mesh/go_build_face.gd")
const _PALETTE_SCRIPT       := preload("res://addons/go_build/core/go_build_material_palette.gd")
const _SETTINGS_SCRIPT      := preload("res://addons/go_build/core/go_build_project_settings.gd")
const _SEL_MGR_SCRIPT       := preload("res://addons/go_build/core/selection_manager.gd")
const _MESH_INSTANCE_SCRIPT := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _GIZMO_PLUGIN_SCRIPT  := preload("res://addons/go_build/core/go_build_gizmo_plugin.gd")
const _PICKING_HELPER_SCRIPT := preload("res://addons/go_build/core/picking_helper.gd")
const _PANEL_SCRIPT         := preload("res://addons/go_build/core/go_build_panel.gd")
const _UV_PANEL_SCRIPT      := preload("res://addons/go_build/uv/go_build_uv_panel.gd")
const _CONTROLLER_SCRIPT    := preload(
		"res://addons/go_build/core/selection_input_controller.gd")
const _TOOL_PINNER_SCRIPT   := preload(
		"res://addons/go_build/core/node3d_editor_tool_pinner.gd")
const _ICON                 := preload("res://addons/go_build/go_build.svg")

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
var _panel_scroll: ScrollContainer               = null
var _uv_panel: GoBuildUvPanel                    = null
var _project_settings: GoBuildProjectSettings    = null
var _edited_node: GoBuildMeshInstance            = null
var _gizmo_plugin: GoBuildGizmoPlugin            = null
var _input_controller: SelectionInputController  = null
var _toolbar: HBoxContainer                      = null
var _snap_btn: OptionButton                      = null
var _rot_snap_btn: OptionButton                  = null
var _scale_snap_btn: OptionButton                = null
## Keeps the native Physical/V tool mode pinned whenever in a sub-element mode.
var _tool_pinner: Node3DEditorToolPinner         = null

## Last observed global transform of the edited node while in Object mode.
## Used to detect when the user moves the node so UVs can be refreshed.
var _prev_object_transform: Transform3D          = Transform3D.IDENTITY

## Guards the deferred object-mode UV rebake so at most one [method _flush_object_uv_bake]
## call is queued per rendered frame, no matter how many _process ticks fire.
var _object_uv_bake_scheduled: bool              = false
## Node targeted by the pending object-mode UV bake.
var _object_uv_pending_node: GoBuildMeshInstance = null

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

	_project_settings = GoBuildProjectSettings.load_or_create()
	# Notify the editor filesystem so the file appears in the dock immediately
	# (necessary when the file was just created on this run).
	EditorInterface.get_resource_filesystem().update_file(
			GoBuildProjectSettings.SETTINGS_PATH)

	_panel = _PANEL_SCRIPT.new()
	_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_panel_scroll = ScrollContainer.new()
	_panel_scroll.name = "GoBuild"
	_panel_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel_scroll.add_child(_panel)
	# Place in the upper-left dock alongside Scene, Import, and GoBuild UV so
	# all GoBuild panels live in the same dock group.
	add_control_to_dock(DOCK_SLOT_LEFT_UL, _panel_scroll)
	_panel.set_plugin(self)
	_panel.set_project_settings(_project_settings)

	_uv_panel = _UV_PANEL_SCRIPT.new()
	_uv_panel.name = "GoBuild UV"
	_uv_panel.custom_minimum_size = Vector2(200.0, 180.0)
	# Place in the upper-left dock alongside the Scene and Import tabs so the
	# UV view is adjacent to the scene tree and feels like a natural workspace.
	add_control_to_dock(DOCK_SLOT_LEFT_UL, _uv_panel)
	_uv_panel.set_plugin(self)

	_gizmo_plugin = _GIZMO_PLUGIN_SCRIPT.new()
	_gizmo_plugin.setup(self)
	add_node_3d_gizmo_plugin(_gizmo_plugin)

	_input_controller = _CONTROLLER_SCRIPT.new()
	_input_controller.setup(_gizmo_plugin, _panel, self)

	_build_toolbar()
	_tool_pinner = Node3DEditorToolPinner.new()
	set_process(true)


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
		remove_control_from_docks(_panel_scroll)
		_panel_scroll.queue_free()
		_panel_scroll = null
		_panel = null

	if _uv_panel:
		remove_control_from_docks(_uv_panel)
		_uv_panel.queue_free()
		_uv_panel = null

	_project_settings = null
	_disconnect_node_signals()
	_edited_node = null

	if _gizmo_plugin:
		remove_node_3d_gizmo_plugin(_gizmo_plugin)
		_gizmo_plugin = null

	_input_controller = null
	_object_uv_bake_scheduled = false
	_object_uv_pending_node = null
	set_process(false)
	if _tool_pinner != null:
		_tool_pinner.invalidate()
		_tool_pinner = null


## Per-frame poll (belt-and-suspenders alongside the per-draw-frame check).
func _process(_delta: float) -> void:
	if _edited_node != null and _tool_pinner != null:
		_tool_pinner.pin_if_active(_edited_node.selection.mode)

	# Live UV refresh in Object mode: schedule a single end-of-frame rebake
	# whenever the node's transform changes.  The flag ensures at most one
	# _flush_object_uv_bake call is deferred per rendered frame, regardless of
	# how many _process ticks fire while the user is dragging.
	if _edited_node != null \
			and _edited_node.selection.get_mode() == SelectionManager.Mode.OBJECT \
			and _edited_node.auto_uv_mode != GoBuildFace.UvMode.NONE:
		var t := _edited_node.global_transform
		if not t.is_equal_approx(_prev_object_transform):
			_prev_object_transform = t
			if _edited_node.needs_world_space_uv_refresh():
				_schedule_object_uv_bake(_edited_node)


## Queue a single deferred UV re-apply + bake for the active node in Object mode.
## Subsequent calls within the same frame are no-ops until the flush fires.
func _schedule_object_uv_bake(node: GoBuildMeshInstance) -> void:
	_object_uv_pending_node = node
	if not _object_uv_bake_scheduled:
		_object_uv_bake_scheduled = true
		call_deferred("_flush_object_uv_bake")


## Flush a pending object-mode UV bake.  Invoked at end-of-frame via call_deferred.
func _flush_object_uv_bake() -> void:
	var node: GoBuildMeshInstance = _object_uv_pending_node
	_object_uv_bake_scheduled = false
	_object_uv_pending_node = null
	if node == null or not is_instance_valid(node):
		return
	if _edited_node == null or node != _edited_node:
		return
	if node.selection.get_mode() != SelectionManager.Mode.OBJECT:
		return
	node._apply_auto_uv()
	node.bake_in_place()


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
		_input_controller.cancel_param_preview(_edited_node)
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
	# Capture the current edit mode so we can carry it to the new node.
	var carry_mode: int = SelectionManager.Mode.OBJECT
	if _edited_node != null and is_instance_valid(_edited_node):
		carry_mode = _edited_node.selection.get_mode()
		_edited_node.selection.clear()
		_edited_node.update_gizmos()
		_edited_node.set_edit_cull_override(false)
	_disconnect_node_signals()

	_edited_node = object as GoBuildMeshInstance
	# Reset transform tracking so _process triggers an immediate UV refresh on
	# the newly selected node (it will differ from the sentinel IDENTITY value).
	_prev_object_transform = Transform3D.IDENTITY
	_object_uv_bake_scheduled = false
	_object_uv_pending_node = null
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
		# Carry the previous edit mode to the new node (if not OBJECT already).
		if carry_mode != SelectionManager.Mode.OBJECT:
			_edited_node.selection.set_mode(carry_mode as SelectionManager.Mode)
		if _edited_node.selection.mode != SelectionManager.Mode.OBJECT:
			call_deferred("_suppress_native_gizmo")

	if _panel:
		_panel.set_target(_edited_node)
	if _uv_panel:
		_uv_panel.set_target(_edited_node)
	_refresh_panel_context()


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
			_panel.update_context("")
		if _uv_panel:
			_uv_panel.set_target(null)


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
	# Belt-and-suspenders: also pin on every viewport render frame.
	if _edited_node != null and _tool_pinner != null:
		_tool_pinner.pin_if_active(_edited_node.selection.mode)
	if _input_controller != null:
		_input_controller.draw_overlay(overlay)
	if _input_controller != null and _input_controller.has_active_param_preview():
		_draw_param_preview_hint(overlay)
	else:
		_draw_mode_hint(overlay)


func _handle_keyboard(event: InputEvent) -> int:
	if not (event is InputEventKey):
		return 0
	var key := event as InputEventKey
	if key.echo:
		return 0
	# Refresh the overlay hint on any Shift / Ctrl / Alt state change.
	# V is consumed below in _handle_action_key so it never reaches native
	# editor physical-mode — but Alt state changes still need overlay refresh.
	match key.keycode:
		KEY_SHIFT, KEY_CTRL, KEY_ALT:
			update_overlays()
			_refresh_panel_context()
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


## Handle single-key action shortcuts (W/E/R transform modes, Delete/X, M, F).
## Returns 1 if consumed, 0 if passed through, -1 if not matched.
func _handle_action_key(keycode: Key) -> int:
	match keycode:
		KEY_W:             return _set_transform_mode(GoBuildGizmoPlugin.TransformMode.TRANSLATE)
		KEY_E:             return _set_transform_mode(GoBuildGizmoPlugin.TransformMode.ROTATE)
		KEY_R:             return _set_transform_mode(GoBuildGizmoPlugin.TransformMode.SCALE)
		# Consume V so the native editor never switches to physical/pan mode.
		# GoBuild uses Alt (not V) for vertex snap, so V has no GoBuild action —
		# swallowing it here is the entire suppression contract for this key.
		KEY_V:             return 1
	# Element-mode action keys — handled by helpers to keep return count low.
	var result: int = _handle_element_action_key(keycode)
	return result


## Handle Delete/X/M/F shortcuts that operate on the current element selection.
## Returns 1 if consumed, 0 if passed through, -1 if not matched.
func _handle_element_action_key(keycode: Key) -> int:
	match keycode:
		KEY_DELETE, KEY_X: return _handle_delete_key()
		KEY_M:             return _handle_merge_key()
		KEY_F:             return _handle_bridge_key()
	return -1  # Not a recognised action key.


## Intercept Delete / X in sub-element modes; pass through in Object mode.
func _handle_delete_key() -> int:
	if _edited_node != null and _panel != null \
			and _edited_node.selection.get_mode() != SelectionManager.Mode.OBJECT:
		_panel.trigger_delete()
		return 1
	return 0


## Intercept M in Vertex mode only; pass through in all other modes.
func _handle_merge_key() -> int:
	if _edited_node != null and _panel != null \
			and _edited_node.selection.get_mode() == SelectionManager.Mode.VERTEX:
		_panel.trigger_merge()
		return 1
	return 0


## Intercept F in Edge mode only; triggers Bridge.  Pass through otherwise.
func _handle_bridge_key() -> int:
	if _edited_node != null and _panel != null \
			and _edited_node.selection.get_mode() == SelectionManager.Mode.EDGE:
		_panel.trigger_bridge()
		return 1
	return 0


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
	_refresh_panel_context()
	# W/E/R shortcuts fire via _shortcut_input on the Window root, which runs
	# before _forward_3d_gui_input — so the native W/E/R button may press itself
	# before GoBuild returns 1 to consume the event.  Defer a re-press of V so
	# it fires at the end of this same frame, after all shortcut processing.
	if _edited_node != null \
			and _edited_node.selection.mode != SelectionManager.Mode.OBJECT:
		call_deferred("_suppress_native_gizmo")
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


## Return the shared [GoBuildProjectSettings] resource for this project.
## Used by the panel and operations to access the global palette library.
func get_project_settings() -> GoBuildProjectSettings:
	return _project_settings


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


## Draw the active parameter-preview label in the viewport overlay.
## Shown in place of the mode-hint when a parameter-preview is active.
func _draw_param_preview_hint(overlay: Control) -> void:
	if _input_controller == null:
		return
	var hint: String = _input_controller.get_param_preview_overlay_text()
	if hint.is_empty():
		return
	var font: Font = ThemeDB.fallback_font
	var fsize: int = 13
	var m: float   = 8.0
	var pos := Vector2(m, overlay.size.y - m)
	overlay.draw_string(font, pos + Vector2(1.0, 1.0), hint,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.0, 0.0, 0.0, 0.60))
	overlay.draw_string(font, pos, hint,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(1.0, 0.85, 0.3, 0.95))


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
				hints.append("Alt: Vertex Snap")
			GoBuildGizmoPlugin.TransformMode.SCALE:
				if mode == SelectionManager.Mode.FACE:
					hints.append("Shift: Inset")
				hints.append("Ctrl: Snap")
	elif shift:
		hints.append("+Ctrl: Snap")

	if hints.is_empty():
		return "%s  ·  %s" % [mode_label, op]
	return "%s  ·  %s    %s" % [mode_label, op, "  ".join(hints)]


## Return a short operation name for the panel context label.
## Mirrors [method _build_overlay_hint] but returns only the active operation
## (no mode prefix, no shortcut hints).
func _build_panel_context() -> String:
	if _edited_node == null or _gizmo_plugin == null:
		return ""
	var mode: SelectionManager.Mode = _edited_node.selection.get_mode()
	if mode == SelectionManager.Mode.OBJECT:
		return ""
	var shift: bool = Input.is_key_pressed(KEY_SHIFT)
	var ctrl:  bool = Input.is_key_pressed(KEY_CTRL)
	var alt_key: bool = Input.is_key_pressed(KEY_ALT)
	var tmode := _gizmo_plugin.transform_mode
	var result: String
	match tmode:
		GoBuildGizmoPlugin.TransformMode.ROTATE:
			result = "■ Snap" if ctrl else "Rotate"
		GoBuildGizmoPlugin.TransformMode.SCALE:
			if shift and mode == SelectionManager.Mode.FACE:
				result = "■ Inset"
			elif ctrl:
				result = "■ Snap"
			else:
				result = "Scale"
		_:  # TRANSLATE
			if alt_key:
				result = "■ Alt Vertex Snap"
			elif ctrl:
				result = "■ Snap"
			elif shift:
				match mode:
					SelectionManager.Mode.FACE: result = "■ Extrude"
					SelectionManager.Mode.EDGE: result = "■ Extrude Edge"
					_:                          result = "Move"
			else:
				result = "Move"
	return result


## Push the current panel context label text to the panel.
func _refresh_panel_context() -> void:
	if _panel == null:
		return
	_panel.update_context(_build_panel_context())


## Enter parameter-preview mode for the given operation.
## Called from [GoBuildPanel] via [code]_plugin.call("begin_param_preview", preview)[/code].
## Takes a mesh snapshot, optionally scales sensitivity by gizmo scale, applies
## the default parameter, and passes the preview to [SelectionInputController].
func begin_param_preview(preview: GoBuildParamPreview) -> void:
	if _input_controller == null or _edited_node == null or _gizmo_plugin == null:
		return
	preview.node     = _edited_node
	preview.snapshot = _edited_node.go_build_mesh.take_snapshot()
	if preview.scale_by_gizmo:
		var s: float = _gizmo_plugin.compute_node_gizmo_scale(_edited_node)
		preview.units_per_pixel *= s
	# Apply the default parameter so the result is visible on entry.
	preview.apply_fn.call(preview.param_start)
	preview.param = preview.param_start
	_edited_node.begin_preview()
	_edited_node.bake_preview()
	_edited_node.update_gizmos()
	_input_controller.begin_param_preview(preview)
	_refresh_panel_context()
	update_overlays()


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_selection_changed() -> void:
	if _edited_node:
		_edited_node.update_gizmos()
	update_overlays()
	if _uv_panel:
		_uv_panel.refresh()


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
		_input_controller.cancel_param_preview(_edited_node)
		_input_controller.cancel_drag(_edited_node)
		_input_controller.clear_hover(_edited_node)
		_input_controller.cancel_box_select(_edited_node)
	_refresh_panel_context()
	if mode != SelectionManager.Mode.OBJECT:
		call_deferred("_suppress_native_gizmo")


func _on_edited_node_removed() -> void:
	if _input_controller != null:
		_input_controller.cancel_drag(null)
		_input_controller.cancel_box_select(null)
	_edited_node = null
	if _panel:
		_panel.set_target(null)
	if _uv_panel:
		_uv_panel.set_target(null)
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
# Native gizmo suppression — delegates to Node3DEditorToolPinner
# ---------------------------------------------------------------------------

## Delegates to [member _tool_pinner] to press the Physical/V button once.
## Called deferred from mode-change handlers and [method _set_transform_mode].
func _suppress_native_gizmo() -> void:
	if _tool_pinner != null:
		_tool_pinner.suppress()
