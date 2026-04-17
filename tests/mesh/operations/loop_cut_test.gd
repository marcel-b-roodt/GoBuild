## Loop cut operation tests — GdUnit4
##
## Tests for [LoopCutOperation.apply] covering:
##   - Vertex / face / edge counts after a single loop cut on a 2×1 quad strip.
##   - Vertex counts after a loop cut on a closed quad ring (single cube face-ring).
##   - Cut vertex positions at t = 0.5 (midpoint) are correct.
##   - Cut vertex positions at a non-default t value are correct.
##   - Adjacent faces in the ring share the cut vertex on their common edge
##     (no T-junctions — shared midpoints).
##   - Material and smooth-group inheritance on replacement quads.
##   - Non-quad faces in the ring stop the ring walk (face is left uncut).
##   - Boundary (open-ring) termination — ring stops at mesh boundary.
##   - Edge-case guards: empty selection, out-of-range index, null mesh.
##
## Mesh conventions:
##   _make_quad_strip(n)  — n quads in a row along the X axis in the XZ plane.
##   _make_closed_ring()  — four quads forming a closed ring (open-top cube).
##   _make_quad_with_tri()— one quad adjacent to one triangle (mixed topology).
extends GdUnitTestSuite

const _FACE_SCRIPT       := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT       := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT       := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _LOOP_CUT_SCRIPT   := preload("res://addons/go_build/mesh/operations/loop_cut_operation.gd")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Build a strip of [param n] unit quads along the X axis in the XZ plane.
## Each quad is [x, x+1] × [0, 1] in XZ.
##
## Vertex layout (n = 2):
##   0=(0,0,0)  1=(1,0,0)  2=(2,0,0)
##   3=(0,0,1)  4=(1,0,1)  5=(2,0,1)
##
## Faces:
##   f0 = [0, 1, 4, 3]  (left quad)
##   f1 = [1, 2, 5, 4]  (right quad)
func _make_quad_strip(n: int) -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	# Bottom row then top row.
	for xi: int in range(n + 1):
		mesh.vertices.append(Vector3(float(xi), 0.0, 0.0))
	for xi: int in range(n + 1):
		mesh.vertices.append(Vector3(float(xi), 0.0, 1.0))

	for qi: int in n:
		var v0: int = qi
		var v1: int = qi + 1
		var v2: int = qi + 1 + (n + 1)
		var v3: int = qi     + (n + 1)
		var face := GoBuildFace.new()
		face.vertex_indices = [v0, v1, v2, v3]
		face.uvs = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		mesh.faces.append(face)
	mesh.rebuild_edges()
	return mesh


## Return the edge index connecting va to vb (order-independent).
func _find_edge(mesh: GoBuildMesh, va: int, vb: int) -> int:
	for i: int in mesh.edges.size():
		if mesh.edges[i].connects(va, vb):
			return i
	return -1


## Four quads forming a closed horizontal ring (each quad is 1×1 in the XZ
## plane, one on each side of a 1×1 unit square column).
## This creates an open-top box without a bottom or top cap.
##
## Top ring vertices: 0=(0,1,0)  1=(1,1,0)  2=(1,1,1)  3=(0,1,1)
## Bottom ring verts: 4=(0,0,0)  5=(1,0,0)  6=(1,0,1)  7=(0,0,1)
##
## Faces (one per side, CCW from outside):
##   Front  (z=0): [0, 1, 5, 4]
##   Right  (x=1): [1, 2, 6, 5]
##   Back   (z=1): [2, 3, 7, 6]
##   Left   (x=0): [3, 0, 4, 7]
func _make_closed_ring() -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [
		Vector3(0.0, 1.0, 0.0),  # 0 top-front-left
		Vector3(1.0, 1.0, 0.0),  # 1 top-front-right
		Vector3(1.0, 1.0, 1.0),  # 2 top-back-right
		Vector3(0.0, 1.0, 1.0),  # 3 top-back-left
		Vector3(0.0, 0.0, 0.0),  # 4 bot-front-left
		Vector3(1.0, 0.0, 0.0),  # 5 bot-front-right
		Vector3(1.0, 0.0, 1.0),  # 6 bot-back-right
		Vector3(0.0, 0.0, 1.0),  # 7 bot-back-left
	]
	var front := GoBuildFace.new()
	front.vertex_indices = [0, 1, 5, 4]
	front.uvs = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var right := GoBuildFace.new()
	right.vertex_indices = [1, 2, 6, 5]
	right.uvs = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var back := GoBuildFace.new()
	back.vertex_indices = [2, 3, 7, 6]
	back.uvs = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var left := GoBuildFace.new()
	left.vertex_indices = [3, 0, 4, 7]
	left.uvs = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	mesh.faces.append(front)
	mesh.faces.append(right)
	mesh.faces.append(back)
	mesh.faces.append(left)
	mesh.rebuild_edges()
	return mesh


## One quad adjacent to one triangle sharing edge v1↔v2.
## Used to verify the ring walk stops at the non-quad face.
##
## Vertices:
##   0=(0,0,0) 1=(1,0,0) 2=(1,0,1) 3=(0,0,1)  — quad [0,1,2,3]
##   4=(2,0,0.5)                               — tri [1,4,2]
func _make_quad_with_tri() -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [
		Vector3(0.0, 0.0, 0.0),  # 0
		Vector3(1.0, 0.0, 0.0),  # 1
		Vector3(1.0, 0.0, 1.0),  # 2
		Vector3(0.0, 0.0, 1.0),  # 3
		Vector3(2.0, 0.0, 0.5),  # 4
	]
	var quad := GoBuildFace.new()
	quad.vertex_indices = [0, 1, 2, 3]
	quad.uvs = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var tri := GoBuildFace.new()
	tri.vertex_indices = [1, 4, 2]
	tri.uvs = [Vector2(0, 0), Vector2(1, 0), Vector2(0.5, 1)]
	mesh.faces.append(quad)
	mesh.faces.append(tri)
	mesh.rebuild_edges()
	return mesh


# ---------------------------------------------------------------------------
# Edge-case guards
# ---------------------------------------------------------------------------

func test_null_mesh_is_no_op() -> void:
	LoopCutOperation.apply(null, [0])  # Must not crash.


func test_empty_selection_is_no_op() -> void:
	var mesh := _make_quad_strip(2)
	var verts_before: int = mesh.vertices.size()
	var faces_before: int = mesh.faces.size()
	LoopCutOperation.apply(mesh, [])
	assert_int(mesh.vertices.size()).is_equal(verts_before)
	assert_int(mesh.faces.size()).is_equal(faces_before)


func test_out_of_range_index_is_no_op() -> void:
	var mesh := _make_quad_strip(1)
	var verts_before: int = mesh.vertices.size()
	LoopCutOperation.apply(mesh, [9999])
	assert_int(mesh.vertices.size()).is_equal(verts_before)


# ---------------------------------------------------------------------------
# Single loop cut on a 2-quad strip (open ring)
# ---------------------------------------------------------------------------
#
# Strip layout (n=2):
#   Verts: 0..5 (6 total).  Interior edge: v1↔v4
#   A loop cut across the strip seeded from the interior v1↔v4 edge should
#   walk one step in one direction only (the ring is open at both ends of the
#   strip), cutting all faces whose opposite edges align.
#
# Seeding the vertical middle edge (v1↔v4):
#   The entry edge in face 0 is v1↔v4 (actually v1 at pos=1, v4 at pos=2 in
#   [0,1,4,3]). The opposite edge is v3↔v0.  No next face beyond v3↔v0
#   (boundary). Other direction from seed: face 1, entry v1↔v4.  Opposite
#   edge v5↔v2. No next face (boundary).
#   So the ring is [face0, face1] — both get cut.
#
# After cutting both faces at t=0.5:
#   2 new cut verts added (one on v1↔v4 shared by both halves — shared key
#   means exactly 1 vertex). Plus one on v0↔v3 (face 0 entry) and one on
#   v2↔v5 (face 1 far edge). Total new verts = 3 (shared v1↔v4 midpoint,
#   v0↔v3 midpoint, v2↔v5 midpoint). Original 6 + 3 = 9.
#
# Wait — let me re-examine. The seed edge walks:
#   half_a starts from seed (va=1, vb=4): finds face containing edge 1↔4,
#     which has v0 forward as entry? Let me retrace:
#   The interior edge 1↔4 is shared by face0=[0,1,4,3] and face1=[1,2,5,4].
#   half_a picks face0 (first valid face). Entry va=1,vb=4. pos_a=1, next_a=2,
#   face.vertex_indices[2]=4=vb → forward=true. opp=(3,0). Walk next: edge 3↔0
#   is boundary (only face0) → next_fi=-1 → stops. half_a = [{face0, va=1, vb=4}]
#   half_b: va=4 vb=1. Finds face1=[1,2,5,4]. pos_a in face1: v4 is at pos=3,
#   next_a=(3+1)%4=0 → v1=entry_vb → forward=true.
#   opp=(1,2) → find edge 1↔2 or 2↔1. Edge 2↔5? No — opposite positions:
#   opp_va_pos=(3+2)%4=1 → v2, opp_vb_pos=(3+3)%4=2 → v5. So opposite edge is
#   v2↔v5 which is boundary → next_fi=-1 → stops.
#   half_b = [{face1, va=4, vb=1}]
#
# Combined (half_b reversed + half_a): [{face1,4,1}, {face0,1,4}]
# Dedup check: first=face1, last=face0 → different → no dedup. Ring = 2 faces.
#
# Cutting face1 {va=4, vb=1}:
#   pos_a: v4 at pos=3, next_a=v1=entry_vb → forward=true.
#   idx0=3(v4), idx1=0(v1), idx2=1(v2), idx3=2(v5)  [face1=[1,2,5,4]]
#   key01 = "1_4_0.500000" → m01 = lerp(v1, v4, 0.5) = (1, 0, 0.5) → idx 6
#     (v1 < v4 so lerp v1→v4)
#   key32 = "2_5_0.500000" → m32 = lerp(v2, v5, 0.5) = (1.5, 0, 0.5) → wait,
#     v2=(1,0,1), v5=(2,0,1). Actually for face1 = [1,2,5,4]:
#     idx3=v5=(2,0,1), idx2=v2=(1,0,1) → key = "2_5_..." → lerp v2 to v5 = (1.5,0,1)
#   Quad A = [v4, m01, m32, v5] = [4, 6, 7, 5] where 6=(1,0,0.5), 7=(1.5,0,1)
#   Wait I need to re-examine with the actual face = [1,2,5,4]:
#     idx0=3 → v3_of_face = face[3]=4, idx1=0 → face[0]=1,
#     idx2=1 → face[1]=2, idx3=2 → face[2]=5
#   So v0=4, v1=1, v2=2, v3=5.
#   key01: min(4,1)=1, max=4 → "1_4_..." → m01 = lerp(v1,v4,0.5) = (1,0,0)+(0,0,0)+...
#   actually v1=(1,0,0) v4=(1,0,1) → lerp = (1,0,0.5) → idx=6
#   key32: v3=5=(2,0,1), v2=2=(1,0,1). min=2,max=5. Lerp v2→v5 at 0.5 = (1.5,0,1) → idx=7
#   qa=[v0=4, m01=6, m32=7, v3=5] = [4,6,7,5]
#   qb=[m01=6, v1=1, v2=2, m32=7] = [6,1,2,7]
#
# Cutting face0 {va=1, vb=4}:
#   face0=[0,1,4,3]. pos_a: v1 at pos=1, next_a=v4=entry_vb → forward=true.
#   idx0=1(v1), idx1=2(v4), idx2=3(v3), idx3=0(v0)
#   v0=1(pos 1), v1=4(pos 2), v2=3(pos 3), v3=0(pos 0)
#   key01: min(1,4)=1 → "1_4_..." → already in cut_verts → m01=6 (shared!)
#   key32: v3=0=(0,0,0), v2=3=(0,0,1). min=0,max=3 → "0_3_..." → lerp v0→v3 = (0,0,0.5) → idx=8
#   qa=[v0=1, m01=6, m32=8, v3=0] = [1,6,8,0]
#   qb=[m01=6, v1=4, v2=3, m32=8] = [6,4,3,8]
#
# Total new verts: 6 + idx6 + idx7 + idx8 = 9. ✓
# Total faces: original 2 replaced (each → 2 new) = 4. ✓

func test_loop_cut_two_quad_strip_adds_three_vertices() -> void:
	var mesh := _make_quad_strip(2)
	# Seed from the interior edge v1↔v4.
	var ei: int = _find_edge(mesh, 1, 4)
	assert_int(ei).is_not_equal(-1)
	LoopCutOperation.apply(mesh, [ei])
	assert_int(mesh.vertices.size()).is_equal(9)


func test_loop_cut_two_quad_strip_produces_four_faces() -> void:
	var mesh := _make_quad_strip(2)
	var ei: int = _find_edge(mesh, 1, 4)
	LoopCutOperation.apply(mesh, [ei])
	assert_int(mesh.faces.size()).is_equal(4)


func test_loop_cut_two_quad_strip_all_faces_are_quads() -> void:
	var mesh := _make_quad_strip(2)
	var ei: int = _find_edge(mesh, 1, 4)
	LoopCutOperation.apply(mesh, [ei])
	for face in mesh.faces:
		assert_int((face as GoBuildFace).vertex_indices.size()).is_equal(4)


# ---------------------------------------------------------------------------
# Shared cut vertex on common edge (no T-junctions)
# ---------------------------------------------------------------------------

func test_shared_midpoint_on_interior_edge() -> void:
	# After cutting the 2-quad strip at v1↔v4, both resulting face pairs should
	# share the midpoint vertex (index 6 at position (1, 0, 0.5)).
	var mesh := _make_quad_strip(2)
	var ei: int = _find_edge(mesh, 1, 4)
	LoopCutOperation.apply(mesh, [ei])
	# Find vertex at (1, 0, 0.5).
	var shared_idx: int = -1
	for vi: int in mesh.vertices.size():
		var v: Vector3 = mesh.vertices[vi]
		if v.distance_to(Vector3(1.0, 0.0, 0.5)) < 0.001:
			shared_idx = vi
			break
	assert_int(shared_idx).is_not_equal(-1)
	# The shared vertex should appear in exactly 2 faces after the cut.
	var face_count_with_shared: int = 0
	for face in mesh.faces:
		if (face as GoBuildFace).vertex_indices.has(shared_idx):
			face_count_with_shared += 1
	assert_int(face_count_with_shared).is_equal(2)


# ---------------------------------------------------------------------------
# Cut vertex position at t = 0.5 (midpoint)
# ---------------------------------------------------------------------------

func test_cut_vertex_at_midpoint() -> void:
	# Cut the boundary edge v0↔v3 side of a single quad.
	# Seeding from boundary edge v0↔v3 in a 1-quad mesh: the ring has only
	# that one face, the entry edge is v0↔v3 and opposite is v1↔v2.
	# New verts: midpoint(v0, v3) = (0, 0, 0.5) and midpoint(v1, v2) = (1, 0, 0.5).
	var mesh := _make_quad_strip(1)
	# Quad 0 = [0, 1, 2, 3] where 2=(1,0,1) and 3=(0,0,1).
	# Edge v0↔v3 is boundary (left edge).
	var ei: int = _find_edge(mesh, 0, 3)
	assert_int(ei).is_not_equal(-1)
	LoopCutOperation.apply(mesh, [ei])
	# Expect a vertex at (0, 0, 0.5).
	var found_left: bool = false
	for v: Vector3 in mesh.vertices:
		if v.distance_to(Vector3(0.0, 0.0, 0.5)) < 0.001:
			found_left = true
	assert_bool(found_left).is_true()
	# Expect a vertex at (1, 0, 0.5).
	var found_right: bool = false
	for v: Vector3 in mesh.vertices:
		if v.distance_to(Vector3(1.0, 0.0, 0.5)) < 0.001:
			found_right = true
	assert_bool(found_right).is_true()


# ---------------------------------------------------------------------------
# Cut vertex position at non-default t
# ---------------------------------------------------------------------------

func test_cut_vertex_at_custom_t() -> void:
	var mesh := _make_quad_strip(1)
	var ei: int = _find_edge(mesh, 0, 3)  # Left boundary edge.
	LoopCutOperation.apply(mesh, [ei], 0.25)
	# Midpoint on v0(0,0,0)→v3(0,0,1) at t=0.25: canonical lerp from lower to
	# higher index → v0 < v3, lerp(v0, v3, 0.25) = (0, 0, 0.25).
	var found: bool = false
	for v: Vector3 in mesh.vertices:
		if v.distance_to(Vector3(0.0, 0.0, 0.25)) < 0.001:
			found = true
	assert_bool(found).is_true()


# ---------------------------------------------------------------------------
# Closed ring — vertex and face counts
# ---------------------------------------------------------------------------
#
# _make_closed_ring() has 4 quad faces (front, right, back, left), 8 vertices,
# and all vertical edges are interior (each shared by 2 faces in the ring).
# A loop cut seeded from any vertical edge should cut all 4 faces.
# New verts: 4 cut vertices (one per vertical edge) = 8 + 4 = 12.
# Faces: 4 original × 2 replacement = 8.

func test_loop_cut_closed_ring_vertex_count() -> void:
	var mesh := _make_closed_ring()
	# Any vertical edge will do.  The front face has edges 0↔1, 1↔5, 5↔4, 4↔0.
	# Edge 0↔1 is horizontal (top); 4↔5 is horizontal (bottom).
	# Vertical edges: 0↔4, 1↔5.
	var ei: int = _find_edge(mesh, 0, 4)
	assert_int(ei).is_not_equal(-1)
	LoopCutOperation.apply(mesh, [ei])
	assert_int(mesh.vertices.size()).is_equal(12)


func test_loop_cut_closed_ring_face_count() -> void:
	var mesh := _make_closed_ring()
	var ei: int = _find_edge(mesh, 0, 4)
	LoopCutOperation.apply(mesh, [ei])
	assert_int(mesh.faces.size()).is_equal(8)


func test_loop_cut_closed_ring_all_faces_are_quads() -> void:
	var mesh := _make_closed_ring()
	var ei: int = _find_edge(mesh, 0, 4)
	LoopCutOperation.apply(mesh, [ei])
	for face in mesh.faces:
		assert_int((face as GoBuildFace).vertex_indices.size()).is_equal(4)


# ---------------------------------------------------------------------------
# Ring stops at non-quad face
# ---------------------------------------------------------------------------

func test_ring_stops_at_triangle() -> void:
	# _make_quad_with_tri: quad [0,1,2,3] adjacent to tri [1,4,2] at edge 1↔2.
	# Seeding from edge 1↔2 (shared interior edge): the ring should cut only the
	# quad face (found by walking from v1→v2 side). The triangle is a non-quad →
	# walk stops without cutting it.
	var mesh := _make_quad_with_tri()
	var ei: int = _find_edge(mesh, 1, 2)
	assert_int(ei).is_not_equal(-1)
	LoopCutOperation.apply(mesh, [ei])
	# The quad was cut into 2. The triangle is unchanged.
	# Vertex count: original 5 + 2 new cut verts (on entry edge + opposite edge) = 7.
	assert_int(mesh.vertices.size()).is_equal(7)
	# Face count: 1 quad → 2 quads + 1 original tri = 3.
	assert_int(mesh.faces.size()).is_equal(3)
	# The triangle face should still have 3 vertices.
	var tri_found: bool = false
	for face in mesh.faces:
		if (face as GoBuildFace).vertex_indices.size() == 3:
			tri_found = true
	assert_bool(tri_found).is_true()


# ---------------------------------------------------------------------------
# Material and smooth-group inheritance
# ---------------------------------------------------------------------------

func test_replacement_quads_inherit_material_index() -> void:
	var mesh := _make_quad_strip(1)
	mesh.faces[0].material_index = 3
	var ei: int = _find_edge(mesh, 0, 3)
	LoopCutOperation.apply(mesh, [ei])
	for face in mesh.faces:
		assert_int((face as GoBuildFace).material_index).is_equal(3)


func test_replacement_quads_inherit_smooth_group() -> void:
	var mesh := _make_quad_strip(1)
	mesh.faces[0].smooth_group = 2
	var ei: int = _find_edge(mesh, 0, 3)
	LoopCutOperation.apply(mesh, [ei])
	for face in mesh.faces:
		assert_int((face as GoBuildFace).smooth_group).is_equal(2)


# ---------------------------------------------------------------------------
# Undo-safe: rebuild_edges is called after apply
# ---------------------------------------------------------------------------

func test_rebuild_edges_called_after_cut() -> void:
	# After a loop cut the edge count should be consistent with the new geometry
	# (each quad has 4 edges; shared edges counted once).  For a 2-quad result
	# from a 1-quad input that was cut at the left boundary edge:
	# 2 quads × 4 edges − 1 shared interior = 7 edges.
	var mesh := _make_quad_strip(1)
	var ei: int = _find_edge(mesh, 0, 3)
	LoopCutOperation.apply(mesh, [ei])
	# After cut: 2 quads → 7 edges (outer boundary 6 + 1 shared interior).
	assert_int(mesh.edges.size()).is_equal(7)
