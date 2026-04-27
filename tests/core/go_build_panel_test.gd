## GdUnit4 tests for [GoBuildPanel] UX behaviour.
##
## Verified here (scene-runner approach — panel added to test suite scene tree):
##   - Panel is visible after [method Node._ready] fires.
##   - Initial state shows "No mesh selected." with empty stats.
##   - [method GoBuildPanel.set_target] with a valid mesh updates status + stats.
##   - [method GoBuildPanel.set_target] with [code]null[/code] reverts to placeholder.
##   - Clearing a target after a valid one removes all stats text.
@tool
extends GdUnitTestSuite

# Self-preloads — dependency order, per the self-preload rule.
# GoBuildPanel references SelectionManager and GoBuildMeshInstance at
# compile time; those must be registered before this script is compiled.
const _FACE_SCRIPT          := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT          := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT          := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _SEL_MGR_SCRIPT       := preload("res://addons/go_build/core/selection_manager.gd")
const _MESH_INSTANCE_SCRIPT := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _PANEL_SCRIPT         := preload("res://addons/go_build/core/go_build_panel.gd")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Instantiate a [GoBuildPanel], add it to the test-suite scene tree so
## [method Node._ready] fires, and register it for auto-cleanup.
func _make_panel() -> GoBuildPanel:
	var panel := GoBuildPanel.new()
	add_child(panel)
	auto_free(panel)
	return panel


## Build a minimal one-face [GoBuildMesh] (four-vertex quad, edges rebuilt).
func _make_quad_mesh() -> GoBuildMesh:
	var m := GoBuildMesh.new()
	m.vertices = [
		Vector3(0.0, 0.0, 0.0),
		Vector3(1.0, 0.0, 0.0),
		Vector3(1.0, 1.0, 0.0),
		Vector3(0.0, 1.0, 0.0),
	]
	var f := GoBuildFace.new()
	f.vertex_indices = [0, 1, 2, 3]
	f.uvs = [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]
	m.faces.append(f)
	m.rebuild_edges()
	return m


## Create a [GoBuildMeshInstance] named "TestNode" with a quad mesh assigned.
## Not added to the scene tree — panel tests only call [method set_target] on it.
func _make_node_with_quad() -> GoBuildMeshInstance:
	var node: GoBuildMeshInstance = auto_free(GoBuildMeshInstance.new())
	node.name = "TestNode"
	node.go_build_mesh = _make_quad_mesh()
	return node


# ---------------------------------------------------------------------------
# Visibility — panel always present in dock
# ---------------------------------------------------------------------------

func test_panel_is_visible_after_ready() -> void:
	var panel := _make_panel()
	assert_bool(panel.visible).is_true()


func test_panel_extends_vboxcontainer() -> void:
	var panel := _make_panel()
	assert_bool(panel is VBoxContainer).is_true()


func test_panel_has_positive_minimum_width() -> void:
	var panel := _make_panel()
	assert_bool(panel.custom_minimum_size.x > 0.0).is_true()


# ---------------------------------------------------------------------------
# Initial state — no target set
# ---------------------------------------------------------------------------

func test_initial_status_label_shows_no_mesh_selected() -> void:
	var panel := _make_panel()
	assert_str(panel._status_label.text).is_equal("No mesh selected.")


func test_initial_stats_label_is_empty() -> void:
	var panel := _make_panel()
	assert_str(panel._stats_label.text).is_equal("")


# ---------------------------------------------------------------------------
# set_target with a valid mesh
# ---------------------------------------------------------------------------

func test_set_target_status_label_starts_with_editing() -> void:
	var panel := _make_panel()
	var node  := _make_node_with_quad()
	panel.set_target(node)
	assert_str(panel._status_label.text).starts_with("Editing:")


func test_set_target_status_label_contains_node_name() -> void:
	var panel := _make_panel()
	var node  := _make_node_with_quad()
	panel.set_target(node)
	assert_str(panel._status_label.text).contains("TestNode")


func test_set_target_stats_label_shows_vertex_count() -> void:
	# Quad mesh has exactly 4 vertices.
	var panel := _make_panel()
	var node  := _make_node_with_quad()
	panel.set_target(node)
	assert_str(panel._stats_label.text).contains("Verts: 4")


func test_set_target_stats_label_shows_face_count() -> void:
	# Quad mesh has exactly 1 face.
	var panel := _make_panel()
	var node  := _make_node_with_quad()
	panel.set_target(node)
	assert_str(panel._stats_label.text).contains("Faces: 1")


func test_set_target_stats_label_shows_edge_count() -> void:
	# Quad mesh has exactly 4 edges after rebuild_edges().
	var panel := _make_panel()
	var node  := _make_node_with_quad()
	panel.set_target(node)
	assert_str(panel._stats_label.text).contains("Edges: 4")


func test_set_target_stats_label_is_not_empty() -> void:
	var panel := _make_panel()
	var node  := _make_node_with_quad()
	panel.set_target(node)
	assert_str(panel._stats_label.text).is_not_empty()


func test_set_target_syncs_auto_uv_option_from_node() -> void:
	var panel := _make_panel()
	var node  := _make_node_with_quad()
	node.auto_uv_mode = GoBuildFace.UvMode.NONE
	panel.set_target(node)
	assert_int(panel._auto_uv_option.selected).is_equal(GoBuildFace.UvMode.NONE)


func test_auto_uv_option_selection_updates_target_mode() -> void:
	var panel := _make_panel()
	var node  := _make_node_with_quad()
	panel.set_target(node)
	panel._on_auto_uv_mode_selected(GoBuildFace.UvMode.NONE)
	assert_int(node.auto_uv_mode).is_equal(GoBuildFace.UvMode.NONE)
	panel._on_auto_uv_mode_selected(GoBuildFace.UvMode.BOX)
	assert_int(node.auto_uv_mode).is_equal(GoBuildFace.UvMode.BOX)


func test_planar_uv_button_disabled_without_face_selection() -> void:
	var panel := _make_panel()
	var node  := _make_node_with_quad()
	panel.set_target(node)
	node.selection.set_mode(SelectionManager.Mode.FACE)
	assert_bool(panel._planar_uv_btn.disabled).is_true()


func test_planar_uv_button_enabled_with_face_selection() -> void:
	var panel := _make_panel()
	var node  := _make_node_with_quad()
	panel.set_target(node)
	node.selection.set_mode(SelectionManager.Mode.FACE)
	node.selection.select_face(0)
	assert_bool(panel._planar_uv_btn.disabled).is_false()


# ---------------------------------------------------------------------------
# set_target(null) — placeholder text
# ---------------------------------------------------------------------------

func test_set_target_null_shows_placeholder_status() -> void:
	var panel := _make_panel()
	panel.set_target(null)
	assert_str(panel._status_label.text).is_equal("No mesh selected.")


func test_set_target_null_stats_label_is_empty() -> void:
	var panel := _make_panel()
	panel.set_target(null)
	assert_str(panel._stats_label.text).is_equal("")


func test_set_target_null_after_valid_target_shows_placeholder_status() -> void:
	var panel := _make_panel()
	var node  := _make_node_with_quad()
	panel.set_target(node)
	# Sanity: status was updated.
	assert_str(panel._status_label.text).starts_with("Editing:")
	# Clear target.
	panel.set_target(null)
	assert_str(panel._status_label.text).is_equal("No mesh selected.")


func test_set_target_null_after_valid_target_clears_stats() -> void:
	var panel := _make_panel()
	var node  := _make_node_with_quad()
	panel.set_target(node)
	# Sanity: stats were populated.
	assert_str(panel._stats_label.text).is_not_empty()
	# Clear target.
	panel.set_target(null)
	assert_str(panel._stats_label.text).is_equal("")


# ---------------------------------------------------------------------------
# Mode button sync — shortcut / signal-driven updates
#
# These tests cover the path: SelectionManager.mode_changed signal →
# GoBuildPanel._on_target_mode_changed → _sync_mode_buttons.
# This is the same path triggered when the user presses a keyboard shortcut
# (1-4) in the 3D viewport — confirming buttons stay in sync with the mode.
# ---------------------------------------------------------------------------

func test_after_set_target_object_button_is_pressed() -> void:
	# Default mode is OBJECT; the Object button must be visually active.
	var panel := _make_panel()
	var node  := _make_node_with_quad()
	panel.set_target(node)
	assert_bool(panel._mode_buttons[SelectionManager.Mode.OBJECT].button_pressed).is_true()


func test_after_set_target_non_object_buttons_are_not_pressed() -> void:
	var panel := _make_panel()
	var node  := _make_node_with_quad()
	panel.set_target(node)
	assert_bool(panel._mode_buttons[SelectionManager.Mode.VERTEX].button_pressed).is_false()
	assert_bool(panel._mode_buttons[SelectionManager.Mode.EDGE].button_pressed).is_false()
	assert_bool(panel._mode_buttons[SelectionManager.Mode.FACE].button_pressed).is_false()


func test_mode_changed_signal_updates_vertex_button() -> void:
	# Simulates what happens when the user presses the Vertex shortcut (2).
	var panel := _make_panel()
	var node  := _make_node_with_quad()
	panel.set_target(node)
	node.selection.set_mode(SelectionManager.Mode.VERTEX)
	assert_bool(panel._mode_buttons[SelectionManager.Mode.VERTEX].button_pressed).is_true()


func test_mode_changed_signal_releases_previous_button() -> void:
	var panel := _make_panel()
	var node  := _make_node_with_quad()
	panel.set_target(node)
	node.selection.set_mode(SelectionManager.Mode.VERTEX)
	# Object and other non-active buttons must be released.
	assert_bool(panel._mode_buttons[SelectionManager.Mode.OBJECT].button_pressed).is_false()
	assert_bool(panel._mode_buttons[SelectionManager.Mode.EDGE].button_pressed).is_false()
	assert_bool(panel._mode_buttons[SelectionManager.Mode.FACE].button_pressed).is_false()


func test_mode_changed_signal_updates_edge_button() -> void:
	var panel := _make_panel()
	var node  := _make_node_with_quad()
	panel.set_target(node)
	node.selection.set_mode(SelectionManager.Mode.EDGE)
	assert_bool(panel._mode_buttons[SelectionManager.Mode.EDGE].button_pressed).is_true()
	assert_bool(panel._mode_buttons[SelectionManager.Mode.VERTEX].button_pressed).is_false()
	assert_bool(panel._mode_buttons[SelectionManager.Mode.FACE].button_pressed).is_false()


func test_mode_changed_signal_updates_face_button() -> void:
	var panel := _make_panel()
	var node  := _make_node_with_quad()
	panel.set_target(node)
	node.selection.set_mode(SelectionManager.Mode.FACE)
	assert_bool(panel._mode_buttons[SelectionManager.Mode.FACE].button_pressed).is_true()
	assert_bool(panel._mode_buttons[SelectionManager.Mode.VERTEX].button_pressed).is_false()
	assert_bool(panel._mode_buttons[SelectionManager.Mode.EDGE].button_pressed).is_false()


func test_mode_sequence_object_vertex_object_syncs_correctly() -> void:
	# Round-trip: OBJECT → VERTEX → OBJECT must leave Object pressed again.
	var panel := _make_panel()
	var node  := _make_node_with_quad()
	panel.set_target(node)
	node.selection.set_mode(SelectionManager.Mode.VERTEX)
	node.selection.set_mode(SelectionManager.Mode.OBJECT)
	assert_bool(panel._mode_buttons[SelectionManager.Mode.OBJECT].button_pressed).is_true()
	assert_bool(panel._mode_buttons[SelectionManager.Mode.VERTEX].button_pressed).is_false()


func test_exactly_one_button_pressed_per_mode() -> void:
	# Verify radio-button invariant: exactly one button pressed per mode.
	var panel := _make_panel()
	var node  := _make_node_with_quad()
	panel.set_target(node)
	var modes: Array = [
		SelectionManager.Mode.OBJECT,
		SelectionManager.Mode.VERTEX,
		SelectionManager.Mode.EDGE,
		SelectionManager.Mode.FACE,
	]
	for active_mode in modes:
		node.selection.set_mode(active_mode)
		var pressed_count := 0
		for btn: Button in panel._mode_buttons:
			if btn.button_pressed:
				pressed_count += 1
		assert_int(pressed_count).is_equal(1)


# ---------------------------------------------------------------------------
# Create-shape parameter preview config
# ---------------------------------------------------------------------------

func test_supports_shape_preview_for_configurable_generators() -> void:
	var panel := _make_panel()
	assert_bool(panel._supports_shape_preview("Cylinder")).is_true()
	assert_bool(panel._supports_shape_preview("Cone")).is_true()
	assert_bool(panel._supports_shape_preview("Sphere")).is_true()
	assert_bool(panel._supports_shape_preview("Staircase")).is_true()
	assert_bool(panel._supports_shape_preview("Torus")).is_true()
	assert_bool(panel._supports_shape_preview("Arch")).is_true()


func test_shape_preview_not_enabled_for_one_click_generators() -> void:
	var panel := _make_panel()
	assert_bool(panel._supports_shape_preview("Cube")).is_false()
	assert_bool(panel._supports_shape_preview("Plane")).is_false()


func test_default_cylinder_params_include_side_count() -> void:
	var panel := _make_panel()
	var p: Dictionary = panel._default_shape_params("Cylinder")
	assert_int(p.get("sides", -1)).is_equal(16)
	assert_bool(p.get("cap_top", false)).is_true()
	assert_bool(p.get("cap_bottom", false)).is_true()


func test_default_sphere_params_include_rings_and_segments() -> void:
	var panel := _make_panel()
	var p: Dictionary = panel._default_shape_params("Sphere")
	assert_int(p.get("rings", -1)).is_equal(8)
	assert_int(p.get("segments", -1)).is_equal(16)


func test_default_torus_params_match_generator_names() -> void:
	var panel := _make_panel()
	var p: Dictionary = panel._default_shape_params("Torus")
	assert_bool(p.has("radius_major")).is_true()
	assert_bool(p.has("radius_minor")).is_true()
	assert_bool(p.has("rings")).is_true()
	assert_bool(p.has("tube_segments")).is_true()


func test_default_arch_params_include_angle_degrees() -> void:
	var panel := _make_panel()
	var p: Dictionary = panel._default_shape_params("Arch")
	assert_bool(p.has("angle_degrees")).is_true()


func test_build_shape_mesh_cylinder_respects_side_count() -> void:
	# Cylinder with both caps: faces = sides (lateral quads) + sides + sides = 3*sides.
	var panel := _make_panel()
	var p: Dictionary = panel._default_shape_params("Cylinder")
	p["sides"] = 12
	var mesh: GoBuildMesh = panel._build_shape_mesh("Cylinder", p)
	assert_int(mesh.faces.size()).is_equal(36)


func test_build_shape_mesh_cone_respects_side_count() -> void:
	# Cone with base cap: faces = sides (lateral) + sides (cap) = 2*sides.
	var panel := _make_panel()
	var p: Dictionary = panel._default_shape_params("Cone")
	p["sides"] = 10
	p["cap_bottom"] = true
	var mesh: GoBuildMesh = panel._build_shape_mesh("Cone", p)
	assert_int(mesh.faces.size()).is_equal(20)


func test_build_shape_mesh_sphere_respects_rings_and_segments() -> void:
	# UV sphere face count = segments * rings.
	var panel := _make_panel()
	var p: Dictionary = panel._default_shape_params("Sphere")
	p["rings"] = 6
	p["segments"] = 12
	var mesh: GoBuildMesh = panel._build_shape_mesh("Sphere", p)
	assert_int(mesh.faces.size()).is_equal(72)


func test_build_shape_mesh_staircase_respects_step_count() -> void:
	# Staircase face count = 2*steps + 4.
	var panel := _make_panel()
	var p: Dictionary = panel._default_shape_params("Staircase")
	p["steps"] = 7
	var mesh: GoBuildMesh = panel._build_shape_mesh("Staircase", p)
	assert_int(mesh.faces.size()).is_equal(18)


func test_build_shape_mesh_torus_respects_ring_and_tube_counts() -> void:
	# Torus face count = rings * tube_segments.
	var panel := _make_panel()
	var p: Dictionary = panel._default_shape_params("Torus")
	p["rings"] = 9
	p["tube_segments"] = 5
	var mesh: GoBuildMesh = panel._build_shape_mesh("Torus", p)
	assert_int(mesh.faces.size()).is_equal(45)


func test_build_shape_mesh_arch_respects_segment_count() -> void:
	# Arch generator builds 4 quad strips across the arc, each with `segments` quads.
	var panel := _make_panel()
	var p: Dictionary = panel._default_shape_params("Arch")
	p["segments"] = 11
	var mesh: GoBuildMesh = panel._build_shape_mesh("Arch", p)
	assert_int(mesh.faces.size()).is_equal(44)


