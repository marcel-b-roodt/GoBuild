## ArchGenerator unit tests.
##
## Face order reference (from ArchGenerator):
##   0  .. segments-1     outer faces  (normal radially outward)
##   s  .. 2s-1           inner faces  (normal radially inward)
##   2s .. 3s-1           front faces  (normal +Z)
##   3s .. 4s-1           back faces   (normal -Z)
##   where s = segments
extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _normal(mesh: GoBuildMesh, face_idx: int) -> Vector3:
	return mesh.compute_face_normal(mesh.faces[face_idx])


# ---------------------------------------------------------------------------
# Face counts
# ---------------------------------------------------------------------------

func test_arch_face_count_default() -> void:
	# 4 × segments = 4 × 8 = 32
	assert_int(ArchGenerator.generate().faces.size()).is_equal(32)


func test_arch_face_count_formula() -> void:
	# 4 * segments
	for s in [1, 2, 4, 12]:
		assert_int(ArchGenerator.generate(1.0, 0.2, 180.0, s).faces.size()).is_equal(4 * s)


# ---------------------------------------------------------------------------
# Vertex counts
# ---------------------------------------------------------------------------

func test_arch_vertex_count_default() -> void:
	# (segments+1) * 4 = 9 * 4 = 36
	assert_int(ArchGenerator.generate().vertices.size()).is_equal(36)


func test_arch_vertex_count_formula() -> void:
	# (segments+1) * 4
	for s in [1, 4, 8]:
		assert_int(ArchGenerator.generate(1.0, 0.2, 180.0, s).vertices.size()).is_equal((s + 1) * 4)


# ---------------------------------------------------------------------------
# Outer face normals — point radially away from origin
# ---------------------------------------------------------------------------

func test_arch_outer_face_normals_point_outward() -> void:
	var mesh := ArchGenerator.generate(1.0, 0.2, 180.0, 8)
	for i in range(8):
		var face := mesh.faces[i] as GoBuildFace
		var n := mesh.compute_face_normal(face)
		# Centroid of face vertices
		var c := Vector3.ZERO
		for idx in face.vertex_indices:
			c += mesh.vertices[idx]
		c /= float(face.vertex_indices.size())
		# Normal XY component should point in same direction as centroid XY
		var c_xy := Vector2(c.x, c.y).normalized()
		var n_xy := Vector2(n.x, n.y)
		assert_float(n_xy.dot(c_xy)).is_greater(0.5)


# ---------------------------------------------------------------------------
# Inner face normals — point radially toward origin
# ---------------------------------------------------------------------------

func test_arch_inner_face_normals_point_inward() -> void:
	var segments := 8
	var mesh := ArchGenerator.generate(1.0, 0.2, 180.0, segments)
	for i in range(segments):
		var face := mesh.faces[segments + i] as GoBuildFace
		var n := mesh.compute_face_normal(face)
		var c := Vector3.ZERO
		for idx in face.vertex_indices:
			c += mesh.vertices[idx]
		c /= float(face.vertex_indices.size())
		# Normal XY component should point OPPOSITE to centroid XY (toward hollow)
		var c_xy := Vector2(c.x, c.y).normalized()
		var n_xy := Vector2(n.x, n.y)
		assert_float(n_xy.dot(c_xy)).is_less(-0.5)


# ---------------------------------------------------------------------------
# Front face normals (+Z)
# ---------------------------------------------------------------------------

func test_arch_front_face_normals_are_z_plus() -> void:
	var segments := 8
	var mesh := ArchGenerator.generate(1.0, 0.2, 180.0, segments)
	for i in range(segments):
		var n := _normal(mesh, 2 * segments + i)
		# Explicit (0,0,1) — avoids FORWARD/BACK constant ambiguity
		assert_float(n.dot(Vector3(0.0, 0.0, 1.0))).is_greater_equal(0.999)


# ---------------------------------------------------------------------------
# Back face normals (-Z)
# ---------------------------------------------------------------------------

func test_arch_back_face_normals_are_z_minus() -> void:
	var segments := 8
	var mesh := ArchGenerator.generate(1.0, 0.2, 180.0, segments)
	for i in range(segments):
		var n := _normal(mesh, 3 * segments + i)
		assert_float(n.dot(Vector3(0.0, 0.0, -1.0))).is_greater_equal(0.999)


# ---------------------------------------------------------------------------
# Geometry — vertices at correct radii and depth
# ---------------------------------------------------------------------------

func test_arch_vertices_at_outer_or_inner_radius() -> void:
	var outer_r := 1.0
	var th := 0.25
	var inner_r := outer_r - th
	var mesh := ArchGenerator.generate(outer_r, th, 180.0, 8)
	for v in mesh.vertices:
		var xz := Vector2((v as Vector3).x, (v as Vector3).y)
		var r := xz.length()
		var on_outer := absf(r - outer_r) < 0.001
		var on_inner := absf(r - inner_r) < 0.001
		assert_bool(on_outer or on_inner).is_true()


func test_arch_vertices_within_depth() -> void:
	var depth := 0.4
	var hd := depth * 0.5
	var mesh := ArchGenerator.generate(1.0, 0.2, 180.0, 8, depth)
	for v in mesh.vertices:
		assert_float(absf((v as Vector3).z)).is_less_equal(hd + 0.001)


func test_arch_respects_outer_radius() -> void:
	var mesh := ArchGenerator.generate(2.0, 0.3, 180.0, 8)
	var max_r := 0.0
	for v in mesh.vertices:
		var r := Vector2((v as Vector3).x, (v as Vector3).y).length()
		max_r = maxf(max_r, r)
	assert_float(max_r).is_equal_approx(2.0, 0.001)


func test_arch_full_circle_spans_360_degrees() -> void:
	# A 360-degree arch should have start and end vertices coinciding
	var mesh := ArchGenerator.generate(1.0, 0.2, 360.0, 8)
	assert_int(mesh.faces.size()).is_equal(4 * 8)


# ---------------------------------------------------------------------------
# UVs
# ---------------------------------------------------------------------------

func test_arch_all_uvs_in_unit_range() -> void:
	var mesh := ArchGenerator.generate()
	for face in mesh.faces:
		for uv in (face as GoBuildFace).uvs:
			assert_float(uv.x).is_greater_equal(0.0)
			assert_float(uv.x).is_less_equal(1.0 + 0.001)
			assert_float(uv.y).is_greater_equal(0.0)
			assert_float(uv.y).is_less_equal(1.0 + 0.001)


# ---------------------------------------------------------------------------
# Bake
# ---------------------------------------------------------------------------

func test_arch_bake_returns_one_surface() -> void:
	assert_int(ArchGenerator.generate().bake().get_surface_count()).is_equal(1)


