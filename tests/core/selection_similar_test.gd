## Select Similar unit tests.
extends GdUnitTestSuite

const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _CUBE_SCRIPT := preload("res://addons/go_build/mesh/generators/cube_generator.gd")
const _SEL_HELPERS_SCRIPT := preload("res://addons/go_build/core/selection_helpers.gd")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Build a 3x3 grid of quads (9 faces, 16 vertices).
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
# Face: Material
# ---------------------------------------------------------------------------

func test_similar_faces_material() -> void:
	var m := _make_3x3_grid()
	# Assign different materials to groups of faces.
	m.faces[0].material_index = 1
	m.faces[1].material_index = 2
	m.faces[2].material_index = 1
	m.faces[3].material_index = 2
	# Remaining faces default to 0.
	var result: Array[int] = SelectionHelpers.similar_faces(
			m, [0], SelectionHelpers.FaceSimilarCriterion.MATERIAL)
	# Faces 0 and 2 share material_index 1.
	assert_int(result.size()).is_equal(2)
	assert_bool(result.has(0)).is_true()
	assert_bool(result.has(2)).is_true()


func test_similar_faces_material_default() -> void:
	var m := _make_3x3_grid()
	# All faces have material_index 0 by default.
	var result: Array[int] = SelectionHelpers.similar_faces(
			m, [4], SelectionHelpers.FaceSimilarCriterion.MATERIAL)
	assert_int(result.size()).is_equal(9)


func test_similar_faces_empty_seed() -> void:
	var m := _make_3x3_grid()
	var result: Array[int] = SelectionHelpers.similar_faces(
			m, [], SelectionHelpers.FaceSimilarCriterion.MATERIAL)
	assert_int(result.size()).is_equal(0)


# ---------------------------------------------------------------------------
# Face: Side Count
# ---------------------------------------------------------------------------

func test_similar_faces_side_count_quads() -> void:
	var m := _make_3x3_grid()
	# All faces are quads (4 sides).
	var result: Array[int] = SelectionHelpers.similar_faces(
			m, [0], SelectionHelpers.FaceSimilarCriterion.SIDE_COUNT)
	assert_int(result.size()).is_equal(9)


func test_similar_faces_side_count_mixed() -> void:
	var m := _make_3x3_grid()
	# Change face 4 to a triangle by removing one vertex.
	m.faces[4].vertex_indices = [5, 6, 10]
	m.rebuild_edges()
	# Select the triangle face — should only match itself.
	var result: Array[int] = SelectionHelpers.similar_faces(
			m, [4], SelectionHelpers.FaceSimilarCriterion.SIDE_COUNT)
	assert_int(result.size()).is_equal(1)
	assert_bool(result.has(4)).is_true()


# ---------------------------------------------------------------------------
# Face: Normal
# ---------------------------------------------------------------------------

func test_similar_faces_normal_flat_grid() -> void:
	var m := _make_3x3_grid()
	# All faces have the same normal (pointing -Z for CCW data).
	var result: Array[int] = SelectionHelpers.similar_faces(
			m, [0], SelectionHelpers.FaceSimilarCriterion.NORMAL)
	assert_int(result.size()).is_equal(9)


# ---------------------------------------------------------------------------
# Face: Coplanar
# ---------------------------------------------------------------------------

func test_similar_faces_coplanar_same_plane() -> void:
	var m := _make_3x3_grid()
	# All faces lie on the Z=0 plane.
	var result: Array[int] = SelectionHelpers.similar_faces(
			m, [0], SelectionHelpers.FaceSimilarCriterion.COPLANAR)
	assert_int(result.size()).is_equal(9)


func test_similar_faces_coplanar_different_plane() -> void:
	var m := _make_3x3_grid()
	# Move face 4's vertices up in Z.
	m.vertices[5].z = 1.0
	m.vertices[6].z = 1.0
	m.vertices[9].z = 1.0
	m.vertices[10].z = 1.0
	m.rebuild_edges()
	# Face 4 is on a different plane now (Z=1).
	var result: Array[int] = SelectionHelpers.similar_faces(
			m, [4], SelectionHelpers.FaceSimilarCriterion.COPLANAR)
	# Only face 4 should match (all others are on Z=0).
	assert_int(result.size()).is_equal(1)
	assert_bool(result.has(4)).is_true()


# ---------------------------------------------------------------------------
# Face: Area
# ---------------------------------------------------------------------------

func test_similar_faces_area_equal() -> void:
	var m := _make_3x3_grid()
	# All 1x1 quads have area 1.0.
	var result: Array[int] = SelectionHelpers.similar_faces(
			m, [0], SelectionHelpers.FaceSimilarCriterion.AREA)
	assert_int(result.size()).is_equal(9)


# ---------------------------------------------------------------------------
# Edge: Length
# ---------------------------------------------------------------------------

func test_similar_edges_length_unit_grid() -> void:
	var m := _make_3x3_grid()
	# All edges in the unit grid have length 1.0.
	# Select a horizontal edge (e.g. 0-1).
	var ei: int = m.find_edge(0, 1)
	assert_int(ei).is_not_equal(-1)
	var result: Array[int] = SelectionHelpers.similar_edges(
			m, [ei], SelectionHelpers.EdgeSimilarCriterion.LENGTH)
	# All unit-length edges should match.
	assert_int(result.size()).is_equal(m.edges.size())


func test_similar_edges_length_mixed() -> void:
	var m := _make_3x3_grid()
	# Modify one vertex to create a non-unit edge.
	m.vertices[1] = Vector3(2, 0, 0)
	m.rebuild_edges()
	# Now edge (0, 1) has length 2 instead of 1.
	var ei: int = m.find_edge(0, 1)
	var result: Array[int] = SelectionHelpers.similar_edges(
			m, [ei], SelectionHelpers.EdgeSimilarCriterion.LENGTH)
	# Only edges of length ~2 should match.
	# Edge (0,1) and potentially edge (1,5) if vertex 1 moved.
	assert_bool(result.has(ei)).is_true()


func test_similar_edges_empty_seed() -> void:
	var m := _make_3x3_grid()
	var result: Array[int] = SelectionHelpers.similar_edges(
			m, [], SelectionHelpers.EdgeSimilarCriterion.LENGTH)
	assert_int(result.size()).is_equal(0)


# ---------------------------------------------------------------------------
# Edge: Face Count
# ---------------------------------------------------------------------------

func test_similar_edges_face_count_boundary() -> void:
	var m := _make_3x3_grid()
	# Select a boundary edge (only 1 face).
	# Top-right corner edge (3, 7) is a boundary edge in a 3x3 grid.
	var ei: int = m.find_edge(3, 7)
	assert_int(ei).is_not_equal(-1)
	var result: Array[int] = SelectionHelpers.similar_edges(
			m, [ei], SelectionHelpers.EdgeSimilarCriterion.FACE_COUNT)
	# All boundary edges should match.
	# In a 3x3 grid, boundary edges are on the outer perimeter.
	for idx: int in result:
		assert_int(m.edges[idx].face_indices.size()).is_equal(1)


func test_similar_edges_face_count_interior() -> void:
	var m := _make_3x3_grid()
	# Select an interior edge (2 faces).
	# Edge (5, 6) is interior in a 3x3 grid.
	var ei: int = m.find_edge(5, 6)
	assert_int(ei).is_not_equal(-1)
	if m.edges[ei].face_indices.size() == 2:
		var result: Array[int] = SelectionHelpers.similar_edges(
				m, [ei], SelectionHelpers.EdgeSimilarCriterion.FACE_COUNT)
		for idx: int in result:
			assert_int(m.edges[idx].face_indices.size()).is_equal(2)


# ---------------------------------------------------------------------------
# Edge: Dihedral
# ---------------------------------------------------------------------------

func test_similar_edges_dihedral_flat() -> void:
	var m := _make_3x3_grid()
	# In a flat grid, all interior edges have dihedral 180 (flat).
	# Select an interior edge.
	var ei: int = m.find_edge(5, 6)
	assert_int(ei).is_not_equal(-1)
	if m.edges[ei].face_indices.size() == 2:
		var result: Array[int] = SelectionHelpers.similar_edges(
				m, [ei], SelectionHelpers.EdgeSimilarCriterion.DIHEDRAL)
		# All flat interior edges should match.
		assert_int(result.size()).is_greater(1)


func test_similar_edges_dihedral_boundary() -> void:
	var m := _make_3x3_grid()
	# Boundary edges have dihedral 180 degrees.
	var ei: int = m.find_edge(0, 1)
	assert_int(ei).is_not_equal(-1)
	var result: Array[int] = SelectionHelpers.similar_edges(
			m, [ei], SelectionHelpers.EdgeSimilarCriterion.DIHEDRAL)
	assert_int(result.size()).is_greater(0)


# ---------------------------------------------------------------------------
# Vertex: Valence
# ---------------------------------------------------------------------------

func test_similar_vertices_valence_corner() -> void:
	var m := _make_3x3_grid()
	# Corner vertices in a 3x3 grid have valence 2 (2 edges).
	# Vertex 0 (bottom-left corner) has edges: (0,1), (0,4).
	var result: Array[int] = SelectionHelpers.similar_vertices(
			m, [0], SelectionHelpers.VertexSimilarCriterion.VALENCE)
	# In a 3x3 grid, 4 corners have valence 2.
	assert_int(result.size()).is_equal(4)
	assert_bool(result.has(0)).is_true()


func test_similar_vertices_valence_interior() -> void:
	var m := _make_3x3_grid()
	# Interior vertex 5 has valence 4.
	var result: Array[int] = SelectionHelpers.similar_vertices(
			m, [5], SelectionHelpers.VertexSimilarCriterion.VALENCE)
	# Only vertex 5 has valence 4 in a 3x3 grid — wait, interior vertices
	# in a 3x3 grid: 5,6,9,10 all have valence 4.
	assert_int(result.size()).is_equal(4)
	assert_bool(result.has(5)).is_true()
	assert_bool(result.has(6)).is_true()
	assert_bool(result.has(9)).is_true()
	assert_bool(result.has(10)).is_true()


func test_similar_vertices_valence_edge() -> void:
	var m := _make_3x3_grid()
	# Edge vertex 1 (bottom row, not corner) has valence 3.
	var result: Array[int] = SelectionHelpers.similar_vertices(
			m, [1], SelectionHelpers.VertexSimilarCriterion.VALENCE)
	# Edge (non-corner) vertices: 1, 2, 4, 7, 8, 11, 12, 13
	# Actually in a 4x4 vertex grid, edge non-corner vertices have valence 3.
	# That's vertices 1, 2, 4, 7, 8, 11, 12, 13 — eight vertices.
	assert_int(result.size()).is_equal(8)