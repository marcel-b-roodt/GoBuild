## UvStitchIslands unit tests — GdUnit4
extends GdUnitTestSuite

const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")


func _make_two_separate_islands() -> GoBuildMesh:
	var gbm := GoBuildMesh.new()
	gbm.vertices = [
		Vector3(0.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0),
		Vector3(1.0, 1.0, 0.0),
		Vector3(2.0, 0.0, 0.0), Vector3(3.0, 0.0, 0.0),
		Vector3(3.0, 1.0, 0.0),
	]
	var f1 := GoBuildFace.new()
	f1.vertex_indices = [0, 1, 2]
	f1.uvs = [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0)]
	var f2 := GoBuildFace.new()
	f2.vertex_indices = [3, 4, 5]
	f2.uvs = [Vector2(3.0, 0.0), Vector2(3.0, 1.0), Vector2(4.0, 1.0)]
	gbm.faces = [f1, f2]
	gbm.rebuild_edges()
	return gbm


func test_stitch_no_shared_edge() -> void:
	var gbm := _make_two_separate_islands()
	var count := UvStitchIslands.apply(gbm, [0, 1])
	assert_int(count).is_equal(0)


func test_stitch_shared_edge() -> void:
	var gbm := GoBuildMesh.new()
	gbm.vertices = [
		Vector3(0.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0),
		Vector3(0.5, 1.0, 0.0), Vector3(1.5, 1.0, 0.0),
	]
	var f1 := GoBuildFace.new()
	f1.vertex_indices = [0, 1, 2]
	f1.uvs = [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.5, 1.0)]
	var f2 := GoBuildFace.new()
	f2.vertex_indices = [1, 3, 2]
	f2.uvs = [Vector2(3.0, 0.0), Vector2(3.0, 1.0), Vector2(4.0, 1.0)]
	gbm.faces = [f1, f2]
	gbm.rebuild_edges()
	var count := UvStitchIslands.apply(gbm, [0, 1])
	assert_int(count).is_equal(1)
	assert_vector(gbm.faces[1].uvs[0]).is_equal(Vector2(1.0, 0.0))


func test_stitch_empty_selection() -> void:
	var gbm := GoBuildMesh.new()
	gbm.vertices = [Vector3.ZERO]
	var count := UvStitchIslands.apply(gbm, [])
	assert_int(count).is_equal(0)