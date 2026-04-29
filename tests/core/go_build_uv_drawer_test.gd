## GdUnit4 tests for [GoBuildUvDrawer] button state and UV action name mapping.
##
## Verified here (scene-runner approach — drawer added to test-suite scene tree):
##   - [method GoBuildUvDrawer.uv_action_name] returns correct strings for every mode.
##   - All projection buttons are disabled when no target is set.
##   - All projection buttons are disabled when target is in non-face mode.
##   - All projection buttons are disabled in Face mode with no selection.
##   - All projection buttons are enabled in Face mode with at least one face selected.
##   - [method GoBuildUvDrawer.cancel_preview] is safe to call when no preview is active.
@tool
extends GdUnitTestSuite

# Self-preloads — dependency order, per the self-preload rule.
const _FACE_SCRIPT          := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT          := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT          := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _SEL_MGR_SCRIPT       := preload("res://addons/go_build/core/selection_manager.gd")
const _MESH_INSTANCE_SCRIPT := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _UV_DRAWER_SCRIPT     := preload("res://addons/go_build/core/go_build_uv_drawer.gd")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Instantiate a [GoBuildUvDrawer], add it to the test scene tree so
## [method Node._ready] fires, and register it for auto-cleanup.
func _make_drawer() -> GoBuildUvDrawer:
	var d := GoBuildUvDrawer.new()
	add_child(d)
	auto_free(d)
	return d


## Create a minimal one-face [GoBuildMeshInstance] with a four-vertex quad.
## Not added to the scene tree — drawers only call set_target() on it.
func _make_node_with_quad() -> GoBuildMeshInstance:
	var node: GoBuildMeshInstance = auto_free(GoBuildMeshInstance.new())
	var m := GoBuildMesh.new()
	m.vertices = [
		Vector3(0.0, 0.0, 0.0),
		Vector3(1.0, 0.0, 0.0),
		Vector3(1.0, 1.0, 0.0),
		Vector3(0.0, 1.0, 0.0),
	]
	var f := GoBuildFace.new()
	f.vertex_indices = [0, 1, 2, 3]
	f.uvs = [
		Vector2(0.0, 0.0),
		Vector2(1.0, 0.0),
		Vector2(1.0, 1.0),
		Vector2(0.0, 1.0),
	]
	m.faces.append(f)
	m.rebuild_edges()
	node.go_build_mesh = m
	return node


# ---------------------------------------------------------------------------
# Static UV action name mapping
# ---------------------------------------------------------------------------

func test_uv_action_name_planar() -> void:
	assert_str(GoBuildUvDrawer.uv_action_name(GoBuildFace.UvMode.PLANAR)) \
		.is_equal("Planar UV")


func test_uv_action_name_box() -> void:
	assert_str(GoBuildUvDrawer.uv_action_name(GoBuildFace.UvMode.BOX)) \
		.is_equal("Box UV")


func test_uv_action_name_cylindrical() -> void:
	assert_str(GoBuildUvDrawer.uv_action_name(GoBuildFace.UvMode.CYLINDRICAL)) \
		.is_equal("Cylindrical UV")


func test_uv_action_name_spherical() -> void:
	assert_str(GoBuildUvDrawer.uv_action_name(GoBuildFace.UvMode.SPHERICAL)) \
		.is_equal("Spherical UV")


# ---------------------------------------------------------------------------
# Button state — no target
# ---------------------------------------------------------------------------

func test_all_buttons_disabled_without_target() -> void:
	var d := _make_drawer()
	d.refresh_buttons()
	assert_bool(d._planar_uv_btn.disabled).is_true()
	assert_bool(d._box_uv_btn.disabled).is_true()
	assert_bool(d._cylindrical_uv_btn.disabled).is_true()
	assert_bool(d._spherical_uv_btn.disabled).is_true()


# ---------------------------------------------------------------------------
# Button state — non-face modes
# ---------------------------------------------------------------------------

func test_all_buttons_disabled_in_object_mode() -> void:
	var d    := _make_drawer()
	var node := _make_node_with_quad()
	d.set_target(node)
	node.selection.set_mode(SelectionManager.Mode.OBJECT)
	d.refresh_buttons()
	assert_bool(d._planar_uv_btn.disabled).is_true()
	assert_bool(d._box_uv_btn.disabled).is_true()
	assert_bool(d._cylindrical_uv_btn.disabled).is_true()
	assert_bool(d._spherical_uv_btn.disabled).is_true()


func test_all_buttons_disabled_in_vertex_mode() -> void:
	var d    := _make_drawer()
	var node := _make_node_with_quad()
	d.set_target(node)
	node.selection.set_mode(SelectionManager.Mode.VERTEX)
	d.refresh_buttons()
	assert_bool(d._planar_uv_btn.disabled).is_true()
	assert_bool(d._box_uv_btn.disabled).is_true()
	assert_bool(d._cylindrical_uv_btn.disabled).is_true()
	assert_bool(d._spherical_uv_btn.disabled).is_true()


func test_all_buttons_disabled_in_edge_mode() -> void:
	var d    := _make_drawer()
	var node := _make_node_with_quad()
	d.set_target(node)
	node.selection.set_mode(SelectionManager.Mode.EDGE)
	d.refresh_buttons()
	assert_bool(d._planar_uv_btn.disabled).is_true()
	assert_bool(d._box_uv_btn.disabled).is_true()
	assert_bool(d._cylindrical_uv_btn.disabled).is_true()
	assert_bool(d._spherical_uv_btn.disabled).is_true()


# ---------------------------------------------------------------------------
# Button state — face mode
# ---------------------------------------------------------------------------

func test_all_buttons_disabled_in_face_mode_no_selection() -> void:
	var d    := _make_drawer()
	var node := _make_node_with_quad()
	d.set_target(node)
	node.selection.set_mode(SelectionManager.Mode.FACE)
	d.refresh_buttons()
	assert_bool(d._planar_uv_btn.disabled).is_true()
	assert_bool(d._box_uv_btn.disabled).is_true()
	assert_bool(d._cylindrical_uv_btn.disabled).is_true()
	assert_bool(d._spherical_uv_btn.disabled).is_true()


func test_all_buttons_enabled_in_face_mode_with_selection() -> void:
	var d    := _make_drawer()
	var node := _make_node_with_quad()
	d.set_target(node)
	node.selection.set_mode(SelectionManager.Mode.FACE)
	node.selection.select_face(0)
	d.refresh_buttons()
	assert_bool(d._planar_uv_btn.disabled).is_false()
	assert_bool(d._box_uv_btn.disabled).is_false()
	assert_bool(d._cylindrical_uv_btn.disabled).is_false()
	assert_bool(d._spherical_uv_btn.disabled).is_false()


# ---------------------------------------------------------------------------
# Preview guard
# ---------------------------------------------------------------------------

## cancel_preview() must be safe to call even when no preview is in progress.
func test_cancel_preview_safe_when_not_active() -> void:
	var d := _make_drawer()
	d.cancel_preview()
	assert_bool(d._uv_preview_active).is_false()
