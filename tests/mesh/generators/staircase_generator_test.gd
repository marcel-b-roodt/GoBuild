## StaircaseGenerator unit tests.
##
## Face order reference (from StaircaseGenerator):
##   2*i                            = tread[i]        (normal +Y)
##   2*i + 1                        = riser[i]        (normal -Z)
##   2*steps + r*n + c - r*(r-1)/2 = left cell(r,c)  (normal -X)
##   2*steps + n*(n+1)/2 + offset   = right cell(r,c) (normal +X)
##   2*steps + n*(n+1)              = bottom           (normal -Y)
##   2*steps + n*(n+1) + 1          = back             (normal +Z)
##
## Total face count: 2*steps + steps*(steps+1) + 2
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
	return 2 * steps + steps * (steps + 1) + 2


static func _left_cell_index(steps: int, r: int, c: int) -> int:
	# Left grid cells start at 2*steps, laid out row by row (c >= r).
	# Row r has (steps - r) cells. Offset = sum of (steps - row) for row < r + (c - r).
	return 2 * steps + r * steps - r * (r - 1) / 2 + (c - r)


static func _right_cell_index(steps: int, r: int, c: int) -> int:
	var n2: int = steps * (steps + 1) / 2
	return 2 * steps + n2 + r * steps - r * (r - 1) / 2 + (c - r)


# ---------------------------------------------------------------------------
# Face counts
# ---------------------------------------------------------------------------

func test_staircase_face_count_default() -> void:
	# steps=4: 8 treads/risers + 10 left cells + 10 right cells + bottom + back = 30
	assert_int(StaircaseGenerator.generate().faces.size()).is_equal(30)


func test_staircase_face_count_one_step() -> void:
	# steps=1: 1 tread + 1 riser + 1 left cell + 1 right cell + bottom + back = 6
	assert_int(StaircaseGenerator.generate(1).faces.size()).is_equal(6)


func test_staircase_face_count_formula() -> void:
	# 2*steps + steps*(steps+1) + 2
	for n in [1, 2, 3, 8]:
		assert_int(StaircaseGenerator.generate(n).faces.size()).is_equal(_face_count(n))


# ---------------------------------------------------------------------------
# Vertex counts
# ---------------------------------------------------------------------------

func test_staircase_vertex_count_default() -> void:
	# Weld merges coincident vertices; unique count well under raw vertex count.
	assert_int(StaircaseGenerator.generate().vertices.size()).is_less(120)


func test_staircase_vertex_count_one_step() -> void:
	# Weld merges coincident step corners; unique count < 24 raw.
	assert_int(StaircaseGenerator.generate(1).vertices.size()).is_less(24)


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
	assert_float(_normal(mesh, 1).dot(Vector3(0.0, 0.0, -1.0))).is_greater_equal(0.999)


func test_staircase_all_riser_normals_are_z_minus() -> void:
	var steps := 4
	var mesh := StaircaseGenerator.generate(steps)
	for i in range(steps):
		assert_float(_normal(mesh, i * 2 + 1).dot(Vector3(0.0, 0.0, -1.0))).is_greater_equal(0.999)


# ---------------------------------------------------------------------------
# Side wall normals
# ---------------------------------------------------------------------------

func test_staircase_left_grid_normals_are_x_minus() -> void:
	var steps := 3
	var mesh := StaircaseGenerator.generate(steps)
	for r in range(steps):
		for c in range(r, steps):
			var idx: int = _left_cell_index(steps, r, c)
			assert_float(_normal(mesh, idx).dot(Vector3.LEFT)).is_greater_equal(0.999)


func test_staircase_right_grid_normals_are_x_plus() -> void:
	var steps := 3
	var mesh := StaircaseGenerator.generate(steps)
	for r in range(steps):
		for c in range(r, steps):
			var idx: int = _right_cell_index(steps, r, c)
			assert_float(_normal(mesh, idx).dot(Vector3.RIGHT)).is_greater_equal(0.999)


# ---------------------------------------------------------------------------
# Bottom and back normals
# ---------------------------------------------------------------------------

func test_staircase_bottom_normal_is_y_minus() -> void:
	var steps := 3
	var mesh := StaircaseGenerator.generate(steps)
	var bottom_idx: int = 2 * steps + steps * (steps + 1)
	assert_float(_normal(mesh, bottom_idx).dot(Vector3.DOWN)).is_greater_equal(0.999)


func test_staircase_back_normal_is_z_plus() -> void:
	var steps := 3
	var mesh := StaircaseGenerator.generate(steps)
	var back_idx: int = 2 * steps + steps * (steps + 1) + 1
	assert_float(_normal(mesh, back_idx).dot(Vector3(0.0, 0.0, 1.0))).is_greater_equal(0.999)


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
# Side wall grid cells are quads
# ---------------------------------------------------------------------------

func test_staircase_side_wall_grid_cells_are_quads() -> void:
	var steps := 3
	var mesh := StaircaseGenerator.generate(steps)
	var n2: int = steps * (steps + 1) / 2
	for i in range(n2):
		var left := mesh.faces[2 * steps + i] as GoBuildFace
		var right := mesh.faces[2 * steps + n2 + i] as GoBuildFace
		assert_int(left.vertex_indices.size()).is_equal(4)
		assert_int(right.vertex_indices.size()).is_equal(4)


# ---------------------------------------------------------------------------
# Edge manifoldness — every side wall edge should have exactly 2 faces
# ---------------------------------------------------------------------------

func test_staircase_side_wall_edges_are_manifold() -> void:
	var steps := 4
	var mesh := StaircaseGenerator.generate(steps)
	mesh.rebuild_edges()
	var n2: int = steps * (steps + 1) / 2
	var side_face_indices: Dictionary = {}
	for i in range(n2):
		side_face_indices[2 * steps + i] = true
		side_face_indices[2 * steps + n2 + i] = true
	for edge_idx in range(mesh.edges.size()):
		var ed: GoBuildEdge = mesh.edges[edge_idx]
		var touches_side: bool = false
		for fi in ed.face_indices:
			if side_face_indices.has(fi):
				touches_side = true
				break
		if touches_side:
			assert_int(ed.face_indices.size()).is_equal(2)


# ---------------------------------------------------------------------------
# Adjacent grid cells share edges (not just vertices)
# ---------------------------------------------------------------------------

func test_staircase_adjacent_grid_cells_share_full_edges() -> void:
	var steps := 3
	var mesh := StaircaseGenerator.generate(steps)
	mesh.rebuild_edges()
	# For each pair of horizontally adjacent left grid cells (same row, c and c+1),
	# verify they share at least one edge (the vertical boundary between them).
	var n2: int = steps * (steps + 1) / 2
	for r in range(steps):
		for c in range(r, steps - 1):
			var left_idx: int = _left_cell_index(steps, r, c)
			var right_idx: int = _left_cell_index(steps, r, c + 1)
			var shared: bool = false
			for edge_idx in range(mesh.edges.size()):
				var ed: GoBuildEdge = mesh.edges[edge_idx]
				if ed.face_indices.has(left_idx) and ed.face_indices.has(right_idx):
					shared = true
					break
			assert_bool(shared).is_true()


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