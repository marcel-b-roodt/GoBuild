## Delete operation tests — GdUnit4
##
## Tests for [DeleteOperation] covering face delete, edge delete, and vertex
## delete: correct face/vertex counts after deletion, index remapping
## correctness, remaining geometry integrity, and edge cases (null mesh, empty
## selection, invalid indices, duplicates).
##
## Test mesh conventions:
##   _make_single_quad() — one CCW-from-above quad (4 verts, 1 face).
##   _make_two_quads()   — two adjacent coplanar quads (6 verts, 2 faces)
##                         sharing one interior edge between v1,v2 (face 0)
##                         and v1,v4 (face 1 in the original numbering).
extends GdUnitTestSuite

# Self-preloads — test scripts are compiled before mesh/ scripts in Godot's
# alphabetical scan order, so explicit preloads are required.
const _FACE_SCRIPT   := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT   := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT   := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _DELETE_SCRIPT := preload(
		"res://addons/go_build/mesh/operations/delete_operation.gd")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Single CCW-from-above quad in the XZ plane; outward normal = +Y.
## Vertices 0-3, Face 0.
func _make_single_quad() -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [
		Vector3(0, 0, 0),
		Vector3(0, 0, 1),
		Vector3(1, 0, 1),
		Vector3(1, 0, 0),
	]
	var face := GoBuildFace.new()
	face.vertex_indices = [0, 1, 2, 3]
	face.uvs = [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)]
	mesh.faces.append(face)
	mesh.rebuild_edges()
	return mesh


## Two adjacent coplanar quads sharing an edge.
##
## Vertices:
##   0=(0,0,0)  1=(0,0,1)  2=(1,0,1)  3=(1,0,0)  4=(0,0,2)  5=(1,0,2)
##
## Face 0: [0, 1, 2, 3]  uses vertices 0,1,2,3
## Face 1: [1, 4, 5, 2]  uses vertices 1,4,5,2  (shares edge v1-v2 with face 0)
##
## Interior (shared) edge: connects v1 and v2 (the edge between the two quads).
## v0 and v3 are exclusive to face 0; v4 and v5 are exclusive to face 1.
func _make_two_quads() -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [
		Vector3(0, 0, 0),  # 0 — exclusive to face 0
		Vector3(0, 0, 1),  # 1 — shared
		Vector3(1, 0, 1),  # 2 — shared
		Vector3(1, 0, 0),  # 3 — exclusive to face 0
		Vector3(0, 0, 2),  # 4 — exclusive to face 1
		Vector3(1, 0, 2),  # 5 — exclusive to face 1
	]
	var f0 := GoBuildFace.new()
	f0.vertex_indices = [0, 1, 2, 3]
	f0.uvs = [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)]
	var f1 := GoBuildFace.new()
	f1.vertex_indices = [1, 4, 5, 2]
	f1.uvs = [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)]
	mesh.faces.append(f0)
	mesh.faces.append(f1)
	mesh.rebuild_edges()
	return mesh


# ---------------------------------------------------------------------------
# apply_faces — face delete
# ---------------------------------------------------------------------------

func test_delete_only_face_empties_mesh() -> void:
	var mesh := _make_single_quad()
	var indices: Array[int] = [0]
	DeleteOperation.apply_faces(mesh, indices)
	assert_int(mesh.faces.size()).is_equal(0)
	assert_int(mesh.vertices.size()).is_equal(0)


func test_delete_one_of_two_faces_leaves_correct_count() -> void:
	var mesh := _make_two_quads()
	var indices: Array[int] = [0]
	DeleteOperation.apply_faces(mesh, indices)
	assert_int(mesh.faces.size()).is_equal(1)


func test_delete_face_removes_its_orphaned_vertices() -> void:
	# Face 0 uses {0,1,2,3}; face 1 uses {1,4,5,2}.
	# Deleting face 0 leaves face 1, which references {1,2,4,5}.
	# Orphaned vertices are {0,3} → vertex count drops from 6 to 4.
	var mesh := _make_two_quads()
	DeleteOperation.apply_faces(mesh, [0])
	assert_int(mesh.vertices.size()).is_equal(4)


func test_delete_face_preserves_remaining_face_vert_count() -> void:
	var mesh := _make_two_quads()
	DeleteOperation.apply_faces(mesh, [0])
	assert_int(mesh.faces[0].vertex_indices.size()).is_equal(4)


func test_delete_face_remaps_indices_into_valid_range() -> void:
	var mesh := _make_two_quads()
	DeleteOperation.apply_faces(mesh, [0])
	for vi: int in mesh.faces[0].vertex_indices:
		assert_bool(vi >= 0 and vi < mesh.vertices.size()).is_true()


func test_delete_face_remapped_indices_are_contiguous() -> void:
	# After deleting face 0, the 4 surviving vertices are compacted to [0,1,2,3].
	var mesh := _make_two_quads()
	DeleteOperation.apply_faces(mesh, [0])
	var sorted: Array[int] = []
	sorted.assign(mesh.faces[0].vertex_indices.duplicate())
	sorted.sort()
	assert_array(sorted).is_equal([0, 1, 2, 3])


func test_delete_all_faces_empties_vertex_array() -> void:
	var mesh := _make_two_quads()
	DeleteOperation.apply_faces(mesh, [0, 1])
	assert_int(mesh.faces.size()).is_equal(0)
	assert_int(mesh.vertices.size()).is_equal(0)


func test_delete_face_invalid_index_is_noop() -> void:
	var mesh := _make_single_quad()
	DeleteOperation.apply_faces(mesh, [99])
	assert_int(mesh.faces.size()).is_equal(1)
	assert_int(mesh.vertices.size()).is_equal(4)


func test_delete_face_empty_selection_is_noop() -> void:
	var mesh := _make_single_quad()
	var indices: Array[int] = []
	DeleteOperation.apply_faces(mesh, indices)
	assert_int(mesh.faces.size()).is_equal(1)


func test_delete_face_null_mesh_is_noop() -> void:
	# Must not crash.
	var indices: Array[int] = [0]
	DeleteOperation.apply_faces(null, indices)


func test_delete_duplicate_indices_count_as_one() -> void:
	var mesh := _make_single_quad()
	var indices: Array[int] = [0, 0, 0]
	DeleteOperation.apply_faces(mesh, indices)
	assert_int(mesh.faces.size()).is_equal(0)


func test_delete_face_rebuilds_edges() -> void:
	var mesh := _make_two_quads()
	DeleteOperation.apply_faces(mesh, [0])
	# Edges must be rebuilt and reference only valid face indices.
	assert_bool(mesh.edges.size() > 0).is_true()
	for edge: GoBuildEdge in mesh.edges:
		for fi: int in edge.face_indices:
			assert_bool(fi < mesh.faces.size()).is_true()


# ---------------------------------------------------------------------------
# apply_edges — edge delete
# ---------------------------------------------------------------------------

func test_delete_boundary_edge_removes_its_face() -> void:
	# All edges in a single quad are boundary edges (one adjacent face each).
	var mesh := _make_single_quad()
	DeleteOperation.apply_edges(mesh, [0])
	assert_int(mesh.faces.size()).is_equal(0)


func test_delete_shared_edge_removes_both_adjacent_faces() -> void:
	var mesh := _make_two_quads()
	# Find the interior edge (2 adjacent faces).
	var shared_idx: int = -1
	for i: int in mesh.edges.size():
		if mesh.edges[i].face_indices.size() == 2:
			shared_idx = i
			break
	assert_bool(shared_idx != -1).is_true()
	DeleteOperation.apply_edges(mesh, [shared_idx])
	assert_int(mesh.faces.size()).is_equal(0)


func test_delete_boundary_edge_of_one_face_in_two_quads() -> void:
	var mesh := _make_two_quads()
	# Find any boundary edge that belongs only to face 0.
	var edge_idx: int = -1
	for i: int in mesh.edges.size():
		var e: GoBuildEdge = mesh.edges[i]
		if e.face_indices.size() == 1 and e.face_indices[0] == 0:
			edge_idx = i
			break
	assert_bool(edge_idx != -1).is_true()
	DeleteOperation.apply_edges(mesh, [edge_idx])
	assert_int(mesh.faces.size()).is_equal(1)


func test_delete_edge_invalid_index_is_noop() -> void:
	var mesh := _make_single_quad()
	DeleteOperation.apply_edges(mesh, [999])
	assert_int(mesh.faces.size()).is_equal(1)


func test_delete_edge_empty_selection_is_noop() -> void:
	var mesh := _make_single_quad()
	var indices: Array[int] = []
	DeleteOperation.apply_edges(mesh, indices)
	assert_int(mesh.faces.size()).is_equal(1)


func test_delete_edge_null_mesh_is_noop() -> void:
	var indices: Array[int] = [0]
	DeleteOperation.apply_edges(null, indices)


# ---------------------------------------------------------------------------
# apply_vertices — vertex delete
# ---------------------------------------------------------------------------

func test_delete_vertex_removes_its_face() -> void:
	# Single quad: deleting any vertex removes the one face.
	var mesh := _make_single_quad()
	var indices: Array[int] = [0]
	DeleteOperation.apply_vertices(mesh, indices)
	assert_int(mesh.faces.size()).is_equal(0)


func test_delete_exclusive_vertex_removes_only_one_face() -> void:
	# v0 is only referenced by face 0.
	var mesh := _make_two_quads()
	DeleteOperation.apply_vertices(mesh, [0])
	assert_int(mesh.faces.size()).is_equal(1)


func test_delete_shared_vertex_removes_both_faces() -> void:
	# v1 and v2 are shared between face 0 and face 1.
	var mesh := _make_two_quads()
	DeleteOperation.apply_vertices(mesh, [1])
	assert_int(mesh.faces.size()).is_equal(0)


func test_delete_vertex_removes_it_from_vertex_array() -> void:
	var mesh := _make_single_quad()
	DeleteOperation.apply_vertices(mesh, [0])
	assert_int(mesh.vertices.size()).is_equal(0)


func test_delete_exclusive_vertex_compacts_correctly() -> void:
	# Deleting v0 (exclusive to face 0) leaves face 1 with {1,4,5,2} → 4 verts.
	var mesh := _make_two_quads()
	DeleteOperation.apply_vertices(mesh, [0])
	assert_int(mesh.vertices.size()).is_equal(4)


func test_delete_vertex_invalid_index_is_noop() -> void:
	var mesh := _make_single_quad()
	DeleteOperation.apply_vertices(mesh, [99])
	assert_int(mesh.faces.size()).is_equal(1)
	assert_int(mesh.vertices.size()).is_equal(4)


func test_delete_vertex_empty_selection_is_noop() -> void:
	var mesh := _make_single_quad()
	var indices: Array[int] = []
	DeleteOperation.apply_vertices(mesh, indices)
	assert_int(mesh.faces.size()).is_equal(1)


func test_delete_vertex_null_mesh_is_noop() -> void:
	var indices: Array[int] = [0]
	DeleteOperation.apply_vertices(null, indices)
