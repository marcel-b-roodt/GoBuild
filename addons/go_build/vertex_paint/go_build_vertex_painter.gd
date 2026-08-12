## Dock panel for vertex colour painting on [GoBuildMesh] instances.
##
## Separate from the main GoBuild panel so the paint workflow has its own
## dedicated space.  Registered as a bottom dock by [GoBuildPlugin].
##
## Contains:
## - Colour picker
## - Channel mask toggles (R, G, B, A)
## - Blend mode dropdown (Mix, Add, Subtract, Multiply)
## - Brush radius and strength sliders (for future brush painting)
## - Fill Selected / Fill All batch buttons
## - Eyedropper button (placeholder for future viewport interaction)
@tool
class_name GoBuildVertexPainter
extends VBoxContainer

# Self-preloads — compile-time type references.
const _MESH_SCRIPT_VP        := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _SEL_MGR_SCRIPT_VP     := preload("res://addons/go_build/core/selection_manager.gd")
const _MESH_INST_SCRIPT_VP   := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _VC_OP_SCRIPT_VP       := \
		preload("res://addons/go_build/mesh/operations/vertex_color_operation.gd")

var _target: GoBuildMeshInstance = null
var _plugin: EditorPlugin = null

# ── Widgets ──────────────────────────────────────────────────────────────
var _color_picker: ColorPickerButton = null
var _channel_r: CheckBox = null
var _channel_g: CheckBox = null
var _channel_b: CheckBox = null
var _channel_a: CheckBox = null
var _blend_mode: OptionButton = null
var _radius_spin: SpinBox = null
var _strength_spin: SpinBox = null
var _fill_selected_btn: Button = null
var _fill_all_btn: Button = null
var _eyedropper_btn: Button = null
var _paint_toggle: Button = null
var _view_r_btn: Button = null
var _view_g_btn: Button = null
var _view_b_btn: Button = null
var _view_a_btn: Button = null

## Which channel is being visualised (0=R, 1=G, 2=B, 3=A, -1=none).
var _view_channel: int = -1


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Called by the plugin after the dock is registered.
func set_plugin(plugin: EditorPlugin) -> void:
	_plugin = plugin


## Set the active [GoBuildMeshInstance].  Pass [code]null[/code] to clear.
func set_target(node: GoBuildMeshInstance) -> void:
	_target = node
	_refresh_buttons()


func _ready() -> void:
	name = "GoBuild Vertex Paint"

	# ── Header ──────────────────────────────────────────────────────────
	var header := Label.new()
	header.text = "── Vertex Paint ──"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	header.add_theme_font_size_override("font_size", 11)
	add_child(header)

	# ── Paint mode toggle ──────────────────────────────────────────────
	_paint_toggle = Button.new()
	_paint_toggle.text = "Paint"
	_paint_toggle.tooltip_text = "Toggle paint mode — LMB paints in viewport when active"
	_paint_toggle.toggle_mode = true
	_paint_toggle.button_pressed = false
	_paint_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_paint_toggle.add_theme_font_size_override("font_size", 12)
	_paint_toggle.pressed.connect(_on_paint_toggled)
	add_child(_paint_toggle)

	add_child(HSeparator.new())
	var color_row := HBoxContainer.new()
	var color_label := Label.new()
	color_label.text = "Color:"
	color_label.add_theme_font_size_override("font_size", 11)
	color_row.add_child(color_label)

	_color_picker = ColorPickerButton.new()
	_color_picker.color = Color.WHITE
	_color_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_row.add_child(_color_picker)
	add_child(color_row)

	# ── Channel toggles ─────────────────────────────────────────────────
	var channel_label := Label.new()
	channel_label.text = "Channels:"
	channel_label.add_theme_font_size_override("font_size", 11)
	add_child(channel_label)

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
	add_child(channel_row)

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
	add_child(blend_row)

	add_child(HSeparator.new())

	# ── Brush settings (for future interactive painting) ─────────────────
	var brush_label := Label.new()
	brush_label.text = "── Brush ──"
	brush_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brush_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	brush_label.add_theme_font_size_override("font_size", 11)
	add_child(brush_label)

	var radius_row := HBoxContainer.new()
	var radius_label := Label.new()
	radius_label.text = "Radius:"
	radius_label.add_theme_font_size_override("font_size", 11)
	radius_row.add_child(radius_label)

	_radius_spin = SpinBox.new()
	_radius_spin.min_value = 0.01
	_radius_spin.max_value = 10.0
	_radius_spin.step = 0.1
	_radius_spin.value = 0.5
	_radius_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	radius_row.add_child(_radius_spin)
	add_child(radius_row)

	var strength_row := HBoxContainer.new()
	var strength_label := Label.new()
	strength_label.text = "Strength:"
	strength_label.add_theme_font_size_override("font_size", 11)
	strength_row.add_child(strength_label)

	_strength_spin = SpinBox.new()
	_strength_spin.min_value = 0.0
	_strength_spin.max_value = 1.0
	_strength_spin.step = 0.05
	_strength_spin.value = 1.0
	_strength_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strength_row.add_child(_strength_spin)
	add_child(strength_row)

	add_child(HSeparator.new())

	# ── Batch operations ─────────────────────────────────────────────────
	var ops_label := Label.new()
	ops_label.text = "── Fill ──"
	ops_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ops_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	ops_label.add_theme_font_size_override("font_size", 11)
	add_child(ops_label)

	var fill_grid := GridContainer.new()
	fill_grid.columns = 2

	_fill_selected_btn = Button.new()
	_fill_selected_btn.text = "Fill Selected"
	_fill_selected_btn.tooltip_text = (
		"Paint selected faces/vertices with the current colour,\n"
		+ "channels, and blend mode.\n"
		+ "Face mode: selected faces.  Vertex mode: selected vertices.\n"
		+ "Object mode: all faces."
	)
	_fill_selected_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fill_selected_btn.add_theme_font_size_override("font_size", 11)
	_fill_selected_btn.disabled = true
	_fill_selected_btn.pressed.connect(_on_fill_selected_pressed)
	fill_grid.add_child(_fill_selected_btn)

	_fill_all_btn = Button.new()
	_fill_all_btn.text = "Fill All"
	_fill_all_btn.tooltip_text = (
		"Paint every vertex in the mesh with the current colour,\n"
		+ "channels, and blend mode.  Requires a mesh to be selected."
	)
	_fill_all_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fill_all_btn.add_theme_font_size_override("font_size", 11)
	_fill_all_btn.disabled = true
	_fill_all_btn.pressed.connect(_on_fill_all_pressed)
	fill_grid.add_child(_fill_all_btn)

	_eyedropper_btn = Button.new()
	_eyedropper_btn.text = "Eyedropper"
	_eyedropper_btn.tooltip_text = "Sample colour from a vertex (Ctrl+click in viewport)"
	_eyedropper_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_eyedropper_btn.add_theme_font_size_override("font_size", 11)
	_eyedropper_btn.disabled = true
	fill_grid.add_child(_eyedropper_btn)

	# ponytail: placeholder cell to keep the grid even
	fill_grid.add_child(Control.new())

	add_child(fill_grid)

	# ── Channel visualiser ────────────────────────────────────────────────
	add_child(HSeparator.new())

	var viz_label := Label.new()
	viz_label.text = "── Channel View ──"
	viz_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	viz_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	viz_label.add_theme_font_size_override("font_size", 11)
	add_child(viz_label)

	var viz_row := HBoxContainer.new()
	_view_r_btn = Button.new()
	_view_r_btn.text = "R"
	_view_r_btn.tooltip_text = "View red channel as greyscale"
	_view_r_btn.toggle_mode = true
	_view_r_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view_r_btn.add_theme_font_size_override("font_size", 11)
	_view_r_btn.pressed.connect(_on_view_channel.bind(0))
	viz_row.add_child(_view_r_btn)

	_view_g_btn = Button.new()
	_view_g_btn.text = "G"
	_view_g_btn.tooltip_text = "View green channel as greyscale"
	_view_g_btn.toggle_mode = true
	_view_g_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view_g_btn.add_theme_font_size_override("font_size", 11)
	_view_g_btn.pressed.connect(_on_view_channel.bind(1))
	viz_row.add_child(_view_g_btn)

	_view_b_btn = Button.new()
	_view_b_btn.text = "B"
	_view_b_btn.tooltip_text = "View blue channel as greyscale"
	_view_b_btn.toggle_mode = true
	_view_b_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view_b_btn.add_theme_font_size_override("font_size", 11)
	_view_b_btn.pressed.connect(_on_view_channel.bind(2))
	viz_row.add_child(_view_b_btn)

	_view_a_btn = Button.new()
	_view_a_btn.text = "A"
	_view_a_btn.tooltip_text = "View alpha channel as greyscale"
	_view_a_btn.toggle_mode = true
	_view_a_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view_a_btn.add_theme_font_size_override("font_size", 11)
	_view_a_btn.pressed.connect(_on_view_channel.bind(3))
	viz_row.add_child(_view_a_btn)

	add_child(viz_row)


# ---------------------------------------------------------------------------
# Public helpers
# ---------------------------------------------------------------------------

## Current channel mask from the toggle checkboxes.
func get_channel_mask() -> int:
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


## Current blend mode from the dropdown.
func get_blend_mode() -> int:
	return _blend_mode.get_selected_id()


## Current colour from the picker.
func get_paint_color() -> Color:
	return _color_picker.color


## Current brush radius.
func get_brush_radius() -> float:
	return _radius_spin.value


## Set brush radius (used by F-drag resize).
func set_brush_radius(v: float) -> void:
	_radius_spin.value = v


## Current brush strength.
func get_brush_strength() -> float:
	return _strength_spin.value


## Set brush strength (used by S-drag resize).
func set_brush_strength(v: float) -> void:
	_strength_spin.value = v


## Set the colour picker to [param c] (used by eyedropper).
func set_paint_color(c: Color) -> void:
	_color_picker.color = c


## Set the blend mode dropdown to [param id].
func set_blend_mode(id: int) -> void:
	if _blend_mode != null:
		_blend_mode.select(id)


## Whether paint mode is active (LMB paints in viewport).
func is_paint_mode() -> bool:
	return _paint_toggle != null and _paint_toggle.button_pressed


## Toggle paint mode on or off programmatically.
func set_paint_mode(enabled: bool) -> void:
	if _paint_toggle != null:
		_paint_toggle.button_pressed = enabled


func _on_paint_toggled() -> void:
	# ponytail: could update viewport overlay hint here in future.
	pass


# ---------------------------------------------------------------------------
# Button refresh
# ---------------------------------------------------------------------------

func _refresh_buttons() -> void:
	if _fill_selected_btn != null:
		_fill_selected_btn.disabled = not _cond_selection_or_object()
	if _fill_all_btn != null:
		_fill_all_btn.disabled = not _cond_has_mesh()
	if _eyedropper_btn != null:
		_eyedropper_btn.disabled = not _cond_has_mesh()


## Called by the plugin on selection change.
func refresh() -> void:
	_refresh_buttons()


# ---------------------------------------------------------------------------
# Conditions
# ---------------------------------------------------------------------------

func _cond_selection_or_object() -> bool:
	if _target == null or _target.go_build_mesh == null:
		return false
	var mode: int = _target.selection.get_mode()
	if mode == SelectionManager.Mode.FACE:
		return not _target.selection.get_selected_faces().is_empty()
	if mode == SelectionManager.Mode.VERTEX:
		return not _target.selection.get_selected_vertices().is_empty()
	if mode == SelectionManager.Mode.OBJECT:
		return true
	return false


func _cond_has_mesh() -> bool:
	return _target != null and _target.go_build_mesh != null


# ---------------------------------------------------------------------------
# Operation handlers
# ---------------------------------------------------------------------------

func _on_fill_selected_pressed() -> void:
	if _target == null or _plugin == null or _target.go_build_mesh == null:
		return
	var mode: int = _target.selection.get_mode()
	var color: Color = get_paint_color()
	var blend: int = get_blend_mode()
	var mask: int = get_channel_mask()

	if mode == SelectionManager.Mode.FACE:
		var sel: Array[int] = _target.selection.get_selected_faces()
		if sel.is_empty():
			return
		var faces: Array[int] = []
		faces.assign(sel)
		_target.apply_operation(
			"Fill Vertex Color",
			func(): VertexColorOperation.fill_faces(
				_target.go_build_mesh, faces, color, blend, mask),
			_plugin.get_undo_redo(),
		)
	elif mode == SelectionManager.Mode.VERTEX:
		var sel: Array[int] = _target.selection.get_selected_vertices()
		if sel.is_empty():
			return
		var verts: Array[int] = []
		verts.assign(sel)
		_target.apply_operation(
			"Paint Vertex Color",
			func(): VertexColorOperation.set_vertices(
				_target.go_build_mesh, verts, color, blend, mask),
			_plugin.get_undo_redo(),
		)
	elif mode == SelectionManager.Mode.OBJECT:
		_target.apply_operation(
			"Fill All Vertex Colors",
			func(): VertexColorOperation.fill_all(
				_target.go_build_mesh, color, blend, mask),
			_plugin.get_undo_redo(),
	)
	_target.update_gizmos()


# ---------------------------------------------------------------------------
# Channel visualiser
# ---------------------------------------------------------------------------

## Toggle channel visualisation.  Clicking the active channel again turns it off.
## When a channel view is active, all vertex colours are replaced by a
## greyscale representation of that channel, and the material is set to
## unlit so the channel value is clearly visible.
func _on_view_channel(channel: int) -> void:
	if _view_channel == channel:
		_view_channel = -1
	else:
		_view_channel = channel
	_update_view_buttons()
	_apply_channel_view()


func _update_view_buttons() -> void:
	_view_r_btn.button_pressed = (_view_channel == 0)
	_view_g_btn.button_pressed = (_view_channel == 1)
	_view_b_btn.button_pressed = (_view_channel == 2)
	_view_a_btn.button_pressed = (_view_channel == 3)


## Apply or remove the channel view material override.
## When active, creates a temporary mesh where the selected channel maps to
## greyscale.  When inactive, restores the original mesh via rebake.
func _apply_channel_view() -> void:
	if _target == null or _target.go_build_mesh == null:
		return
	var gbm: GoBuildMesh = _target.go_build_mesh
	var am: ArrayMesh = _target.mesh as ArrayMesh
	if am == null:
		return

	if _view_channel == -1:
		_target.bake()
		return

	# Ensure vertex colours are populated.
	VertexColorOperation._ensure_colors(gbm)

	# Create a view mesh where vertex colours map the selected channel to greyscale.
	var view_mesh := GoBuildMesh.new()
	view_mesh.vertices = gbm.vertices
	view_mesh.faces = gbm.faces
	view_mesh.edges = gbm.edges
	view_mesh.vertex_colors.clear()
	view_mesh.vertex_colors.resize(gbm.vertices.size())
	for i: int in gbm.vertices.size():
		var c: Color = gbm.vertex_colors[i] if gbm.vertex_colors.size() > i else Color.WHITE
		var v: float
		match _view_channel:
			0: v = c.r
			1: v = c.g
			2: v = c.b
			3: v = c.a
			_: v = c.r
		view_mesh.vertex_colors[i] = Color(v, v, v, 1.0)
	view_mesh.material_slots = gbm.material_slots

	# Bake and display with an unlit material so greyscale is clearly visible.
	var baked: ArrayMesh = view_mesh.bake()
	var unlit := StandardMaterial3D.new()
	unlit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	unlit.vertex_color_use_as_albedo = true
	unlit.albedo_color = Color.WHITE
	for si: int in baked.get_surface_count():
		baked.surface_set_material(si, unlit)
	_target.mesh = baked


func _on_fill_all_pressed() -> void:
	if _target == null or _plugin == null or _target.go_build_mesh == null:
		return
	var color: Color = get_paint_color()
	var blend: int = get_blend_mode()
	var mask: int = get_channel_mask()
	_target.apply_operation(
		"Fill All Vertex Colors",
		func(): VertexColorOperation.fill_all(
			_target.go_build_mesh, color, blend, mask),
		_plugin.get_undo_redo(),
	)
	_target.update_gizmos()