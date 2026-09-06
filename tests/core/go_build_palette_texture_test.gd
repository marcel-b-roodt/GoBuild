## Palette texture support tests — GdUnit4
##
## [GoBuildMaterialPalette.material_from_file] wraps a Texture2D file in a
## StandardMaterial3D (albedo) or loads .tres materials directly.
@tool
extends GdUnitTestSuite

const _PALETTE_SCRIPT := preload("res://addons/go_build/core/go_build_material_palette.gd")


func test_material_from_file_empty_path_is_null() -> void:
	assert_that(GoBuildMaterialPalette.material_from_file("")).is_null()


func test_material_from_unsupported_extension_is_null() -> void:
	assert_that(GoBuildMaterialPalette.material_from_file("res://project.godot")).is_null()


func test_material_from_file_loads_tres_material() -> void:
	var path := "res://tests/core/fixture_palette_mat.tres"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.2, 0.3)
	mat.resource_name = "Fixture"
	ResourceSaver.save(mat, path)
	auto_free(mat)
	var loaded := GoBuildMaterialPalette.material_from_file(path)
	assert_bool(loaded is StandardMaterial3D).is_true()
	assert_float((loaded as StandardMaterial3D).albedo_color.r).is_equal_approx(0.1, 0.001)


func test_material_from_file_wraps_texture() -> void:
	# Uses the addon's shipped metre texture — a real imported Texture2D.
	var path := "res://addons/go_build/go_build_metre_texture.png"
	var loaded := GoBuildMaterialPalette.material_from_file(path)
	assert_bool(loaded is StandardMaterial3D).is_true()
	var smat := loaded as StandardMaterial3D
	assert_bool(smat.albedo_texture is Texture2D).is_true()
	assert_str(smat.resource_name).is_equal("go_build_metre_texture")