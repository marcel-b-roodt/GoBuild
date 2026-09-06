## Viewport-anchored panel for structural generator parameters.
##
## Two modes:
##  - **Draw mode** (default): floats over the viewport during the 3-click
##    shape draw; edits flow into the draw controller's extra params.
##  - **Re-edit mode**: bound to an untouched [GoBuildMeshInstance] whose mesh
##    still matches its generator-pristine state; edits regenerate the mesh
##    from the stored shape params.  The node's transform is preserved.
##
## Deliberately a plain [PanelContainer], not a [PopupPanel]: popups close on
## outside clicks, which would swallow the draw flow's anchor clicks.
## Shown/hidden by [GoBuildCreateDrawer] alongside the dock strip.
@tool
class_name GoBuildDrawParamPopup
extends PanelContainer

signal edit_applied

# Self-preloads — dependency order.
const _CATALOG_SCRIPT := \
		preload("res://addons/go_build/mesh/generators/shape_creation_catalog.gd")
const _DRAW_CTRL_SCRIPT := \
		preload("res://addons/go_build/core/go_build_shape_draw_controller.gd")

const _POPUP_WIDTH: float = 180.0
const _POPUP_MARGIN: float = 8.0

var _draw_ctrl: GoBuildShapeDrawController = null

# Re-edit mode state.
var _edit_node: GoBuildMeshInstance = null
var _edit_shape_name: String = ""
var _edit_drawn: Vector3 = Vector3.ZERO
var _edit_params: Dictionary = {}
var _edit_undo_snapshot: Dictionary = {}


## Build one widget per structural param spec and anchor the panel to the
## top-right of [param vp_rect] (screen coords of the 3D viewport).
## Does nothing when the shape has no structural params.
func open(
		shape_name: String,
		draw_ctrl: GoBuildShapeDrawController,
		vp_rect: Rect2,
) -> void:
	_draw_ctrl = draw_ctrl
	for child: Node in get_children():
		child.queue_free()
	var specs: Array[Dictionary] = _CATALOG_SCRIPT.non_drawable_param_specs(shape_name)
	if specs.is_empty() or _draw_ctrl == null:
		hide()
		return
	var vbox := VBoxContainer.new()
	var title := Label.new()
	title.text = shape_name
	title.add_theme_font_size_override("font_size", 11)
	vbox.add_child(title)
	for spec: Dictionary in specs:
		var t: String = str(spec.get("type", ""))
		var key: String = str(spec.get("key", ""))
		var label_text: String = str(spec.get("label", key))
		if t == "bool":
			var chk := CheckBox.new()
			chk.text = label_text
			chk.add_theme_font_size_override("font_size", 10)
			chk.button_pressed = bool(_draw_ctrl.get_extra_params().get(key, false))
			chk.toggled.connect(_on_bool_changed.bind(key))
			vbox.add_child(chk)
		else:
			var row := HBoxContainer.new()
			var lbl := Label.new()
			lbl.text = label_text
			lbl.add_theme_font_size_override("font_size", 10)
			row.add_child(lbl)
			var spin := SpinBox.new()
			spin.min_value = float(spec.get("min", 0.0))
			spin.max_value = float(spec.get("max", 100.0))
			spin.step = float(spec.get("step", 1.0))
			spin.allow_greater = false
			spin.allow_lesser = false
			spin.rounded = t == "int"
			spin.value = float(_draw_ctrl.get_extra_params().get(key, 0))
			spin.custom_minimum_size.x = 80.0
			spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			spin.value_changed.connect(_on_spin_changed.bind(key, t == "int"))
			row.add_child(spin)
			vbox.add_child(row)
	add_child(vbox)
	size = Vector2(_POPUP_WIDTH, 0.0)
	position = Vector2(
			vp_rect.end.x - _POPUP_WIDTH - _POPUP_MARGIN,
			vp_rect.position.y + _POPUP_MARGIN)
	show()


func close() -> void:
	_draw_ctrl = null
	_edit_node = null
	_edit_shape_name = ""
	for child: Node in get_children():
		child.queue_free()
	hide()


## Open in re-edit mode for [param node]: infers the shape from the node name,
## stores draw params from the current AABB, and rebuilds on edits while
## [member GoBuildMeshInstance.is_pristine_state_valid] holds.
func open_for_edit(node: GoBuildMeshInstance, shape_name: String, vp_rect: Rect2) -> void:
	_draw_ctrl = null
	if node == null or node.go_build_mesh == null \
			or not node.is_pristine_state_valid():
		hide()
		return
	_edit_node = node
	_edit_shape_name = shape_name
	var aabb: AABB = node.go_build_mesh.compute_aabb()
	_edit_drawn = aabb.size
	_edit_params = node.go_build_mesh.get_meta("go_build_params", {})
	for child: Node in get_children():
		child.queue_free()
	var specs: Array[Dictionary] = _CATALOG_SCRIPT.non_drawable_param_specs(shape_name)
	if specs.is_empty():
		hide()
		return
	var vbox := VBoxContainer.new()
	var title := Label.new()
	title.text = "%s (editable)" % shape_name
	title.add_theme_font_size_override("font_size", 11)
	vbox.add_child(title)
	for spec: Dictionary in specs:
		var t: String = str(spec.get("type", ""))
		var key: String = str(spec.get("key", ""))
		var label_text: String = str(spec.get("label", key))
		if t == "bool":
			var chk := CheckBox.new()
			chk.text = label_text
			chk.add_theme_font_size_override("font_size", 10)
			chk.button_pressed = bool(_edit_params.get(key, false))
			chk.toggled.connect(_on_edit_bool_changed.bind(key))
			vbox.add_child(chk)
		else:
			var row := HBoxContainer.new()
			var lbl := Label.new()
			lbl.text = label_text
			lbl.add_theme_font_size_override("font_size", 10)
			row.add_child(lbl)
			var spin := SpinBox.new()
			spin.min_value = float(spec.get("min", 0.0))
			spin.max_value = float(spec.get("max", 100.0))
			spin.step = float(spec.get("step", 1.0))
			spin.allow_greater = false
			spin.allow_lesser = false
			spin.rounded = t == "int"
			spin.value = float(_edit_params.get(key, 0))
			spin.custom_minimum_size.x = 80.0
			spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			spin.value_changed.connect(_on_edit_spin_changed.bind(key, t == "int"))
			row.add_child(spin)
			vbox.add_child(row)
	add_child(vbox)
	size = Vector2(_POPUP_WIDTH, 0.0)
	position = Vector2(
			vp_rect.end.x - _POPUP_WIDTH - _POPUP_MARGIN,
			vp_rect.position.y + _POPUP_MARGIN)
	show()


## Regenerate the bound node's mesh from the stored shape + current params.
func _regenerate_edit_mesh() -> void:
	if _edit_node == null or not is_instance_valid(_edit_node):
		return
	if not _edit_node.is_pristine_state_valid():
		# User edited the mesh since opening — close re-edit mode.
		close()
		return
	var params: Dictionary = _edit_params.duplicate()
	params["width"] = _edit_drawn.x
	params["height"] = _edit_drawn.y
	params["depth"] = _edit_drawn.z
	var gbm := _edit_node.go_build_mesh
	var undo_snap: Dictionary = gbm.take_snapshot()
	gbm.restore_snapshot(_edit_node.get_pristine_state())
	var generated: GoBuildMesh = _CATALOG_SCRIPT.build_mesh(_edit_shape_name, params)
	if generated != null:
		gbm.vertices = generated.vertices
		gbm.faces = generated.faces
		gbm.material_slots = generated.material_slots
	gbm.rebuild_edges()
	_edit_node.bake()
	edit_applied.emit()


func _on_spin_changed(value: float, key: String, is_int: bool) -> void:
	if _draw_ctrl != null:
		_draw_ctrl.set_extra_param(key, int(round(value)) if is_int else value)


func _on_bool_changed(pressed: bool, key: String) -> void:
	if _draw_ctrl != null:
		_draw_ctrl.set_extra_param(key, pressed)


func _on_edit_spin_changed(value: float, key: String, is_int: bool) -> void:
	if _edit_node == null:
		return
	_edit_params[key] = int(round(value)) if is_int else value
	_regenerate_edit_mesh()


func _on_edit_bool_changed(pressed: bool, key: String) -> void:
	if _edit_node == null:
		return
	_edit_params[key] = pressed
	_regenerate_edit_mesh()