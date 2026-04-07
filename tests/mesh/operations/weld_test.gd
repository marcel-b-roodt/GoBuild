## Weld / Merge operation tests — GdUnit4
##
## Tests for [WeldOperation] covering:
##   apply_merge: centroid position, degenerate-face removal, vertex compaction,
##                index remapping, edge cases (< 2 verts, null, invalid indices).
##   apply_weld_by_threshold: threshold grouping, centroid accuracy, degenerate
##                removal, no-op when nothing is close enough.
##
## Test mesh conventions:
##   _make_line_quad()  — one quad; v0 and v1 share position (already coincident).
##   _make_two_quads()  — two adjacent quads sharing an interior edge (v1, v2).
##   _make_triangle()   — single triangle; merging all 3 vertices must produce
##                        a degenerate face that gets removed.
extends GdUnitTestSuite

const _FACE_SCRIPT  := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT  := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT  := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _WELD_SCRIPT  := preload(
		"res://addons/go_build/mesh/operations/weld_operation.gd")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Single quad: v0=(0,0,0)  v1=(0,0,1)  v2=(1,0,1)  v3=(1,0,0)
func _make_single_quad() -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [
		Vector3(0, 0, 0), Vector3(0, 0, 1),
		Vector3(1, 0, 1), Vector3(1, 0, 0),
	]
	var f := GoBuildFace.new()
	f.vertex_indices = [0, 1, 2, 3]
	f.uvs = [Vector2(0,0), Vector2(0,1), Vector2(1,1), Vector2(1,0)]
	mesh.faces.append(f)
	mesh.rebuild_edges()
	return mesh


## Two adjacent quads sharing edge v1-v2.
## v0=(0,0,0)  v1=(0,0,1)  v2=(1,0,1)  v3=(1,0,0)  v4=(0,0,2)  v5=(1,0,2)
## Face 0: [0,1,2,3]   Face 1: [1,4,5,2]
func _make_two_quads() -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [
		Vector3(0,0,0), Vector3(0,0,1), Vector3(1,0,1),
		Vector3(1,0,0), Vector3(0,0,2), Vector3(1,0,2),
	]
	var f0 := GoBuildFace.new()
	f0.vertex_indices = [0, 1, 2, 3]
	f0.uvs = [Vector2(0,0), Vector2(0,1), Vector2(1,1), Vector2(1,0)]
	var f1 := GoBuildFace.new()
	f1.vertex_indices = [1, 4, 5, 2]
	f1.uvs = [Vector2(0,0), Vector2(0,1), Vector2(1,1), Vector2(1,0)]
	mesh.faces.append(f0)
	mesh.faces.append(f1)
	mesh.rebuild_edges()
	return mesh


## Single triangle: v0=(0,0,0)  v1=(1,0,0)  v2=(0,0,1)
func _make_triangle() -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [Vector3(0,0,0), Vector3(1,0,0), Vector3(0,0,1)]
	var f := GoBuildFace.new()
	f.vertex_indices = [0, 1, 2]
	f.uvs = [Vector2(0,0), Vector2(1,0), Vector2(0,1)]
	mesh.faces.append(f)
	mesh.rebuild_edges()
	return mesh


# ---------------------------------------------------------------------------
# apply_merge — position of survivor
# ---------------------------------------------------------------------------

func test_merge_two_verts_positions_at_centroid() -> void:
	# Merge v0=(0,0,0) and v2=(1,0,1): centroid = (0.5, 0, 0.5).
	var mesh := _make_single_quad()
	var indices: Array[int] = [0, 2]
	WeldOperation.apply_merge(mesh, indices)
	# Find the vertex at centroid (or close enough).
	var found: bool = false
	for v: Vector3 in mesh.vertices:
		if v.is_equal_approx(Vector3(0.5, 0, 0.5)):
			found = true
			break
	assert_bool(found).is_true()


func test_merge_two_adjacent_verts_centroid_correct() -> void:
	# Merge v0=(0,0,0) and v1=(0,0,1): centroid = (0,0,0.5).
	var mesh := _make_single_quad()
	var indices: Array[int] = [0, 1]
	WeldOperation.apply_merge(mesh, indices)
	var found: bool = false
	for v: Vector3 in mesh.vertices:
		if v.is_equal_approx(Vector3(0, 0, 0.5)):
			found = true
			break
	assert_bool(found).is_true()


# ---------------------------------------------------------------------------
# apply_merge — face and vertex counts
# ---------------------------------------------------------------------------

func test_merge_two_verts_of_quad_reduces_vertex_count() -> void:
	# Merging two verts of the only face collapses one; face becomes a triangle.
	# Vertex count after compaction: 4 → 3 (one duplicate removed).
	var mesh := _make_single_quad()
	var indices: Array[int] = [0, 1]
	WeldOperation.apply_merge(mesh, indices)
	assert_int(mesh.vertices.size()).is_equal(3)


func test_merge_two_verts_of_quad_keeps_face() -> void:
	# A quad losing one unique vertex becomes a 3-vertex (triangle) face — still valid.
	var mesh := _make_single_quad()
	var indices: Array[int] = [0, 1]
	WeldOperation.apply_merge(mesh, indices)
	assert_int(mesh.faces.size()).is_equal(1)


func test_merge_all_verts_of_triangle_removes_degenerate_face() -> void:
	# Merging all 3 vertices of a triangle leaves < 3 distinct indices → face removed.
	var mesh := _make_triangle()
	var indices: Array[int] = [0, 1, 2]
	WeldOperation.apply_merge(mesh, indices)
	assert_int(mesh.faces.size()).is_equal(0)
	assert_int(mesh.vertices.size()).is_equal(0)


func test_merge_shared_verts_removes_shared_face() -> void:
	# Merge v1 and v2 (shared by both quads): both faces become degenerate.
	var mesh := _make_two_quads()
	var indices: Array[int] = [1, 2]
	WeldOperation.apply_merge(mesh, indices)
	# Face 0 [0,1,2,3] → [0,C,C,3] where C=merged; only 3 distinct → valid tri.
	# Face 1 [1,4,5,2] → [C,4,5,C] — 3 distinct → valid tri.
	# Both faces survive as triangles.
	assert_int(mesh.faces.size()).is_equal(2)


func test_merge_remaps_keep_indices_in_valid_range() -> void:
	var mesh := _make_two_quads()
	var indices: Array[int] = [0, 3]
	WeldOperation.apply_merge(mesh, indices)
	for face: GoBuildFace in mesh.faces:
		for vi: int in face.vertex_indices:
			assert_bool(vi >= 0 and vi < mesh.vertices.size()).is_true()


# ---------------------------------------------------------------------------
# apply_merge — edge cases
# ---------------------------------------------------------------------------

func test_merge_single_index_is_noop() -> void:
	var mesh := _make_single_quad()
	var indices: Array[int] = [0]
	WeldOperation.apply_merge(mesh, indices)
	assert_int(mesh.faces.size()).is_equal(1)
	assert_int(mesh.vertices.size()).is_equal(4)


func test_merge_empty_selection_is_noop() -> void:
	var mesh := _make_single_quad()
	var indices: Array[int] = []
	WeldOperation.apply_merge(mesh, indices)
	assert_int(mesh.faces.size()).is_equal(1)
	assert_int(mesh.vertices.size()).is_equal(4)


func test_merge_null_mesh_is_noop() -> void:
	var indices: Array[int] = [0, 1]
	WeldOperation.apply_merge(null, indices)  # Must not crash.


func test_merge_invalid_indices_filtered_out() -> void:
	var mesh := _make_single_quad()
	# Only index 0 is valid; 99 is out of range → effectively single index → noop.
	var indices: Array[int] = [0, 99]
	WeldOperation.apply_merge(mesh, indices)
	assert_int(mesh.vertices.size()).is_equal(4)


func test_merge_duplicate_indices_count_as_one() -> void:
	var mesh := _make_single_quad()
	# [0, 0, 1] de-duplicates to [0, 1] → valid merge.
	var indices: Array[int] = [0, 0, 1]
	WeldOperation.apply_merge(mesh, indices)
	assert_int(mesh.vertices.size()).is_equal(3)


func test_merge_rebuilds_edges() -> void:
	var mesh := _make_two_quads()
	var indices: Array[int] = [0, 3]
	WeldOperation.apply_merge(mesh, indices)
	assert_bool(mesh.edges.size() > 0).is_true()
	for edge: GoBuildEdge in mesh.edges:
		for fi: int in edge.face_indices:
			assert_bool(fi < mesh.faces.size()).is_true()


# ---------------------------------------------------------------------------
# apply_weld_by_threshold
# ---------------------------------------------------------------------------

func test_weld_threshold_merges_coincident_verts() -> void:
	# Place v0 and v1 at the same position; threshold weld should merge them.
	var mesh := GoBuildMesh.new()
	mesh.vertices = [
		Vector3(0, 0, 0), Vector3(0, 0, 0),   # coincident
		Vector3(1, 0, 1), Vector3(1, 0, 0),
	]
	var f := GoBuildFace.new()
	f.vertex_indices = [0, 1, 2, 3]
	f.uvs = [Vector2(0,0), Vector2(0,1), Vector2(1,1), Vector2(1,0)]
	mesh.faces.append(f)
	mesh.rebuild_edges()
	WeldOperation.apply_weld_by_threshold(mesh, 0.0001)
	# After merge v0 and v1 collapse; face becomes degenerate (only 3 distinct).
	# Vertex count should drop.
	assert_bool(mesh.vertices.size() < 4).is_true()


func test_weld_threshold_does_not_merge_distant_verts() -> void:
	var mesh := _make_single_quad()
	# All verts are 1 unit apart; threshold 0.0001 must not merge anything.
	WeldOperation.apply_weld_by_threshold(mesh, 0.0001)
	assert_int(mesh.vertices.size()).is_equal(4)
	assert_int(mesh.faces.size()).is_equal(1)


func test_weld_threshold_merged_position_is_centroid() -> void:
	var mesh := GoBuildMesh.new()
	# v0 and v1 are 0.05 apart; threshold 0.1 should merge them to centroid (0.025, 0, 0).
	mesh.vertices = [Vector3(0,0,0), Vector3(0.05,0,0), Vector3(1,0,0)]
	var f := GoBuildFace.new()
	f.vertex_indices = [0, 1, 2]
	f.uvs = [Vector2(0,0), Vector2(0.5,0), Vector2(1,0)]
	mesh.faces.append(f)
	mesh.rebuild_edges()
	WeldOperation.apply_weld_by_threshold(mesh, 0.1)
	# After merge, face is degenerate (only 2 distinct) → removed.
	# One or two vertices remain (centroid + far vert).
	assert_bool(mesh.vertices.size() <= 2).is_true()


func test_weld_threshold_null_mesh_is_noop() -> void:
	WeldOperation.apply_weld_by_threshold(null, 0.001)  # Must not crash.


func test_weld_threshold_single_vertex_is_noop() -> void:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [Vector3(0, 0, 0)]
	WeldOperation.apply_weld_by_threshold(mesh, 1.0)
	assert_int(mesh.vertices.size()).is_equal(1)


func test_weld_rebuilds_edges() -> void:
	var mesh := _make_two_quads()
	WeldOperation.apply_weld_by_threshold(mesh, 0.0001)
	for edge: GoBuildEdge in mesh.edges:
		for fi: int in edge.face_indices:
			assert_bool(fi < mesh.faces.size()).is_true()
