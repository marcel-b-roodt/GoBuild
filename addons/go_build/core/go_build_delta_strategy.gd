## Pure delta-strategy functions for [GoBuildDragController].
##
## Each function takes the current drag state and scene context, computes a delta
## value (float or [Vector3]), and returns it without mutating any state or
## modifying any mesh. The controller applies the result to the mesh and manages
## deferred baking, undo, and overlays.
##
## Strategies are intentionally stateless so they can be unit-tested without a
## scene tree. All mutable state lives in [GoBuildDragOperation] and
## [GoBuildDragController].
@tool
class_name GoBuildDeltaStrategy
extends RefCounted

const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _TRANSFORM_HELPERS_SCRIPT := preload(
		"res://addons/go_build/core/go_build_transform_helpers.gd")


## Result of a delta computation. The controller interprets this based on the
## [member delta_mode] stored in the [GoBuildDragOperation].
##
## For MODE_AXIS_PROJECT, MODE_PLANE_PROJECT, MODE_VIEWPORT_PLANE_PROJECT:
##   [member vec_value] is the local-space translation delta.
##
## For MODE_ROTATE:
##   [member float_value] is the signed angle in radians.
##
## For MODE_SCALE_AXIS, MODE_SCALE_UNIFORM:
##   [member float_value] is the scale ratio (1.0 = no change).
##
## For MODE_INSET:
##   [member float_value] is the lerp amount (0–1).
##
## For MODE_PARAM_RADIAL, MODE_PARAM_LINEAR:
##   [member float_value] is the raw delta from [GoBuildMouseTracker].
##
## [member needs_initialise] is [code]true[/code] when the strategy needs its
## initial reference point set from the current frame's hit/project result.
## The controller should store the returned [member vec_value] or
## [member float_value] as the anchor and call again.
class StrategyResult:
	var float_value: float = 0.0
	var vec_value: Vector3 = Vector3.ZERO
	var needs_initialise: bool = false


static func make_result_float(v: float) -> StrategyResult:
	var r := StrategyResult.new()
	r.float_value = v
	return r


static func make_result_vec(v: Vector3) -> StrategyResult:
	var r := StrategyResult.new()
	r.vec_value = v
	return r


static func make_result_init_float(v: float = 0.0) -> StrategyResult:
	var r := StrategyResult.new()
	r.needs_initialise = true
	r.float_value = v
	return r


static func make_result_init_vec(v: Vector3 = Vector3.ZERO) -> StrategyResult:
	var r := StrategyResult.new()
	r.needs_initialise = true
	r.vec_value = v
	return r


## Axis-project translate: project mouse onto an axis line through the centroid.
## Returns a [StrategyResult] with [member vec_value] = local-space translation.
##
## [param initial_t]: pass [code]INF[/code] on the first call; the strategy will
## return [code]needs_initialise = true[/code] and the controller must store
## [member float_value] as the initial t parameter.
static func axis_project(
		camera: Camera3D,
		screen_pos: Vector2,
		world_centroid: Vector3,
		world_axis: Vector3,
		node_transform: Transform3D,
		snap_step: float,
		snap_enabled: bool,
		precision_multiplier: float,
		initial_t: float,
) -> StrategyResult:
	var t_now: float = _TRANSFORM_HELPERS_SCRIPT.project_to_axis(
			camera, screen_pos, world_centroid, world_axis)
	if initial_t == INF:
		return make_result_init_float(t_now)
	var t_delta: float = t_now - initial_t
	if snap_enabled:
		t_delta = snappedf(t_delta, snap_step)
	t_delta *= precision_multiplier
	var delta_world: Vector3 = world_axis * t_delta
	var delta_local: Vector3 = node_transform.basis.inverse() * delta_world
	return make_result_vec(delta_local)


## Plane-project translate: project mouse onto a world-space plane through the
## centroid, compute world-space delta from an initial hit point.
## Returns [StrategyResult] with [member vec_value] = local-space translation.
##
## [param initial_hit]: pass [code]Vector3.ZERO[/code] on the first call with
## [param needs_init] = [code]true[/code].
static func plane_project(
		camera: Camera3D,
		screen_pos: Vector2,
		world_centroid: Vector3,
		world_normal: Vector3,
		node_transform: Transform3D,
		snap_step: float,
		snap_enabled: bool,
		precision_multiplier: float,
		initial_hit: Vector3,
		needs_init: bool,
) -> StrategyResult:
	if needs_init:
		var hit0: Vector3 = _TRANSFORM_HELPERS_SCRIPT.project_to_plane(
				camera, screen_pos, world_centroid, world_normal)
		if hit0 == Vector3.INF:
			return make_result_init_vec()
		return make_result_init_vec(hit0)
	var hit: Vector3 = _TRANSFORM_HELPERS_SCRIPT.project_to_plane(
			camera, screen_pos, world_centroid, world_normal)
	if hit == Vector3.INF:
		return make_result_vec(Vector3.ZERO)
	var delta_world: Vector3 = hit - initial_hit
	if snap_enabled:
		delta_world = delta_world.snapped(Vector3.ONE * snap_step)
	delta_world *= precision_multiplier
	var delta_local: Vector3 = node_transform.basis.inverse() * delta_world
	return make_result_vec(delta_local)


## Viewport-plane translate: project mouse onto a plane facing the camera
## through the centroid.
## Returns [StrategyResult] with [member vec_value] = local-space translation.
static func viewport_plane_project(
		camera: Camera3D,
		screen_pos: Vector2,
		world_centroid: Vector3,
		camera_forward: Vector3,
		node_transform: Transform3D,
		snap_step: float,
		snap_enabled: bool,
		precision_multiplier: float,
		initial_hit: Vector3,
		needs_init: bool,
) -> StrategyResult:
	if needs_init:
		var hit0: Vector3 = _TRANSFORM_HELPERS_SCRIPT.ray_plane_intersect(
				camera.project_ray_origin(screen_pos),
				camera.project_ray_normal(screen_pos),
				world_centroid, camera_forward)
		if hit0 == Vector3.INF:
			return make_result_init_vec()
		return make_result_init_vec(hit0)
	var hit: Vector3 = _TRANSFORM_HELPERS_SCRIPT.ray_plane_intersect(
			camera.project_ray_origin(screen_pos),
			camera.project_ray_normal(screen_pos),
			world_centroid, camera_forward)
	if hit == Vector3.INF:
		return make_result_vec(Vector3.ZERO)
	var delta_world: Vector3 = hit - initial_hit
	if snap_enabled:
		delta_world = delta_world.snapped(Vector3.ONE * snap_step)
	delta_world *= precision_multiplier
	var delta_local: Vector3 = node_transform.basis.inverse() * delta_world
	return make_result_vec(delta_local)


## Rotate: compute signed angle around [param rotation_axis] from a reference
## direction to the current mouse direction.
## Returns [StrategyResult] with [member float_value] = angle in radians.
##
## [param ref_dir]: the initial direction vector on the first frame.
## Pass [code]Vector3.ZERO[/code] with [param needs_init] = [code]true[/code].
static func rotate(
		camera: Camera3D,
		screen_pos: Vector2,
		world_centroid: Vector3,
		rotation_axis: Vector3,
		snap_step_rad: float,
		snap_enabled: bool,
		precision_multiplier: float,
		ref_dir: Vector3,
		needs_init: bool,
) -> StrategyResult:
	var hit: Vector3 = _TRANSFORM_HELPERS_SCRIPT.project_to_plane(
			camera, screen_pos, world_centroid, rotation_axis)
	if hit == Vector3.INF:
		return make_result_float(0.0)
	var dir: Vector3 = hit - world_centroid
	if dir.length_squared() < 1e-7:
		return make_result_float(0.0)
	dir = dir.normalized()
	if needs_init:
		var r := StrategyResult.new()
		r.needs_initialise = true
		r.vec_value = dir
		return r
	var delta_angle: float = ref_dir.signed_angle_to(dir, rotation_axis)
	if snap_enabled:
		delta_angle = snappedf(delta_angle, snap_step_rad)
	delta_angle *= precision_multiplier
	return make_result_float(delta_angle)


## Per-axis scale: compute a scale ratio from projection onto an axis.
## Returns [StrategyResult] with [member float_value] = scale ratio (1.0 = no change).
static func scale_axis(
		camera: Camera3D,
		screen_pos: Vector2,
		world_centroid: Vector3,
		world_axis: Vector3,
		snap_step: float,
		snap_enabled: bool,
		precision_multiplier: float,
		initial_t: float,
) -> StrategyResult:
	var t_now: float = _TRANSFORM_HELPERS_SCRIPT.project_to_axis(
			camera, screen_pos, world_centroid, world_axis)
	if initial_t == INF:
		return make_result_init_float(t_now)
	if abs(initial_t) < 1e-5:
		return make_result_float(1.0)
	var scale_ratio: float = t_now / initial_t
	if snap_enabled:
		scale_ratio = snappedf(scale_ratio, snap_step)
	scale_ratio = 1.0 + (scale_ratio - 1.0) * precision_multiplier
	return make_result_float(scale_ratio)


## Uniform scale: project mouse onto a camera-facing plane through the centroid,
## compute a ratio from initial distance to current projected distance.
## Returns [StrategyResult] with [member float_value] = scale ratio.
static func scale_uniform(
		camera: Camera3D,
		screen_pos: Vector2,
		world_centroid: Vector3,
		camera_forward: Vector3,
		snap_step: float,
		snap_enabled: bool,
		precision_multiplier: float,
		initial_dist: float,
		initial_dir: Vector3,
		needs_init: bool,
) -> StrategyResult:
	var hit: Vector3 = _TRANSFORM_HELPERS_SCRIPT.ray_plane_intersect(
			camera.project_ray_origin(screen_pos),
			camera.project_ray_normal(screen_pos),
			world_centroid, camera_forward)
	if hit == Vector3.INF:
		return make_result_float(1.0)
	if needs_init:
		var dist: float = hit.distance_to(world_centroid)
		if dist < 1e-3:
			return make_result_init_float(1.0)
		var r := StrategyResult.new()
		r.needs_initialise = true
		r.float_value = dist
		r.vec_value = hit - world_centroid
		return r
	if initial_dist < 1e-3:
		return make_result_float(1.0)
	var offset: Vector3 = hit - world_centroid
	var projected: float = offset.dot(initial_dir.normalized())
	var scale_ratio: float = projected / initial_dist
	if snap_enabled:
		scale_ratio = snappedf(scale_ratio, snap_step)
	scale_ratio = 1.0 + (scale_ratio - 1.0) * precision_multiplier
	return make_result_float(scale_ratio)


## Inset: compute a 0–1 lerp amount from screen-space horizontal offset.
## Returns [StrategyResult] with [member float_value] = inset amount (0–1).
static func inset(
		screen_pos: Vector2,
		snap_step: float,
		snap_enabled: bool,
		precision_multiplier: float,
		initial_screen: Vector2,
		inset_offset: float,
) -> StrategyResult:
	var offset: float = (screen_pos - initial_screen).dot(Vector2(1.0, 0.0))
	var amount: float = offset * 0.005
	if snap_enabled:
		amount = snappedf(amount, snap_step)
	amount *= precision_multiplier
	amount = clampf(amount + inset_offset, 0.0, 1.0)
	return make_result_float(amount)


## Param radial: delta is Euclidean distance from anchor, driven by
## [GoBuildMouseTracker].
## Returns [StrategyResult] with [member float_value] = param value.
static func param_radial(
		tracker_delta: float,
		param_start: float,
		precision_offset: float,
		sensitivity: float,
		precision_multiplier: float,
		param_min: float,
		param_max: float,
		snap_to_start: bool,
		snap_threshold: float,
) -> StrategyResult:
	var raw: float = param_start + precision_offset \
			+ tracker_delta * sensitivity * precision_multiplier
	var param: float = clampf(raw, param_min, param_max)
	if snap_to_start and absf(param - param_start) < snap_threshold:
		param = param_start
	return make_result_float(param)


## Param linear: delta is signed dot product against screen_direction.
static func param_linear(
		tracker_delta: float,
		param_start: float,
		precision_offset: float,
		sensitivity: float,
		precision_multiplier: float,
		param_min: float,
		param_max: float,
		snap_to_start: bool,
		snap_threshold: float,
) -> StrategyResult:
	var raw: float = param_start + precision_offset \
			+ tracker_delta * sensitivity * precision_multiplier
	var param: float = clampf(raw, param_min, param_max)
	if snap_to_start and absf(param - param_start) < snap_threshold:
		param = param_start
	return make_result_float(param)


# ---------------------------------------------------------------------------
# Per-frame delta strategies (accumulated from mm.relative)
#
# Each function takes a single frame's pixel delta (mm.relative), projects it
# onto the relevant screen-space axis/plane direction, and returns an
# incremental world-space delta.  The DragController accumulates these into
# cumulative totals, applying snap and clamp at the total level.
#
# Key property: because each frame's contribution is computed independently
# from mm.relative, veering off-axis can only reduce the magnitude of that
# frame's contribution — it cannot reverse the cumulative total.  The total
# only reverses when the user deliberately reverses direction.
# ---------------------------------------------------------------------------


## Per-frame axis translate: project one frame's pixel delta onto the
## screen-space direction of [param world_axis] and convert to world-space.
static func axis_project_frame(
		frame_delta: Vector2,
		camera: Camera3D,
		world_centroid: Vector3,
		world_axis: Vector3,
		node_xform: Transform3D,
		precision_multiplier: float,
) -> StrategyResult:
	var upp: float = compute_units_per_pixel(camera, world_centroid)
	if upp < 1e-7:
		return make_result_vec(Vector3.ZERO)
	var screen_dir: Vector2 = world_axis_to_screen(camera, world_centroid, world_axis)
	if screen_dir.length_squared() < 1e-8:
		return make_result_vec(Vector3.ZERO)
	var projected_pixels: float = frame_delta.dot(screen_dir)
	var world_delta: float = projected_pixels * upp * precision_multiplier
	var delta_world: Vector3 = world_axis.normalized() * world_delta
	var delta_local: Vector3 = node_xform.basis.inverse() * delta_world
	return make_result_vec(delta_local)


## Per-frame plane translate: decompose one frame's pixel delta into two
## screen-space tangent directions of the plane.
static func plane_project_frame(
		frame_delta: Vector2,
		camera: Camera3D,
		world_centroid: Vector3,
		world_normal: Vector3,
		node_xform: Transform3D,
		precision_multiplier: float,
) -> StrategyResult:
	var upp: float = compute_units_per_pixel(camera, world_centroid)
	if upp < 1e-7:
		return make_result_vec(Vector3.ZERO)
	var tangent_a: Vector3 = _plane_tangent_a(camera, world_normal)
	if tangent_a.length_squared() < 1e-10:
		return make_result_vec(Vector3.ZERO)
	var tangent_b: Vector3 = world_normal.cross(tangent_a).normalized()
	var screen_ea: Vector2 = world_axis_to_screen(camera, world_centroid, tangent_a)
	var screen_eb: Vector2 = world_axis_to_screen(camera, world_centroid, tangent_b)
	var proj_a: float = frame_delta.dot(screen_ea) * upp * precision_multiplier
	var proj_b: float = frame_delta.dot(screen_eb) * upp * precision_multiplier
	var delta_world: Vector3 = tangent_a * proj_a + tangent_b * proj_b
	var delta_local: Vector3 = node_xform.basis.inverse() * delta_world
	return make_result_vec(delta_local)


## Per-frame viewport-plane translate: like plane_project_frame but uses
## the camera's forward direction as the plane normal.
static func viewport_plane_project_frame(
		frame_delta: Vector2,
		camera: Camera3D,
		world_centroid: Vector3,
		node_xform: Transform3D,
		precision_multiplier: float,
) -> StrategyResult:
	var camera_forward: Vector3 = -camera.global_transform.basis.z
	return plane_project_frame(frame_delta, camera, world_centroid,
			camera_forward, node_xform, precision_multiplier)


## Per-frame rotate: project one frame's pixel delta onto the screen-space
## perpendicular of the rotation axis and convert to an angular delta.
static func rotate_frame(
		frame_delta: Vector2,
		camera: Camera3D,
		world_centroid: Vector3,
		rotation_axis: Vector3,
		precision_multiplier: float,
) -> StrategyResult:
	var upp: float = compute_units_per_pixel(camera, world_centroid)
	if upp < 1e-7:
		return make_result_float(0.0)
	var screen_axis: Vector2 = world_axis_to_screen(camera, world_centroid, rotation_axis)
	if screen_axis.length_squared() < 1e-8:
		return make_result_float(0.0)
	var screen_perp: Vector2 = Vector2(-screen_axis.y, screen_axis.x)
	var angular_pixels: float = frame_delta.dot(screen_perp)
	var radius_pixels: float = 10.0
	var angle: float = angular_pixels * upp / radius_pixels * precision_multiplier
	return make_result_float(angle)


## Per-frame axis scale: project one frame's pixel delta onto the axis
## direction and return an incremental scale delta.
static func scale_axis_frame(
		frame_delta: Vector2,
		camera: Camera3D,
		world_centroid: Vector3,
		world_axis: Vector3,
		initial_world_size: float,
		precision_multiplier: float,
) -> StrategyResult:
	if initial_world_size < 1e-5:
		return make_result_float(0.0)
	var upp: float = compute_units_per_pixel(camera, world_centroid)
	if upp < 1e-7:
		return make_result_float(0.0)
	var screen_dir: Vector2 = world_axis_to_screen(camera, world_centroid, world_axis)
	if screen_dir.length_squared() < 1e-8:
		return make_result_float(0.0)
	var projected_pixels: float = frame_delta.dot(screen_dir)
	var world_delta: float = projected_pixels * upp / initial_world_size * precision_multiplier
	return make_result_float(world_delta)


## Per-frame uniform scale: project one frame's pixel delta onto a screen
## direction and return an incremental scale delta.
static func scale_uniform_frame(
		frame_delta: Vector2,
		camera: Camera3D,
		world_centroid: Vector3,
		camera_forward: Vector3,
		initial_world_size: float,
		precision_multiplier: float,
) -> StrategyResult:
	if initial_world_size < 1e-5:
		return make_result_float(0.0)
	var upp: float = compute_units_per_pixel(camera, world_centroid)
	if upp < 1e-7:
		return make_result_float(0.0)
	var screen_up: Vector2 = world_axis_to_screen(camera, world_centroid,
			camera_forward.cross(Vector3.UP).normalized() + Vector3.UP)
	if screen_up.length_squared() < 1e-8:
		screen_up = Vector2.UP
	var projected_pixels: float = frame_delta.dot(screen_up.normalized())
	var world_delta: float = projected_pixels * upp / initial_world_size * precision_multiplier
	return make_result_float(world_delta)


## Per-frame inset: horizontal pixel delta converted to inset delta.
static func inset_frame(
		frame_delta: Vector2,
		precision_multiplier: float,
) -> StrategyResult:
	var offset: float = frame_delta.dot(Vector2(1.0, 0.0)) * 0.005 * precision_multiplier
	return make_result_float(offset)


## Compute world-space distance per screen pixel at [param world_point].
##
## Projects two points 1 pixel apart at the depth of [param world_point] and
## measures their separation in world space.  This adapts automatically to
## camera zoom, perspective, and viewport size.
static func compute_units_per_pixel(camera: Camera3D, world_point: Vector3) -> float:
	var vp_size: Vector2 = camera.get_viewport().get_visible_rect().size
	var depth: float = world_point.distance_to(camera.global_position)
	if depth < 1e-4:
		return 0.0
	var p0: Vector3 = camera.project_position(vp_size * 0.5, depth)
	var p1: Vector3 = camera.project_position(vp_size * 0.5 + Vector2(1.0, 0.0), depth)
	return p0.distance_to(p1)


## Project [param world_direction] into a 2D screen-space direction.
##
## Returns the normalised direction vector in screen coordinates.
## This is the fundamental operation for per-frame delta strategies: it
## converts a world-space axis to its appearance on screen, so per-frame
## pixel displacement can be projected onto it.
static func world_axis_to_screen(camera: Camera3D, world_origin: Vector3,
		world_direction: Vector3) -> Vector2:
	var p0: Vector2 = camera.unproject_position(world_origin)
	var p1: Vector2 = camera.unproject_position(world_origin + world_direction)
	var screen_dir: Vector2 = (p1 - p0).normalized()
	if screen_dir.length_squared() < 1e-8:
		return Vector2.ZERO
	return screen_dir


## Compute a screen-perpendicular tangent to [param world_normal] as seen by
## [param camera].  Used by plane-project strategies to decompose pixel offset
## into two independent axes on the plane.
static func _plane_tangent_a(camera: Camera3D, world_normal: Vector3) -> Vector3:
	var cam_up: Vector3 = camera.global_transform.basis.y
	var tangent: Vector3 = cam_up - world_normal * cam_up.dot(world_normal)
	if tangent.length_squared() < 1e-10:
		cam_up = camera.global_transform.basis.x
		tangent = cam_up - world_normal * cam_up.dot(world_normal)
	if tangent.length_squared() < 1e-10:
		return Vector3.RIGHT
	return tangent.normalized()