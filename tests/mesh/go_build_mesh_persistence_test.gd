## Persistence round-trip tests for [GoBuildMesh] and [GoBuildFace].
##
## These tests verify that saving a [GoBuildMesh] resource to disk and
## reloading it (via [ResourceSaver] / [ResourceLoader]) produces an
## identical mesh — no vertex position loss, no face topology loss, no UV
## loss, no material loss, and no crash from missing @tool / @export.
##
## After reload, [method GoBuildMesh.rebuild_edges] is also exercised so the
## full _ready() path is covered.
@tool
extends GdUnitTestSuite

const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")

## Temp path used for all round-trip saves.  Written to user:// so it never
## ends up inside the project's res:// tree during CI runs.
const _TMP_PATH := "user://go_build_persistence_test_tmp.tres"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Build a unit quad on the XY plane with distinct UV0 coordinates, a second
## UV1 channel, a non-default material index, and a non-default smooth group.
func _make_quad_full() -> GoBuildMesh:
	var m := GoBuildMesh.new()
	m.vertices = [
		Vector3(0.0, 0.0, 0.0),
		Vector3(1.0, 0.0, 0.0),
		Vector3(1.0, 1.0, 0.0),
		Vector3(0.0, 1.0, 0.0),
	]
	var f := GoBuildFace.new()
	f.vertex_indices = [0, 1, 2, 3]
	f.uvs  = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	f.uv2s = [Vector2(0, 0), Vector2(0.5, 0), Vector2(0.5, 0.5), Vector2(0, 0.5)]
	f.material_index = 0
	f.smooth_group   = 1
	m.faces.append(f)
	m.rebuild_edges()
	return m


## Build a two-quad mesh (two faces, 8 vertices) to test multi-face persistence.
func _make_two_quad_mesh() -> GoBuildMesh:
	var m := GoBuildMesh.new()
	# Quad A: z = 0
	m.vertices.append_array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0),
	])
	# Quad B: z = 1
	m.vertices.append_array([
		Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1),
	])
	var fa := GoBuildFace.new()
	fa.vertex_indices = [0, 1, 2, 3]
	fa.uvs = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var fb := GoBuildFace.new()
	fb.vertex_indices = [4, 5, 6, 7]
	fb.uvs = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	m.faces.append(fa)
	m.faces.append(fb)
	m.rebuild_edges()
	return m


## Save [param mesh] to [constant _TMP_PATH], clear the ResourceLoader cache,
## and return the freshly loaded copy.  Fails the test if either step errors.
func _round_trip(mesh: GoBuildMesh) -> GoBuildMesh:
	var save_err: int = ResourceSaver.save(mesh, _TMP_PATH)
	assert_int(save_err).is_equal(OK)

	# Force ResourceLoader to ignore its in-memory cache so we get a fully
	# deserialised object rather than the same instance.
	var loaded: Resource = ResourceLoader.load(_TMP_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_object(loaded).is_not_null()
	assert_bool(loaded is GoBuildMesh).is_true()
	return loaded as GoBuildMesh


func after_test() -> void:
	# Clean up the temp file after every test that may have written it.
	if ResourceLoader.exists(_TMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_TMP_PATH))


# ---------------------------------------------------------------------------
# Vertex persistence
# ---------------------------------------------------------------------------

func test_vertex_count_survives_round_trip() -> void:
	var original := _make_quad_full()
	var reloaded := _round_trip(original)
	assert_int(reloaded.vertices.size()).is_equal(original.vertices.size())


func test_vertex_positions_survive_round_trip() -> void:
	var original := _make_quad_full()
	var reloaded := _round_trip(original)
	for i in original.vertices.size():
		var approx := Vector3(1e-5, 1e-5, 1e-5)
		assert_vector(reloaded.vertices[i]).is_equal_approx(original.vertices[i], approx)


# ---------------------------------------------------------------------------
# Face topology persistence
# ---------------------------------------------------------------------------

func test_face_count_survives_round_trip() -> void:
	var original := _make_quad_full()
	var reloaded := _round_trip(original)
	assert_int(reloaded.faces.size()).is_equal(original.faces.size())


func test_face_vertex_indices_survive_round_trip() -> void:
	var original := _make_quad_full()
	var reloaded := _round_trip(original)
	var of: GoBuildFace = original.faces[0]
	var rf: GoBuildFace = reloaded.faces[0]
	assert_int(rf.vertex_indices.size()).is_equal(of.vertex_indices.size())
	for i in of.vertex_indices.size():
		assert_int(rf.vertex_indices[i]).is_equal(of.vertex_indices[i])


func test_face_material_index_survives_round_trip() -> void:
	var original := _make_quad_full()
	original.faces[0].material_index = 2
	var reloaded := _round_trip(original)
	assert_int(reloaded.faces[0].material_index).is_equal(2)


func test_face_smooth_group_survives_round_trip() -> void:
	var original := _make_quad_full()
	original.faces[0].smooth_group = 3
	var reloaded := _round_trip(original)
	assert_int(reloaded.faces[0].smooth_group).is_equal(3)


# ---------------------------------------------------------------------------
# UV persistence
# ---------------------------------------------------------------------------

func test_uv0_survives_round_trip() -> void:
	var original := _make_quad_full()
	var reloaded := _round_trip(original)
	var of: GoBuildFace = original.faces[0]
	var rf: GoBuildFace = reloaded.faces[0]
	assert_int(rf.uvs.size()).is_equal(of.uvs.size())
	for i in of.uvs.size():
		assert_vector(rf.uvs[i]).is_equal_approx(of.uvs[i], Vector2(1e-5, 1e-5))


func test_uv1_lightmap_survives_round_trip() -> void:
	var original := _make_quad_full()
	var reloaded := _round_trip(original)
	var of: GoBuildFace = original.faces[0]
	var rf: GoBuildFace = reloaded.faces[0]
	assert_int(rf.uv2s.size()).is_equal(of.uv2s.size())
	for i in of.uv2s.size():
		assert_vector(rf.uv2s[i]).is_equal_approx(of.uv2s[i], Vector2(1e-5, 1e-5))


# ---------------------------------------------------------------------------
# Multi-face persistence
# ---------------------------------------------------------------------------

func test_multi_face_vertex_count_survives_round_trip() -> void:
	var original := _make_two_quad_mesh()
	var reloaded := _round_trip(original)
	assert_int(reloaded.vertices.size()).is_equal(8)
	assert_int(reloaded.faces.size()).is_equal(2)


func test_multi_face_indices_survive_round_trip() -> void:
	var original := _make_two_quad_mesh()
	var reloaded := _round_trip(original)
	# Face B references vertices 4-7.
	assert_int(reloaded.faces[1].vertex_indices[0]).is_equal(4)
	assert_int(reloaded.faces[1].vertex_indices[3]).is_equal(7)


# ---------------------------------------------------------------------------
# Edge rebuild after reload
# ---------------------------------------------------------------------------

func test_edges_empty_before_rebuild() -> void:
	# A freshly deserialised mesh has no edges — they are not @export.
	var original := _make_quad_full()
	var reloaded := _round_trip(original)
	assert_int(reloaded.edges.size()).is_equal(0)


func test_rebuild_edges_restores_correct_count_after_reload() -> void:
	var original := _make_quad_full()
	var reloaded := _round_trip(original)
	reloaded.rebuild_edges()
	# A single quad has 4 edges.
	assert_int(reloaded.edges.size()).is_equal(4)


func test_rebuild_edges_boundaries_after_reload() -> void:
	var original := _make_quad_full()
	var reloaded := _round_trip(original)
	reloaded.rebuild_edges()
	for edge: GoBuildEdge in reloaded.edges:
		assert_bool(edge.is_boundary()).is_true()


func test_coincident_groups_rebuilt_after_reload() -> void:
	var original := _make_quad_full()
	var reloaded := _round_trip(original)
	# Before rebuild, coincident_groups is empty.
	assert_int(reloaded.coincident_groups.size()).is_equal(0)
	reloaded.rebuild_edges()
	# After rebuild it must be parallel to vertices.
	assert_int(reloaded.coincident_groups.size()).is_equal(reloaded.vertices.size())


# ---------------------------------------------------------------------------
# Bake integrity after reload + rebuild
# ---------------------------------------------------------------------------

func test_bake_produces_correct_surface_count_after_reload() -> void:
	var original := _make_quad_full()
	var reloaded := _round_trip(original)
	reloaded.rebuild_edges()
	assert_int(reloaded.bake().get_surface_count()).is_equal(1)


func test_bake_produces_correct_vertex_count_after_reload() -> void:
	var original := _make_quad_full()
	var reloaded := _round_trip(original)
	reloaded.rebuild_edges()
	var arrays: Array = reloaded.bake().surface_get_arrays(0)
	# One quad → 2 triangles → 6 verts.
	assert_int((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()).is_equal(6)


func test_bake_uv0_values_survive_full_pipeline() -> void:
	var original := _make_quad_full()
	var reloaded := _round_trip(original)
	reloaded.rebuild_edges()
	var arrays: Array = reloaded.bake().surface_get_arrays(0)
	var baked_uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	# 6 UV entries (one per triangle vertex) — none should be zero-zero unless
	# the corner genuinely maps to (0,0).  Spot-check: at least one UV ≠ (0,0).
	var has_nonzero := false
	for uv: Vector2 in baked_uvs:
		if uv.length_squared() > 1e-6:
			has_nonzero = true
			break
	assert_bool(has_nonzero).is_true()


# ---------------------------------------------------------------------------
# No crash / no placeholder on reload
# ---------------------------------------------------------------------------

func test_reloaded_mesh_is_gobuildmesh_not_bare_resource() -> void:
	var original := _make_quad_full()
	var reloaded := _round_trip(original)
	# If @tool or @export was missing the engine returns a plain Resource
	# placeholder.  This assertion catches that regression.
	assert_bool(reloaded is GoBuildMesh).is_true()


func test_reloaded_faces_are_gobuildface_not_bare_resource() -> void:
	var original := _make_quad_full()
	var reloaded := _round_trip(original)
	assert_int(reloaded.faces.size()).is_greater(0)
	for face: GoBuildFace in reloaded.faces:
		assert_bool(face is GoBuildFace).is_true()
