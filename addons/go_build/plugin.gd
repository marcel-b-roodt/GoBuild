## GoBuild EditorPlugin entry point.
##
## Registers the GoBuildMeshInstance custom type, adds the side-panel dock,
## and wires editor selection so the panel updates when a mesh is selected.
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
const _DEBUG_SCRIPT        := preload("res://addons/go_build/core/go_build_debug.gd")
const _SEL_MGR_SCRIPT      := preload("res://addons/go_build/core/selection_manager.gd")
const _MESH_INSTANCE_SCRIPT := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _GIZMO_PLUGIN_SCRIPT  := preload("res://addons/go_build/core/go_build_gizmo_plugin.gd")
const _PICKING_HELPER_SCRIPT := preload("res://addons/go_build/core/picking_helper.gd")
const _PANEL_SCRIPT         := preload("res://addons/go_build/core/go_build_panel.gd")
const _ICON                 := preload("res://icon.svg")

## Squared pixel distance the mouse must travel before a left-drag
## is treated as a box select rather than a point click.
const BOX_SELECT_DRAG_THRESHOLD_SQ: float = 25.0  # 5 px

## Screen-space pixel radius used when testing whether a left-click press
## falls on a translate cone handle (line-segment check along the cone body).
const _TRANSLATE_HANDLE_PICK_RADIUS_PX: float = 10.0
## Squared screen-space pixel radius for rotate-ring dot handle picking (point check).
const _ROTATE_HANDLE_PICK_RADIUS_SQ: float = 144.0  # 12 px
## Squared screen-space pixel radius for scale cube handle picking (point check).
const _SCALE_HANDLE_PICK_RADIUS_SQ: float  = 144.0  # 12 px
## Squared screen-space pixel radius for planar handle centre picking (point check).
const _PLANE_HANDLE_PICK_RADIUS_SQ: float  = 225.0  # 15 px — slightly larger (square area)
## Squared screen-space pixel radius for viewport-plane handle picking.
const _VIEW_PLANE_PICK_RADIUS_SQ: float    = 196.0  # 14 px

## EditorSettings keys for the four mode-switch shortcuts.
## Users can change the bound key under Editor → Editor Settings → gobuild.
const _SHORTCUT_OBJECT := "gobuild/shortcuts/object_mode"
const _SHORTCUT_VERTEX := "gobuild/shortcuts/vertex_mode"
const _SHORTCUT_EDGE   := "gobuild/shortcuts/edge_mode"
const _SHORTCUT_FACE   := "gobuild/shortcuts/face_mode"

var _panel: GoBuildPanel = null
var _edited_node: GoBuildMeshInstance = null
var _gizmo_plugin: GoBuildGizmoPlugin = null

# Box-select tracking state.
var _box_select_started: bool  = false  # mouse button is currently held
var _box_select_active:  bool  = false  # drag threshold has been exceeded
var _box_select_start:   Vector2 = Vector2.ZERO
var _box_select_current: Vector2 = Vector2.ZERO

# Handle-drag tracking state.
# Godot's native _set_handle pipeline only fires in Move mode (KEY_W).
# We run in Select mode (KEY_Q) to hide the node-level transform widget,
# so we manage handle dragging ourselves via begin_drag/update_drag/commit_drag.
var _dragging_handle:   bool    = false  # drag threshold exceeded and drag started
var _active_handle_id:  int     = -1     # handle ID being dragged
var _pressed_handle_id: int     = -1     # handle ID under the cursor at press time
var _handle_press_pos:  Vector2 = Vector2.ZERO

# Mode-switch shortcuts (initialised in _enter_tree via EditorSettings).
var _shortcut_object: Shortcut
var _shortcut_vertex: Shortcut
var _shortcut_edge:   Shortcut
var _shortcut_face:   Shortcut


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _enter_tree() -> void:
	# Register the custom node type so it appears in "Add Node".
	add_custom_type(
		"GoBuildMeshInstance",
		"MeshInstance3D",
		_MESH_INSTANCE_SCRIPT,
		_ICON,
	)

	# Load (or create) mode-switch shortcuts from EditorSettings.
	_init_shortcuts()

	# Create and dock the side panel.
	_panel = _PANEL_SCRIPT.new()
	add_control_to_dock(DOCK_SLOT_LEFT_BL, _panel)
	_panel.set_plugin(self)

	# Register the gizmo plugin so GoBuildMeshInstance nodes get overlays.
	_gizmo_plugin = _GIZMO_PLUGIN_SCRIPT.new()
	_gizmo_plugin.setup(self)
	add_node_3d_gizmo_plugin(_gizmo_plugin)


func _exit_tree() -> void:
	remove_custom_type("GoBuildMeshInstance")

	if _panel:
		remove_control_from_docks(_panel)
		_panel.queue_free()
		_panel = null

	_disconnect_node_signals()
	_edited_node = null

	if _gizmo_plugin:
		remove_node_3d_gizmo_plugin(_gizmo_plugin)
		_gizmo_plugin = null


## Detect OS-level window focus changes (e.g. alt-tab back into the editor).
## [constant NOTIFICATION_APPLICATION_FOCUS_IN] fires on [Node] when the
## application window regains focus after losing it to another OS window.
## Godot does NOT re-call [method _edit] for the already-selected node on
## focus return, so gizmos go stale.  We trigger a full refresh here.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_on_editor_focus_regained()


## Recover from a stale-gizmo state caused by alt-tab / OS window focus change.
##
## After the application regains focus Godot does NOT re-call [method _edit]
## for the currently selected node, so [GoBuildGizmo._redraw] never fires and
## the transform handles appear frozen.  This method:
##
## 1. Validates [member _edited_node] — clears it if the instance is gone.
## 2. Resets any in-progress native gizmo drag state (drag events from before
##    the focus loss are gone; the drag cannot be completed cleanly).
## 3. Cycles the gizmo plugin registration so Godot re-scans the scene and
##    calls [method GoBuildGizmoPlugin._has_gizmo] on every node.
## 4. Fires [method _force_gizmo_redraw_deferred] to recreate or refresh the
##    gizmo in the next frame.
func _on_editor_focus_regained() -> void:
	# ── Step 1: validate the edited-node reference ──────────────────────────
	if _edited_node != null and not is_instance_valid(_edited_node):
		GoBuildDebug.log("[GoBuild] PLUGIN._on_editor_focus_regained  edited_node gone — clearing")
		_disconnect_node_signals()
		_edited_node = null
		if _panel:
			_panel.set_target(null)

	if _edited_node == null:
		return

	GoBuildDebug.log("[GoBuild] PLUGIN._on_editor_focus_regained  node=%s" % _edited_node.name)

	# ── Step 2: reset stale drag / box-select state ──────────────────────────
	# Input events from before the focus loss are gone; any in-progress drag
	# cannot be completed cleanly.  Cancel and clear all drag state.
	_cancel_active_drag()
	_box_select_started = false
	_box_select_active  = false

	# ── Step 3: cycle plugin registration to flush Godot's gizmo cache ───────
	# Same technique used in _edit(): forces Node3DEditor to re-run _has_gizmo()
	# on every scene node, ensuring our gizmo exists before the redraw fires.
	if _gizmo_plugin:
		remove_node_3d_gizmo_plugin(_gizmo_plugin)
		add_node_3d_gizmo_plugin(_gizmo_plugin)

	# ── Step 4: deferred redraw ──────────────────────────────────────────────
	_force_gizmo_redraw_deferred(_edited_node)


# ---------------------------------------------------------------------------
# Selection / editing
# ---------------------------------------------------------------------------

## Returns true when a [GoBuildMeshInstance] is selected so the plugin
## receives [method _edit] and [method _make_visible] notifications.
func _handles(object: Object) -> bool:
	return object is GoBuildMeshInstance


## Called by the editor when a [GoBuildMeshInstance] is selected.
func _edit(object: Object) -> void:
	# Cleanly disconnect from any previously edited node first.
	_disconnect_node_signals()

	_edited_node = object as GoBuildMeshInstance
	var dbg_mode: int = _edited_node.selection.get_mode() if _edited_node else -1
	var dbg_script: Script = _edited_node.get_script() if _edited_node else null
	var dbg_path: String = dbg_script.resource_path if dbg_script else "null"
	GoBuildDebug.log("[GoBuild] PLUGIN._edit  node=%s  is_null=%s  mode=%d  script_path=%s" \
			% [str(object), str(_edited_node == null), dbg_mode, dbg_path])

	if _edited_node != null:
		# Drive viewport redraws whenever selection or mode changes.
		_edited_node.selection.selection_changed.connect(_on_selection_changed)
		_edited_node.selection.mode_changed.connect(_on_mode_changed)
		# Clear our reference if the node is removed from the scene tree.
		_edited_node.tree_exiting.connect(_on_edited_node_removed)

		# ── Force gizmo redraw ───────────────────────────────────────────
		# When the user physically clicks the node in the 3D viewport, Godot
		# creates the gizmo BEFORE calling _edit().  Previously we cycled the
		# plugin registration (remove + add) here to force gizmo creation for
		# programmatic selections.  That approach was actively harmful: the
		# remove step destroyed the gizmo that Godot had just created, and
		# the add step did NOT synchronously re-create it (evidenced by the
		# absence of any GIZMO_PLUGIN._has_gizmo log entries after the cycle).
		# The result was update_gizmos() finding an empty gizmo list → no redraw.
		#
		# The correct approach:
		#   1. Immediate update_gizmos() — works when the gizmo already exists
		#      (physical viewport click, or the node was in the scene before the
		#      plugin was registered and got a gizmo on _enter_tree).
		#   2. Deferred update_gizmos() — catches programmatic-selection cases
		#      where Godot defers gizmo creation to the next frame (e.g. after
		#      EditorSelection.add_node() or an undo/redo insertion).
		# Godot only calls _has_gizmo() when the plugin is first registered
		_force_gizmo_redraw_deferred(_edited_node)
		# OR when the user physically clicks a node in the 3D viewport.
		# Programmatic selection (EditorSelection.add_node, scene-tree click)
		# does NOT trigger the Node3DEditor gizmo-creation pipeline.
		# Additionally, our _forward_3d_gui_input consumes clicks in element
		# modes, so Godot never gets a viewport click to trigger it either.
		# Cycling the plugin registration forces Node3DEditor to call
		# _has_gizmo() on all scene nodes right now, creating the gizmo.
		if _gizmo_plugin:
			remove_node_3d_gizmo_plugin(_gizmo_plugin)
			add_node_3d_gizmo_plugin(_gizmo_plugin)

		_edited_node.update_gizmos()

		# Always hide Godot's built-in transform widget while a GoBuildMeshInstance
		# is being edited — our gizmo provides its own handles and the engine
		# gizmo overlaps and conflicts with them in all edit modes.
		# KEY_Q = Select mode: no transform arrows shown.
		# KEY_W is restored in _make_visible(false) and _on_edited_node_removed
		# once the node is deselected.
		_send_editor_tool_shortcut(KEY_Q)

	if _panel:
		_panel.set_target(_edited_node)


## Called by the editor to show or hide our UI when selection changes.
## Note: _make_visible is the bottom-panel API. We use a dock control instead,
## Wait one frame, then ensure a [GoBuildGizmo] is attached to [param node]
## and trigger a redraw — but only while [param node] is still the currently
## edited node.
##
## Two paths:
##  - Gizmo already exists (normal engine-managed creation): call
##    [method Node3D.update_gizmos] to trigger [method GoBuildGizmo._redraw].
##  - Gizmo missing (engine scan didn't fire — e.g. programmatic selection,
##    undo/redo timing, scene-load race): create one via
##    [method GoBuildGizmoPlugin._create_gizmo] and attach it with
##    [method Node3D.add_gizmo].  [method Node3D.add_gizmo] calls
##    [method GoBuildGizmo._redraw] immediately, so no extra
##    [method Node3D.update_gizmos] call is needed.
func _force_gizmo_redraw_deferred(node: Node3D) -> void:
	await get_tree().process_frame
	if not is_instance_valid(node) or node != _edited_node:
		return
	if _gizmo_plugin == null:
		return

	var has_gizmo: bool = _gizmo_plugin.has_our_gizmo(node)
	GoBuildDebug.log("[GoBuild] PLUGIN._force_gizmo_redraw_deferred  node_valid=true  has_gizmo=%s" \
			% str(has_gizmo))

	if has_gizmo:
		# Gizmo exists — just trigger a redraw.
		node.update_gizmos()
		return

	# No GoBuild gizmo on this node yet.  The engine's gizmo-creation pipeline
	# (triggered by add_node_3d_gizmo_plugin scanning the scene) apparently did
	# not fire for this node in time — or at all.  Create one manually.
	#
	# We call _create_gizmo() directly (bypassing the C++ pipeline), so the
	# normal internal set_plugin() step is skipped.  We compensate by writing
	# the plugin reference into GoBuildGizmo._manual_plugin_ref directly, which
	# _redraw() uses as a fallback when get_plugin() returns null.
	GoBuildDebug.log("[GoBuild] PLUGIN._force_gizmo_redraw_deferred  no gizmo — force-creating")
	var gizmo: EditorNode3DGizmo = _gizmo_plugin._create_gizmo(node)
	if gizmo == null:
		GoBuildDebug.log("[GoBuild] PLUGIN._force_gizmo_redraw_deferred  _create_gizmo null — giving up")
		return
	# Set the plugin reference so _redraw() can access shared materials.
	gizmo.set("_manual_plugin_ref", _gizmo_plugin)
	# add_gizmo() calls _redraw() immediately when the node is inside the world.
	node.add_gizmo(gizmo)


## so we deliberately do NOT hide _panel here — the dock tab must always show
## content. We only clear the selection when another node type is selected.
func _make_visible(visible: bool) -> void:
	if not visible:
		_clear_hover()
		_disconnect_node_signals()
		_edited_node = null
		if _panel:
			_panel.set_target(null)
		# Restore the built-in transform widget now that GoBuild is no longer active.
		_send_editor_tool_shortcut(KEY_W)


# ---------------------------------------------------------------------------
# Viewport input — keyboard shortcuts
# ---------------------------------------------------------------------------

## Intercept input in the 3D viewport.
##
## - Keys [b]1–4[/b]: switch edit mode (mirrors Blender muscle-memory).
## - [b]Escape[/b]: cancel an in-progress handle drag.
## - [b]Left-click on a transform handle[/b]: consume and begin a custom drag
##   via [method GoBuildGizmoPlugin.begin_drag] (Godot's native _set_handle
##   pipeline is disabled in SELECT mode which we use to hide the node gizmo).
## - [b]Left-click elsewhere[/b]: pick vertex / edge / face depending on active mode.
##   [kbd]Shift[/kbd] adds to the selection; [kbd]Ctrl[/kbd] toggles.
## - [b]Left-drag[/b]: rubber-band box select in element modes.
##
## Returns a non-zero int to consume the event.
func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if _edited_node == null:
		return 0
	var key_result: int = _handle_keyboard(event)
	if key_result != 0:
		return key_result
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		# Right-button drag = Godot native viewport orbit / freelook.
		# Never intercept it — any lingering GoBuild state must not steal those events.
		if mm.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			return 0
		return _handle_mouse_motion(camera, mm)
	if event is InputEventMouseButton:
		return _handle_mouse_button_event(camera, event as InputEventMouseButton)
	return 0


## Dispatch a mouse-button event received from [method _forward_3d_gui_input].
##
## Right-button press: cancel any in-progress GoBuild drag / box-select so
## Godot's native viewport orbit / freelook can run without interference.
## Left-button: delegate to the press / release handlers.
## All other buttons: pass through (return 0).
func _handle_mouse_button_event(camera: Camera3D, mb: InputEventMouseButton) -> int:
	if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		_cancel_active_drag()
		_cancel_box_select()
		return 0
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			return _handle_mouse_press(camera, mb)
		return _handle_mouse_release(camera, mb)
	return 0


## Draw the box-select rectangle overlay while a drag is in progress.
func _forward_3d_draw_over_viewport(overlay: Control) -> void:
	if not _box_select_active:
		return
	var rect: Rect2 = _get_box_select_rect()
	overlay.draw_rect(rect, Color(0.25, 0.45, 0.8, 0.15), true)
	overlay.draw_rect(rect, Color(0.5, 0.7, 1.0, 0.85), false)


## Handle keyboard mode-switch shortcuts and drag cancellation.
## Returns 1 if consumed, 0 if not.
##
## Shortcuts default to 1/2/3/4 but are rebindable via
## Editor → Editor Settings → gobuild → shortcuts.
## W/E/R switch the GoBuild transform mode (Translate/Rotate/Scale) and are
## consumed so Godot's built-in tool-switch does not also fire (we stay in
## SELECT mode regardless of transform mode).
func _handle_keyboard(event: InputEvent) -> int:
	if not (event is InputEventKey):
		return 0
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return 0
	if key.keycode == KEY_ESCAPE and (_dragging_handle or _pressed_handle_id != -1):
		_cancel_active_drag()
		if _edited_node:
			_edited_node.update_gizmos()
		return 1
	return _handle_keyboard_shortcut(key)


## Dispatch mode-switch and transform-mode shortcuts from [method _handle_keyboard].
func _handle_keyboard_shortcut(key: InputEventKey) -> int:
	match key.keycode:
		KEY_W: return _set_transform_mode(GoBuildGizmoPlugin.TransformMode.TRANSLATE)
		KEY_E: return _set_transform_mode(GoBuildGizmoPlugin.TransformMode.ROTATE)
		KEY_R: return _set_transform_mode(GoBuildGizmoPlugin.TransformMode.SCALE)
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


## Apply a [GoBuildGizmoPlugin.TransformMode] change and trigger a gizmo redraw.
## Returns 1 (consumed) always — the mode switch is a GoBuild-internal event.
func _set_transform_mode(mode: GoBuildGizmoPlugin.TransformMode) -> int:
	if _gizmo_plugin == null:
		return 0
	_cancel_active_drag()
	_clear_hover()
	_gizmo_plugin.transform_mode = mode
	if _edited_node:
		_edited_node.update_gizmos()
	return 1


# ---------------------------------------------------------------------------
# Shortcut initialisation
# ---------------------------------------------------------------------------

## Create or load the four mode-switch shortcuts from EditorSettings.
## Settings persist across editor sessions under the [code]gobuild/shortcuts[/code]
## category.  Users can rebind them in Editor → Editor Settings.
func _init_shortcuts() -> void:
	var es := EditorInterface.get_editor_settings()
	_shortcut_object = _require_shortcut(es, _SHORTCUT_OBJECT, KEY_1)
	_shortcut_vertex = _require_shortcut(es, _SHORTCUT_VERTEX, KEY_2)
	_shortcut_edge   = _require_shortcut(es, _SHORTCUT_EDGE,   KEY_3)
	_shortcut_face   = _require_shortcut(es, _SHORTCUT_FACE,   KEY_4)


## Return the persisted [Shortcut] for [param setting].
## If the setting does not yet exist, create a default bound to [param default_key]
## with [constant KEY_LOCATION_UNSPECIFIED] so it never matches numpad events.
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


## Public entry point for changing edit mode.
## Called by keyboard shortcuts (via [method _handle_keyboard]) and by
## [GoBuildPanel] mode buttons.  Always use this instead of setting
## [member SelectionManager.mode] directly so the editor tool shortcut and
## the explicit gizmo refresh both fire regardless of call origin.
func switch_mode(mode: SelectionManager.Mode) -> void:
	_set_mode(mode)


func _set_mode(mode: SelectionManager.Mode) -> void:
	if _edited_node == null:
		GoBuildDebug.log("[GoBuild] PLUGIN._set_mode  SKIPPED — _edited_node is null")
		return
	GoBuildDebug.log("[GoBuild] PLUGIN._set_mode  mode=%d  node=%s" % [mode, _edited_node.name])
	_edited_node.selection.set_mode(mode)
	# Belt-and-suspenders: force a gizmo redraw immediately after the mode
	# switch.  The signal chain (mode_changed → _on_mode_changed → update_gizmos)
	# already handles this, but an explicit call here guarantees element overlays
	# appear on the very next frame even if the editor's signal delivery is deferred.
	_edited_node.update_gizmos()


# ---------------------------------------------------------------------------
# Picking
# ---------------------------------------------------------------------------

## Perform a pick at [param click_pos] for the current edit mode.
## [param additive] (Shift) adds to the existing selection.
## [param toggle]   (Ctrl)  toggles the hit element in/out of the selection.
## Returns 1 to consume the event, 0 to let it propagate.
func _handle_pick(
		camera: Camera3D,
		click_pos: Vector2,
		additive: bool,
		toggle: bool,
) -> int:
	var sel: SelectionManager = _edited_node.selection
	var mode: SelectionManager.Mode = sel.get_mode()
	var gbm: GoBuildMesh = _edited_node.go_build_mesh

	GoBuildDebug.log("[GoBuild] PLUGIN._handle_pick  mode=%d  gbm_null=%s  verts=%d  faces=%d" \
			% [mode, str(gbm == null), gbm.vertices.size() if gbm else -1, gbm.faces.size() if gbm else -1])

	# Object mode: let Godot handle its own node-selection click.
	if mode == SelectionManager.Mode.OBJECT:
		return 0

	if gbm == null:
		return 1

	# Find the nearest hit element for the active mode.
	var hit_idx: int = -1
	match mode:
		SelectionManager.Mode.VERTEX:
			hit_idx = PickingHelper.find_nearest_vertex(camera, click_pos, _edited_node, gbm)
		SelectionManager.Mode.EDGE:
			hit_idx = PickingHelper.find_nearest_edge(camera, click_pos, _edited_node, gbm)
		SelectionManager.Mode.FACE:
			hit_idx = PickingHelper.find_nearest_face(camera, click_pos, _edited_node, gbm)

	GoBuildDebug.log("[GoBuild] PLUGIN._handle_pick  hit=%d  pos=%s" \
			% [hit_idx, str(click_pos)])

	if hit_idx == -1:
		# Missed everything — clear selection on a plain click.
		if not additive and not toggle:
			sel.clear()
		return 1   # Still consume so we don't deselect the GoBuildMeshInstance node.

	_apply_pick(sel, mode, hit_idx, additive, toggle)
	return 1


## Apply [param hit_idx] to [param sel] according to the modifier keys.
func _apply_pick(
		sel: SelectionManager,
		mode: SelectionManager.Mode,
		hit_idx: int,
		additive: bool,
		toggle: bool,
) -> void:
	if toggle:
		match mode:
			SelectionManager.Mode.VERTEX: sel.toggle_vertex(hit_idx)
			SelectionManager.Mode.EDGE:   sel.toggle_edge(hit_idx)
			SelectionManager.Mode.FACE:   sel.toggle_face(hit_idx)
	elif additive:
		match mode:
			SelectionManager.Mode.VERTEX: sel.select_vertex(hit_idx)
			SelectionManager.Mode.EDGE:   sel.select_edge(hit_idx)
			SelectionManager.Mode.FACE:   sel.select_face(hit_idx)
	else:
		# Plain click: replace the whole selection with just this element.
		sel.clear()
		match mode:
			SelectionManager.Mode.VERTEX: sel.select_vertex(hit_idx)
			SelectionManager.Mode.EDGE:   sel.select_edge(hit_idx)
			SelectionManager.Mode.FACE:   sel.select_face(hit_idx)


# ---------------------------------------------------------------------------
# Overlay / gizmo refresh
# ---------------------------------------------------------------------------

## Triggered when the edited node's [SelectionManager] emits
## [signal SelectionManager.selection_changed].
func _on_selection_changed() -> void:
	# update_overlays() repaints the 2D box-select overlay.
	# update_gizmos() triggers _redraw() on EditorNode3DGizmo instances
	# so vertex/edge/face highlights stay in sync with the selection.
	if _edited_node:
		_edited_node.update_gizmos()
	update_overlays()


## Triggered when the edited node's [SelectionManager] emits
## [signal SelectionManager.mode_changed].
## This fires for every mode change regardless of source (panel button, keyboard
## shortcut, or direct API call), so it is the canonical place for side-effects
## that must always accompany a mode switch.
func _on_mode_changed(mode: SelectionManager.Mode) -> void:
	GoBuildDebug.log("[GoBuild] PLUGIN._on_mode_changed  mode=%d  edited_null=%s" \
			% [mode, str(_edited_node == null)])
	# Cancel any in-progress handle drag before the mode changes.
	_cancel_active_drag()
	_clear_hover()
	# Always stay in Select mode (KEY_Q) so Godot's built-in transform widget
	# never overlaps our custom gizmo handles, regardless of edit mode.
	# KEY_W is only restored when the node is deselected entirely
	# (_make_visible(false) / _on_edited_node_removed).
	_send_editor_tool_shortcut(KEY_Q)
	_cancel_box_select()


## Triggered when the currently edited node exits the scene tree
## (user deleted it or unloaded the scene).  Clears stale editing state.
func _on_edited_node_removed() -> void:
	_cancel_active_drag()
	_clear_hover()
	_box_select_started = false
	_box_select_active  = false
	_edited_node = null
	if _panel:
		_panel.set_target(null)
	_send_editor_tool_shortcut(KEY_W)
	update_overlays()


## Safely disconnect all signals connected to [member _edited_node].
## No-op if [member _edited_node] is null or any signal is not connected.
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
# Mouse input helpers
# ---------------------------------------------------------------------------

## Handle a left-mouse-button press in element mode.
##
## If the click lands on a transform handle, consume and record the handle so
## [method _handle_mouse_motion] can start a custom drag once the threshold is
## exceeded.  We must consume (return 1) rather than pass through because
## Godot's native _set_handle pipeline requires Move mode (KEY_W), but we run
## in Select mode (KEY_Q) to hide the node-level transform widget.
## Otherwise begin box-select tracking.
func _handle_mouse_press(camera: Camera3D, mb: InputEventMouseButton) -> int:
	var mode: SelectionManager.Mode = _edited_node.selection.get_mode()
	if mode == SelectionManager.Mode.OBJECT:
		return 0
	var hit_id: int = _find_hovered_handle_id(camera, mb.position)
	if hit_id != -1:
		GoBuildDebug.log("[GoBuild] PLUGIN._handle_mouse_press  hit_id=%d → custom drag armed" % hit_id)
		_pressed_handle_id = hit_id
		_handle_press_pos  = mb.position
		return 1
	# No handle hit — start box-select tracking.
	GoBuildDebug.log("[GoBuild] PLUGIN._handle_mouse_press  mode=%d  pos=%s  (box-select start)" \
			% [_edited_node.selection.get_mode(), str(mb.position)])
	_box_select_started = true
	_box_select_active  = false
	_box_select_start   = mb.position
	_box_select_current = mb.position
	return 1


## Return the handle ID nearest to [param click_pos] for the currently active
## transform mode, or [code]-1[/code] if no handle is hit.
##
## Dispatches to [method _find_translate_handle], [method _find_rotate_handle],
## or [method _find_scale_handle] based on [member GoBuildGizmoPlugin.transform_mode].
func _find_hovered_handle_id(camera: Camera3D, click_pos: Vector2) -> int:
	if _gizmo_plugin == null or _edited_node == null:
		return -1
	var positions: Array[Vector3] = \
			_gizmo_plugin.get_transform_handle_world_positions(_edited_node)
	if positions.is_empty():
		return -1
	match _gizmo_plugin.transform_mode:
		GoBuildGizmoPlugin.TransformMode.ROTATE:
			return _find_rotate_handle(camera, click_pos, positions)
		GoBuildGizmoPlugin.TransformMode.SCALE:
			return _find_scale_handle(camera, click_pos, positions)
		_:  # TRANSLATE
			return _find_translate_handle(camera, click_pos, positions)


## Test translate cone tips (positions 0–2) then plane handles.
func _find_translate_handle(camera: Camera3D, click_pos: Vector2, positions: Array[Vector3]) -> int:
	var gt: Transform3D = _edited_node.global_transform
	var s: float        = _gizmo_plugin.compute_node_gizmo_scale(_edited_node)
	var cone_h: float   = GoBuildGizmoPlugin.CONE_HEIGHT * s
	var local_axes: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	for i: int in 3:
		var apex_world: Vector3 = positions[i]
		if not camera.is_position_in_frustum(apex_world):
			continue
		var world_axis: Vector3  = (gt.basis * local_axes[i]).normalized()
		var base_world: Vector3  = apex_world - world_axis * cone_h
		if PickingHelper.point_to_segment_dist(
				click_pos,
				camera.unproject_position(base_world),
				camera.unproject_position(apex_world)) <= _TRANSLATE_HANDLE_PICK_RADIUS_PX:
			return GoBuildGizmoPlugin.AXIS_HANDLE_OFFSET + i
	return _find_plane_handle(camera, click_pos, s)


## Test planar handle centres then the viewport-plane handle at the centroid.
##
## The viewport-plane handle pick area is enlarged to roughly match the rotation
## ring's screen-space radius: any click within that radius of the centroid (that
## does not land on an axis cone or a planar square) starts a camera-plane drag.
## This mirrors Godot's native inner-sphere viewport-drag UX.
func _find_plane_handle(camera: Camera3D, click_pos: Vector2, s: float) -> int:
	var gt: Transform3D = _edited_node.global_transform
	var lc: Vector3 = _gizmo_plugin.get_selection_local_centroid(_edited_node)
	var inner: float = GoBuildGizmoPlugin.PLANE_INNER_OFFSET * s
	var local_centers: Array[Vector3] = [
		lc + Vector3(inner, inner, 0.0),   # XY
		lc + Vector3(0.0,  inner, inner),  # YZ
		lc + Vector3(inner, 0.0,  inner),  # XZ
	]
	for i: int in 3:
		var world_pos: Vector3 = gt * local_centers[i]
		if not camera.is_position_in_frustum(world_pos):
			continue
		if camera.unproject_position(world_pos).distance_squared_to(click_pos) \
				<= _PLANE_HANDLE_PICK_RADIUS_SQ:
			return GoBuildGizmoPlugin.PLANE_HANDLE_OFFSET + i

	# Viewport-plane handle — accept any click within the ring's screen radius of
	# the centroid so the inner area behaves like Godot's sphere translate handle.
	var centroid_world: Vector3 = gt * lc
	if camera.is_position_in_frustum(centroid_world):
		var c_screen: Vector2 = camera.unproject_position(centroid_world)
		# Derive the ring screen radius by projecting a point at ring_r_world from
		# the centroid (UP direction in local space → world via global_transform.basis).
		var ring_r_world: float = GoBuildGizmoPlugin.ROT_RING_RADIUS * s
		var ring_edge_world: Vector3 = gt * (lc + Vector3.UP * ring_r_world)
		var ring_screen_r_sq: float
		if camera.is_position_in_frustum(ring_edge_world):
			ring_screen_r_sq = c_screen.distance_squared_to(
					camera.unproject_position(ring_edge_world))
		else:
			ring_screen_r_sq = _VIEW_PLANE_PICK_RADIUS_SQ   # safe fallback
		if c_screen.distance_squared_to(click_pos) <= ring_screen_r_sq:
			return GoBuildGizmoPlugin.VIEW_PLANE_HANDLE_ID
	return -1


## Test rotation ring handles by projecting the mouse ray onto each ring plane
## and accepting the hit if the intersection lands within a tolerance band of
## the ring radius (±20 % of the world-space ring radius).
##
## Supersedes the old dot-only check (positions[3..5]) — the full-ring approach
## naturally handles zoom scaling: [code]ring_r_world = ROT_RING_RADIUS * s[/code]
## is derived from [method GoBuildGizmoPlugin.compute_world_gizmo_scale], so the
## pick band shrinks / grows in world space exactly as the drawn ring does.
##
## Returns the handle ID of the nearest ring that was hit, or [code]-1[/code].
func _find_rotate_handle(camera: Camera3D, click_pos: Vector2, _positions: Array[Vector3]) -> int:
	if _gizmo_plugin == null or _edited_node == null:
		return -1
	var lc: Vector3          = _gizmo_plugin.get_selection_local_centroid(_edited_node)
	var gt: Transform3D      = _edited_node.global_transform
	var world_centroid: Vector3 = gt * lc
	var s: float             = _gizmo_plugin.compute_world_gizmo_scale(world_centroid)
	var ring_r_world: float  = GoBuildGizmoPlugin.ROT_RING_RADIUS * s
	var tol: float           = ring_r_world * 0.2   # ±20 % tolerance band

	var ray_origin: Vector3  = camera.project_ray_origin(click_pos)
	var ray_dir: Vector3     = camera.project_ray_normal(click_pos)

	# Ring plane normals in local space: X-ring lies in the YZ plane (normal = X),
	# Y-ring lies in the XZ plane (normal = Y), Z-ring lies in the XY plane (normal = Z).
	var local_normals: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var best_id:  int   = -1
	var best_err: float = tol  # start just at tolerance; any tighter hit wins

	for i: int in 3:
		var world_normal: Vector3 = (gt.basis * local_normals[i]).normalized()
		var hit: Vector3 = GoBuildGizmoPlugin._ray_plane_intersect(
				ray_origin, ray_dir, world_centroid, world_normal)
		if hit == Vector3.INF:
			continue
		var dist: float     = hit.distance_to(world_centroid)
		var ring_err: float = abs(dist - ring_r_world)
		if ring_err < best_err:
			best_err = ring_err
			best_id  = GoBuildGizmoPlugin.ROT_HANDLE_OFFSET + i

	return best_id


## Test scale cube tips (positions 0–2 — same world positions as translate tips).
func _find_scale_handle(camera: Camera3D, click_pos: Vector2, positions: Array[Vector3]) -> int:
	for i: int in 3:
		var tip_world: Vector3 = positions[i]
		if not camera.is_position_in_frustum(tip_world):
			continue
		if camera.unproject_position(tip_world).distance_squared_to(click_pos) \
				<= _SCALE_HANDLE_PICK_RADIUS_SQ:
			return GoBuildGizmoPlugin.SCALE_HANDLE_OFFSET + i
	return -1


## Simulate pressing [param keycode] to switch Godot's built-in 3D editor tool mode.
##
## Stop-gap for the lack of a public [EditorPlugin] API to set the tool mode directly.
##
## Uses [method Object.call_deferred] so the key event fires in the next frame,
## after any dock-panel button press has finished processing and settled its focus
## state.  The 3D viewport container is explicitly focused before dispatching the
## event so that [code]Node3DEditorViewport._gui_input()[/code] receives it
## regardless of which dock control previously held keyboard focus.
##
## Typical use: KEY_Q = "Select" (hides transform arrows during element editing),
## KEY_W = "Move" (restores transform arrows on return to Object mode).
func _send_editor_tool_shortcut(keycode: Key) -> void:
	call_deferred("_do_send_editor_tool_shortcut", keycode)


## Deferred body for [method _send_editor_tool_shortcut].
## Runs in the next frame so button-press focus has settled before we redirect it.
func _do_send_editor_tool_shortcut(keycode: Key) -> void:
	# Guard: when right-click is held the 3D viewport is in "freelook" mode.
	# In freelook mode KEY_Q = "move camera down", KEY_W = "move forward", etc.
	# Injecting any tool-switch key during freelook would translate the camera.
	# Bail out — the native gizmo may flash briefly, but that is far less
	# disruptive than an unintended camera movement.
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		return

	# Focus the 3D viewport container so Node3DEditorViewport._gui_input()
	# receives the key event.  Without this, clicking a dock button shifts
	# keyboard focus to the dock, and Input.parse_input_event never reaches
	# the viewport's shortcut handler.
	var sv: SubViewport = EditorInterface.get_editor_viewport_3d(0)
	if sv != null:
		var parent: Node = sv.get_parent()
		if parent is Control:
			(parent as Control).grab_focus()

	# Send the key press that switches the editor tool mode.
	var ev_down := InputEventKey.new()
	ev_down.keycode          = keycode
	ev_down.physical_keycode = keycode
	ev_down.pressed          = true
	ev_down.echo             = false
	Input.parse_input_event(ev_down)

	# Immediately follow with a key-release so Input.is_key_pressed(keycode)
	# returns false right away.  Without this the key state stays "held" inside
	# Godot's Input singleton, and the viewport's freelook update loop would
	# keep moving the camera for every frame the button appeared held.
	var ev_up := InputEventKey.new()
	ev_up.keycode          = keycode
	ev_up.physical_keycode = keycode
	ev_up.pressed          = false
	ev_up.echo             = false
	Input.parse_input_event(ev_up)


## Handle a left-mouse-button release.
## If a handle drag was active  → commit it.
## If a handle was pressed but no drag threshold → no-op (handle click does not pick geometry).
## If box-select was active    → finish it.
## If box-select started but no drag threshold → delegate to point-pick.
func _handle_mouse_release(camera: Camera3D, mb: InputEventMouseButton) -> int:
	# ── Handle drag commit ────────────────────────────────────────────────────
	if _dragging_handle:
		_gizmo_plugin.commit_drag(_edited_node, _active_handle_id, false)
		_dragging_handle  = false
		_active_handle_id = -1
		if _edited_node:
			_edited_node.update_gizmos()
		return 1
	# ── Handle press without drag → no-op ────────────────────────────────────
	# Design decision: clicking a transform handle without dragging does not
	# select geometry.  The event is consumed with no mesh or selection change.
	if _pressed_handle_id != -1:
		_pressed_handle_id = -1
		return 1
	# ── Box-select ────────────────────────────────────────────────────────────
	if not _box_select_started:
		return 0
	_box_select_started = false
	if _box_select_active:
		_box_select_active = false
		update_overlays()
		GoBuildDebug.log("[GoBuild] PLUGIN._handle_mouse_release  → _finish_box_select")
		_finish_box_select(camera, mb.shift_pressed, mb.ctrl_pressed)
		return 1
	GoBuildDebug.log("[GoBuild] PLUGIN._handle_mouse_release  → _handle_pick  pos=%s" \
			% str(_box_select_start))
	return _handle_pick(camera, _box_select_start, mb.shift_pressed, mb.ctrl_pressed)


## Track mouse movement for box-select and handle drags.
func _handle_mouse_motion(camera: Camera3D, mm: InputEventMouseMotion) -> int:
	# ── Handle drag ───────────────────────────────────────────────────────────
	if _dragging_handle:
		_gizmo_plugin.update_drag(_edited_node, _active_handle_id, camera, mm.position)
		if _edited_node:
			# Defer the gizmo redraw to once per frame — multiple motion events
			# can arrive per frame and _redraw() is expensive (array allocations,
			# cone ArrayMesh creation).  Non-drag paths still call update_gizmos()
			# directly for immediate feedback.
			_gizmo_plugin.schedule_gizmo_redraw(_edited_node)
		return 1
	# ── Handle press pending drag start ────────────────────────────────────────
	if _pressed_handle_id != -1:
		if _handle_press_pos.distance_squared_to(mm.position) > BOX_SELECT_DRAG_THRESHOLD_SQ:
			var started: bool = _gizmo_plugin.begin_drag(_edited_node, _pressed_handle_id)
			if started:
				_dragging_handle  = true
				_active_handle_id = _pressed_handle_id
				_pressed_handle_id = -1
				_gizmo_plugin.update_drag(_edited_node, _active_handle_id, camera, mm.position)
				if _edited_node:
					_gizmo_plugin.schedule_gizmo_redraw(_edited_node)
				return 1
			# begin_drag failed (no selection?) — discard the press
			_pressed_handle_id = -1
		return 1  # Still consuming during the ramp-up window
	# ── Box-select ────────────────────────────────────────────────────────────
	if not _box_select_started:
		# Idle motion — update handle hover highlight state.
		_update_hover(camera, mm.position)
		return 0
	_box_select_current = mm.position
	if not _box_select_active:
		if _box_select_start.distance_squared_to(_box_select_current) > BOX_SELECT_DRAG_THRESHOLD_SQ:
			_box_select_active = true
	if _box_select_active:
		update_overlays()
		return 1
	return 0


# ---------------------------------------------------------------------------
# Box select
# ---------------------------------------------------------------------------

## Return the normalised screen-space [Rect2] for the current box-select drag.
func _get_box_select_rect() -> Rect2:
	return Rect2(
		Vector2(
			min(_box_select_start.x, _box_select_current.x),
			min(_box_select_start.y, _box_select_current.y),
		),
		Vector2(
			abs(_box_select_current.x - _box_select_start.x),
			abs(_box_select_current.y - _box_select_start.y),
		),
	)


## Select all elements inside the current box-select rect and apply the
## result to the [SelectionManager] using the appropriate modifier logic.
func _finish_box_select(camera: Camera3D, additive: bool, toggle: bool) -> void:
	var sel: SelectionManager = _edited_node.selection
	var mode: SelectionManager.Mode = sel.get_mode()
	var gbm: GoBuildMesh = _edited_node.go_build_mesh
	if gbm == null:
		return

	var rect: Rect2 = _get_box_select_rect()
	var hit_indices: Array[int] = []
	match mode:
		SelectionManager.Mode.VERTEX:
			hit_indices = PickingHelper.find_vertices_in_rect(camera, rect, _edited_node, gbm)
		SelectionManager.Mode.EDGE:
			hit_indices = PickingHelper.find_edges_in_rect(camera, rect, _edited_node, gbm)
		SelectionManager.Mode.FACE:
			hit_indices = PickingHelper.find_faces_in_rect(camera, rect, _edited_node, gbm)

	# Plain drag (no modifier) clears first, then selects all hits.
	if not additive and not toggle:
		sel.clear()

	for idx: int in hit_indices:
		if toggle:
			match mode:
				SelectionManager.Mode.VERTEX: sel.toggle_vertex(idx)
				SelectionManager.Mode.EDGE:   sel.toggle_edge(idx)
				SelectionManager.Mode.FACE:   sel.toggle_face(idx)
		else:
			match mode:
				SelectionManager.Mode.VERTEX: sel.select_vertex(idx)
				SelectionManager.Mode.EDGE:   sel.select_edge(idx)
				SelectionManager.Mode.FACE:   sel.select_face(idx)


## Cancel and clean up any in-progress handle drag.
## Safe to call when no drag is active.
func _cancel_active_drag() -> void:
	if _dragging_handle and _gizmo_plugin != null and _edited_node != null:
		_gizmo_plugin.commit_drag(_edited_node, _active_handle_id, true)
	_dragging_handle   = false
	_active_handle_id  = -1
	_pressed_handle_id = -1
	if _gizmo_plugin != null:
		_gizmo_plugin.reset_drag_state()


## Cancel any in-progress box select and clear the overlay.
## Also triggers a gizmo redraw so the element overlay matches the new mode.
func _cancel_box_select() -> void:
	_box_select_started = false
	_box_select_active  = false
	if _edited_node:
		_edited_node.update_gizmos()
	update_overlays()


# ---------------------------------------------------------------------------
# Hover tracking (TODO F)
# ---------------------------------------------------------------------------

## Update the hovered-handle state from [param pos] during idle mouse motion.
##
## Calls [method _find_hovered_handle_id] and writes the result to
## [member GoBuildGizmoPlugin._hovered_handle_id].  When the value changes a
## deferred gizmo redraw is scheduled so the highlight appears at end-of-frame
## without triggering a per-event [method GoBuildGizmo._redraw].
## No-op when [member _gizmo_plugin] or [member _edited_node] is null.
func _update_hover(camera: Camera3D, pos: Vector2) -> void:
	if _gizmo_plugin == null:
		return
	var new_hover: int = _find_hovered_handle_id(camera, pos)
	if new_hover != _gizmo_plugin._hovered_handle_id:
		_gizmo_plugin._hovered_handle_id = new_hover
		if _edited_node != null:
			_gizmo_plugin.schedule_gizmo_redraw(_edited_node)


## Clear the hovered-handle state and schedule a gizmo redraw if needed.
##
## Called on mode change, node deselect, and node removal so a stale hover
## highlight is never left visible after the handles themselves disappear.
func _clear_hover() -> void:
	if _gizmo_plugin == null:
		return
	if _gizmo_plugin._hovered_handle_id == -1:
		return
	_gizmo_plugin._hovered_handle_id = -1
	if _edited_node != null:
		_gizmo_plugin.schedule_gizmo_redraw(_edited_node)

