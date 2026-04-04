## Extrude operation tests — GdUnit4
##
## Tests for [ExtrudeOperation.apply] covering vertex/face counts, winding order,
## and edge cases (zero distance, empty/invalid selection).
##
## Test mesh convention:
##   _make_plus_y_quad() builds a single CCW-from-above quad in the XZ plane
##   with outward normal +Y.  After extruding by [param distance] all top-ring
##   vertices should sit at y = distance and all side-face normals should be
##   horizontal (n.y ≈ 0).
extends GdUnitTestSuite

# Self-preloads — needed because the test suite is compiled before the
# mesh/ scripts in Godot's alphabetical scan order.
const _FACE_SCRIPT    := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT    := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT    := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _EXTRUDE_SCRIPT := preload("res://addons/go_build/mesh/operations/extrude_operation.gd")


# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------

## Create a single quad face in the XZ plane with outward normal +Y.
##
## Vertex winding [v0, v1, v2, v3] is CCW when viewed from above (+Y), so
## [method GoBuildMesh.compute_face_normal] returns (0, 1, 0).
## Coordinates: v0=(0,0,0)  v1=(0,0,1)  v2=(1,0,1)  v3=(1,0,0)
func _make_plus_y_quad() -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [
		Vector3(0.0, 0.0, 0.0),
		Vector3(0.0, 0.0, 1.0),
		Vector3(1.0, 0.0, 1.0),
		Vector3(1.0, 0.0, 0.0),
	]
	var face := GoBuildFace.new()
	face.vertex_indices = [0, 1, 2, 3]
	face.uvs = [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)]
	mesh.faces.append(face)
	return mesh


# ---------------------------------------------------------------------------
# Normal sanity-check — verifies the helper itself is correct
# ---------------------------------------------------------------------------

func test_helper_quad_normal_is_plus_y() -> void:
	var mesh := _make_plus_y_quad()
	var n: Vector3 = mesh.compute_face_normal(mesh.faces[0])
	assert_float(n.dot(Vector3.UP)).is_greater_equal(0.999)


# ---------------------------------------------------------------------------
# Vertex and face counts
# ---------------------------------------------------------------------------

func test_extrude_single_quad_vertex_count() -> void:
	var mesh := _make_plus_y_quad()
	var indices: Array[int] = [0]
	ExtrudeOperation.apply(mesh, indices, 1.0)
	# 4 original + 4 new top-ring vertices = 8.
	assert_int(mesh.vertices.size()).is_equal(8)


func test_extrude_single_quad_face_count() -> void:
	var mesh := _make_plus_y_quad()
	var indices: Array[int] = [0]
	ExtrudeOperation.apply(mesh, indices, 1.0)
	# 1 updated top face + 4 side faces = 5.
	assert_int(mesh.faces.size()).is_equal(5)


# ---------------------------------------------------------------------------
# Extruded top-face position
# ---------------------------------------------------------------------------

func test_extrude_top_face_vertices_at_correct_height() -> void:
	var mesh := _make_plus_y_quad()
	var indices: Array[int] = [0]
	ExtrudeOperation.apply(mesh, indices, 2.0)
	# Face 0 (the original, now the top) should reference vertices at y ≈ 2.0.
	var top: GoBuildFace = mesh.faces[0]
	for vi: int in top.vertex_indices:
		assert_float(mesh.vertices[vi].y).is_equal_approx(2.0, 0.001)


func test_extrude_top_face_normal_is_still_plus_y() -> void:
	var mesh := _make_plus_y_quad()
	var indices: Array[int] = [0]
	ExtrudeOperation.apply(mesh, indices, 1.0)
	var n: Vector3 = mesh.compute_face_normal(mesh.faces[0])
	assert_float(n.dot(Vector3.UP)).is_greater_equal(0.999)


# ---------------------------------------------------------------------------
# Side-face winding and normals
# ---------------------------------------------------------------------------

func test_extrude_side_face_count_is_four() -> void:
	var mesh := _make_plus_y_quad()
	var indices: Array[int] = [0]
	ExtrudeOperation.apply(mesh, indices, 1.0)
	# Faces 1-4 are the side faces; face 0 is the extruded top.
	assert_int(mesh.faces.size() - 1).is_equal(4)


func test_extrude_side_face_normals_are_horizontal() -> void:
	# All side faces of an extruded +Y quad should have horizontal normals (n.y ≈ 0).
	var mesh := _make_plus_y_quad()
	var indices: Array[int] = [0]
	ExtrudeOperation.apply(mesh, indices, 1.0)
	for fi: int in range(1, mesh.faces.size()):
		var n: Vector3 = mesh.compute_face_normal(mesh.faces[fi])
		assert_float(absf(n.y)).is_less(0.01)


func test_extrude_side_face_normals_are_unit_length() -> void:
	var mesh := _make_plus_y_quad()
	var indices: Array[int] = [0]
	ExtrudeOperation.apply(mesh, indices, 1.0)
	for fi: int in range(1, mesh.faces.size()):
		var n: Vector3 = mesh.compute_face_normal(mesh.faces[fi])
		assert_float(n.length()).is_equal_approx(1.0, 0.001)


func test_extrude_side_face_normals_point_outward() -> void:
	# The base centroid of the quad is at (0.5, 0, 0.5) in XZ.
	# Each side-face outward normal projected onto XZ should point away from that centroid.
	var mesh := _make_plus_y_quad()
	var indices: Array[int] = [0]
	ExtrudeOperation.apply(mesh, indices, 1.0)
	var base_centroid := Vector3(0.5, 0.0, 0.5)
	for fi: int in range(1, mesh.faces.size()):
		var face: GoBuildFace = mesh.faces[fi]
		var face_centroid := Vector3.ZERO
		for vi: int in face.vertex_indices:
			face_centroid += mesh.vertices[vi]
		face_centroid /= float(face.vertex_indices.size())
		var outward_dir := Vector3(
			face_centroid.x - base_centroid.x,
			0.0,
			face_centroid.z - base_centroid.z,
		).normalized()
		var n: Vector3 = mesh.compute_face_normal(face)
		var n_xz := Vector3(n.x, 0.0, n.z).normalized()
		assert_float(n_xz.dot(outward_dir)).is_greater_equal(0.99)


# ---------------------------------------------------------------------------
# Side-face UV validity
# ---------------------------------------------------------------------------

func test_extrude_side_face_uvs_are_valid() -> void:
	var mesh := _make_plus_y_quad()
	var indices: Array[int] = [0]
	ExtrudeOperation.apply(mesh, indices, 1.0)
	for fi: int in range(1, mesh.faces.size()):
		var face: GoBuildFace = mesh.faces[fi]
		assert_int(face.uvs.size()).is_equal(face.vertex_indices.size())


# ---------------------------------------------------------------------------
# Original face UV preservation
# ---------------------------------------------------------------------------

func test_extrude_top_face_uvs_are_preserved() -> void:
	var mesh := _make_plus_y_quad()
	var original_uvs: Array = [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)]
	var indices: Array[int] = [0]
	ExtrudeOperation.apply(mesh, indices, 1.0)
	var top: GoBuildFace = mesh.faces[0]
	assert_int(top.uvs.size()).is_equal(original_uvs.size())
	for i: int in original_uvs.size():
		assert_float(top.uvs[i].x).is_equal_approx(original_uvs[i].x, 0.001)
		assert_float(top.uvs[i].y).is_equal_approx(original_uvs[i].y, 0.001)


# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

func test_extrude_zero_distance_still_creates_geometry() -> void:
	# A zero-distance extrude produces geometry at the same positions.
	var mesh := _make_plus_y_quad()
	var indices: Array[int] = [0]
	ExtrudeOperation.apply(mesh, indices, 0.0)
	assert_int(mesh.vertices.size()).is_equal(8)
	assert_int(mesh.faces.size()).is_equal(5)


func test_extrude_empty_selection_is_noop() -> void:
	var mesh := _make_plus_y_quad()
	var indices: Array[int] = []
	ExtrudeOperation.apply(mesh, indices, 1.0)
	assert_int(mesh.vertices.size()).is_equal(4)
	assert_int(mesh.faces.size()).is_equal(1)


func test_extrude_invalid_index_is_skipped() -> void:
	var mesh := _make_plus_y_quad()
	var indices: Array[int] = [99]
	ExtrudeOperation.apply(mesh, indices, 1.0)
	assert_int(mesh.vertices.size()).is_equal(4)
	assert_int(mesh.faces.size()).is_equal(1)


func test_extrude_mixed_valid_and_invalid_indices() -> void:
	# Only face 0 is valid; 99 and -1 should be silently skipped.
	var mesh := _make_plus_y_quad()
	var indices: Array[int] = [0, 99, -1]
	ExtrudeOperation.apply(mesh, indices, 1.0)
	assert_int(mesh.vertices.size()).is_equal(8)
	assert_int(mesh.faces.size()).is_equal(5)


func test_extrude_rebuilds_edges() -> void:
	var mesh := _make_plus_y_quad()
	var indices: Array[int] = [0]
	ExtrudeOperation.apply(mesh, indices, 1.0)
	# rebuild_edges is called inside apply — edge list must be non-empty.
	assert_int(mesh.edges.size()).is_greater(0)
