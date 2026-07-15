## Rip operation tests — GdUnit4
##
## Tests for [RipOperation] covering:
##   apply_vertices: rip selected vertices; verify duplicated vertices,
##                   face integrity, edge rebuild, and edge cases.
##   apply_vertex_drag: rip + translate, verify offset positions.
##   apply_edges:      rip along selected edges; verify vertex duplication.
##   apply_edge_drag:  rip along edges + translate.
##   compute_rip_direction: verify average normal computation.
##
## Key behavior:
##   - With face selection: duplicate vertices go into SELECTED faces (the
##     ripped piece). Originals stay in unselected faces (mesh body).
##   - Without face selection (Vertex mode): direction-based face split.
##     Faces whose normal aligns with the direction go to the duplicate;
##     faces whose normal opposes the direction keep the original.
##     If all faces fall on one side, a forced split puts at least one face
##     in each group.
##
## Test mesh conventions:
##   _make_two_quads() — two adjacent quads sharing edge v1-v2 on the XZ plane.
##   _make_single_quad() — one quad on the XZ plane.
extends GdUnitTestSuite

const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _RIP_SCRIPT  := preload("res://addons/go_build/mesh/operations/rip_operation.gd")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Two adjacent quads sharing interior edge v1-v2, on the XZ plane.
## v0=(0,0,0)  v1=(1,0,0)  v2=(1,0,1)  v3=(0,0,1)  v4=(2,0,0)  v5=(2,0,1)
## Face 0: [0,1,2,3] (normal +Y)   Face 1: [1,4,5,2] (normal +Y)
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
# apply_vertices — explicit face selection
# ---------------------------------------------------------------------------

func test_rip_vertex_creates_seam() -> void:
	var mesh := _make_two_quads()
	var before_verts: int = mesh.vertices.size()
	var result: Array[int] = RipOperation.apply_vertices(mesh, [1], [0])
	assert_int(mesh.vertices.size()).is_equal(before_verts + 1)
	assert_bool(mesh.vertices[result[0]].is_equal_approx(Vector3(1, 0, 0))).is_true()
	assert_int(mesh.faces.size()).is_equal(2)
	# Face 0 (selected) should reference the NEW duplicate vertex.
	assert_bool(mesh.faces[0].vertex_indices.has(result[0])).is_true()
	assert_bool(not mesh.faces[0].vertex_indices.has(1)).is_true()
	# Face 1 (unselected) should still reference original vertex 1.
	assert_bool(mesh.faces[1].vertex_indices.has(1)).is_true()


func test_rip_vertex_preserves_face_count() -> void:
	var mesh := _make_two_quads()
	RipOperation.apply_vertices(mesh, [1], [0])
	assert_int(mesh.faces.size()).is_equal(2)


func test_rip_both_shared_vertices() -> void:
	var mesh := _make_two_quads()
	var result: Array[int] = RipOperation.apply_vertices(mesh, [1, 2], [0])
	assert_int(result.size()).is_equal(2)
	assert_int(mesh.faces.size()).is_equal(2)
	# Face 0 (selected) references the new duplicates.
	assert_bool(not mesh.faces[0].vertex_indices.has(1)).is_true()
	assert_bool(not mesh.faces[0].vertex_indices.has(2)).is_true()
	# Face 1 (unselected) keeps the original vertices.
	assert_bool(mesh.faces[1].vertex_indices.has(1)).is_true()
	assert_bool(mesh.faces[1].vertex_indices.has(2)).is_true()


func test_rip_creates_boundary_edge() -> void:
	var mesh := _make_two_quads()
	var interior_ei: int = mesh.find_edge(1, 2)
	assert_bool(interior_ei >= 0).is_true()
	assert_int(mesh.edges[interior_ei].face_indices.size()).is_equal(2)

	RipOperation.apply_vertices(mesh, [1], [0])
	assert_bool(mesh.edges.size() > 0).is_true()


func test_rip_vertex_noop_when_all_faces_selected() -> void:
	var mesh := _make_two_quads()
	var result: Array[int] = RipOperation.apply_vertices(mesh, [1], [0, 1])
	assert_int(result.size()).is_equal(0)
	assert_int(mesh.vertices.size()).is_equal(6)
	assert_int(mesh.faces.size()).is_equal(2)


func test_rip_vertex_noop_when_no_shared_faces() -> void:
	var mesh := _make_two_quads()
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
# apply_vertices — direction-based face split (Vertex mode, no face selection)
# ---------------------------------------------------------------------------

func test_rip_direction_split_creates_vertex() -> void:
	var mesh := _make_two_quads()
	var before_verts: int = mesh.vertices.size()
	# Vertex 1 is shared by faces 0 and 1. Both face normals point +Y.
	# Direction +Y: both faces have normal dot direction >= 0 → "toward".
	# Force split: one face stays with original, rest go to duplicate.
	var result: Array[int] = RipOperation.apply_vertices(mesh, [1], [], Vector3.UP)
	assert_int(result.size()).is_equal(1)
	# Vertex count should increase by 1.
	assert_int(mesh.vertices.size()).is_equal(before_verts + 1)
	assert_int(mesh.faces.size()).is_equal(2)
	# Exactly one face should reference the duplicate, one should reference the original.
	var dup_count: int = 0
	var orig_count: int = 0
	for face: GoBuildFace in mesh.faces:
		if face.vertex_indices.has(result[0]):
			dup_count += 1
		if face.vertex_indices.has(1):
			orig_count += 1
	assert_int(dup_count).is_equal(1)
	assert_int(orig_count).is_equal(1)


func test_rip_direction_multi_vertex_no_cross_contamination() -> void:
	# Two vertices (1 and 2) share two faces.  Both are ripped with direction +Y.
	# Both face normals are +Y, so force-split applies.
	# Each vertex should get its own toward/away split independently,
	# not contaminate the other's face assignments.
	var mesh := _make_two_quads()
	var result: Array[int] = RipOperation.apply_vertices(mesh, [1, 2], [], Vector3.UP)
	assert_int(result.size()).is_equal(2)
	assert_int(mesh.faces.size()).is_equal(2)
	# Each original vertex should appear in exactly one face (the "away" face).
	# Each duplicate should appear in exactly one face (the "toward" face).
	var v1_orig_in: int = 0
	var v2_orig_in: int = 0
	var dup0_in: int = 0
	var dup1_in: int = 0
	for face: GoBuildFace in mesh.faces:
		if face.vertex_indices.has(1):
			v1_orig_in += 1
		if face.vertex_indices.has(2):
			v2_orig_in += 1
		if face.vertex_indices.has(result[0]):
			dup0_in += 1
		if face.vertex_indices.has(result[1]):
			dup1_in += 1
	assert_int(v1_orig_in).is_equal(1)
	assert_int(v2_orig_in).is_equal(1)
	assert_int(dup0_in).is_equal(1)
	assert_int(dup1_in).is_equal(1)


func test_rip_direction_split_with_opposing_faces() -> void:
	# Build a mesh where vertex 1 is shared by faces with different normals.
	var mesh := GoBuildMesh.new()
	mesh.vertices = [
		Vector3(0, 0, 0),   # 0
		Vector3(1, 0, 0),   # 1
		Vector3(1, 0, -1),  # 2
		Vector3(0, 0, -1),  # 3
		Vector3(1, 1, 0),   # 4
		Vector3(1, 1, -1),  # 5
	]
	# Bottom face (normal -Y): [0,3,2,1]  — vertices wound CCW from below
	var f_bottom := GoBuildFace.new()
	f_bottom.vertex_indices = [0, 1, 2, 3]
	f_bottom.uvs = [Vector2(0,0), Vector2(1,0), Vector2(1,1), Vector2(0,1)]
	# Top face (normal +Y): [1,4,5,2]
	var f_top := GoBuildFace.new()
	f_top.vertex_indices = [1, 4, 5, 2]
	f_top.uvs = [Vector2(0,0), Vector2(1,0), Vector2(1,1), Vector2(0,1)]
	mesh.faces.append(f_bottom)
	mesh.faces.append(f_top)
	mesh.rebuild_edges()

	# Rip vertex 1 with direction +Y.
	# Top face normal ~+Y → toward → gets duplicate.
	# Bottom face normal ~-Y → away → keeps original.
	var result: Array[int] = RipOperation.apply_vertices(mesh, [1], [], Vector3.UP)
	assert_int(result.size()).is_equal(1)
	# Top face should reference the duplicate.
	assert_bool(mesh.faces[1].vertex_indices.has(result[0])).is_true()
	assert_bool(not mesh.faces[1].vertex_indices.has(1)).is_true()
	# Bottom face should keep original vertex 1.
	assert_bool(mesh.faces[0].vertex_indices.has(1)).is_true()


func test_rip_direction_preserves_positions() -> void:
	var mesh := _make_two_quads()
	var result: Array[int] = RipOperation.apply_vertices(mesh, [1], [], Vector3.UP)
	assert_int(result.size()).is_equal(1)
	assert_bool(mesh.vertices[result[0]].is_equal_approx(mesh.vertices[1])).is_true()


func test_rip_direction_single_face_vertex_is_noop() -> void:
	var mesh := _make_single_quad()
	# Vertex 0 has only 1 adjacent face. Can't create a seam.
	var result: Array[int] = RipOperation.apply_vertices(mesh, [0], [], Vector3.UP)
	assert_int(result.size()).is_equal(0)
	assert_int(mesh.vertices.size()).is_equal(4)


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
# apply_vertex_drag
# ---------------------------------------------------------------------------

func test_rip_vertex_drag_translates_ripped_piece() -> void:
	var mesh := _make_two_quads()
	var direction := Vector3(0.0, 1.0, 0.0)
	var distance := 2.0
	var result: Array[int] = RipOperation.apply_vertex_drag(
			mesh, [1], [0], direction, distance)
	assert_int(result.size()).is_equal(1)
	var offset: Vector3 = direction * distance
	assert_bool(mesh.vertices[result[0]].is_equal_approx(
			Vector3(1, 0, 0) + offset)).is_true()
	# Original vertex 1 should still be at its original position.
	assert_bool(mesh.vertices[1].is_equal_approx(Vector3(1, 0, 0))).is_true()


func test_rip_vertex_drag_negative_distance() -> void:
	var mesh := _make_two_quads()
	var direction := Vector3(0.0, 1.0, 0.0)
	var distance := -1.5
	var result: Array[int] = RipOperation.apply_vertex_drag(
			mesh, [1], [0], direction, distance)
	assert_int(result.size()).is_equal(1)
	var offset: Vector3 = direction * distance
	assert_bool(mesh.vertices[result[0]].is_equal_approx(
			Vector3(1, 0, 0) + offset)).is_true()


func test_rip_vertex_drag_zero_distance() -> void:
	var mesh := _make_two_quads()
	var result: Array[int] = RipOperation.apply_vertex_drag(
			mesh, [1], [0], Vector3.UP, 0.0)
	assert_int(result.size()).is_equal(1)
	assert_bool(mesh.vertices[result[0]].is_equal_approx(Vector3(1, 0, 0))).is_true()


func test_rip_edge_drag_translates_ripped_piece() -> void:
	var mesh := _make_two_quads()
	mesh.rebuild_edges()
	var ei: int = mesh.find_edge(1, 2)
	assert_bool(ei >= 0).is_true()

	var direction := Vector3(0.0, 1.0, 0.0)
	var distance := 1.0
	var result: Array[int] = RipOperation.apply_edge_drag(
			mesh, [ei], direction, distance)
	assert_int(result.size()).is_equal(2)
	for vi: int in result:
		assert_bool(mesh.vertices[vi].y).is_greater(0.0)


# ---------------------------------------------------------------------------
# apply_edges
# ---------------------------------------------------------------------------

func test_rip_edge_creates_seam() -> void:
	var mesh := _make_two_quads()
	mesh.rebuild_edges()
	var ei: int = mesh.find_edge(1, 2)
	assert_bool(ei >= 0).is_true()

	var result: Array[int] = RipOperation.apply_edges(mesh, [ei])
	assert_int(result.size()).is_equal(2)
	assert_int(mesh.faces.size()).is_equal(2)


func test_rip_edge_on_single_face_is_noop() -> void:
	var mesh := _make_single_quad()
	mesh.rebuild_edges()
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
	for face: GoBuildFace in mesh.faces:
		var seen: Dictionary = {}
		for vi: int in face.vertex_indices:
			seen[vi] = true
		assert_bool(seen.size() >= 3).is_true()


# ---------------------------------------------------------------------------
# compute_rip_direction
# ---------------------------------------------------------------------------

func test_compute_rip_direction_returns_normalized() -> void:
	var mesh := _make_two_quads()
	var direction: Vector3 = RipOperation.compute_rip_direction(mesh, [0])
	assert_bool(direction.is_normalized()).is_true()


func test_compute_rip_direction_empty_faces() -> void:
	var direction: Vector3 = RipOperation.compute_rip_direction(null, [])
	assert_bool(direction.is_equal_approx(Vector3.UP)).is_true()


func test_compute_rip_direction_single_face() -> void:
	var mesh := _make_single_quad()
	var direction: Vector3 = RipOperation.compute_rip_direction(mesh, [0])
	# Single quad on the XZ plane — normal should point up (Y).
	assert_bool(direction.y).is_greater(0.9)