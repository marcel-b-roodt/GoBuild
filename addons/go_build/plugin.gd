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
const _PANEL_SCRIPT         := preload("res://addons/go_build/core/go_build_panel.gd")
const _ICON                 := preload("res://icon.svg")

var _panel: GoBuildPanel = null
var _edited_node: GoBuildMeshInstance = null
var _gizmo_plugin: GoBuildGizmoPlugin = null


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

## Intercept keyboard input in the 3D viewport.
## Keys 1–4 switch the active editing mode; mirrors Blender muscle-memory.
## Returns a non-zero int to consume the event and prevent other handlers
## (e.g. Godot's own viewport shortcuts) from reacting.
func _forward_3d_gui_input(_camera: Camera3D, event: InputEvent) -> int:
	if _edited_node == null:
		return 0

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_set_mode(SelectionManager.Mode.OBJECT)
				return 1
			KEY_2:
				_set_mode(SelectionManager.Mode.VERTEX)
				return 1
			KEY_3:
				_set_mode(SelectionManager.Mode.EDGE)
				return 1
			KEY_4:
				_set_mode(SelectionManager.Mode.FACE)
				return 1

	return 0


func _set_mode(mode: SelectionManager.Mode) -> void:
	if _edited_node == null:
		return
	_edited_node.selection.set_mode(mode)
	# The panel listens to selection.mode_changed, so it updates automatically.


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
	update_overlays()


## Triggered when the currently edited node exits the scene tree
## (user deleted it or unloaded the scene).  Clears stale editing state.
func _on_edited_node_removed() -> void:
	# At this point _edited_node is still valid (tree_exiting fires before free),
	# but we clear it so the panel stops referencing a dead node.
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
