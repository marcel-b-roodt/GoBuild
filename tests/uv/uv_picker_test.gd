## UvPicker unit tests — GdUnit4
##
## Tests all pure static hit-testing and geometry functions.
extends GdUnitTestSuite

const _FACE_SCRIPT  := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MESH_SCRIPT  := preload("res://addons/go_build/mesh/go_build_mesh.gd")


# ---------------------------------------------------------------------------
# point_in_polygon
# ---------------------------------------------------------------------------

func test_point_in_polygon_triangle_inside() -> void:
	var poly: Array[Vector2] = [
		Vector2(0.0, 0.0),
		Vector2(1.0, 0.0),
		Vector2(0.5, 1.0),
	]
	assert_bool(UvPicker.point_in_polygon(Vector2(0.5, 0.4), poly)).is_true()


func test_point_in_polygon_triangle_outside() -> void:
	var poly: Array[Vector2] = [
		Vector2(0.0, 0.0),
		Vector2(1.0, 0.0),
		Vector2(0.5, 1.0),
	]
	assert_bool(not UvPicker.point_in_polygon(Vector2(2.0, 2.0), poly)).is_true()


func test_point_in_polygon_square_inside() -> void:
	var poly: Array[Vector2] = [
		Vector2(0.0, 0.0),
		Vector2(1.0, 0.0),
		Vector2(1.0, 1.0),
		Vector2(0.0, 1.0),
	]
	assert_bool(UvPicker.point_in_polygon(Vector2(0.5, 0.5), poly)).is_true()


func test_point_in_polygon_square_on_edge() -> void:
	var poly: Array[Vector2] = [
		Vector2(0.0, 0.0),
		Vector2(1.0, 0.0),
		Vector2(1.0, 1.0),
		Vector2(0.0, 1.0),
	]
	UvPicker.point_in_polygon(Vector2(0.5, 0.0), poly)


func test_point_in_polygon_concave() -> void:
	var poly: Array[Vector2] = [
		Vector2(0.0, 0.0),
		Vector2(2.0, 0.0),
		Vector2(2.0, 1.0),
		Vector2(1.0, 1.0),
		Vector2(1.0, 2.0),
		Vector2(0.0, 2.0),
	]
	assert_bool(UvPicker.point_in_polygon(Vector2(0.5, 0.5), poly)).is_true()
	assert_bool(UvPicker.point_in_polygon(Vector2(0.5, 1.5), poly)).is_true()
	assert_bool(not UvPicker.point_in_polygon(Vector2(1.5, 1.5), poly)).is_true()


# ---------------------------------------------------------------------------
# min_edge_dist_sq
# ---------------------------------------------------------------------------

func test_min_edge_dist_sq_on_edge() -> void:
	var poly: Array[Vector2] = [
		Vector2(0.0, 0.0),
		Vector2(1.0, 0.0),
		Vector2(1.0, 1.0),
	]
	assert_float(UvPicker.min_edge_dist_sq(Vector2(0.5, 0.0), poly)).is_equal(0.0)


func test_min_edge_dist_sq_near_edge() -> void:
	var poly: Array[Vector2] = [
		Vector2(0.0, 0.0),
		Vector2(1.0, 0.0),
		Vector2(1.0, 1.0),
	]
	var dsq := UvPicker.min_edge_dist_sq(Vector2(0.5, 0.01), poly)
	assert_float(dsq).is_less(0.001)


# ---------------------------------------------------------------------------
# pick_face
# ---------------------------------------------------------------------------

func _make_single_triangle_mesh() -> GoBuildMesh:
	var gbm := GoBuildMesh.new()
	gbm.vertices = [
		Vector3(0.0, 0.0, 0.0),
		Vector3(1.0, 0.0, 0.0),
		Vector3(0.0, 1.0, 0.0),
	]
	var face := GoBuildFace.new()
	face.vertex_indices = [0, 1, 2]
	face.uvs = [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.0, 1.0)]
	gbm.faces = [face]
	return gbm


func test_pick_face_hit() -> void:
	var gbm := _make_single_triangle_mesh()
	var hit := UvPicker.pick_face(gbm, Vector2(0.3, 0.3))
	assert_int(hit).is_equal(0)


func test_pick_face_miss() -> void:
	var gbm := _make_single_triangle_mesh()
	var hit := UvPicker.pick_face(gbm, Vector2(2.0, 2.0))
	assert_int(hit).is_equal(-1)


func test_pick_face_near_edge() -> void:
	var gbm := _make_single_triangle_mesh()
	var hit := UvPicker.pick_face(gbm, Vector2(0.5, -0.002))
	assert_int(hit).is_equal(0)


func test_pick_face_null_mesh() -> void:
	var hit := UvPicker.pick_face(null, Vector2(0.5, 0.5))
	assert_int(hit).is_equal(-1)


# ---------------------------------------------------------------------------
# pick_face_all
# ---------------------------------------------------------------------------

func test_pick_face_all_single() -> void:
	var gbm := _make_single_triangle_mesh()
	var hits := UvPicker.pick_face_all(gbm, Vector2(0.3, 0.3))
	assert_array(hits).contains(0)


func test_pick_face_all_overlapping() -> void:
	var gbm := GoBuildMesh.new()
	gbm.vertices = [
		Vector3(0.0, 0.0, 0.0),
		Vector3(1.0, 0.0, 0.0),
		Vector3(0.0, 1.0, 0.0),
	]
	var f1 := GoBuildFace.new()
	f1.vertex_indices = [0, 1, 2]
	f1.uvs = [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.0, 1.0)]
	var f2 := GoBuildFace.new()
	f2.vertex_indices = [0, 1, 2]
	f2.uvs = [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.0, 1.0)]
	gbm.faces = [f1, f2]
	var hits := UvPicker.pick_face_all(gbm, Vector2(0.3, 0.3))
	assert_int(hits.size()).is_equal(2)


# ---------------------------------------------------------------------------
# pick_faces_in_rect
# ---------------------------------------------------------------------------

func test_pick_faces_in_rect_hit() -> void:
	var gbm := _make_single_triangle_mesh()
	var rect := Rect2(Vector2(-0.5, -0.5), Vector2(2.0, 2.0))
	var hits := UvPicker.pick_faces_in_rect(gbm, rect)
	assert_array(hits).contains(0)


func test_pick_faces_in_rect_miss() -> void:
	var gbm := _make_single_triangle_mesh()
	var rect := Rect2(Vector2(2.0, 2.0), Vector2(1.0, 1.0))
	var hits := UvPicker.pick_faces_in_rect(gbm, rect)
	assert_array(hits).is_empty()


# ---------------------------------------------------------------------------
# pick_vert
# ---------------------------------------------------------------------------

func test_pick_vert_hit() -> void:
	var gbm := _make_single_triangle_mesh()
	var hit := UvPicker.pick_vert(gbm, Vector2(0.0, 0.0), 180.0, 12.0)
	assert_int(hit.x).is_equal(0)
	assert_int(hit.y).is_equal(0)


func test_pick_vert_miss() -> void:
	var gbm := _make_single_triangle_mesh()
	var hit := UvPicker.pick_vert(gbm, Vector2(5.0, 5.0), 180.0, 12.0)
	assert_int(hit.x).is_equal(-1)


# ---------------------------------------------------------------------------
# compute_pivot
# ---------------------------------------------------------------------------

func test_compute_pivot_single_face() -> void:
	var gbm := _make_single_triangle_mesh()
	var pivot := UvPicker.compute_pivot(gbm, [0])
	assert_vector(pivot).is_equal(Vector2(1.0 / 3.0, 1.0 / 3.0))


func test_compute_pivot_empty() -> void:
	var gbm := _make_single_triangle_mesh()
	var pivot := UvPicker.compute_pivot(gbm, [])
	assert_vector(pivot).is_equal(Vector2.ZERO)


func test_compute_pivot_null_mesh() -> void:
	var pivot := UvPicker.compute_pivot(null, [0])
	assert_vector(pivot).is_equal(Vector2.ZERO)