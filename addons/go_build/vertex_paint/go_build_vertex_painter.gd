## Dock panel for vertex colour painting on [GoBuildMesh] instances.
##
## Separate from the main GoBuild panel so the paint workflow has its own
## dedicated space.  Registered as a bottom dock by [GoBuildPlugin].
##
## Contains:
## - Colour picker (or greyscale value slider when greyscale mode is on)
## - Target channel dropdown (Colour, Custom 0–3)
## - Channel mask toggles (R, G, B, A)
## - Blend mode dropdown (Mix, Add, Subtract, Multiply)
## - Greyscale paint toggle
## - Brush radius and strength sliders
## - Fill Selected / Fill All batch buttons
## - Isolate View section: visualise a component of the active target channel
@tool
class_name GoBuildVertexPainter
extends VBoxContainer

# Self-preloads — compile-time type references.
const _SEL_MGR_SCRIPT_VP     := preload("res://addons/go_build/core/selection_manager.gd")
const _MESH_INST_SCRIPT_VP   := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _VC_OP_SCRIPT_VP       := \
		preload("res://addons/go_build/mesh/operations/vertex_color_operation.gd")

const _ISOLATE_SHADER_CODE: String = """shader_type spatial;
render_mode unshaded;

uniform vec4 show_channels = vec4(1.0, 1.0, 1.0, 1.0);
uniform bool greyscale = false;

void fragment() {
	vec4 src = COLOR;
	vec4 filtered = vec4(
		src.r * show_channels.r,
		src.g * show_channels.g,
		src.b * show_channels.b,
		src.a * show_channels.a
	);
	if (greyscale) {
		float v = filtered.r + filtered.g + filtered.b + filtered.a;
		ALBEDO = vec3(v);
	} else {
		ALBEDO = vec3(filtered.r, filtered.g, filtered.b);
	}
	ALPHA = 1.0;
}
"""

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
var _target_channel: OptionButton = null
var _greyscale_toggle: CheckBox = null
var _greyscale_spin: HSlider = null
var _greyscale_value_label: Label = null
var _isolate_btn: Button = null

## Whether isolate view is active.
var _isolate_active: bool = false

## Stashed original vertex_colors when isolating a custom channel.
## When isolate targets a custom channel, we copy that channel's data into
## vertex_colors for the shader to read.  The original colors are restored
## when isolate is turned off.
var _isolate_original_colors: Array[Color] = []

## The shader material used for isolate view. Persisted so we can re-apply it
## after mesh replacements (bake, preview, undo) without recreating it each time.
var _isolate_material: ShaderMaterial = null


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Called by the plugin after the dock is registered.
func set_plugin(plugin: EditorPlugin) -> void:
	_plugin = plugin


## Set the active [GoBuildMeshInstance].  Pass [code]null[/code] to clear.
func set_target(node: GoBuildMeshInstance) -> void:
	# Disconnect mesh_changed from old target.
	if _target != null and _target.mesh_changed.is_connected(_on_target_mesh_changed):
		_target.mesh_changed.disconnect(_on_target_mesh_changed)
	_target = node
	# Reconnect to new target if isolate is active.
	if _target != null and _isolate_active:
		_target.mesh_changed.connect(_on_target_mesh_changed)
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

	# ── Greyscale paint mode ─────────────────────────────────────────────
	var gs_row := HBoxContainer.new()
	_greyscale_toggle = CheckBox.new()
	_greyscale_toggle.text = "Greyscale"
	_greyscale_toggle.button_pressed = false
	_greyscale_toggle.tooltip_text = "Paint a single value into all masked channels (R=G=B=A=value)"
	_greyscale_toggle.add_theme_font_size_override("font_size", 11)
	_greyscale_toggle.toggled.connect(_on_greyscale_toggled)
	gs_row.add_child(_greyscale_toggle)

	_greyscale_spin = HSlider.new()
	_greyscale_spin.min_value = 0.0
	_greyscale_spin.max_value = 1.0
	_greyscale_spin.step = 0.01
	_greyscale_spin.value = 1.0
	_greyscale_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_greyscale_spin.editable = false
	_greyscale_spin.visible = false
	gs_row.add_child(_greyscale_spin)

	_greyscale_value_label = Label.new()
	_greyscale_value_label.text = "1.00"
	_greyscale_value_label.add_theme_font_size_override("font_size", 11)
	_greyscale_value_label.custom_minimum_size.x = 36
	_greyscale_value_label.visible = false
	gs_row.add_child(_greyscale_value_label)
	_greyscale_spin.value_changed.connect(_on_greyscale_value_changed)
	add_child(gs_row)

	# ── Target channel + Isolate toggle ──────────────────────────────────
	var target_row := HBoxContainer.new()
	var target_label := Label.new()
	target_label.text = "Target:"
	target_label.add_theme_font_size_override("font_size", 11)
	target_row.add_child(target_label)

	_target_channel = OptionButton.new()
	_target_channel.add_item("Color", _VC_OP_SCRIPT_VP.TargetChannel.COLOR)
	_target_channel.add_item("Custom 0", _VC_OP_SCRIPT_VP.TargetChannel.CUSTOM0)
	_target_channel.add_item("Custom 1", _VC_OP_SCRIPT_VP.TargetChannel.CUSTOM1)
	_target_channel.add_item("Custom 2", _VC_OP_SCRIPT_VP.TargetChannel.CUSTOM2)
	_target_channel.add_item("Custom 3", _VC_OP_SCRIPT_VP.TargetChannel.CUSTOM3)
	_target_channel.tooltip_text = "Which per-vertex channel to paint on (Alt+1–5)"
	_target_channel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_target_channel.item_selected.connect(_on_target_channel_changed)
	target_row.add_child(_target_channel)

	_isolate_btn = Button.new()
	_isolate_btn.text = "👁"
	_isolate_btn.toggle_mode = true
	_isolate_btn.button_pressed = false
	_isolate_btn.tooltip_text = (
		"Isolate: show the target channel in the viewport.\n"
		+ "Uses the active Channels mask (R/G/B/A).\n"
		+ "Click again to return to normal rendering.\n"
		+ "Hotkey: Alt+T")
	_isolate_btn.add_theme_font_size_override("font_size", 11)
	_isolate_btn.toggled.connect(_on_isolate_toggled)
	target_row.add_child(_isolate_btn)

	add_child(target_row)

	# ── Channel toggles ─────────────────────────────────────────────────
	var channel_label := Label.new()
	channel_label.text = "Channels:"
	channel_label.add_theme_font_size_override("font_size", 11)
	add_child(channel_label)

	var channel_row := HBoxContainer.new()
	_channel_r = CheckBox.new()
	_channel_r.text = "R"
	_channel_r.button_pressed = true
	_channel_r.tooltip_text = "Red channel (Alt+Q)"
	_channel_r.toggled.connect(_on_channel_toggled)
	channel_row.add_child(_channel_r)

	_channel_g = CheckBox.new()
	_channel_g.text = "G"
	_channel_g.button_pressed = true
	_channel_g.tooltip_text = "Green channel (Alt+W)"
	_channel_g.toggled.connect(_on_channel_toggled)
	channel_row.add_child(_channel_g)

	_channel_b = CheckBox.new()
	_channel_b.text = "B"
	_channel_b.button_pressed = true
	_channel_b.tooltip_text = "Blue channel (Alt+E)"
	_channel_b.toggled.connect(_on_channel_toggled)
	channel_row.add_child(_channel_b)

	_channel_a = CheckBox.new()
	_channel_a.text = "A"
	_channel_a.button_pressed = false
	_channel_a.tooltip_text = "Alpha channel (Alt+R)"
	_channel_a.toggled.connect(_on_channel_toggled)
	channel_row.add_child(_channel_a)
	add_child(channel_row)

	# ── Blend mode ───────────────────────────────────────────────────────
	var blend_row := HBoxContainer.new()
	var blend_label := Label.new()
	blend_label.text = "Blend:"
	blend_label.add_theme_font_size_override("font_size", 11)
	blend_row.add_child(blend_label)

	_blend_mode = OptionButton.new()
	_blend_mode.add_item("Mix", _VC_OP_SCRIPT_VP.BlendMode.MIX)
	_blend_mode.add_item("Add", _VC_OP_SCRIPT_VP.BlendMode.ADD)
	_blend_mode.add_item("Subtract", _VC_OP_SCRIPT_VP.BlendMode.SUBTRACT)
	_blend_mode.add_item("Multiply", _VC_OP_SCRIPT_VP.BlendMode.MULTIPLY)
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
	_radius_spin.step = 0.01
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
	_strength_spin.step = 0.01
	_strength_spin.value = 1.0
	_strength_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strength_row.add_child(_strength_spin)
	add_child(strength_row)

	add_child(HSeparator.new())

	# ── Batch operations ─────────────────────────────────────────────────
	var ops_label := Label.new()
	ops_label.text = "── Apply to Selection ──"
	ops_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ops_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	ops_label.add_theme_font_size_override("font_size", 11)
	add_child(ops_label)

	var fill_grid := GridContainer.new()
	fill_grid.columns = 2

	_fill_selected_btn = Button.new()
	_fill_selected_btn.text = "Fill Selected"
	_fill_selected_btn.tooltip_text = (
		"Apply paint to the current selection.\n"
		+ "Face mode: selected faces.  Vertex mode: selected vertices.\n"
		+ "Object mode: all faces.\n"
		+ "Works without Paint mode enabled."
	)
	_fill_selected_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fill_selected_btn.add_theme_font_size_override("font_size", 11)
	_fill_selected_btn.disabled = true
	_fill_selected_btn.pressed.connect(_on_fill_selected_pressed)
	fill_grid.add_child(_fill_selected_btn)

	_fill_all_btn = Button.new()
	_fill_all_btn.text = "Fill All"
	_fill_all_btn.tooltip_text = (
		"Apply paint to every vertex in the mesh.\n"
		+ "Works without Paint mode enabled."
	)
	_fill_all_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fill_all_btn.add_theme_font_size_override("font_size", 11)
	_fill_all_btn.disabled = true
	_fill_all_btn.pressed.connect(_on_fill_all_pressed)
	fill_grid.add_child(_fill_all_btn)

	_eyedropper_btn = Button.new()
	_eyedropper_btn.text = "Eyedropper"
	_eyedropper_btn.tooltip_text = "Sample colour from a vertex (Alt+click in viewport)"
	_eyedropper_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_eyedropper_btn.add_theme_font_size_override("font_size", 11)
	_eyedropper_btn.disabled = true
	fill_grid.add_child(_eyedropper_btn)

	# ponytail: placeholder cell to keep the grid even
	fill_grid.add_child(Control.new())

	add_child(fill_grid)

	_update_paint_toggle_style()


# ---------------------------------------------------------------------------
# Public helpers
# ---------------------------------------------------------------------------

## Current channel mask from the toggle checkboxes.
func get_channel_mask() -> int:
	var mask: int = 0
	if _channel_r.button_pressed:
		mask |= _VC_OP_SCRIPT_VP.CHANNEL_R
	if _channel_g.button_pressed:
		mask |= _VC_OP_SCRIPT_VP.CHANNEL_G
	if _channel_b.button_pressed:
		mask |= _VC_OP_SCRIPT_VP.CHANNEL_B
	if _channel_a.button_pressed:
		mask |= _VC_OP_SCRIPT_VP.CHANNEL_A
	if mask == 0:
		mask = _VC_OP_SCRIPT_VP.CHANNEL_ALL
	return mask


## Current blend mode from the dropdown.
func get_blend_mode() -> int:
	return _blend_mode.get_selected_id()


## Current target channel from the dropdown.
func get_target_channel() -> int:
	return _target_channel.get_selected_id()


## Current colour from the picker.  In greyscale mode, returns
## [code]Color(v, v, v, v)[/code] from the greyscale slider.
func get_paint_color() -> Color:
	if _greyscale_toggle != null and _greyscale_toggle.button_pressed:
		var v: float = _greyscale_spin.value
		return Color(v, v, v, v)
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


## Toggle channel R checkbox (Alt+Q).
func toggle_channel_r() -> void:
	if _channel_r != null:
		_channel_r.button_pressed = not _channel_r.button_pressed


## Toggle channel G checkbox (Alt+W).
func toggle_channel_g() -> void:
	if _channel_g != null:
		_channel_g.button_pressed = not _channel_g.button_pressed


## Toggle channel B checkbox (Alt+E).
func toggle_channel_b() -> void:
	if _channel_b != null:
		_channel_b.button_pressed = not _channel_b.button_pressed


## Toggle channel A checkbox (Alt+R).
func toggle_channel_a() -> void:
	if _channel_a != null:
		_channel_a.button_pressed = not _channel_a.button_pressed


## Select target channel by index (Alt+1–5).
func select_target_channel(index: int) -> void:
	if _target_channel != null and index >= 0 and index < _target_channel.item_count:
		_target_channel.select(index)
		_on_target_channel_changed(index)


## Toggle isolate view (Alt+T).
## Only works when paint mode is active.
func toggle_isolate() -> void:
	if _isolate_btn != null and _paint_toggle != null and _paint_toggle.button_pressed:
		_isolate_btn.button_pressed = not _isolate_btn.button_pressed
		_on_isolate_toggled()


## Whether paint mode is active (LMB paints in viewport).
func is_paint_mode() -> bool:
	return _paint_toggle != null and _paint_toggle.button_pressed


## Toggle paint mode on or off programmatically.
func set_paint_mode(enabled: bool) -> void:
	if _paint_toggle != null:
		_paint_toggle.button_pressed = enabled
		_update_paint_toggle_style()


func _on_paint_toggled() -> void:
	_update_paint_toggle_style()
	var gizmo_plugin = _plugin.get("_gizmo_plugin") if _plugin != null else null
	if _paint_toggle.button_pressed:
		# Ensure vertex colour data exists on the mesh.
		if _target != null and _target.go_build_mesh != null:
			_VC_OP_SCRIPT_VP._ensure_channel(
				_target.go_build_mesh, _VC_OP_SCRIPT_VP.TargetChannel.COLOR)
		if _isolate_active:
			# Isolate takes priority over paint materials — just refresh isolate view.
			_apply_isolate_view()
			_switch_to_vertex_mode()
		else:
			_enable_vertex_color_display()
			_switch_to_vertex_mode()
		if gizmo_plugin != null:
			gizmo_plugin.show_vertex_colors = true
	else:
		# Turning paint mode off — also disable isolate.
		if _isolate_active:
			_isolate_active = false
			_isolate_btn.button_pressed = false
			_update_isolate_style()
			if _target != null and _target.mesh_changed.is_connected(_on_target_mesh_changed):
				_target.mesh_changed.disconnect(_on_target_mesh_changed)
			_isolate_material = null
			_VC_OP_SCRIPT_VP.restore_vertex_colors(
				_target.go_build_mesh, _isolate_original_colors)
		_restore_materials()
		if gizmo_plugin != null:
			gizmo_plugin.show_vertex_colors = false


func _update_paint_toggle_style() -> void:
	if _paint_toggle.button_pressed:
		_paint_toggle.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
		_paint_toggle.add_theme_color_override("font_hover_color", Color(1.0, 0.90, 0.50))
		_paint_toggle.add_theme_color_override("font_pressed_color", Color(1.0, 0.85, 0.35))
		var pressed_bg := StyleBoxFlat.new()
		pressed_bg.bg_color = Color(0.30, 0.25, 0.12)
		pressed_bg.set_corner_radius_all(4)
		pressed_bg.set_content_margin_all(4)
		_paint_toggle.add_theme_stylebox_override("pressed", pressed_bg)
		var hover_bg := StyleBoxFlat.new()
		hover_bg.bg_color = Color(0.35, 0.30, 0.15)
		hover_bg.set_corner_radius_all(4)
		hover_bg.set_content_margin_all(4)
		_paint_toggle.add_theme_stylebox_override("hover", hover_bg)
	else:
		_paint_toggle.remove_theme_color_override("font_color")
		_paint_toggle.remove_theme_color_override("font_hover_color")
		_paint_toggle.remove_theme_color_override("font_pressed_color")
		_paint_toggle.remove_theme_stylebox_override("pressed")
		_paint_toggle.remove_theme_stylebox_override("hover")


func _on_greyscale_toggled(pressed: bool) -> void:
	_greyscale_spin.editable = pressed
	_color_picker.visible = not pressed
	_greyscale_spin.visible = pressed
	_greyscale_value_label.visible = pressed
	if _isolate_active:
		_apply_isolate_view()


func _on_greyscale_value_changed(value: float) -> void:
	_greyscale_value_label.text = "%.2f" % value


## Switch the target to vertex selection mode so vertex gizmos are visible.
func _switch_to_vertex_mode() -> void:
	if _target == null:
		return
	_target.selection.set_mode(SelectionManager.Mode.VERTEX)
	_target.update_gizmos()


## Ensure vertex colours are visible on all materials when paint mode activates.
## Forces [code]vertex_color_use_as_albedo = true[/code] on every [BaseMaterial3D]
## and initializes [member GoBuildMesh.vertex_colors] if empty.
func _enable_vertex_color_display() -> void:
	if _target == null or _target.go_build_mesh == null:
		return
	var gbm: GoBuildMesh = _target.go_build_mesh
	_VC_OP_SCRIPT_VP._ensure_channel(gbm, _VC_OP_SCRIPT_VP.TargetChannel.COLOR)
	_target.bake()
	_apply_paint_materials()


## Apply material overrides that enable vertex colour display for painting.
## Duplicates any [BaseMaterial3D] surface material and sets
## [code]vertex_color_use_as_albedo = true[/code].
func _apply_paint_materials() -> void:
	var am := _target.mesh as ArrayMesh
	if am == null:
		return
	for i: int in am.get_surface_count():
		var orig: Material = am.surface_get_material(i)
		if orig is BaseMaterial3D:
			var dup: BaseMaterial3D = (orig as BaseMaterial3D).duplicate()
			dup.vertex_color_use_as_albedo = true
			_target.set_surface_override_material(i, dup)
		elif orig == null:
			var mat := StandardMaterial3D.new()
			mat.vertex_color_use_as_albedo = true
			mat.albedo_color = Color.WHITE
			_target.set_surface_override_material(i, mat)


## Remove paint-mode material overrides, restoring original surface materials.
func _restore_materials() -> void:
	if _target == null:
		return
	_clear_material_overrides()
	_target.bake()
	_target.update_gizmos()


## Remove all surface override materials set during paint mode or isolate view.
func _clear_material_overrides() -> void:
	if _target == null:
		return
	var am := _target.mesh as ArrayMesh
	if am == null:
		return
	for i: int in am.get_surface_count():
		_target.set_surface_override_material(i, null)


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
	var target: int = get_target_channel()

	if mode == SelectionManager.Mode.FACE:
		var sel: Array[int] = _target.selection.get_selected_faces()
		if sel.is_empty():
			return
		var faces: Array[int] = []
		faces.assign(sel)
		_target.apply_operation(
			"Fill Vertex Color",
			func(): _VC_OP_SCRIPT_VP.fill_faces(
				_target.go_build_mesh, faces, color, blend, mask, target),
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
			func(): _VC_OP_SCRIPT_VP.set_vertices(
				_target.go_build_mesh, verts, color, blend, mask, target),
			_plugin.get_undo_redo(),
		)
	elif mode == SelectionManager.Mode.OBJECT:
		_target.apply_operation(
			"Fill All Vertex Colors",
			func(): _VC_OP_SCRIPT_VP.fill_all(
				_target.go_build_mesh, color, blend, mask, target),
			_plugin.get_undo_redo(),
	)
	_target.update_gizmos()


# ---------------------------------------------------------------------------
# Channel visualiser
# ---------------------------------------------------------------------------

func _on_target_channel_changed(_index: int) -> void:
	if _isolate_active:
		_apply_isolate_view()

func _on_channel_toggled(_pressed: bool) -> void:
	if _isolate_active:
		_apply_isolate_view()


func _on_isolate_toggled(_pressed: bool = false) -> void:
	# Isolate only works in paint mode.
	if _paint_toggle != null and not _paint_toggle.button_pressed:
		_isolate_btn.button_pressed = false
		_isolate_active = false
		_update_isolate_style()
		return
	_isolate_active = _isolate_btn.button_pressed
	_update_isolate_style()
	if _isolate_active:
		if _target != null and not _target.mesh_changed.is_connected(_on_target_mesh_changed):
			_target.mesh_changed.connect(_on_target_mesh_changed)
		_apply_isolate_view()
	else:
		if _target != null and _target.mesh_changed.is_connected(_on_target_mesh_changed):
			_target.mesh_changed.disconnect(_on_target_mesh_changed)
		_apply_isolate_view()


func _on_target_mesh_changed() -> void:
	if _isolate_active:
		_refresh_isolate_after_bake()


## Whether isolate view is currently active.
func is_isolate_active() -> bool:
	return _isolate_active


## Re-apply the isolate view after the mesh data has changed (e.g. after a paint stroke).
func refresh_isolate_view() -> void:
	if _isolate_active:
		_apply_isolate_view()


## Re-apply the stored isolate shader material as surface overrides on the
## current mesh.  Called after mesh replacements (begin_preview, bake) that
## assign a new ArrayMesh, which loses any surface override materials.
func reapply_isolate_overrides() -> void:
	if _isolate_active:
		_apply_isolate_overrides()


## Copy custom channel data into vertex_colors for the shader to read.
## Call before [method GoBuildMeshInstance.bake_preview] during painting when
## isolating a custom channel.  Does NOT bake or reconnect signals.
func sync_isolate_vertex_colors() -> void:
	if _target == null or _target.go_build_mesh == null:
		return
	if not _isolate_active:
		return
	var target: int = get_target_channel()
	if target == _VC_OP_SCRIPT_VP.TargetChannel.COLOR:
		return
	if _isolate_original_colors.is_empty():
		return
	_VC_OP_SCRIPT_VP.sync_channel_to_vertex_colors(
		_target.go_build_mesh, target as _VC_OP_SCRIPT_VP.TargetChannel)


## Lightweight refresh after a mesh bake.  Syncs custom channel vertex colours
## if needed, and re-applies the shader overrides on the new mesh.  Called via the
## [signal mesh_changed] signal so we never need to manually call this.
func _refresh_isolate_after_bake() -> void:
	if _target == null or _target.go_build_mesh == null:
		return
	var target: int = get_target_channel()
	# If isolating a custom channel, sync vertex colors and rebake.
	# For the Color target, the mesh already has the right vertex colors —
	# just re-apply the shader overrides on the new mesh.
	if target != _VC_OP_SCRIPT_VP.TargetChannel.COLOR and not _isolate_original_colors.is_empty():
		sync_isolate_vertex_colors()
		_target.bake_silently()
	_apply_isolate_overrides()


func _update_isolate_style() -> void:
	if _isolate_btn.button_pressed:
		_isolate_btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
		_isolate_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.90, 0.50))
		_isolate_btn.add_theme_color_override("font_pressed_color", Color(1.0, 0.85, 0.35))
		var pressed_bg := StyleBoxFlat.new()
		pressed_bg.bg_color = Color(0.30, 0.25, 0.12)
		pressed_bg.set_corner_radius_all(4)
		pressed_bg.set_content_margin_all(4)
		_isolate_btn.add_theme_stylebox_override("pressed", pressed_bg)
		var hover_bg := StyleBoxFlat.new()
		hover_bg.bg_color = Color(0.35, 0.30, 0.15)
		hover_bg.set_corner_radius_all(4)
		hover_bg.set_content_margin_all(4)
		_isolate_btn.add_theme_stylebox_override("hover", hover_bg)
	else:
		_isolate_btn.remove_theme_color_override("font_color")
		_isolate_btn.remove_theme_color_override("font_hover_color")
		_isolate_btn.remove_theme_color_override("font_pressed_color")
		_isolate_btn.remove_theme_stylebox_override("pressed")
		_isolate_btn.remove_theme_stylebox_override("hover")


## Apply or remove the isolate view.
## When active, overrides all surface materials with a shader that isolates the
## target channel using the active channel mask. The real mesh is never replaced —
## only material overrides change.
## When inactive, clears the overrides and restores normal or paint-mode rendering.
func _apply_isolate_view() -> void:
	if _target == null or _target.go_build_mesh == null:
		return

	if not _isolate_active:
		_isolate_material = null
		_VC_OP_SCRIPT_VP.restore_vertex_colors(
			_target.go_build_mesh, _isolate_original_colors)
		_clear_material_overrides()
		_target.bake_silently()
		if _paint_toggle != null and _paint_toggle.button_pressed:
			_apply_paint_materials()
		return

	var target: int = get_target_channel()
	var mask: int = get_channel_mask()
	var greyscale: bool = _greyscale_toggle != null and _greyscale_toggle.button_pressed
	var show_r: float = 1.0 if (mask & _VC_OP_SCRIPT_VP.CHANNEL_R) != 0 else 0.0
	var show_g: float = 1.0 if (mask & _VC_OP_SCRIPT_VP.CHANNEL_G) != 0 else 0.0
	var show_b: float = 1.0 if (mask & _VC_OP_SCRIPT_VP.CHANNEL_B) != 0 else 0.0
	var show_a: float = 1.0 if (mask & _VC_OP_SCRIPT_VP.CHANNEL_A) != 0 else 0.0
	# Alpha-only automatically becomes greyscale.
	var only_alpha: bool = show_a > 0.5 and show_r < 0.5 and show_g < 0.5 and show_b < 0.5
	if only_alpha:
		greyscale = true

	# Restore original vertex_colors before potentially replacing them with a
	# different custom channel.  Without this, switching from Custom 0 to Custom 1
	# would stash Custom-0-as-vertex_colors as "original", losing the real colours.
	_VC_OP_SCRIPT_VP.restore_vertex_colors(
		_target.go_build_mesh, _isolate_original_colors)

	# Ensure the target channel data exists before baking.
	_VC_OP_SCRIPT_VP._ensure_channel(
		_target.go_build_mesh, target as _VC_OP_SCRIPT_VP.TargetChannel)

	# When isolating a custom channel, copy that channel into vertex_colors
	# so the shader can read it from COLOR.  The original colors are stashed
	# in _isolate_original_colors for restoration when isolate is turned off.
	if target != _VC_OP_SCRIPT_VP.TargetChannel.COLOR:
		_isolate_original_colors = _VC_OP_SCRIPT_VP.swap_channel_to_vertex_colors(
			_target.go_build_mesh, target as _VC_OP_SCRIPT_VP.TargetChannel)

	# Build or update the isolate shader material.
	if _isolate_material == null or _isolate_material.shader == null:
		var shader := Shader.new()
		shader.code = _ISOLATE_SHADER_CODE
		_isolate_material = ShaderMaterial.new()
		_isolate_material.shader = shader
	_isolate_material.set_shader_parameter("show_channels", Color(show_r, show_g, show_b, show_a))
	_isolate_material.set_shader_parameter("greyscale", greyscale)

	# Bake the real mesh so vertex colors are up to date, then apply overrides.
	_target.bake_silently()
	_apply_isolate_overrides()


## Apply the stored isolate shader material as surface overrides on the current mesh.
## Called after every mesh replacement (bake, begin_preview, end_preview) to keep
## the isolate view visible.
func _apply_isolate_overrides() -> void:
	if _isolate_material == null or _target == null:
		return
	var am := _target.mesh as ArrayMesh
	if am == null:
		return
	for si: int in am.get_surface_count():
		_target.set_surface_override_material(si, _isolate_material)


func _on_fill_all_pressed() -> void:
	if _target == null or _plugin == null or _target.go_build_mesh == null:
		return
	var color: Color = get_paint_color()
	var blend: int = get_blend_mode()
	var mask: int = get_channel_mask()
	var target: int = get_target_channel()
	_target.apply_operation(
		"Fill All Vertex Colors",
		func(): _VC_OP_SCRIPT_VP.fill_all(
			_target.go_build_mesh, color, blend, mask, target),
		_plugin.get_undo_redo(),
	)
	_target.update_gizmos()
