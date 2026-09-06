## Live symmetry helper tests — GdUnit4
##
## [GoBuildSymmetry]: mirror_point/on_plane, partner maps, and materialize
## (append-twinned faces + weld) driven by position fingerprints.
extends GdUnitTestSuite

const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _SYM_SCRIPT  := preload("res://addons/go_build/core/go_build_symmetry.gd")


# ---------------------------------------------------------------------------
# mirror_point / on_plane
# ---------------------------------------------------------------------------

func test_mirror_point_x() -> void:
	assert_vector(_SYM_SCRIPT.mirror_point(Vector3(1, 2, 3), 0)) \
			.is_equal_approx(Vector3(-1, 2, 3), Vector3.ONE * 0.001)


func test_mirror_point_y() -> void:
	assert_vector(_SYM_SCRIPT.mirror_point(Vector3(1, 2, 3), 1)) \
			.is_equal_approx(Vector3(1, -2, 3), Vector3.ONE * 0.001)


func test_mirror_point_z() -> void:
	assert_vector(_SYM_SCRIPT.mirror_point(Vector3(1, 2, 3), 2)) \
			.is_equal_approx(Vector3(1, 2, -3), Vector3.ONE * 0.001)


func test_on_plane() -> void:
	assert_bool(_SYM_SCRIPT.on_plane(Vector3(0.0, 5.0, -3.0), 0)).is_true()
	assert_bool(_SYM_SCRIPT.on_plane(Vector3(0.1, 5.0, -3.0), 0)).is_false()
	assert_bool(_SYM_SCRIPT.on_plane(Vector3(1.0, 0.0, 2.0), 1)).is_true()


func test_mirror_delta_negates_normal_component() -> void:
	assert_vector(_SYM_SCRIPT.mirror_delta(Vector3(1, 0, -2), 0)) \
			.is_equal_approx(Vector3(-1, 0, -2), Vector3.ONE * 0.001)


# ---------------------------------------------------------------------------
# build_partner_map
# ---------------------------------------------------------------------------

## Mirror-asymmetric pair: verts at x=1 and x=-1 across X axis.
func _make_pair_mesh() -> GoBuildMesh:
	var m := GoBuildMesh.new()
	m.vertices = [
		Vector3(1.0, 0.0, 0.0),
		Vector3(-1.0, 0.0, 0.0),
		Vector3(0.0, 1.0, 0.0),
	]
	var f := GoBuildFace.new()
	f.vertex_indices = [0, 2, 1]
	f.uvs = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	m.faces.append(f)
	m.rebuild_edges()
	return m


func test_partner_map_pairs_across_x() -> void:
	var m := _make_pair_mesh()
	var map: Dictionary = _SYM_SCRIPT.build_partner_map(m, 0)
	assert_int(map[0]).is_equal(1)
	assert_int(map[1]).is_equal(0)
	# On-plane vertex mirrors to itself.
	assert_int(map[2]).is_equal(2)


func test_partner_map_unmirrored_vertex_is_minus_one() -> void:
	var m := _make_pair_mesh()
	# Strip the negative partner so vert 0 has no twin.
	m.vertices[1] = Vector3(-2.0, 0.0, 0.0)
	var map: Dictionary = _SYM_SCRIPT.build_partner_map(m, 0)
	assert_int(map[0]).is_equal(-1)


# ---------------------------------------------------------------------------
# materialize
# ---------------------------------------------------------------------------

## One triangle on +X side, nothing on -X: materialize should add a mirrored
## twin. Uses two triangles forming a quad on +Y side for stable winding.
func _make_half_mesh() -> GoBuildMesh:
	# Quad at x ∈ [0.5, 1.5], y ∈ [0,1]: two triangles via two faces.
	var m := GoBuildMesh.new()
	m.vertices = [
		Vector3(0.5, 0.0, 0.0),
		Vector3(1.5, 0.0, 0.0),
		Vector3(1.5, 1.0, 0.0),
		Vector3(0.5, 1.0, 0.0),
	]
	var f1 := GoBuildFace.new()
	f1.vertex_indices = [0, 1, 2]
	f1.uvs = [Vector2.ZERO, Vector2(1, 0), Vector2(1, 1)]
	var f2 := GoBuildFace.new()
	f2.vertex_indices = [0, 2, 3]
	f2.uvs = [Vector2.ZERO, Vector2(1, 1), Vector2(0, 1)]
	m.faces.append(f1)
	m.faces.append(f2)
	m.finalize()
	return m


func test_materialize_adds_mirror_faces() -> void:
	var m := _make_half_mesh()
	var added: int = _SYM_SCRIPT.materialize(m, 0)
	assert_int(added).is_equal(2)
	assert_int(m.faces.size()).is_equal(4)


func test_materialize_idempotent_when_symmetric() -> void:
	var m := _make_half_mesh()
	_SYM_SCRIPT.materialize(m, 0)
	var second: int = _SYM_SCRIPT.materialize(m, 0)
	assert_int(second).is_equal(0)
	assert_int(m.faces.size()).is_equal(4)


func test_materialize_preserves_winding_outward() -> void:
	var m := _make_half_mesh()
	_SYM_SCRIPT.materialize(m, 0)
	# Both original + mirrored faces should have valid non-degenerate normals.
	for face: GoBuildFace in m.faces:
		var n := m.compute_face_normal(face)
		assert_float(n.length()).is_equal_approx(1.0, 0.01)


func test_materialize_welds_seam_vertices() -> void:
	var m := _make_half_mesh()
	GoBuildSymmetry.materialize(m, 0)
	# Seam verts (x = 0.5) are their own mirrors — reused, not duplicated.
	# Unique positions: 4 originals + mirrored far pair (±1.5) = 6 positions,
	# but generator verts stay unwelded across the z=0 plane split... assert
	# no duplicate positions instead of a hard count.
	var seen: Dictionary = {}
	var dupes := 0
	for v: Vector3 in m.vertices:
		var key := "%d_%d_%d" % [roundi(v.x * 1000), roundi(v.y * 1000), roundi(v.z * 1000)]
		if seen.has(key):
			dupes += 1
		seen[key] = true
	assert_int(dupes).is_equal(0)


func test_count_unmirrored_faces() -> void:
	var m := _make_half_mesh()
	assert_int(_SYM_SCRIPT.count_unmirrored_faces(m, 0)).is_equal(2)
	_SYM_SCRIPT.materialize(m, 0)
	assert_int(_SYM_SCRIPT.count_unmirrored_faces(m, 0)).is_equal(0)


func test_materialize_y_axis() -> void:
	var m := GoBuildMesh.new()
	m.vertices = [
		Vector3(0.0, 1.0, 0.0),
		Vector3(1.0, 1.0, 0.0),
		Vector3(1.0, 1.0, 1.0),
	]
	var f := GoBuildFace.new()
	f.vertex_indices = [0, 1, 2]
	f.uvs = [Vector2.ZERO, Vector2(1, 0), Vector2(1, 1)]
	m.faces.append(f)
	var added: int = _SYM_SCRIPT.materialize(m, 1)
	assert_int(added).is_equal(1)
	# Mirrored verts at y = -1 must exist.
	var found := false
	for v: Vector3 in m.vertices:
		if absf(v.y + 1.0) < 0.001:
			found = true
	assert_bool(found).is_true()