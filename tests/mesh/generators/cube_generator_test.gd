## CubeGenerator unit tests.
extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _normal(mesh: GoBuildMesh, face_idx: int) -> Vector3:
	return mesh.compute_face_normal(mesh.faces[face_idx])


# ---------------------------------------------------------------------------
# Face and vertex counts
# ---------------------------------------------------------------------------

func test_cube_default_has_six_faces() -> void:
	assert_int(CubeGenerator.generate().faces.size()).is_equal(6)


func test_cube_vertex_count_no_subdivisions() -> void:
	# 8 unique corner positions after weld (was 24 raw = 6 faces × 4)
	assert_int(CubeGenerator.generate(1.0, 1.0, 1.0, 0).vertices.size()).is_equal(8)


func test_cube_face_count_subdivisions_1() -> void:
	# subdivisions=1 → steps=2 → 2×2=4 quads per face → 6×4=24
	assert_int(CubeGenerator.generate(1.0, 1.0, 1.0, 1).faces.size()).is_equal(24)


func test_cube_vertex_count_subdivisions_1() -> void:
	# After weld: 8 corners + 12 edge-midpoints + 6 face-centres = 26
	assert_int(CubeGenerator.generate(1.0, 1.0, 1.0, 1).vertices.size()).is_equal(26)


func test_cube_face_count_subdivisions_2() -> void:
	# subdivisions=2 → steps=3 → 3×3=9 quads per face → 6×9=54
	assert_int(CubeGenerator.generate(1.0, 1.0, 1.0, 2).faces.size()).is_equal(54)


# ---------------------------------------------------------------------------
# Face normals — outward directions
# ---------------------------------------------------------------------------

func test_cube_top_face_normal_is_y_plus() -> void:
	var mesh := CubeGenerator.generate()
	assert_float(_normal(mesh, 0).dot(Vector3.UP)).is_greater_equal(0.999)


func test_cube_bottom_face_normal_is_y_minus() -> void:
	var mesh := CubeGenerator.generate()
	assert_float(_normal(mesh, 1).dot(Vector3.DOWN)).is_greater_equal(0.999)


func test_cube_front_face_normal_is_z_plus() -> void:
	var mesh := CubeGenerator.generate()
	# Vector3.BACK = (0, 0, +1) in Godot 4.  Vector3.FORWARD = (0, 0, -1).
	assert_float(_normal(mesh, 2).dot(Vector3.BACK)).is_greater_equal(0.999)


func test_cube_back_face_normal_is_z_minus() -> void:
	var mesh := CubeGenerator.generate()
	# Vector3.FORWARD = (0, 0, -1) in Godot 4.  Vector3.BACK = (0, 0, +1).
	assert_float(_normal(mesh, 3).dot(Vector3.FORWARD)).is_greater_equal(0.999)


func test_cube_right_face_normal_is_x_plus() -> void:
	var mesh := CubeGenerator.generate()
	assert_float(_normal(mesh, 4).dot(Vector3.RIGHT)).is_greater_equal(0.999)


func test_cube_left_face_normal_is_x_minus() -> void:
	var mesh := CubeGenerator.generate()
	assert_float(_normal(mesh, 5).dot(Vector3.LEFT)).is_greater_equal(0.999)


# ---------------------------------------------------------------------------
# Normals are unit length
# ---------------------------------------------------------------------------

func test_cube_all_face_normals_are_unit_length() -> void:
	var mesh := CubeGenerator.generate()
	for i in mesh.faces.size():
		assert_float(_normal(mesh, i).length()).is_equal_approx(1.0, 0.001)


# ---------------------------------------------------------------------------
# Dimensions
# ---------------------------------------------------------------------------

func test_cube_respects_custom_dimensions() -> void:
	var mesh := CubeGenerator.generate(4.0, 2.0, 6.0, 0)
	var max_x := 0.0
	var max_y := 0.0
	var max_z := 0.0
	for v in mesh.vertices:
		max_x = maxf(max_x, absf(v.x))
		max_y = maxf(max_y, absf(v.y))
		max_z = maxf(max_z, absf(v.z))
	assert_float(max_x).is_equal_approx(2.0, 0.001)  # half of 4
	assert_float(max_y).is_equal_approx(1.0, 0.001)  # half of 2
	assert_float(max_z).is_equal_approx(3.0, 0.001)  # half of 6


func test_cube_is_centred_at_origin() -> void:
	var mesh := CubeGenerator.generate(2.0, 2.0, 2.0, 0)
	var centroid := Vector3.ZERO
	for v in mesh.vertices:
		centroid += v
	centroid /= float(mesh.vertices.size())
	assert_float(centroid.length()).is_equal_approx(0.0, 0.001)


# ---------------------------------------------------------------------------
# UVs
# ---------------------------------------------------------------------------

func test_cube_uvs_are_in_unit_range() -> void:
	var mesh := CubeGenerator.generate(1.0, 1.0, 1.0, 0)
	for face in mesh.faces:
		for uv in (face as GoBuildFace).uvs:
			assert_float(uv.x).is_greater_equal(0.0)
			assert_float(uv.x).is_less_equal(1.0)
			assert_float(uv.y).is_greater_equal(0.0)
			assert_float(uv.y).is_less_equal(1.0)


func test_cube_each_face_has_four_uvs() -> void:
	var mesh := CubeGenerator.generate()
	for face in mesh.faces:
		assert_int((face as GoBuildFace).uvs.size()).is_equal(4)


# ---------------------------------------------------------------------------
# Edges
# ---------------------------------------------------------------------------

func test_cube_edges_are_rebuilt_after_generate() -> void:
	var mesh := CubeGenerator.generate()
	assert_int(mesh.edges.size()).is_greater(0)


func test_cube_no_subdivisions_has_24_edges() -> void:
	# 6 separate quad faces, each with 4 boundary edges = 24
	assert_int(CubeGenerator.generate().edges.size()).is_equal(24)


# ---------------------------------------------------------------------------
# Bake
# ---------------------------------------------------------------------------

func test_cube_bake_returns_one_surface() -> void:
	var am: ArrayMesh = CubeGenerator.generate().bake()
	assert_int(am.get_surface_count()).is_equal(1)


func test_cube_bake_contains_correct_triangle_count() -> void:
	# 6 quads → 12 triangles → 36 vertices in the packed array
	var arrays: Array = CubeGenerator.generate().bake().surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert_int(verts.size()).is_equal(36)

