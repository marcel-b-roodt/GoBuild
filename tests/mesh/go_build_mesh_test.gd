## GoBuildMesh unit tests.
extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Build a simple axis-aligned quad on the XY plane.
func _make_xy_quad() -> GoBuildMesh:
	var m := GoBuildMesh.new()
	m.vertices = [
		Vector3(0, 0, 0),
		Vector3(1, 0, 0),
		Vector3(1, 1, 0),
		Vector3(0, 1, 0),
	]
	var f := GoBuildFace.new()
	f.vertex_indices = [0, 1, 2, 3]
	f.uvs = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	m.faces.append(f)
	return m


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

func test_new_mesh_arrays_are_empty() -> void:
	var m := GoBuildMesh.new()
	assert_int(m.vertices.size()).is_equal(0)
	assert_int(m.faces.size()).is_equal(0)
	assert_int(m.edges.size()).is_equal(0)


# ---------------------------------------------------------------------------
# Bake — empty mesh
# ---------------------------------------------------------------------------

func test_bake_empty_mesh_returns_array_mesh() -> void:
	var result := GoBuildMesh.new().bake()
	assert_object(result).is_not_null()
	assert_bool(result is ArrayMesh).is_true()


func test_bake_empty_mesh_has_zero_surfaces() -> void:
	assert_int(GoBuildMesh.new().bake().get_surface_count()).is_equal(0)


# ---------------------------------------------------------------------------
# Bake — single quad (one material)
# ---------------------------------------------------------------------------

func test_bake_single_quad_produces_one_surface() -> void:
	assert_int(_make_xy_quad().bake().get_surface_count()).is_equal(1)


func test_bake_single_quad_vertex_count() -> void:
	# One quad → 2 triangles → 6 vertices in the packed array.
	var am: ArrayMesh = _make_xy_quad().bake()
	var arrays: Array = am.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert_int(verts.size()).is_equal(6)


func test_bake_triangle_winding_is_cw_from_outside() -> void:
	# Regression guard: _build_surface must emit CW triangles (from outside)
	# so Godot 4's Vulkan renderer treats them as front-facing.
	#
	# _make_xy_quad has face.vertex_indices wound CCW from +Z so that
	# compute_face_normal() returns +Z (outward).  After the winding reversal
	# in _build_surface the first emitted triangle must produce a cross product
	# that points toward -Z (CW from +Z).
	var arrays: Array = _make_xy_quad().bake().surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cross: Vector3 = (verts[1] - verts[0]).cross(verts[2] - verts[0])
	# cross.z < 0  →  CW from +Z  →  front-facing in Godot 4 Vulkan.
	assert_float(cross.z).is_less(0.0)


# ---------------------------------------------------------------------------
# Bake — two materials → two surfaces
# ---------------------------------------------------------------------------

func test_bake_two_materials_produces_two_surfaces() -> void:
	var m := GoBuildMesh.new()
	m.vertices = [
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0),
		Vector3(2, 0, 0), Vector3(3, 0, 0), Vector3(3, 1, 0), Vector3(2, 1, 0),
	]
	var f0 := GoBuildFace.new()
	f0.vertex_indices = [0, 1, 2, 3]
	f0.uvs = [Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	f0.material_index = 0

	var f1 := GoBuildFace.new()
	f1.vertex_indices = [4, 5, 6, 7]
	f1.uvs = [Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	f1.material_index = 1

	m.faces.append(f0)
	m.faces.append(f1)
	assert_int(m.bake().get_surface_count()).is_equal(2)


# ---------------------------------------------------------------------------
# Face normal — compute_face_normal
# ---------------------------------------------------------------------------

func test_face_normal_xy_plane_quad_points_in_z() -> void:
	var m := _make_xy_quad()
	var n: Vector3 = m.compute_face_normal(m.faces[0])
	assert_float(absf(n.z)).is_greater(0.99)


func test_face_normal_is_unit_length() -> void:
	var m := _make_xy_quad()
	var n: Vector3 = m.compute_face_normal(m.faces[0])
	assert_float(n.length()).is_equal_approx(1.0, 0.001)


func test_face_normal_triangle_points_in_z() -> void:
	var m := GoBuildMesh.new()
	m.vertices = [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)]
	var f := GoBuildFace.new()
	f.vertex_indices = [0, 1, 2]
	f.uvs = [Vector2.ZERO, Vector2(1, 0), Vector2(0, 1)]
	m.faces.append(f)
	var n := m.compute_face_normal(f)
	assert_float(absf(n.z)).is_greater(0.99)


# ---------------------------------------------------------------------------
# Edge derivation — rebuild_edges
# ---------------------------------------------------------------------------

func test_rebuild_edges_quad_has_four_edges() -> void:
	var m := _make_xy_quad()
	m.rebuild_edges()
	assert_int(m.edges.size()).is_equal(4)


func test_rebuild_edges_all_quad_edges_are_boundary() -> void:
	var m := _make_xy_quad()
	m.rebuild_edges()
	for edge in m.edges:
		assert_bool((edge as GoBuildEdge).is_boundary()).is_true()


func test_rebuild_edges_two_adjacent_quads_share_interior_edge() -> void:
	var m := GoBuildMesh.new()
	m.vertices = [
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0),
		Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(2, 1, 0),
	]
	var f0 := GoBuildFace.new()
	f0.vertex_indices = [0, 1, 4, 3]
	f0.uvs = [Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]

	var f1 := GoBuildFace.new()
	f1.vertex_indices = [1, 2, 5, 4]
	f1.uvs = [Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]

	m.faces.append(f0)
	m.faces.append(f1)
	m.rebuild_edges()

	# Two quads share edge 1-4; that edge should have 2 face_indices.
	var interior_count := 0
	for edge in m.edges:
		if not (edge as GoBuildEdge).is_boundary():
			interior_count += 1
	assert_int(interior_count).is_equal(1)


# ---------------------------------------------------------------------------
# Snapshot / Restore
# ---------------------------------------------------------------------------

func test_snapshot_restores_vertices() -> void:
	var m := _make_xy_quad()
	var snap := m.take_snapshot()

	m.vertices[0] = Vector3(99, 0, 0)
	m.restore_snapshot(snap)

	assert_vector3(m.vertices[0]).is_equal(Vector3(0, 0, 0))


func test_snapshot_restores_face_count() -> void:
	var m := _make_xy_quad()
	var snap := m.take_snapshot()

	m.faces.clear()
	m.restore_snapshot(snap)

	assert_int(m.faces.size()).is_equal(1)


func test_snapshot_rebuilds_edges_on_restore() -> void:
	var m := _make_xy_quad()
	m.rebuild_edges()
	var snap := m.take_snapshot()

	m.faces.clear()
	m.edges.clear()
	m.restore_snapshot(snap)

	# restore_snapshot calls rebuild_edges internally.
	assert_int(m.edges.size()).is_equal(4)


func test_snapshot_is_deep_copy() -> void:
	var m := _make_xy_quad()
	var snap := m.take_snapshot()

	# Mutate the snapshot's vertex array — should not affect m.
	var snap_verts: Array[Vector3] = snap["vertices"]
	snap_verts[0] = Vector3(99, 0, 0)

	assert_vector3(m.vertices[0]).is_equal(Vector3(0, 0, 0))


# ---------------------------------------------------------------------------
# translate_vertices
# ---------------------------------------------------------------------------

func test_translate_moves_specified_vertices() -> void:
	var m := _make_xy_quad()
	var indices: Array[int] = [0, 1]
	m.translate_vertices(indices, Vector3(1, 2, 3))
	assert_vector3(m.vertices[0]).is_equal(Vector3(1, 2, 3))
	assert_vector3(m.vertices[1]).is_equal(Vector3(2, 2, 3))


func test_translate_does_not_move_unselected_vertices() -> void:
	var m := _make_xy_quad()
	var indices: Array[int] = [0]
	m.translate_vertices(indices, Vector3(10, 0, 0))
	# vertices 1, 2, 3 should be unchanged.
	assert_vector3(m.vertices[1]).is_equal(Vector3(1, 0, 0))
	assert_vector3(m.vertices[2]).is_equal(Vector3(1, 1, 0))
	assert_vector3(m.vertices[3]).is_equal(Vector3(0, 1, 0))


func test_translate_zero_delta_is_noop() -> void:
	var m := _make_xy_quad()
	var before := m.vertices[0]
	var indices: Array[int] = [0, 1, 2, 3]
	m.translate_vertices(indices, Vector3.ZERO)
	assert_vector3(m.vertices[0]).is_equal(before)


func test_translate_all_vertices() -> void:
	var m := _make_xy_quad()
	var indices: Array[int] = [0, 1, 2, 3]
	m.translate_vertices(indices, Vector3(5, 0, 0))
	for v in m.vertices:
		assert_float(v.x).is_equal_approx(
			m.vertices[0].x, 0.001)  # all shifted by same delta, so same X


func test_translate_empty_indices_is_safe() -> void:
	var m := _make_xy_quad()
	var before := m.vertices.duplicate()
	var indices: Array[int] = []
	m.translate_vertices(indices, Vector3(1, 1, 1))
	for i in m.vertices.size():
		assert_vector3(m.vertices[i]).is_equal(before[i])


# ---------------------------------------------------------------------------
# compute_centroid
# ---------------------------------------------------------------------------

func test_centroid_single_vertex() -> void:
	var m := _make_xy_quad()
	var indices: Array[int] = [2]  # (1,1,0)
	assert_vector3(m.compute_centroid(indices)).is_equal(Vector3(1, 1, 0))


func test_centroid_all_quad_vertices() -> void:
	var m := _make_xy_quad()
	# Quad has verts (0,0,0),(1,0,0),(1,1,0),(0,1,0) — centroid = (0.5,0.5,0)
	var indices: Array[int] = [0, 1, 2, 3]
	assert_vector3(m.compute_centroid(indices)).is_equal_approx(
		Vector3(0.5, 0.5, 0.0), 0.001)


func test_centroid_empty_returns_zero() -> void:
	var m := _make_xy_quad()
	var indices: Array[int] = []
	assert_vector3(m.compute_centroid(indices)).is_equal(Vector3.ZERO)


# ---------------------------------------------------------------------------
# rebuild_coincident_groups
# ---------------------------------------------------------------------------

func test_coincident_groups_single_vertex_is_own_group() -> void:
	var m := GoBuildMesh.new()
	m.vertices = [Vector3(0, 0, 0)]
	m.rebuild_coincident_groups()
	assert_int(m.coincident_groups[0]).is_equal(0)


func test_coincident_groups_two_distinct_vertices_have_different_groups() -> void:
	var m := GoBuildMesh.new()
	m.vertices = [Vector3(0, 0, 0), Vector3(1, 0, 0)]
	m.rebuild_coincident_groups()
	assert_bool(m.coincident_groups[0] != m.coincident_groups[1]).is_true()


func test_coincident_groups_two_coincident_vertices_share_group() -> void:
	var m := GoBuildMesh.new()
	m.vertices = [Vector3(0, 0, 0), Vector3(0, 0, 0)]
	m.rebuild_coincident_groups()
	assert_int(m.coincident_groups[0]).is_equal(m.coincident_groups[1])


func test_coincident_groups_canonical_id_is_lowest_member() -> void:
	# The canonical group ID must be the lowest vertex index in the group.
	var m := GoBuildMesh.new()
	m.vertices = [Vector3(1, 2, 3), Vector3(1, 2, 3), Vector3(1, 2, 3)]
	m.rebuild_coincident_groups()
	assert_int(m.coincident_groups[0]).is_equal(0)
	assert_int(m.coincident_groups[1]).is_equal(0)
	assert_int(m.coincident_groups[2]).is_equal(0)


func test_coincident_groups_mixed_mesh_correct_grouping() -> void:
	# Vertices 0 and 2 share a position; vertex 1 is unique.
	var m := GoBuildMesh.new()
	m.vertices = [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 0)]
	m.rebuild_coincident_groups()
	assert_int(m.coincident_groups[0]).is_equal(m.coincident_groups[2])
	assert_bool(m.coincident_groups[1] != m.coincident_groups[0]).is_true()


func test_coincident_groups_cube_has_eight_unique_groups() -> void:
	# CubeGenerator: 24 verts (4 per face × 6 faces) at only 8 unique corners.
	var mesh := CubeGenerator.generate(1.0, 1.0, 1.0, 0)
	var seen: Dictionary = {}
	for g: int in mesh.coincident_groups:
		seen[g] = true
	assert_int(seen.size()).is_equal(8)


func test_coincident_groups_built_by_rebuild_edges() -> void:
	# rebuild_edges() must call rebuild_coincident_groups() automatically.
	var m := GoBuildMesh.new()
	m.vertices = [Vector3(0, 0, 0), Vector3(0, 0, 0)]
	var f := GoBuildFace.new()
	f.vertex_indices = [0, 1]
	f.uvs = [Vector2.ZERO, Vector2.ZERO]
	m.faces.append(f)
	m.rebuild_edges()
	assert_int(m.coincident_groups.size()).is_equal(2)
	assert_int(m.coincident_groups[0]).is_equal(m.coincident_groups[1])


func test_coincident_groups_rebuilt_after_snapshot_restore() -> void:
	# restore_snapshot → rebuild_edges → rebuild_coincident_groups.
	var m := GoBuildMesh.new()
	m.vertices = [Vector3(0, 0, 0), Vector3(0, 0, 0), Vector3(1, 0, 0)]
	var f := GoBuildFace.new()
	f.vertex_indices = [0, 1, 2]
	f.uvs = [Vector2.ZERO, Vector2.ZERO, Vector2(1, 0)]
	m.faces.append(f)
	m.rebuild_edges()

	var snap := m.take_snapshot()
	m.coincident_groups.clear()
	m.restore_snapshot(snap)

	assert_int(m.coincident_groups.size()).is_equal(3)
	assert_int(m.coincident_groups[0]).is_equal(m.coincident_groups[1])


# ---------------------------------------------------------------------------
# get_coincident_vertices
# ---------------------------------------------------------------------------

func test_get_coincident_vertices_unique_vertex_returns_self() -> void:
	var m := GoBuildMesh.new()
	m.vertices = [Vector3(0, 0, 0), Vector3(1, 0, 0)]
	m.rebuild_coincident_groups()
	var result := m.get_coincident_vertices(0)
	assert_int(result.size()).is_equal(1)
	assert_bool(result.has(0)).is_true()


func test_get_coincident_vertices_returns_all_group_members() -> void:
	var m := GoBuildMesh.new()
	m.vertices = [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 0)]
	m.rebuild_coincident_groups()
	var result := m.get_coincident_vertices(0)
	assert_int(result.size()).is_equal(2)
	assert_bool(result.has(0)).is_true()
	assert_bool(result.has(2)).is_true()


func test_get_coincident_vertices_non_canonical_member_returns_full_group() -> void:
	# Querying via index 2 (non-canonical) should return the same group as index 0.
	var m := GoBuildMesh.new()
	m.vertices = [Vector3(5, 5, 5), Vector3(5, 5, 5), Vector3(5, 5, 5)]
	m.rebuild_coincident_groups()
	var result := m.get_coincident_vertices(2)
	assert_int(result.size()).is_equal(3)


func test_get_coincident_vertices_fallback_when_groups_not_built() -> void:
	# If coincident_groups hasn't been built, returns single-element array.
	var m := GoBuildMesh.new()
	m.vertices = [Vector3(0, 0, 0)]
	# Do NOT call rebuild_coincident_groups() — groups remain empty.
	var result := m.get_coincident_vertices(0)
	assert_int(result.size()).is_equal(1)
	assert_bool(result.has(0)).is_true()


