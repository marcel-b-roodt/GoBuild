## UvPackIslands unit tests — GdUnit4
extends GdUnitTestSuite

const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")


func _make_two_island_mesh() -> GoBuildMesh:
	var gbm := GoBuildMesh.new()
	gbm.vertices = [
		Vector3(0.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0),
		Vector3(1.0, 1.0, 0.0), Vector3(0.0, 1.0, 0.0),
		Vector3(2.0, 0.0, 0.0), Vector3(3.0, 0.0, 0.0),
		Vector3(3.0, 1.0, 0.0), Vector3(2.0, 1.0, 0.0),
	]
	var f1 := GoBuildFace.new()
	f1.vertex_indices = [0, 1, 2, 3]
	f1.uvs = [Vector2(0.0, 0.0), Vector2(0.5, 0.0), Vector2(0.5, 0.5), Vector2(0.0, 0.5)]
	var f2 := GoBuildFace.new()
	f2.vertex_indices = [4, 5, 6, 7]
	f2.uvs = [Vector2(0.5, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 0.5), Vector2(0.5, 0.5)]
	gbm.faces = [f1, f2]
	return gbm


func test_pack_returns_island_count() -> void:
	var gbm := _make_two_island_mesh()
	var count := UvPackIslands.apply(gbm)
	assert_int(count).is_equal(2)


func test_pack_uvs_within_tile() -> void:
	var gbm := _make_two_island_mesh()
	UvPackIslands.apply(gbm)
	for face: GoBuildFace in gbm.faces:
		for uv: Vector2 in face.uvs:
			assert_float(uv.x).is_greater_equal(-0.02)
			assert_float(uv.y).is_greater_equal(-0.02)
			assert_float(uv.x).is_less_equal(1.02)
			assert_float(uv.y).is_less_equal(1.02)


func test_pack_empty_mesh() -> void:
	var gbm := GoBuildMesh.new()
	var count := UvPackIslands.apply(gbm)
	assert_int(count).is_equal(0)


func test_pack_single_face() -> void:
	var gbm := GoBuildMesh.new()
	gbm.vertices = [Vector3.ZERO, Vector3(1, 0, 0), Vector3(0, 1, 0)]
	var f := GoBuildFace.new()
	f.vertex_indices = [0, 1, 2]
	f.uvs = [Vector2(5.0, 5.0), Vector2(6.0, 5.0), Vector2(5.0, 6.0)]
	gbm.faces = [f]
	var count := UvPackIslands.apply(gbm)
	assert_int(count).is_equal(1)
	for uv: Vector2 in gbm.faces[0].uvs:
		assert_float(uv.x).is_greater_equal(-0.02)
		assert_float(uv.y).is_greater_equal(-0.02)