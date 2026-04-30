## GdUnit4 tests for [GoBuildSurfaceDrawer] button state.
##
## Verified here:
##   - All buttons disabled when target is null.
##   - Assign/Flat/Smooth disabled in Edge mode (wrong mode).
##   - Assign/Flat/Smooth disabled in Face mode with no selection.
##   - Assign/Flat/Smooth enabled in Face mode with ≥1 face selected.
##   - Auto Smooth disabled when target has no mesh.
##   - Auto Smooth enabled when target has a mesh (independent of selection).
@tool
extends GdUnitTestSuite

# Self-preloads — dependency order.
const _FACE_SCRIPT             := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT             := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT             := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _SEL_MGR_SCRIPT          := preload("res://addons/go_build/core/selection_manager.gd")
const _MESH_INSTANCE_SCRIPT    := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _DRAWER_SCRIPT           := preload("res://addons/go_build/core/go_build_drawer.gd")
const _SURFACE_DRAWER_SCRIPT   := preload("res://addons/go_build/core/go_build_surface_drawer.gd")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_drawer() -> GoBuildSurfaceDrawer:
	var d := GoBuildSurfaceDrawer.new()
	add_child(d)
	auto_free(d)
	return d


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
	assert_bool(d._assign_smooth_btn.disabled).is_true()
	assert_bool(d._flat_btn.disabled).is_true()
	assert_bool(d._smooth_btn.disabled).is_true()
	assert_bool(d._auto_smooth_btn.disabled).is_true()


# ---------------------------------------------------------------------------
# Wrong mode (Edge) — Assign/Flat/Smooth disabled; Auto Smooth enabled (mesh-only)
# ---------------------------------------------------------------------------

func test_face_buttons_disabled_in_edge_mode() -> void:
	var d := _make_drawer()
	var node := _make_node()
	d.set_target(node)
	node.selection.set_mode(SelectionManager.Mode.EDGE)
	d.refresh_buttons()
	assert_bool(d._assign_smooth_btn.disabled).is_true()
	assert_bool(d._flat_btn.disabled).is_true()
	assert_bool(d._smooth_btn.disabled).is_true()


func test_auto_smooth_enabled_in_edge_mode_with_mesh() -> void:
	var d := _make_drawer()
	var node := _make_node()
	d.set_target(node)
	node.selection.set_mode(SelectionManager.Mode.EDGE)
	d.refresh_buttons()
	# Auto Smooth only needs a mesh, not a face selection.
	assert_bool(d._auto_smooth_btn.disabled).is_false()


# ---------------------------------------------------------------------------
# Face mode — no selection
# ---------------------------------------------------------------------------

func test_face_buttons_disabled_in_face_mode_with_no_selection() -> void:
	var d := _make_drawer()
	var node := _make_node()
	d.set_target(node)
	node.selection.set_mode(SelectionManager.Mode.FACE)
	d.refresh_buttons()
	assert_bool(d._assign_smooth_btn.disabled).is_true()
	assert_bool(d._flat_btn.disabled).is_true()
	assert_bool(d._smooth_btn.disabled).is_true()


# ---------------------------------------------------------------------------
# Face mode — 1 face selected
# ---------------------------------------------------------------------------

func test_face_buttons_enabled_with_one_face_selected() -> void:
	var d := _make_drawer()
	var node := _make_node()
	d.set_target(node)
	node.selection.set_mode(SelectionManager.Mode.FACE)
	node.selection.select_face(0)
	d.refresh_buttons()
	assert_bool(d._assign_smooth_btn.disabled).is_false()
	assert_bool(d._flat_btn.disabled).is_false()
	assert_bool(d._smooth_btn.disabled).is_false()


# ---------------------------------------------------------------------------
# Auto Smooth — needs mesh only
# ---------------------------------------------------------------------------

func test_auto_smooth_disabled_when_node_has_no_mesh() -> void:
	var d := _make_drawer()
	var node: GoBuildMeshInstance = auto_free(GoBuildMeshInstance.new())
	# node.go_build_mesh is null by default.
	d.set_target(node)
	d.refresh_buttons()
	assert_bool(d._auto_smooth_btn.disabled).is_true()


func test_auto_smooth_enabled_when_node_has_mesh() -> void:
	var d := _make_drawer()
	var node := _make_node()
	d.set_target(node)
	d.refresh_buttons()
	assert_bool(d._auto_smooth_btn.disabled).is_false()
