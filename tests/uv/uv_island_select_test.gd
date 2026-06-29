## UvIslandSelect unit tests.
extends GdUnitTestSuite

const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")


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
	f2.uvs = [Vector2(0.6, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 0.5), Vector2(0.6, 0.5)]
	gbm.faces = [f1, f2]
	return gbm


# ---------------------------------------------------------------------------
# select_island
# ---------------------------------------------------------------------------

func test_select_island_two_island_mesh() -> void:
	var mesh := _make_two_island_mesh()
	# Face 0 and face 1 are in separate islands (no shared UV positions).
	var island0 := UvIslandSelect.select_island(mesh, 0)
	assert_int(island0.size()).is_equal(1)
	assert_int(island0[0]).is_equal(0)
	var island1 := UvIslandSelect.select_island(mesh, 1)
	assert_int(island1.size()).is_equal(1)
	assert_int(island1[0]).is_equal(1)


func test_select_island_connected_mesh() -> void:
	# Two faces sharing a UV edge.
	var mesh := GoBuildMesh.new()
	mesh.vertices = [
		Vector3(0.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0),
		Vector3(1.0, 1.0, 0.0), Vector3(0.0, 1.0, 0.0),
		Vector3(2.0, 1.0, 0.0), Vector3(2.0, 0.0, 0.0),
	]
	var f1 := GoBuildFace.new()
	f1.vertex_indices = [0, 1, 2, 3]
	f1.uvs = [Vector2(0.0, 0.0), Vector2(0.5, 0.0), Vector2(0.5, 1.0), Vector2(0.0, 1.0)]
	var f2 := GoBuildFace.new()
	f2.vertex_indices = [1, 4, 2]
	f2.uvs = [Vector2(0.5, 0.0), Vector2(1.0, 0.0), Vector2(0.5, 1.0)]
	mesh.faces = [f1, f2]
	# Face 1 shares UV vertex (0.5, 0.0) and (0.5, 1.0) with face 0.
	var island := UvIslandSelect.select_island(mesh, 0)
	assert_int(island.size()).is_equal(2)
	assert_that(island.has(0)).is_true()
	assert_that(island.has(1)).is_true()


func test_select_island_on_cube() -> void:
	var mesh := CubeGenerator.generate(1.0, 1.0, 1.0, 0)
	# Default cube has per-face UVs: each face is its own island.
	var island := UvIslandSelect.select_island(mesh, 0)
	assert_int(island.size()).is_equal(1)
	assert_int(island[0]).is_equal(0)


func test_select_island_invalid_face() -> void:
	var mesh := CubeGenerator.generate(1.0, 1.0, 1.0, 0)
	var island := UvIslandSelect.select_island(mesh, -1)
	assert_int(island.size()).is_equal(0)
	island = UvIslandSelect.select_island(mesh, 999)
	assert_int(island.size()).is_equal(0)


func test_select_island_empty_mesh() -> void:
	var mesh := GoBuildMesh.new()
	var island := UvIslandSelect.select_island(mesh, 0)
	assert_int(island.size()).is_equal(0)


# ---------------------------------------------------------------------------
# build_all_islands
# ---------------------------------------------------------------------------

func test_build_all_islands_two_islands() -> void:
	var mesh := _make_two_island_mesh()
	var islands := UvIslandSelect.build_all_islands(mesh)
	assert_int(islands.size()).is_equal(2)


func test_build_all_islands_connected() -> void:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [
		Vector3(0.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0),
		Vector3(1.0, 1.0, 0.0), Vector3(0.0, 1.0, 0.0),
		Vector3(2.0, 1.0, 0.0), Vector3(2.0, 0.0, 0.0),
	]
	var f1 := GoBuildFace.new()
	f1.vertex_indices = [0, 1, 2, 3]
	f1.uvs = [Vector2(0.0, 0.0), Vector2(0.5, 0.0), Vector2(0.5, 1.0), Vector2(0.0, 1.0)]
	var f2 := GoBuildFace.new()
	f2.vertex_indices = [1, 4, 2]
	f2.uvs = [Vector2(0.5, 0.0), Vector2(1.0, 0.0), Vector2(0.5, 1.0)]
	mesh.faces = [f1, f2]
	var islands := UvIslandSelect.build_all_islands(mesh)
	assert_int(islands.size()).is_equal(1)
	assert_int(islands[0].size()).is_equal(2)


func test_build_all_islands_empty_mesh() -> void:
	var mesh := GoBuildMesh.new()
	var islands := UvIslandSelect.build_all_islands(mesh)
	assert_int(islands.size()).is_equal(0)