## GdUnit4 tests for [GoBuildMaterialsDrawer] button state and slot list.
##
## Verified here (scene-runner approach — drawer added to test-suite scene tree):
##   - Assign / quickset buttons disabled with no target or in non-face modes.
##   - Assign / quickset buttons enabled in Face mode with at least one face selected.
##   - Apply Palette button disabled when no settings resource is assigned.
##   - Apply Palette button disabled when the settings palette list is empty.
##   - Apply Palette button enabled when target, settings, and a palette item are present.
##   - Palette dropdown item count matches the number of palettes in settings.
##   - The live slot list (mat_palette_vbox) is empty when no target is set.
##   - The live slot list shows a placeholder label when the mesh has no material slots.
##   - The live slot list shows one row per material slot.
@tool
extends GdUnitTestSuite

# Self-preloads — dependency order, per the self-preload rule.
const _FACE_SCRIPT          := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT          := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT          := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _SEL_MGR_SCRIPT       := preload("res://addons/go_build/core/selection_manager.gd")
const _MESH_INSTANCE_SCRIPT := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _PALETTE_SCRIPT       := preload("res://addons/go_build/core/go_build_material_palette.gd")
const _SETTINGS_SCRIPT      := preload("res://addons/go_build/core/go_build_project_settings.gd")
const _MAT_DRAWER_SCRIPT    := preload("res://addons/go_build/core/go_build_materials_drawer.gd")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Instantiate a [GoBuildMaterialsDrawer], add it to the test scene tree so
## [method Node._ready] fires, and register it for auto-cleanup.
func _make_drawer() -> GoBuildMaterialsDrawer:
	var d := GoBuildMaterialsDrawer.new()
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


## Create a node whose mesh has [param slot_count] null material slots.
func _make_node_with_slots(slot_count: int) -> GoBuildMeshInstance:
	var node := _make_node_with_quad()
	var slots: Array[Material] = []
	for _i: int in slot_count:
		slots.append(null)
	node.go_build_mesh.material_slots = slots
	return node


## Create a [GoBuildProjectSettings] with [param count] named palettes.
## Does not touch the filesystem — palettes are ephemeral Resource objects.
func _make_settings_with_palettes(count: int) -> GoBuildProjectSettings:
	var settings := GoBuildProjectSettings.new()
	for i: int in count:
		var pal := GoBuildMaterialPalette.new()
		pal.palette_name = "Palette %d" % i
		settings.palettes.append(pal)
	return settings


# ---------------------------------------------------------------------------
# Button state — assign / quickset buttons
# ---------------------------------------------------------------------------

func test_assign_material_btn_disabled_without_target() -> void:
	var d := _make_drawer()
	d.refresh_buttons()
	assert_bool(d._assign_material_btn.disabled).is_true()


func test_assign_material_btn_disabled_in_vertex_mode() -> void:
	var d    := _make_drawer()
	var node := _make_node_with_quad()
	d.set_target(node)
	node.selection.set_mode(SelectionManager.Mode.VERTEX)
	d.refresh_buttons()
	assert_bool(d._assign_material_btn.disabled).is_true()


func test_assign_material_btn_disabled_in_face_mode_no_selection() -> void:
	var d    := _make_drawer()
	var node := _make_node_with_quad()
	d.set_target(node)
	node.selection.set_mode(SelectionManager.Mode.FACE)
	d.refresh_buttons()
	assert_bool(d._assign_material_btn.disabled).is_true()


func test_assign_material_btn_enabled_in_face_mode_with_selection() -> void:
	var d    := _make_drawer()
	var node := _make_node_with_quad()
	d.set_target(node)
	node.selection.set_mode(SelectionManager.Mode.FACE)
	node.selection.select_face(0)
	d.refresh_buttons()
	assert_bool(d._assign_material_btn.disabled).is_false()


func test_qs_checker_btn_disabled_without_target() -> void:
	var d := _make_drawer()
	d.refresh_buttons()
	assert_bool(d._qs_checker_btn.disabled).is_true()


func test_qs_checker_btn_enabled_in_face_mode_with_selection() -> void:
	var d    := _make_drawer()
	var node := _make_node_with_quad()
	d.set_target(node)
	node.selection.set_mode(SelectionManager.Mode.FACE)
	node.selection.select_face(0)
	d.refresh_buttons()
	assert_bool(d._qs_checker_btn.disabled).is_false()


func test_qs_white_btn_enabled_in_face_mode_with_selection() -> void:
	var d    := _make_drawer()
	var node := _make_node_with_quad()
	d.set_target(node)
	node.selection.set_mode(SelectionManager.Mode.FACE)
	node.selection.select_face(0)
	d.refresh_buttons()
	assert_bool(d._qs_white_btn.disabled).is_false()


func test_qs_grey_btn_enabled_in_face_mode_with_selection() -> void:
	var d    := _make_drawer()
	var node := _make_node_with_quad()
	d.set_target(node)
	node.selection.set_mode(SelectionManager.Mode.FACE)
	node.selection.select_face(0)
	d.refresh_buttons()
	assert_bool(d._qs_grey_btn.disabled).is_false()


# ---------------------------------------------------------------------------
# Palette dropdown and Apply button
# ---------------------------------------------------------------------------

func test_apply_palette_btn_disabled_without_settings() -> void:
	var d := _make_drawer()
	d.refresh_buttons()
	assert_bool(d._apply_palette_btn.disabled).is_true()


func test_palette_option_empty_without_settings() -> void:
	var d := _make_drawer()
	assert_int(d._palette_option.get_item_count()).is_equal(0)


func test_palette_option_count_matches_one_palette() -> void:
	var d        := _make_drawer()
	var settings := _make_settings_with_palettes(1)
	d.set_project_settings(settings)
	assert_int(d._palette_option.get_item_count()).is_equal(1)


func test_palette_option_count_matches_two_palettes() -> void:
	var d        := _make_drawer()
	var settings := _make_settings_with_palettes(2)
	d.set_project_settings(settings)
	assert_int(d._palette_option.get_item_count()).is_equal(2)


func test_apply_palette_btn_disabled_when_palettes_empty() -> void:
	var d        := _make_drawer()
	var settings := _make_settings_with_palettes(0)
	var node     := _make_node_with_quad()
	d.set_project_settings(settings)
	d.set_target(node)
	d.refresh_buttons()
	assert_bool(d._apply_palette_btn.disabled).is_true()


func test_apply_palette_btn_enabled_with_target_and_palette_selected() -> void:
	var d        := _make_drawer()
	var settings := _make_settings_with_palettes(1)
	var node     := _make_node_with_quad()
	d.set_project_settings(settings)
	d.set_target(node)
	d._palette_option.select(0)
	d.refresh_buttons()
	assert_bool(d._apply_palette_btn.disabled).is_false()


# ---------------------------------------------------------------------------
# Live slot list
# ---------------------------------------------------------------------------

func test_mat_palette_vbox_empty_without_target() -> void:
	var d := _make_drawer()
	d.refresh()
	assert_int(d._mat_palette_vbox.get_child_count()).is_equal(0)


func test_mat_palette_vbox_shows_placeholder_label_when_no_slots() -> void:
	var d    := _make_drawer()
	var node := _make_node_with_slots(0)
	d.set_target(node)
	d.refresh()
	# A single "no slots" label should be the only child.
	assert_int(d._mat_palette_vbox.get_child_count()).is_equal(1)


func test_mat_palette_vbox_shows_one_row_per_slot() -> void:
	var d    := _make_drawer()
	var node := _make_node_with_slots(3)
	d.set_target(node)
	d.refresh()
	assert_int(d._mat_palette_vbox.get_child_count()).is_equal(3)


func test_mat_palette_vbox_clears_on_target_cleared() -> void:
	var d    := _make_drawer()
	var node := _make_node_with_slots(2)
	d.set_target(node)
	d.refresh()
	# Sanity: 2 rows present.
	assert_int(d._mat_palette_vbox.get_child_count()).is_equal(2)
	d.set_target(null)
	d.refresh()
	assert_int(d._mat_palette_vbox.get_child_count()).is_equal(0)
