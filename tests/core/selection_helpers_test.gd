## SelectionHelpers grow/shrink unit tests.
extends GdUnitTestSuite

const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _CUBE_SCRIPT := preload("res://addons/go_build/mesh/generators/cube_generator.gd")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Build a 2×1 grid of quads on the XY plane.
## Vertices: (0,0) (1,0) (2,0) (0,1) (1,1) (2,1)
## Faces: [0,1,4,3] and [1,2,5,4]
func _make_two_adjacent_quads() -> GoBuildMesh:
	var m := GoBuildMesh.new()
	m.vertices = [
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0),
		Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(2, 1, 0),
	]
	var f0 := GoBuildFace.new()
	f0.vertex_indices = [0, 1, 4, 3]
	var f1 := GoBuildFace.new()
	f1.vertex_indices = [1, 2, 5, 4]
	m.faces.append(f0)
	m.faces.append(f1)
	m.rebuild_edges()
	return m


## Build a 3×3 grid of quads (9 faces, 16 vertices).
func _make_3x3_grid() -> GoBuildMesh:
	var m := GoBuildMesh.new()
	for y: int in 4:
		for x: int in 4:
			m.vertices.append(Vector3(x, y, 0))
	for fy: int in 3:
		for fx: int in 3:
			var f := GoBuildFace.new()
			var v0: int = fx + fy * 4
			f.vertex_indices = [v0, v0 + 1, v0 + 5, v0 + 4]
			m.faces.append(f)
	m.rebuild_edges()
	return m


# ---------------------------------------------------------------------------
# Grow vertices
# ---------------------------------------------------------------------------

func test_grow_vertices_single_vertex_on_quad() -> void:
	var m := _make_two_adjacent_quads()
	# Select vertex 1 (shared by both quads).
	var result: Array[int] = SelectionHelpers.grow_vertices(m, [1])
	# Vertex 1 connects to: 0, 2, 4, 3, 5 via edges.
	# Result should include vertex 1 itself plus all neighbours.
	assert_bool(result.has(0)).is_true()
	assert_bool(result.has(1)).is_true()
	assert_bool(result.has(2)).is_true()
	assert_bool(result.has(3)).is_true()
	assert_bool(result.has(4)).is_true()
	assert_bool(result.has(5)).is_true()
	assert_int(result.size()).is_equal(6)


func test_grow_vertices_corner_on_grid() -> void:
	var m := _make_3x3_grid()
	# Select corner vertex 0 — should grow to include 0, 1, 4.
	var result: Array[int] = SelectionHelpers.grow_vertices(m, [0])
	assert_int(result.size()).is_equal(3)
	assert_bool(result.has(0)).is_true()
	assert_bool(result.has(1)).is_true()
	assert_bool(result.has(4)).is_true()


func test_grow_vertices_empty_selection() -> void:
	var m := _make_two_adjacent_quads()
	var result: Array[int] = SelectionHelpers.grow_vertices(m, [])
	assert_int(result.size()).is_equal(0)


# ---------------------------------------------------------------------------
# Grow edges
# ---------------------------------------------------------------------------

func test_grow_edges_single_edge() -> void:
	var m := _make_two_adjacent_quads()
	# Find edge (0,1) — a boundary edge in face 0.
	var ei: int = m.find_edge(0, 1)
	assert_int(ei).is_not_equal(-1)
	var result: Array[int] = SelectionHelpers.grow_edges(m, [ei])
	# Edges touching vertex 0 or 1: (0,1), (0,3), (1,2), (1,4).
	assert_int(result.size()).is_equal(4)
	assert_bool(result.has(ei)).is_true()


# ---------------------------------------------------------------------------
# Grow faces
# ---------------------------------------------------------------------------

func test_grow_faces_single_face_on_grid() -> void:
	var m := _make_3x3_grid()
	# Select center face (index 4).
	var result: Array[int] = SelectionHelpers.grow_faces(m, [4])
	# Center face shares edges with faces 1, 3, 5, 7.
	assert_int(result.size()).is_equal(5)
	assert_bool(result.has(4)).is_true()
	assert_bool(result.has(1)).is_true()
	assert_bool(result.has(3)).is_true()
	assert_bool(result.has(5)).is_true()
	assert_bool(result.has(7)).is_true()


func test_grow_faces_corner_face() -> void:
	var m := _make_3x3_grid()
	# Corner face 0 shares edges with faces 1 and 3.
	var result: Array[int] = SelectionHelpers.grow_faces(m, [0])
	assert_int(result.size()).is_equal(3)
	assert_bool(result.has(0)).is_true()
	assert_bool(result.has(1)).is_true()
	assert_bool(result.has(3)).is_true()


# ---------------------------------------------------------------------------
# Shrink vertices
# ---------------------------------------------------------------------------

func test_shrink_vertices_removes_border() -> void:
	var m := _make_3x3_grid()
	# Select all interior vertices (5, 6, 9, 10) — each has all neighbours
	# also selected when the full 2×2 interior block is picked.
	# Actually, test with the full grid.
	var all_verts: Array[int] = []
	for i: int in m.vertices.size():
		all_verts.append(i)
	# When all vertices are selected, shrink should keep all (every
	# neighbour is selected).
	var result: Array[int] = SelectionHelpers.shrink_vertices(m, all_verts)
	assert_int(result.size()).is_equal(m.vertices.size())


func test_shrink_vertices_single_vertex_goes_empty() -> void:
	var m := _make_two_adjacent_quads()
	# A single vertex always has unselected neighbours.
	var result: Array[int] = SelectionHelpers.shrink_vertices(m, [1])
	assert_int(result.size()).is_equal(0)


# ---------------------------------------------------------------------------
# Shrink edges
# ---------------------------------------------------------------------------

func test_shrink_edges_single_edge_goes_empty() -> void:
	var m := _make_two_adjacent_quads()
	var ei: int = m.find_edge(0, 1)
	var result: Array[int] = SelectionHelpers.shrink_edges(m, [ei])
	assert_int(result.size()).is_equal(0)


# ---------------------------------------------------------------------------
# Shrink faces
# ---------------------------------------------------------------------------

func test_shrink_faces_border_removed() -> void:
	var m := _make_3x3_grid()
	# Select all 9 faces — shrink should keep only the center face (4).
	var all_faces: Array[int] = []
	for i: int in 9:
		all_faces.append(i)
	var result: Array[int] = SelectionHelpers.shrink_faces(m, all_faces)
	assert_int(result.size()).is_equal(1)
	assert_bool(result.has(4)).is_true()


func test_shrink_faces_corner_face_set() -> void:
	var m := _make_3x3_grid()
	# Select corner faces {0, 1, 3}. Face 0 is on the border.
	var result: Array[int] = SelectionHelpers.shrink_faces(m, [0, 1, 3])
	# Only face 0 has all edges shared within the selection? No:
	# face 0 shares edges with 1 and 3, both selected. But face 0
	# also has boundary edges (not shared with any face). Those
	# boundary edges have only face 0 in their face_indices, which
	# IS in the selected set. So face 0 may survive.
	# Actually, face 0 has edges that border ONLY face 0 (boundary edges).
	# For a boundary edge, all adjacent faces (just face 0) are selected.
	# So face 0 would survive. Faces 1 and 3 also each border face 0 (selected)
	# and faces outside the set (2, 4, 5). So they would NOT survive.
	# Result: only face 0.
	assert_int(result.size()).is_equal(1)
	assert_bool(result.has(0)).is_true()


func test_shrink_faces_empty_selection() -> void:
	var m := _make_two_adjacent_quads()
	var result: Array[int] = SelectionHelpers.shrink_faces(m, [])
	assert_int(result.size()).is_equal(0)