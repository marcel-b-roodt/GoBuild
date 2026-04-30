## Shape-creation drawer for the GoBuild editor panel.
##
## Renders a button for every registered shape in [ShapeCreationCatalog].
## Shapes without parameters (e.g. Cube, Plane) insert immediately into the
## currently open scene with full undo/redo.  Shapes that support a parameter
## preview (e.g. Cylinder, Sphere) open [GoBuildShapePreview] first.
##
## Drop into any [VBoxContainer] with [method Node.add_child].  After adding:
##   - Call [method GoBuildDrawer.set_plugin] once.
##   - Starts open by default so the Create section is visible on launch.
@tool
class_name GoBuildCreateDrawer
extends GoBuildDrawer

# Self-preloads — dependency order.
const _SEL_MGR_SCRIPT_CR   := preload("res://addons/go_build/core/selection_manager.gd")
const _MESH_INST_SCRIPT_CR := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _DRAWER_SCRIPT_CR    := preload("res://addons/go_build/core/go_build_drawer.gd")
const _SHAPE_CATALOG_SCRIPT_CR := \
		preload("res://addons/go_build/mesh/generators/shape_creation_catalog.gd")
const _SHAPE_PREVIEW_SCRIPT_CR := \
		preload("res://addons/go_build/core/go_build_shape_preview.gd")

var _shape_preview: GoBuildShapePreview = null


func _ready() -> void:
	_setup_drawer("Create Shape", true)

	var grid := GridContainer.new()
	grid.columns = 2
	_content.add_child(grid)

	for shape_name: String in ShapeCreationCatalog.all_shapes():
		var btn := Button.new()
		btn.text = shape_name
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_shape_button_pressed.bind(shape_name))
		grid.add_child(btn)

	_shape_preview = GoBuildShapePreview.new()
	_shape_preview.accepted.connect(_on_shape_preview_accepted)
	_shape_preview.cancelled.connect(_on_shape_preview_cancelled)
	_content.add_child(_shape_preview)


# ---------------------------------------------------------------------------
# Internal handlers
# ---------------------------------------------------------------------------

func _on_shape_button_pressed(shape_name: String) -> void:
	if not ShapeCreationCatalog.supports_preview(shape_name):
		# Shapes without parameters insert immediately.
		if _shape_preview != null and _shape_preview.is_active():
			_shape_preview.cancel()
		var params := ShapeCreationCatalog.default_params(shape_name)
		_insert_shape(
			func() -> GoBuildMesh: return ShapeCreationCatalog.build_mesh(shape_name, params),
			ShapeCreationCatalog.node_name(shape_name))
		return

	if not Engine.is_editor_hint():
		return
	var scene_root: Node = EditorInterface.get_edited_scene_root()
	if scene_root == null:
		push_warning("GoBuild: no open scene — create or open a scene first")
		return
	_shape_preview.start(shape_name, scene_root)


func _on_shape_preview_accepted(shape_key: String, params: Dictionary) -> void:
	_insert_shape(
		func() -> GoBuildMesh: return ShapeCreationCatalog.build_mesh(shape_key, params),
		ShapeCreationCatalog.node_name(shape_key))


func _on_shape_preview_cancelled() -> void:
	pass  # Nothing extra needed; GoBuildShapePreview already cleaned up.


## Create a [GoBuildMeshInstance] populated by [param mesh_callable] and
## insert it at the root of the currently edited scene with full undo/redo.
func _insert_shape(mesh_callable: Callable, node_name: String) -> void:
	if not Engine.is_editor_hint():
		return
	if _plugin == null:
		push_warning("GoBuild: cannot insert shape — plugin reference not set")
		return

	var scene_root: Node = EditorInterface.get_edited_scene_root()
	if scene_root == null:
		push_warning("GoBuild: no open scene — create or open a scene first")
		return

	var node := GoBuildMeshInstance.new()
	node.name = node_name
	node.go_build_mesh = mesh_callable.call()
	# Seed slot 0 with the default GoBuild metre material so new shapes
	# render with the standard look rather than an unshaded surface.
	var default_mat: Material = load("res://addons/go_build/go_build_material.tres")
	if default_mat != null and node.go_build_mesh != null:
		node.go_build_mesh.material_slots = [default_mat]

	var ur: EditorUndoRedoManager = _plugin.get_undo_redo()
	ur.create_action("Insert " + node_name)
	ur.add_do_method(scene_root, "add_child", node, true)
	ur.add_do_method(node, "set_owner", scene_root)
	ur.add_undo_method(scene_root, "remove_child", node)
	ur.add_undo_reference(node)
	ur.commit_action()

	# Auto-select the new node so the user can immediately switch to an
	# edit mode without having to click in the scene tree.
	var es: EditorSelection = EditorInterface.get_selection()
	es.clear()
	es.add_node(node)
