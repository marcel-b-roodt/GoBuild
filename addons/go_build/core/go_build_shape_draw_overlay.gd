## Builds the overlay label strings for the interactive shape draw flow.
##
## Two labels are produced:
## - **State label** (bottom-left): describes the current draw step and available
##   modifiers.
## - **Dimensions label** (bottom-right): shows the current shape measurements.
@tool
class_name ShapeDrawOverlay
extends RefCounted

enum DrawState { IDLE, POSITION, WIDTH, LENGTH, HEIGHT, POLYGON }

const _MAPPING_SCRIPT := \
		preload("res://addons/go_build/mesh/generators/shape_param_mapping.gd")


static func state_label(
		shape_name: String,
		state: int,
		_shift_held: bool,
		_ctrl_held: bool,
		snap_mode: int = 0,
) -> String:
	if state == DrawState.IDLE:
		return ""
	match state:
		DrawState.POSITION:
			return "Create %s — Click to place" % shape_name
		DrawState.WIDTH:
			var shift_hint: String = "Shift: Circle" \
					if _MAPPING_SCRIPT.is_radial(shape_name) else "Shift: Square"
			return "Create %s — %s | Ctrl: Grid Snap | Drag sets width + orientation, click to fix" \
					% [shape_name, shift_hint]
		DrawState.LENGTH:
			var parts: Array[String] = ["Set Length/Depth", "Shift: Square",
					"Ctrl: %s Snap" % ("Grid" if snap_mode == 0 else "Delta")]
			if _MAPPING_SCRIPT.is_radial(shape_name):
				parts[0] = "Set Diameter"
			return "Create %s — %s" % [shape_name, " | ".join(parts)]
		DrawState.HEIGHT:
			var parts2: Array[String] = ["Set Height", "Shift: Uniform",
					"Ctrl: %s Snap" % ("Grid" if snap_mode == 0 else "Delta")]
			return "Create %s — %s" % [shape_name, " | ".join(parts2)]
		DrawState.POLYGON:
			return "Create %s — Click vertices, close loop or Enter to finish" % shape_name
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
	if state == DrawState.POLYGON:
		if drawn_height < 0.001:
			return ""
		return "H: %sm" % _fmt(drawn_height)
	if state == DrawState.WIDTH:
		return "W: %sm" % _fmt(drawn_width)
	if state == DrawState.LENGTH:
		if _MAPPING_SCRIPT.is_radial(shape_name):
			var r2: float = maxf(drawn_width, drawn_depth) / 2.0
			return "R: %sm  (W: %sm × D: %sm)" % \
					[_fmt(r2), _fmt(drawn_width), _fmt(drawn_depth)]
		return "W: %sm × D: %sm" % [_fmt(drawn_width), _fmt(drawn_depth)]
	var w: float = drawn_width
	var d: float = drawn_depth
	var h: float = drawn_height
	if _MAPPING_SCRIPT.is_radial(shape_name):
		var r: float = maxf(w, d) / 2.0
		return "R: %sm × H: %sm  (W: %sm × D: %sm)" \
				% [_fmt(r), _fmt(h), _fmt(w), _fmt(d)]
	if shape_name == "Plane":
		return "W: %sm × D: %sm" % [_fmt(w), _fmt(d)]
	return "W: %sm × D: %sm × H: %sm" % [_fmt(w), _fmt(d), _fmt(h)]


static func _fmt(v: float) -> String:
	if is_zero_approx(v):
		return "0"
	if absf(v) >= 100.0:
		return "%.1f" % v
	return "%.2f" % v