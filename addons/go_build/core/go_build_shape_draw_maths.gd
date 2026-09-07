## Pure draw-flow maths for the shape draw controller.
##
## All functions are static and side-effect free: they take the current
## draw state (anchor, cursor projection, surface normal, modifiers,
## snap step and mode) and return the resulting dimensions and basis.
## No camera, no Input, no scene tree — trivially unit-testable.
##
## Snap semantics (DrawSnapMode):
##  - WORLD_GRID: the cursor POSITION is snapped to the full 3D world grid
##    before deriving dimensions — grid-aligned footprints by construction.
##    Height snaps the TOP face's absolute coordinate to the grid.
##  - DELTA_GRID: the dimension VALUE (width / depth / height) is snapped.
@tool
class_name ShapeDrawMaths
extends RefCounted

enum SnapMode { WORLD_GRID, DELTA_GRID }

const _MIN_DIM: float = 0.01


## Snap a world position to the full 3D world grid.
static func world_snap(pos: Vector3, step: float) -> Vector3:
	return Vector3(snappedf(pos.x, step), snappedf(pos.y, step),
			snappedf(pos.z, step))


## Build the orientation basis from the width direction: local +X along
## [param u], +Y = surface up [param n], +Z = u × n (perpendicular, right-handed).
static func basis_from_width_dir(u: Vector3, n: Vector3) -> Basis:
	var x := u.normalized()
	var y := n.normalized()
	if absf(x.dot(y)) > 0.999:
		y = Vector3.UP if absf(x.dot(Vector3.UP)) < 0.999 else Vector3.RIGHT
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


## WIDTH step result from the projected cursor [param target].
## Returns {} when the segment is degenerate (below minimum dimension).
## Keys: "width" (float), "basis" (Basis).
static func width_result(
		anchor: Vector3,
		target: Vector3,
		normal: Vector3,
		step: float,
		ctrl_held: bool,
) -> Dictionary:
	if ctrl_held and step > 0.0:
		target = world_snap(target, step)
	var diff: Vector3 = target - anchor
	var w: float = diff.length()
	if w < _MIN_DIM:
		return {}
	if ctrl_held and step > 0.0:
		w = snappedf(w, step)
	var u := diff.normalized()
	return {"width": maxf(w, _MIN_DIM), "basis": basis_from_width_dir(u, normal)}


## LENGTH step result.  Returns {} when the depth is degenerate.
## Keys: "depth" (float, absolute), "drag_dir_z" (float, sign).
static func length_result(
		anchor: Vector3,
		target: Vector3,
		basis: Basis,
		width: float,
		shift_held: bool,
		ctrl_held: bool,
		step: float,
) -> Dictionary:
	if ctrl_held and step > 0.0:
		target = world_snap(target, step)
	var signed_d: float = (target - anchor).dot(basis.z)
	if shift_held:
		signed_d = width * signf(signed_d) if absf(signed_d) > _MIN_DIM \
				else width
	if ctrl_held and step > 0.0 and absf(signed_d) > _MIN_DIM:
		signed_d = snappedf(signed_d, step)
	if absf(signed_d) < _MIN_DIM:
		return {}
	return {"depth": absf(signed_d), "drag_dir_z": signf(signed_d)}


## HEIGHT step result from the raw cursor hit on the height plane.
## Keys: "height" (float).
static func height_result(
		anchor: Vector3,
		plane_hit: Vector3,
		normal_dir: Vector3,
		ctrl_held: bool,
		step: float,
) -> Dictionary:
	var raw_h: float = (plane_hit - anchor).dot(normal_dir)
	if ctrl_held and step > 0.0:
		# Snap the TOP face's absolute coordinate to the world grid:
		# the shape's top lands on a grid plane even from off-grid
		# surfaces.  (The value itself is then also grid-quantized
		# whenever the anchor is.)
		var anchor_h: float = anchor.dot(normal_dir)
		raw_h = snappedf(anchor_h + raw_h, step) - anchor_h
	return {"height": maxf(raw_h, _MIN_DIM)}