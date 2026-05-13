## Abstracts raw mouse input into a clean delta-tracking interface for drag operations.
##
## [GoBuildMouseTracker] sits between raw [InputEventMouseMotion] events and the
## [GoBuildDragController]. It owns the accumulated delta, anchor position,
## precision state, and snap state so that the controller never touches raw input
## directly.
##
## Infinite scroll: when active, the tracker expects the cursor to be warped to
## viewport center by the caller after each [method feed] call. After a warp,
## the next [method feed] call will see a synthetic motion event whose position
## is near the warp target. The tracker detects this via [member _warp_pending]
## and discards the artefact. The caller is responsible for calling
## [method Input.warp_mouse] and setting [member _warp_pending] to true, or
## calling [method request_warp] which sets the flag.
@tool
class_name GoBuildMouseTracker
extends RefCounted

const PRECISION_MULTIPLIER: float = 0.1

## Minimum distance from the viewport edge (in pixels) before warping kicks in.
const WARP_MARGIN: float = 20.0

var _active: bool = false
var _anchor: Vector2 = Vector2.ZERO
var _accumulated: Vector2 = Vector2.ZERO
var _prev_shift: bool = false
var _precision_offset: float = 0.0
var _current_precision: float = 1.0
var _filter_count: int = 0

var _accumulated_delta: float = 0.0
var _sensitivity: float = 1.0
var _radial: bool = true
var _screen_direction: Vector2 = Vector2(1.0, 0.0)

var _viewport_size: Vector2 = Vector2(1280.0, 720.0)

## When true, the next [method feed] call will discard its relative delta because
## it is a synthetic motion caused by [method Input.warp_mouse] repositioning the
## cursor back to center.
var _warp_pending: bool = false

## Screen position where the cursor was warped to. Used to detect the synthetic
## warp event: if [code]event.position[/code] is close to this point, the event
## is the warp artefact and should be discarded.
var _warp_target: Vector2 = Vector2.ZERO


func begin(anchor: Vector2, viewport_size: Vector2, radial: bool,
		screen_direction: Vector2, sensitivity: float) -> void:
	_active = true
	_anchor = anchor
	_viewport_size = viewport_size
	_accumulated = anchor
	_prev_shift = Input.is_key_pressed(KEY_SHIFT)
	_precision_offset = 0.0
	_current_precision = PRECISION_MULTIPLIER if _prev_shift else 1.0
	_filter_count = 4
	_accumulated_delta = 0.0
	_sensitivity = sensitivity
	_radial = radial
	_screen_direction = screen_direction
	_warp_pending = false
	_warp_target = _viewport_size * 0.5


func feed(event: InputEventMouseMotion) -> void:
	if not _active:
		return
	if _warp_pending:
		if event.position.distance_squared_to(_warp_target) < 25.0 * 25.0:
			_warp_pending = false
			return
		_warp_pending = false
	if _filter_count > 0:
		if event.relative.length_squared() > 50.0 * 50.0:
			_filter_count -= 1
			return
		_filter_count = 0
	_accumulated += event.relative
	var shift_now: bool = event.shift_pressed
	if shift_now != _prev_shift:
		var old_p: float = PRECISION_MULTIPLIER if _prev_shift else 1.0
		var new_p: float = PRECISION_MULTIPLIER if shift_now else 1.0
		_precision_offset += _accumulated_delta * _sensitivity * (old_p - new_p)
		_prev_shift = shift_now
		_current_precision = new_p
	_compute_delta()


func feed_raw_delta(delta: Vector2, shift_pressed: bool) -> void:
	if not _active:
		return
	_accumulated += delta
	var shift_now: bool = shift_pressed
	if shift_now != _prev_shift:
		var old_p: float = PRECISION_MULTIPLIER if _prev_shift else 1.0
		var new_p: float = PRECISION_MULTIPLIER if shift_now else 1.0
		_precision_offset += _accumulated_delta * _sensitivity * (old_p - new_p)
		_prev_shift = shift_now
		_current_precision = new_p
	_compute_delta()


func end() -> void:
	_active = false
	_anchor = Vector2.ZERO
	_accumulated = Vector2.ZERO
	_precision_offset = 0.0
	_accumulated_delta = 0.0
	_current_precision = 1.0
	_prev_shift = false
	_filter_count = 0
	_warp_pending = false


func is_active() -> bool:
	return _active


func get_anchor() -> Vector2:
	return _anchor


func get_virtual_pos() -> Vector2:
	return _accumulated


func get_delta() -> float:
	return _accumulated_delta


func get_precision_multiplier() -> float:
	return _current_precision


func get_precision_offset() -> float:
	return _precision_offset


func get_viewport_size() -> Vector2:
	return _viewport_size


func get_raw_offset_from_anchor() -> Vector2:
	return _accumulated - _anchor


func reset_filter() -> void:
	_filter_count = 0


## When the caller's param strategy clamps the computed value to a min/max bound,
## the tracker's accumulated delta includes invisible "excess" movement past that
## bound. This method folds that excess back so the next frame's delta starts
## from the clamped position rather than requiring the user to "undo" the invisible
## accumulation.
##
## [param consumed_delta]: the tracker delta that actually contributed to the
## clamped result (i.e. the delta that maps from [member param_start] to the
## clamped value).
func fold_clamp_excess(consumed_delta: float) -> void:
	var excess: float = _accumulated_delta - consumed_delta
	if not _radial:
		_accumulated -= _screen_direction * excess
	_accumulated_delta = consumed_delta


## Returns the screen position of the indicator cursor, scaled by the current
## precision multiplier so the visual movement matches the actual param change rate.
##
## Without this, the indicator dot moves at full speed regardless of precision mode,
## while the param only changes at 10% — the line appears disproportionately long
## for tiny changes. This method produces a position that:
## - Is continuous across precision mode switches (no visual jump)
## - Moves at precision-scaled speed (10% speed in precision mode)
## - Reverses correctly (no dead zone)
## - Uses the raw mouse direction for radial drags
func get_indicator_pos() -> Vector2:
	var effective_delta: float = _precision_offset / _sensitivity \
			+ _accumulated_delta * _current_precision
	var raw_offset: Vector2 = _accumulated - _anchor
	if _radial:
		var raw_len: float = raw_offset.length()
		if raw_len < 0.001:
			return _anchor
		var direction: Vector2 = raw_offset / raw_len
		return _anchor + direction * effective_delta
	return _anchor + _screen_direction * effective_delta


func _compute_delta() -> void:
	var offset: Vector2 = _accumulated - _anchor
	if _radial:
		_accumulated_delta = offset.length()
	else:
		_accumulated_delta = offset.dot(_screen_direction)


## Mark that a cursor warp has just occurred. The next [method feed] call will
## check [member _warp_pending] and discard the synthetic motion event whose
## position is near [member _warp_target].
##
## The caller is responsible for calling [method Input.warp_mouse] to the
## viewport center and then calling this method to set the flag.
func request_warp() -> void:
	_warp_target = _viewport_size * 0.5
	_warp_pending = true