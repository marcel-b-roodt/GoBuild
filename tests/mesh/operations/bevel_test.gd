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
	# Each endpoint of the edge gets one slid copy per adjacent face → 2×2 = 4 new verts.
	# The 2 original edge endpoints are orphaned and removed by compaction.
	# Net: 6 original − 2 orphans + 4 slid = 8.
	var mesh := _make_two_quads()
	var ei: int = _interior_edge_index(mesh)
	var indices: Array[int] = [ei]
	BevelOperation.apply(mesh, indices, 0.1)
	assert_int(mesh.vertices.size()).is_equal(8)


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
	# The four slid verts should each be within 0.15 units of the original
	# va or vb position.  Original va/vb are removed by compaction so we
	# capture their positions BEFORE the bevel is applied.
	var mesh := _make_two_quads()
	var ei: int = _interior_edge_index(mesh)
	var edge: GoBuildEdge = mesh.edges[ei]
	var va_pos: Vector3 = mesh.vertices[edge.vertex_a]
	var vb_pos: Vector3 = mesh.vertices[edge.vertex_b]
	BevelOperation.apply(mesh, [ei], 0.1)
	# Exactly 4 of the 8 remaining vertices should be close to va or vb.
	var close_count: int = 0
	for vi: int in mesh.vertices.size():
		var v: Vector3 = mesh.vertices[vi]
		if v.distance_to(va_pos) < 0.15 or v.distance_to(vb_pos) < 0.15:
			close_count += 1
	assert_int(close_count).is_equal(4)


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
	# The 2 original endpoints are orphaned and removed by compaction,
	# leaving 4 + 2 - 2 = 4 vertices.
	assert_int(mesh.faces.size()).is_equal(1)
	assert_int(mesh.vertices.size()).is_equal(4)


# ---------------------------------------------------------------------------
# Adjacent faces have bevelled vertices (original va/vb removed from faces)
# ---------------------------------------------------------------------------

func test_bevel_removes_original_verts_from_adjacent_faces() -> void:
	# Capture the original positions of va/vb before bevel.
	var mesh := _make_two_quads()
	var ei: int = _interior_edge_index(mesh)
	var edge: GoBuildEdge = mesh.edges[ei]
	var va_pos: Vector3 = mesh.vertices[edge.vertex_a]
	var vb_pos: Vector3 = mesh.vertices[edge.vertex_b]
	BevelOperation.apply(mesh, [ei], 0.1)
	# After compaction, no vertex should sit exactly at the original va/vb
	# positions (the originals were orphaned and removed).
	for vi: int in mesh.vertices.size():
		var v: Vector3 = mesh.vertices[vi]
		assert_bool(
				v.distance_to(va_pos) < 1e-4 or v.distance_to(vb_pos) < 1e-4
		).is_false()


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


# ---------------------------------------------------------------------------
# Loop-cut ring bevel — cap faces at T-junction endpoints
# ---------------------------------------------------------------------------
# A closed 4-face ring (like an open-top/bottom cube column) with a horizontal
# loop cut applied at y=0.5 produces 8 faces.  The inner horizontal edges each
# have two plan faces (the two halves of one original quad) and two non-plan
# faces (the two halves of the neighbouring original quad).
#
# After the cut (t=0.5 on vertical edges of the ring):
#   Vertices 0-7 as in _make_closed_ring (y=1 top, y=0 bottom).
#   New mid-ring vertices: 8=(0,0.5,0) 9=(1,0.5,0) 10=(1,0.5,1) 11=(0,0.5,1)
#   8 new faces (2 per original face): see _make_loop_cut_ring below.
#
# Bevelling edge 8↔9 (front inner horizontal):
#   • 2 plan faces: front-top [8,0,1,9] and front-bot [4,8,9,5]
#   • At v8: 2 non-plan faces (left-top [11,3,0,8] and left-bot [7,11,8,4])
#     → cap needed, W = v11
#   • At v9: 2 non-plan faces (right-top [9,1,2,10] and right-bot [5,9,10,6])
#     → cap needed, W = v10
#   Expected result: 1 bevel strip + 2 cap triangles = 3 new faces → 11 total.

## Flat closed ring (4 side faces, no top/bottom) after a horizontal loop cut.
## Produces the T-junction topology needed to exercise bevel endpoint caps.
func _make_loop_cut_ring() -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [
		Vector3(0.0, 1.0, 0.0),  # 0  TFL
		Vector3(1.0, 1.0, 0.0),  # 1  TFR
		Vector3(1.0, 1.0, 1.0),  # 2  TBR
		Vector3(0.0, 1.0, 1.0),  # 3  TBL
		Vector3(0.0, 0.0, 0.0),  # 4  BFL
		Vector3(1.0, 0.0, 0.0),  # 5  BFR
		Vector3(1.0, 0.0, 1.0),  # 6  BBR
		Vector3(0.0, 0.0, 1.0),  # 7  BBL
		Vector3(0.0, 0.5, 0.0),  # 8  MFL
		Vector3(1.0, 0.5, 0.0),  # 9  MFR
		Vector3(1.0, 0.5, 1.0),  # 10 MBR
		Vector3(0.0, 0.5, 1.0),  # 11 MBL
	]
	var add_quad := func(a: int, b: int, c: int, d: int) -> void:
		var f := GoBuildFace.new()
		f.vertex_indices = [a, b, c, d]
		f.uvs = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		mesh.faces.append(f)
	# Top halves
	add_quad.call(8,  0, 1,  9)   # 0 front-top
	add_quad.call(9,  1, 2, 10)   # 1 right-top
	add_quad.call(10, 2, 3, 11)   # 2 back-top
	add_quad.call(11, 3, 0,  8)   # 3 left-top
	# Bottom halves
	add_quad.call(4,  8,  9, 5)   # 4 front-bot
	add_quad.call(5,  9, 10, 6)   # 5 right-bot
	add_quad.call(6, 10, 11, 7)   # 6 back-bot
	add_quad.call(7, 11,  8, 4)   # 7 left-bot
	mesh.rebuild_edges()
	return mesh


func test_bevel_loop_cut_inner_edge_creates_strip_and_two_caps() -> void:
	# Bevel the front inner edge 8↔9.  Expected:
	#   - 1 bevel strip face
	#   - 2 cap triangle faces (one per endpoint)
	#   → 8 original + 3 new = 11 total faces
	var mesh := _make_loop_cut_ring()
	var ei: int = mesh.find_edge(8, 9)
	assert_int(ei).is_not_equal(-1)
	BevelOperation.apply(mesh, [ei], 0.1)
	assert_int(mesh.faces.size()).is_equal(11)


func test_bevel_loop_cut_strip_face_has_correct_normal() -> void:
	# The bevel strip for front inner edge 8↔9 should face outward (+Z direction).
	var mesh := _make_loop_cut_ring()
	var ei: int = mesh.find_edge(8, 9)
	BevelOperation.apply(mesh, [ei], 0.1)
	# Strip is the 9th face (index 8) — the first new face added after the 8 original.
	var found_front_normal := false
	for fi: int in mesh.faces.size():
		var n: Vector3 = mesh.compute_face_normal(mesh.faces[fi])
		if n.z > 0.9:
			found_front_normal = true
			break
	assert_bool(found_front_normal).is_true()
