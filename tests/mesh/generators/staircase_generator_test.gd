## StaircaseGenerator unit tests.
##
## Face order reference (from StaircaseGenerator):
##   2*i       = tread[i]   (normal +Y)
##   2*i + 1   = riser[i]   (normal -Z)
##   2*steps   = left wall  (normal -X)
##   2*steps+1 = right wall (normal +X)
##   2*steps+2 = bottom     (normal -Y)
##   2*steps+3 = back       (normal +Z)
extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _normal(mesh: GoBuildMesh, face_idx: int) -> Vector3:
	return mesh.compute_face_normal(mesh.faces[face_idx])


# ---------------------------------------------------------------------------
# Face counts
# ---------------------------------------------------------------------------

func test_staircase_face_count_default() -> void:
	# steps=4: 4 treads + 4 risers + left + right + bottom + back = 12
	assert_int(StaircaseGenerator.generate().faces.size()).is_equal(12)


func test_staircase_face_count_one_step() -> void:
	# steps=1: 1 tread + 1 riser + 4 enclosing faces = 6
	assert_int(StaircaseGenerator.generate(1).faces.size()).is_equal(6)


func test_staircase_face_count_formula() -> void:
	# 2*steps + 4
	for n in [1, 2, 3, 8]:
		assert_int(StaircaseGenerator.generate(n).faces.size()).is_equal(2 * n + 4)


# ---------------------------------------------------------------------------
# Vertex counts
# ---------------------------------------------------------------------------

func test_staircase_vertex_count_default() -> void:
	# 12*steps + 12 = 12*4 + 12 = 60
	assert_int(StaircaseGenerator.generate().vertices.size()).is_equal(60)


func test_staircase_vertex_count_one_step() -> void:
	# 12*1 + 12 = 24
	assert_int(StaircaseGenerator.generate(1).vertices.size()).is_equal(24)


# ---------------------------------------------------------------------------
# Tread normals (+Y)
# ---------------------------------------------------------------------------

func test_staircase_first_tread_normal_is_y_plus() -> void:
	var mesh := StaircaseGenerator.generate(2)
	assert_float(_normal(mesh, 0).dot(Vector3.UP)).is_greater_equal(0.999)


func test_staircase_all_tread_normals_are_y_plus() -> void:
	var steps := 4
	var mesh := StaircaseGenerator.generate(steps)
	for i in range(steps):
		assert_float(_normal(mesh, i * 2).dot(Vector3.UP)).is_greater_equal(0.999)


# ---------------------------------------------------------------------------
# Riser normals (-Z)
# ---------------------------------------------------------------------------

func test_staircase_first_riser_normal_is_z_minus() -> void:
	var mesh := StaircaseGenerator.generate(2)
	# Explicit (0,0,-1) to avoid FORWARD/BACK constant ambiguity
	assert_float(_normal(mesh, 1).dot(Vector3(0.0, 0.0, -1.0))).is_greater_equal(0.999)


func test_staircase_all_riser_normals_are_z_minus() -> void:
	var steps := 4
	var mesh := StaircaseGenerator.generate(steps)
	for i in range(steps):
		assert_float(_normal(mesh, i * 2 + 1).dot(Vector3(0.0, 0.0, -1.0))).is_greater_equal(0.999)


# ---------------------------------------------------------------------------
# Side wall normals
# ---------------------------------------------------------------------------

func test_staircase_left_wall_normal_is_x_minus() -> void:
	var steps := 3
	var mesh := StaircaseGenerator.generate(steps)
	assert_float(_normal(mesh, 2 * steps).dot(Vector3.LEFT)).is_greater_equal(0.999)


func test_staircase_right_wall_normal_is_x_plus() -> void:
	var steps := 3
	var mesh := StaircaseGenerator.generate(steps)
	assert_float(_normal(mesh, 2 * steps + 1).dot(Vector3.RIGHT)).is_greater_equal(0.999)


# ---------------------------------------------------------------------------
# Bottom and back normals
# ---------------------------------------------------------------------------

func test_staircase_bottom_normal_is_y_minus() -> void:
	var steps := 3
	var mesh := StaircaseGenerator.generate(steps)
	assert_float(_normal(mesh, 2 * steps + 2).dot(Vector3.DOWN)).is_greater_equal(0.999)


func test_staircase_back_normal_is_z_plus() -> void:
	var steps := 3
	var mesh := StaircaseGenerator.generate(steps)
	assert_float(_normal(mesh, 2 * steps + 3).dot(Vector3(0.0, 0.0, 1.0))).is_greater_equal(0.999)


# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------

func test_staircase_origin_at_bottom_front_corner() -> void:
	# All vertices should have y >= 0 and z >= 0
	var mesh := StaircaseGenerator.generate(4)
	for v in mesh.vertices:
		assert_float((v as Vector3).y).is_greater_equal(-0.001)
		assert_float((v as Vector3).z).is_greater_equal(-0.001)


func test_staircase_respects_width() -> void:
	var mesh := StaircaseGenerator.generate(2, 3.0)
	var max_x := 0.0
	for v in mesh.vertices:
		max_x = maxf(max_x, absf((v as Vector3).x))
	assert_float(max_x).is_equal_approx(1.5, 0.001)  # half of 3


func test_staircase_respects_total_height() -> void:
	var steps := 3
	var sh := 0.5
	var mesh := StaircaseGenerator.generate(steps, 1.0, sh)
	var max_y := 0.0
	for v in mesh.vertices:
		max_y = maxf(max_y, (v as Vector3).y)
	assert_float(max_y).is_equal_approx(float(steps) * sh, 0.001)


func test_staircase_respects_total_depth() -> void:
	var steps := 3
	var sd := 0.4
	var mesh := StaircaseGenerator.generate(steps, 1.0, 0.25, sd)
	var max_z := 0.0
	for v in mesh.vertices:
		max_z = maxf(max_z, (v as Vector3).z)
	assert_float(max_z).is_equal_approx(float(steps) * sd, 0.001)


# ---------------------------------------------------------------------------
# Side wall polygon vertex counts
# ---------------------------------------------------------------------------

func test_staircase_side_wall_vertex_count() -> void:
	# Each side wall has 2*steps + 2 vertices
	var steps := 3
	var mesh := StaircaseGenerator.generate(steps)
	var left  := mesh.faces[2 * steps]     as GoBuildFace
	var right := mesh.faces[2 * steps + 1] as GoBuildFace
	assert_int(left.vertex_indices.size()).is_equal(2 * steps + 2)
	assert_int(right.vertex_indices.size()).is_equal(2 * steps + 2)


# ---------------------------------------------------------------------------
# UVs
# ---------------------------------------------------------------------------

func test_staircase_all_uvs_in_unit_range() -> void:
	var mesh := StaircaseGenerator.generate()
	for face in mesh.faces:
		for uv in (face as GoBuildFace).uvs:
			assert_float(uv.x).is_greater_equal(0.0)
			assert_float(uv.x).is_less_equal(1.0 + 0.001)
			assert_float(uv.y).is_greater_equal(0.0)
			assert_float(uv.y).is_less_equal(1.0 + 0.001)


# ---------------------------------------------------------------------------
# Bake
# ---------------------------------------------------------------------------

func test_staircase_bake_returns_one_surface() -> void:
	assert_int(StaircaseGenerator.generate().bake().get_surface_count()).is_equal(1)

