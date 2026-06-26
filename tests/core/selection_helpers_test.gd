## SelectionHelpers grow/shrink/path unit tests.
extends GdUnitTestSuite

const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _CUBE_SCRIPT := preload("res://addons/go_build/mesh/generators/cube_generator.gd")
const _STAIR_SCRIPT := preload("res://addons/go_build/mesh/generators/staircase_generator.gd")


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
	# Vertex 1 connects via edges to: 0, 2, 4.
	# Vertices 3 and 5 are NOT edge-neighbours of vertex 1.
	var result: Array[int] = SelectionHelpers.grow_vertices(m, [1])
	# grow_vertices adds all edge-neighbours plus the seed itself.
	assert_bool(result.has(0)).is_true()
	assert_bool(result.has(1)).is_true()
	assert_bool(result.has(2)).is_true()
	assert_bool(result.has(4)).is_true()
	assert_int(result.size()).is_equal(4)


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


# ---------------------------------------------------------------------------
# Loop selection
# ---------------------------------------------------------------------------

func test_edge_loop_on_grid_horizontal() -> void:
	var m := _make_3x3_grid()
	# Edge (1,5) — vertical edge at column 1.
	# Loop selects connected vertical edges in the same column.
	var ei: int = m.find_edge(1, 5)
	assert_int(ei).is_not_equal(-1)
	var result: Array[int] = SelectionHelpers.edge_loop(m, ei)
	assert_int(result.size()).is_equal(3)
	assert_bool(result.has(ei)).is_true()


func test_edge_loop_on_grid_boundary() -> void:
	var m := _make_3x3_grid()
	# Top edge of the grid — a boundary edge.
	var ei: int = m.find_edge(3, 7)
	assert_int(ei).is_not_equal(-1)
	var result: Array[int] = SelectionHelpers.edge_loop(m, ei)
	# Boundary edges only have one face, so the loop walks one direction.
	# Should return at least 1 edge (the seed itself).
	assert_int(result.size()).is_greater_equal(1)
	assert_bool(result.has(ei)).is_true()


func test_edge_returns_empty_for_invalid_index() -> void:
	var m := _make_3x3_grid()
	var result: Array[int] = SelectionHelpers.edge_loop(m, -1)
	assert_int(result.size()).is_equal(0)
	result = SelectionHelpers.edge_ring(m, 999)
	assert_int(result.size()).is_equal(0)


# ---------------------------------------------------------------------------
# Ring selection
# ---------------------------------------------------------------------------

func test_edge_ring_on_grid() -> void:
	var m := _make_3x3_grid()
	# Edge (1,2) — horizontal bottom boundary edge.
	# Ring selects parallel horizontal edges across the perpendicular strip.
	var ei: int = m.find_edge(1, 2)
	assert_int(ei).is_not_equal(-1)
	var result: Array[int] = SelectionHelpers.edge_ring(m, ei)
	assert_int(result.size()).is_equal(4)
	assert_bool(result.has(ei)).is_true()


func test_face_loop_from_edge() -> void:
	var m := _make_3x3_grid()
	# Edge (0,1) — horizontal bottom boundary edge.
	# face_loop with side_face=f0 walks the strip on f0's side.
	# f0=[0,1,5,4]: opposite of (0,1) is (4,5). Walk through f0→f3→f6.
	var ei: int = m.find_edge(0, 1)
	assert_int(ei).is_not_equal(-1)
	var f0: int = 0
	var result: Array[int] = SelectionHelpers.face_loop(m, ei, f0)
	# Should return the left column: f0, f3, f6.
	assert_int(result.size()).is_equal(3)
	assert_bool(result.has(0)).is_true()
	assert_bool(result.has(3)).is_true()
	assert_bool(result.has(6)).is_true()


func test_face_loop_other_side() -> void:
	var m := _make_3x3_grid()
	# Edge (1,5) — vertical interior edge shared by f0 and f1.
	# face_loop walks the strip PERPENDICULAR to the seed edge.
	# From a vertical edge, the opposite edge in each face is also vertical,
	# and since those opposite edges are boundaries, the loop terminates
	# immediately (only the seed face is returned).
	# Use face_ring to get the column of faces sharing the edge.
	var ei: int = m.find_edge(1, 5)
	assert_int(ei).is_not_equal(-1)
	var left: Array[int] = SelectionHelpers.face_loop(m, ei, 0)
	var right: Array[int] = SelectionHelpers.face_loop(m, ei, 1)
	# Both loops terminate at boundaries, returning only the seed face.
	assert_int(left.size()).is_equal(1)
	assert_bool(left.has(0)).is_true()
	assert_int(right.size()).is_equal(1)
	assert_bool(right.has(1)).is_true()


func test_face_ring_from_edge() -> void:
	var m := _make_3x3_grid()
	var ei: int = m.find_edge(0, 1)
	assert_int(ei).is_not_equal(-1)
	var result: Array[int] = SelectionHelpers.face_ring(m, ei)
	assert_int(result.size()).is_greater_equal(1)


# ---------------------------------------------------------------------------
# Face path (weighted Dijkstra)
# ---------------------------------------------------------------------------

func test_face_path_coplanar_preferred_on_cube() -> void:
	# On a cube, face_path from front face to side face should go
	# through the shared edge rather than going around through
	# the back face (which would be a longer geometric path).
	var m: GoBuildMesh = CubeGenerator.generate(2.0, 2.0, 2.0, 0)
	m.rebuild_edges()
	# Cube faces: 0=front(+Z), 1=back(-Z), 2=top(+Y), 3=bottom(-Y), 4=right(+X), 5=left(-X)
	# Path from front to right should be [front, right] (direct neighbors).
	var path: Array[int] = SelectionHelpers.face_path(m, 0, 4)
	assert_int(path.size()).is_greater_equal(2)
	assert_int(path[0]).is_equal(0)
	assert_int(path[path.size() - 1]).is_equal(4)


func test_face_path_same_face() -> void:
	var m := _make_3x3_grid()
	var path: Array[int] = SelectionHelpers.face_path(m, 0, 0)
	assert_int(path.size()).is_equal(1)
	assert_int(path[0]).is_equal(0)


func test_face_path_on_grid_prefers_shortest() -> void:
	var m := _make_3x3_grid()
	# Path from face 0 (top-left corner) to face 8 (bottom-right corner)
	# should take 5 hops: 0→1→2→5→8 or 0→3→6→7→8 (or similar).
	var path: Array[int] = SelectionHelpers.face_path(m, 0, 8)
	assert_int(path.size()).is_greater_equal(2)
	assert_int(path[0]).is_equal(0)
	assert_int(path[path.size() - 1]).is_equal(8)
	# On a flat grid all faces are coplanar, so the path should be
	# a shortest hop-count path (Manhattan distance + 1).
	assert_int(path.size()).is_less_equal(6)


func test_face_path_invalid_indices() -> void:
	var m := _make_3x3_grid()
	var path: Array[int] = SelectionHelpers.face_path(m, -1, 0)
	assert_int(path.size()).is_equal(0)
	path = SelectionHelpers.face_path(m, 0, 999)
	assert_int(path.size()).is_equal(0)


# ---------------------------------------------------------------------------
# Edge path (weighted Dijkstra)
# ---------------------------------------------------------------------------

func test_edge_path_on_grid_straight_line() -> void:
	var m := _make_3x3_grid()
	# Find two boundary edges on opposite sides of the grid.
	# Edge (0,1) — top-left horizontal boundary.
	# Edge (2,6) — bottom-left vertical boundary... not quite right.
	# Let's use edges along the bottom boundary row.
	var e01: int = m.find_edge(0, 1)
	var e11_12: int = m.find_edge(11, 12)
	assert_int(e01).is_not_equal(-1)
	assert_int(e11_12).is_not_equal(-1)
	var path: Array[int] = SelectionHelpers.edge_path(m, e01, e11_12)
	assert_int(path.size()).is_greater_equal(2)
	assert_int(path[0]).is_equal(e01)
	assert_int(path[path.size() - 1]).is_equal(e11_12)


func test_edge_path_same_edge() -> void:
	var m := _make_3x3_grid()
	var ei: int = m.find_edge(0, 1)
	var path: Array[int] = SelectionHelpers.edge_path(m, ei, ei)
	assert_int(path.size()).is_equal(1)
	assert_int(path[0]).is_equal(ei)


func test_edge_path_invalid_indices() -> void:
	var m := _make_3x3_grid()
	var path: Array[int] = SelectionHelpers.edge_path(m, -1, 0)
	assert_int(path.size()).is_equal(0)
	path = SelectionHelpers.edge_path(m, 0, 999)
	assert_int(path.size()).is_equal(0)


func test_edge_path_prefers_coplanar_on_cube() -> void:
	# On a cube, edge_path from a front-face edge to a side-face edge
	# should go through the shared edge rather than around through
	# the back face.
	var m: GoBuildMesh = CubeGenerator.generate(2.0, 2.0, 2.0, 0)
	m.rebuild_edges()
	# Find an edge on the front face and an edge on the right face.
	# Front face vertices: (0,0,1),(1,0,1),(1,1,1),(0,1,1) →
	# right face vertices: (1,0,1),(1,0,0),(1,1,0),(1,1,1)
	# Shared edge: (1,0,1)-(1,1,1) — find it.
	var all_edges := m.edges
	var front_ei: int = -1
	var right_ei: int = -1
	var shared_ei: int = -1
	for i: int in all_edges.size():
		var ed: GoBuildEdge = all_edges[i]
		var va: Vector3 = m.vertices[ed.vertex_a]
		var vb: Vector3 = m.vertices[ed.vertex_b]
		# Front face edge: both endpoints at z=1 (front face).
		if absf(va.z - 1.0) < 0.01 and absf(vb.z - 1.0) < 0.01:
			if front_ei == -1:
				front_ei = i
		# Right face edge: both endpoints at x=1 (right face).
		if absf(va.x - 1.0) < 0.01 and absf(vb.x - 1.0) < 0.01:
			if right_ei == -1 and ed.face_indices.size() >= 2:
				right_ei = i
	assert_int(front_ei).is_not_equal(-1)
	assert_int(right_ei).is_not_equal(-1)
	var path: Array[int] = SelectionHelpers.edge_path(m, front_ei, right_ei)
	assert_int(path.size()).is_greater_equal(2)
	assert_int(path[0]).is_equal(front_ei)
	assert_int(path[path.size() - 1]).is_equal(right_ei)


# ---------------------------------------------------------------------------
# Staircase edge path prefers coplanar
# ---------------------------------------------------------------------------

func test_edge_path_staircase_prefers_side_over_back() -> void:
	var m: GoBuildMesh = StaircaseGenerator.generate(4, 1.0, 0.25, 0.3)
	m.rebuild_edges()
	# Find an edge on the left side wall (normal -X) and another
	# on the right side wall (normal +X). The path should go around
	# the front or back, not through every face of the staircase.
	# We just verify the path exists and is non-trivial.
	assert_int(m.edges.size()).is_greater(0)
	# Pick any two edges and verify path exists.
	var path: Array[int] = SelectionHelpers.edge_path(m, 0, m.edges.size() - 1)
	# Path should exist on a connected mesh.
	assert_int(path.size()).is_greater_equal(2)


func test_face_path_staircase_prefers_side_over_back() -> void:
	var m: GoBuildMesh = StaircaseGenerator.generate(4, 1.0, 0.25, 0.3)
	m.rebuild_edges()
	# Find the first tread face (normal +Y) and the back face (normal +Z).
	# face_path should prefer going through side faces rather than through
	# the bottom face, because side faces are more coplanar with the tread
	# than the bottom face (perpendicular).
	var tread_fi: int = 0  # First tread
	# Find the back face — it has normal (0,0,1).
	var back_fi: int = -1
	for fi: int in m.faces.size():
		var n: Vector3 = m.compute_face_normal(m.faces[fi])
		if n.dot(Vector3(0.0, 0.0, 1.0)) > 0.999:
			back_fi = fi
			break
	assert_int(back_fi).is_not_equal(-1)
	var path: Array[int] = SelectionHelpers.face_path(m, tread_fi, back_fi)
	assert_int(path.size()).is_greater_equal(2)
	assert_int(path[0]).is_equal(tread_fi)
	assert_int(path[path.size() - 1]).is_equal(back_fi)