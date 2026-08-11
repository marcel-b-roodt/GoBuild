## Triangulate operation tests — GdUnit4
##
## Tests for [TriangulateOperation] covering:
##   - Quad → 2 triangles
##   - Pentagon → 3 triangles
##   - Hexagon → 4 triangles (fan fallback for non-planar)
##   - Triangle (no-op, already 3 vertices)
##   - Null / empty inputs
extends GdUnitTestSuite

const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _TRI_SCRIPT  := preload("res://addons/go_build/mesh/operations/triangulate_operation.gd")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Single quad on XZ plane.
func _make_quad() -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [
		Vector3(0, 0, 0), Vector3(1, 0, 0),
		Vector3(1, 0, 1), Vector3(0, 0, 1),
	]
	var f := GoBuildFace.new()
	f.vertex_indices = [0, 1, 2, 3]
	f.uvs = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	mesh.faces.append(f)
	mesh.rebuild_edges()
	return mesh


## Pentagon (convex) on XZ plane.
## v0=(0,0,0) v1=(1,0,0) v2=(1.5,0,1) v3=(0.5,0,1.5) v4=(-0.5,0,1)
func _make_pentagon() -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [
		Vector3(0, 0, 0), Vector3(1, 0, 0),
		Vector3(1.5, 0, 1), Vector3(0.5, 0, 1.5),
		Vector3(-0.5, 0, 1),
	]
	var f := GoBuildFace.new()
	f.vertex_indices = [0, 1, 2, 3, 4]
	f.uvs = []
	f.uvs.resize(5)
	f.uvs.fill(Vector2.ZERO)
	mesh.faces.append(f)
	mesh.rebuild_edges()
	return mesh


## Hexagon formed by dissolving a cube corner — non-planar.
## Simulates the result of dissolving vertex 1 on a standard cube.
func _make_nonplanar_hex() -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	# Original cube vertices (without the dissolved vertex 1).
	mesh.vertices = [
		Vector3(0, 0, 0),   # 0
		Vector3(1, 0, 1),   # 1 (was 2)
		Vector3(0, 1, 0),   # 2 (was 4)
		Vector3(1, 1, 0),   # 3 (was 5)
		Vector3(1, 1, 1),   # 4 (was 6)
		Vector3(0, 1, 1),   # 5 (was 7)
	]
	var f := GoBuildFace.new()
	# This hexagon wraps around a cube corner — definitely non-planar.
	f.vertex_indices = [0, 1, 4, 5, 2, 3]
	f.uvs = []
	f.uvs.resize(6)
	f.uvs.fill(Vector2.ZERO)
	mesh.faces.append(f)
	mesh.rebuild_edges()
	return mesh


## Single triangle.
func _make_triangle() -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)]
	var f := GoBuildFace.new()
	f.vertex_indices = [0, 1, 2]
	f.uvs = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	mesh.faces.append(f)
	mesh.rebuild_edges()
	return mesh


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_triangulate_quad_produces_two_triangles() -> void:
	var mesh := _make_quad()
	TriangulateOperation.apply(mesh, [0])
	assert_int(mesh.faces.size()).is_equal(2)
	for f: GoBuildFace in mesh.faces:
		assert_int(f.vertex_indices.size()).is_equal(3)


func test_triangulate_pentagon_produces_three_triangles() -> void:
	var mesh := _make_pentagon()
	TriangulateOperation.apply(mesh, [0])
	assert_int(mesh.faces.size()).is_equal(3)
	for f: GoBuildFace in mesh.faces:
		assert_int(f.vertex_indices.size()).is_equal(3)


func test_triangulate_nonplanar_hex_uses_fan_fallback() -> void:
	var mesh := _make_nonplanar_hex()
	# This should succeed — ear_clip will fail, fan fallback kicks in.
	TriangulateOperation.apply(mesh, [0])
	assert_int(mesh.faces.size()).is_equal(4, "Non-planar hex should produce 4 triangles")
	for f: GoBuildFace in mesh.faces:
		assert_int(f.vertex_indices.size()).is_equal(3)


func test_triangulate_triangle_is_noop() -> void:
	var mesh := _make_triangle()
	TriangulateOperation.apply(mesh, [0])
	# Triangle should be left unchanged.
	assert_int(mesh.faces.size()).is_equal(1)
	assert_int(mesh.faces[0].vertex_indices.size()).is_equal(3)


func test_triangulate_null_mesh() -> void:
	TriangulateOperation.apply(null, [0])
	# Should not crash.


func test_triangulate_empty_indices() -> void:
	var mesh := _make_quad()
	TriangulateOperation.apply(mesh, [])
	assert_int(mesh.faces.size()).is_equal(1)


func test_triangulate_preserves_material() -> void:
	var mesh := _make_quad()
	mesh.faces[0].material_index = 2
	mesh.faces[0].smooth_group = 5
	TriangulateOperation.apply(mesh, [0])
	for f: GoBuildFace in mesh.faces:
		assert_int(f.material_index).is_equal(2)
		assert_int(f.smooth_group).is_equal(5)


func test_triangulate_multiple_faces() -> void:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [
		Vector3(0, 0, 0), Vector3(1, 0, 0),
		Vector3(1, 0, 1), Vector3(0, 0, 1),
		Vector3(2, 0, 0), Vector3(2, 0, 1),
	]
	var f0 := GoBuildFace.new()
	f0.vertex_indices = [0, 1, 2, 3]
	f0.uvs = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	var f1 := GoBuildFace.new()
	f1.vertex_indices = [1, 4, 5, 2]
	f1.uvs = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	mesh.faces.append(f0)
	mesh.faces.append(f1)
	mesh.rebuild_edges()
	TriangulateOperation.apply(mesh, [0, 1])
	assert_int(mesh.faces.size()).is_equal(4)
	for f: GoBuildFace in mesh.faces:
		assert_int(f.vertex_indices.size()).is_equal(3)