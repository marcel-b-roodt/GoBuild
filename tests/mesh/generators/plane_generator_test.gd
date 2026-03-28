## PlaneGenerator unit tests.
extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Face and vertex counts — no subdivisions
# ---------------------------------------------------------------------------

func test_plane_default_has_one_face() -> void:
	assert_int(PlaneGenerator.generate().faces.size()).is_equal(1)


func test_plane_vertex_count_no_subdivisions() -> void:
	# 1 quad → (1+1)² = 4 vertices
	assert_int(PlaneGenerator.generate(1.0, 1.0, 0, 0).vertices.size()).is_equal(4)


# ---------------------------------------------------------------------------
# Face and vertex counts — with subdivisions
# ---------------------------------------------------------------------------

func test_plane_face_count_with_x_subdivisions() -> void:
	# subdivisions_x=2 → steps_x=3, steps_z=1 → 3×1 = 3 faces
	assert_int(PlaneGenerator.generate(1.0, 1.0, 2, 0).faces.size()).is_equal(3)


func test_plane_face_count_with_z_subdivisions() -> void:
	# subdivisions_z=3 → steps_z=4, steps_x=1 → 1×4 = 4 faces
	assert_int(PlaneGenerator.generate(1.0, 1.0, 0, 3).faces.size()).is_equal(4)


func test_plane_face_count_with_both_subdivisions() -> void:
	# subdivisions_x=1, subdivisions_z=2 → steps 2×3 = 6 faces
	assert_int(PlaneGenerator.generate(1.0, 1.0, 1, 2).faces.size()).is_equal(6)


func test_plane_vertex_count_with_subdivisions() -> void:
	# subdivisions_x=1, subdivisions_z=2 → (2+1)×(3+1) = 3×4 = 12 vertices
	assert_int(PlaneGenerator.generate(1.0, 1.0, 1, 2).vertices.size()).is_equal(12)


# ---------------------------------------------------------------------------
# Normal direction
# ---------------------------------------------------------------------------

func test_plane_face_normal_is_y_plus() -> void:
	var mesh := PlaneGenerator.generate()
	var n := mesh.compute_face_normal(mesh.faces[0])
	assert_float(n.dot(Vector3.UP)).is_greater_equal(0.999)


func test_plane_normal_is_unit_length() -> void:
	var mesh := PlaneGenerator.generate()
	var n := mesh.compute_face_normal(mesh.faces[0])
	assert_float(n.length()).is_equal_approx(1.0, 0.001)


# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------

func test_plane_lies_flat_in_xz_plane() -> void:
	var mesh := PlaneGenerator.generate(2.0, 3.0, 0, 0)
	for v in mesh.vertices:
		assert_float(absf((v as Vector3).y)).is_equal_approx(0.0, 0.001)


func test_plane_respects_width_and_depth() -> void:
	var mesh := PlaneGenerator.generate(4.0, 6.0, 0, 0)
	var max_x := 0.0
	var max_z := 0.0
	for v in mesh.vertices:
		max_x = maxf(max_x, absf((v as Vector3).x))
		max_z = maxf(max_z, absf((v as Vector3).z))
	assert_float(max_x).is_equal_approx(2.0, 0.001)  # half of 4
	assert_float(max_z).is_equal_approx(3.0, 0.001)  # half of 6


func test_plane_is_centred_at_origin() -> void:
	var mesh := PlaneGenerator.generate(2.0, 2.0)
	var centroid := Vector3.ZERO
	for v in mesh.vertices:
		centroid += v
	centroid /= float(mesh.vertices.size())
	assert_float(centroid.length()).is_equal_approx(0.0, 0.001)


# ---------------------------------------------------------------------------
# UVs
# ---------------------------------------------------------------------------

func test_plane_uvs_are_in_unit_range() -> void:
	var mesh := PlaneGenerator.generate(1.0, 1.0, 1, 1)
	for face in mesh.faces:
		for uv in (face as GoBuildFace).uvs:
			assert_float(uv.x).is_greater_equal(0.0)
			assert_float(uv.x).is_less_equal(1.0)
			assert_float(uv.y).is_greater_equal(0.0)
			assert_float(uv.y).is_less_equal(1.0)


# ---------------------------------------------------------------------------
# Edges
# ---------------------------------------------------------------------------

func test_plane_edges_rebuilt_after_generate() -> void:
	var mesh := PlaneGenerator.generate()
	assert_int(mesh.edges.size()).is_greater(0)


func test_plane_no_subdivisions_has_four_boundary_edges() -> void:
	var mesh := PlaneGenerator.generate()
	assert_int(mesh.edges.size()).is_equal(4)
	for edge in mesh.edges:
		assert_bool((edge as GoBuildEdge).is_boundary()).is_true()


# ---------------------------------------------------------------------------
# Bake
# ---------------------------------------------------------------------------

func test_plane_bake_returns_one_surface() -> void:
	assert_int(PlaneGenerator.generate().bake().get_surface_count()).is_equal(1)


func test_plane_bake_single_quad_has_six_baked_vertices() -> void:
	# 1 quad → 2 triangles → 6 vertices in packed array
	var arrays: Array = PlaneGenerator.generate().bake().surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert_int(verts.size()).is_equal(6)

