## TorusGenerator unit tests.
extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Face counts
# ---------------------------------------------------------------------------

func test_torus_face_count() -> void:
	# rings × tube_segments quads
	assert_int(TorusGenerator.generate(0.5, 0.2, 8, 6).faces.size()).is_equal(48)


func test_torus_default_face_count() -> void:
	# default rings=24, tube_segments=12 → 288 faces
	assert_int(TorusGenerator.generate().faces.size()).is_equal(288)


# ---------------------------------------------------------------------------
# Vertex counts
# ---------------------------------------------------------------------------

func test_torus_vertex_count() -> void:
	# After weld: rings × tube_segments (seam rows/cols collapsed)
	# rings=8, tube_segments=6: 8 × 6 = 48  (was 9 × 7 = 63 raw)
	assert_int(TorusGenerator.generate(0.5, 0.2, 8, 6).vertices.size()).is_equal(48)


# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------

func test_torus_vertices_at_correct_major_radius() -> void:
	# Each vertex is at distance between (major - minor) and (major + minor) from origin in XZ
	var rmaj := 1.0
	var rmin := 0.3
	var mesh := TorusGenerator.generate(rmaj, rmin, 12, 8)
	for v in mesh.vertices:
		var xz_dist: float = Vector2((v as Vector3).x, (v as Vector3).z).length()
		assert_float(xz_dist).is_greater_equal(rmaj - rmin - 0.001)
		assert_float(xz_dist).is_less_equal(rmaj + rmin + 0.001)


func test_torus_lies_near_xz_plane() -> void:
	# Y extent should not exceed minor radius
	var rmin := 0.25
	var mesh := TorusGenerator.generate(0.6, rmin, 12, 8)
	for v in mesh.vertices:
		assert_float(absf((v as Vector3).y)).is_less_equal(rmin + 0.001)


func test_torus_is_centred_at_origin() -> void:
	var mesh := TorusGenerator.generate(0.5, 0.2, 12, 8)
	var centroid := Vector3.ZERO
	for v in mesh.vertices:
		centroid += v
	centroid /= float(mesh.vertices.size())
	assert_float(centroid.length()).is_equal_approx(0.0, 0.05)


# ---------------------------------------------------------------------------
# Normals — should point outward from the tube surface
# ---------------------------------------------------------------------------

func test_torus_face_normals_point_away_from_tube_centre() -> void:
	# Regression guard for CCW winding: face.vertex_indices must be wound
	# CCW from outside so compute_face_normal() returns an outward normal.
	# The old buggy order [i00,i10,i11,i01] gave dot ≈ -0.976 (inward).
	# The correct order [i00,i01,i11,i10] gives dot ≈ +0.976 (outward).
	var rmaj := 0.5
	var mesh := TorusGenerator.generate(rmaj, 0.2, 8, 6)
	for face in mesh.faces:
		var f := face as GoBuildFace
		var n := mesh.compute_face_normal(f)
		# Centroid of face
		var c := Vector3.ZERO
		for idx in f.vertex_indices:
			c += mesh.vertices[idx]
		c /= float(f.vertex_indices.size())
		# Nearest point on major ring to centroid
		var c_xz := Vector2(c.x, c.z)
		var ring_pt: Vector3
		if c_xz.length() > 0.0001:
			var ring_dir := c_xz.normalized()
			ring_pt = Vector3(ring_dir.x * rmaj, 0.0, ring_dir.y * rmaj)
		else:
			ring_pt = Vector3(rmaj, 0.0, 0.0)
		var outward := (c - ring_pt).normalized()
		# Must be clearly outward (> 0.5), not merely > 0.
		assert_float(n.dot(outward)).is_greater(0.5)


# ---------------------------------------------------------------------------
# UVs
# ---------------------------------------------------------------------------

func test_torus_uvs_in_unit_range() -> void:
	var mesh := TorusGenerator.generate(0.5, 0.2, 8, 6)
	for face in mesh.faces:
		for uv in (face as GoBuildFace).uvs:
			assert_float(uv.x).is_greater_equal(0.0)
			assert_float(uv.x).is_less_equal(1.0 + 0.001)
			assert_float(uv.y).is_greater_equal(0.0)
			assert_float(uv.y).is_less_equal(1.0 + 0.001)


# ---------------------------------------------------------------------------
# Bake
# ---------------------------------------------------------------------------

func test_torus_bake_returns_one_surface() -> void:
	assert_int(TorusGenerator.generate().bake().get_surface_count()).is_equal(1)

