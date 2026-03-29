## GoBuild EditorPlugin entry point.
##
## Registers the GoBuildMeshInstance custom type, adds the side-panel dock,
## and wires editor selection so the panel updates when a mesh is selected.
##
## This script MUST remain GDScript. See copilot-instructions § Editor plugin rules.
@tool
extends EditorPlugin

const _MESH_INSTANCE_SCRIPT := preload(
		"res://addons/go_build/core/go_build_mesh_instance.gd")
const _PANEL_SCRIPT := preload(
		"res://addons/go_build/core/go_build_panel.gd")
const _ICON := preload("res://icon.svg")

var _panel: GoBuildPanel = null
var _edited_node: GoBuildMeshInstance = null


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


func _exit_tree() -> void:
	remove_custom_type("GoBuildMeshInstance")

	if _panel:
		remove_control_from_docks(_panel)
		_panel.queue_free()
		_panel = null

	_edited_node = null


# ---------------------------------------------------------------------------
# Selection / editing
# ---------------------------------------------------------------------------

## Returns true when a [GoBuildMeshInstance] is selected so the plugin
## receives [method _edit] and [method _make_visible] notifications.
func _handles(object: Object) -> bool:
	return object is GoBuildMeshInstance


## Called by the editor when a [GoBuildMeshInstance] is selected.
func _edit(object: Object) -> void:
	_edited_node = object as GoBuildMeshInstance
	if _panel:
		_panel.set_target(_edited_node)


## Called by the editor to show or hide our UI when selection changes.
## Note: _make_visible is the bottom-panel API. We use a dock control instead,
## so we deliberately do NOT hide _panel here — the dock tab must always show
## content. We only clear the selection when another node type is selected.
func _make_visible(visible: bool) -> void:
	if not visible:
		_edited_node = null
		if _panel:
			_panel.set_target(null)


# ---------------------------------------------------------------------------
# Viewport input — keyboard shortcuts
# ---------------------------------------------------------------------------

## Intercept keyboard input in the 3D viewport.
## Keys 1–4 switch the active editing mode; mirrors Blender muscle-memory.
## Returns [code]true[/code] to consume the event and prevent other handlers
## (e.g. Godot's own viewport shortcuts) from reacting.
func _forward_3d_gui_input(_camera: Camera3D, event: InputEvent) -> bool:
	if _edited_node == null:
		return false

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_set_mode(SelectionManager.Mode.OBJECT)
				return true
			KEY_2:
				_set_mode(SelectionManager.Mode.VERTEX)
				return true
			KEY_3:
				_set_mode(SelectionManager.Mode.EDGE)
				return true
			KEY_4:
				_set_mode(SelectionManager.Mode.FACE)
				return true

	return false


func _set_mode(mode: SelectionManager.Mode) -> void:
	if _edited_node == null:
		return
	_edited_node.selection.set_mode(mode)
	# The panel listens to selection.mode_changed, so it updates automatically.


