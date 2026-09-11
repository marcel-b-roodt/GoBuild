## Unit tests for [SnapToGridOperation] (ProBuilder "Snap Selection to
## Grid").
##
## Contract: each selected vertex snaps INDEPENDENTLY to its nearest grid
## cell in world space (node transform honoured, result converted back to
## mesh-local), repairing malformed off-grid geometry deforming-ly.  No
## topology change, no edge rebuild required; invalid indices skipped;
## step <= 0 no-ops.  Undo/redo is handled by
## [method GoBuildMeshInstance.apply_operation] (covered by integration).
@tool
extends GdUnitTestSuite

const _OP_SCRIPT := preload("res://addons/go_build/mesh/operations/snap_to_grid_operation.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")


func _identity() -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3.ZERO)


func _quad_mesh(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	mesh.vertices.assign([a, b, c, d])
	var face := GoBuildFace.new()
	face.vertex_indices.assign([0, 1, 2, 3])
	face.uvs.assign([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.LEFT])
	face.uv2s.assign([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2(0, 1)])
	mesh.faces.append(face)
	mesh.rebuild_edges()
	return mesh


# ---------------------------------------------------------------------------
# Axis-aligned node (transform = identity)
# ---------------------------------------------------------------------------

func test_off_grid_edge_both_endpoints_land_on_grid() -> void:
	# The reported case: 2.863 m edge → both ends on the 0.1 m grid.
	var mesh := _quad_mesh(
			Vector3(-2.362876, 1.377355, -0.5),
			Vector3(0.5, 1.377355, -0.5),
			Vector3(-2.362876, -0.5, -0.5),
			Vector3(0.5, -0.5, -0.5))
	var moved := _OP_SCRIPT.apply(mesh, [0, 1, 2, 3], _identity(), 0.1)
	# vert3 (0.5, -0.5, -0.5) is already on-grid → untouched.
	assert_int(moved).is_equal(3)
	# Index 3 (0.5, -0.5, -0.5) is already on-grid → untouched.
	assert_vector(mesh.vertices[3]).is_equal_approx(Vector3(0.5, -0.5, -0.5),
			Vector3.ONE * 0.0001)
	for v: Vector3 in mesh.vertices:
		assert_float(v.x).is_equal_approx(snappedf(v.x, 0.1), 0.0001)
		assert_float(v.y).is_equal_approx(snappedf(v.y, 0.1), 0.0001)
		assert_float(v.z).is_equal_approx(snappedf(v.z, 0.1), 0.0001)


func test_edge_length_is_normalised() -> void:
	# 2.863 m edge → both endpoints individually snapped → length must be
	# a grid multiple (2.9 m expected from -2.362876 → -2.4 / 0.5 → 0.5).
	var mesh := _quad_mesh(
			Vector3(-2.362876, 0.0, 0.0),
			Vector3(0.5, 0.0, 0.0),
			Vector3(-2.362876, -1.0, 0.0),
			Vector3(0.5, -1.0, 0.0))
	_OP_SCRIPT.apply(mesh, [0, 1], _identity(), 0.1)
	var length: float = (mesh.vertices[1] - mesh.vertices[0]).length()
	assert_float(length).is_equal_approx(2.9, 0.001)


func test_topology_is_untouched() -> void:
	var mesh := _quad_mesh(
			Vector3(0.03, 0.03, 0.0),
			Vector3(1.07, 0.02, 0.0),
			Vector3(1.04, 1.05, 0.0),
			Vector3(0.02, 1.01, 0.0))
	var face_count: int = mesh.faces.size()
	var edge_count: int = mesh.edges.size()
	_OP_SCRIPT.apply(mesh, [0, 1, 2, 3], _identity(), 0.1)
	assert_int(mesh.faces.size()).is_equal(face_count)
	assert_int(mesh.edges.size()).is_equal(edge_count)


func test_already_on_grid_vertices_report_zero_moved() -> void:
	var mesh := _quad_mesh(
			Vector3(1.0, 0.0, 0.0),
			Vector3(2.0, 0.0, 0.0),
			Vector3(2.0, 1.0, 0.0),
			Vector3(1.0, 1.0, 0.0))
	var moved := _OP_SCRIPT.apply(mesh, [0, 1, 2, 3], _identity(), 0.5)
	assert_int(moved).is_equal(0)


func test_partial_selection_moves_only_selected() -> void:
	var mesh := _quad_mesh(
			Vector3(0.03, 0.0, 0.0),
			Vector3(0.97, 0.0, 0.0),
			Vector3(0.0, 1.0, 0.0),
			Vector3(1.0, 1.0, 0.0))
	_OP_SCRIPT.apply(mesh, [0], _identity(), 0.5)
	assert_vector(mesh.vertices[0]).is_equal_approx(Vector3(0.0, 0, 0),
			Vector3.ONE * 0.001)
	assert_vector(mesh.vertices[1]).is_equal_approx(Vector3(0.97, 0, 0),
			Vector3.ONE * 0.001)


func test_invalid_indices_skipped() -> void:
	var mesh := _quad_mesh(
			Vector3(0.03, 0.0, 0.0),
			Vector3(1.0, 0.0, 0.0),
			Vector3(0.0, 1.0, 0.0),
			Vector3(1.0, 1.0, 0.0))
	var moved := _OP_SCRIPT.apply(mesh, [-1, 0, 99], _identity(), 0.5)
	assert_int(moved).is_equal(1)


func test_zero_step_no_op() -> void:
	var mesh := _quad_mesh(
			Vector3(0.03, 0.0, 0.0),
			Vector3(1.0, 0.0, 0.0),
			Vector3(0.0, 1.0, 0.0),
			Vector3(1.0, 1.0, 0.0))
	var before := mesh.vertices.duplicate()
	var moved := _OP_SCRIPT.apply(mesh, [0, 1, 2, 3], _identity(), 0.0)
	assert_int(moved).is_equal(0)
	assert_vector(mesh.vertices[0]).is_equal_approx(Vector3(0.03, 0, 0),
			Vector3.ONE * 0.0001)


# ---------------------------------------------------------------------------
# Transformed node (world = local * node_xform)
# ---------------------------------------------------------------------------

func test_node_offset_world_snapping_in_local_space() -> void:
	# Node origin (10.03, 0, 0): local vert 0.03 is world 10.06?? No —
	# 10.03 + 0.03 = 10.06 → snaps to 10.1 → local back to 0.07.
	var mesh := _quad_mesh(
			Vector3(0.03, 0.0, 0.0),
			Vector3(1.0, 0.0, 0.0),
			Vector3(0.0, 1.0, 0.0),
			Vector3(1.0, 1.0, 0.0))
	var xf := Transform3D(Basis.IDENTITY, Vector3(10.03, 0, 0))
	_OP_SCRIPT.apply(mesh, [0], xf, 0.1)
	assert_vector(mesh.vertices[0]).is_equal_approx(Vector3(0.07, 0, 0),
			Vector3.ONE * 0.001)


func test_node_rotated_90_y_snaps_in_world() -> void:
	# Node rotated 90° around Y: world X is local -Z.  World vert
	# (0.03, 0, 0) → snaps to (0.0, 0, 0) → local stays (0.03, 0, 0)
	# because the world position is already grid-adjacent... use a
	# clearer case: local (0, 0, -0.03) = world (0.03, 0, 0) → snaps to
	# (0, 0, 0) world → local (0, 0, 0).
	var mesh := _quad_mesh(
			Vector3(0.0, 0.0, -0.03),
			Vector3(1.0, 0.0, 0.0),
			Vector3(0.0, 1.0, 0.0),
			Vector3(1.0, 1.0, 0.0))
	var basis := Basis(Vector3.UP, PI * 0.5)
	var xf := Transform3D(basis, Vector3.ZERO)
	_OP_SCRIPT.apply(mesh, [0], xf, 0.5)
	assert_vector(mesh.vertices[0]).is_equal_approx(Vector3.ZERO,
			Vector3.ONE * 0.001)


# ---------------------------------------------------------------------------
# Full-plugin path (undo wiring) is editor-only; maths covered here.
# ---------------------------------------------------------------------------