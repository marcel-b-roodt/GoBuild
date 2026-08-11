## Triangulate utility tests — GdUnit4
##
## Tests for [Triangulate] fan() and ear_clip():
##   fan: triangle, quad, pentagon return correct CW-from-outside indices.
##   ear_clip: convex quad, convex pentagon, concave polygon.
##   ear_clip: CW winding in 2D projection (signed area fix).
extends GdUnitTestSuite

const _TRI_SCRIPT := preload("res://addons/go_build/mesh/triangulate.gd")


# ---------------------------------------------------------------------------
# fan() tests
# ---------------------------------------------------------------------------

func test_fan_triangle() -> void:
	var tris: Array = Triangulate.fan(3)
	assert_int(tris.size()).is_equal(1)
	var tri: Array = tris[0]
	assert_int(tri.size()).is_equal(3)
	# Fan returns [0, 2, 1] for a triangle — CW from outside.
	assert_int(tri[0]).is_equal(0)
	assert_int(tri[1]).is_equal(2)
	assert_int(tri[2]).is_equal(1)


func test_fan_quad() -> void:
	var tris: Array = Triangulate.fan(4)
	assert_int(tris.size()).is_equal(2)
	# First triangle: [0, 2, 1], second: [0, 3, 2]
	assert_int(tris[0][0]).is_equal(0)
	assert_int(tris[0][1]).is_equal(2)
	assert_int(tris[0][2]).is_equal(1)
	assert_int(tris[1][0]).is_equal(0)
	assert_int(tris[1][1]).is_equal(3)
	assert_int(tris[1][2]).is_equal(2)


func test_fan_pentagon() -> void:
	var tris: Array = Triangulate.fan(5)
	assert_int(tris.size()).is_equal(3)
	# Each triangle fans from vertex 0.
	for tri: Array in tris:
		assert_int(tri[0]).is_equal(0)


# ---------------------------------------------------------------------------
# ear_clip() tests
# ---------------------------------------------------------------------------

func test_ear_clip_triangle() -> void:
	var points: Array[Vector3] = [
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1),
	]
	var normal := Vector3.UP
	var tris: Array = Triangulate.ear_clip(points, normal)
	assert_int(tris.size()).is_equal(1)
	assert_int(tris[0].size()).is_equal(3)
	# Should return indices [0, 1, 2] for a simple triangle.
	assert_int(tris[0][0]).is_equal(0)
	assert_int(tris[0][1]).is_equal(1)
	assert_int(tris[0][2]).is_equal(2)


func test_ear_clip_convex_quad() -> void:
	# Quad on XZ plane, Y-up normal.
	var points: Array[Vector3] = [
		Vector3(0, 0, 0), Vector3(1, 0, 0),
		Vector3(1, 0, 1), Vector3(0, 0, 1),
	]
	var normal := Vector3.UP
	var tris: Array = Triangulate.ear_clip(points, normal)
	assert_int(tris.size()).is_equal(2)
	# All triangle indices should be valid (0-3).
	for tri: Array in tris:
		assert_int(tri.size()).is_equal(3)
		for idx: int in tri:
			assert_bool(idx >= 0 and idx < 4, "Index %d out of range" % idx)


func test_ear_clip_concave_polygon() -> void:
	# Arrow/chevron shape: concave at vertex 3.
	#   1
	#  / \
	# 0   2
	#  \ /
	#   3---4
	var points: Array[Vector3] = [
		Vector3(0, 0, 1),   # 0 - top-left
		Vector3(2, 0, 2),   # 1 - top
		Vector3(4, 0, 1),   # 2 - top-right
		Vector3(2, 0, 0),   # 3 - concave point (indent)
		Vector3(4, 0, -1),  # 4 - bottom-right
	]
	var normal := Vector3.UP
	var tris: Array = Triangulate.ear_clip(points, normal)
	# Should produce 3 triangles for a 5-vertex polygon.
	assert_int(tris.size()).is_equal(3)


func test_ear_clip_cw_winding_fix() -> void:
	# Pass a quad with CW winding (when viewed from +Y).
	# The signed-area check should reverse the projection and still produce triangles.
	var points: Array[Vector3] = [
		Vector3(0, 0, 0), Vector3(0, 0, 1),
		Vector3(1, 0, 1), Vector3(1, 0, 0),
	]
	# Normal pointing UP (the quad is on the XZ plane, CCW from above).
	var normal := Vector3.UP
	var tris: Array = Triangulate.ear_clip(points, normal)
	# Even though this is CW when projected to XZ, the signed-area fix
	# should reverse the projection and find ears.
	assert_bool(tris.size() >= 2, "Should produce at least 2 triangles for CW quad")


func test_ear_clip_line_degenerate() -> void:
	# Collinear points — ear_clip should return minimal triangles (may be empty).
	var points: Array[Vector3] = [
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0),
	]
	var normal := Vector3.UP
	var tris: Array = Triangulate.ear_clip(points, normal)
	# Degenerate: all cross products are zero, no ears found.
	# Should return either empty or the final 3 remaining points.
	# We just verify it doesn't crash.
	assert_bool(tris.size() <= 1, "Degenerate input should produce 0 or 1 triangles")