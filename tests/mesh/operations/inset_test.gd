## Negative inset (depth mode) tests — GdUnit4
##
## Negative [InsetOperation.apply] amount pushes the inner ring along
## -face-normal by units (sunken floor).  Covers inner-ring position, vertical
## side walls, normals map, and the unchanged positive/noop paths.
extends GdUnitTestSuite

# Self-preloads — needed because the test suite is compiled before the
# mesh/ scripts in Godot's alphabetical scan order.
const _FACE_SCRIPT    := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT    := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT    := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _INSET_SCRIPT   := preload("res://addons/go_build/mesh/operations/inset_operation.gd")


# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------

## Create a single quad face in the XZ plane with outward normal +Y.
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
# Positive path (unchanged behaviour)
# ---------------------------------------------------------------------------

func test_positive_amount_blends_toward_centroid() -> void:
	var mesh := _make_plus_y_quad()
	InsetOperation.apply(mesh, [0], 0.5, {}, {})
	var inner: GoBuildFace = mesh.faces[0]
	for vi: int in inner.vertex_indices:
		assert_float(mesh.vertices[vi].y).is_equal_approx(0.0, 0.001)


func test_zero_amount_keeps_outer_positions() -> void:
	var mesh := _make_plus_y_quad()
	InsetOperation.apply(mesh, [0], 0.0, {}, {})
	var inner: GoBuildFace = mesh.faces[0]
	for vi: int in inner.vertex_indices:
		assert_float(mesh.vertices[vi].y).is_equal_approx(0.0, 0.001)


# ---------------------------------------------------------------------------
# Negative amount (depth mode)
# ---------------------------------------------------------------------------

func test_negative_amount_pushes_inner_ring_along_minus_normal() -> void:
	var mesh := _make_plus_y_quad()
	InsetOperation.apply(mesh, [0], -0.25, {}, {})
	var inner: GoBuildFace = mesh.faces[0]
	for vi: int in inner.vertex_indices:
		assert_float(mesh.vertices[vi].y).is_equal_approx(-0.25, 0.001)
	# Inner ring keeps the outer ring's XY footprint.
	assert_float(mesh.vertices[inner.vertex_indices[0]].x).is_equal_approx(0.0, 0.001)
	assert_float(mesh.vertices[inner.vertex_indices[2]].x).is_equal_approx(1.0, 0.001)


func test_negative_amount_side_wall_normals_are_horizontal() -> void:
	var mesh := _make_plus_y_quad()
	InsetOperation.apply(mesh, [0], -0.25, {}, {})
	for fi: int in range(1, mesh.faces.size()):
		var n: Vector3 = mesh.compute_face_normal(mesh.faces[fi])
		# Vertical walls → normals lie flat in XZ, no Y component.
		assert_float(n.y).is_less(0.001)
		assert_float(n.length()).is_equal_approx(1.0, 0.001)


func test_negative_amount_populates_side_geometry() -> void:
	var mesh := _make_plus_y_quad()
	InsetOperation.apply(mesh, [0], -0.25, {}, {})
	# 1 inner face + 4 border quads.
	assert_int(mesh.faces.size()).is_equal(5)
	assert_int(mesh.vertices.size()).is_equal(8)


func test_negative_amount_inner_normal_is_minus_face_normal() -> void:
	var mesh := _make_plus_y_quad()
	var normals: Dictionary = {}
	InsetOperation.apply(mesh, [0], -0.25, {}, normals)
	assert_int(normals.size()).is_equal(4)
	for idx: int in normals:
		var n: Vector3 = normals[idx]
		assert_float(n.dot(Vector3.UP)).is_greater_equal(0.999)


func test_positive_amount_inner_normal_is_face_normal() -> void:
	var mesh := _make_plus_y_quad()
	var normals: Dictionary = {}
	InsetOperation.apply(mesh, [0], 0.5, {}, normals)
	for idx: int in normals:
		var n: Vector3 = normals[idx]
		assert_float(n.dot(Vector3.UP)).is_greater_equal(0.999)


func test_negative_amount_inner_centroids_still_populated() -> void:
	var mesh := _make_plus_y_quad()
	var centroids: Dictionary = {}
	InsetOperation.apply(mesh, [0], -0.25, centroids, {})
	assert_int(centroids.size()).is_equal(4)
	for idx: int in centroids:
		var c: Vector3 = centroids[idx]
		assert_vector(c).is_equal_approx(Vector3(0.5, 0.0, 0.5), Vector3.ONE * 0.001)


# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

func test_negative_amount_empty_selection_is_noop() -> void:
	var mesh := _make_plus_y_quad()
	InsetOperation.apply(mesh, [], -0.25, {}, {})
	assert_int(mesh.vertices.size()).is_equal(4)
	assert_int(mesh.faces.size()).is_equal(1)


func test_negative_amount_invalid_index_is_skipped() -> void:
	var mesh := _make_plus_y_quad()
	InsetOperation.apply(mesh, [99], -0.25, {}, {})
	assert_int(mesh.vertices.size()).is_equal(4)
	assert_int(mesh.faces.size()).is_equal(1)


func test_inset_rebuilds_edges_in_negative_mode() -> void:
	var mesh := _make_plus_y_quad()
	InsetOperation.apply(mesh, [0], -0.25, {}, {})
	assert_int(mesh.edges.size()).is_greater(0)