## A [SpinBox] that emits [signal spin_committed] when a spin-drag ends
## (mouse up after dragging the arrows) or when the user presses Enter in the
## LineEdit.
##
## Standard [SpinBox] only emits [signal value_changed] on every tick while
## dragging, with no signal for "editing ended". This control fills that gap
## by polling [method Input.is_mouse_button_pressed] each frame to detect when
## a left-button drag release occurs after a value change.
##
## Usage:
##   - Connect [signal spin_committed] to your undo/commit handler.
##   - Connect [signal value_changed] to your live-update/preview handler.
##   - Call [method configure] instead of setting properties individually for
##     convenience.
@tool
class_name GoBuildUndoSpinBox
extends SpinBox

## Emitted when the user finishes editing: either by releasing a spin-drag
## or by pressing Enter in the LineEdit.  The [param current_value] is the
## spinbox's current value at commit time.
signal spin_committed(current_value: float)

## True while we detect a mouse-drag on the spin arrows.
var _dragging: bool = false

## Set to true on every [signal value_changed] tick; cleared at end of frame.
var _value_changed_this_frame: bool = false


func _ready() -> void:
	value_changed.connect(_on_value_changed)
	# Defer LineEdit connection so SpinBox internals are ready.
	call_deferred("_connect_line_edit")


func _process(_delta: float) -> void:
	var left_down: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	# Detect spin-drag start: left button is held and a value tick happened.
	if left_down and _value_changed_this_frame:
		_dragging = true
	# Detect spin-drag end: left button released after a drag.
	if _dragging and not left_down:
		_dragging = false
		spin_committed.emit(value)
	_value_changed_this_frame = false


func _on_value_changed(_v: float) -> void:
	_value_changed_this_frame = true


func _on_line_edit_text_submitted(_text: String) -> void:
	spin_committed.emit(value)


func _connect_line_edit() -> void:
	var le: LineEdit = get_line_edit()
	if le != null:
		le.text_submitted.connect(_on_line_edit_text_submitted)


## Convenience: set [member min_value], [member max_value], [member step],
## [member value], and optional [member suffix] in one call.
func configure(
		min_val: float,
		max_val: float,
		step_val: float,
		initial: float,
		suffix_text: String = "",
) -> void:
	min_value = min_val
	max_value = max_val
	step = step_val
	value = initial
	if suffix_text != "":
		suffix = suffix_text