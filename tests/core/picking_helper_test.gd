## Unit tests for [PickingHelper] pure-math helpers.
##
## Only [method PickingHelper.point_to_segment_dist] and
## [method PickingHelper.ray_triangle_intersect] are tested here — both are
## pure functions with no scene-tree dependency.
## Camera-dependent methods (find_nearest_vertex etc.) require a GdUnit4
## scene test and are deferred to a later stage.
@tool
extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# point_to_segment_dist
# ---------------------------------------------------------------------------

func test_p2s_point_on_segment_midpoint() -> void:
	# Midpoint of (0,0)→(10,0) should be distance 0 from (5,0).
	assert_float(PickingHelper.point_to_segment_dist(
		Vector2(5, 0), Vector2(0, 0), Vector2(10, 0)
	)).is_equal_approx(0.0, 0.001)


func test_p2s_point_above_segment() -> void:
	# (5,3) is 3 units above the horizontal segment (0,0)→(10,0).
	assert_float(PickingHelper.point_to_segment_dist(
		Vector2(5, 3), Vector2(0, 0), Vector2(10, 0)
	)).is_equal_approx(3.0, 0.001)


func test_p2s_point_past_end_clamps_to_endpoint() -> void:
	# (12,0) is past end of (0,0)→(10,0) — nearest point is (10,0), dist = 2.
	assert_float(PickingHelper.point_to_segment_dist(
		Vector2(12, 0), Vector2(0, 0), Vector2(10, 0)
	)).is_equal_approx(2.0, 0.001)


func test_p2s_point_before_start_clamps_to_start() -> void:
	assert_float(PickingHelper.point_to_segment_dist(
		Vector2(-3, 0), Vector2(0, 0), Vector2(10, 0)
	)).is_equal_approx(3.0, 0.001)


func test_p2s_degenerate_segment_returns_dist_to_point() -> void:
	# Zero-length segment: distance is just point-to-point.
	assert_float(PickingHelper.point_to_segment_dist(
		Vector2(3, 4), Vector2(0, 0), Vector2(0, 0)
	)).is_equal_approx(5.0, 0.001)


func test_p2s_perpendicular_to_diagonal_segment() -> void:
	# Segment (0,0)→(4,4), query point (4,0) — nearest point (2,2), dist = sqrt(8).
	var expected: float = sqrt(8.0)
	assert_float(PickingHelper.point_to_segment_dist(
		Vector2(4, 0), Vector2(0, 0), Vector2(4, 4)
	)).is_equal_approx(expected, 0.001)


# ---------------------------------------------------------------------------
# ray_triangle_intersect
# ---------------------------------------------------------------------------

## A simple triangle in the XZ plane at Y=1, hit from above (+Y direction).
func _make_xz_triangle() -> Array:
	return [
		Vector3(-1, 1,  0),  # v0
		Vector3( 1, 1,  0),  # v1
		Vector3( 0, 1,  2),  # v2
	]


func test_ray_hits_triangle_centre() -> void:
	var tri := _make_xz_triangle()
	# Centroid is at (0, 1, 2/3). Ray from above along -Y.
	var t: float = PickingHelper.ray_triangle_intersect(
		Vector3(0, 5, 0.667), Vector3(0, -1, 0),
		tri[0], tri[1], tri[2]
	)
	assert_float(t).is_greater(0.0)


func test_ray_misses_triangle_wide() -> void:
	var tri := _make_xz_triangle()
	var t: float = PickingHelper.ray_triangle_intersect(
		Vector3(10, 5, 0), Vector3(0, -1, 0),
		tri[0], tri[1], tri[2]
	)
	assert_float(t).is_equal_approx(-1.0, 0.001)


func test_ray_parallel_returns_minus_one() -> void:
	var tri := _make_xz_triangle()
	# Ray travelling along +X is parallel to the XZ-plane triangle at Y=1.
	var t: float = PickingHelper.ray_triangle_intersect(
		Vector3(-5, 1, 0.667), Vector3(1, 0, 0),
		tri[0], tri[1], tri[2]
	)
	assert_float(t).is_equal_approx(-1.0, 0.001)


func test_ray_behind_triangle_returns_minus_one() -> void:
	# Ray points away from the triangle (+Y instead of -Y).
	var tri := _make_xz_triangle()
	var t: float = PickingHelper.ray_triangle_intersect(
		Vector3(0, 5, 0.667), Vector3(0, 1, 0),
		tri[0], tri[1], tri[2]
	)
	assert_float(t).is_equal_approx(-1.0, 0.001)


func test_ray_hits_back_face_two_sided() -> void:
	# Same as centre hit but ray comes from below (+Y direction pointing up).
	# Two-sided test: ray from (0, -5, 0.667) going +Y should still hit.
	var tri := _make_xz_triangle()
	var t: float = PickingHelper.ray_triangle_intersect(
		Vector3(0, -5, 0.667), Vector3(0, 1, 0),
		tri[0], tri[1], tri[2]
	)
	assert_float(t).is_greater(0.0)


func test_ray_t_is_correct_distance() -> void:
	# Ray from (0, 5, 0.667) downward (-Y). Triangle at Y=1 → t should be ~4.
	var tri := _make_xz_triangle()
	var t: float = PickingHelper.ray_triangle_intersect(
		Vector3(0, 5, 0.667), Vector3(0, -1, 0),
		tri[0], tri[1], tri[2]
	)
	assert_float(t).is_equal_approx(4.0, 0.01)


func test_ray_hits_v0_vertex_exactly() -> void:
	var tri := _make_xz_triangle()
	# Ray straight down onto v0 = (-1, 1, 0).
	var t: float = PickingHelper.ray_triangle_intersect(
		Vector3(-1, 10, 0), Vector3(0, -1, 0),
		tri[0], tri[1], tri[2]
	)
	assert_float(t).is_greater(0.0)


func test_ray_hits_edge_midpoint() -> void:
	# Midpoint of edge v0→v1 is (0, 1, 0). Ray from above.
	var tri := _make_xz_triangle()
	var t: float = PickingHelper.ray_triangle_intersect(
		Vector3(0, 10, 0), Vector3(0, -1, 0),
		tri[0], tri[1], tri[2]
	)
	assert_float(t).is_greater(0.0)

