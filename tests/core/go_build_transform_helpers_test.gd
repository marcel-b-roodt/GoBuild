## Unit tests for [GoBuildTransformHelpers].
##
## Pure-logic tests — no scene tree required.
## Tests the pure-math helpers that underpin the gizmo drag system.
## Run via the GdUnit4 panel in the Godot editor.
@tool
extends GdUnitTestSuite

const _HELPERS_SCRIPT := preload("res://addons/go_build/core/go_build_transform_helpers.gd")


# ---------------------------------------------------------------------------
# get_local_axis
# ---------------------------------------------------------------------------

func test_get_local_axis_x() -> void:
	assert_vector(GoBuildTransformHelpers.get_local_axis(0)).is_equal(Vector3.RIGHT)


func test_get_local_axis_y() -> void:
	assert_vector(GoBuildTransformHelpers.get_local_axis(1)).is_equal(Vector3.UP)


func test_get_local_axis_z() -> void:
	assert_vector(GoBuildTransformHelpers.get_local_axis(2)).is_equal(Vector3.BACK)


func test_get_local_axis_invalid_returns_zero() -> void:
	assert_vector(GoBuildTransformHelpers.get_local_axis(-1)).is_equal(Vector3.ZERO)
	assert_vector(GoBuildTransformHelpers.get_local_axis(3)).is_equal(Vector3.ZERO)


# ---------------------------------------------------------------------------
# ray_plane_intersect — basic cases
# ---------------------------------------------------------------------------

func test_ray_plane_intersect_perpendicular_hit() -> void:
	var hit := GoBuildTransformHelpers.ray_plane_intersect(
			Vector3(0.0, 5.0, 0.0), Vector3(0.0, -1.0, 0.0),
			Vector3.ZERO, Vector3.UP)
	assert_vector(hit).is_equal(Vector3.ZERO)


func test_ray_plane_intersect_offset_hit() -> void:
	var hit := GoBuildTransformHelpers.ray_plane_intersect(
			Vector3(0.0, 10.0, 0.0), Vector3(0.0, -1.0, 0.0),
			Vector3(0.0, 3.0, 0.0), Vector3.UP)
	assert_vector(hit).is_equal(Vector3(0.0, 3.0, 0.0))


func test_ray_plane_intersect_diagonal() -> void:
	var dir := Vector3(1.0, 1.0, 0.0).normalized()
	var normal := Vector3(1.0, 1.0, 0.0).normalized()
	var hit := GoBuildTransformHelpers.ray_plane_intersect(
			Vector3.ZERO, dir,
			Vector3(2.0, 2.0, 0.0), normal)
	assert_vector(hit).is_equal_approx(Vector3(2.0, 2.0, 0.0), 0.001)


func test_ray_plane_intersect_behind_camera_returns_inf() -> void:
	var hit := GoBuildTransformHelpers.ray_plane_intersect(
			Vector3(0.0, 5.0, 0.0), Vector3(0.0, 1.0, 0.0),
			Vector3.ZERO, Vector3.UP)
	assert_bool(hit == Vector3.INF).is_true()


func test_ray_plane_intersect_parallel_returns_inf() -> void:
	var hit := GoBuildTransformHelpers.ray_plane_intersect(
			Vector3(0.0, 5.0, 0.0), Vector3(1.0, 0.0, 0.0),
			Vector3.ZERO, Vector3.UP)
	assert_bool(hit == Vector3.INF).is_true()


func test_ray_plane_intersect_z_plane() -> void:
	var hit := GoBuildTransformHelpers.ray_plane_intersect(
			Vector3(0.0, 0.0, -5.0), Vector3(0.0, 0.0, 1.0),
			Vector3.ZERO, Vector3.BACK)
	assert_vector(hit).is_equal(Vector3.ZERO)


func test_ray_plane_intersect_negative_z_plane() -> void:
	var hit := GoBuildTransformHelpers.ray_plane_intersect(
			Vector3(0.0, 0.0, 5.0), Vector3(0.0, 0.0, -1.0),
			Vector3.ZERO, Vector3.FORWARD)
	assert_vector(hit).is_equal(Vector3.ZERO)


func test_ray_plane_intersect_x_plane_from_side() -> void:
	var hit := GoBuildTransformHelpers.ray_plane_intersect(
			Vector3(-5.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0),
			Vector3.ZERO, Vector3.RIGHT)
	assert_vector(hit).is_equal(Vector3.ZERO)


# ---------------------------------------------------------------------------
# Rotated node — world_axis correctness
#
# These tests verify that a local axis transformed through a Basis produces
# a valid world-space direction, and that double-transforming produces a
# DIFFERENT (incorrect) result — the exact bug that was fixed.
# ---------------------------------------------------------------------------

func test_basis_transform_preserves_orthogonality() -> void:
	var basis := Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK).rotated(Vector3.UP, PI / 3.0)
	var world_x := (basis * Vector3.RIGHT).normalized()
	var world_y := (basis * Vector3.UP).normalized()
	var world_z := (basis * Vector3.BACK).normalized()
	assert_float(world_x.dot(world_y)).is_equal_approx(0.0, 0.001)
	assert_float(world_y.dot(world_z)).is_equal_approx(0.0, 0.001)
	assert_float(world_z.dot(world_x)).is_equal_approx(0.0, 0.001)


func test_basis_transform_produces_unit_vectors() -> void:
	var basis := Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK).rotated(
			Vector3(1.0, 0.5, 0.3).normalized(), 1.2)
	assert_float((basis * Vector3.RIGHT).length()).is_equal_approx(1.0, 0.001)
	assert_float((basis * Vector3.UP).length()).is_equal_approx(1.0, 0.001)
	assert_float((basis * Vector3.BACK).length()).is_equal_approx(1.0, 0.001)


func test_double_basis_transform_differs_from_single() -> void:
	var basis := Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK).rotated(Vector3.UP, PI / 4.0)
	var world_x := (basis * Vector3.RIGHT).normalized()
	var double_x := (basis * world_x).normalized()
	assert_vector(world_x).is_not_equal(double_x)


func test_double_transform_breaks_orthogonality() -> void:
	var basis := Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK).rotated(Vector3.UP, PI / 4.0)
	var world_x := (basis * Vector3.RIGHT).normalized()
	var world_y := (basis * Vector3.UP).normalized()
	var double_x := (basis * world_x).normalized()
	assert_float(double_x.dot(world_y)).is_not_equal_approx(0.0, 0.05)


func test_identity_basis_single_and_double_transform_match() -> void:
	var basis := Basis()
	var single := (basis * Vector3.RIGHT).normalized()
	var double_t := (basis * single).normalized()
	assert_vector(single).is_equal(double_t)


func test_rotated_basis_world_axis_correct_ray_intersect() -> void:
	var basis := Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK).rotated(Vector3.UP, PI / 4.0)
	var world_x := (basis * Vector3.RIGHT).normalized()
	var origin := Vector3.ZERO
	var plane_origin := Vector3(1.0, 0.0, 0.0)
	var ray_origin := plane_origin + world_x * 10.0
	var hit := GoBuildTransformHelpers.ray_plane_intersect(
			ray_origin, -world_x, plane_origin, world_x)
	assert_vector(hit).is_equal_approx(plane_origin, 0.001)


func test_rotated_basis_double_transform_wrong_ray_intersect() -> void:
	var basis := Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK).rotated(Vector3.UP, PI / 4.0)
	var world_x := (basis * Vector3.RIGHT).normalized()
	var double_x := (basis * world_x).normalized()
	var plane_origin := Vector3(1.0, 0.0, 0.0)
	var ray_origin := plane_origin + world_x * 10.0
	var hit := GoBuildTransformHelpers.ray_plane_intersect(
			ray_origin, -world_x, plane_origin, double_x)
	assert_vector(hit).is_not_equal_approx(plane_origin, 0.01)


# ---------------------------------------------------------------------------
# get_snap_step
# ---------------------------------------------------------------------------

func test_get_snap_step_override() -> void:
	assert_float(GoBuildTransformHelpers.get_snap_step(0.5)).is_equal_approx(0.5, 0.001)


func test_get_snap_step_positive_override() -> void:
	assert_float(GoBuildTransformHelpers.get_snap_step(2.0)).is_equal_approx(2.0, 0.001)


func test_get_snap_step_negative_override_falls_back() -> void:
	var step := GoBuildTransformHelpers.get_snap_step(-1.0)
	assert_float(step).is_greater(0.0)