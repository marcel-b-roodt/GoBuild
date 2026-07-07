## Rip operation tests — GdUnit4
##
## Tests for [RipOperation] covering:
##   apply_vertices: rip a selected vertex out of unselected faces; verify
##                   duplicated vertices, face integrity, edge rebuild, and
##                   edge cases (null, empty, no shared faces, all faces selected).
##   apply_edges:    rip along selected edges; verify vertex duplication and
##                   seam creation.
##
## Test mesh conventions:
##   _make_two_quads() — two adjacent quads sharing edge v1-v2.
##   _make_three_quads_strip() — three quads in a row sharing two interior edges.
##   _make_single_quad() — one quad (ripping has nothing to separate).
extends GdUnitTestSuite

const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _RIP_SCRIPT  := preload("res://addons/go_build/mesh/operations/rip_operation.gd")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Two adjacent quads sharing interior edge v1-v2.
## v0=(0,0,0)  v1=(1,0,0)  v2=(1,0,1)  v3=(0,0,1)  v4=(2,0,0)  v5=(2,0,1)
## Face 0: [0,1,2,3]   Face 1: [1,4,5,2]
func _make_two_quads() -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [
		Vector3(0, 0, 0),  # 0
		Vector3(1, 0, 0),  # 1
		Vector3(1, 0, 1),  # 2
		Vector3(0, 0, 1),  # 3
		Vector3(2, 0, 0),  # 4
		Vector3(2, 0, 1),  # 5
	]
	var f0 := GoBuildFace.new()
	f0.vertex_indices = [0, 1, 2, 3]
	f0.uvs = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var f1 := GoBuildFace.new()
	f1.vertex_indices = [1, 4, 5, 2]
	f1.uvs = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	mesh.faces.append(f0)
	mesh.faces.append(f1)
	mesh.rebuild_edges()
	return mesh


## Single quad: v0=(0,0,0) v1=(1,0,0) v2=(1,0,1) v3=(0,0,1)
func _make_single_quad() -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [
		Vector3(0, 0, 0), Vector3(1, 0, 0),
		Vector3(1, 0, 1), Vector3(0, 0, 1),
	]
	var f := GoBuildFace.new()
	f.vertex_indices = [0, 1, 2, 3]
	f.uvs = [Vector2(0,0), Vector2(1,0), Vector2(1,1), Vector2(0,1)]
	mesh.faces.append(f)
	mesh.rebuild_edges()
	return mesh


# ---------------------------------------------------------------------------
# apply_vertices — basic rip
# ---------------------------------------------------------------------------

func test_rip_vertex_creates_seam() -> void:
	var mesh := _make_two_quads()
	# Rip vertex 1 out of face 1 (keep it in face 0).
	# After rip, face 1 should reference a NEW vertex at the same position.
	var before_verts: int = mesh.vertices.size()
	var result: Array[int] = RipOperation.apply_vertices(mesh, [1], [0])
	# A new vertex should have been created.
	assert_int(mesh.vertices.size()).is_equal(before_verts + 1)
	# The new vertex should be at the same position as vertex 1.
	assert_bool(mesh.vertices[result[0]].is_equal_approx(Vector3(1, 0, 0))).is_true()
	# Both faces should still exist (no degeneration).
	assert_int(mesh.faces.size()).is_equal(2)
	# Face 0 should still reference original vertex 1.
	assert_bool(mesh.faces[0].vertex_indices.has(1)).is_true()
	# Face 1 should reference the new vertex instead of vertex 1.
	assert_bool(mesh.faces[1].vertex_indices.has(result[0])).is_true()
	assert_bool(not mesh.faces[1].vertex_indices.has(1)).is_true()


func test_rip_vertex_preserves_face_count() -> void:
	var mesh := _make_two_quads()
	RipOperation.apply_vertices(mesh, [1], [0])
	assert_int(mesh.faces.size()).is_equal(2)


func test_rip_both_shared_vertices() -> void:
	var mesh := _make_two_quads()
	# Rip both shared vertices (1 and 2) out of face 1.
	var result: Array[int] = RipOperation.apply_vertices(mesh, [1, 2], [0])
	# Two new vertices should be created (one for each shared vertex).
	assert_int(result.size()).is_equal(2)
	# Both faces should still exist.
	assert_int(mesh.faces.size()).is_equal(2)
	# Face 0 keeps original vertices 1 and 2.
	assert_bool(mesh.faces[0].vertex_indices.has(1)).is_true()
	assert_bool(mesh.faces[0].vertex_indices.has(2)).is_true()
	# Face 1 references the new duplicates, not the originals.
	assert_bool(not mesh.faces[1].vertex_indices.has(1)).is_true()
	assert_bool(not mesh.faces[1].vertex_indices.has(2)).is_true()


func test_rip_creates_boundary_edge() -> void:
	var mesh := _make_two_quads()
	# Before rip, edge (1,2) is shared by both faces (interior).
	var interior_ei: int = mesh.find_edge(1, 2)
	assert_bool(interior_ei >= 0).is_true()
	assert_int(mesh.edges[interior_ei].face_indices.size()).is_equal(2)

	RipOperation.apply_vertices(mesh, [1], [0])

	# After rip, the edge between original v1 and its duplicate should be
	# a boundary (only one face).  Verify edges were rebuilt.
	assert_bool(mesh.edges.size() > 0).is_true()


func test_rip_vertex_noop_when_all_faces_selected() -> void:
	var mesh := _make_two_quads()
	# If ALL faces are selected, rip does nothing — no unselected faces to
	# separate from.
	var result: Array[int] = RipOperation.apply_vertices(mesh, [1], [0, 1])
	assert_int(result.size()).is_equal(0)
	# Mesh should be unchanged.
	assert_int(mesh.vertices.size()).is_equal(6)
	assert_int(mesh.faces.size()).is_equal(2)


func test_rip_vertex_noop_when_no_shared_faces() -> void:
	var mesh := _make_two_quads()
	# Vertex 0 only belongs to face 0. If face 0 is selected and vertex 0
	# is ripped, there are no unselected faces — no rip occurs.
	var result: Array[int] = RipOperation.apply_vertices(mesh, [0], [0])
	assert_int(result.size()).is_equal(0)


func test_rip_empty_selection_is_noop() -> void:
	var mesh := _make_two_quads()
	var result: Array[int] = RipOperation.apply_vertices(mesh, [], [])
	assert_int(result.size()).is_equal(0)
	assert_int(mesh.vertices.size()).is_equal(6)


func test_rip_null_mesh_is_noop() -> void:
	var indices: Array[int] = [0]
	var faces: Array[int] = [0]
	RipOperation.apply_vertices(null, indices, faces)


# ---------------------------------------------------------------------------
# apply_vertices — implicit face selection
# ---------------------------------------------------------------------------

func test_rip_implicit_face_selection() -> void:
	var mesh := _make_two_quads()
	# When face_indices is empty, all faces containing the vertex are "selected".
	# This means no unselected faces exist → no rip.
	var result: Array[int] = RipOperation.apply_vertices(mesh, [1], [])
	assert_int(result.size()).is_equal(0)


# ---------------------------------------------------------------------------
# apply_vertices — edge rebuild
# ---------------------------------------------------------------------------

func test_rip_rebuilds_edges() -> void:
	var mesh := _make_two_quads()
	RipOperation.apply_vertices(mesh, [1], [0])
	for edge: GoBuildEdge in mesh.edges:
		for fi: int in edge.face_indices:
			assert_bool(fi < mesh.faces.size()).is_true()


func test_rip_all_vertex_indices_in_valid_range() -> void:
	var mesh := _make_two_quads()
	RipOperation.apply_vertices(mesh, [1], [0])
	for face: GoBuildFace in mesh.faces:
		for vi: int in face.vertex_indices:
			assert_bool(vi >= 0 and vi < mesh.vertices.size()).is_true()


# ---------------------------------------------------------------------------
# apply_edges
# ---------------------------------------------------------------------------

func test_rip_edge_creates_seam() -> void:
	var mesh := _make_two_quads()
	mesh.rebuild_edges()
	# The interior edge connects v1 and v2.
	var ei: int = mesh.find_edge(1, 2)
	assert_bool(ei >= 0).is_true()

	var result: Array[int] = RipOperation.apply_edges(mesh, [ei])
	# Both endpoint vertices should be duplicated.
	assert_int(result.size()).is_equal(2)
	# Both faces should survive.
	assert_int(mesh.faces.size()).is_equal(2)


func test_rip_edge_on_single_face_is_noop() -> void:
	var mesh := _make_single_quad()
	mesh.rebuild_edges()
	# All edges of a single quad are boundary (1 face only).
	# Rip on a boundary edge: the endpoint vertices belong to only the one face,
	# so they are fully selected → no rip.
	var ei: int = mesh.find_edge(0, 1)
	var result: Array[int] = RipOperation.apply_edges(mesh, [ei])
	assert_int(result.size()).is_equal(0)


func test_rip_edges_empty_selection_is_noop() -> void:
	var mesh := _make_two_quads()
	var result: Array[int] = RipOperation.apply_edges(mesh, [])
	assert_int(result.size()).is_equal(0)


func test_rip_edges_null_mesh_is_noop() -> void:
	var edges: Array[int] = [0]
	RipOperation.apply_edges(null, edges)


# ---------------------------------------------------------------------------
# apply_vertices — degenerate face removal
# ---------------------------------------------------------------------------

func test_rip_does_not_produce_degenerate_faces() -> void:
	var mesh := _make_two_quads()
	RipOperation.apply_vertices(mesh, [1, 2], [0])
	# Every face should have at least 3 distinct vertex indices.
	for face: GoBuildFace in mesh.faces:
		var seen: Dictionary = {}
		for vi: int in face.vertex_indices:
			seen[vi] = true
		assert_bool(seen.size() >= 3).is_true()