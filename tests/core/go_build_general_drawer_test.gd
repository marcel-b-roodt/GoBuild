## GdUnit4 tests for [GoBuildGeneralDrawer] button state.
##
## Verified here:
##   - Delete button disabled when target is null.
##   - Delete button disabled in Object mode (no element selection possible).
##   - Delete button enabled in Vertex mode with ≥1 vertex selected.
##   - Delete button enabled in Edge mode with ≥1 edge selected.
##   - Delete button enabled in Face mode with ≥1 face selected.
##   - Delete button disabled in Vertex mode with no selection.
@tool
extends GdUnitTestSuite

# Self-preloads — dependency order.
const _FACE_SCRIPT             := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT             := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT             := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _SEL_MGR_SCRIPT          := preload("res://addons/go_build/core/selection_manager.gd")
const _MESH_INSTANCE_SCRIPT    := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _DRAWER_SCRIPT           := preload("res://addons/go_build/core/go_build_drawer.gd")
const _GENERAL_DRAWER_SCRIPT   := preload("res://addons/go_build/core/go_build_general_drawer.gd")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_drawer() -> GoBuildGeneralDrawer:
	var d := GoBuildGeneralDrawer.new()
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

func test_delete_disabled_without_target() -> void:
	var d := _make_drawer()
	d.refresh_buttons()
	assert_bool(d._delete_btn.disabled).is_true()


# ---------------------------------------------------------------------------
# Object mode — no element selection
# ---------------------------------------------------------------------------

func test_delete_disabled_in_object_mode() -> void:
	var d := _make_drawer()
	var node := _make_node()
	d.set_target(node)
	node.selection.set_mode(SelectionManager.Mode.OBJECT)
	d.refresh_buttons()
	assert_bool(d._delete_btn.disabled).is_true()


# ---------------------------------------------------------------------------
# Vertex mode
# ---------------------------------------------------------------------------

func test_delete_disabled_in_vertex_mode_with_no_selection() -> void:
	var d := _make_drawer()
	var node := _make_node()
	d.set_target(node)
	node.selection.set_mode(SelectionManager.Mode.VERTEX)
	d.refresh_buttons()
	assert_bool(d._delete_btn.disabled).is_true()


func test_delete_enabled_in_vertex_mode_with_selection() -> void:
	var d := _make_drawer()
	var node := _make_node()
	d.set_target(node)
	node.selection.set_mode(SelectionManager.Mode.VERTEX)
	node.selection.select_vertex(0)
	d.refresh_buttons()
	assert_bool(d._delete_btn.disabled).is_false()


# ---------------------------------------------------------------------------
# Edge mode
# ---------------------------------------------------------------------------

func test_delete_enabled_in_edge_mode_with_selection() -> void:
	var d := _make_drawer()
	var node := _make_node()
	d.set_target(node)
	node.selection.set_mode(SelectionManager.Mode.EDGE)
	node.selection.select_edge(0)
	d.refresh_buttons()
	assert_bool(d._delete_btn.disabled).is_false()


# ---------------------------------------------------------------------------
# Face mode
# ---------------------------------------------------------------------------

func test_delete_enabled_in_face_mode_with_selection() -> void:
	var d := _make_drawer()
	var node := _make_node()
	d.set_target(node)
	node.selection.set_mode(SelectionManager.Mode.FACE)
	node.selection.select_face(0)
	d.refresh_buttons()
	assert_bool(d._delete_btn.disabled).is_false()
