## Unit tests for [GoBuildGizmoPlugin] pure-math helpers.
##
## Tested here (no scene-tree dependency):
## - [method GoBuildGizmoPlugin._get_local_axis]
## - [method GoBuildGizmoPlugin._get_handle_name]
## - [method GoBuildGizmoPlugin._get_affected_vertex_indices]
## - [method GoBuildGizmoPlugin.get_selection_local_centroid]
## - [constant GoBuildGizmoPlugin.TransformMode] existence
##
## Scene-dependent (deferred to a later scene-runner test):
## - [method GoBuildGizmoPlugin._project_to_axis] — requires a live [Camera3D]
## - Full drag round-trip (_get_handle_value → _set_handle → _commit_handle)
##   — requires an EditorUndoRedoManager and a wired EditorPlugin.
@tool
extends GdUnitTestSuite

# Self-preloads — dependency order, per the self-preload rule.
const _FACE_SCRIPT          := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT          := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT          := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _SEL_MGR_SCRIPT       := preload("res://addons/go_build/core/selection_manager.gd")
const _MESH_INSTANCE_SCRIPT := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _GIZMO_PLUGIN_SCRIPT  := preload("res://addons/go_build/core/go_build_gizmo_plugin.gd")


# ---------------------------------------------------------------------------
# Suite-level skip: EditorNode3DGizmoPlugin cannot be instantiated headlessly.
# GdUnit4 reads the 'do_skip' parameter of before() at scan time to decide
# whether to skip the entire suite.
# ---------------------------------------------------------------------------
func before(
		do_skip := not Engine.is_editor_hint(),
		skip_reason := "GoBuildGizmoPlugin requires editor context — skipped in headless mode."
) -> void:
	# GdUnit4 reads 'do_skip' and 'skip_reason' default values at scan time
	# to decide whether to skip the entire suite.  The body below is only
	# reached in editor mode (do_skip=false) and is a harmless no-op.
	if do_skip:
		print("[GoBuild test] Skipping gizmo suite: %s" % skip_reason)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Create a GoBuildGizmoPlugin without calling setup() — sufficient for
## pure-math helpers that do not access _editor_plugin or materials.
func _make_plugin() -> GoBuildGizmoPlugin:
	return GoBuildGizmoPlugin.new()


## Build a minimal quad GoBuildMesh with rebuild_edges() called.
func _make_quad_mesh() -> GoBuildMesh:
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
	m.rebuild_edges()
	return m


## Create a bare GoBuildMeshInstance with a quad mesh assigned and some
## selection state, without needing to add it to the scene tree.
func _make_node_with_quad() -> GoBuildMeshInstance:
	var node: GoBuildMeshInstance = auto_free(GoBuildMeshInstance.new())
	var gbm := _make_quad_mesh()
	node.go_build_mesh = gbm
	return node


# ---------------------------------------------------------------------------
# _get_local_axis
# ---------------------------------------------------------------------------

func test_axis_0_is_right() -> void:
	var plugin := _make_plugin()
	assert_vector(plugin._get_local_axis(0)).is_equal(Vector3.RIGHT)


func test_axis_1_is_up() -> void:
	var plugin := _make_plugin()
	assert_vector(plugin._get_local_axis(1)).is_equal(Vector3.UP)


func test_axis_2_is_back() -> void:
	# Vector3.BACK = (0, 0, 1) — +Z in Godot 4.  See coordinate-system docs.
	var plugin := _make_plugin()
	assert_vector(plugin._get_local_axis(2)).is_equal(Vector3.BACK)


func test_axis_unknown_returns_zero() -> void:
	var plugin := _make_plugin()
	assert_vector(plugin._get_local_axis(99)).is_equal(Vector3.ZERO)


# ---------------------------------------------------------------------------
# _get_handle_name
# ---------------------------------------------------------------------------

func test_handle_name_move_x() -> void:
	var plugin := _make_plugin()
	assert_str(plugin._get_handle_name(
		null,
		GoBuildGizmoPlugin.AXIS_HANDLE_OFFSET + 0,
		false
	)).is_equal("Move X")


func test_handle_name_move_y() -> void:
	var plugin := _make_plugin()
	assert_str(plugin._get_handle_name(
		null,
		GoBuildGizmoPlugin.AXIS_HANDLE_OFFSET + 1,
		false
	)).is_equal("Move Y")


func test_handle_name_move_z() -> void:
	var plugin := _make_plugin()
	assert_str(plugin._get_handle_name(
		null,
		GoBuildGizmoPlugin.AXIS_HANDLE_OFFSET + 2,
		false
	)).is_equal("Move Z")


func test_handle_name_non_axis_handle_returns_empty() -> void:
	# handle_id values below AXIS_HANDLE_OFFSET are vertex/face handles —
	# the plugin should return "" for those.
	var plugin := _make_plugin()
	assert_str(plugin._get_handle_name(null, 0, false)).is_equal("")
	assert_str(plugin._get_handle_name(null, 42, false)).is_equal("")


func test_handle_name_rotate_x() -> void:
	var plugin := _make_plugin()
	assert_str(plugin._get_handle_name(
		null, GoBuildGizmoPlugin.ROT_HANDLE_OFFSET + 0, false
	)).is_equal("Rotate X")


func test_handle_name_rotate_y() -> void:
	var plugin := _make_plugin()
	assert_str(plugin._get_handle_name(
		null, GoBuildGizmoPlugin.ROT_HANDLE_OFFSET + 1, false
	)).is_equal("Rotate Y")


func test_handle_name_rotate_z() -> void:
	var plugin := _make_plugin()
	assert_str(plugin._get_handle_name(
		null, GoBuildGizmoPlugin.ROT_HANDLE_OFFSET + 2, false
	)).is_equal("Rotate Z")


# ---------------------------------------------------------------------------
# _ray_plane_intersect
# ---------------------------------------------------------------------------

func test_ray_plane_hit_perpendicular() -> void:
	# Ray from (0,5,0) pointing straight down, plane at Y=0 normal (0,1,0).
	# Expected hit: (0,0,0), t = 5.
	var hit: Vector3 = GoBuildGizmoPlugin._ray_plane_intersect(
		Vector3(0.0, 5.0, 0.0), Vector3(0.0, -1.0, 0.0),
		Vector3.ZERO, Vector3.UP
	)
	assert_vector(hit).is_equal_approx(Vector3.ZERO, Vector3(0.001, 0.001, 0.001))


func test_ray_plane_hit_offset_origin() -> void:
	# Ray from (3,5,0) pointing straight down, plane at Y=0.
	# Expected hit: (3,0,0).
	var hit: Vector3 = GoBuildGizmoPlugin._ray_plane_intersect(
		Vector3(3.0, 5.0, 0.0), Vector3(0.0, -1.0, 0.0),
		Vector3.ZERO, Vector3.UP
	)
	assert_vector(hit).is_equal_approx(Vector3(3.0, 0.0, 0.0), Vector3(0.001, 0.001, 0.001))


func test_ray_plane_parallel_returns_inf() -> void:
	# Ray travelling along +X is parallel to XZ plane (normal = UP).
	var hit: Vector3 = GoBuildGizmoPlugin._ray_plane_intersect(
		Vector3(0.0, 1.0, 0.0), Vector3(1.0, 0.0, 0.0),
		Vector3.ZERO, Vector3.UP
	)
	assert_bool(hit == Vector3.INF).is_true()


func test_ray_plane_behind_camera_returns_inf() -> void:
	# Ray from (0,-5,0) pointing further down (-Y); plane at Y=0 is above.
	# The intersection would be at t < 0 (behind origin).
	var hit: Vector3 = GoBuildGizmoPlugin._ray_plane_intersect(
		Vector3(0.0, -5.0, 0.0), Vector3(0.0, -1.0, 0.0),
		Vector3.ZERO, Vector3.UP
	)
	assert_bool(hit == Vector3.INF).is_true()


func test_ray_plane_diagonal_hit() -> void:
	# Ray from (0,4,0) at 45° toward the XZ plane.
	# dir = (1,-1,0).normalized() = (0.707, -0.707, 0)
	# Plane: Y=0, normal=UP.  t = 4 / 0.707 ≈ 5.657; hit_x = 4.
	var dir := Vector3(1.0, -1.0, 0.0).normalized()
	var hit: Vector3 = GoBuildGizmoPlugin._ray_plane_intersect(
		Vector3(0.0, 4.0, 0.0), dir, Vector3.ZERO, Vector3.UP
	)
	assert_float(hit.x).is_equal_approx(4.0, 0.01)
	assert_float(hit.y).is_equal_approx(0.0, 0.001)



# ---------------------------------------------------------------------------
# _get_affected_vertex_indices
# ---------------------------------------------------------------------------

func test_affected_indices_vertex_mode_returns_selected_vertices() -> void:
	var plugin  := _make_plugin()
	var node    := _make_node_with_quad()
	node.selection.set_mode(SelectionManager.Mode.VERTEX)
	node.selection.select_vertex(0)
	node.selection.select_vertex(2)

	var result: Array[int] = plugin._get_affected_vertex_indices(node)
	assert_int(result.size()).is_equal(2)
	assert_bool(result.has(0)).is_true()
	assert_bool(result.has(2)).is_true()


func test_affected_indices_vertex_mode_empty_when_nothing_selected() -> void:
	var plugin := _make_plugin()
	var node   := _make_node_with_quad()
	node.selection.set_mode(SelectionManager.Mode.VERTEX)
	# No selection.

	var result: Array[int] = plugin._get_affected_vertex_indices(node)
	assert_array(result).is_empty()


func test_affected_indices_edge_mode_returns_edge_endpoints() -> void:
	var plugin := _make_plugin()
	var node   := _make_node_with_quad()
	node.selection.set_mode(SelectionManager.Mode.EDGE)
	# Select edge 0 — the quad has 4 edges; edge[0] connects vertices 0 and 1.
	node.selection.select_edge(0)

	var result: Array[int] = plugin._get_affected_vertex_indices(node)
	# Must contain the two endpoint vertex indices, no duplicates.
	assert_int(result.size()).is_equal(2)
	var edge: GoBuildEdge = node.go_build_mesh.edges[0]
	assert_bool(result.has(edge.vertex_a)).is_true()
	assert_bool(result.has(edge.vertex_b)).is_true()


func test_affected_indices_edge_mode_deduplicates_shared_vertices() -> void:
	# Select two edges that share a vertex — the shared vertex appears once.
	var plugin := _make_plugin()
	var node   := _make_node_with_quad()
	node.selection.set_mode(SelectionManager.Mode.EDGE)
	node.selection.select_edge(0)
	node.selection.select_edge(1)

	var result: Array[int] = plugin._get_affected_vertex_indices(node)
	# Edges 0 and 1 share one vertex → 3 unique vertices total.
	assert_int(result.size()).is_equal(3)


func test_affected_indices_face_mode_returns_all_face_vertices() -> void:
	var plugin := _make_plugin()
	var node   := _make_node_with_quad()
	node.selection.set_mode(SelectionManager.Mode.FACE)
	node.selection.select_face(0)

	var result: Array[int] = plugin._get_affected_vertex_indices(node)
	# The quad face has 4 vertices: 0, 1, 2, 3.
	assert_int(result.size()).is_equal(4)
	for idx in [0, 1, 2, 3]:
		assert_bool(result.has(idx)).is_true()


func test_affected_indices_null_mesh_returns_empty() -> void:
	var plugin := _make_plugin()
	var node: GoBuildMeshInstance = auto_free(GoBuildMeshInstance.new())
	# go_build_mesh is null by default.

	var result: Array[int] = plugin._get_affected_vertex_indices(node)
	assert_array(result).is_empty()


# ---------------------------------------------------------------------------
# _get_handle_name — new handle types (scale, plane, view-plane)
# ---------------------------------------------------------------------------

func test_handle_name_scale_x() -> void:
	var plugin := _make_plugin()
	assert_str(plugin._get_handle_name(
		null, GoBuildGizmoPlugin.SCALE_HANDLE_OFFSET + 0, false
	)).is_equal("Scale X")


func test_handle_name_scale_y() -> void:
	var plugin := _make_plugin()
	assert_str(plugin._get_handle_name(
		null, GoBuildGizmoPlugin.SCALE_HANDLE_OFFSET + 1, false
	)).is_equal("Scale Y")


func test_handle_name_scale_z() -> void:
	var plugin := _make_plugin()
	assert_str(plugin._get_handle_name(
		null, GoBuildGizmoPlugin.SCALE_HANDLE_OFFSET + 2, false
	)).is_equal("Scale Z")


func test_handle_name_plane_xy() -> void:
	var plugin := _make_plugin()
	assert_str(plugin._get_handle_name(
		null, GoBuildGizmoPlugin.PLANE_HANDLE_OFFSET + 0, false
	)).is_equal("Move XY")


func test_handle_name_plane_yz() -> void:
	var plugin := _make_plugin()
	assert_str(plugin._get_handle_name(
		null, GoBuildGizmoPlugin.PLANE_HANDLE_OFFSET + 1, false
	)).is_equal("Move YZ")


func test_handle_name_plane_xz() -> void:
	var plugin := _make_plugin()
	assert_str(plugin._get_handle_name(
		null, GoBuildGizmoPlugin.PLANE_HANDLE_OFFSET + 2, false
	)).is_equal("Move XZ")


func test_handle_name_view_plane() -> void:
	var plugin := _make_plugin()
	assert_str(plugin._get_handle_name(
		null, GoBuildGizmoPlugin.VIEW_PLANE_HANDLE_ID, false
	)).is_equal("Move (View Plane)")


# ---------------------------------------------------------------------------
# TransformMode enum
# ---------------------------------------------------------------------------

func test_transform_mode_default_is_translate() -> void:
	var plugin := _make_plugin()
	assert_int(plugin.transform_mode).is_equal(GoBuildGizmoPlugin.TransformMode.TRANSLATE)


func test_transform_mode_enum_values() -> void:
	assert_int(GoBuildGizmoPlugin.TransformMode.TRANSLATE).is_equal(0)
	assert_int(GoBuildGizmoPlugin.TransformMode.ROTATE).is_equal(1)
	assert_int(GoBuildGizmoPlugin.TransformMode.SCALE).is_equal(2)


# ---------------------------------------------------------------------------
# get_selection_local_centroid
# ---------------------------------------------------------------------------

func test_centroid_vertex_mode_single_vertex() -> void:
	var plugin := _make_plugin()
	var node   := _make_node_with_quad()
	node.selection.set_mode(SelectionManager.Mode.VERTEX)
	node.selection.select_vertex(0)
	# Vertex 0 of the quad mesh is at (0,0,0).
	var lc: Vector3 = plugin.get_selection_local_centroid(node)
	assert_vector(lc).is_equal_approx(Vector3(0.0, 0.0, 0.0), Vector3(0.001, 0.001, 0.001))


func test_centroid_vertex_mode_two_vertices() -> void:
	var plugin := _make_plugin()
	var node   := _make_node_with_quad()
	node.selection.set_mode(SelectionManager.Mode.VERTEX)
	node.selection.select_vertex(0)  # (0,0,0)
	node.selection.select_vertex(1)  # (1,0,0)
	var lc: Vector3 = plugin.get_selection_local_centroid(node)
	assert_vector(lc).is_equal_approx(Vector3(0.5, 0.0, 0.0), Vector3(0.001, 0.001, 0.001))


func test_centroid_empty_returns_zero() -> void:
	var plugin := _make_plugin()
	var node   := _make_node_with_quad()
	node.selection.set_mode(SelectionManager.Mode.VERTEX)
	# No selection.
	var lc: Vector3 = plugin.get_selection_local_centroid(node)
	assert_vector(lc).is_equal(Vector3.ZERO)


# ---------------------------------------------------------------------------
# _get_snap_step — static helper
# ---------------------------------------------------------------------------

func test_snap_step_non_editor_returns_one() -> void:
	# Outside the editor hint context, _get_snap_step must return 1.0.
	if Engine.is_editor_hint():
		pass  # Can't test this path from inside the editor.
	else:
		assert_float(GoBuildGizmoPlugin._get_snap_step()).is_equal(1.0)


