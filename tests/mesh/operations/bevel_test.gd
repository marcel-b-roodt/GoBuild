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
const _CUBE_GEN      := preload("res://addons/go_build/mesh/generators/cube_generator.gd")


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


## Plain welded cube — single edge bevel should add exactly 1 strip face,
## 2 N-gon faces (corner non-plan grow), and 4 new slid vertices.
## 6 original verts → 2 endpoints compacted out → +4 slid = 8 total verts.
## 6 original faces → 2 corner faces expand to N-gons (no extra), +1 strip = 7 total.
func _make_cube() -> GoBuildMesh:
	return CubeGenerator.generate(1.0, 1.0, 1.0)


func test_bevel_cube_edge_adds_one_strip_face() -> void:
	# Beveling a single edge of a plain cube should add exactly 1 new face (strip).
	# The two non-plan corner faces grow in-place as N-gons (no extra faces).
	var mesh := _make_cube()
	# Pick any non-boundary interior edge.
	var ei: int = -1
	for i: int in mesh.edges.size():
		if not (mesh.edges[i] as GoBuildEdge).is_boundary():
			ei = i
			break
	assert_int(ei).is_not_equal(-1)
	BevelOperation.apply(mesh, [ei], 0.1)
	assert_int(mesh.faces.size()).is_equal(7)


func test_bevel_cube_edge_vertex_count() -> void:
	# 8 original cube verts → 2 compacted out → +4 slid = 10 total.
	var mesh := _make_cube()
	var ei: int = -1
	for i: int in mesh.edges.size():
		if not (mesh.edges[i] as GoBuildEdge).is_boundary():
			ei = i
			break
	BevelOperation.apply(mesh, [ei], 0.1)
	assert_int(mesh.vertices.size()).is_equal(10)


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


# ---------------------------------------------------------------------------
# Loop-cut FULL CUBE — outer edge bevel (the "left edge" scenario)
# ---------------------------------------------------------------------------
# A full 6-face cube with a horizontal loop cut retains the original top outer
# edges.  Beveling such an edge involves a T-junction at each endpoint because
# one of the slide neighbours is an inner-ring midpoint vertex (4 faces).
# The correct result is 1 strip + 2 cap faces = 3 new faces → 16 total
# (12 existing after loop cut, +3 new).  There should be NO open holes.

## Full welded cube with a horizontal loop cut at y=0 (mid-height for unit cube).
## Returns the mesh AFTER the loop cut is applied.
func _make_loop_cut_full_cube() -> GoBuildMesh:
	var mesh := CubeGenerator.generate(1.0, 1.0, 1.0)
	# Find a vertical edge on the front face to seed the loop cut.
	# Front face is at Z=0.5.  Vertical edges connect top Y=0.5 and bottom Y=-0.5.
	var seed_ei: int = -1
	for ei: int in mesh.edges.size():
		var e: GoBuildEdge = mesh.edges[ei] as GoBuildEdge
		var va_pos: Vector3 = mesh.vertices[e.vertex_a]
		var vb_pos: Vector3 = mesh.vertices[e.vertex_b]
		# Vertical edge: same X and Z, different Y.
		if absf(va_pos.x - vb_pos.x) < 1e-4 \
				and absf(va_pos.z - vb_pos.z) < 1e-4 \
				and absf(va_pos.y - vb_pos.y) > 0.9:
			seed_ei = ei
			break
	assert_int(seed_ei).is_not_equal(-1)
	var seed_arr: Array[int] = [seed_ei]
	LoopCutOperation.apply(mesh, seed_arr, 0.5)
	return mesh


func test_loop_cut_full_cube_face_count() -> void:
	# After loop cut: 6 original faces; the loop cut on a vertical ring edge
	# splits only the 4 side faces (top and bottom stay whole) → 6-4+8 = 10 faces.
	var mesh := _make_loop_cut_full_cube()
	assert_int(mesh.faces.size()).is_equal(10)


func test_bevel_outer_top_edge_of_loop_cut_cube_face_count() -> void:
	# Bevel one of the original outer top edges of a loop-cut cube.
	# Both endpoints are cube corners (3-face vertices) with 1 non-plan face
	# each, so the N-gon approach applies: 10 original + 1 strip = 11 faces.
	var mesh := _make_loop_cut_full_cube()
	var target_ei: int = -1
	for ei: int in mesh.edges.size():
		var e: GoBuildEdge = mesh.edges[ei] as GoBuildEdge
		if e.face_indices.size() != 2:
			continue
		var va_pos: Vector3 = mesh.vertices[e.vertex_a]
		var vb_pos: Vector3 = mesh.vertices[e.vertex_b]
		if va_pos.y > 0.4 and vb_pos.y > 0.4 and absf(va_pos.y - vb_pos.y) < 1e-4:
			target_ei = ei
			break
	assert_int(target_ei).is_not_equal(-1)
	BevelOperation.apply(mesh, [target_ei], 0.1)
	assert_int(mesh.faces.size()).is_equal(11)


func test_bevel_inner_ring_edge_of_loop_cut_cube_face_count() -> void:
	# Bevel one inner ring edge of the loop-cut full cube.
	# Each endpoint is a 4-face midpoint vertex with 2 non-plan faces → cap approach.
	# Expected: 10 original + 1 strip + 2 cap triangles = 13 total.
	var mesh := _make_loop_cut_full_cube()
	# Inner ring edge: both endpoints at Y=0 (midpoints created by loop cut).
	var target_ei: int = -1
	for ei: int in mesh.edges.size():
		var e: GoBuildEdge = mesh.edges[ei] as GoBuildEdge
		if e.face_indices.size() != 2:
			continue
		var va_pos: Vector3 = mesh.vertices[e.vertex_a]
		var vb_pos: Vector3 = mesh.vertices[e.vertex_b]
		# Inner ring edge: both endpoints at Y=0, horizontal.
		if absf(va_pos.y) < 1e-4 and absf(vb_pos.y) < 1e-4 \
				and absf(va_pos.y - vb_pos.y) < 1e-4:
			target_ei = ei
			break
	assert_int(target_ei).is_not_equal(-1)
	BevelOperation.apply(mesh, [target_ei], 0.1)
	assert_int(mesh.faces.size()).is_equal(13)


func test_bevel_inner_ring_edge_cap_anchor_not_at_original_position() -> void:
	# After beveling an inner ring edge, the cap anchor vertex should sit
	# between vi and W (not at vi or W exactly).  This verifies the W vertex
	# was found correctly — if W is wrong the anchor would land in the wrong place.
	var mesh := _make_loop_cut_full_cube()
	var target_ei: int = -1
	for ei: int in mesh.edges.size():
		var e: GoBuildEdge = mesh.edges[ei] as GoBuildEdge
		if e.face_indices.size() != 2:
			continue
		var va_pos: Vector3 = mesh.vertices[e.vertex_a]
		var vb_pos: Vector3 = mesh.vertices[e.vertex_b]
		if absf(va_pos.y) < 1e-4 and absf(vb_pos.y) < 1e-4:
			target_ei = ei
			break
	var orig_vc: int = mesh.vertices.size()
	assert_int(target_ei).is_not_equal(-1)
	BevelOperation.apply(mesh, [target_ei], 0.1)
	# After compaction, count vertices at Y=0 (on the inner ring plane).
	# Original inner ring had 4 vertices at Y=0.  After bevel of one edge:
	# the two endpoints are replaced by their slid copies and anchor vertices.
	# The anchor vertices must also be at Y=0 (they lie on the inner ring).
	var y0_count: int = 0
	for vi: int in mesh.vertices.size():
		if absf(mesh.vertices[vi].y) < 0.05:
			y0_count += 1
	# Must have at least the 4 original ring verts (some replaced) + anchor verts.
	assert_int(y0_count).is_greater_equal(4)


func test_bevel_all_inner_ring_edges_of_loop_cut_cube() -> void:
	# Each of the 4 inner ring edges should produce 13 faces when beveled.
	# If any produces a different count, the cap W-vertex detection is wrong for that edge.
	var ring_edges: Array[int] = []
	var base_mesh := _make_loop_cut_full_cube()
	for ei: int in base_mesh.edges.size():
		var e: GoBuildEdge = base_mesh.edges[ei] as GoBuildEdge
		if e.face_indices.size() != 2:
			continue
		var va_pos: Vector3 = base_mesh.vertices[e.vertex_a]
		var vb_pos: Vector3 = base_mesh.vertices[e.vertex_b]
		if absf(va_pos.y) < 1e-4 and absf(vb_pos.y) < 1e-4:
			ring_edges.append(ei)
	assert_int(ring_edges.size()).is_equal(4)
	for ei: int in ring_edges:
		var mesh := _make_loop_cut_full_cube()
		BevelOperation.apply(mesh, [ei], 0.1)
		assert_int(mesh.faces.size()).is_equal(13)
		# All faces must have at most 5 vertices (quads grown by anchor insert).
		for fi: int in mesh.faces.size():
			assert_int(mesh.faces[fi].vertex_indices.size()).is_less_equal(5)


func test_bevel_inner_ring_edge_cap_no_duplicate_vertices() -> void:
	# The cap triangle added at each bevel endpoint must have 3 DISTINCT vertex
	# indices.  If _sort_entries_ccw chooses the same slid copy for both non-plan
	# faces, the cap becomes [sA, sA, anchor] — a degenerate zero-area face.
	# This test catches that regression by verifying no face has duplicate verts.
	var ring_edges: Array[int] = []
	var base_mesh := _make_loop_cut_full_cube()
	for ei: int in base_mesh.edges.size():
		var e: GoBuildEdge = base_mesh.edges[ei] as GoBuildEdge
		if e.face_indices.size() != 2:
			continue
		var va_pos: Vector3 = base_mesh.vertices[e.vertex_a]
		var vb_pos: Vector3 = base_mesh.vertices[e.vertex_b]
		if absf(va_pos.y) < 1e-4 and absf(vb_pos.y) < 1e-4:
			ring_edges.append(ei)
	assert_int(ring_edges.size()).is_equal(4)
	for ei: int in ring_edges:
		var mesh := _make_loop_cut_full_cube()
		BevelOperation.apply(mesh, [ei], 0.1)
		for fi: int in mesh.faces.size():
			var vis: Array = []
			for vi: int in mesh.faces[fi].vertex_indices:
				vis.append(vi)
			var unique: Dictionary = {}
			for vi: int in vis:
				unique[vi] = true
			assert_int(unique.size()).is_equal(vis.size())
