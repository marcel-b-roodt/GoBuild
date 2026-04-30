## HardEdgeOperation tests — GdUnit4
extends GdUnitTestSuite

const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _OP_SCRIPT   := preload("res://addons/go_build/mesh/operations/hard_edge_operation.gd")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Returns a two-face mesh sharing vertex indices 0 and 1 (shared edge).
##
## Face A (index 0): quad in the XY plane, normal -Z.
##   Vertex order (CCW from -Z): [3, 2, 1, 0]
##     v0=(0,0,0)  v1=(1,0,0)  v2=(1,1,0)  v3=(0,1,0)
##
## Face B (index 1): quad in the XZ plane, normal -Y (verified below).
##   Vertex order (CCW from -Y): [0, 1, 5, 4]
##     v0=(0,0,0)  v1=(1,0,0)  v4=(0,0,1)  v5=(1,0,1)
##
## The mesh is pre-rebuilt so edges and coincident_groups are populated.
func _make_two_face_mesh() -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [
		Vector3(0.0, 0.0, 0.0),  # 0 — shared corner
		Vector3(1.0, 0.0, 0.0),  # 1 — shared corner
		Vector3(1.0, 1.0, 0.0),  # 2 — face A only
		Vector3(0.0, 1.0, 0.0),  # 3 — face A only
		Vector3(0.0, 0.0, 1.0),  # 4 — face B only
		Vector3(1.0, 0.0, 1.0),  # 5 — face B only
	]
	# Face A: CCW from -Z → normal -Z.
	var face_a := GoBuildFace.new()
	face_a.vertex_indices = [3, 2, 1, 0]
	face_a.uvs = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	face_a.smooth_group = 1
	mesh.faces.append(face_a)
	# Face B: CCW from -Y → normal -Y.
	var face_b := GoBuildFace.new()
	face_b.vertex_indices = [0, 1, 5, 4]
	face_b.uvs = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	face_b.smooth_group = 1
	mesh.faces.append(face_b)
	mesh.rebuild_edges()
	return mesh


## Returns the shared edge index between vertex 0 and vertex 1 in [param mesh].
func _shared_edge_idx(mesh: GoBuildMesh) -> int:
	return mesh.find_edge(0, 1)


# ---------------------------------------------------------------------------
# State mutations
# ---------------------------------------------------------------------------

func test_apply_marks_edge_as_hard() -> void:
	var mesh := _make_two_face_mesh()
	var ei: int = _shared_edge_idx(mesh)
	var indices: Array[int] = [ei]
	HardEdgeOperation.apply(mesh, indices, true)
	assert_bool(mesh.edges[ei].is_hard).is_true()


func test_apply_adds_pair_to_hard_edge_pairs() -> void:
	var mesh := _make_two_face_mesh()
	var ei: int = _shared_edge_idx(mesh)
	var indices: Array[int] = [ei]
	HardEdgeOperation.apply(mesh, indices, true)
	var expected := Vector2i(0, 1)
	assert_bool(mesh.hard_edge_pairs.has(expected)).is_true()


func test_apply_no_duplicate_in_hard_edge_pairs() -> void:
	var mesh := _make_two_face_mesh()
	var ei: int = _shared_edge_idx(mesh)
	var indices: Array[int] = [ei]
	HardEdgeOperation.apply(mesh, indices, true)
	HardEdgeOperation.apply(mesh, indices, true)
	var count: int = 0
	for p: Vector2i in mesh.hard_edge_pairs:
		if p == Vector2i(0, 1):
			count += 1
	assert_int(count).is_equal(1)


func test_apply_soft_clears_is_hard() -> void:
	var mesh := _make_two_face_mesh()
	var ei: int = _shared_edge_idx(mesh)
	var indices: Array[int] = [ei]
	HardEdgeOperation.apply(mesh, indices, true)
	HardEdgeOperation.apply(mesh, indices, false)
	assert_bool(mesh.edges[ei].is_hard).is_false()


func test_apply_soft_removes_from_hard_edge_pairs() -> void:
	var mesh := _make_two_face_mesh()
	var ei: int = _shared_edge_idx(mesh)
	var indices: Array[int] = [ei]
	HardEdgeOperation.apply(mesh, indices, true)
	HardEdgeOperation.apply(mesh, indices, false)
	assert_bool(mesh.hard_edge_pairs.has(Vector2i(0, 1))).is_false()


func test_apply_noop_for_empty_indices() -> void:
	var mesh := _make_two_face_mesh()
	var indices: Array[int] = []
	HardEdgeOperation.apply(mesh, indices, true)
	assert_int(mesh.hard_edge_pairs.size()).is_equal(0)


func test_apply_noop_for_null_mesh() -> void:
	# Must not crash.
	var indices: Array[int] = [0]
	HardEdgeOperation.apply(null, indices, true)


func test_apply_skips_out_of_range_index() -> void:
	var mesh := _make_two_face_mesh()
	var indices: Array[int] = [999]
	HardEdgeOperation.apply(mesh, indices, true)
	assert_int(mesh.hard_edge_pairs.size()).is_equal(0)


func test_hard_flag_survives_rebuild_edges() -> void:
	var mesh := _make_two_face_mesh()
	var ei: int = _shared_edge_idx(mesh)
	var indices: Array[int] = [ei]
	HardEdgeOperation.apply(mesh, indices, true)
	# Simulate what happens after an operation (which calls rebuild_edges).
	mesh.rebuild_edges()
	var ei2: int = _shared_edge_idx(mesh)
	assert_bool(mesh.edges[ei2].is_hard).is_true()


# ---------------------------------------------------------------------------
# Bake pipeline: normal seam
# ---------------------------------------------------------------------------

## Shared edge is hard: face A's vertices should have -Z normals and
## face B's vertices should have -Y normals at the shared edge, even though
## both faces are in smooth_group = 1.
func test_hard_edge_produces_normal_seam() -> void:
	var mesh := _make_two_face_mesh()
	var ei: int = _shared_edge_idx(mesh)
	var indices: Array[int] = [ei]
	HardEdgeOperation.apply(mesh, indices, true)

	var array_mesh: ArrayMesh = mesh.bake()
	assert_object(array_mesh).is_not_null()
	assert_bool(array_mesh.get_surface_count() > 0).is_true()

	var arrays: Array = array_mesh.surface_get_arrays(0)
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]

	# _build_surface triangulates each face in fan order [0, tri+2, tri+1].
	# Face A [3,2,1,0] → tri0:[3,1,2] tri1:[3,0,1] → 6 verts = indices 0-5.
	# Face B [0,1,5,4] → tri0:[0,5,1] tri1:[0,4,5] → 6 verts = indices 6-11.
	#
	# With hard edge, face A's region and face B's region are distinct.
	# Face A normal = -Z.  Face B normal = -Y.
	# v0 in face A (baked index 4) must have normal ~(0,0,-1).
	# v0 in face B (baked index 6) must have normal ~(0,-1,0).
	var norm_v0_in_a: Vector3 = norms[4]  # vertex 0, from face A's triangulation
	var norm_v0_in_b: Vector3 = norms[6]  # vertex 0, from face B's triangulation

	assert_float(norm_v0_in_a.dot(Vector3.FORWARD)).is_greater_equal(0.99)
	assert_float(norm_v0_in_b.dot(Vector3.DOWN)).is_greater_equal(0.99)


## Soft shared edge (same smooth_group): v0 and v1 should receive an averaged
## normal from both faces, so neither face gets a pure -Z or -Y normal there.
func test_soft_edge_smooth_normals_blend() -> void:
	var mesh := _make_two_face_mesh()
	# Default: no hard edges — the shared edge is soft.

	var array_mesh: ArrayMesh = mesh.bake()
	var arrays: Array = array_mesh.surface_get_arrays(0)
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]

	# v0 in face A (baked index 4): must NOT be pure -Z (it's averaged with -Y).
	var norm_v0_in_a: Vector3 = norms[4]
	assert_float(norm_v0_in_a.dot(Vector3.FORWARD)).is_less(0.99)
