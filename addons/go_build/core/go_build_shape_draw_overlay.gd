## Builds the overlay label strings for the interactive shape draw flow.
##
## Two labels are produced:
## - **State label** (bottom-left): describes the current draw step and available
##   modifiers.
## - **Dimensions label** (bottom-right): shows the current shape measurements.
@tool
class_name ShapeDrawOverlay
extends RefCounted

enum DrawState { IDLE, POSITION, BASE, HEIGHT }

const _MAPPING_SCRIPT := \
		preload("res://addons/go_build/mesh/generators/shape_param_mapping.gd")


static func state_label(
		shape_name: String,
		state: int,
		_shift_held: bool,
		_ctrl_held: bool,
) -> String:
	if state == DrawState.IDLE:
		return ""
	match state:
		DrawState.POSITION:
			return "Create %s — Click to place" % shape_name
		DrawState.BASE:
			var shift_hint: String = "Shift: Circle" \
					if _MAPPING_SCRIPT.is_radial(shape_name) else "Shift: Square"
			var parts: Array[String] = ["Set Width/Depth", shift_hint, "Ctrl: Snap"]
			return "Create %s — %s" % [shape_name, " | ".join(parts)]
		DrawState.HEIGHT:
			var parts2: Array[String] = ["Set Height", "Shift: Uniform", "Ctrl: Snap"]
			return "Create %s — %s" % [shape_name, " | ".join(parts2)]
	return ""


static func dims_label(
		shape_name: String,
		state: int,
		drawn_width: float,
		drawn_depth: float,
		drawn_height: float,
) -> String:
	if state == DrawState.IDLE or state == DrawState.POSITION:
		return ""
	if drawn_width < 0.001 and drawn_depth < 0.001:
		return ""
	var w: float = drawn_width
	var d: float = drawn_depth
	var h: float = drawn_height
	if _MAPPING_SCRIPT.is_radial(shape_name):
		var r: float = maxf(w, d) / 2.0
		if state == DrawState.BASE:
			return "R: %sm  (W: %sm × D: %sm)" % [_fmt(r), _fmt(w), _fmt(d)]
		return "R: %sm × H: %sm  (W: %sm × D: %sm)" \
				% [_fmt(r), _fmt(h), _fmt(w), _fmt(d)]
	if shape_name == "Plane":
		return "W: %sm × D: %sm" % [_fmt(w), _fmt(d)]
	if state == DrawState.BASE:
		return "W: %sm × D: %sm" % [_fmt(w), _fmt(d)]
	return "W: %sm × D: %sm × H: %sm" % [_fmt(w), _fmt(d), _fmt(h)]


static func _fmt(v: float) -> String:
	if is_zero_approx(v):
		return "0"
	if absf(v) >= 100.0:
		return "%.1f" % v
	return "%.2f" % v