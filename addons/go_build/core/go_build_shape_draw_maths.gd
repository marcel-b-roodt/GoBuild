## Pure draw-flow maths for the shape draw controller.
##
## All functions are static and side-effect free: they take the current
## draw state (anchor, cursor projection, surface normal, modifiers,
## snap step and mode) and return the resulting dimensions and basis.
## No camera, no Input, no scene tree — trivially unit-testable.
##
## Snap semantics (mirroring the gizmo drag modes in
## GoBuildDragOperation.SnapMode), applied whenever Ctrl is held:
##  - SMART: the cursor POSITION is snapped to the full 3D world grid before
##    deriving dimensions — grid-aligned geometry by construction.  Dimension
##    VALUES are NOT re-quantized: with an off-grid anchor the length between
##    the anchor and the snapped cursor is whatever the grid dictates (the
##    far edge lands on a grid plane; re-quantizing would push it off).
##  - DELTA: positions stay freehand; the dimension VALUES (width / depth /
##    height) are quantized to the grid step as freehand increments.
##  - Height snaps the TOP face's absolute coordinate to the grid in both
##    modes (Smart = grid semantics; Delta = the absolute top is still the
##    meaningful measure to keep in step increments).
@tool
class_name ShapeDrawMaths
extends RefCounted

const _MIN_DIM: float = 0.01


## Snap mode values, mirroring [enum GoBuildDragOperation.SnapMode]
## (0 = SMART, 1 = DELTA) without a compile-time preload cycle.
const SNAP_SMART: int = 0
const SNAP_DELTA: int = 1


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
		snap_mode: int = SNAP_SMART,
) -> Dictionary:
	if ctrl_held and step > 0.0:
		if snap_mode == SNAP_SMART:
			target = world_snap(target, step)
			var diff_snap: Vector3 = target - anchor
			var w_snap: float = diff_snap.length()
			if w_snap < _MIN_DIM:
				return {}
			return {"width": w_snap, "basis": basis_from_width_dir(
					diff_snap.normalized(), normal)}
		var diff0: Vector3 = target - anchor
		var w0: float = snappedf(diff0.length(), step)
		if w0 < _MIN_DIM:
			return {}
		var u0 := diff0.normalized()
		return {"width": w0, "basis": basis_from_width_dir(u0, normal)}
	var diff: Vector3 = target - anchor
	var w: float = diff.length()
	if w < _MIN_DIM:
		return {}
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
		snap_mode: int = SNAP_SMART,
) -> Dictionary:
	if ctrl_held and step > 0.0:
		if snap_mode == SNAP_SMART:
			target = world_snap(target, step)
		else:
			var signed_d0: float = (target - anchor).dot(basis.z)
			if shift_held:
				signed_d0 = width * signf(signed_d0) \
						if absf(signed_d0) > _MIN_DIM else width
			elif absf(signed_d0) > _MIN_DIM:
				signed_d0 = snappedf(signed_d0, step)
			if absf(signed_d0) < _MIN_DIM:
				return {}
			return {"depth": absf(signed_d0), "drag_dir_z": signf(signed_d0)}
	var signed_d: float = (target - anchor).dot(basis.z)
	if shift_held:
		signed_d = width * signf(signed_d) if absf(signed_d) > _MIN_DIM \
				else width
	if absf(signed_d) < _MIN_DIM:
		return {}
	return {"depth": absf(signed_d), "drag_dir_z": signf(signed_d)}


## HEIGHT step result from the raw cursor hit on the height plane.
## Keys: "height" (float).
## [param snap_mode] is reserved for future mode-specific height snapping;
## both modes currently snap the TOP face's absolute coordinate.
static func height_result(
		anchor: Vector3,
		plane_hit: Vector3,
		normal_dir: Vector3,
		ctrl_held: bool,
		step: float,
		_snap_mode: int = SNAP_SMART,
) -> Dictionary:
	var raw_h: float = (plane_hit - anchor).dot(normal_dir)
	if ctrl_held and step > 0.0:
		# Snap the TOP face's absolute coordinate to the world grid in
		# BOTH modes: Smart keeps the top on a grid plane; Delta keeps
		# the absolute top in whole-step increments from the world
		# origin (the top position is the meaningful measure there).
		var anchor_h: float = anchor.dot(normal_dir)
		raw_h = snappedf(anchor_h + raw_h, step) - anchor_h
	return {"height": maxf(raw_h, _MIN_DIM)}