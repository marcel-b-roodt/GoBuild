## GoBuild EditorPlugin entry point.
##
## Registers the GoBuildMeshInstance custom type, adds the side-panel dock,
## and wires editor selection so the panel updates when a mesh is selected.
##
## This script MUST remain GDScript. See copilot-instructions § Editor plugin rules.
@tool
extends EditorPlugin

# ---------------------------------------------------------------------------
# Preloads — ORDER MATTERS.
# Each script is listed after the scripts it depends on so that class names
# are registered in the global registry before they are referenced by a later
# script in the chain.
# ---------------------------------------------------------------------------
const _SEL_MGR_SCRIPT      := preload("res://addons/go_build/core/selection_manager.gd")
const _MESH_INSTANCE_SCRIPT := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _GIZMO_PLUGIN_SCRIPT  := preload("res://addons/go_build/core/go_build_gizmo_plugin.gd")
const _PICKING_HELPER_SCRIPT := preload("res://addons/go_build/core/picking_helper.gd")
const _PANEL_SCRIPT         := preload("res://addons/go_build/core/go_build_panel.gd")
const _ICON                 := preload("res://icon.svg")

## Minimum squared pixel distance the mouse must travel before a left-drag
## is treated as a box select rather than a point click.
const BOX_SELECT_DRAG_THRESHOLD_SQ: float = 25.0  # 5 px

var _panel: GoBuildPanel = null
var _edited_node: GoBuildMeshInstance = null
var _gizmo_plugin: GoBuildGizmoPlugin = null

# Box-select tracking state.
var _box_select_started: bool  = false  # mouse button is currently held
var _box_select_active:  bool  = false  # drag threshold has been exceeded
var _box_select_start:   Vector2 = Vector2.ZERO
var _box_select_current: Vector2 = Vector2.ZERO


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

	if _edited_node != null:
		# Drive viewport redraws whenever selection or mode changes.
		_edited_node.selection.selection_changed.connect(_on_selection_changed)
		_edited_node.selection.mode_changed.connect(_on_mode_changed)
		# Clear our reference if the node is removed from the scene tree
		# (e.g. the user presses Delete in the scene panel).
		_edited_node.tree_exiting.connect(_on_edited_node_removed)

	if _panel:
		_panel.set_target(_edited_node)


## Called by the editor to show or hide our UI when selection changes.
## Note: _make_visible is the bottom-panel API. We use a dock control instead,
## so we deliberately do NOT hide _panel here — the dock tab must always show
## content. We only clear the selection when another node type is selected.
func _make_visible(visible: bool) -> void:
	if not visible:
		_disconnect_node_signals()
		_edited_node = null
		if _panel:
			_panel.set_target(null)


# ---------------------------------------------------------------------------
# Viewport input — keyboard shortcuts
# ---------------------------------------------------------------------------

## Intercept input in the 3D viewport.
##
## - Keys [b]1–4[/b]: switch edit mode (mirrors Blender muscle-memory).
## - [b]Left-click[/b]: pick vertex / edge / face depending on active mode.
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
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				return _handle_mouse_press(camera, mb)
			return _handle_mouse_release(camera, mb)
	elif event is InputEventMouseMotion:
		return _handle_mouse_motion(event as InputEventMouseMotion)
	return 0


## Draw the box-select rectangle overlay while a drag is in progress.
func _forward_3d_draw_over_viewport(overlay: Control) -> void:
	if not _box_select_active:
		return
	var rect: Rect2 = _get_box_select_rect()
	overlay.draw_rect(rect, Color(0.25, 0.45, 0.8, 0.15), true)
	overlay.draw_rect(rect, Color(0.5, 0.7, 1.0, 0.85), false)


## Handle keyboard mode-switch shortcuts (1–4). Returns 1 if consumed, 0 if not.
func _handle_keyboard(event: InputEvent) -> int:
	if not (event is InputEventKey):
		return 0
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return 0
	match key.keycode:
		KEY_1: _set_mode(SelectionManager.Mode.OBJECT)
		KEY_2: _set_mode(SelectionManager.Mode.VERTEX)
		KEY_3: _set_mode(SelectionManager.Mode.EDGE)
		KEY_4: _set_mode(SelectionManager.Mode.FACE)
		_:     return 0
	return 1


func _set_mode(mode: SelectionManager.Mode) -> void:
	if _edited_node == null:
		return
	_edited_node.selection.set_mode(mode)
	# The panel listens to selection.mode_changed, so it updates automatically.


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
	update_overlays()


## Triggered when the edited node's [SelectionManager] emits
## [signal SelectionManager.mode_changed].
func _on_mode_changed(_mode: SelectionManager.Mode) -> void:
	_cancel_box_select()


## Triggered when the currently edited node exits the scene tree
## (user deleted it or unloaded the scene).  Clears stale editing state.
func _on_edited_node_removed() -> void:
	# At this point _edited_node is still valid (tree_exiting fires before free),
	# but we clear it so the panel stops referencing a dead node.
	_box_select_started = false
	_box_select_active  = false
	_edited_node = null
	if _panel:
		_panel.set_target(null)
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
## Begins tracking a potential box select; consumes the event so the editor
## does not deselect the [GoBuildMeshInstance].
func _handle_mouse_press(_camera: Camera3D, mb: InputEventMouseButton) -> int:
	var mode: SelectionManager.Mode = _edited_node.selection.get_mode()
	# In object mode let Godot handle its own node-selection click.
	if mode == SelectionManager.Mode.OBJECT:
		return 0
	_box_select_started = true
	_box_select_active  = false
	_box_select_start   = mb.position
	_box_select_current = mb.position
	return 1


## Handle a left-mouse-button release.
## Completes a box select if a drag was in progress; otherwise delegates to
## the existing point-pick logic.
func _handle_mouse_release(camera: Camera3D, mb: InputEventMouseButton) -> int:
	if not _box_select_started:
		return 0
	_box_select_started = false
	if _box_select_active:
		_box_select_active = false
		update_overlays()
		_finish_box_select(camera, mb.shift_pressed, mb.ctrl_pressed)
		return 1
	# No significant drag — treat as a plain point pick at the press position.
	return _handle_pick(camera, _box_select_start, mb.shift_pressed, mb.ctrl_pressed)


## Track mouse movement. Activates the box select once the drag exceeds the
## pixel threshold; redraws the overlay every frame while active.
func _handle_mouse_motion(mm: InputEventMouseMotion) -> int:
	if not _box_select_started:
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


## Cancel any in-progress box select and clear the overlay.
func _cancel_box_select() -> void:
	_box_select_started = false
	_box_select_active  = false
	update_overlays()

