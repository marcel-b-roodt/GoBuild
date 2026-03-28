## GoBuild editor side-panel dock.
##
## Displayed in the bottom-left dock slot while the plugin is active.
## Shows the currently selected [GoBuildMeshInstance] and its mesh statistics.
## Future stages will add toolbar buttons for all modelling operations.
@tool
class_name GoBuildPanel
extends VBoxContainer

const _VERSION := "0.1.0"

var _status_label: Label
var _stats_label: Label
var _target: GoBuildMeshInstance = null
var _plugin: EditorPlugin = null


## Called by the owning [EditorPlugin] immediately after the panel is docked.
## Required so [method _insert_shape] can access [method EditorPlugin.get_undo_redo].
func set_plugin(plugin: EditorPlugin) -> void:
	_plugin = plugin


func _ready() -> void:
	name = "GoBuild"
	custom_minimum_size = Vector2(180, 0)

	# ── Header ──────────────────────────────────────────────────────────
	var header := Label.new()
	header.text = "GoBuild  v" + _VERSION
	header.add_theme_font_size_override("font_size", 13)
	add_child(header)

	add_child(HSeparator.new())

	# ── Create Shape ─────────────────────────────────────────────────────
	var create_label := Label.new()
	create_label.text = "── Create Shape ──"
	create_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	create_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	create_label.add_theme_font_size_override("font_size", 11)
	add_child(create_label)

	var grid := GridContainer.new()
	grid.columns = 2
	add_child(grid)

	var shapes: Array = [
		["Cube",      func(): return CubeGenerator.generate()],
		["Plane",     func(): return PlaneGenerator.generate()],
		["Cylinder",  func(): return CylinderGenerator.generate()],
		["Sphere",    func(): return SphereGenerator.generate()],
		["Cone",      func(): return ConeGenerator.generate()],
		["Torus",     func(): return TorusGenerator.generate()],
		["Staircase", func(): return StaircaseGenerator.generate()],
		["Arch",      func(): return ArchGenerator.generate()],
	]
	for shape_data: Array in shapes:
		var btn := Button.new()
		btn.text = shape_data[0]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_insert_shape.bind(shape_data[1], "GoBuild" + shape_data[0]))
		grid.add_child(btn)

	add_child(HSeparator.new())

	# ── Status ───────────────────────────────────────────────────────────
	_status_label = Label.new()
	_status_label.text = "No mesh selected."
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_ONLY
	add_child(_status_label)

	# ── Stats ────────────────────────────────────────────────────────────
	_stats_label = Label.new()
	_stats_label.add_theme_color_override("font_color",
			Color(0.65, 0.65, 0.65))
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_ONLY
	add_child(_stats_label)

	add_child(HSeparator.new())

	# ── Hint ─────────────────────────────────────────────────────────────
	var hint := Label.new()
	hint.text = "Select a GoBuildMeshInstance\nnode to begin editing."
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_ONLY
	hint.add_theme_font_size_override("font_size", 11)
	add_child(hint)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Update the panel to reflect [param target].
## Pass [code]null[/code] to clear the selection display.
func set_target(target: GoBuildMeshInstance) -> void:
	_target = target
	_refresh()


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _refresh() -> void:
	if _target == null or _target.go_build_mesh == null:
		_status_label.text = "No mesh selected."
		_stats_label.text = ""
		return

	var gbm: GoBuildMesh = _target.go_build_mesh
	_status_label.text = "Editing:  %s" % _target.name

	var vert_count: int = gbm.vertices.size()
	var face_count: int = gbm.faces.size()
	var edge_count: int = gbm.edges.size()
	_stats_label.text = "Verts: %d   Faces: %d   Edges: %d" % [
		vert_count, face_count, edge_count,
	]


## Create a [GoBuildMeshInstance] populated by [param mesh_callable] and
## insert it at the root of the currently edited scene with full undo/redo.
func _insert_shape(mesh_callable: Callable, node_name: String) -> void:
	if not Engine.is_editor_hint():
		return
	if not _plugin:
		push_warning("GoBuild: cannot insert shape — plugin reference not set")
		return

	var scene_root: Node = EditorInterface.get_edited_scene_root()
	if not scene_root:
		push_warning("GoBuild: no open scene — create or open a scene first")
		return

	var node := GoBuildMeshInstance.new()
	node.name = node_name
	node.go_build_mesh = mesh_callable.call()

	var ur: EditorUndoRedoManager = _plugin.get_undo_redo()
	ur.create_action("Insert " + node_name)
	ur.add_do_method(scene_root, "add_child", node, true)
	ur.add_do_method(node, "set_owner", scene_root)
	ur.add_undo_method(scene_root, "remove_child", node)
	ur.add_undo_reference(node)
	ur.commit_action()


