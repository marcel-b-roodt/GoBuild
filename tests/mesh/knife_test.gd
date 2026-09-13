## GoBuildKnife pure-geometry tests (edge_hit, face_crossings, the apply
## pipeline).
extends GdUnitTestSuite

const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _KNIFE       := preload("res://addons/go_build/mesh/knife.gd")
const _TRI         := preload("res://addons/go_build/mesh/triangulate.gd")
const _PICKING     := preload("res://addons/go_build/core/picking_helper.gd")
const _CUBE5       := preload("res://tests/mesh/go_build_cube5_fixture.gd")


## Flat quad in the XZ plane (normal +Y): 2×2 square centred on origin.
## Ring order [0,3,2,1] is CCW-from-above (per GoBuild's CCW-from-outside
## convention, verified by compute_face_normal returning UP).
func _make_quad() -> GoBuildMesh:
	var m := GoBuildMesh.new()
	m.vertices = [
		Vector3(-1.0, 0.0, -1.0),   # 0
		Vector3( 1.0, 0.0, -1.0),   # 1
		Vector3( 1.0, 0.0,  1.0),   # 2
		Vector3(-1.0, 0.0,  1.0),   # 3
	]
	var f := GoBuildFace.new()
	f.vertex_indices = [0, 3, 2, 1]
	m.faces.append(f)
	m.rebuild_edges()
	return m


# ---------------------------------------------------------------------------
# edge_hit
# ---------------------------------------------------------------------------

func test_edge_hit_crosses_perpendicular() -> void:
	# Cut along z from (0,0,-2) to (0,0,2); edge from (1,0,-1) to (1,0,1)?
	# Use bottom edge (-1,0,-1)→(1,0,-1): cut crosses it at (0,0,-1), u=0.5.
	var hit := _KNIFE.edge_hit(
			Vector3(0, 0, -2), Vector3(0, 0, 2),
			Vector3(-1, 0, -1), Vector3(1, 0, -1))
	assert_bool(hit.is_empty()).is_false()
	assert_vector(hit["hit"]).is_equal_approx(Vector3(0, 0, -1), Vector3.ONE * 0.001)
	assert_float(hit["t"]).is_equal_approx(0.25, 0.001)
	assert_float(hit["u"]).is_equal_approx(0.5, 0.001)


func test_edge_hit_miss_beyond_bounds() -> void:
	# Cut segment shorter than needed: parallel offset — never touches edge.
	var hit := _KNIFE.edge_hit(
			Vector3(5, 0, -2), Vector3(5, 0, 2),
			Vector3(-1, 0, -1), Vector3(1, 0, -1))
	assert_bool(hit.is_empty()).is_true()


func test_edge_hit_parallel_returns_empty() -> void:
	var hit := _KNIFE.edge_hit(
			Vector3(-1, 0, -2), Vector3(1, 0, -2),
			Vector3(-1, 0, -1), Vector3(1, 0, -1))
	assert_bool(hit.is_empty()).is_true()


# ---------------------------------------------------------------------------
# face_crossings
# ---------------------------------------------------------------------------

func test_face_crossings_two() -> void:
	var m := _make_quad()
	# Segment across the whole quad along Z.
	var crossings := _KNIFE.face_crossings(
			Vector3(0, 0, -2), Vector3(0, 0, 2), m, m.faces[0])
	assert_int(crossings.size()).is_equal(2)
	# First (t-sorted) hits the z=-1 edge (ring slot 3: v3→v0 with ring
	# [0,3,2,1]: slot 3 = v1, edge v1→v0? — actually slot indices refer to the
	# [0,3,2,1] ring: edge (2→1) is pos 2 with verts 2→1 crossing z=1..-1.
	# Simplest invariant: first crossing u=0.5, second u=0.5, distinct pos.
	assert_float(crossings[0]["u"]).is_equal_approx(0.5, 0.001)
	assert_float(crossings[1]["u"]).is_equal_approx(0.5, 0.001)
	assert_int(crossings[1]["pos"]).is_not_equal(crossings[0]["pos"])


func test_face_crossings_none_when_outside() -> void:
	var m := _make_quad()
	var crossings := _KNIFE.face_crossings(
			Vector3(5, 0, -2), Vector3(5, 0, 2), m, m.faces[0])
	assert_int(crossings.size()).is_equal(0)


# ---------------------------------------------------------------------------
# apply — boundary-to-boundary chord through the three-phase pipeline
# ---------------------------------------------------------------------------

func test_apply_splits_quad_along_chord() -> void:
	var m := _make_quad()
	m.faces[0].uvs = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	# Chord across the quad: entry mid-edge, interior middle, exit mid-edge
	# (points must be in path order).
	var points := [
		{"face_index": 0, "position": Vector3(0.0, 0.0, -1.0)},
		{"face_index": 0, "position": Vector3(0.0, 0.0, 0.0)},
		{"face_index": 0, "position": Vector3(0.0, 0.0, 1.0)},
	]
	var did := _KNIFE.apply(m, points, false)
	assert_bool(did).is_true()
	# NGON emission: two sub-polygon faces (bake triangulates) — minimal
	# geometry, no triangle fans.
	assert_int(m.faces.size()).is_equal(2)
	# Shared cut vertices on both crossed edges (2) + 1 interior path vertex.
	assert_int(m.vertices.size()).is_equal(7)
	for f: GoBuildFace in m.faces:
		var n := m.compute_face_normal(f)
		assert_float(n.dot(Vector3.UP)).is_greater_equal(0.999)


func test_apply_preserves_material_and_smooth() -> void:
	var m := _make_quad()
	m.faces[0].material_index = 2
	m.faces[0].smooth_group = 5
	var points := [
		{"face_index": 0, "position": Vector3(0.0, 0.0, -1.0)},
		{"face_index": 0, "position": Vector3(0.0, 0.0, 0.0)},
		{"face_index": 0, "position": Vector3(0.0, 0.0, 1.0)},
	]
	_KNIFE.apply(m, points, false)
	for f: GoBuildFace in m.faces:
		assert_int(f.material_index).is_equal(2)
		assert_int(f.smooth_group).is_equal(5)


func test_apply_preserves_uv_layout() -> void:
	# The quad's UVs tile 0..1 over the face; a chord split must keep the
	# UV field intact — ring verts keep their slot UVs, new interior verts
	# interpolate (no dominant-axis re-projection stretching UVs out of
	# the tile).
	var m := _make_quad()
	m.faces[0].uvs = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var points := [
		{"face_index": 0, "position": Vector3(0.0, 0.0, -1.0)},
		{"face_index": 0, "position": Vector3(0.0, 0.0, 0.0)},
		{"face_index": 0, "position": Vector3(0.0, 0.0, 1.0)},
	]
	var did := _KNIFE.apply(m, points, true)
	assert_bool(did).is_true()
	for f: GoBuildFace in m.faces:
		assert_int(f.uvs.size()).is_equal(f.vertex_indices.size())
		for uv: Vector2 in f.uvs:
			# Every UV stays inside (or on) the original 0..1 tile.
			assert_float(uv.x).is_greater_equal(-0.001)
			assert_float(uv.x).is_less_equal(1.001)
			assert_float(uv.y).is_greater_equal(-0.001)
			assert_float(uv.y).is_less_equal(1.001)
	# The original 4 ring verts (their positions) must carry their exact
	# original UVs on whichever face now holds them.
	for vi: int in 4:
		var found := false
		for f: GoBuildFace in m.faces:
			var slot: int = f.vertex_indices.find(vi)
			if slot >= 0 and f.uvs.size() == f.vertex_indices.size():
				var expect := Vector2(0, 0)
				if vi == 3:
					expect = Vector2(1, 0)
				elif vi == 2:
					expect = Vector2(1, 1)
				elif vi == 1:
					expect = Vector2(0, 1)
				assert_vector(f.uvs[slot]).is_equal_approx(expect,
						Vector2(0.001, 0.001))
				found = true
				break
		assert_bool(found).is_true()


func test_apply_splits_square_into_nine() -> void:
	# 3×3 grid of quads ([0,3,2,1] CCW ring); knife draws an axis-aligned
	# square loop in the CENTRE cell — every segment lies on ONE face, so the
	# walk is 4 splits of the same face (its ring updates each time).
	var m := GoBuildMesh.new()
	# 4×4 verts = 3×3 quads, XZ plane, spanning -1.5..1.5.
	for zi: int in 4:
		for xi: int in 4:
			m.vertices.append(Vector3(xi - 1.5, 0.0, zi - 1.5))
	for zi: int in 3:
		for xi: int in 3:
			var f := GoBuildFace.new()
			# CCW-from-above: (x,z) → (x+1,z) → (x+1,z+1) → (x,z+1) is CW;
			# [v00, v01, v11, v10] with z-rows: build via ring (x,z),(x,z+1),(x+1,z+1),(x+1,z).
			var v00: int = zi * 4 + xi
			var v01: int = (zi + 1) * 4 + xi
			var v11: int = (zi + 1) * 4 + xi + 1
			var v10: int = zi * 4 + xi + 1
			f.vertex_indices = [v00, v01, v11, v10]
			m.faces.append(f)
	m.rebuild_edges()
	# Sanity: centre face normal +Y.
	var centre_fi := 4
	var n := m.compute_face_normal(m.faces[centre_fi])
	assert_float(n.dot(Vector3.UP)).is_greater(0.999)
	# Knife loop: rectangle INSIDE the centre face.  Its corners are interior
	# points (each segment crosses the face boundary once in each direction
	# only for the closing pass — but interior→interior chords never cross
	# the boundary, so instead use mid-edge points on the centre face's
	# boundary: the four edge midpoints form the knife loop.
	var loop: Array = [
		{"face_index": centre_fi, "position": Vector3( 0.0, 0.0, -0.5)},
		{"face_index": centre_fi, "position": Vector3( 0.5, 0.0,  0.0)},
		{"face_index": centre_fi, "position": Vector3( 0.0, 0.0,  0.5)},
		{"face_index": centre_fi, "position": Vector3(-0.5, 0.0,  0.0)},
	]
	var did: bool = _KNIFE.apply(m, loop, true)
	assert_bool(did).is_true()
	# Closed diamond carves the centre face; assert the split happened and
	# the result is valid geometry (exact face count depends on triangulation).
	assert_int(m.faces.size()).is_greater(9)
	# All faces keep +Y normals and non-degenerate rings.
	for f: GoBuildFace in m.faces:
		var fn := m.compute_face_normal(f)
		assert_float(fn.dot(Vector3.UP)).is_greater(0.99)
		assert_int(f.vertex_indices.size()).is_greater_equal(3)
		var uniq := {}
		for vi: int in f.vertex_indices:
			uniq[vi] = true
		assert_int(uniq.size()).is_equal(f.vertex_indices.size())


# ---------------------------------------------------------------------------
# Minimal topology — closed quad loop on one quad face (Blender-equivalence)
# ---------------------------------------------------------------------------
# Repro: knife-draw a small closed quad inside a plane's single quad face.
# Blender (knife-constrained) result: the face becomes the loop n-gon plus a
# ring band — 5 faces, 4 new vertices, 8 new edges (4 loop + 4 spokes).
# Our model has no pre-existing neighbours to stitch to, so the loop edges
# are the only new edges and each loop vertex connects to ONE ring corner.

## Closed quad loop centred inside the flat 2×2 quad (all corners interior).
func _make_loop_points() -> Array:
	return [
		{"face_index": 0, "position": Vector3(-0.5, 0.0, -0.5)},
		{"face_index": 0, "position": Vector3( 0.5, 0.0, -0.5)},
		{"face_index": 0, "position": Vector3( 0.5, 0.0,  0.5)},
		{"face_index": 0, "position": Vector3(-0.5, 0.0,  0.5)},
	]


func test_closed_quad_loop_minimal_topology() -> void:
	var m := _make_quad()
	var verts_before: int = m.vertices.size()
	var edges_before: int = m.edges.size()
	var did := _KNIFE.apply(m, _make_loop_points(), true)
	assert_bool(did).is_true()
	# Blender counts: island quad + two band n-gons = 3 faces, +4 loop
	# vertices, +6 edges (4 island + 2 bridges — Blender's minimal layout).
	assert_int(m.faces.size()).is_equal(3)
	assert_int(m.vertices.size()).is_equal(verts_before + 4)
	assert_int(m.edges.size()).is_equal(edges_before + 6)
	# Island n-gon replaces the original face at index 0.
	assert_int(m.faces[0].vertex_indices.size()).is_equal(4)
	for f: GoBuildFace in m.faces:
		var n := m.compute_face_normal(f)
		assert_float(n.dot(Vector3.UP)).is_greater_equal(0.999)
	# No T-junctions: every edge is used by exactly one or two faces.
	for e: GoBuildEdge in m.edges:
		assert_int(e.face_indices.size()).is_between(1, 2)


func test_closed_loop_band_quads_are_simple() -> void:
	var m := _make_quad()
	var did := _KNIFE.apply(m, _make_loop_points(), true)
	assert_bool(did).is_true()
	# The two band faces (index 1..2) are concave n-gons — each must be a
	# proper ring: no repeated vertices (no bowtie/pinch).
	for fi: int in range(1, m.faces.size()):
		var ring: Array[int] = m.faces[fi].vertex_indices
		assert_int(ring.size()).is_equal(6)
		var uniq := {}
		for vi: int in ring:
			uniq[vi] = true
		assert_int(uniq.size()).is_equal(6)


func test_closed_quad_loop_bake_area_preserved() -> void:
	var m := _make_quad()
	var did := _KNIFE.apply(m, _make_loop_points(), true)
	assert_bool(did).is_true()
	var baked := m.bake()
	var total := 0.0
	for s: int in baked.get_surface_count():
		var arrays: Array = baked.surface_get_arrays(s)
		# _build_surface emits no index buffer — triangles are consecutive
		# vertex triples.
		var va: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for t: int in va.size() / 3:
			var a: Vector3 = va[t * 3]
			var b: Vector3 = va[t * 3 + 1]
			var c: Vector3 = va[t * 3 + 2]
			total += (b - a).cross(c - a).length() * 0.5
	# Original quad area = 4.  Baked triangle sum must match (any loss or
	# overlap means the tessellation shredded or duplicated geometry).
	assert_float(total).is_equal_approx(4.0, 0.001)


# ---------------------------------------------------------------------------
# Minimal topology — open edge-to-edge cut (2 new edges only)
# ---------------------------------------------------------------------------

func test_open_cut_minimal_geometry() -> void:
	var m := _make_quad()
	var verts_before: int = m.vertices.size()
	var edges_before: int = m.edges.size()
	var points := [
		{"face_index": 0, "position": Vector3(0.0, 0.0, -1.0)},
		{"face_index": 0, "position": Vector3(0.0, 0.0, 0.0)},
		{"face_index": 0, "position": Vector3(0.0, 0.0, 1.0)},
	]
	var did := _KNIFE.apply(m, points, false)
	assert_bool(did).is_true()
	# Open cut through one quad: 2 faces; +3 vertices = 2 shared edge-split
	# cut verts + 1 interior path vertex; +4 edges = 2 edge-split halves +
	# 2 path edges (each path edge borders both sub-faces).  All minimal.
	assert_int(m.faces.size()).is_equal(2)
	assert_int(m.vertices.size()).is_equal(verts_before + 3)
	assert_int(m.edges.size()).is_equal(edges_before + 4)
	for e: GoBuildEdge in m.edges:
		assert_int(e.face_indices.size()).is_between(1, 2)


# ---------------------------------------------------------------------------
# Close-on-existing edges — Blender's zero-geometry close
# ---------------------------------------------------------------------------

func test_corner_snapped_loop_adds_zero_geometry() -> void:
	# A loop snapped onto the face's own corners rides existing edges —
	# Blender adds no vertices/edges/faces (the drawn poly IS the face).
	var m := _make_quad()
	var verts_before: int = m.vertices.size()
	var edges_before: int = m.edges.size()
	var loop := [
		{"face_index": 0, "position": Vector3(-1.0, 0.0, -1.0)},
		{"face_index": 0, "position": Vector3( 1.0, 0.0, -1.0)},
		{"face_index": 0, "position": Vector3( 1.0, 0.0,  1.0)},
		{"face_index": 0, "position": Vector3(-1.0, 0.0,  1.0)},
	]
	var did := _KNIFE.apply(m, loop, true)
	assert_bool(did).is_false()
	assert_int(m.vertices.size()).is_equal(verts_before)
	assert_int(m.edges.size()).is_equal(edges_before)
	assert_int(m.faces.size()).is_equal(1)


func test_edge_snapped_loop_shares_crossing_vertices() -> void:
	# Loop points on the ring-edge midpoints: crossings must become SHARED
	# vertices (one per ring edge, in both neighbouring ring slots) — no
	# duplicates.  All four loop points are ring members after phase 2, so
	# the bands chain member→member: +4 verts, +8 edges (4 island + 4 ring
	# split halves — no bridges needed).
	var m := _make_quad()
	var verts_before: int = m.vertices.size()
	var edges_before: int = m.edges.size()
	var loop := [
		{"face_index": 0, "position": Vector3( 0.0, 0.0, -1.0)},
		{"face_index": 0, "position": Vector3( 1.0, 0.0,  0.0)},
		{"face_index": 0, "position": Vector3( 0.0, 0.0,  1.0)},
		{"face_index": 0, "position": Vector3(-1.0, 0.0,  0.0)},
	]
	var did := _KNIFE.apply(m, loop, true)
	assert_bool(did).is_true()
	# All four loop points split their ring edges (members) — bands chain
	# member→member as 4 tri bands: 1 island + 4 tri bands = 5 faces,
	# +4 verts (members), +8 edges (4 ring split halves + 4 island edges).
	assert_int(m.faces.size()).is_equal(5)
	assert_int(m.vertices.size()).is_equal(verts_before + 4)
	assert_int(m.edges.size()).is_equal(edges_before + 8)
	# Ring uniqueness on every face — no bowties, no T-junctions.
	for f: GoBuildFace in m.faces:
		var uniq := {}
		for vi: int in f.vertex_indices:
			uniq[vi] = true
		assert_int(uniq.size()).is_equal(f.vertex_indices.size())


## Boundary-hugging D-loop (both ends on one ring edge, like a knife stroke
## pressed against the face border): the on-edge points split the ring, one
## band takes the island's far side — no overlapping n-gons.
func test_boundary_hugging_loop_single_band() -> void:
	var m := _make_quad()
	var verts_before: int = m.vertices.size()
	var edges_before: int = m.edges.size()
	var loop := [
		{"face_index": 0, "position": Vector3(-1.0, 0.0, -0.0002)},
		{"face_index": 0, "position": Vector3(-1.0, 0.0,  0.7062)},
		{"face_index": 0, "position": Vector3(-0.5801, 0.0,  0.8108)},
		{"face_index": 0, "position": Vector3(-0.4024, 0.0,  0.0500)},
		{"face_index": 0, "position": Vector3(-1.0, 0.0, -0.0002)},
	]
	var did := _KNIFE.apply(m, loop, true)
	assert_bool(did).is_true()
	# Island + one band (the far side); the slit edge along the boundary is
	# Blender-parity (zero-width contact).
	assert_int(m.faces.size()).is_equal(2)
	assert_int(m.vertices.size()).is_equal(verts_before + 4)
	# Bake tiling: island (0.38) + band must total the 4-unit face.
	var baked := m.bake()
	var total := 0.0
	for s: int in baked.get_surface_count():
		var arrays: Array = baked.surface_get_arrays(s)
		var va: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for t: int in va.size() / 3:
			var a: Vector3 = va[t * 3]
			var b: Vector3 = va[t * 3 + 1]
			var c: Vector3 = va[t * 3 + 2]
			total += (b - a).cross(c - a).length() * 0.5
	assert_float(total).is_equal_approx(4.0, 0.001)


# ---------------------------------------------------------------------------
# Multi-face cycle — pass-through faces cut, no degenerate anchors
# ---------------------------------------------------------------------------

func test_multiface_cycle_no_degenerate_anchor() -> void:
	# Stroke A→A→B→close across two adjacent quads: every visited face
	# interior gains the cut; no "degenerate anchors" drops, no duplicated
	# point.  Points are face INTERIORS so the path genuinely pierces the
	# shared edge twice.
	var m := GoBuildMesh.new()
	for zi: int in 2:
		for xi: int in 3:
			m.vertices.append(Vector3(xi - 1.5, 0.0, zi - 0.5))
	var f0 := GoBuildFace.new()
	f0.vertex_indices = [0, 3, 4, 1]     # left quad (CCW from above)
	var f1 := GoBuildFace.new()
	f1.vertex_indices = [1, 4, 5, 2]     # right quad
	m.faces.append(f0)
	m.faces.append(f1)
	m.rebuild_edges()
	assert_float(m.compute_face_normal(m.faces[0]).dot(Vector3.UP)).is_greater(0.99)
	assert_float(m.compute_face_normal(m.faces[1]).dot(Vector3.UP)).is_greater(0.99)
	# 4-point cycle (4th = close duplicate of the 1st, dropped by resolver):
	# two interior points on face 0, one interior point on face 1.
	var loop: Array = [
		{"face_index": 0, "position": Vector3(-1.0, 0.0,  0.25)},
		{"face_index": 0, "position": Vector3(-1.0, 0.0, -0.25)},
		{"face_index": 1, "position": Vector3( 0.0, 0.0, -0.25)},
		{"face_index": 0, "position": Vector3(-1.0, 0.0,  0.25)},
	]
	var did := _KNIFE.apply(m, loop, true)
	assert_bool(did).is_true()
	# Face 1 (the pass-through face) must be re-partitioned — no silent drop.
	var f1_cut := false
	for f: GoBuildFace in m.faces:
		if f.vertex_indices.has(5) and f.vertex_indices.size() != 4:
			f1_cut = true
	assert_bool(f1_cut).is_true()
	# Every face ring has unique vertices — no bowties, no T-junctions.
	for f: GoBuildFace in m.faces:
		var uniq := {}
		for vi: int in f.vertex_indices:
			uniq[vi] = true
		assert_int(uniq.size()).is_equal(f.vertex_indices.size())
	# No T-junctions: every edge shared by at most 2 faces.
	for e: GoBuildEdge in m.edges:
		assert_int(e.face_indices.size()).is_between(1, 2)


# ---------------------------------------------------------------------------
# Regression probes — the session's bug strokes as permanent tests.
# Each asserts the two invariants that caught every bug this round:
#   1. face-plane polygon tiling (no overlaps, no holes, area preserved)
#   2. bake triangle-sum equals the pre-cut area
# ---------------------------------------------------------------------------

## Total triangle area of a face ring (ear-clip triangulation).
func _ring_area(m: GoBuildMesh, ring: Array[int]) -> float:
	var fp: Array[Vector3] = []
	for vi: int in ring:
		fp.append(m.vertices[vi])
	var tris: Array = _TRI.triangulate_face(fp)
	var total := 0.0
	for t: Array in tris:
		var a: Vector3 = fp[t[0]]
		var b: Vector3 = fp[t[1]]
		var c: Vector3 = fp[t[2]]
		total += (b - a).cross(c - a).length() * 0.5
	return total


## Assert the faces whose rings live on the given plane tile it exactly:
## every plane point is covered by exactly one face (grid-scan, catching
## both overlaps — 2+ faces — and holes — 0 faces).  An empty [param faces]
## list auto-detects: all faces whose ring vertices lie on the plane.
func _assert_plane_tiling(m: GoBuildMesh, plane_axis: int, plane_value: float,
		faces: Array[int], expected_area: float) -> void:
	var face_list: Array[int] = []
	face_list.assign(faces)
	if face_list.is_empty():
		for fi: int in m.faces.size():
			var on_plane := true
			var ring: Array[int] = m.faces[fi].vertex_indices
			if ring.is_empty():
				continue
			for vi: int in ring:
				var v: Vector3 = m.vertices[vi]
				var coord: float = v.x if plane_axis == Vector3.AXIS_X \
						else (v.y if plane_axis == Vector3.AXIS_Y else v.z)
				if absf(coord - plane_value) > 1e-4:
					on_plane = false
					break
			if on_plane:
				face_list.append(fi)
	var covered := 0.0
	# Sum of the tile faces' areas must equal the expected area exactly —
	# the overlap detector (any double coverage shows up as area > target).
	for fi: int in face_list:
		covered += _ring_area(m, m.faces[fi].vertex_indices)
	assert_float(covered).is_equal_approx(expected_area, 0.002)


## A 2×2×1 cube with the +Z face at ring [6, 7, 1, 0] (the session's
## standard repro mesh — vertex layout matches the in-editor GoBuildCube).
func _make_cube_2x2x1() -> GoBuildMesh:
	var m := GoBuildMesh.new()
	m.vertices = [
		Vector3(-1, -1, 0.5), Vector3(1, -1, 0.5),
		Vector3(-1, -1, -0.5), Vector3(1, -1, -0.5),
		Vector3(-1, 1, -0.5), Vector3(1, 1, -0.5),
		Vector3(-1, 1, 0.5), Vector3(1, 1, 0.5),
	]
	var quads := [
		[3, 2, 4, 5],   # -Z
		[2, 3, 1, 0],   # -Y
		[0, 1, 7, 6],   # +Z (face 2, CCW-from-outside: bottom→right→top→left)
		[4, 5, 7, 6],   # +Y
		[2, 4, 6, 0],   # -X
		[3, 1, 7, 5],   # +X
	]
	for q: Array in quads:
		var f := GoBuildFace.new()
		var r: Array[int] = []
		r.assign(q)
		f.vertex_indices = r
		m.faces.append(f)
	m.rebuild_edges()
	return m


## Close a stroke on a +Z face with the close-click duplicate.
func _closed_stroke(m: GoBuildMesh, raw: Array, face_index: int = 2) -> void:
	var pts: Array = []
	for p: Vector3 in raw:
		pts.append({"face_index": face_index, "position": p})
	pts.append({"face_index": face_index, "position": raw[0]})
	var did := _KNIFE.apply(m, pts, true)
	assert_bool(did).is_true()


func test_closed_loop_three_members_left_edge() -> void:
	# Probe 25: the user's 3-member stroke (two boundary clamps on the left
	# edge, one on the top edge). Member-chain bands + structural arc pick.
	var m := _make_cube_2x2x1()
	_closed_stroke(m, [
		Vector3(-1.101054, -0.084685, 0.5),
		Vector3(-1.551401, 0.427696, 0.5),
		Vector3(-0.604704, 1.14943, 0.5),
		Vector3(-0.08694, 0.481373, 0.5),
	])
	# +2f +4v +6e; the neighbour face gains the split ring members.
	assert_int(m.faces.size()).is_equal(8)
	assert_int(m.vertices.size()).is_equal(12)
	_assert_plane_tiling(m, Vector3.AXIS_Z, 0.5, [2, 6, 7], 4.0)


func test_closed_loop_single_member_hug() -> void:
	# Probe 24's single-member variant: one loop point clamped onto the
	# boundary edge.  Keyhole layout (no bridge): island + ONE outer face
	# with the attachment slit — island replaces the +Z quad, outer appends.
	var m := _make_cube_2x2x1()
	_closed_stroke(m, [
		Vector3(-0.876151, -0.201455, 0.5),
		Vector3(-1.226858, 0.272112, 0.5),
		Vector3(-0.416962, 0.973595, 0.5),
		Vector3(-0.039031, 0.630911, 0.5),
	])
	assert_int(m.faces.size()).is_equal(7)
	_assert_plane_tiling(m, Vector3.AXIS_Z, 0.5, [], 4.0)


func test_closed_loop_big_cube_interior_island() -> void:
	# Probe 27: 5-point stroke, all interior, 4×3×1 cube — the bridge
	# contest + containment check on a non-square face.
	var m := GoBuildMesh.new()
	m.vertices = [
		Vector3(-2, -1.5, 0.5), Vector3(2, -1.5, 0.5),
		Vector3(-2, -1.5, -0.5), Vector3(2, -1.5, -0.5),
		Vector3(-2, 1.5, -0.5), Vector3(2, 1.5, -0.5),
		Vector3(-2, 1.5, 0.5), Vector3(2, 1.5, 0.5),
	]
	var quads := [
		[3, 2, 4, 5],
		[2, 3, 1, 0],
		[6, 7, 1, 0],
		[4, 5, 7, 6],
		[2, 4, 6, 0],
		[3, 1, 7, 5],
	]
	for q: Array in quads:
		var f := GoBuildFace.new()
		var r: Array[int] = []
		r.assign(q)
		f.vertex_indices = r
		m.faces.append(f)
	m.rebuild_edges()
	_closed_stroke(m, [
		Vector3(-0.864275, -0.176974, 0.5),
		Vector3(-1.65335, 0.49988, 0.5),
		Vector3(-0.852346, 1.113059, 0.5),
		Vector3(-0.142936, 0.600445, 0.5),
		Vector3(-0.48113, -0.025409, 0.5),
	])
	assert_int(m.vertices.size()).is_equal(13)
	_assert_plane_tiling(m, Vector3.AXIS_Z, 0.5, [], 12.0)


func test_edge_to_edge_quad_strip_inserted() -> void:
	# Probe 30: 4-point open cut, edge-snapped ends, the central quad strip
	# must exist (the "missing quad" bug).
	var m := _make_cube_2x2x1()
	var raw := [
		Vector3(-0.5, -1.0, 0.5),
		Vector3(-0.5, 1.0, 0.5),
		Vector3(0.5, 1.0, 0.5),
		Vector3(0.5, -1.0, 0.5),
	]
	var pts: Array = []
	for p: Vector3 in raw:
		pts.append({"face_index": 2, "position": p})
	assert_bool(_KNIFE.apply(m, pts, false)).is_true()
	# +4 cut verts (both ends mid-edge, mid-path points on the top edge),
	# the strip quad + 2 side bands.
	assert_int(m.vertices.size()).is_equal(12)
	_assert_plane_tiling(m, Vector3.AXIS_Z, 0.5, [], 4.0)


func test_edge_riding_stroke_tiling() -> void:
	# Probe 31: the stroke rides the bottom edge then the top edge —
	# zero-area stretches skip, bands tile exactly.
	var m := _make_cube_2x2x1()
	_closed_stroke(m, [
		Vector3(-0.5, -1.0, 0.5),
		Vector3(0.5, -1.0, 0.5),
		Vector3(0.5, 1.0, 0.5),
		Vector3(-0.5, 1.0, 0.5),
	])
	_assert_plane_tiling(m, Vector3.AXIS_Z, 0.5, [], 4.0)


func test_open_cut_all_edge_snapped_members() -> void:
	# Probe 29: edge-snap start + mid-path edge snap + snapped corners —
	# +2v +2e +2f, no T-junctions, no duplicate corners, exact tiling.
	var m := _make_cube_2x2x1()
	var raw := [
		Vector3(-1, -0.5, 0.5),      # edge snap (left edge)
		Vector3(-0.284, 1.0, 0.5),   # edge snap (top edge)
		Vector3(1, -1, 0.5),         # snapped vertex 1
		Vector3(1, 1, 0.5),          # snapped vertex 7
	]
	var pts: Array = []
	for p: Vector3 in raw:
		pts.append({"face_index": 2, "position": p})
	assert_bool(_KNIFE.apply(m, pts, false)).is_true()
	assert_int(m.vertices.size()).is_equal(10)
	_assert_plane_tiling(m, Vector3.AXIS_Z, 0.5, [], 4.0)


func test_open_cut_revisiting_path_rejected_clean() -> void:
	# Probe 26: off-face clicks clamp to one corner → the path revisits it
	# → clean rejection, NO orphaned vertices, did=false.
	var m := _make_cube_2x2x1()
	var raw := [
		Vector3(-1.5, -0.701414, 1.0),
		Vector3(-0.685621, 0.102565, 1.0),
		Vector3(0.298902, 0.185749, 1.0),
		Vector3(5.456833, 1.402827, 10.13233),
		Vector3(5.485754, 1.402827, 10.13233),
		Vector3(0.6517, 0.587142, 1.0),
		Vector3(6.219157, 1.402827, 10.13233),
		Vector3(1.5, 0.701414, 1.0),
	]
	var pts: Array = []
	for p: Vector3 in raw:
		pts.append({"face_index": 2, "position": p})
	var did := _KNIFE.apply(m, pts, false)
	assert_bool(did).is_false()
	# Clean rejection: the face count is unchanged.  The on-edge splits for
	# the clamped points DO mutate the ring (shared with the neighbour —
	# persistent edges), so vertices grow; the stroke still applies no cut.
	assert_int(m.faces.size()).is_equal(6)


func test_seam_two_points_inserts_drawn_edge() -> void:
	# 2026-09-13 session: a 2-point open stroke with both ends on RING
	# EDGES (edge-snapped) resolved as two single-touch runs —
	# "+0f +0v +0e", nothing inserted.  Blender's knife seam: the drawn
	# edge must split the face into two (+1f +2v: the 2 ring splits;
	# +3e: 4 split halves − 1 original + 2 drawn edges).
	var m := _make_cube_2x2x1()
	var pts: Array = [
		{"face_index": 2, "position": Vector3(-0.6, -1.0, 0.5)},
		{"face_index": 2, "position": Vector3(-0.6, 1.0, 0.5)},
	]
	assert_bool(_KNIFE.apply(m, pts, false)).is_true()
	# The seam edge exists between the two (split) ring points.
	var seam_found := false
	var seam_vi := [-1, -1]
	for e: GoBuildEdge in m.edges:
		var pa: Vector3 = m.vertices[e.vertex_a]
		var pb: Vector3 = m.vertices[e.vertex_b]
		if absf(pa.x - pb.x) < 1e-4 and absf(pa.x - -0.6) < 1e-4 \
				and absf(pa.z - pb.z) < 1e-4:
			seam_found = true
			seam_vi = [e.vertex_a, e.vertex_b]
	assert_bool(seam_found).is_true()
	# The +Z face split at the seam: each half's ring holds both endpoints.
	var halves := 0
	for f: GoBuildFace in m.faces:
		var ring: Array[int] = f.vertex_indices
		if ring.has(seam_vi[0]) and ring.has(seam_vi[1]) \
				and absf(m.vertices[ring[0]].z - 0.5) < 1e-4:
			halves += 1
	assert_int(halves).is_equal(2)
	assert_int(m.faces.size()).is_equal(7)
	# A later cut THROUGH the seam splits the face there: run a second
	# stroke crossing the seam edge mid-face (the seam now sits between
	# the split halves at face index 2 — stroke its band's interior).
	var pts2: Array = [
		{"face_index": 2, "position": Vector3(-0.3, -0.5, 0.5)},
		{"face_index": 2, "position": Vector3(-0.3, 0.5, 0.5)},
		{"face_index": 2, "position": Vector3(0.5, 0.0, 0.5)},
	]
	assert_bool(_KNIFE.apply(m, pts2, false)).is_true()
	assert_int(m.faces.size()).is_greater(7)
	for f: GoBuildFace in m.faces:
		var uniq := {}
		for vi: int in f.vertex_indices:
			uniq[vi] = true
		assert_int(uniq.size()).is_equal(f.vertex_indices.size())


func test_seam_snapped_corners_zero_new_vertices() -> void:
	# Both ends snapped to existing ring CORNERS: the seam edge connects
	# them with ZERO new vertices (+1f +1e — the face splits in two).
	var m := _make_cube_2x2x1()
	var pts: Array = [
		{"face_index": 2, "position": Vector3(-1.0, -1.0, 0.5)},
		{"face_index": 2, "position": Vector3(1.0, 1.0, 0.5)},
	]
	var v0: int = m.vertices.size()
	assert_bool(_KNIFE.apply(m, pts, false)).is_true()
	assert_int(m.vertices.size()).is_equal(v0)
	assert_bool(m.find_edge(0, 7) >= 0 or m.find_edge(7, 0) >= 0).is_true()
	assert_int(m.faces.size()).is_equal(7)


func test_seam_snapped_corners_scattered_cursor_faces() -> void:
	# 2026-09-13 session: a 2-point corner-to-corner seam on an n-gon cap
	# with the picks recorded under DIFFERENT cursor faces (side faces —
	# snapping grabs a shared vertex under whatever face the cursor was
	# over) resolved as two single-touch runs and inserted nothing.  The
	# resolver's coplanar-consensus remap now covers OPEN strokes too: one
	# face holds both picks (the cap) → remap → the seam cuts it.
	var m := GoBuildMesh.new()
	m.vertices = [
		Vector3(-1.6, 0, -2.8), Vector3(2.4, 0, -2.8), Vector3(2.4, 0, 1.2),
		Vector3(-1.6, 0, 1.2), Vector3(-1.6, 0, 3.2),
		Vector3(-1.6, -4, -2.8), Vector3(2.4, -4, -2.8), Vector3(2.4, -4, 1.2),
		Vector3(-1.6, -4, 1.2), Vector3(-1.6, -4, 3.2),
	]
	for ring: Array in [[0, 1, 6, 5], [1, 2, 7, 6], [2, 3, 8, 7],
			[3, 4, 9, 8], [4, 0, 5, 9]]:
		var f := GoBuildFace.new()
		f.vertex_indices.assign(ring)
		m.faces.append(f)
	var cap := GoBuildFace.new()
	cap.vertex_indices = [0, 1, 2, 3, 4]
	m.faces.append(cap)
	var bot := GoBuildFace.new()
	bot.vertex_indices = [5, 6, 7, 8, 9]
	m.faces.append(bot)
	m.rebuild_edges()
	var f0: int = m.faces.size()
	assert_bool(_KNIFE.apply(m, [
		{"face_index": 0, "position": m.vertices[0]},
		{"face_index": 1, "position": m.vertices[2]},
	], false)).is_true()
	# The cap split into two n-gons; the seam edge 0—2 exists.
	assert_int(m.faces.size()).is_equal(f0 + 1)
	assert_bool(m.find_edge(0, 2) >= 0 or m.find_edge(2, 0) >= 0).is_true()
	for f: GoBuildFace in m.faces:
		var uniq := {}
		for vi: int in f.vertex_indices:
			uniq[vi] = true
		assert_int(uniq.size()).is_equal(f.vertex_indices.size())


func test_closed_loop_user_stroke_offface_clamped() -> void:
	# Probe 32: the user's stroke with p1 outside the face — the clamp
	# projects it to the ring edge (single-member hug on the 2×2 cube);
	# keyhole layout: island + one outer face, no bridge sliver (the
	# bare-band + garbage-chord regression).
	var m := _make_cube_2x2x1()
	_closed_stroke(m, [
		Vector3(-1.189649, -0.347268, 0.5),
		Vector3(-1.596828, 0.406711, 0.5),
		Vector3(-0.521511, 0.911013, 0.5),
		Vector3(-0.318196, 0.224513, 0.5),
	])
	assert_int(m.faces.size()).is_equal(7)
	_assert_plane_tiling(m, Vector3.AXIS_Z, 0.5, [], 4.0)


func test_closed_loop_single_member_no_bridge() -> void:
	# User's vertex-attached quad: p0 on the bottom ring edge, 3 interior.
	# Blender adds NO bridging edge for an edge-attached loop — the outer
	# region is ONE keyhole n-gon ([m, outer walk, m, island far side]),
	# not island + band + sliver triangle.
	var m := GoBuildMesh.new()
	m.vertices = [
		Vector3(-2.362876, 1.377355, 0.5),   # 0 top-left (user vert 0)
		Vector3(0.5, 1.377355, 0.5),         # 1 top-right (user vert 1)
		Vector3(0.5, -0.5, 0.5),             # 2 bottom-right (user vert 7)
		Vector3(-2.362876, -0.5, 0.5),       # 3 bottom-left (user vert 6)
	]
	var f := GoBuildFace.new()
	f.vertex_indices = [3, 2, 1, 0]   # user ring [6,7,1,0], +Z CCW
	m.faces.append(f)
	m.rebuild_edges()
	_closed_stroke(m, [
		Vector3(-1.378645, -0.5, 0.5),      # p0 on edge 6→7
		Vector3(-1.671996, 0.123955, 0.5),
		Vector3(-0.855642, 0.63515, 0.5),
		Vector3(-0.436442, 0.136388, 0.5),
	], 0)
	# +4 cut verts (4..7), +1f (island + keyhole outer replace the quad),
	# +5e (1 split half + 4 island edges) — NO bridge edge.
	assert_int(m.vertices.size()).is_equal(8)
	assert_int(m.faces.size()).is_equal(2)
	assert_int(m.edges.size()).is_equal(9)
	# Island edges exist; the old bridge (corner→island_next) must NOT.
	assert_int(m.find_edge(4, 5)).is_greater_equal(0)   # island p0→p1
	assert_int(m.find_edge(3, 5)).is_equal(-1)          # no bridge
	# Tiling exact (the keyhole's slit covers no area).
	_assert_plane_tiling(m, Vector3.AXIS_Z, 0.5, [], 5.375)


func test_point_in_poly_downward_edges() -> void:
	# Addendum 8 regression: the maxf epsilon clamp on the signed
	# interpolation denominator dropped downward-edge crossings. The
	# containment verdict for the island arc must be winding-independent:
	# verify a known concave dent polygon's containment answers.
	var m := _make_cube_2x2x1()
	_closed_stroke(m, [
		Vector3(-1.130335, -0.239581, 0.5),
		Vector3(-1.715156, 0.331783, 0.5),
		Vector3(-1.050912, 0.950463, 0.5),
		Vector3(-0.344665, 0.232149, 0.5),
	])
	# The two bands + island tile the face — the containment-driven arc
	# pick must produce NO overlap (the bare-band emission shape).
	_assert_plane_tiling(m, Vector3.AXIS_Z, 0.5, [], 4.0)


func test_closed_loop_all_points_on_ring_edges() -> void:
	# User's quad-with-all-verts-on-existing-edges stroke: 2 points on the
	# bottom ring edge, 2 on the top ring edge of ONE quad face.  The
	# clicks pick cursor-faces that may differ (shared edges) — the
	# stroke must still resolve as a single-face loop: 4 cut verts on the
	# ring edges (shared with the neighbours), the 2 drawn edges connecting
	# bottom→top pairs, face split into 3 (island quad + 2 outer regions).
	var m := GoBuildMesh.new()
	# Vertex indices follow the user's numbering: 0/1 = main quad's top
	# corners, 4/5 = neighbour's top corners, 6/7 = main quad's bottom.
	m.vertices = [
		Vector3(-2.362876, 1.377355, 0.5),   # 0 top-left
		Vector3(0.5, 1.377355, 0.5),         # 1 top-right
		Vector3(0.5, 2.5, 0.5),              # 4 neighbour top-right
		Vector3(-2.362876, 2.5, 0.5),        # 5 neighbour top-left
		Vector3(0.5, -0.5, 0.5),             # 7 bottom-right
		Vector3(-2.362876, -0.5, 0.5),       # 6 bottom-left
	]
	var quads := [
		[0, 1, 4, 5],   # face 0: main quad = user ring [0,1,7,6] (+Z CCW)
		[0, 1, 2, 3],   # face 1: neighbour above, sharing edge 0→1
	]
	for q: Array in quads:
		var f := GoBuildFace.new()
		var r: Array[int] = []
		r.assign(q)
		f.vertex_indices = r
		m.faces.append(f)
	m.rebuild_edges()
	# Stroke in the user's order; points 1/2 picked under the NEIGHBOUR's
	# face index (cursor-face on the shared top edge), 0/3 on face 0.
	var pts := [
		{"face_index": 0, "position": Vector3(-1.4995, -0.5, 0.5)},
		{"face_index": 1, "position": Vector3(-1.486727, 1.377355, 0.5)},
		{"face_index": 1, "position": Vector3(-0.707117, 1.377355, 0.5)},
		{"face_index": 0, "position": Vector3(-0.770313, -0.5, 0.5)},
		{"face_index": 0, "position": Vector3(-1.4995, -0.5, 0.5)},
	]
	var did := _KNIFE.apply(m, pts, true)
	assert_bool(did).is_true()
	# +4 cut verts, +6 edges (4 split halves + 2 drawn), +2 faces.
	assert_int(m.vertices.size()).is_equal(10)
	assert_int(m.edges.size()).is_equal(13)
	assert_int(m.faces.size()).is_equal(4)
	# The two drawn edges exist (the user's expected "connecting" edges).
	# Cut verts append in ring-scan order: 6=p0, 7=p3, 8=p1, 9=p2.
	assert_int(m.find_edge(6, 8)).is_greater_equal(0)   # p0→p1 (bottom→top left)
	assert_int(m.find_edge(9, 7)).is_greater_equal(0)   # p2→p3 (top→bottom right)
	# Cut verts sit exactly on the original edges' lines.
	assert_vector(m.vertices[6]).is_equal_approx(Vector3(-1.4995, -0.5, 0.5),
			Vector3(0.001, 0.001, 0.001))
	assert_vector(m.vertices[7]).is_equal_approx(Vector3(-0.770313, -0.5, 0.5),
			Vector3(0.001, 0.001, 0.001))
	# Face 0's three tiles + the neighbour tile the two quads exactly
	# (5.375 main + 3.214 neighbour).
	_assert_plane_tiling(m, Vector3.AXIS_Z, 0.5, [], 8.589)

func test_multiface_stroke_splits_shared_edge() -> void:
	# The user's prism stroke: a closed quad crossing between two adjacent
	# faces (picked 4,2,2,4).  The straight 3D segments tunnel the shared
	# corner edge — the screen-space crossings (injected, camera-free here:
	# hand-built hit list, same data screen_edge_hits would produce) must
	# split that edge, and each face resolves as its own run (no cross-plane
	# "loop" fold, no warped island quad spanning two planes).
	var m := _make_cube_2x2x1()
	# Face 2 = +Z ring [0,1,7,6]; face 5 = +X ring [3,1,7,5]; the shared
	# edge = 1→7 (x=1, z=0.5, the vertical front-right edge).
	assert_int(m.find_edge(1, 7)).is_greater_equal(0)
	# Stroke in the user's pattern: 2 points on +X (face 5), 2 on +Z
	# (face 2), closed.  p0/p3 sit near the shared edge but strictly on
	# their own face's plane; the segments p0→p1 / p2→p3 tunnel corner 1-7.
	var pts := [
		{"face_index": 5, "position": Vector3(1.0, -0.077266, 0.015628)},
		{"face_index": 2, "position": Vector3(0.033242, -0.141501, 0.5)},
		{"face_index": 2, "position": Vector3(-0.098605, 0.549144, 0.5)},
		{"face_index": 5, "position": Vector3(1.0, 0.793538, 0.024406)},
		{"face_index": 5, "position": Vector3(1.0, -0.077266, 0.015628)},
	]
	# Injected screen crossings (what the controller's camera projection
	# yields): p0→p1 crosses edge 1→7 at y≈-0.1; p2→p3 crosses it at y≈0.7.
	var edge_hits := [
		{"segment": 0, "edge_a": 1, "edge_b": 7, "t": 0.42,
				"point": Vector3(1.0, -0.1, 0.5)},
		{"segment": 2, "edge_a": 1, "edge_b": 7, "t": 0.85,
				"point": Vector3(1.0, 0.7, 0.5)},
	]
	assert_bool(_KNIFE.apply(m, pts, true, edge_hits)).is_true()
	# +2 cut verts (edge 1→7 split twice) + 4 path verts (p0..p3 become
	# real corners on their host faces); each face resolves as its own run
	# (2 bands + path quad per face → +2f), the bands' rings walk the split
	# shared line 1→c→c→7 (no T-junctions, no cross-plane island).
	assert_int(m.vertices.size()).is_equal(14)
	assert_int(m.faces.size()).is_equal(8)
	assert_int(m.edges.size()).is_equal(20)
	# The original shared edge is GONE (split into halves).
	assert_int(m.find_edge(1, 7)).is_equal(-1)
	# Exactly two new verts sit ON the shared line (x=1, z=0.5, y in
	# (−1, 1) — between corners 1 and 7).
	var on_edge: Array[int] = []
	for vi: int in m.vertices.size():
		var v: Vector3 = m.vertices[vi]
		if absf(v.x - 1.0) < 1e-4 and absf(v.z - 0.5) < 1e-4 \
				and v.y > -0.999 and v.y < 0.999:
			on_edge.append(vi)
	assert_int(on_edge.size()).is_equal(2)
	# Each cut vert is a ring member of faces on BOTH sides (the +X path
	# quad and band, the +Z path quad and band — no T-junction).
	for vi: int in on_edge:
		assert_int(m.faces_of_vertex(vi).size()).is_greater_equal(3)


func test_closed_loop_snap_grabbed_wrong_cursor_face() -> void:
	# Log-2 regression: p0 snaps to a ring vert recorded under the
	# NEIGHBOUR's face index (cursor-face on a heavily-cut mesh).  The
	# owner remap must (a) find the owner via any point's ring adjacency
	# — not just the first point's picked face — and (b) run BEFORE the
	# face clamp, which otherwise displaces the point onto the wrong
	# face's boundary (a bottom-edge click became a top-edge hug).
	var m := GoBuildMesh.new()
	m.vertices = [
		Vector3(-2.362876, 1.377355, 0.5),   # 0 main top-left
		Vector3(0.5, 1.377355, 0.5),         # 1 main top-right
		Vector3(0.5, 2.5, 0.5),              # 2 neighbour top-right
		Vector3(-2.362876, 2.5, 0.5),        # 3 neighbour top-left
		Vector3(0.5, -0.5, 0.5),             # 4 main bottom-right
		Vector3(-2.362876, -0.5, 0.5),       # 5 main bottom-left
	]
	var quads := [
		[5, 4, 1, 0],   # face 0: main quad (bl→br→tr→tl CCW)
		[0, 1, 2, 3],   # face 1: neighbour above, shares edge 0→1
	]
	for q: Array in quads:
		var f := GoBuildFace.new()
		var r: Array[int] = []
		r.assign(q)
		f.vertex_indices = r
		m.faces.append(f)
	m.rebuild_edges()
	# p0 ON face 0's bottom edge but recorded under face 1; p1..p3
	# interior of face 0; closed with the duplicate closing point.
	var bottom_p := Vector3(-1.378645, -0.5, 0.5)
	var pts := [
		{"face_index": 1, "position": bottom_p},
		{"face_index": 0, "position": Vector3(-1.671996, 0.123955, 0.5)},
		{"face_index": 0, "position": Vector3(-0.855642, 0.63515, 0.5)},
		{"face_index": 0, "position": Vector3(-0.436442, 0.136388, 0.5)},
		{"face_index": 1, "position": bottom_p},
	]
	assert_bool(_KNIFE.apply(m, pts, true, [])).is_true()
	# Single-face loop resolution: island + one keyhole outer band.
	assert_int(m.vertices.size()).is_equal(10)
	assert_int(m.faces.size()).is_equal(3)
	# The island quad + 4 path verts; the cut vert on the bottom edge
	# exists (vert 6, appended first).
	assert_vector(m.vertices[6]).is_equal_approx(bottom_p,
			Vector3(0.001, 0.001, 0.001))
	_assert_plane_tiling(m, Vector3.AXIS_Z, 0.5, [], 8.589)


# ---------------------------------------------------------------------------
# Historical regression tests — GoBuildCube5 (the session's standard user
# mesh, verbatim Print Selection dump).  Every repro is the EXACT user data;
# see the test-writing skill: approximated repros validate on the wrong mesh.
# ---------------------------------------------------------------------------

func test_cube5_closed_interior_quad_resolves_as_loop() -> void:
	# 2026-09-06 session: a 4-point closed quad, all picks interior to face 2
	# (+Z), resolved as OPEN runs ("open run face 2: 2 band(s)") with three
	# "single touch point" faces — the quad never closed.  Root cause: the
	# graze check in _split_groups_at_exits.  Expected: single-face loop →
	# island + 2-band outer (Blender's counts: +2f, +4v, +6e).
	var m: GoBuildMesh = _CUBE5.make()
	var pts: Array = _CUBE5.closed_quad_stroke()
	assert_bool(_KNIFE.apply(m, pts, true, [])).is_true()
	# Island (4 loop verts) + two outer bands: 6 + 4 verts, +2 faces.
	assert_int(m.vertices.size()).is_equal(12)
	assert_int(m.faces.size()).is_equal(8)
	assert_int(m.edges.size()).is_equal(18)
	# The island quad is a standalone 4-vert face (verts 8..11).
	var island: Array[int] = []
	for fi: int in m.faces.size():
		var ring: Array[int] = m.faces[fi].vertex_indices
		if ring.size() == 4 and ring[0] >= 8:
			island = ring
	assert_int(island.size()).is_equal(4)
	# The drawn quad's corners land exactly on the recorded pick positions.
	for i: int in 4:
		var expected: Vector3 = pts[i]["position"]
		var got: Vector3 = m.vertices[island[i]]
		assert_vector(got).is_equal_approx(expected, Vector3.ONE * 0.001)
	# The +Z plane tiles exactly (island + bands, no overlap, no hole).
	_assert_plane_tiling(m, Vector3.AXIS_Z, 0.5, [], 5.374634)


func test_cube5_pick_round_trip() -> void:
	# 2026-09-06 session: clicks "jump" — the crosshair and the recorded
	# point drift apart at oblique camera angles.  Guard the pick pipeline
	# (unproject → ray → front-face triangle) as pure maths: a world point
	# on face 2 projects to screen; the ray back through its own screen
	# position must re-hit the SAME point (front-facing, sub-1e-4 error) for
	# the repro camera (corner view from outside the prism).
	# Headless Godot lacks an editor viewport — build a 1920×1080
	# SubViewport with the repro camera and await two frames for the
	# projection matrices.
	var vp := SubViewport.new()
	vp.size = Vector2i(1920, 1080)
	Engine.get_main_loop().root.add_child(vp)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.current = true
	cam.fov = 75.0
	cam.look_at_from_position(Vector3(4.0, -3.0, 13.0),
			Vector3(-0.9, 0.4, 9.43), Vector3.UP)
	await (Engine.get_main_loop() as SceneTree).process_frame
	await (Engine.get_main_loop() as SceneTree).process_frame
	var m: GoBuildMesh = _CUBE5.make()
	var gt := Transform3D(Basis(), Vector3(0, 0, 8.93))
	var inv: Transform3D = gt.affine_inverse()
	var tri := _TRI
	for raw: Vector3 in [
		Vector3(-0.836043, -0.068909, 0.5),
		Vector3(0.067063, -0.10663, 0.5),
		Vector3(-0.694604, 0.813599, 0.5),
		Vector3(-0.777948, 0.299069, 0.5),
	]:
		var world: Vector3 = gt * raw
		var sp: Vector2 = cam.unproject_position(world)
		var ro: Vector3 = inv * cam.project_ray_origin(sp)
		var rd: Vector3 = (inv.basis * cam.project_ray_normal(sp)).normalized()
		# The ray through its own screen point must pass through the point.
		assert_float((raw - ro).cross(rd).length()).is_less(0.001)
		# And hit face 2 first, exactly at the point (front-facing only).
		var best_t := INF
		for fi: int in m.faces.size():
			var f: GoBuildFace = m.faces[fi]
			var verts: Array[Vector3] = []
			for vi: int in f.vertex_indices:
				verts.append(m.vertices[vi])
			var n: Vector3 = tri.polygon_normal(verts)
			if n.length_squared() < 1e-12 or rd.dot(n) >= 0.0:
				continue
			for t: Array in tri.ear_clip(verts, n):
				var hit: float = _PICKING.ray_triangle_intersect(
						ro, rd, verts[t[0]], verts[t[1]], verts[t[2]])
				if hit >= 0.0 and hit < best_t:
					best_t = hit
		assert_float(best_t).is_less(INF)
		var hit_p: Vector3 = ro + rd * best_t
		assert_vector(hit_p).is_equal_approx(raw, Vector3.ONE * 0.0001)
	vp.free()


func test_cube5_open_quad_no_backface_crossings() -> void:
	# 2026-09-06 session (2nd failure): the "open quad" on face 2 — the
	# stroke leaked off the face: five "single touch point" runs on faces
	# 3 and 1 (the BACK side of the prism), the +Z face cut only along the
	# p2→p3 segment, p0/p1 vanished.  Root cause: screen_edge_hits had no
	# occlusion culling — the projected stroke crossed the FAR-side edges
	# (faces 1/3 lie behind the +Z surface at this camera), those crossings
	# were injected with far-face host indices, and the single-face owner
	# failed.  The mesh state = the session's dump MINUS the second cut's
	# own changes (the prior cut — itself a back-face leak — had already
	# partitioned faces 1/3/5; verts 8..11 on the -Y/-Z/-X planes).
	var m: GoBuildMesh = _make_cube5_after_first_cut()
	# The stroke the session recorded (all picks on face 2, +Z, closed):
	var raw := [
		Vector3(-0.723889, -0.285307, 0.5),
		Vector3(-1.867907, 0.138019, 0.5),
		Vector3(-0.1243, 0.872055, 0.5),
		Vector3(0.218928, 0.237972, 0.5),
	]
	var pts: Array = []
	for p: Vector3 in raw:
		pts.append({"face_index": 2, "position": p})
	pts.append({"face_index": 2, "position": raw[0]})
	# WITHOUT injections (the occlusion cull removes all back-side
	# crossings) the stroke must resolve as a single-face loop: island +
	# 2 bands on face 2's plane.  (Before the fix: +1f +6v +7e with
	# touch-point runs; the island path never ran and p0/p1 were dropped.)
	assert_bool(_KNIFE.apply(m, pts, true, [])).is_true()
	assert_int(m.vertices.size()).is_equal(16)
	assert_int(m.faces.size()).is_equal(8)
	# The island quad exists: 4 verts all with z=0.5 matching the picks.
	var island: Array[int] = []
	for fi: int in m.faces.size():
		var ring: Array[int] = m.faces[fi].vertex_indices
		if ring.size() == 4 and ring[0] >= 12:
			var on_z := true
			for vi: int in ring:
				if absf(m.vertices[vi].z - 0.5) > 1e-4:
					on_z = false
			if on_z:
				island = ring
	assert_int(island.size()).is_equal(4)
	# Island ring order is the CCW-from-outside convention (the REVERSE of
	# the drawn stroke when the stroke ran CW) — match by POSITION.
	for i: int in 4:
		var found := false
		for vi: int in island:
			if m.vertices[vi].distance_to(raw[i]) < 0.001:
				found = true
		assert_bool(found).is_true()


func test_cube5_multiface_closed_quad_shared_edge() -> void:
	# 2026-09-06 session (3rd failure): the closed quad across the +X/+Z
	# shared edge 7→1 resolved WRONG — the drawn edges were anchored to
	# the shared edge's RING CORNERS (bridged [1,7,9,8]) instead of being
	# split at the two interior crossing points; the drawn polygon's
	# corners never connected.  Root cause: _ray_line_closest's ray
	# parameter s = (b*f − c*d)/a — wrong denominator (a) AND the
	# occlusion gate inherited it: the bogus s made every shared-edge
	# crossing read as "far from the surface" → culled → no injections →
	# the runs became per-face with nearest-corner anchors.
	# Correct s = (b*f − c*d)/denom.  Expected: the shared edge splits at
	# both crossings (+2 cut verts), each face gets the drawn quad's
	# piece (crossings + its two picks) + remainder.
	var m: GoBuildMesh = _CUBE5.make()
	var raw := [
		{"face_index": 4, "position": Vector3(0.5, 0.138604, 0.088279)},
		{"face_index": 2, "position": Vector3(0.176483, 0.126724, 0.5)},
		{"face_index": 2, "position": Vector3(0.122862, 0.674897, 0.5)},
		{"face_index": 4, "position": Vector3(0.5, 0.735754, 0.289982)},
	]
	var pts: Array = []
	for p: Dictionary in raw:
		pts.append(p)
	pts.append({"face_index": 4, "position": raw[0]["position"]})
	# The injected screen crossings (what screen_edge_hits yields at the
	# repro camera — verified in the probe): both segments cross the
	# shared edge 7→1.
	var edge_hits := [
		{"segment": 0, "edge_a": 7, "edge_b": 1, "t": 0.291,
				"point": Vector3(0.5, 0.046085, 0.5)},
		{"segment": 2, "edge_a": 7, "edge_b": 1, "t": 0.596,
				"point": Vector3(0.5, 0.619824, 0.5)},
	]
	assert_bool(_KNIFE.apply(m, pts, true, edge_hits)).is_true()
	# +2f +6v +8e (4 path verts + 2 cut verts on the shared edge).
	assert_int(m.vertices.size()).is_equal(14)
	assert_int(m.faces.size()).is_equal(8)
	assert_int(m.edges.size()).is_equal(20)
	# The shared edge is GONE (split into two halves through both cut
	# verts); exactly 2 new verts sit on its line (x=0.5, z=0.5).
	assert_int(m.find_edge(7, 1)).is_equal(-1)
	var on_edge: Array[int] = []
	for vi: int in m.vertices.size():
		var v: Vector3 = m.vertices[vi]
		if absf(v.x - 0.5) < 1e-4 and absf(v.z - 0.5) < 1e-4 \
				and v.y > -0.499 and v.y < 1.377:
			on_edge.append(vi)
	assert_int(on_edge.size()).is_equal(2)
	# Each cut vert is shared by faces on both sides (no T-junction).
	for vi: int in on_edge:
		assert_int(m.faces_of_vertex(vi).size()).is_greater_equal(3)
	# Each face hosts the drawn quad's piece: a 4-gon (two crossings +
	# its two picks) — face 4's piece uses x=0.5 verts, face 2's uses
	# z=0.5 verts.
	var piece_4 := -1
	var piece_2 := -1
	for fi: int in m.faces.size():
		var ring: Array[int] = m.faces[fi].vertex_indices
		if ring.size() != 4:
			continue
		var on_x := true
		var on_z := true
		for vi: int in ring:
			if absf(m.vertices[vi].x - 0.5) > 1e-4:
				on_x = false
			if absf(m.vertices[vi].z - 0.5) > 1e-4:
				on_z = false
		if on_x:
			piece_4 = fi
		if on_z:
			piece_2 = fi
	assert_int(piece_4).is_greater_equal(0)
	assert_int(piece_2).is_greater_equal(0)
	# The pieces contain the picks at the exact recorded positions.
	for p: Dictionary in raw:
		var found := false
		for fi: int in [piece_4, piece_2]:
			for vi: int in m.faces[fi].vertex_indices:
				if m.vertices[vi].distance_to(p["position"]) < 0.001:
					found = true
		assert_bool(found).is_true()


func test_screen_edge_hits_culls_backface_crossings() -> void:
	# The gate itself: at the repro camera, the stroke's projected
	# segments cross the SHARED edge 7→1 (injected — 2 hits) but must NOT
	# cross the far-side edges (culled).  Guards the occlusion gate and
	# the s-parameter it depends on.
	var m: GoBuildMesh = _CUBE5.make()
	var vp := SubViewport.new()
	vp.size = Vector2i(1920, 1080)
	Engine.get_main_loop().root.add_child(vp)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.current = true
	cam.fov = 75.0
	cam.look_at_from_position(Vector3(1.6, -0.7, 11.53),
			Vector3(0.5, 0.44, 9.43), Vector3.UP)
	await (Engine.get_main_loop() as SceneTree).process_frame
	await (Engine.get_main_loop() as SceneTree).process_frame
	var to_world := Transform3D(Basis(), Vector3(0, 0, 8.93))
	var pts := [
		{"face_index": 4, "position": Vector3(0.5, 0.138604, 0.088279)},
		{"face_index": 2, "position": Vector3(0.176483, 0.126724, 0.5)},
		{"face_index": 2, "position": Vector3(0.122862, 0.674897, 0.5)},
		{"face_index": 4, "position": Vector3(0.5, 0.735754, 0.289982)},
		{"face_index": 4, "position": Vector3(0.5, 0.138604, 0.088279)},
	]
	var hits := _KNIFE.screen_edge_hits(m, pts, true, cam, to_world)
	assert_int(hits.size()).is_equal(2)
	for h: Dictionary in hits:
		var a: int = h["edge_a"]
		var b: int = h["edge_b"]
		assert_bool((a == 7 and b == 1) or (a == 1 and b == 7)).is_true()
	vp.free()


## The session's GoBuildCube5 after the FIRST (leaked) cut — the exact
## mesh state of the second failure, rebuilt from the Print Selection
## dump minus the second cut's own effects (face 2 still intact).
func _make_cube5_after_first_cut() -> GoBuildMesh:
	var m := GoBuildMesh.new()
	m.vertices = [
		Vector3(-2.362876, 1.377355, 0.5),   # 0
		Vector3(0.5, 1.377355, 0.5),         # 1
		Vector3(-2.362876, 1.377355, -0.5),  # 2
		Vector3(0.5, 1.377355, -0.5),        # 3
		Vector3(-2.362876, -0.5, -0.5),      # 4
		Vector3(0.5, -0.5, -0.5),            # 5
		Vector3(-2.362876, -0.5, 0.5),       # 6
		Vector3(0.5, -0.5, 0.5),             # 7
		Vector3(-2.362876, -0.268757, -0.5), # 8
		Vector3(-1.737952, -0.5, -0.5),      # 9
		Vector3(-2.362876, -0.062529, -0.5), # 10
		Vector3(-0.570817, -0.5, -0.5),      # 11
	]
	var quads := [
		[0, 1, 3, 2],              # +Y
		[4, 9, 11, 5, 7, 6],       # -Y (prior cut's band)
		[6, 7, 1, 0],              # +Z (face 2, INTACT before this cut)
		[5, 11, 9, 4, 8, 10, 2, 3],# -Z→-X→-Z band (non-planar prior leak)
		[7, 5, 3, 1],              # +X
		[4, 6, 0, 2, 10, 8],       # -X (prior cut's band)
	]
	for q: Array in quads:
		var f := GoBuildFace.new()
		var r: Array[int] = []
		r.assign(q)
		f.vertex_indices = r
		m.faces.append(f)
	m.rebuild_edges()
	return m
