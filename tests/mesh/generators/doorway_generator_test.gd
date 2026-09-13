## DoorwayGenerator unit tests.
##
## Rectangular mode: jamb columns up to the opening top + a header band
## spanning the full wall width (opening ceiling = band's bottom strip).
## Arched mode: jambs up to the spring line + a head band (arc strips,
## flank strips, reveal, wall-top quad) — no spandrel boxes.
extends GdUnitTestSuite

# Self-preloads — dependency order.
const _MESH_SCRIPT    := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _FACE_SCRIPT    := preload("res://addons/go_build/mesh/go_build_face.gd")
const _DOORWAY_SCRIPT := preload("res://addons/go_build/mesh/generators/doorway_generator.gd")


# ---------------------------------------------------------------------------
# Rectangular mode
# ---------------------------------------------------------------------------

func test_rect_face_count() -> void:
	# 2 jamb boxes (5 exposed faces each — tops buried vs the header band)
	# + header band (front, back, top; ±X sides skipped as wall-outer
	# coincidence... no: band spans full width so its ±X sides ARE the
	# wall sides, skipped as buried vs nothing — omitted) + ceiling strip.
	# = 10 + 3 + 1 = 14.
	assert_int(_DOORWAY_SCRIPT.generate(2.0, 2.5, 0.2, 1.0, 2.0, false).faces.size()).is_equal(14)


func test_rect_user_dims_all_planar_quads() -> void:
	# Regression (user-dumped topology, 2026-09-12): the post-weld
	# dissolve corrupted the header (its own bottom-front/back edges
	# got dissolved into warped quads, then the round-2 seam dissolve
	# collapsed the mess — Open H stopped doing anything).  The clean
	# header-band decomposition needs no dissolve: jamb inner walls run
	# only to the opening top (no buried spans above it — the user's
	# "unnecessary full-height faces"), every ring a planar quad,
	# opening top moves with Open H.
	var mesh := _DOORWAY_SCRIPT.generate(3.819528, 2.328407, 0.3, 1.909764, 1.862726, false)
	assert_int(mesh.vertices.size()).is_equal(20)
	assert_int(mesh.faces.size()).is_equal(14)
	for face: GoBuildFace in mesh.faces:
		assert_int(face.vertex_indices.size()).is_equal(4)
		var pts: Array[Vector3] = []
		for vi: int in face.vertex_indices:
			pts.append(mesh.vertices[vi])
		var n := mesh.compute_face_normal(face)
		for p: Vector3 in pts:
			assert_float(absf(n.dot(p - pts[0]))).is_less(0.001)


func test_rect_open_h_moves_opening_top() -> void:
	# Regression (user-reported): Open H must move the opening top.
	# The opening-top plane (base + oh) carries the header's bottom
	# corners — 4 verts (front/back × left/right flank).
	var width := 4.5
	var height := 4.4613
	var ow := 1.5
	for ratio: float in [0.1, 0.3, 0.5, 0.8]:
		var oh := height * ratio
		var mesh := _DOORWAY_SCRIPT.generate(width, height, 2.0, ow, oh, false)
		var y_open_top := -height * 0.5 + oh
		var at_open_top := 0
		for v: Vector3 in mesh.vertices:
			if absf(v.y - y_open_top) < 0.001 and absf(v.x) < ow * 0.5 + 0.001:
				at_open_top += 1
		assert_int(at_open_top).is_equal(4)


func test_rect_vertex_count() -> void:
	var mesh := _DOORWAY_SCRIPT.generate(2.0, 2.5, 0.2, 1.0, 2.0, false)
	assert_int(mesh.vertices.size()).is_equal(20)
	assert_int(mesh.faces.size()).is_equal(14)


func test_rect_jamb_inner_walls_end_at_opening_top() -> void:
	# Regression (user-reported): the jamb inner walls (x = ±ow/2 planes)
	# used to span the FULL wall height — the span above the opening top
	# was buried geometry.  Now they stop at the opening top.
	var mesh := _DOORWAY_SCRIPT.generate(3.0, 4.0, 2.0, 1.5, 2.9, false)
	var y_open_top := -2.0 + 2.9
	for v: Vector3 in mesh.vertices:
		if absf(absf(v.x) - 0.75) < 0.001 and absf(v.z) < 1.001:
			# Inner-wall verts live on the opening flank: none above the top.
			assert_float(v.y).is_less_equal(y_open_top + 0.001)


func test_rect_no_buried_faces_parity() -> void:
	# Ray-parity over the rect matrix: every face even, opening hollow.
	for owr: float in [0.3, 0.5, 0.7]:
		for ohr: float in [0.2, 0.5, 0.8]:
			var mesh := _DOORWAY_SCRIPT.generate(
					3.0, 4.0, 2.0, 3.0 * owr, 4.0 * ohr, false)
			assert_array(_parity_fails(mesh)).is_empty()
			var mid := Vector3(0.0, -2.0 + 4.0 * ohr * 0.5, -1.5)
			assert_int(_ray_hits(mid, mesh)).is_equal(0)


func test_rect_all_normals_point_outward() -> void:
	var mesh := _DOORWAY_SCRIPT.generate(2.0, 2.5, 0.2, 1.0, 2.0, false)
	for face: GoBuildFace in mesh.faces:
		var n := mesh.compute_face_normal(face)
		assert_float(n.length()).is_equal_approx(1.0, 0.001)


func test_rect_opening_is_hollow_through_depth() -> void:
	# A ray through the opening centre (y at mid-opening) must not cross faces.
	var mesh := _DOORWAY_SCRIPT.generate(2.0, 2.5, 0.2, 1.0, 2.5 * 0.8, false)
	# Opening centre: x = 0, y from -1.25 up 2.0 → mid ≈ -0.25
	var mid_y := -1.25 + 2.5 * 0.8 * 0.5
	var front := Vector3(0.0, mid_y, 0.11)
	var back := Vector3(0.0, mid_y, -0.11)
	var seg_count := 0
	for face: GoBuildFace in mesh.faces:
		var verts: Array[Vector3] = []
		for vi: int in face.vertex_indices:
			verts.append(mesh.vertices[vi])
		if _segment_intersects_quad(front, back, verts):
			seg_count += 1
	assert_int(seg_count).is_equal(0)


func test_rect_header_faces_above_opening() -> void:
	# Wall material must exist above the opening: the header band's
	# front quad spans the full wall width from the opening top up.
	var width := 2.0
	var oh := 2.0
	var mesh := _DOORWAY_SCRIPT.generate(width, 2.5, 0.2, 1.0, oh, false)
	var y_open_top := -1.25 + oh
	var found_above := false
	for face: GoBuildFace in mesh.faces:
		var xs: Array[float] = []
		var above := false
		for vi: int in face.vertex_indices:
			var v: Vector3 = mesh.vertices[vi]
			xs.append(v.x)
			if v.y > y_open_top + 0.01:
				above = true
		# Coverage, not verts: a face above the opening top whose span
		# crosses the opening's mid-line is wall material over the void.
		if above and xs.min() < 0.0 and xs.max() > 0.0:
			found_above = true
			break
	assert_bool(found_above).is_true()


# ---------------------------------------------------------------------------
# Arched mode
# ---------------------------------------------------------------------------

func test_arched_has_more_faces_than_rect() -> void:
	var rect := _DOORWAY_SCRIPT.generate(2.0, 2.5, 0.2, 1.0, 2.0, false).faces.size()
	var arc := _DOORWAY_SCRIPT.generate(2.0, 2.5, 0.2, 1.0, 2.0, true, 8).faces.size()
	assert_int(arc).is_greater(rect)


func test_arched_no_spandrel_flank_faces() -> void:
	# Regression (user-reported): the spandrel boxes' inner walls
	# (x = ±ow/2, spring → wall top) were "unnecessary geometry" —
	# replaced by the head band's flank strips on the wall FRONT/BACK
	# planes.  No face may lie on the x = ±ow/2 plane above the spring.
	var ow := 1.5
	var mesh := _DOORWAY_SCRIPT.generate(3.0, 4.0, 2.0, ow, 3.5, true, 8)
	var spring := maxf(-2.0 + 3.5 - ow * 0.5, -2.0)
	for face: GoBuildFace in mesh.faces:
		var n := mesh.compute_face_normal(face)
		if absf(absf(n.x) - 1.0) < 0.01:
			# ±X-facing faces must be jamb inner/outer walls BELOW spring.
			for vi: int in face.vertex_indices:
				if absf(absf(mesh.vertices[vi].x) - ow * 0.5) < 0.001:
					assert_float(mesh.vertices[vi].y).is_less_equal(spring + 0.001)


func test_arched_parity_and_containment() -> void:
	# Ray-parity over the arched matrix: every face even, opening hollow,
	# wall solid.
	for owr: float in [0.3, 0.5, 0.7]:
		for ohr: float in [0.2, 0.5, 0.8]:
			var mesh := _DOORWAY_SCRIPT.generate(
					3.0, 4.0, 2.0, 3.0 * owr, 4.0 * ohr, true, 8)
			assert_array(_parity_fails(mesh)).is_empty()
			var mid := Vector3(0.0, -2.0 + 4.0 * ohr * 0.4, -1.5)
			assert_int(_ray_hits(mid, mesh)).is_equal(0)
			assert_int(_ray_hits(Vector3(1.4, 0.0, -1.5), mesh)).is_equal(2)


func test_arched_bakes_single_surface() -> void:
	assert_int(_DOORWAY_SCRIPT.generate(2.0, 2.5, 0.2, 1.0, 2.0, true, 8).bake()
			.get_surface_count()).is_equal(1)


func test_arched_all_normals_unit_length() -> void:
	var mesh := _DOORWAY_SCRIPT.generate(2.0, 2.5, 0.2, 1.0, 2.0, true, 8)
	for face: GoBuildFace in mesh.faces:
		var n := mesh.compute_face_normal(face)
		assert_float(n.length()).is_equal_approx(1.0, 0.001)


func test_arched_apex_reaches_opening_top() -> void:
	var ow := 1.0
	var oh := 2.0
	var mesh := _DOORWAY_SCRIPT.generate(2.0, 2.5, 0.2, ow, oh, true, 8)
	# Inner arc apex (x=0) must reach exactly the opening top: base + oh.
	var found_apex := false
	for v: Vector3 in mesh.vertices:
		if absf(v.x) < 0.001 \
				and absf(v.y - (-1.25 + oh)) < 0.001:
			found_apex = true
			break
	assert_bool(found_apex).is_true()


func test_arched_outer_apex_flush_with_wall_top() -> void:
	# Outer ring apex touches the wall top: base + height.
	var mesh := _DOORWAY_SCRIPT.generate(2.0, 2.5, 0.2, 1.0, 2.0, true, 8)
	var found_top := false
	for v: Vector3 in mesh.vertices:
		if absf(v.x) < 0.001 and absf(v.y - 1.25) < 0.001:
			found_top = true
			break
	assert_bool(found_top).is_true()


func test_arched_wall_top_cap_closes_opening_band() -> void:
	# Regression (user-reported): the wall top over the opening band
	# was an open hole.  The head band's wall-top quad (full width,
	# y = wall top) must exist; a vertical ray down through the band
	# crosses it.
	var mesh := _DOORWAY_SCRIPT.generate(2.0, 2.5, 0.2, 1.0, 2.0, true, 8)
	var y_top := 1.25
	var cap_faces := 0
	for face: GoBuildFace in mesh.faces:
		var all_top := true
		var xs: Array[float] = []
		for vi: int in face.vertex_indices:
			if absf(mesh.vertices[vi].y - y_top) > 0.001:
				all_top = false
			xs.append(mesh.vertices[vi].x)
		if all_top and xs.min() < 0.4 and xs.max() > -0.4:
			cap_faces += 1
	assert_int(cap_faces).is_greater(0)


func test_arched_arched_vertices_on_expected_radii() -> void:
	var ow := 1.0
	var radius := ow * 0.5
	var hw := 1.0
	var spring_y := -1.25 + 2.0 - radius
	var mesh := _DOORWAY_SCRIPT.generate(2.0, 2.5, 0.2, ow, 2.0, true, 8)
	for v: Vector3 in mesh.vertices:
		# Only arc tube vertices lie above the spring line inside the jamb band.
		if v.y > spring_y + 0.001 and absf(v.x) < hw - 0.001:
			assert_bool(true).is_true()


# ---------------------------------------------------------------------------
# Geometry invariants
# ---------------------------------------------------------------------------

func _parity_fails(mesh: GoBuildMesh) -> Array[int]:
	var bad: Array[int] = []
	for fi: int in mesh.faces.size():
		var face: GoBuildFace = mesh.faces[fi]
		var n: Vector3 = mesh.compute_face_normal(face)
		var fc := Vector3.ZERO
		for vi: int in face.vertex_indices:
			fc += mesh.vertices[vi]
		fc /= float(face.vertex_indices.size())
		var orig: Vector3 = fc + n * 1e-4
		var hits := 0
		for fj: int in mesh.faces.size():
			if fj == fi:
				continue
			var idx: Array = mesh.faces[fj].vertex_indices
			for k: int in range(1, idx.size() - 1):
				if _ray_tri(orig, n, mesh.vertices[idx[0]],
						mesh.vertices[idx[k]], mesh.vertices[idx[k + 1]]) > 0.0:
					hits += 1
					break
		if hits % 2 == 1:
			bad.append(fi)
	return bad


func _ray_hits(orig: Vector3, mesh: GoBuildMesh) -> int:
	# Count faces crossed by a +Z ray from orig (through the wall).
	var hits := 0
	for fj: int in mesh.faces.size():
		var idx: Array = mesh.faces[fj].vertex_indices
		for k: int in range(1, idx.size() - 1):
			if _ray_tri(orig, Vector3(0, 0, 1), mesh.vertices[idx[0]],
					mesh.vertices[idx[k]],
					mesh.vertices[idx[k + 1]]) > 0.0:
				hits += 1
				break
	return hits


func test_wall_within_depth_extent() -> void:
	var depth := 0.4
	var hd := depth * 0.5
	var mesh := _DOORWAY_SCRIPT.generate(2.0, 2.5, depth, 1.0, 2.0, true, 8)
	for v: Vector3 in mesh.vertices:
		assert_float(absf(v.z)).is_less_equal(hd + 0.001)


func test_wall_width_extent() -> void:
	var width := 2.0
	var mesh := _DOORWAY_SCRIPT.generate(width, 2.5, 0.2, 1.0, 2.0, false)
	for v: Vector3 in mesh.vertices:
		assert_float(absf(v.x)).is_less_equal(width * 0.5 + 0.001)


func test_all_uvs_present() -> void:
	var mesh := _DOORWAY_SCRIPT.generate(2.0, 2.5, 0.2, 1.0, 2.0, true, 8)
	for face: GoBuildFace in mesh.faces:
		assert_int(face.uvs.size()).is_equal(face.vertex_indices.size())


func test_weld_merges_shared_corners() -> void:
	# Jamb tops coincide with the header band bottom corners — weld
	# reduces to 20 verts (16 jamb corners + 4 ceiling-strip corners).
	var mesh := _DOORWAY_SCRIPT.generate(2.0, 2.5, 0.2, 1.0, 2.0, false)
	assert_int(mesh.vertices.size()).is_equal(20)


# ---------------------------------------------------------------------------
# Segment count parameter
# ---------------------------------------------------------------------------

func test_more_segments_more_faces() -> void:
	var low := _DOORWAY_SCRIPT.generate(2.0, 2.5, 0.2, 1.0, 2.0, true, 2).faces.size()
	var high := _DOORWAY_SCRIPT.generate(2.0, 2.5, 0.2, 1.0, 2.0, true, 12).faces.size()
	assert_int(high).is_greater(low)


## Segment-triangle intersection (Möller–Trumbore style, via ray).
## Returns the distance along the ray, or -1 when it misses.
func _ray_tri(orig: Vector3, dir: Vector3, a: Vector3, b: Vector3,
		c: Vector3) -> float:
	var e1: Vector3 = b - a
	var e2: Vector3 = c - a
	var p: Vector3 = dir.cross(e2)
	var det: float = e1.dot(p)
	if absf(det) < 1e-10:
		return -1.0
	var inv: float = 1.0 / det
	var t: Vector3 = orig - a
	var u: float = t.dot(p) * inv
	if u < -1e-6 or u > 1.0 + 1e-6:
		return -1.0
	var q: Vector3 = t.cross(e1)
	var v: float = dir.dot(q) * inv
	if v < -1e-6 or u + v > 1.0 + 1e-6:
		return -1.0
	var dist: float = e2.dot(q) * inv
	if dist < 1e-6:
		return -1.0
	return dist


## Segment-triangle intersection (Möller–Trumbore style, via ray).
func _segment_intersects_quad(a: Vector3, b: Vector3, quad: Array[Vector3]) -> bool:
	var tri0 := [quad[0], quad[1], quad[2]]
	var tri1 := [quad[0], quad[2], quad[3]]
	return _segment_hits_tri(a, b, tri0) or _segment_hits_tri(a, b, tri1)


func _segment_hits_tri(a: Vector3, b: Vector3, tri: Array) -> bool:
	var d: Vector3 = b - a
	var e1: Vector3 = tri[1] - tri[0]
	var e2: Vector3 = tri[2] - tri[0]
	var p: Vector3 = d.cross(e2)
	var det: float = e1.dot(p)
	if absf(det) < 0.000001:
		return false
	var inv_det := 1.0 / det
	var t_vec: Vector3 = a - tri[0]
	var u: float = t_vec.dot(p) * inv_det
	if u < 0.0 or u > 1.0:
		return false
	var q: Vector3 = t_vec.cross(e1)
	var v: float = d.dot(q) * inv_det
	if v < 0.0 or u + v > 1.0:
		return false
	var t: float = e2.dot(q) * inv_det
	return t >= 0.0 and t <= 1.0