## Dissolve operation tests — GdUnit4
##
## Tests for [DissolveOperation] covering:
##   dissolve_edges: merge two adjacent faces into one, skip boundary edges,
##                   skip edges with != 2 faces, winding correctness.
##   dissolve_vertices: cube corner → hexagonal face, L-shape skip (2 faces),
##                      non-planar dissolve with winding fix, multiple vertices.
extends GdUnitTestSuite

const _FACE_SCRIPT     := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT     := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT     := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _DISSOLVE_SCRIPT := preload("res://addons/go_build/mesh/operations/dissolve_operation.gd")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Two adjacent quads sharing interior edge (v1, v2).
## v0=(0,0,0) v1=(0,0,1) v2=(1,0,1) v3=(1,0,0) v4=(0,0,2) v5=(1,0,2)
## Face 0: [0,1,2,3]   Face 1: [1,4,5,2]
func _make_two_quads() -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [
		Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 1),
		Vector3(1, 0, 0), Vector3(0, 0, 2), Vector3(1, 0, 2),
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


## Cube with 6 faces. Vertex indices:
##   0=(0,0,0) 1=(1,0,0) 2=(1,0,1) 3=(0,0,1)
##   4=(0,1,0) 5=(1,1,0) 6=(1,1,1) 7=(0,1,1)
## Faces (CCW from outside):
##   Front: [0,1,5,4]  Right: [1,2,6,5]  Back: [2,3,7,6]
##   Left: [3,0,4,7]   Top: [4,5,6,7]    Bottom: [0,3,2,1]
func _make_cube() -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1),
		Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(0, 1, 1),
	]
	var faces_data: Array = [
		[0, 1, 5, 4],  # Front
		[1, 2, 6, 5],  # Right
		[2, 3, 7, 6],  # Back
		[3, 0, 4, 7],  # Left
		[4, 5, 6, 7],  # Top
		[0, 3, 2, 1],  # Bottom
	]
	for fd: Array in faces_data:
		var f := GoBuildFace.new()
		f.vertex_indices = []
		f.vertex_indices.assign(fd)
		f.uvs = []
		f.uvs.resize(fd.size())
		f.uvs.fill(Vector2.ZERO)
		mesh.faces.append(f)
	mesh.rebuild_edges()
	return mesh


# ---------------------------------------------------------------------------
# dissolve_edges tests
# ---------------------------------------------------------------------------

func test_dissolve_edge_merges_two_quads() -> void:
	var mesh := _make_two_quads()
	# Edge between v1 and v2 is the shared interior edge.
	var edge_idx: int = mesh.find_edge(1, 2)
	assert_bool(edge_idx >= 0, "Should find shared edge")
	DissolveOperation.dissolve_edges(mesh, [edge_idx])
	# Should merge into one face.
	assert_int(mesh.faces.size()).is_equal(1)
	# Should have 4 vertices (all unique, none removed by dissolve).
	assert_int(mesh.faces[0].vertex_indices.size()).is_equal(4)
	# The merged face should contain all 4 unique vertices.
	for vi: int in [0, 3, 4, 5]:
		assert_bool(mesh.faces[0].vertex_indices.has(vi),
				"Merged face should contain vertex %d" % vi)


func test_dissolve_edge_skips_boundary() -> void:
	var mesh := _make_two_quads()
	# Boundary edge (v0, v1) — only one adjacent face.
	var boundary_idx: int = mesh.find_edge(0, 1)
	assert_bool(boundary_idx >= 0, "Should find boundary edge")
	var face_count_before: int = mesh.faces.size()
	DissolveOperation.dissolve_edges(mesh, [boundary_idx])
	# Nothing should change.
	assert_int(mesh.faces.size()).is_equal(face_count_before)


func test_dissolve_edge_null_mesh() -> void:
	DissolveOperation.dissolve_edges(null, [0])
	# Should not crash.


func test_dissolve_edge_empty_indices() -> void:
	var mesh := GoBuildMesh.new()
	DissolveOperation.dissolve_edges(mesh, [])
	# Should not crash.


# ---------------------------------------------------------------------------
# dissolve_vertices tests
# ---------------------------------------------------------------------------

func test_dissolve_vertex_cube_corner_produces_hexagon() -> void:
	var mesh := _make_cube()
	# Vertex 1 (front-bottom-right corner) is shared by 3 faces: front, right, bottom.
	DissolveOperation.dissolve_vertices(mesh, [1])
	# 3 faces merged into 1, so 6 - 3 + 1 = 4 faces total.
	assert_int(mesh.faces.size()).is_equal(4)
	# Find the merged face (it should have 6 vertices — a hexagon).
	var merged: GoBuildFace = null
	for f: GoBuildFace in mesh.faces:
		if f.vertex_indices.size() == 6:
			merged = f
			break
	assert_not_null(merged, "Should find a hexagonal face")
	# The merged face should not contain vertex 1 (the dissolved vertex).
	assert_bool(not merged.vertex_indices.has(1), "Merged face should not contain dissolved vertex")


func test_dissolve_vertex_cube_corner_winding() -> void:
	var mesh := _make_cube()
	DissolveOperation.dissolve_vertices(mesh, [1])
	# Find the merged face.
	var merged: GoBuildFace = null
	for f: GoBuildFace in mesh.faces:
		if f.vertex_indices.size() == 6:
			merged = f
			break
	assert_not_null(merged, "Should find a hexagonal face")
	# Compute its normal — should point outward (positive Y or positive X-ish).
	var normal: Vector3 = mesh.compute_face_normal(merged)
	# The corner at vertex 1 (1,0,0) should produce a normal that points
	# roughly outward from the corner. It should have positive components
	# in the directions of the original faces (front=+Z, right=+X, bottom=-Y).
	assert_float(normal.x).is_greater(0.0, "Normal should point outward (+X)")
	assert_float(normal.z).is_greater(0.0, "Normal should point outward (+Z)")


func test_dissolve_vertex_skips_two_face_corner() -> void:
	var mesh := _make_two_quads()
	# Vertex 0 is only in face 0 — only 1 face. Should be skipped.
	var face_count_before: int = mesh.faces.size()
	DissolveOperation.dissolve_vertices(mesh, [0])
	assert_int(mesh.faces.size()).is_equal(face_count_before)


func test_dissolve_vertex_null_mesh() -> void:
	DissolveOperation.dissolve_vertices(null, [0])
	# Should not crash.


func test_dissolve_vertex_empty_indices() -> void:
	var mesh := GoBuildMesh.new()
	DissolveOperation.dissolve_vertices(mesh, [])
	# Should not crash.


func test_dissolve_vertex_compacts_removed_vertex() -> void:
	var mesh := _make_cube()
	DissolveOperation.dissolve_vertices(mesh, [1])
	# After compact, vertex 1 should be removed from the vertices array.
	# The remaining vertices should be re-indexed.
	assert_bool(mesh.vertices.size() < 8, "Dissolved vertex should be compacted away")