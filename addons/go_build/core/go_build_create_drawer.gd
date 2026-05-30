## Shape-creation drawer for the GoBuild editor panel.
##
## Renders a button for every registered shape in [ShapeCreationCatalog].
## Shapes without parameters (e.g. Cube, Plane) insert immediately into the
## currently open scene with full undo/redo.  Shapes that support a parameter
## preview (e.g. Cylinder, Sphere) open [GoBuildShapePreview] first.
##
## [method insert_shape] is the single canonical path for inserting a new
## [GoBuildMeshInstance] — all callers (panel buttons, context menu, preview
## acceptance) go through it.
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
const _SHAPE_PLACEMENT_SCRIPT_CR := \
		preload("res://addons/go_build/core/shape_placement.gd")

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
	if _shape_preview != null and _shape_preview.is_active():
		_shape_preview.cancel()
	var placement := _viewport_center_placement()
	if placement != null:
		ShapePlacement.apply_bottom_offset(placement, shape_name)
	var edited: GoBuildMeshInstance = _get_edited_instance()
	var scene_root: Node = EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return

	if not ShapeCreationCatalog.supports_preview(shape_name):
		var resolved: Dictionary = ShapePlacement.resolve_parent_and_position(
				placement, edited, scene_root)
		insert_shape(
			func() -> GoBuildMesh: return ShapeCreationCatalog.build_mesh(
					shape_name, ShapeCreationCatalog.default_params(shape_name)),
			ShapeCreationCatalog.node_name(shape_name),
			resolved["parent"],
			resolved["local_pos"])
		return

	if not Engine.is_editor_hint():
		return
	_shape_preview.start_with_placement(shape_name, scene_root, placement, edited)


func _on_shape_preview_accepted(
		shape_key: String,
		params: Dictionary,
		parent: Node,
		local_pos: Vector3,
) -> void:
	insert_shape(
		func() -> GoBuildMesh: return ShapeCreationCatalog.build_mesh(shape_key, params),
		ShapeCreationCatalog.node_name(shape_key),
		parent,
		local_pos)


func _on_shape_preview_cancelled() -> void:
	pass


## Create a [GoBuildMeshInstance] populated by [param mesh_callable] and
## insert it into the scene with full undo/redo and auto-selection.
##
## This is the single canonical insertion path used by all callers:
## panel buttons, context menu instant shapes, and preview acceptance.
##
## [param parent] is the parent [Node]; if null, scene root is used.
## [param local_pos] is the position.  If [param parent] is the scene root,
## this is treated as world-space via [code]global_position[/code]; otherwise
## it is local to [param parent].
func insert_shape(
		mesh_callable: Callable,
		node_name: String,
		parent: Node = null,
		local_pos: Vector3 = Vector3.ZERO,
) -> void:
	if not Engine.is_editor_hint():
		return
	if _plugin == null:
		push_warning("GoBuild: cannot insert shape — plugin reference not set")
		return

	var scene_root: Node = EditorInterface.get_edited_scene_root()
	if scene_root == null:
		push_warning("GoBuild: no open scene — create or open a scene first")
		return

	if parent == null:
		parent = scene_root

	var node := GoBuildMeshInstance.new()
	node.name = node_name
	node.go_build_mesh = mesh_callable.call()
	if parent == scene_root:
		node.global_position = local_pos
	else:
		node.position = local_pos
	var default_mat: Material = load("res://addons/go_build/go_build_material.tres")
	if default_mat != null and node.go_build_mesh != null:
		node.go_build_mesh.material_slots = [default_mat]

	var ur: EditorUndoRedoManager = _plugin.get_undo_redo()
	ur.create_action("Insert " + node_name)
	ur.add_do_method(parent, "add_child", node, true)
	ur.add_do_method(node, "set_owner", scene_root)
	ur.add_undo_method(parent, "remove_child", node)
	ur.add_undo_reference(node)
	ur.commit_action()

	# Auto-select the new node so the user can immediately switch to an
	# edit mode without having to click in the scene tree.
	var es: EditorSelection = EditorInterface.get_selection()
	es.clear()
	es.add_node(node)


## Return the currently edited [GoBuildMeshInstance] from the editor selection,
## or null if none is selected.
func _get_edited_instance() -> GoBuildMeshInstance:
	if _plugin == null:
		return null
	var sel: EditorSelection = EditorInterface.get_selection()
	if sel.get_selected_nodes().is_empty():
		return null
	var first: Node = sel.get_selected_nodes()[0]
	if first is GoBuildMeshInstance:
		return first as GoBuildMeshInstance
	return null


## Compute a placement result at the centre of the editor 3D viewport.
## Returns null if there is no camera or scene.
func _viewport_center_placement() -> RefCounted:
	var sv: SubViewport = EditorInterface.get_editor_viewport_3d(0)
	if sv == null:
		return null
	var camera: Camera3D = sv.get_camera_3d()
	if camera == null:
		return null
	var center: Vector2 = Vector2(sv.size.x * 0.5, sv.size.y * 0.5)
	var edited: GoBuildMeshInstance = _get_edited_instance()
	return ShapePlacement.find_placement(camera, center, edited)


## Start a shape preview positioned at the placement result's world position.
## Called from the context menu when a preview-supporting shape is chosen.
func start_shape_preview_at(
		shape_name: String,
		placement: RefCounted,
		edited_node: GoBuildMeshInstance,
) -> void:
	if not Engine.is_editor_hint():
		return
	var scene_root: Node = EditorInterface.get_edited_scene_root()
	if scene_root == null:
		push_warning("GoBuild: no open scene — create or open a scene first")
		return
	if _shape_preview != null and _shape_preview.is_active():
		_shape_preview.cancel()
	_shape_preview.start_with_placement(shape_name, scene_root, placement, edited_node)