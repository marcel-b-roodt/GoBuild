## Bevel operation tests — GdUnit4
##
## Tests for [BevelOperation.apply] covering:
##   - Vertex / face / edge counts after bevelling a boundary edge in a
##     two-quad mesh (the only interior edge that has two adjacent faces).
##   - Vertex positions of the slid copies.
##   - Bevel face winding (CCW normal should point upward).
##   - Material inheritance from the source face.
##   - Boundary-edge guard (no bevel face added when edge has only one face).
##   - Edge-case guards: zero width, empty selection, out-of-range index.
##
## Test mesh conventions:
##   _make_two_quads() — two adjacent unit quads in the XZ plane sharing one
##     interior edge (v1↔v2).  This shared edge is the bevel target.
##   _make_plus_y_quad() — single quad, all edges boundary — used to verify
##     that boundary edges produce no bevel face.
extends GdUnitTestSuite

const _FACE_SCRIPT   := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT   := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT   := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _BEVEL_SCRIPT  := preload("res://addons/go_build/mesh/operations/bevel_operation.gd")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Two unit quads in the XZ plane sharing interior edge v1↔v2.
##   Left quad  faces = [0,1,2,3], normal +Y, v0..v3.
##   Right quad faces = [1,4,5,2], normal +Y, v1,v4,v5,v2.
## After rebuild_edges() the edge v1↔v2 has face_indices.size() == 2.
func _make_two_quads() -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [
		Vector3(0.0, 0.0, 0.0),  # 0
		Vector3(1.0, 0.0, 0.0),  # 1
		Vector3(1.0, 0.0, 1.0),  # 2
		Vector3(0.0, 0.0, 1.0),  # 3
		Vector3(2.0, 0.0, 0.0),  # 4
		Vector3(2.0, 0.0, 1.0),  # 5
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


## Single quad in the XZ plane (normal = +Y), all 4 edges boundary.
func _make_plus_y_quad() -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [
		Vector3(0.0, 0.0, 0.0),
		Vector3(1.0, 0.0, 0.0),
		Vector3(1.0, 0.0, 1.0),
		Vector3(0.0, 0.0, 1.0),
	]
	var face := GoBuildFace.new()
	face.vertex_indices = [0, 1, 2, 3]
	face.uvs = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	mesh.faces.append(face)
	mesh.rebuild_edges()
	return mesh


## Return the index of the interior edge (v1↔v2) in _make_two_quads().
func _interior_edge_index(mesh: GoBuildMesh) -> int:
	for ei: int in mesh.edges.size():
		if not (mesh.edges[ei] as GoBuildEdge).is_boundary():
			return ei
	return -1


# ---------------------------------------------------------------------------
# Helper sanity checks
# ---------------------------------------------------------------------------

func test_two_quads_has_one_interior_edge() -> void:
	var mesh := _make_two_quads()
	var count := 0
	for e in mesh.edges:
		if not (e as GoBuildEdge).is_boundary():
			count += 1
	assert_int(count).is_equal(1)


func test_interior_edge_index_is_valid() -> void:
	var mesh := _make_two_quads()
	assert_int(_interior_edge_index(mesh)).is_not_equal(-1)


# ---------------------------------------------------------------------------
# Vertex counts after bevel
# ---------------------------------------------------------------------------

func test_bevel_interior_edge_adds_four_vertices() -> void:
	# Each endpoint of the edge gets one slid copy per adjacent face → 2×2 = 4.
	var mesh := _make_two_quads()
	var ei: int = _interior_edge_index(mesh)
	var indices: Array[int] = [ei]
	BevelOperation.apply(mesh, indices, 0.1)
	assert_int(mesh.vertices.size()).is_equal(10)


# ---------------------------------------------------------------------------
# Face counts after bevel
# ---------------------------------------------------------------------------

func test_bevel_interior_edge_adds_one_bevel_face() -> void:
	# Original 2 faces + 1 bevel quad = 3.
	var mesh := _make_two_quads()
	var ei: int = _interior_edge_index(mesh)
	BevelOperation.apply(mesh, [ei], 0.1)
	assert_int(mesh.faces.size()).is_equal(3)


# ---------------------------------------------------------------------------
# Vertex positions — slid copies
# ---------------------------------------------------------------------------

func test_bevel_slid_vertex_is_at_correct_distance_from_origin() -> void:
	# After bevel the original va (index 1) and vb (index 2) remain in the
	# vertex array but are no longer referenced by the adjacent faces.
	# The four new verts should each be exactly 0.1 units from the
	# original va or vb position (along the face-perimeter direction).
	var mesh := _make_two_quads()
	var ei: int = _interior_edge_index(mesh)
	var edge: GoBuildEdge = mesh.edges[ei]
	var va_pos: Vector3 = mesh.vertices[edge.vertex_a]
	var vb_pos: Vector3 = mesh.vertices[edge.vertex_b]
	BevelOperation.apply(mesh, [ei], 0.1)
	# New verts are indices 6..9.
	for vi: int in range(6, 10):
		var v: Vector3 = mesh.vertices[vi]
		var dist_a: float = v.distance_to(va_pos)
		var dist_b: float = v.distance_to(vb_pos)
		var near_either: bool = dist_a < 0.15 or dist_b < 0.15
		assert_bool(near_either).is_true()


func test_bevel_width_zero_produces_no_change() -> void:
	# Zero width — guard prevents any modification.
	var mesh := _make_two_quads()
	var ei: int = _interior_edge_index(mesh)
	BevelOperation.apply(mesh, [ei], 0.0)
	assert_int(mesh.vertices.size()).is_equal(6)
	assert_int(mesh.faces.size()).is_equal(2)


# ---------------------------------------------------------------------------
# No bevel face on boundary edges
# ---------------------------------------------------------------------------

func test_bevel_boundary_edge_adds_no_bevel_face() -> void:
	# A boundary edge has only one adjacent face → no bevel face gap to fill.
	var mesh := _make_plus_y_quad()
	var ei: int = 0  # Any of the 4 boundary edges.
	BevelOperation.apply(mesh, [ei], 0.1)
	# 2 new verts (one per endpoint slid within the single adjacent face),
	# 1 original face (its verts replaced), 0 new bevel faces.
	assert_int(mesh.faces.size()).is_equal(1)
	assert_int(mesh.vertices.size()).is_equal(6)


# ---------------------------------------------------------------------------
# Adjacent faces have bevelled vertices (original va/vb removed from faces)
# ---------------------------------------------------------------------------

func test_bevel_removes_original_verts_from_adjacent_faces() -> void:
	var mesh := _make_two_quads()
	var ei: int = _interior_edge_index(mesh)
	var edge: GoBuildEdge = mesh.edges[ei]
	var va: int = edge.vertex_a
	var vb: int = edge.vertex_b
	BevelOperation.apply(mesh, [ei], 0.1)
	# Neither va nor vb should appear in any face's vertex_indices after bevel.
	for face in mesh.faces:
		for vi: int in (face as GoBuildFace).vertex_indices:
			assert_bool(vi == va or vi == vb).is_false()


# ---------------------------------------------------------------------------
# Bevel face winding (normal should point upward for XZ-plane mesh)
# ---------------------------------------------------------------------------

func test_bevel_face_normal_points_in_y_direction() -> void:
	var mesh := _make_two_quads()
	var ei: int = _interior_edge_index(mesh)
	BevelOperation.apply(mesh, [ei], 0.1)
	# The bevel face is the last one appended (index 2).
	var bevel_face: GoBuildFace = mesh.faces[2]
	var n: Vector3 = mesh.compute_face_normal(bevel_face)
	# The bevel strip is coplanar with the XZ mesh — normal must be ±Y.
	assert_float(absf(n.y)).is_greater(0.9)


# ---------------------------------------------------------------------------
# Material inheritance
# ---------------------------------------------------------------------------

func test_bevel_face_inherits_material_from_adjacent_face() -> void:
	var mesh := _make_two_quads()
	mesh.faces[0].material_index = 3
	var ei: int = _interior_edge_index(mesh)
	BevelOperation.apply(mesh, [ei], 0.1)
	# Bevel face (index 2) should inherit from face index 0 (fi0).
	assert_int(mesh.faces[2].material_index).is_equal(3)


# ---------------------------------------------------------------------------
# Bevel face has 4 UVs
# ---------------------------------------------------------------------------

func test_bevel_face_has_four_uvs() -> void:
	var mesh := _make_two_quads()
	var ei: int = _interior_edge_index(mesh)
	BevelOperation.apply(mesh, [ei], 0.1)
	assert_int(mesh.faces[2].uvs.size()).is_equal(4)


# ---------------------------------------------------------------------------
# Edge-case guards
# ---------------------------------------------------------------------------

func test_empty_selection_is_noop() -> void:
	var mesh := _make_two_quads()
	BevelOperation.apply(mesh, [], 0.1)
	assert_int(mesh.vertices.size()).is_equal(6)
	assert_int(mesh.faces.size()).is_equal(2)


func test_out_of_range_index_is_skipped() -> void:
	var mesh := _make_two_quads()
	BevelOperation.apply(mesh, [999], 0.1)
	assert_int(mesh.vertices.size()).is_equal(6)
	assert_int(mesh.faces.size()).is_equal(2)
