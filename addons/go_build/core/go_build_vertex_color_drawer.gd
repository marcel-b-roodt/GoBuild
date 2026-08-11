## Vertex-colour operations drawer for the GoBuild editor panel.
##
## Hosts colour picker, channel toggles (R/G/B/A), blend mode, and Fill /
## Fill All buttons.  Works in Face mode (selected faces) and Object mode (all
## faces).
@tool
class_name GoBuildVertexColorDrawer
extends GoBuildDrawer

# Self-preloads — dependency order.
const _MESH_SCRIPT_VC        := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _SEL_MGR_SCRIPT_VC     := preload("res://addons/go_build/core/selection_manager.gd")
const _MESH_INST_SCRIPT_VC   := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _VC_OP_SCRIPT_VC       := \
		preload("res://addons/go_build/mesh/operations/vertex_color_operation.gd")

var _color_picker: ColorPickerButton = null
var _channel_r: CheckBox = null
var _channel_g: CheckBox = null
var _channel_b: CheckBox = null
var _channel_a: CheckBox = null
var _blend_mode: OptionButton = null
var _fill_btn: Button = null
var _fill_all_btn: Button = null


func _ready() -> void:
	_setup_drawer("Vertex Color", false)

	# ── Colour picker ────────────────────────────────────────────────────
	var color_row := HBoxContainer.new()
	var color_label := Label.new()
	color_label.text = "Color:"
	color_label.add_theme_font_size_override("font_size", 11)
	color_row.add_child(color_label)

	_color_picker = ColorPickerButton.new()
	_color_picker.color = Color.WHITE
	_color_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_row.add_child(_color_picker)
	_content.add_child(color_row)

	# ── Channel toggles ──────────────────────────────────────────────────
	var channel_label := Label.new()
	channel_label.text = "Channels:"
	channel_label.add_theme_font_size_override("font_size", 11)
	_content.add_child(channel_label)

	var channel_row := HBoxContainer.new()
	_channel_r = CheckBox.new()
	_channel_r.text = "R"
	_channel_r.button_pressed = true
	channel_row.add_child(_channel_r)

	_channel_g = CheckBox.new()
	_channel_g.text = "G"
	_channel_g.button_pressed = true
	channel_row.add_child(_channel_g)

	_channel_b = CheckBox.new()
	_channel_b.text = "B"
	_channel_b.button_pressed = true
	channel_row.add_child(_channel_b)

	_channel_a = CheckBox.new()
	_channel_a.text = "A"
	_channel_a.button_pressed = false
	channel_row.add_child(_channel_a)
	_content.add_child(channel_row)

	# ── Blend mode ───────────────────────────────────────────────────────
	var blend_row := HBoxContainer.new()
	var blend_label := Label.new()
	blend_label.text = "Blend:"
	blend_label.add_theme_font_size_override("font_size", 11)
	blend_row.add_child(blend_label)

	_blend_mode = OptionButton.new()
	_blend_mode.add_item("Mix", VertexColorOperation.BlendMode.MIX)
	_blend_mode.add_item("Add", VertexColorOperation.BlendMode.ADD)
	_blend_mode.add_item("Subtract", VertexColorOperation.BlendMode.SUBTRACT)
	_blend_mode.add_item("Multiply", VertexColorOperation.BlendMode.MULTIPLY)
	_blend_mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	blend_row.add_child(_blend_mode)
	_content.add_child(blend_row)

	# ── Fill buttons ─────────────────────────────────────────────────────
	_fill_btn = _op_button("Fill",
		"Paint selected face vertices with the chosen colour, channels, and blend mode.")
	_fill_btn.pressed.connect(_on_fill_pressed)
	_content.add_child(_fill_btn)
	_register_op(_fill_btn, _cond_face_selected)

	_fill_all_btn = _op_button("Fill All",
		"Paint every vertex in the mesh with the chosen colour, channels, and blend mode.")
	_fill_all_btn.pressed.connect(_on_fill_all_pressed)
	_content.add_child(_fill_all_btn)
	_register_op(_fill_all_btn, _cond_has_mesh)


func _channel_mask() -> int:
	var mask: int = 0
	if _channel_r.button_pressed:
		mask |= VertexColorOperation.CHANNEL_R
	if _channel_g.button_pressed:
		mask |= VertexColorOperation.CHANNEL_G
	if _channel_b.button_pressed:
		mask |= VertexColorOperation.CHANNEL_B
	if _channel_a.button_pressed:
		mask |= VertexColorOperation.CHANNEL_A
	if mask == 0:
		mask = VertexColorOperation.CHANNEL_ALL
	return mask


func _on_fill_pressed() -> void:
	if _target == null or _plugin == null or _target.go_build_mesh == null:
		return
	var faces: Array[int] = []
	if _target.selection.get_mode() == SelectionManager.Mode.FACE:
		var sel: Array[int] = _target.selection.get_selected_faces()
		if sel.is_empty():
			return
		faces.assign(sel)
	else:
		return
	var color: Color = _color_picker.color
	var blend: int = _blend_mode.get_selected_id()
	var mask: int = _channel_mask()
	_run_op(
		"Fill Vertex Color",
		func(): VertexColorOperation.fill_faces(
			_target.go_build_mesh, faces, color, blend, mask),
		false,
	)


func _on_fill_all_pressed() -> void:
	if _target == null or _plugin == null or _target.go_build_mesh == null:
		return
	var color: Color = _color_picker.color
	var blend: int = _blend_mode.get_selected_id()
	var mask: int = _channel_mask()
	_run_op(
		"Fill All Vertex Colors",
		func(): VertexColorOperation.fill_all(
			_target.go_build_mesh, color, blend, mask),
		false,
	)


# ---------------------------------------------------------------------------
# Conditions
# ---------------------------------------------------------------------------

func _cond_face_selected() -> bool:
	return _target != null \
		and _target.selection.get_mode() == SelectionManager.Mode.FACE \
		and not _target.selection.get_selected_faces().is_empty()


func _cond_has_mesh() -> bool:
	return _target != null and _target.go_build_mesh != null