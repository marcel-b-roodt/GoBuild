## Flip Normals operation tests — GdUnit4
##
## Tests for [FlipNormalsOperation.apply] covering normal direction, UV-to-vertex
## mapping preservation, unchanged geometry counts, double-flip round-trip, and
## edge cases (null mesh, empty selection, invalid indices, partial flip).
##
## Test mesh convention:
##   _make_plus_y_quad() builds a single CCW-from-above quad in the XZ plane
##   with outward normal +Y.  After a single flip the outward normal is −Y.
extends GdUnitTestSuite

# Self-preloads — needed because test/ scripts are compiled before the
# mesh/ and mesh/operations/ scripts in Godot's alphabetical scan order.
const _FACE_SCRIPT         := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT         := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT         := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _FLIP_NORMALS_SCRIPT := preload(
		"res://addons/go_build/mesh/operations/flip_normals_operation.gd")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Single CCW-from-above quad in the XZ plane; outward normal = +Y.
## Vertices: v0=(0,0,0)  v1=(0,0,1)  v2=(1,0,1)  v3=(1,0,0)
## UVs:      (0,0)       (0,1)       (1,1)        (1,0)
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
# Helper sanity-check — verifies the quad has the expected +Y normal
# ---------------------------------------------------------------------------

func test_helper_quad_normal_is_plus_y() -> void:
	var mesh := _make_plus_y_quad()
	var n: Vector3 = mesh.compute_face_normal(mesh.faces[0])
	assert_float(n.dot(Vector3.UP)).is_greater_equal(0.999)


# ---------------------------------------------------------------------------
# Normal direction after flip
# ---------------------------------------------------------------------------

func test_flip_reverses_normal_to_minus_y() -> void:
	var mesh := _make_plus_y_quad()
	var indices: Array[int] = [0]
	FlipNormalsOperation.apply(mesh, indices)
	var n: Vector3 = mesh.compute_face_normal(mesh.faces[0])
	# After flip the outward normal should point −Y.
	assert_float(n.dot(Vector3.DOWN)).is_greater_equal(0.999)


func test_double_flip_restores_plus_y_normal() -> void:
	var mesh := _make_plus_y_quad()
	var indices: Array[int] = [0]
	FlipNormalsOperation.apply(mesh, indices)
	FlipNormalsOperation.apply(mesh, indices)
	var n: Vector3 = mesh.compute_face_normal(mesh.faces[0])
	assert_float(n.dot(Vector3.UP)).is_greater_equal(0.999)


# ---------------------------------------------------------------------------
# Geometry counts unchanged
# ---------------------------------------------------------------------------

func test_vertex_count_unchanged_after_flip() -> void:
	var mesh := _make_plus_y_quad()
	var indices: Array[int] = [0]
	FlipNormalsOperation.apply(mesh, indices)
	assert_int(mesh.vertices.size()).is_equal(4)


func test_face_count_unchanged_after_flip() -> void:
	var mesh := _make_plus_y_quad()
	var indices: Array[int] = [0]
	FlipNormalsOperation.apply(mesh, indices)
	assert_int(mesh.faces.size()).is_equal(1)


# ---------------------------------------------------------------------------
# UV-to-vertex mapping preserved
# ---------------------------------------------------------------------------

func test_uv_mapping_preserved_after_flip() -> void:
	# Original: vertex_indices=[0,1,2,3], uvs=[(0,0),(0,1),(1,1),(1,0)]
	# After flip: vertex_indices=[3,2,1,0], uvs=[(1,0),(1,1),(0,1),(0,0)]
	# Slot 0 now holds vertex index 3, which must keep its original uv (1, 0).
	# Slot 3 now holds vertex index 0, which must keep its original uv (0, 0).
	var mesh := _make_plus_y_quad()
	var indices: Array[int] = [0]
	FlipNormalsOperation.apply(mesh, indices)
	var face: GoBuildFace = mesh.faces[0]
	# Slot 0: vertex 3, original uv (1, 0)
	assert_float(face.uvs[0].x).is_equal_approx(1.0, 0.001)
	assert_float(face.uvs[0].y).is_equal_approx(0.0, 0.001)
	# Slot 3: vertex 0, original uv (0, 0)
	assert_float(face.uvs[3].x).is_equal_approx(0.0, 0.001)
	assert_float(face.uvs[3].y).is_equal_approx(0.0, 0.001)


func test_uv_count_matches_vertex_count_after_flip() -> void:
	var mesh := _make_plus_y_quad()
	var indices: Array[int] = [0]
	FlipNormalsOperation.apply(mesh, indices)
	var face: GoBuildFace = mesh.faces[0]
	assert_int(face.uvs.size()).is_equal(face.vertex_indices.size())


# ---------------------------------------------------------------------------
# UV2 preserved (when populated)
# ---------------------------------------------------------------------------

func test_uv2_reversed_when_fully_populated() -> void:
	var mesh := _make_plus_y_quad()
	var face: GoBuildFace = mesh.faces[0]
	face.uv2s = [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)]
	var indices: Array[int] = [0]
	FlipNormalsOperation.apply(mesh, indices)
	# uv2s[0] should now be the original uv2s[3] = (1, 0).
	assert_float(face.uv2s[0].x).is_equal_approx(1.0, 0.001)
	assert_float(face.uv2s[0].y).is_equal_approx(0.0, 0.001)


func test_uv2_not_reversed_when_empty() -> void:
	# Empty uv2s should stay empty after flip; no crash.
	var mesh := _make_plus_y_quad()
	var indices: Array[int] = [0]
	FlipNormalsOperation.apply(mesh, indices)
	assert_int(mesh.faces[0].uv2s.size()).is_equal(0)


# ---------------------------------------------------------------------------
# Edge list rebuilt
# ---------------------------------------------------------------------------

func test_flip_rebuilds_edges() -> void:
	var mesh := _make_plus_y_quad()
	var indices: Array[int] = [0]
	FlipNormalsOperation.apply(mesh, indices)
	# rebuild_edges is called inside apply — edge list must be non-empty.
	assert_int(mesh.edges.size()).is_greater(0)


# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

func test_empty_selection_does_nothing() -> void:
	var mesh := _make_plus_y_quad()
	var indices: Array[int] = []
	FlipNormalsOperation.apply(mesh, indices)
	var n: Vector3 = mesh.compute_face_normal(mesh.faces[0])
	assert_float(n.dot(Vector3.UP)).is_greater_equal(0.999)


func test_null_mesh_does_not_crash() -> void:
	# Must not throw — null guard in apply().
	var indices: Array[int] = [0]
	FlipNormalsOperation.apply(null, indices)
	assert_bool(true).is_true()


func test_invalid_index_skipped() -> void:
	var mesh := _make_plus_y_quad()
	var indices: Array[int] = [99]
	FlipNormalsOperation.apply(mesh, indices)
	var n: Vector3 = mesh.compute_face_normal(mesh.faces[0])
	assert_float(n.dot(Vector3.UP)).is_greater_equal(0.999)


func test_negative_index_skipped() -> void:
	var mesh := _make_plus_y_quad()
	var indices: Array[int] = [-1]
	FlipNormalsOperation.apply(mesh, indices)
	var n: Vector3 = mesh.compute_face_normal(mesh.faces[0])
	assert_float(n.dot(Vector3.UP)).is_greater_equal(0.999)


func test_mixed_valid_and_invalid_indices() -> void:
	# Index 0 is valid; 99 and -1 should be silently skipped.
	var mesh := _make_plus_y_quad()
	var indices: Array[int] = [0, 99, -1]
	FlipNormalsOperation.apply(mesh, indices)
	var n: Vector3 = mesh.compute_face_normal(mesh.faces[0])
	# Face 0 should be flipped (index 0 is valid).
	assert_float(n.dot(Vector3.DOWN)).is_greater_equal(0.999)


# ---------------------------------------------------------------------------
# Partial flip — only selected faces are affected
# ---------------------------------------------------------------------------

func test_partial_flip_leaves_unselected_face_unchanged() -> void:
	# Two-face mesh in the XZ plane sharing an edge.
	# Flip only face 1; face 0 must be unaffected.
	var mesh := GoBuildMesh.new()
	mesh.vertices = [
		Vector3(0.0, 0.0, 0.0),  # 0
		Vector3(0.0, 0.0, 1.0),  # 1
		Vector3(1.0, 0.0, 1.0),  # 2
		Vector3(1.0, 0.0, 0.0),  # 3
		Vector3(2.0, 0.0, 0.0),  # 4
		Vector3(2.0, 0.0, 1.0),  # 5
	]
	var face0 := GoBuildFace.new()
	face0.vertex_indices = [0, 1, 2, 3]
	face0.uvs = [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)]
	var face1 := GoBuildFace.new()
	face1.vertex_indices = [3, 2, 5, 4]
	face1.uvs = [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)]
	mesh.faces.append(face0)
	mesh.faces.append(face1)

	var indices: Array[int] = [1]
	FlipNormalsOperation.apply(mesh, indices)

	# Face 0: unselected — normal remains +Y.
	var n0: Vector3 = mesh.compute_face_normal(mesh.faces[0])
	assert_float(n0.dot(Vector3.UP)).is_greater_equal(0.999)

	# Face 1: selected — normal flipped to −Y.
	var n1: Vector3 = mesh.compute_face_normal(mesh.faces[1])
	assert_float(n1.dot(Vector3.DOWN)).is_greater_equal(0.999)

