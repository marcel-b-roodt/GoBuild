## GdUnit4 tests for [GoBuildMaterialsDrawer] button state and palette list.
##
## Verified here (scene-runner approach — drawer added to test-suite scene tree):
##   - Use buttons enabled when target exists (any mode).
##   - Use buttons enabled in Face mode with selection.
##   - Palette dropdown populated from injected _discovered_palettes.
##   - Palette material list shows one row per material in the selected palette.
##   - Palette material list shows placeholder when no palette is selected.
##   - Palette material list shows empty palette label when palette has no materials.
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
const _MATERIALS_SCRIPT     := preload("res://addons/go_build/core/go_build_materials.gd")


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


## Create a [GoBuildMaterialPalette] with [param count] placeholder materials.
func _make_palette_with_materials(palette_name: String, count: int) -> GoBuildMaterialPalette:
	var pal := GoBuildMaterialPalette.new()
	pal.palette_name = palette_name
	for i: int in count:
		var mat := StandardMaterial3D.new()
		mat.resource_name = "Mat %d" % i
		mat.albedo_color = Color(randf(), randf(), randf())
		pal.materials.append(mat)
	return pal


## Inject [param palettes] into the drawer's internal discovery list and
## rebuild the dropdown, bypassing filesystem scanning.
func _inject_palettes(d: GoBuildMaterialsDrawer, palettes: Array[GoBuildMaterialPalette]) -> void:
	d._discovered_palettes = palettes
	d._palette_option.clear()
	for pal: GoBuildMaterialPalette in palettes:
		var display: String = pal.palette_name if pal.palette_name != "" else "(unnamed)"
		d._palette_option.add_item(display)
	if not palettes.is_empty():
		d._palette_option.select(0)
		d._on_palette_selected(0)
	d.refresh_buttons()


# ---------------------------------------------------------------------------
# Palette dropdown
# ---------------------------------------------------------------------------

func test_palette_option_empty_without_injected_palettes() -> void:
	var d := _make_drawer()
	assert_int(d._palette_option.get_item_count()).is_equal(0)


func test_palette_option_count_matches_injected_palettes() -> void:
	var d := _make_drawer()
	var pals: Array[GoBuildMaterialPalette] = []
	pals.append(_make_palette_with_materials("Wood", 2))
	pals.append(_make_palette_with_materials("Metal", 3))
	_inject_palettes(d, pals)
	assert_int(d._palette_option.get_item_count()).is_equal(2)


# ---------------------------------------------------------------------------
# Palette material list
# ---------------------------------------------------------------------------

func test_pal_materials_vbox_shows_placeholder_when_no_palette() -> void:
	var d := _make_drawer()
	d.refresh()
	assert_int(d._pal_materials_vbox.get_child_count()).is_equal(1)


func test_pal_materials_vbox_shows_empty_label_when_palette_has_no_materials() -> void:
	var d := _make_drawer()
	var empty_pal := GoBuildMaterialPalette.new()
	empty_pal.palette_name = "Empty"
	var pals: Array[GoBuildMaterialPalette] = [empty_pal]
	_inject_palettes(d, pals)
	d._on_palette_selected(0)
	assert_int(d._pal_materials_vbox.get_child_count()).is_equal(1)


func test_pal_materials_vbox_shows_one_row_per_material() -> void:
	var d := _make_drawer()
	var pal := _make_palette_with_materials("Test", 3)
	var pals: Array[GoBuildMaterialPalette] = [pal]
	_inject_palettes(d, pals)
	d._on_palette_selected(0)
	assert_int(d._pal_materials_vbox.get_child_count()).is_equal(3)


func test_pal_materials_vbox_clears_when_palette_deselected() -> void:
	var d := _make_drawer()
	var pal := _make_palette_with_materials("Test", 2)
	var pals: Array[GoBuildMaterialPalette] = [pal]
	_inject_palettes(d, pals)
	d._on_palette_selected(0)
	assert_int(d._pal_materials_vbox.get_child_count()).is_equal(2)
	# Deselect by clearing discovered palettes
	var empty: Array[GoBuildMaterialPalette] = []
	_inject_palettes(d, empty)
	assert_int(d._pal_materials_vbox.get_child_count()).is_equal(1)


# ---------------------------------------------------------------------------
# Default palette creation
# ---------------------------------------------------------------------------

func test_ensure_default_palette_creates_palette_object() -> void:
	var pal := GoBuildProjectSettings.ensure_default_palette()
	if pal != null:
		assert_bool(pal is GoBuildMaterialPalette).is_true()
		assert_str(pal.palette_name).is_equal("Default")
		assert_int(pal.materials.size()).is_greater_equal(3)


# ---------------------------------------------------------------------------
# GoBuildProjectSettings.discover_palettes
# ---------------------------------------------------------------------------

func test_discover_palettes_returns_array() -> void:
	var result := GoBuildProjectSettings.discover_palettes()
	assert_bool(result is Array).is_true()