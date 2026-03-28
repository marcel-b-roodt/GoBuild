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
func _make_visible(visible: bool) -> void:
	if _panel:
		_panel.visible = visible
	if not visible:
		_edited_node = null
		if _panel:
			_panel.set_target(null)

