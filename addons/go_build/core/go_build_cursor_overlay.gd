## Shared 2D viewport-overlay cursor helpers.
##
## The knife tool and Create Polygon's polygon step use the same crosshair +
## rubber-band preview language.  Kept here so both draw identically.
@tool
class_name GoBuildCursorOverlay
extends RefCounted

const CROSSHAIR_COLOR := Color(1.0, 1.0, 1.0, 0.65)
const SNAP_DOT_COLOR := Color(1.0, 0.95, 0.5, 1.0)
const RUBBER_COLOR := Color(0.55, 0.92, 1.0, 0.55)


## Crosshair at [param cursor] (screen px): four short arms around a centre
## gap, plus a centre dot when [param snapped] is true.
static func draw_crosshair(overlay: Control, cursor: Vector2, snapped: bool) -> void:
	var gap := 4.0
	var arm := 6.0
	overlay.draw_line(cursor + Vector2(-gap - arm, 0), cursor + Vector2(-gap, 0),
			CROSSHAIR_COLOR, 1.5)
	overlay.draw_line(cursor + Vector2(gap, 0), cursor + Vector2(gap + arm, 0),
			CROSSHAIR_COLOR, 1.5)
	overlay.draw_line(cursor + Vector2(0, -gap - arm), cursor + Vector2(0, -gap),
			CROSSHAIR_COLOR, 1.5)
	overlay.draw_line(cursor + Vector2(0, gap), cursor + Vector2(0, gap + arm),
			CROSSHAIR_COLOR, 1.5)
	if snapped:
		overlay.draw_circle(cursor, 2.5, SNAP_DOT_COLOR)


## Rubber-band segment from [param from_screen] to [param to_screen].
static func draw_rubber_band(
		overlay: Control,
		from_screen: Vector2,
		to_screen: Vector2,
) -> void:
	overlay.draw_line(from_screen, to_screen, RUBBER_COLOR, 2.0)


## Faint closing-segment preview from [param from_screen] to the loop start.
static func draw_closing_preview(
		overlay: Control,
		from_screen: Vector2,
		to_screen: Vector2,
) -> void:
	overlay.draw_line(from_screen, to_screen, Color(0.55, 0.92, 1.0, 0.35), 1.0)