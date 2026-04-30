## GdUnit4 tests for [GoBuildVertexDrawer] button state.
##
## Verified here (scene-runner approach — drawer added to test-suite scene tree):
##   - Merge button disabled when target is null.
##   - Merge button disabled when fewer than 2 vertices are selected.
##   - Merge button enabled when 2 or more vertices are selected in Vertex mode.
##   - Weld button disabled when target is null.
##   - Weld button enabled in Vertex mode (empty selection is fine).
##   - Weld button disabled when mode is Face (not Vertex).
@tool
extends GdUnitTestSuite

# Self-preloads — dependency order, per the self-preload rule.
const _FACE_SCRIPT           := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT           := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT           := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _SEL_MGR_SCRIPT        := preload("res://addons/go_build/core/selection_manager.gd")
const _MESH_INSTANCE_SCRIPT  := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _DRAWER_SCRIPT         := preload("res://addons/go_build/core/go_build_drawer.gd")
const _VERTEX_DRAWER_SCRIPT  := preload("res://addons/go_build/core/go_build_vertex_drawer.gd")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_drawer() -> GoBuildVertexDrawer:
	var d := GoBuildVertexDrawer.new()
	add_child(d)
	auto_free(d)
	return d


## Create a minimal [GoBuildMeshInstance] with two vertices so selection
## helpers have something to work with.
func _make_node() -> GoBuildMeshInstance:
	var node: GoBuildMeshInstance = auto_free(GoBuildMeshInstance.new())
	var m := GoBuildMesh.new()
	m.vertices = [Vector3(0.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0)]
	var f := GoBuildFace.new()
	f.vertex_indices = [0, 1]
	f.uvs            = [Vector2(0.0, 0.0), Vector2(1.0, 0.0)]
	m.faces.append(f)
	m.rebuild_edges()
	node.go_build_mesh = m
	return node


# ---------------------------------------------------------------------------
# Merge button
# ---------------------------------------------------------------------------

func test_merge_disabled_without_target() -> void:
	var d := _make_drawer()
	d.refresh_buttons()
	assert_bool(d._merge_btn.disabled).is_true()


func test_merge_disabled_with_zero_vertices_selected() -> void:
	var d := _make_drawer()
	var node := _make_node()
	d.set_target(node)
	node.selection.set_mode(SelectionManager.Mode.VERTEX)
	# No vertices selected — default empty.
	d.refresh_buttons()
	assert_bool(d._merge_btn.disabled).is_true()


func test_merge_disabled_with_one_vertex_selected() -> void:
	var d := _make_drawer()
	var node := _make_node()
	d.set_target(node)
	node.selection.set_mode(SelectionManager.Mode.VERTEX)
	node.selection.select_vertex(0)
	d.refresh_buttons()
	assert_bool(d._merge_btn.disabled).is_true()


func test_merge_enabled_with_two_vertices_selected() -> void:
	var d := _make_drawer()
	var node := _make_node()
	d.set_target(node)
	node.selection.set_mode(SelectionManager.Mode.VERTEX)
	node.selection.select_vertex(0)
	node.selection.select_vertex(1)
	d.refresh_buttons()
	assert_bool(d._merge_btn.disabled).is_false()


func test_merge_disabled_in_face_mode_even_with_selection() -> void:
	var d := _make_drawer()
	var node := _make_node()
	d.set_target(node)
	node.selection.set_mode(SelectionManager.Mode.FACE)
	node.selection.select_vertex(0)
	node.selection.select_vertex(1)
	d.refresh_buttons()
	assert_bool(d._merge_btn.disabled).is_true()


# ---------------------------------------------------------------------------
# Weld button
# ---------------------------------------------------------------------------

func test_weld_disabled_without_target() -> void:
	var d := _make_drawer()
	d.refresh_buttons()
	assert_bool(d._weld_btn.disabled).is_true()


func test_weld_enabled_in_vertex_mode_no_selection() -> void:
	var d := _make_drawer()
	var node := _make_node()
	d.set_target(node)
	node.selection.set_mode(SelectionManager.Mode.VERTEX)
	d.refresh_buttons()
	assert_bool(d._weld_btn.disabled).is_false()


func test_weld_disabled_in_face_mode() -> void:
	var d := _make_drawer()
	var node := _make_node()
	d.set_target(node)
	node.selection.set_mode(SelectionManager.Mode.FACE)
	d.refresh_buttons()
	assert_bool(d._weld_btn.disabled).is_true()


func test_weld_disabled_in_edge_mode() -> void:
	var d := _make_drawer()
	var node := _make_node()
	d.set_target(node)
	node.selection.set_mode(SelectionManager.Mode.EDGE)
	d.refresh_buttons()
	assert_bool(d._weld_btn.disabled).is_true()
