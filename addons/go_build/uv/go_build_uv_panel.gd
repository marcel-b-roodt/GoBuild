## Dock panel that hosts the [GoBuildUvCanvas] viewer.
##
## Registered as a second editor dock by [GoBuildPlugin].  When the active
## node changes the plugin calls [method set_target]; the embedded canvas
## automatically redraws on mesh or selection change.
##
## Supports island editing: click-select faces in UV space, drag islands to
## reposition them, and switch transform mode (Move/Rotate/Scale) via the
## toolbar or keyboard (G/R/S).
@tool
class_name GoBuildUvPanel
extends VBoxContainer

# Self-preload — ensures GoBuildUvCanvas is registered before use.
const _CANVAS_SCRIPT        := preload("res://addons/go_build/uv/go_build_uv_canvas.gd")
const _MESH_INSTANCE_SCRIPT := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _MESH_SCRIPT          := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _SEL_MGR_SCRIPT       := preload("res://addons/go_build/core/selection_manager.gd")
const _PACK_SCRIPT           := preload("res://addons/go_build/uv/uv_pack_islands.gd")
const _STITCH_SCRIPT         := preload("res://addons/go_build/uv/uv_stitch_islands.gd")

var _canvas: GoBuildUvCanvas = null
var _zoom_label: Label       = null
var _plugin: EditorPlugin    = null
var _move_btn: Button        = null
var _rotate_btn: Button      = null
var _scale_btn: Button       = null
var _bg_btn: Button          = null
var _pack_btn: Button        = null
var _stitch_btn: Button      = null
var _select_mode_btn: Button = null
var _repeat_spin: SpinBox    = null


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Called by the plugin after the dock is registered.
func set_plugin(plugin: EditorPlugin) -> void:
	_plugin = plugin
	if _canvas != null:
		_canvas.set_plugin(plugin)


## Set the active [GoBuildMeshInstance] to display.  Pass [code]null[/code]
## to clear the view (no mesh selected).
func set_target(node: GoBuildMeshInstance) -> void:
	if _canvas != null:
		_canvas.set_target(node)
	_update_zoom_label()


## Force a redraw of the canvas (called by the plugin after selection changes
## that don't trigger mesh_changed, e.g. mode switches).
func refresh() -> void:
	if _canvas != null:
		_canvas.queue_redraw()
	_update_zoom_label()


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Toolbar rows wrapped in a horizontal ScrollContainer so they scroll
	# if the dock is narrow, while the canvas below expands normally.
	var toolbar_scroll := ScrollContainer.new()
	toolbar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	toolbar_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	toolbar_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var toolbar_vbox := VBoxContainer.new()
	toolbar_scroll.add_child(toolbar_vbox)

	# Toolbar row 1.
	var header := HBoxContainer.new()
	toolbar_vbox.add_child(header)

	var title := Label.new()
	title.text = "UV View"
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", Color(0.70, 0.70, 0.70))
	header.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	_zoom_label = Label.new()
	_zoom_label.text = ""
	_zoom_label.add_theme_font_size_override("font_size", 10)
	_zoom_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	header.add_child(_zoom_label)

	var reset_btn := Button.new()
	reset_btn.text = "Reset"
	reset_btn.flat = true
	reset_btn.tooltip_text = "Reset pan and zoom to default."
	reset_btn.pressed.connect(_on_reset_pressed)
	header.add_child(reset_btn)

	toolbar_vbox.add_child(HSeparator.new())

	# Toolbar row 2 — transform mode buttons.
	var xform_bar := HBoxContainer.new()
	toolbar_vbox.add_child(xform_bar)

	_select_mode_btn = Button.new()
	_select_mode_btn.text = "Face"
	_select_mode_btn.flat = true
	_select_mode_btn.toggle_mode = true
	_select_mode_btn.button_pressed = true
	_select_mode_btn.tooltip_text = "Toggle UV selection mode: Face / Vertex (Tab)"
	_select_mode_btn.pressed.connect(_on_select_mode_pressed)
	xform_bar.add_child(_select_mode_btn)

	_move_btn = Button.new()
	_move_btn.text = "Move"
	_move_btn.flat = true
	_move_btn.tooltip_text = "Move UV island (W)"
	_move_btn.toggle_mode = true
	_move_btn.button_pressed = true
	_move_btn.pressed.connect(_on_move_pressed)
	xform_bar.add_child(_move_btn)

	_rotate_btn = Button.new()
	_rotate_btn.text = "Rotate"
	_rotate_btn.flat = true
	_rotate_btn.tooltip_text = "Rotate UV island (E)"
	_rotate_btn.toggle_mode = true
	_rotate_btn.pressed.connect(_on_rotate_pressed)
	xform_bar.add_child(_rotate_btn)

	_scale_btn = Button.new()
	_scale_btn.text = "Scale"
	_scale_btn.flat = true
	_scale_btn.tooltip_text = "Scale UV island (R)"
	_scale_btn.toggle_mode = true
	_scale_btn.pressed.connect(_on_scale_pressed)
	xform_bar.add_child(_scale_btn)

	_bg_btn = Button.new()
	_bg_btn.text = "BG:Checker"
	_bg_btn.flat = true
	_bg_btn.tooltip_text = "Cycle background: Checker / Texture / Off"
	_bg_btn.pressed.connect(_on_bg_pressed)
	xform_bar.add_child(_bg_btn)

	toolbar_vbox.add_child(HSeparator.new())

	# Toolbar row 3 — island operations.
	var island_bar := HBoxContainer.new()
	toolbar_vbox.add_child(island_bar)

	_pack_btn = Button.new()
	_pack_btn.text = "Pack"
	_pack_btn.flat = true
	_pack_btn.tooltip_text = "Pack all UV islands into the 0-1 tile."
	_pack_btn.pressed.connect(_on_pack_pressed)
	island_bar.add_child(_pack_btn)

	_stitch_btn = Button.new()
	_stitch_btn.text = "Stitch"
	_stitch_btn.flat = true
	_stitch_btn.tooltip_text = "Stitch selected UV islands that share edges."
	_stitch_btn.pressed.connect(_on_stitch_pressed)
	island_bar.add_child(_stitch_btn)

	var repeat_label := Label.new()
	repeat_label.text = "Repeat:"
	repeat_label.add_theme_font_size_override("font_size", 10)
	repeat_label.add_theme_color_override("font_color", Color(0.70, 0.70, 0.70))
	island_bar.add_child(repeat_label)

	_repeat_spin = SpinBox.new()
	_repeat_spin.min_value = 1
	_repeat_spin.max_value = 8
	_repeat_spin.value = 1
	_repeat_spin.step = 1
	_repeat_spin.tooltip_text = "Number of UV tile repeats shown in the view."
	_repeat_spin.value_changed.connect(_on_repeat_changed)
	island_bar.add_child(_repeat_spin)

	var spacer3 := Control.new()
	spacer3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	island_bar.add_child(spacer3)

	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xform_bar.add_child(spacer2)

	add_child(toolbar_scroll)
	add_child(HSeparator.new())

	# Canvas — occupies all remaining vertical space.
	_canvas = _CANVAS_SCRIPT.new()
	_canvas.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.clip_contents = true
	add_child(_canvas)
	if _plugin != null:
		_canvas.set_plugin(_plugin)

	_canvas.draw.connect(_update_zoom_label)
	_canvas.draw.connect(_update_transform_buttons)


# ---------------------------------------------------------------------------
# Handlers
# ---------------------------------------------------------------------------

func _on_reset_pressed() -> void:
	if _canvas != null:
		_canvas.reset_view()
	_update_zoom_label()


func _on_select_mode_pressed() -> void:
	if _canvas != null:
		if _canvas.get_uv_select_mode() == GoBuildUvCanvas.UvSelectMode.FACE:
			_canvas.set_uv_select_mode(GoBuildUvCanvas.UvSelectMode.VERTEX)
		else:
			_canvas.set_uv_select_mode(GoBuildUvCanvas.UvSelectMode.FACE)
	_update_select_mode_btn()


func _on_move_pressed() -> void:
	if _canvas != null:
		_canvas.set_transform_mode(GoBuildUvCanvas.UvTransformMode.MOVE)
	_update_transform_buttons()


func _on_rotate_pressed() -> void:
	if _canvas != null:
		_canvas.set_transform_mode(GoBuildUvCanvas.UvTransformMode.ROTATE)
	_update_transform_buttons()


func _on_scale_pressed() -> void:
	if _canvas != null:
		_canvas.set_transform_mode(GoBuildUvCanvas.UvTransformMode.SCALE)
	_update_transform_buttons()


func _on_bg_pressed() -> void:
	if _canvas != null:
		_canvas.cycle_bg_mode()
	_update_bg_label()


func _on_repeat_changed(value: float) -> void:
	if _canvas != null:
		_canvas.set_tile_repeat(int(value))


func _on_pack_pressed() -> void:
	if _canvas == null or _canvas._target == null or _canvas._target.go_build_mesh == null:
		return
	var gbm: GoBuildMesh = _canvas._target.go_build_mesh
	var snapshot := gbm.take_snapshot()
	var count := UvPackIslands.apply(gbm)
	_canvas._target.bake_in_place()
	if _plugin != null and count > 0:
		var ur: EditorUndoRedoManager = _plugin.get_undo_redo()
		ur.create_action("Pack UV Islands (%d)" % count)
		ur.add_do_method(_canvas._target, "restore_and_bake", gbm.take_snapshot())
		ur.add_undo_method(_canvas._target, "restore_and_bake", snapshot)
		ur.commit_action()
	_canvas.queue_redraw()


func _on_stitch_pressed() -> void:
	if _canvas == null or _canvas._target == null or _canvas._target.go_build_mesh == null:
		return
	var gbm: GoBuildMesh = _canvas._target.go_build_mesh
	var sel_faces: Array[int] = []
	if _canvas._target.selection.get_mode() == SelectionManager.Mode.FACE:
		sel_faces = _canvas._target.selection.get_selected_faces()
	if sel_faces.is_empty():
		return
	var snapshot := gbm.take_snapshot()
	var count := UvStitchIslands.apply(gbm, sel_faces)
	_canvas._target.bake_in_place()
	if _plugin != null and count > 0:
		var ur: EditorUndoRedoManager = _plugin.get_undo_redo()
		ur.create_action("Stitch UV Islands (%d merged)" % count)
		ur.add_do_method(_canvas._target, "restore_and_bake", gbm.take_snapshot())
		ur.add_undo_method(_canvas._target, "restore_and_bake", snapshot)
		ur.commit_action()
	_canvas.queue_redraw()


func _update_zoom_label() -> void:
	if _zoom_label == null or _canvas == null:
		return
	_zoom_label.text = "%d px/uv" % int(_canvas.get_zoom())


func _update_transform_buttons() -> void:
	if _move_btn == null or _canvas == null:
		return
	var mode: int = _canvas.get_transform_mode()
	_move_btn.button_pressed = (mode == GoBuildUvCanvas.UvTransformMode.MOVE)
	_rotate_btn.button_pressed = (mode == GoBuildUvCanvas.UvTransformMode.ROTATE)
	_scale_btn.button_pressed = (mode == GoBuildUvCanvas.UvTransformMode.SCALE)
	_update_select_mode_btn()


func _update_bg_label() -> void:
	if _bg_btn == null or _canvas == null:
		return
	var mode: int = _canvas.get_bg_mode()
	var labels: Array[String] = ["BG:Checker", "BG:Texture", "BG:Off"]
	_bg_btn.text = labels[mode]


func _update_select_mode_btn() -> void:
	if _select_mode_btn == null or _canvas == null:
		return
	var mode: int = _canvas.get_uv_select_mode()
	if mode == GoBuildUvCanvas.UvSelectMode.FACE:
		_select_mode_btn.text = "Face"
		_select_mode_btn.button_pressed = true
	else:
		_select_mode_btn.text = "Vertex"
		_select_mode_btn.button_pressed = false
