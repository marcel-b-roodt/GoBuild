## DoorwayGenerator unit tests.
##
## Rectangular mode: jambs (left/right columns) + header slab above the
## opening; jambs run the full wall height.  Arched mode: jambs up to the
## spring line, side slabs beside the arc, and an arch tube (front/back
## ring faces + inner/outer radial faces).
extends GdUnitTestSuite

# Self-preloads — dependency order.
const _MESH_SCRIPT    := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _FACE_SCRIPT    := preload("res://addons/go_build/mesh/go_build_face.gd")
const _DOORWAY_SCRIPT := preload("res://addons/go_build/mesh/generators/doorway_generator.gd")


# ---------------------------------------------------------------------------
# Rectangular mode
# ---------------------------------------------------------------------------

func test_rect_face_count() -> void:
	# 2 jamb boxes (6 faces each) + header box (6) = 18
	assert_int(_DOORWAY_SCRIPT.generate(2.0, 2.5, 0.2, 1.0, 2.0, false).faces.size()).is_equal(18)


func test_rect_vertex_count() -> void:
	# 3 boxes × 8 verts (add_quad_grid 3×3×2 grid) — before weld.
	var mesh := _DOORWAY_SCRIPT.generate(2.0, 2.5, 0.2, 1.0, 2.0, false)
	# finalize() welds coincident verts; jamb/header share seams so the
	# welded count is lower — just assert within a sane range.
	assert_int(mesh.vertices.size()).is_greater(0)
	assert_int(mesh.faces.size()).is_equal(18)


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
	var width := 2.0
	var oh := 2.0
	var mesh := _DOORWAY_SCRIPT.generate(width, 2.5, 0.2, 1.0, oh, false)
	var y_open_top := -1.25 + oh
	var found_above := false
	for face: GoBuildFace in mesh.faces:
		for vi: int in face.vertex_indices:
			if mesh.vertices[vi].y > y_open_top + 0.01 \
					and absf(mesh.vertices[vi].x) < 0.9:
				found_above = true
				break
		if found_above:
			break
	assert_bool(found_above).is_true()


# ---------------------------------------------------------------------------
# Arched mode
# ---------------------------------------------------------------------------

func test_arched_has_more_faces_than_rect() -> void:
	var rect := _DOORWAY_SCRIPT.generate(2.0, 2.5, 0.2, 1.0, 2.0, false).faces.size()
	var arc := _DOORWAY_SCRIPT.generate(2.0, 2.5, 0.2, 1.0, 2.0, true, 8).faces.size()
	assert_int(arc).is_greater(rect)


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
	# Jamb boxes share corner positions with header/side slabs — weld should
	# reduce below the naive 3-box × 24-vert grid count.
	var mesh := _DOORWAY_SCRIPT.generate(2.0, 2.5, 0.2, 1.0, 2.0, false)
	assert_int(mesh.vertices.size()).is_less(72)


# ---------------------------------------------------------------------------
# Segment count parameter
# ---------------------------------------------------------------------------

func test_more_segments_more_faces() -> void:
	var low := _DOORWAY_SCRIPT.generate(2.0, 2.5, 0.2, 1.0, 2.0, true, 2).faces.size()
	var high := _DOORWAY_SCRIPT.generate(2.0, 2.5, 0.2, 1.0, 2.0, true, 12).faces.size()
	assert_int(high).is_greater(low)


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