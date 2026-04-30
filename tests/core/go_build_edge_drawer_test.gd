## GdUnit4 tests for [GoBuildEdgeDrawer] button state.
##
## Verified here:
##   - All buttons disabled when target is null.
##   - All buttons disabled in Object mode (wrong mode).
##   - Extrude/Bevel/Loop Cut/Hard/Soft enabled in Edge mode with ≥1 edge selected.
##   - All buttons disabled in Edge mode with no edges selected.
##   - Bridge disabled with only 1 boundary edge; enabled with ≥2 boundary edges.
@tool
extends GdUnitTestSuite

# Self-preloads — dependency order.
const _FACE_SCRIPT          := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT          := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT          := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _SEL_MGR_SCRIPT       := preload("res://addons/go_build/core/selection_manager.gd")
const _MESH_INSTANCE_SCRIPT := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _DRAWER_SCRIPT        := preload("res://addons/go_build/core/go_build_drawer.gd")
const _EDGE_DRAWER_SCRIPT   := preload("res://addons/go_build/core/go_build_edge_drawer.gd")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_drawer() -> GoBuildEdgeDrawer:
	var d := GoBuildEdgeDrawer.new()
	add_child(d)
	auto_free(d)
	return d


## Build a single-quad mesh (4 verts, 1 face, 4 boundary edges after rebuild).
func _make_node() -> GoBuildMeshInstance:
	var node: GoBuildMeshInstance = auto_free(GoBuildMeshInstance.new())
	var m := GoBuildMesh.new()
	m.vertices = [
		Vector3(-1.0, 0.0, -1.0),
		Vector3( 1.0, 0.0, -1.0),
		Vector3( 1.0, 0.0,  1.0),
		Vector3(-1.0, 0.0,  1.0),
	]
	var f := GoBuildFace.new()
	f.vertex_indices = [0, 1, 2, 3]
	f.uvs = [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]
	m.faces.append(f)
	m.rebuild_edges()
	node.go_build_mesh = m
	return node


# ---------------------------------------------------------------------------
# Null target
# ---------------------------------------------------------------------------

func test_all_buttons_disabled_without_target() -> void:
	var d := _make_drawer()
	d.refresh_buttons()
	assert_bool(d._extrude_edge_btn.disabled).is_true()
	assert_bool(d._bevel_btn.disabled).is_true()
	assert_bool(d._bridge_btn.disabled).is_true()
	assert_bool(d._loop_cut_btn.disabled).is_true()
	assert_bool(d._hard_edge_btn.disabled).is_true()
	assert_bool(d._soft_edge_btn.disabled).is_true()


# ---------------------------------------------------------------------------
# Wrong mode (Object) — all disabled
# ---------------------------------------------------------------------------

func test_all_buttons_disabled_in_object_mode() -> void:
	var d := _make_drawer()
	var node := _make_node()
	d.set_target(node)
	node.selection.set_mode(SelectionManager.Mode.OBJECT)
	d.refresh_buttons()
	assert_bool(d._extrude_edge_btn.disabled).is_true()
	assert_bool(d._bevel_btn.disabled).is_true()
	assert_bool(d._bridge_btn.disabled).is_true()
	assert_bool(d._loop_cut_btn.disabled).is_true()
	assert_bool(d._hard_edge_btn.disabled).is_true()
	assert_bool(d._soft_edge_btn.disabled).is_true()


# ---------------------------------------------------------------------------
# Edge mode — no selection
# ---------------------------------------------------------------------------

func test_all_buttons_disabled_in_edge_mode_with_no_selection() -> void:
	var d := _make_drawer()
	var node := _make_node()
	d.set_target(node)
	node.selection.set_mode(SelectionManager.Mode.EDGE)
	# No edges selected.
	d.refresh_buttons()
	assert_bool(d._extrude_edge_btn.disabled).is_true()
	assert_bool(d._bevel_btn.disabled).is_true()
	assert_bool(d._bridge_btn.disabled).is_true()
	assert_bool(d._loop_cut_btn.disabled).is_true()
	assert_bool(d._hard_edge_btn.disabled).is_true()
	assert_bool(d._soft_edge_btn.disabled).is_true()


# ---------------------------------------------------------------------------
# Edge mode — 1 edge selected
# ---------------------------------------------------------------------------

func test_edge_buttons_enabled_with_one_edge_selected() -> void:
	var d := _make_drawer()
	var node := _make_node()
	d.set_target(node)
	node.selection.set_mode(SelectionManager.Mode.EDGE)
	node.selection.select_edge(0)
	d.refresh_buttons()
	# All except Bridge require only _cond_edge_any (≥1 edge selected).
	assert_bool(d._extrude_edge_btn.disabled).is_false()
	assert_bool(d._bevel_btn.disabled).is_false()
	assert_bool(d._loop_cut_btn.disabled).is_false()
	assert_bool(d._hard_edge_btn.disabled).is_false()
	assert_bool(d._soft_edge_btn.disabled).is_false()


# ---------------------------------------------------------------------------
# Bridge — needs ≥2 boundary edges
# ---------------------------------------------------------------------------

func test_bridge_disabled_with_one_boundary_edge() -> void:
	var d := _make_drawer()
	var node := _make_node()
	d.set_target(node)
	node.selection.set_mode(SelectionManager.Mode.EDGE)
	node.selection.select_edge(0)   # Only 1 boundary edge.
	d.refresh_buttons()
	assert_bool(d._bridge_btn.disabled).is_true()


func test_bridge_enabled_with_two_boundary_edges() -> void:
	var d := _make_drawer()
	var node := _make_node()
	d.set_target(node)
	node.selection.set_mode(SelectionManager.Mode.EDGE)
	# Single-face quad: every edge is a boundary edge (is_boundary() == true).
	node.selection.select_edge(0)
	node.selection.select_edge(1)
	d.refresh_buttons()
	assert_bool(d._bridge_btn.disabled).is_false()
