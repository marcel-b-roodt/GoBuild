## CylinderGenerator unit tests.
extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Face counts
# ---------------------------------------------------------------------------

func test_cylinder_lateral_face_count() -> void:
	# sides=8, no caps → 8 lateral quads
	assert_int(CylinderGenerator.generate(0.5, 1.0, 8, false, false).faces.size()).is_equal(8)


func test_cylinder_with_caps_face_count() -> void:
	# sides=8, both caps → 8 lateral + 8 bottom + 8 top = 24
	assert_int(CylinderGenerator.generate(0.5, 1.0, 8, true, true).faces.size()).is_equal(24)


func test_cylinder_top_cap_only_face_count() -> void:
	# sides=6, top only → 6 lateral + 6 top = 12
	assert_int(CylinderGenerator.generate(0.5, 1.0, 6, true, false).faces.size()).is_equal(12)


func test_cylinder_bottom_cap_only_face_count() -> void:
	# sides=6, bottom only → 6 lateral + 6 bottom = 12
	assert_int(CylinderGenerator.generate(0.5, 1.0, 6, false, true).faces.size()).is_equal(12)


# ---------------------------------------------------------------------------
# Vertex counts
# ---------------------------------------------------------------------------

func test_cylinder_vertex_count_no_caps() -> void:
	# 2 rings × sides = 2×8 = 16
	assert_int(CylinderGenerator.generate(0.5, 1.0, 8, false, false).vertices.size()).is_equal(16)


func test_cylinder_vertex_count_with_caps() -> void:
	# 2 rings × 8 + 1 bottom centre + 1 top centre = 18
	assert_int(CylinderGenerator.generate(0.5, 1.0, 8, true, true).vertices.size()).is_equal(18)


# ---------------------------------------------------------------------------
# Normals — lateral faces should point radially outward
# ---------------------------------------------------------------------------

func test_cylinder_lateral_face_normals_point_outward() -> void:
	var mesh := CylinderGenerator.generate(0.5, 1.0, 8, false, false)
	for i in range(8):
		var n := mesh.compute_face_normal(mesh.faces[i])
		# Y component of lateral normals should be near zero
		assert_float(absf(n.y)).is_less_equal(0.1)
		# XZ magnitude should be near 1 (pointing radially)
		assert_float(Vector2(n.x, n.z).length()).is_greater_equal(0.9)


func test_cylinder_top_cap_normal_is_y_plus() -> void:
	var mesh := CylinderGenerator.generate(0.5, 1.0, 8, true, false)
	# Top cap faces start at index 8 (after 8 lateral faces)
	var n := mesh.compute_face_normal(mesh.faces[8])
	assert_float(n.dot(Vector3.UP)).is_greater_equal(0.9)


func test_cylinder_bottom_cap_normal_is_y_minus() -> void:
	var mesh := CylinderGenerator.generate(0.5, 1.0, 8, false, true)
	# Bottom cap faces start at index 8
	var n := mesh.compute_face_normal(mesh.faces[8])
	assert_float(n.dot(Vector3.DOWN)).is_greater_equal(0.9)


# ---------------------------------------------------------------------------
# Dimensions
# ---------------------------------------------------------------------------

func test_cylinder_respects_radius() -> void:
	var mesh := CylinderGenerator.generate(2.0, 1.0, 16, false, false)
	for v in mesh.vertices:
		var xz := Vector2((v as Vector3).x, (v as Vector3).z)
		assert_float(xz.length()).is_equal_approx(2.0, 0.001)


func test_cylinder_respects_height() -> void:
	var mesh := CylinderGenerator.generate(0.5, 4.0, 8, false, false)
	var max_y := 0.0
	for v in mesh.vertices:
		max_y = maxf(max_y, absf((v as Vector3).y))
	assert_float(max_y).is_equal_approx(2.0, 0.001)  # half of 4


func test_cylinder_is_centred_at_origin() -> void:
	var mesh := CylinderGenerator.generate(0.5, 1.0, 8, false, false)
	var centroid := Vector3.ZERO
	for v in mesh.vertices:
		centroid += v
	centroid /= float(mesh.vertices.size())
	assert_float(centroid.length()).is_equal_approx(0.0, 0.01)


# ---------------------------------------------------------------------------
# UVs
# ---------------------------------------------------------------------------

func test_cylinder_lateral_uvs_in_unit_range() -> void:
	var mesh := CylinderGenerator.generate(0.5, 1.0, 8, false, false)
	for face in mesh.faces:
		for uv in (face as GoBuildFace).uvs:
			assert_float(uv.x).is_greater_equal(0.0)
			assert_float(uv.x).is_less_equal(1.0 + 0.001)
			assert_float(uv.y).is_greater_equal(0.0)
			assert_float(uv.y).is_less_equal(1.0)


# ---------------------------------------------------------------------------
# Bake
# ---------------------------------------------------------------------------

func test_cylinder_bake_returns_one_surface() -> void:
	assert_int(CylinderGenerator.generate().bake().get_surface_count()).is_equal(1)

