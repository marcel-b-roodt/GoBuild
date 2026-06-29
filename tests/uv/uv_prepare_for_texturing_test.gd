## UvPrepareForTexturing unit tests.
extends GdUnitTestSuite

const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")


func test_prepare_cube() -> void:
	var mesh := CubeGenerator.generate(1.0, 1.0, 1.0, 0)
	# Before: default cube has per-face UVs, each face in its own island.
	var islands_before := UvIslandSelect.build_all_islands(mesh)
	assert_int(islands_before.size()).is_equal(6)

	var count := UvPrepareForTexturing.apply(mesh)
	# After: Box projection + pack should produce islands (6 from a cube
	# with Box projection — opposing faces share projections).
	assert_int(count).is_greater(0)
	# All UVs should be within the 0-1 range.
	for face: GoBuildFace in mesh.faces:
		for uv: Vector2 in face.uvs:
			assert_that(uv.x >= -0.01).is_true()
			assert_that(uv.x <= 1.01).is_true()
			assert_that(uv.y >= -0.01).is_true()
			assert_that(uv.y <= 1.01).is_true()


func test_prepare_plane() -> void:
	var mesh := PlaneGenerator.generate(2.0, 2.0, 1, 1)
	var count := UvPrepareForTexturing.apply(mesh)
	# A single quad plane should pack into one island.
	assert_int(count).is_equal(1)
	# All UVs should be within 0-1 range.
	for face: GoBuildFace in mesh.faces:
		for uv: Vector2 in face.uvs:
			assert_that(uv.x >= -0.01).is_true()
			assert_that(uv.x <= 1.01).is_true()
			assert_that(uv.y >= -0.01).is_true()
			assert_that(uv.y <= 1.01).is_true()


func test_prepare_empty_mesh() -> void:
	var mesh := GoBuildMesh.new()
	var count := UvPrepareForTexturing.apply(mesh)
	assert_int(count).is_equal(0)


func test_prepare_resets_face_projection_mode() -> void:
	var mesh := CubeGenerator.generate(1.0, 1.0, 1.0, 0)
	# Set some faces to a non-NONE projection mode.
	mesh.faces[0].uv_projection_mode = GoBuildFace.UvMode.PLANAR
	mesh.faces[1].uv_projection_mode = GoBuildFace.UvMode.BOX
	UvPrepareForTexturing.apply(mesh)
	# After prepare, all faces should have NONE mode (set by the operation).
	for face: GoBuildFace in mesh.faces:
		assert_int(face.uv_projection_mode).is_equal(GoBuildFace.UvMode.NONE)