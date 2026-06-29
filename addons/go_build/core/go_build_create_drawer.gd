## Shape-creation drawer for the GoBuild editor panel.
##
## Renders a button for every registered shape in [ShapeCreationCatalog].
## All shapes now launch the interactive 3-click draw controller which lets
## the user draw the shape's bounding box directly in the viewport.
##
## [method insert_shape] remains the single canonical path for inserting a
## new [GoBuildMeshInstance] — the draw controller commits through it.
@tool
class_name GoBuildCreateDrawer
extends GoBuildDrawer

# Self-preloads — dependency order.
const _SEL_MGR_SCRIPT_CR   := preload("res://addons/go_build/core/selection_manager.gd")
const _MESH_INST_SCRIPT_CR := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _DRAWER_SCRIPT_CR    := preload("res://addons/go_build/core/go_build_drawer.gd")
const _SHAPE_CATALOG_SCRIPT_CR := \
		preload("res://addons/go_build/mesh/generators/shape_creation_catalog.gd")
const _SHAPE_PLACEMENT_SCRIPT_CR := \
		preload("res://addons/go_build/core/shape_placement.gd")
const _DRAW_CTRL_SCRIPT_CR := \
		preload("res://addons/go_build/core/go_build_shape_draw_controller.gd")

var _align_to_surface_cb: CheckBox = null
var _parent_mode_option: OptionButton = null
var _param_strip: VBoxContainer = null
var _param_controls: Dictionary = {}


func _ready() -> void:
	_setup_drawer("Create Shape", true)

	var align_hb := HBoxContainer.new()
	_align_to_surface_cb = CheckBox.new()
	_align_to_surface_cb.text = "Align to Surface"
	_align_to_surface_cb.button_pressed = true
	_align_to_surface_cb.tooltip_text = \
			"Rotate new shapes so Y aligns with the surface normal"
	_align_to_surface_cb.toggled.connect(_on_align_to_surface_toggled)
	align_hb.add_child(_align_to_surface_cb)
	_content.add_child(align_hb)

	var parent_hb := HBoxContainer.new()
	var parent_lbl := Label.new()
	parent_lbl.text = "Insert as:"
	parent_lbl.add_theme_font_size_override("font_size", 11)
	parent_hb.add_child(parent_lbl)
	_parent_mode_option = OptionButton.new()
	_parent_mode_option.add_item("Child", GoBuildShapeDrawController.ParentMode.CHILD)
	_parent_mode_option.add_item("Sibling", GoBuildShapeDrawController.ParentMode.SIBLING)
	_parent_mode_option.add_item("Root", GoBuildShapeDrawController.ParentMode.ROOT)
	_parent_mode_option.tooltip_text = \
			"Child: under hit surface | Sibling: same parent | Root: scene root"
	_parent_mode_option.item_selected.connect(_on_parent_mode_selected)
	parent_hb.add_child(_parent_mode_option)
	_content.add_child(parent_hb)

	var grid := GridContainer.new()
	grid.columns = 2
	_content.add_child(grid)

	for shape_name: String in ShapeCreationCatalog.all_shapes():
		var btn := Button.new()
		btn.text = shape_name
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_shape_button_pressed.bind(shape_name))
		grid.add_child(btn)

	_param_strip = VBoxContainer.new()
	_param_strip.visible = false
	_content.add_child(_param_strip)


# ---------------------------------------------------------------------------
# Shape button handler
# ---------------------------------------------------------------------------

func _on_shape_button_pressed(shape_name: String) -> void:
	if not Engine.is_editor_hint():
		return
	if _plugin == null:
		return
	var align_to_surface: bool = \
			_align_to_surface_cb.button_pressed if _align_to_surface_cb != null else true
	var parent_mode: int = \
			_parent_mode_option.get_selected_id() if _parent_mode_option != null \
			else GoBuildShapeDrawController.ParentMode.CHILD
	var sv: SubViewport = EditorInterface.get_editor_viewport_3d(0)
	var camera: Camera3D = null
	var screen_pos: Vector2 = Vector2.ZERO
	if sv != null:
		camera = sv.get_camera_3d()
		screen_pos = Vector2(sv.size.x * 0.5, sv.size.y * 0.5)
	var edited: GoBuildMeshInstance = _get_edited_instance()
	var draw_ctrl: GoBuildShapeDrawController = _plugin.get("_shape_draw_controller")
	if draw_ctrl == null:
		return
	draw_ctrl.start(shape_name, _plugin, align_to_surface, camera, screen_pos, edited)
	draw_ctrl.set_parent_mode(parent_mode)
	_show_param_strip(shape_name, draw_ctrl)


func _on_align_to_surface_toggled(pressed: bool) -> void:
	if _plugin == null:
		return
	var draw_ctrl: GoBuildShapeDrawController = _plugin.get("_shape_draw_controller")
	if draw_ctrl == null or not draw_ctrl.is_active():
		return
	draw_ctrl.set_align_to_surface(pressed)


func _on_parent_mode_selected(_index: int) -> void:
	if _plugin == null:
		return
	var draw_ctrl: GoBuildShapeDrawController = _plugin.get("_shape_draw_controller")
	if draw_ctrl == null or not draw_ctrl.is_active():
		return
	draw_ctrl.set_parent_mode(_parent_mode_option.get_selected_id())


# ---------------------------------------------------------------------------
# Parameter strip for non-drawable structural params
# ---------------------------------------------------------------------------

func _show_param_strip(shape_name: String, draw_ctrl: GoBuildShapeDrawController) -> void:
	_clear_param_strip()
	var specs: Array[Dictionary] = ShapeCreationCatalog.non_drawable_param_specs(shape_name)
	if specs.is_empty():
		_param_strip.visible = false
		return
	var bool_row := HBoxContainer.new()
	for spec: Dictionary in specs:
		var t: String = str(spec.get("type", ""))
		var key: String = str(spec.get("key", ""))
		var label_text: String = str(spec.get("label", key))
		if t == "bool":
			var chk := CheckBox.new()
			chk.text = label_text
			var default_val = draw_ctrl.get_extra_params().get(key, spec.get("default", false))
			chk.button_pressed = bool(default_val)
			chk.toggled.connect(_on_param_changed.bind(key, draw_ctrl, true))
			bool_row.add_child(chk)
			_param_controls[key] = chk
		else:
			var row := HBoxContainer.new()
			var lbl := Label.new()
			lbl.text = label_text
			lbl.add_theme_font_size_override("font_size", 11)
			row.add_child(lbl)
			var spin := SpinBox.new()
			spin.min_value = float(spec.get("min", 0.0))
			spin.max_value = float(spec.get("max", 100.0))
			spin.step = float(spec.get("step", 1.0))
			spin.allow_greater = false
			spin.allow_lesser = false
			spin.rounded = t == "int"
			var default_val = draw_ctrl.get_extra_params().get(key, spec.get("default", 0))
			spin.value = float(default_val)
			spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			spin.value_changed.connect(_on_param_spin_changed.bind(key, draw_ctrl, t == "int"))
			row.add_child(spin)
			_param_strip.add_child(row)
			_param_controls[key] = spin
	if bool_row.get_child_count() > 0:
		_param_strip.add_child(bool_row)
	_param_strip.visible = true


func _clear_param_strip() -> void:
	for child: Node in _param_strip.get_children():
		child.queue_free()
	_param_controls.clear()
	_param_strip.visible = false


func _on_param_changed(
		value: Variant,
		key: String,
		draw_ctrl: GoBuildShapeDrawController,
		_is_bool: bool,
) -> void:
	draw_ctrl.set_extra_param(key, value)


func _on_param_spin_changed(
		value: float,
		key: String,
		draw_ctrl: GoBuildShapeDrawController,
		is_int: bool,
) -> void:
	draw_ctrl.set_extra_param(key, int(round(value)) if is_int else value)


func hide_param_strip() -> void:
	_clear_param_strip()


# ---------------------------------------------------------------------------
# Canonical insertion path
# ---------------------------------------------------------------------------

## Create a [GoBuildMeshInstance] populated by [param mesh_callable] and
## insert it into the scene with full undo/redo and auto-selection.
##
## This is the single canonical insertion path used by all callers:
## the draw controller, and any future programmatic callers.
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
		local_basis: Basis = Basis.IDENTITY,
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
	if not local_basis.is_equal_approx(Basis.IDENTITY):
		node.basis = local_basis
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

	var es: EditorSelection = EditorInterface.get_selection()
	es.clear()
	es.add_node(node)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

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


## Return whether the "Align to Surface" toggle is checked.
func is_align_to_surface() -> bool:
	if _align_to_surface_cb == null:
		return true
	return _align_to_surface_cb.button_pressed


## Start the interactive shape draw positioned at the viewport center.
## Called from the context menu "Add Shape" path.
func start_shape_draw_at(
		shape_name: String,
		camera: Camera3D,
		screen_pos: Vector2,
		edited_node: GoBuildMeshInstance,
) -> void:
	if not Engine.is_editor_hint():
		return
	if _plugin == null:
		return
	var align_to_surface: bool = is_align_to_surface()
	var parent_mode: int = \
			_parent_mode_option.get_selected_id() if _parent_mode_option != null \
			else GoBuildShapeDrawController.ParentMode.CHILD
	var draw_ctrl: GoBuildShapeDrawController = _plugin.get("_shape_draw_controller")
	if draw_ctrl == null:
		return
	draw_ctrl.start_at_position(shape_name, _plugin, align_to_surface, camera,
			screen_pos, edited_node)
	draw_ctrl.set_parent_mode(parent_mode)
	_show_param_strip(shape_name, draw_ctrl)