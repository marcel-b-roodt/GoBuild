## Parameter editor for UV projection operations.
##
## Shows Scale, U Offset, V Offset, and optionally a Seam Rotation spinbox,
## plus Accept and Cancel buttons.  Used by [GoBuildPanel] to let the user
## preview and adjust UV projection parameters before committing them.
##
## Usage (panel side):
##   _uv_param_box = GoBuildUvParamBox.new()
##   _uv_param_box.params_changed.connect(_on_uv_params_preview)
##   _uv_param_box.apply_requested.connect(_on_uv_params_apply)
##   _uv_param_box.cancelled.connect(_on_uv_params_cancelled)
##   add_child(_uv_param_box)
##   _uv_param_box.setup("Sphere UV", true, 1.0, Vector2.ZERO, 0.0)
@tool
class_name GoBuildUvParamBox
extends VBoxContainer

## Emitted on every spinbox change so the panel can show a live preview.
## [param params] always has keys: [code]scale[/code], [code]u_offset[/code],
## [code]v_offset[/code], [code]seam_rotation[/code].
signal params_changed(params: Dictionary)

## Emitted when the user clicks Accept.
signal apply_requested(params: Dictionary)

## Emitted when the user clicks Cancel.
signal cancelled

var _title_label: Label = null
var _grid: GridContainer = null
var _seam_row_label: Label = null
var _seam_spin: SpinBox = null
var _accept_btn: Button = null
var _cancel_btn: Button = null

var _scale_spin: SpinBox = null
var _u_offset_spin: SpinBox = null
var _v_offset_spin: SpinBox = null

var _params: Dictionary = {}
var _has_seam_rotation: bool = false


func _ready() -> void:
	visible = false

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 11)
	_title_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	add_child(_title_label)

	_grid = GridContainer.new()
	_grid.columns = 2
	add_child(_grid)

	_build_grid()

	var actions := HBoxContainer.new()
	add_child(actions)

	_accept_btn = Button.new()
	_accept_btn.text = "Accept"
	_accept_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_accept_btn.pressed.connect(_on_accept_pressed)
	actions.add_child(_accept_btn)

	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel"
	_cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cancel_btn.pressed.connect(_on_cancel_pressed)
	actions.add_child(_cancel_btn)


## Configure and show the param box for a UV projection operation.
##
## [param mode_name] is used as the title (e.g. "Sphere UV").
## [param has_seam] controls visibility of the Seam Rotation row.
## The remaining params are the starting values for the spinboxes.
func setup(
		mode_name: String,
		has_seam: bool,
		initial_scale: float = 1.0,
		initial_offset: Vector2 = Vector2.ZERO,
		initial_seam_rotation: float = 0.0,
) -> void:
	_title_label.text = mode_name + " Parameters"
	_has_seam_rotation = has_seam

	_params = {
		"scale": initial_scale,
		"u_offset": initial_offset.x,
		"v_offset": initial_offset.y,
		"seam_rotation": initial_seam_rotation,
	}

	_scale_spin.set_value_no_signal(initial_scale)
	_u_offset_spin.set_value_no_signal(initial_offset.x)
	_v_offset_spin.set_value_no_signal(initial_offset.y)
	_seam_spin.set_value_no_signal(initial_seam_rotation)
	_seam_row_label.visible = has_seam
	_seam_spin.visible = has_seam

	visible = true


## Hide the param box without emitting any signal.
## Used internally and by the panel when it needs to forcibly close the box.
func hide_box() -> void:
	visible = false
	_params = {}


## Returns the current parameter values.
func get_params() -> Dictionary:
	return _params.duplicate()


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _build_grid() -> void:
	_scale_spin     = _add_spin("scale",        "Scale",        0.01, 100.0, 0.01, 1.0)
	_u_offset_spin  = _add_spin("u_offset",     "U Offset",   -10.0,  10.0, 0.01, 0.0)
	_v_offset_spin  = _add_spin("v_offset",     "V Offset",   -10.0,  10.0, 0.01, 0.0)
	_seam_row_label = _add_spin_with_label_ref(
			"seam_rotation", "Seam Rot",  -360.0, 360.0, 1.0, 0.0)
	_seam_row_label.visible = false
	_seam_spin.visible = false


func _add_spin(
		key: String,
		label: String,
		min_value: float,
		max_value: float,
		step: float,
		default_value: float,
) -> SpinBox:
	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_font_size_override("font_size", 11)
	_grid.add_child(lbl)

	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.allow_greater = false
	spin.allow_lesser = false
	spin.value = default_value
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(_on_spin_changed.bind(key))
	_grid.add_child(spin)
	return spin


## Like [method _add_spin] but also returns the label node (for seam row visibility control).
func _add_spin_with_label_ref(
		key: String,
		label: String,
		min_value: float,
		max_value: float,
		step: float,
		default_value: float,
) -> Label:
	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_font_size_override("font_size", 11)
	_grid.add_child(lbl)

	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.allow_greater = false
	spin.allow_lesser = false
	spin.value = default_value
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(_on_spin_changed.bind(key))
	_grid.add_child(spin)
	_seam_spin = spin
	return lbl


func _on_spin_changed(value: float, key: String) -> void:
	_params[key] = value
	params_changed.emit(_params.duplicate())


func _on_accept_pressed() -> void:
	apply_requested.emit(_params.duplicate())
	visible = false
	_params = {}


func _on_cancel_pressed() -> void:
	visible = false
	_params = {}
	cancelled.emit()
