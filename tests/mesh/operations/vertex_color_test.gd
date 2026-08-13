## VertexColorOperation tests — GdUnit4
##
## Tests for [VertexColorOperation] covering:
##   - fill_faces: paint all vertices of selected faces
##   - fill_all: paint every vertex
##   - set_vertices: paint specific vertices
##   - Blend modes: Mix, Add, Subtract, Multiply
##   - Channel masking: R-only, G-only, RGB, etc.
##   - _ensure_channel: lazy init (white for COLOR, zero for custom)
extends GdUnitTestSuite

const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _VC_OP_SCRIPT := preload("res://addons/go_build/mesh/operations/vertex_color_operation.gd")


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


func _make_two_quads() -> GoBuildMesh:
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
	return mesh


# ---------------------------------------------------------------------------
# fill_faces
# ---------------------------------------------------------------------------

func test_fill_faces_paints_selected_face_vertices() -> void:
	var mesh := _make_two_quads()
	VertexColorOperation.fill_faces(mesh, [0], Color.RED)
	assert_color_equal(mesh.vertex_colors[0], Color.RED)
	assert_color_equal(mesh.vertex_colors[1], Color.RED)
	assert_color_equal(mesh.vertex_colors[2], Color.RED)
	assert_color_equal(mesh.vertex_colors[3], Color.RED)
	assert_color_equal(mesh.vertex_colors[4], Color.WHITE)
	assert_color_equal(mesh.vertex_colors[5], Color.WHITE)


func test_fill_faces_no_duplicate_work() -> void:
	var mesh := _make_two_quads()
	VertexColorOperation.fill_faces(mesh, [0, 1], Color.RED)
	for i: int in mesh.vertices.size():
		assert_color_equal(mesh.vertex_colors[i], Color.RED)


func test_fill_faces_null_mesh() -> void:
	VertexColorOperation.fill_faces(null, [0], Color.RED)


func test_fill_faces_empty_indices() -> void:
	var mesh := _make_quad()
	VertexColorOperation.fill_faces(mesh, [], Color.RED)
	for i: int in mesh.vertices.size():
		assert_color_equal(mesh.vertex_colors[i], Color.WHITE)


func test_fill_faces_out_of_range_index() -> void:
	var mesh := _make_quad()
	VertexColorOperation.fill_faces(mesh, [99], Color.RED)
	for i: int in mesh.vertices.size():
		assert_color_equal(mesh.vertex_colors[i], Color.WHITE)


# ---------------------------------------------------------------------------
# fill_all
# ---------------------------------------------------------------------------

func test_fill_all_paints_every_vertex() -> void:
	var mesh := _make_two_quads()
	VertexColorOperation.fill_all(mesh, Color.BLUE)
	for i: int in mesh.vertices.size():
		assert_color_equal(mesh.vertex_colors[i], Color.BLUE)


func test_fill_all_null_mesh() -> void:
	VertexColorOperation.fill_all(null, Color.RED)


# ---------------------------------------------------------------------------
# set_vertices
# ---------------------------------------------------------------------------

func test_set_vertices_paints_specific_vertices() -> void:
	var mesh := _make_quad()
	VertexColorOperation.set_vertices(mesh, [0, 2], Color.GREEN)
	assert_color_equal(mesh.vertex_colors[0], Color.GREEN)
	assert_color_equal(mesh.vertex_colors[1], Color.WHITE)
	assert_color_equal(mesh.vertex_colors[2], Color.GREEN)
	assert_color_equal(mesh.vertex_colors[3], Color.WHITE)


func test_set_vertices_null_mesh() -> void:
	VertexColorOperation.set_vertices(null, [0], Color.RED)


func test_set_vertices_out_of_range() -> void:
	var mesh := _make_quad()
	VertexColorOperation.set_vertices(mesh, [99], Color.RED)
	for i: int in mesh.vertices.size():
		assert_color_equal(mesh.vertex_colors[i], Color.WHITE)


# ---------------------------------------------------------------------------
# Blend modes
# ---------------------------------------------------------------------------

func test_blend_mode_mix() -> void:
	var mesh := _make_quad()
	mesh.vertex_colors[0] = Color(0.5, 0.5, 0.5, 1.0)
	VertexColorOperation.fill_faces(
		mesh, [0], Color(1.0, 0.0, 0.0, 1.0),
		VertexColorOperation.BlendMode.MIX, VertexColorOperation.CHANNEL_ALL)
	assert_color_equal(mesh.vertex_colors[0], Color(1.0, 0.0, 0.0, 1.0))


func test_blend_mode_add() -> void:
	var mesh := _make_quad()
	mesh.vertex_colors[0] = Color(0.5, 0.5, 0.5, 1.0)
	VertexColorOperation.fill_faces(
		mesh, [0], Color(0.3, 0.3, 0.3, 0.5),
		VertexColorOperation.BlendMode.ADD, VertexColorOperation.CHANNEL_ALL)
	assert_color_equal(mesh.vertex_colors[0], Color(0.8, 0.8, 0.8, 1.0))


func test_blend_mode_subtract() -> void:
	var mesh := _make_quad()
	mesh.vertex_colors[0] = Color(0.8, 0.8, 0.8, 1.0)
	VertexColorOperation.fill_faces(
		mesh, [0], Color(0.3, 0.3, 0.3, 0.5),
		VertexColorOperation.BlendMode.SUBTRACT, VertexColorOperation.CHANNEL_ALL)
	assert_color_equal(mesh.vertex_colors[0], Color(0.5, 0.5, 0.5, 0.5))


func test_blend_mode_multiply() -> void:
	var mesh := _make_quad()
	mesh.vertex_colors[0] = Color(1.0, 0.5, 0.0, 1.0)
	VertexColorOperation.fill_faces(
		mesh, [0], Color(0.5, 0.5, 0.5, 1.0),
		VertexColorOperation.BlendMode.MULTIPLY, VertexColorOperation.CHANNEL_ALL)
	assert_color_equal(mesh.vertex_colors[0], Color(0.5, 0.25, 0.0, 1.0))


func test_blend_mode_add_clamps() -> void:
	var mesh := _make_quad()
	mesh.vertex_colors[0] = Color(0.9, 0.9, 0.9, 1.0)
	VertexColorOperation.fill_faces(
		mesh, [0], Color(0.5, 0.5, 0.5, 0.5),
		VertexColorOperation.BlendMode.ADD, VertexColorOperation.CHANNEL_ALL)
	assert_color_equal(mesh.vertex_colors[0], Color(1.0, 1.0, 1.0, 1.0))


func test_blend_mode_subtract_clamps() -> void:
	var mesh := _make_quad()
	mesh.vertex_colors[0] = Color(0.1, 0.1, 0.1, 0.2)
	VertexColorOperation.fill_faces(
		mesh, [0], Color(0.5, 0.5, 0.5, 0.5),
		VertexColorOperation.BlendMode.SUBTRACT, VertexColorOperation.CHANNEL_ALL)
	assert_color_equal(mesh.vertex_colors[0], Color(0.0, 0.0, 0.0, 0.0))


# ---------------------------------------------------------------------------
# Channel masking
# ---------------------------------------------------------------------------

func test_channel_mask_r_only() -> void:
	var mesh := _make_quad()
	mesh.vertex_colors[0] = Color(0.0, 0.0, 0.0, 1.0)
	VertexColorOperation.fill_faces(
		mesh, [0], Color(1.0, 1.0, 1.0, 0.0),
		VertexColorOperation.BlendMode.MIX, VertexColorOperation.CHANNEL_R)
	assert_color_equal(mesh.vertex_colors[0], Color(1.0, 0.0, 0.0, 1.0))


func test_channel_mask_rgb() -> void:
	var mesh := _make_quad()
	mesh.vertex_colors[0] = Color(0.0, 0.0, 0.0, 1.0)
	VertexColorOperation.fill_faces(
		mesh, [0], Color(1.0, 1.0, 1.0, 0.0),
		VertexColorOperation.BlendMode.MIX, VertexColorOperation.CHANNEL_RGB)
	assert_color_equal(mesh.vertex_colors[0], Color(1.0, 1.0, 1.0, 1.0))


func test_channel_mask_a_only() -> void:
	var mesh := _make_quad()
	mesh.vertex_colors[0] = Color(0.0, 0.0, 0.0, 1.0)
	VertexColorOperation.fill_faces(
		mesh, [0], Color(1.0, 1.0, 1.0, 0.5),
		VertexColorOperation.BlendMode.MIX, VertexColorOperation.CHANNEL_A)
	assert_color_equal(mesh.vertex_colors[0], Color(0.0, 0.0, 0.0, 0.5))


# ---------------------------------------------------------------------------
# _ensure_channel
# ---------------------------------------------------------------------------

func test_ensure_channel_initializes_white_for_color() -> void:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [Vector3.ZERO, Vector3.RIGHT, Vector3.FORWARD]
	var f := GoBuildFace.new()
	f.vertex_indices = [0, 1, 2]
	f.uvs = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	mesh.faces.append(f)
	assert_int(mesh.vertex_colors.size()).is_equal(0)
	VertexColorOperation.fill_all(mesh, Color.RED)
	assert_int(mesh.vertex_colors.size()).is_equal(3)
	assert_color_equal(mesh.vertex_colors[0], Color.RED)
	assert_color_equal(mesh.vertex_colors[1], Color.RED)
	assert_color_equal(mesh.vertex_colors[2], Color.RED)


func test_ensure_channel_initializes_zero_for_custom() -> void:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [Vector3.ZERO, Vector3.RIGHT, Vector3.FORWARD]
	var f := GoBuildFace.new()
	f.vertex_indices = [0, 1, 2]
	f.uvs = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	mesh.faces.append(f)
	assert_int(mesh.custom_channel_0.size()).is_equal(0)
	VertexColorOperation.fill_all(mesh, Color.RED, VertexColorOperation.BlendMode.MIX,
		VertexColorOperation.CHANNEL_ALL, VertexColorOperation.TargetChannel.CUSTOM0)
	assert_int(mesh.custom_channel_0.size()).is_equal(3)
	assert_color_equal(mesh.custom_channel_0[0], Color.RED)
	assert_color_equal(mesh.custom_channel_0[1], Color.RED)
	assert_color_equal(mesh.custom_channel_0[2], Color.RED)


func test_fill_faces_custom_channel() -> void:
	var mesh := _make_two_quads()
	VertexColorOperation.fill_faces(mesh, [0], Color.RED, VertexColorOperation.BlendMode.MIX,
		VertexColorOperation.CHANNEL_ALL, VertexColorOperation.TargetChannel.CUSTOM1)
	assert_color_equal(mesh.custom_channel_1[0], Color.RED)
	assert_color_equal(mesh.custom_channel_1[1], Color.RED)
	assert_color_equal(mesh.custom_channel_1[2], Color.RED)
	assert_color_equal(mesh.custom_channel_1[3], Color.RED)
	assert_color_equal(mesh.custom_channel_1[4], Color(0, 0, 0, 0))
	assert_color_equal(mesh.custom_channel_1[5], Color(0, 0, 0, 0))


func test_set_vertices_custom_channel() -> void:
	var mesh := _make_quad()
	VertexColorOperation.set_vertices(mesh, [0, 2], Color.GREEN, VertexColorOperation.BlendMode.MIX,
		VertexColorOperation.CHANNEL_ALL, VertexColorOperation.TargetChannel.CUSTOM2)
	assert_color_equal(mesh.custom_channel_2[0], Color.GREEN)
	assert_color_equal(mesh.custom_channel_2[1], Color(0, 0, 0, 0))
	assert_color_equal(mesh.custom_channel_2[2], Color.GREEN)
	assert_color_equal(mesh.custom_channel_2[3], Color(0, 0, 0, 0))


func test_custom_channel_blend_mode_add() -> void:
	var mesh := _make_quad()
	VertexColorOperation.fill_all(mesh, Color(0.5, 0.5, 0.5, 0.5), VertexColorOperation.BlendMode.MIX,
		VertexColorOperation.CHANNEL_ALL, VertexColorOperation.TargetChannel.CUSTOM0)
	VertexColorOperation.fill_all(mesh, Color(0.3, 0.3, 0.3, 0.3), VertexColorOperation.BlendMode.ADD,
		VertexColorOperation.CHANNEL_ALL, VertexColorOperation.TargetChannel.CUSTOM0)
	assert_color_equal(mesh.custom_channel_0[0], Color(0.8, 0.8, 0.8, 0.8))


func test_custom_channel_mask_r_only() -> void:
	var mesh := _make_quad()
	VertexColorOperation.fill_all(mesh, Color(0, 0, 0, 0), VertexColorOperation.BlendMode.MIX,
		VertexColorOperation.CHANNEL_ALL, VertexColorOperation.TargetChannel.CUSTOM3)
	VertexColorOperation.fill_all(mesh, Color(1, 0, 0, 0), VertexColorOperation.BlendMode.MIX,
		VertexColorOperation.CHANNEL_R, VertexColorOperation.TargetChannel.CUSTOM3)
	assert_color_equal(mesh.custom_channel_3[0], Color(1, 0, 0, 0))


func test_bake_includes_custom_channels() -> void:
	var mesh := _make_quad()
	VertexColorOperation.fill_all(mesh, Color.RED, VertexColorOperation.BlendMode.MIX,
		VertexColorOperation.CHANNEL_ALL, VertexColorOperation.TargetChannel.CUSTOM0)
	var baked: ArrayMesh = mesh.bake()
	assert_int(baked.get_surface_count()).is_greater(0)
	var arrays: Array = baked.surface_get_arrays(0)
	assert_that(arrays[Mesh.ARRAY_CUSTOM0]).is_not_null()


func test_bake_omits_empty_custom_channels() -> void:
	var mesh := _make_quad()
	var baked: ArrayMesh = mesh.bake()
	assert_int(baked.get_surface_count()).is_greater(0)
	var arrays: Array = baked.surface_get_arrays(0)
	# Custom channels should be null when empty
	assert_that(arrays[Mesh.ARRAY_CUSTOM0] == null or arrays[Mesh.ARRAY_CUSTOM0].is_empty()).is_true()


# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------

func assert_color_equal(actual: Color, expected: Color, delta: float = 0.001) -> void:
	assert_float(actual.r).is_equal_approx(expected.r, delta)
	assert_float(actual.g).is_equal_approx(expected.g, delta)
	assert_float(actual.b).is_equal_approx(expected.b, delta)
	assert_float(actual.a).is_equal_approx(expected.a, delta)