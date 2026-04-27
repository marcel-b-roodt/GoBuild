## Dock panel that hosts the [GoBuildUvCanvas] viewer.
##
## Registered as a second editor dock by [GoBuildPlugin].  When the active
## node changes the plugin calls [method set_target]; the embedded canvas
## automatically redraws on mesh or selection change.
##
## The panel is intentionally view-only in this first pass.  UV island
## editing (drag, rotate, scale) will be added in a later stage.
@tool
class_name GoBuildUvPanel
extends VBoxContainer

# Self-preload — ensures GoBuildUvCanvas is registered before use.
const _CANVAS_SCRIPT       := preload("res://addons/go_build/uv/go_build_uv_canvas.gd")
const _MESH_INSTANCE_SCRIPT := preload("res://addons/go_build/core/go_build_mesh_instance.gd")

var _canvas: GoBuildUvCanvas = null
var _zoom_label: Label       = null
var _plugin: EditorPlugin    = null


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Called by the plugin after the dock is registered.
func set_plugin(plugin: EditorPlugin) -> void:
	_plugin = plugin


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
	# Toolbar.
	var header := HBoxContainer.new()
	add_child(header)

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

	add_child(HSeparator.new())

	# Canvas — occupies all remaining vertical space.
	_canvas = _CANVAS_SCRIPT.new()
	_canvas.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.clip_contents = true
	add_child(_canvas)

	# Update zoom label whenever the canvas redraws.
	# Use a deferred call so the canvas has time to process input before label refresh.
	_canvas.draw.connect(_update_zoom_label)


# ---------------------------------------------------------------------------
# Handlers
# ---------------------------------------------------------------------------

func _on_reset_pressed() -> void:
	if _canvas != null:
		_canvas.reset_view()
	_update_zoom_label()


func _update_zoom_label() -> void:
	if _zoom_label == null or _canvas == null:
		return
	_zoom_label.text = "%d px/uv" % int(_canvas.get_zoom())
