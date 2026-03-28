## ConeGenerator unit tests.
extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Face counts
# ---------------------------------------------------------------------------

func test_cone_lateral_face_count() -> void:
	# sides=6, no cap → 6 lateral triangles
	assert_int(ConeGenerator.generate(0.5, 1.0, 6, false).faces.size()).is_equal(6)


func test_cone_with_cap_face_count() -> void:
	# sides=8, with cap → 8 lateral + 8 cap = 16
	assert_int(ConeGenerator.generate(0.5, 1.0, 8, true).faces.size()).is_equal(16)


# ---------------------------------------------------------------------------
# Vertex counts
# ---------------------------------------------------------------------------

func test_cone_vertex_count_no_cap() -> void:
	# sides base ring + 1 apex = sides + 1
	assert_int(ConeGenerator.generate(0.5, 1.0, 8, false).vertices.size()).is_equal(9)


func test_cone_vertex_count_with_cap() -> void:
	# sides ring + 1 apex + 1 cap centre = sides + 2
	assert_int(ConeGenerator.generate(0.5, 1.0, 8, true).vertices.size()).is_equal(10)


# ---------------------------------------------------------------------------
# Normals
# ---------------------------------------------------------------------------

func test_cone_lateral_normals_have_upward_component() -> void:
	# Lateral face normals tilt outward and upward (away from axis, toward apex)
	var mesh := ConeGenerator.generate(0.5, 1.0, 8, false)
	for face in mesh.faces:
		var n := mesh.compute_face_normal(face as GoBuildFace)
		assert_float(Vector2(n.x, n.z).length()).is_greater(0.3)


func test_cone_bottom_cap_normal_is_y_minus() -> void:
	var mesh := ConeGenerator.generate(0.5, 1.0, 8, true)
	# Cap faces start at index 8
	var n := mesh.compute_face_normal(mesh.faces[8])
	assert_float(n.dot(Vector3.DOWN)).is_greater_equal(0.9)


# ---------------------------------------------------------------------------
# Apex position
# ---------------------------------------------------------------------------

func test_cone_apex_is_at_top() -> void:
	var mesh := ConeGenerator.generate(0.5, 2.0, 8, false)
	# Apex index = sides (= 8)
	var apex: Vector3 = mesh.vertices[8]
	assert_float(apex.y).is_equal_approx(1.0, 0.001)   # hh = height/2 = 1
	assert_float(absf(apex.x)).is_equal_approx(0.0, 0.001)
	assert_float(absf(apex.z)).is_equal_approx(0.0, 0.001)


# ---------------------------------------------------------------------------
# Dimensions
# ---------------------------------------------------------------------------

func test_cone_respects_base_radius() -> void:
	var mesh := ConeGenerator.generate(3.0, 1.0, 16, false)
	# All base ring verts (indices 0..15) should be at radius 3
	for i in range(16):
		var v: Vector3 = mesh.vertices[i]
		assert_float(Vector2(v.x, v.z).length()).is_equal_approx(3.0, 0.001)


func test_cone_respects_height() -> void:
	var mesh := ConeGenerator.generate(0.5, 6.0, 8, false)
	var max_y := 0.0
	var min_y := 0.0
	for v in mesh.vertices:
		max_y = maxf(max_y, (v as Vector3).y)
		min_y = minf(min_y, (v as Vector3).y)
	assert_float(max_y).is_equal_approx(3.0, 0.001)   # hh = 3
	assert_float(min_y).is_equal_approx(-3.0, 0.001)


# ---------------------------------------------------------------------------
# Bake
# ---------------------------------------------------------------------------

func test_cone_bake_returns_one_surface() -> void:
	assert_int(ConeGenerator.generate().bake().get_surface_count()).is_equal(1)

