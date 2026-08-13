## GoBuildVertexPaintBrush tests — GdUnit4
##
## Tests for [GoBuildVertexPaintBrush.paint_vertices_in_radius] covering:
##   - vertex selection within radius
##   - strength scaling
##   - blend modes (Mix, Add)
##   - channel masking (R-only)
##   - zero radius hits nothing
##   - stroke lifecycle (begin/end/cancel)
##   - custom channel targets (CUSTOM0–CUSTOM3)
##   - custom channel blend and mask
##   - painted_vertices dictionary with custom channels
extends GdUnitTestSuite

const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _BRUSH_SCRIPT := preload(
		"res://addons/go_build/vertex_paint/go_build_vertex_paint_brush.gd")
const _VC_OP_SCRIPT := preload(
		"res://addons/go_build/mesh/operations/vertex_color_operation.gd")


func _make_unit_cube() -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [
		Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.5, -0.5),
		Vector3(0.5, -0.5, 0.5), Vector3(-0.5, -0.5, 0.5),
		Vector3(-0.5, 0.5, -0.5), Vector3(0.5, 0.5, -0.5),
		Vector3(0.5, 0.5, 0.5), Vector3(-0.5, 0.5, 0.5),
	]
	var colors: Array[Color] = []
	colors.resize(8)
	colors.fill(Color.WHITE)
	mesh.vertex_colors = colors
	var faces_data: Array = [
		[0, 3, 2, 1], [4, 5, 6, 7], [0, 4, 7, 3],
		[1, 2, 6, 5], [0, 1, 5, 4], [3, 7, 6, 2],
	]
	for vi_arr: Array in faces_data:
		var f := GoBuildFace.new()
		f.vertex_indices.assign(vi_arr)
		f.uvs.resize(vi_arr.size())
		mesh.faces.append(f)
	mesh.rebuild_edges()
	return mesh


func assert_color_equal(actual: Color, expected: Color, delta: float = 0.001) -> void:
	assert_float(actual.r).is_equal_approx(expected.r, delta)
	assert_float(actual.g).is_equal_approx(expected.g, delta)
	assert_float(actual.b).is_equal_approx(expected.b, delta)
	assert_float(actual.a).is_equal_approx(expected.a, delta)


func test_paint_near_origin_selects_nearby_vertices() -> void:
	var mesh := _make_unit_cube()
	GoBuildVertexPaintBrush.paint_vertices_in_radius(
		mesh, Vector3.ZERO, 1.0,
		Color.RED, VertexColorOperation.BlendMode.MIX,
		VertexColorOperation.CHANNEL_ALL, 1.0)
	var red_count: int = 0
	for c: Color in mesh.vertex_colors:
		if c.is_equal_approx(Color.RED):
			red_count += 1
	assert_int(red_count).is_greater(0)
	assert_int(red_count).is_less(8)


func test_paint_large_radius_covers_all() -> void:
	var mesh := _make_unit_cube()
	GoBuildVertexPaintBrush.paint_vertices_in_radius(
		mesh, Vector3.ZERO, 10.0,
		Color.BLUE, VertexColorOperation.BlendMode.MIX,
		VertexColorOperation.CHANNEL_ALL, 1.0)
	for c: Color in mesh.vertex_colors:
		assert_color_equal(c, Color.BLUE)


func test_paint_zero_radius_hits_none() -> void:
	var mesh := _make_unit_cube()
	GoBuildVertexPaintBrush.paint_vertices_in_radius(
		mesh, Vector3.ZERO, 0.0,
		Color.RED, VertexColorOperation.BlendMode.MIX,
		VertexColorOperation.CHANNEL_ALL, 1.0)
	for c: Color in mesh.vertex_colors:
		assert_color_equal(c, Color.WHITE)


func test_paint_strength_scales_colour() -> void:
	var mesh := _make_unit_cube()
	GoBuildVertexPaintBrush.paint_vertices_in_radius(
		mesh, Vector3.ZERO, 10.0,
		Color.GREEN, VertexColorOperation.BlendMode.MIX,
		VertexColorOperation.CHANNEL_ALL, 0.5)
	var half_green := Color(0.0, 0.5, 0.0, 0.5)
	for c: Color in mesh.vertex_colors:
		assert_color_equal(c, half_green)


func test_paint_blend_mode_add() -> void:
	var mesh := _make_unit_cube()
	mesh.vertex_colors[0] = Color(0.5, 0.5, 0.5, 1.0)
	GoBuildVertexPaintBrush.paint_vertices_in_radius(
		mesh, Vector3(-0.5, -0.5, -0.5), 0.01,
		Color(0.2, 0.2, 0.2, 0.0), VertexColorOperation.BlendMode.ADD,
		VertexColorOperation.CHANNEL_ALL, 1.0)
	assert_color_equal(mesh.vertex_colors[0], Color(0.7, 0.7, 0.7, 1.0))


func test_paint_channel_mask_r_only() -> void:
	var mesh := _make_unit_cube()
	GoBuildVertexPaintBrush.paint_vertices_in_radius(
		mesh, Vector3.ZERO, 10.0,
		Color.RED, VertexColorOperation.BlendMode.MIX,
		VertexColorOperation.CHANNEL_R, 1.0)
	for c: Color in mesh.vertex_colors:
		assert_float(c.r).is_equal_approx(1.0, 0.001)
		assert_float(c.g).is_equal_approx(0.0, 0.001)
		assert_float(c.b).is_equal_approx(0.0, 0.001)
		assert_float(c.a).is_equal_approx(1.0, 0.001)


func test_begin_end_stroke_lifecycle() -> void:
	var brush := GoBuildVertexPaintBrush.new()
	assert_bool(brush.is_active()).is_false()
	brush.begin_stroke(null)
	assert_bool(brush.is_active()).is_true()
	brush.end_stroke(null, null)
	assert_bool(brush.is_active()).is_false()


func test_cancel_stroke_deactivates() -> void:
	var brush := GoBuildVertexPaintBrush.new()
	brush.begin_stroke(null)
	assert_bool(brush.is_active()).is_true()
	brush.cancel_stroke(null)
	assert_bool(brush.is_active()).is_false()


func test_paint_at_not_active_does_nothing() -> void:
	var brush := GoBuildVertexPaintBrush.new()
	var mesh := _make_unit_cube()
	brush.paint_at(
		null, Vector3.ZERO, 10.0,
		Color.RED, VertexColorOperation.BlendMode.MIX,
		VertexColorOperation.CHANNEL_ALL, 1.0)
	for c: Color in mesh.vertex_colors:
		assert_color_equal(c, Color.WHITE)


func test_paint_returns_true_when_vertices_hit() -> void:
	var mesh := _make_unit_cube()
	var painted: Dictionary = {}
	var result: bool = GoBuildVertexPaintBrush.paint_vertices_in_radius(
		mesh, Vector3.ZERO, 10.0,
		Color.RED, VertexColorOperation.BlendMode.MIX,
		VertexColorOperation.CHANNEL_ALL, 1.0, painted)
	assert_bool(result).is_true()


func test_paint_returns_false_when_nothing_hit() -> void:
	var mesh := _make_unit_cube()
	var painted: Dictionary = {}
	var result: bool = GoBuildVertexPaintBrush.paint_vertices_in_radius(
		mesh, Vector3(100, 100, 100), 0.01,
		Color.RED, VertexColorOperation.BlendMode.MIX,
		VertexColorOperation.CHANNEL_ALL, 1.0, painted)
	assert_bool(result).is_false()


# ---------------------------------------------------------------------------
# Custom channel targets
# ---------------------------------------------------------------------------

func test_paint_custom0_target() -> void:
	var mesh := _make_unit_cube()
	GoBuildVertexPaintBrush.paint_vertices_in_radius(
		mesh, Vector3.ZERO, 10.0,
		Color.RED, VertexColorOperation.BlendMode.MIX,
		VertexColorOperation.CHANNEL_ALL, 1.0, {},
		VertexColorOperation.TargetChannel.CUSTOM0)
	assert_int(mesh.custom_channel_0.size()).is_equal(8)
	for c: Color in mesh.custom_channel_0:
		assert_color_equal(c, Color.RED)


func test_paint_custom1_target() -> void:
	var mesh := _make_unit_cube()
	GoBuildVertexPaintBrush.paint_vertices_in_radius(
		mesh, Vector3.ZERO, 10.0,
		Color(0.0, 1.0, 0.0, 0.5), VertexColorOperation.BlendMode.MIX,
		VertexColorOperation.CHANNEL_ALL, 1.0, {},
		VertexColorOperation.TargetChannel.CUSTOM1)
	assert_int(mesh.custom_channel_1.size()).is_equal(8)
	for c: Color in mesh.custom_channel_1:
		assert_color_equal(c, Color(0.0, 1.0, 0.0, 0.5))


func test_paint_custom2_target_partial_radius() -> void:
	var mesh := _make_unit_cube()
	GoBuildVertexPaintBrush.paint_vertices_in_radius(
		mesh, Vector3(-0.5, -0.5, -0.5), 0.01,
		Color.BLUE, VertexColorOperation.BlendMode.MIX,
		VertexColorOperation.CHANNEL_ALL, 1.0, {},
		VertexColorOperation.TargetChannel.CUSTOM2)
	assert_int(mesh.custom_channel_2.size()).is_equal(8)
	assert_color_equal(mesh.custom_channel_2[0], Color.BLUE)
	for i: int in range(1, mesh.custom_channel_2.size()):
		assert_color_equal(mesh.custom_channel_2[i], Color(0, 0, 0, 0))


func test_paint_custom3_does_not_affect_vertex_colors() -> void:
	var mesh := _make_unit_cube()
	GoBuildVertexPaintBrush.paint_vertices_in_radius(
		mesh, Vector3.ZERO, 10.0,
		Color.RED, VertexColorOperation.BlendMode.MIX,
		VertexColorOperation.CHANNEL_ALL, 1.0, {},
		VertexColorOperation.TargetChannel.CUSTOM3)
	for c: Color in mesh.vertex_colors:
		assert_color_equal(c, Color.WHITE)


func test_paint_custom_channel_add_blend() -> void:
	var mesh := _make_unit_cube()
	VertexColorOperation.fill_all(mesh, Color(0.5, 0.5, 0.5, 0.5),
		VertexColorOperation.BlendMode.MIX, VertexColorOperation.CHANNEL_ALL,
		VertexColorOperation.TargetChannel.CUSTOM0)
	GoBuildVertexPaintBrush.paint_vertices_in_radius(
		mesh, Vector3.ZERO, 10.0,
		Color(0.3, 0.3, 0.3, 0.3), VertexColorOperation.BlendMode.ADD,
		VertexColorOperation.CHANNEL_ALL, 1.0, {},
		VertexColorOperation.TargetChannel.CUSTOM0)
	for c: Color in mesh.custom_channel_0:
		assert_color_equal(c, Color(0.8, 0.8, 0.8, 0.8))


func test_paint_custom_channel_mask_g_only() -> void:
	var mesh := _make_unit_cube()
	VertexColorOperation.fill_all(mesh, Color(0, 0, 0, 0),
		VertexColorOperation.BlendMode.MIX, VertexColorOperation.CHANNEL_ALL,
		VertexColorOperation.TargetChannel.CUSTOM0)
	GoBuildVertexPaintBrush.paint_vertices_in_radius(
		mesh, Vector3.ZERO, 10.0,
		Color(1.0, 1.0, 1.0, 1.0), VertexColorOperation.BlendMode.MIX,
		VertexColorOperation.CHANNEL_G, 1.0, {},
		VertexColorOperation.TargetChannel.CUSTOM0)
	for c: Color in mesh.custom_channel_0:
		assert_float(c.g).is_equal_approx(1.0, 0.001)
		assert_float(c.r).is_equal_approx(0.0, 0.001)
		assert_float(c.b).is_equal_approx(0.0, 0.001)
		assert_float(c.a).is_equal_approx(0.0, 0.001)


func test_paint_custom_channel_strength_scales() -> void:
	var mesh := _make_unit_cube()
	GoBuildVertexPaintBrush.paint_vertices_in_radius(
		mesh, Vector3.ZERO, 10.0,
		Color.GREEN, VertexColorOperation.BlendMode.MIX,
		VertexColorOperation.CHANNEL_ALL, 0.5, {},
		VertexColorOperation.TargetChannel.CUSTOM0)
	for c: Color in mesh.custom_channel_0:
		assert_color_equal(c, Color(0.0, 0.5, 0.0, 0.5))


func test_paint_custom_channel_painted_dict_tracks_originals() -> void:
	var mesh := _make_unit_cube()
	VertexColorOperation.fill_all(mesh, Color(0.4, 0.4, 0.4, 0.4),
		VertexColorOperation.BlendMode.MIX, VertexColorOperation.CHANNEL_ALL,
		VertexColorOperation.TargetChannel.CUSTOM0)
	var painted: Dictionary = {}
	GoBuildVertexPaintBrush.paint_vertices_in_radius(
		mesh, Vector3.ZERO, 10.0,
		Color.RED, VertexColorOperation.BlendMode.MIX,
		VertexColorOperation.CHANNEL_ALL, 1.0, painted,
		VertexColorOperation.TargetChannel.CUSTOM0)
	assert_int(painted.size()).is_equal(8)
	for vi: int in painted:
		assert_color_equal(painted[vi], Color(0.4, 0.4, 0.4, 0.4))


func test_paint_color_target_default_is_vertex_colors() -> void:
	var mesh := _make_unit_cube()
	GoBuildVertexPaintBrush.paint_vertices_in_radius(
		mesh, Vector3.ZERO, 10.0,
		Color.RED, VertexColorOperation.BlendMode.MIX,
		VertexColorOperation.CHANNEL_ALL, 1.0, {},
		VertexColorOperation.TargetChannel.COLOR)
	for c: Color in mesh.vertex_colors:
		assert_color_equal(c, Color.RED)