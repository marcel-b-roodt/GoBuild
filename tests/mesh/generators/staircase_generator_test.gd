## StaircaseGenerator unit tests.
##
## Face order reference (from StaircaseGenerator):
##   2*i           = tread[i]   (normal +Y)
##   2*i + 1       = riser[i]   (normal -Z)
##   2*steps       = left side  (concave n-gon, normal -X)
##   2*steps + 1   = right side (concave n-gon, normal +X)
##   2*steps + 2   = bottom     (normal -Y)
##   2*steps + 3   = back       (normal +Z)
##
## Total face count: 2*steps + 4
## Regression baselines (user-dumped topology, 4 steps, 1.0/0.25/0.3):
##   20 vertices, 30 edges, 12 faces, 0 boundary edges.
extends GdUnitTestSuite

# Self-preloads — dependency order.
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _STAIR_SCRIPT := preload("res://addons/go_build/mesh/generators/staircase_generator.gd")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _normal(mesh: GoBuildMesh, face_idx: int) -> Vector3:
	return mesh.compute_face_normal(mesh.faces[face_idx])


static func _face_count(steps: int) -> int:
	return 2 * steps + 4


func _count_boundary_edges(mesh: GoBuildMesh) -> int:
	var b := 0
	for e in mesh.edges:
		if (e as GoBuildEdge).face_indices.size() != 2:
			b += 1
	return b


# ---------------------------------------------------------------------------
# Face counts
# ---------------------------------------------------------------------------

func test_staircase_face_count_default() -> void:
	assert_int(StaircaseGenerator.generate().faces.size()).is_equal(_face_count(4))


func test_staircase_face_count_one_step() -> void:
	assert_int(StaircaseGenerator.generate(1).faces.size()).is_equal(_face_count(1))


func test_staircase_face_count_formula() -> void:
	for n in [1, 2, 3, 8]:
		assert_int(StaircaseGenerator.generate(n).faces.size()).is_equal(_face_count(n))


func test_staircase_regression_topology_counts() -> void:
	# User-dumped baseline before the n-gon rewrite: 38/72/36 (subdivided).
	# After the merge: 20 vertices, 30 edges, 12 faces, closed manifold.
	var mesh := StaircaseGenerator.generate(4, 1.0, 0.25, 0.3)
	mesh.rebuild_edges()
	assert_int(mesh.vertices.size()).is_equal(20)
	assert_int(mesh.edges.size()).is_equal(30)
	assert_int(mesh.faces.size()).is_equal(12)
	assert_int(_count_boundary_edges(mesh)).is_equal(0)


# ---------------------------------------------------------------------------
# Tread and riser normals
# ---------------------------------------------------------------------------

func test_staircase_all_tread_normals_are_y_plus() -> void:
	var steps := 4
	var mesh := StaircaseGenerator.generate(steps)
	for i in range(steps):
		assert_float(_normal(mesh, i * 2).dot(Vector3.UP)).is_greater_equal(0.999)


func test_staircase_all_riser_normals_are_z_minus() -> void:
	var steps := 4
	var mesh := StaircaseGenerator.generate(steps)
	for i in range(steps):
		assert_float(_normal(mesh, i * 2 + 1).dot(Vector3(0.0, 0.0, -1.0))).is_greater_equal(0.999)


# ---------------------------------------------------------------------------
# Side / bottom / back normals
# ---------------------------------------------------------------------------

func test_staircase_left_side_normal_is_x_minus() -> void:
	var mesh := StaircaseGenerator.generate(4)
	assert_float(_normal(mesh, 8).dot(Vector3.LEFT)).is_greater_equal(0.999)


func test_staircase_right_side_normal_is_x_plus() -> void:
	var mesh := StaircaseGenerator.generate(4)
	assert_float(_normal(mesh, 9).dot(Vector3.RIGHT)).is_greater_equal(0.999)


func test_staircase_bottom_normal_is_y_minus() -> void:
	var mesh := StaircaseGenerator.generate(4)
	assert_float(_normal(mesh, 10).dot(Vector3.DOWN)).is_greater_equal(0.999)


func test_staircase_back_normal_is_z_plus() -> void:
	var mesh := StaircaseGenerator.generate(4)
	assert_float(_normal(mesh, 11).dot(Vector3(0.0, 0.0, 1.0))).is_greater_equal(0.999)


# ---------------------------------------------------------------------------
# Side walls are single n-gons covering the full profile
# ---------------------------------------------------------------------------

func test_staircase_side_walls_are_single_ngons() -> void:
	var mesh := StaircaseGenerator.generate(4)
	var left: GoBuildFace = mesh.faces[8]
	var right: GoBuildFace = mesh.faces[9]
	# 4 steps → 2*steps + 2 profile corners (front-bottom, back-bottom,
	# back-top, per-step riser/tread corners) → 10 verts per side.
	assert_int(left.vertex_indices.size()).is_equal(2 * 4 + 2)
	assert_int(right.vertex_indices.size()).is_equal(2 * 4 + 2)


func test_staircase_side_wall_vertices_on_correct_axis() -> void:
	var mesh := StaircaseGenerator.generate(4)
	for vi in mesh.faces[8].vertex_indices:
		assert_float((mesh.vertices[vi] as Vector3).x).is_equal_approx(-0.5, 0.001)
	for vi in mesh.faces[9].vertex_indices:
		assert_float((mesh.vertices[vi] as Vector3).x).is_equal_approx(0.5, 0.001)


func test_staircase_side_walls_share_edges_with_steps() -> void:
	# Every tread/riser edge on the side planes must be shared with the
	# side n-gon (no T-junctions along the profile).
	var mesh := StaircaseGenerator.generate(4, 1.0, 0.25, 0.3)
	mesh.rebuild_edges()
	var left_fi := 8
	var right_fi := 9
	var shared := 0
	for e in mesh.edges:
		var ed := e as GoBuildEdge
		if ed.face_indices.has(left_fi) or ed.face_indices.has(right_fi):
			shared += 1
	# 10 side vertices each → 8 profile edges (2 shared with treads/risers
	# at each riser corner) + 1 bottom edge + 1 back vertical edge = 10
	# edges per side, 20 total.
	assert_int(shared).is_equal(20)


# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------

func test_staircase_origin_at_bottom_front_corner() -> void:
	var mesh := StaircaseGenerator.generate(4)
	for v in mesh.vertices:
		assert_float((v as Vector3).y).is_greater_equal(-0.001)
		assert_float((v as Vector3).z).is_greater_equal(-0.001)


func test_staircase_respects_width() -> void:
	var mesh := StaircaseGenerator.generate(2, 3.0)
	var max_x := 0.0
	for v in mesh.vertices:
		max_x = maxf(max_x, absf((v as Vector3).x))
	assert_float(max_x).is_equal_approx(1.5, 0.001)


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
# Manifold + bake
# ---------------------------------------------------------------------------

func test_staircase_all_edges_are_manifold() -> void:
	var steps := 4
	var mesh := StaircaseGenerator.generate(steps)
	mesh.rebuild_edges()
	for edge_idx in range(mesh.edges.size()):
		var ed: GoBuildEdge = mesh.edges[edge_idx]
		assert_int(ed.face_indices.size()).is_equal(2)


func test_staircase_bake_returns_one_surface() -> void:
	assert_int(StaircaseGenerator.generate().bake().get_surface_count()).is_equal(1)


# ---------------------------------------------------------------------------
# Flip
# ---------------------------------------------------------------------------

func test_staircase_flipped_preserves_topology() -> void:
	var mesh := StaircaseGenerator.generate(4, 1.0, 0.25, 0.3, 0, true)
	mesh.rebuild_edges()
	assert_int(mesh.vertices.size()).is_equal(20)
	assert_int(mesh.edges.size()).is_equal(30)
	assert_int(mesh.faces.size()).is_equal(12)
	assert_int(_count_boundary_edges(mesh)).is_equal(0)


func test_staircase_flipped_riser_normals_are_z_plus() -> void:
	# Flipped ascent runs -Z: risers face +Z.
	var mesh := StaircaseGenerator.generate(4, 1.0, 0.25, 0.3, 0, true)
	for i in range(4):
		assert_float(_normal(mesh, i * 2 + 1).dot(Vector3(0.0, 0.0, 1.0))).is_greater_equal(0.999)


func test_staircase_flipped_back_wall_at_z_zero() -> void:
	# The back wall (ascent end) sits at z=0 when flipped; its outward
	# normal points -Z. All verts stay within [0, total_depth].
	var mesh := StaircaseGenerator.generate(4, 1.0, 0.25, 0.3, 0, true)
	for v in mesh.vertices:
		assert_float((v as Vector3).z).is_greater_equal(-0.001)
		assert_float((v as Vector3).z).is_less_equal(1.201)
	assert_float(_normal(mesh, 11).dot(Vector3(0.0, 0.0, -1.0))).is_greater_equal(0.999)


func test_staircase_flip_round_trip_identity() -> void:
	# Sanity: flipped vs unflipped differ; unflipped generation is stable.
	var a := StaircaseGenerator.generate(4, 1.0, 0.25, 0.3, 0, false)
	var b := StaircaseGenerator.generate(4, 1.0, 0.25, 0.3, 0, true)
	var c := StaircaseGenerator.generate(4, 1.0, 0.25, 0.3, 0, false)
	var differs := false
	for i: int in a.vertices.size():
		if not (a.vertices[i] as Vector3).is_equal_approx(b.vertices[i]):
			differs = true
			break
	assert_bool(differs).is_true()
	for i: int in a.vertices.size():
		assert_that((a.vertices[i] as Vector3).is_equal_approx(c.vertices[i])).is_true()


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