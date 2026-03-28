## SphereGenerator unit tests.
extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Face counts
# ---------------------------------------------------------------------------

func test_sphere_face_count() -> void:
	# rings=4, segments=8:
	# lateral: (rings-2) × segments = 2 × 8 = 16
	# south cap: segments = 8
	# north cap: segments = 8
	# total: 32
	assert_int(SphereGenerator.generate(0.5, 4, 8).faces.size()).is_equal(32)


func test_sphere_minimal_rings_face_count() -> void:
	# rings=2, segments=6: 0 lateral rings + 6 south + 6 north = 12
	assert_int(SphereGenerator.generate(0.5, 2, 6).faces.size()).is_equal(12)


# ---------------------------------------------------------------------------
# Vertex counts
# ---------------------------------------------------------------------------

func test_sphere_vertex_count() -> void:
	# (rings+1) × (segments+1) vertices
	# rings=4, segments=8: 5 × 9 = 45
	assert_int(SphereGenerator.generate(0.5, 4, 8).vertices.size()).is_equal(45)


# ---------------------------------------------------------------------------
# Geometry — all vertices on the sphere surface
# ---------------------------------------------------------------------------

func test_sphere_all_vertices_on_surface() -> void:
	var r := 2.0
	var mesh := SphereGenerator.generate(r, 8, 16)
	for v in mesh.vertices:
		assert_float((v as Vector3).length()).is_equal_approx(r, 0.001)


func test_sphere_is_centred_at_origin() -> void:
	var mesh := SphereGenerator.generate(1.0, 6, 12)
	var centroid := Vector3.ZERO
	for v in mesh.vertices:
		centroid += v
	centroid /= float(mesh.vertices.size())
	assert_float(centroid.length()).is_equal_approx(0.0, 0.05)


# ---------------------------------------------------------------------------
# Normals — face normals should point away from origin
# ---------------------------------------------------------------------------

func test_sphere_face_normals_point_outward() -> void:
	var mesh := SphereGenerator.generate(1.0, 6, 12)
	for face in mesh.faces:
		var f := face as GoBuildFace
		var n := mesh.compute_face_normal(f)
		# Centroid of face vertices
		var c := Vector3.ZERO
		for idx in f.vertex_indices:
			c += mesh.vertices[idx]
		c /= float(f.vertex_indices.size())
		# Normal should point in same general direction as the centroid vector
		assert_float(n.dot(c.normalized())).is_greater(0.0)


# ---------------------------------------------------------------------------
# UVs
# ---------------------------------------------------------------------------

func test_sphere_uvs_in_unit_range() -> void:
	var mesh := SphereGenerator.generate(1.0, 4, 8)
	for face in mesh.faces:
		for uv in (face as GoBuildFace).uvs:
			assert_float(uv.x).is_greater_equal(0.0)
			assert_float(uv.x).is_less_equal(1.0 + 0.001)
			assert_float(uv.y).is_greater_equal(0.0)
			assert_float(uv.y).is_less_equal(1.0 + 0.001)


# ---------------------------------------------------------------------------
# Bake
# ---------------------------------------------------------------------------

func test_sphere_bake_returns_one_surface() -> void:
	assert_int(SphereGenerator.generate().bake().get_surface_count()).is_equal(1)

