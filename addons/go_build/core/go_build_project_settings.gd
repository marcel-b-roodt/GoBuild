## Plugin-wide project settings for GoBuild.
##
## Saved as a [code].tres[/code] resource at
## [code]res://addons/go_build/go_build_settings.tres[/code].  The plugin loads
## this file on startup (creating it when absent) and exposes it via
## [method GoBuildPlugin.get_project_settings] so every panel and operation
## can access it without knowing the storage details.
##
## The [member palettes] field is **deprecated** — kept only for backward-
## compatible deserialization of older settings files.  Palette discovery is
## now filesystem-driven via [method discover_palettes].  When
## [method migrate_palettes_to_disk] finds palettes in the deprecated array,
## it saves each one as a standalone [code].tres[/code] file and clears the array.
@tool
class_name GoBuildProjectSettings
extends Resource

# Self-preloads — dependency order.
const _PALETTE_SCRIPT  := preload("res://addons/go_build/core/go_build_material_palette.gd")
const _MATERIALS_SCRIPT := preload("res://addons/go_build/core/go_build_materials.gd")

## Path used to load and save the project settings file.
## Exposed so [GoBuildPlugin] can notify the editor filesystem after creation.
const SETTINGS_PATH := "res://addons/go_build/go_build_settings.tres"

## Legacy path from earlier versions. Checked during [method load_or_create]
## so existing projects are migrated automatically on next plugin load.
const _LEGACY_PATH := "res://go_build_settings.tres"

## Default palette path. Created on first run when no palettes exist.
const DEFAULT_PALETTE_PATH := "res://addons/go_build/default_palette.tres"

## Deprecated. Kept for backward-compatible deserialization of older settings
## files only. Palette discovery is now filesystem-driven via
## [method discover_palettes].  Call [method migrate_palettes_to_disk] once
## after loading to save any in-memory palettes to standalone [code].tres[/code]
## files and clear this array.
@export var palettes: Array[GoBuildMaterialPalette] = []


# ---------------------------------------------------------------------------
# Static helpers
# ---------------------------------------------------------------------------

## Load the settings resource from [constant SETTINGS_PATH], creating and saving
## a fresh default when the file does not yet exist.
static func load_or_create() -> GoBuildProjectSettings:
	# Try the canonical path first.
	if ResourceLoader.exists(SETTINGS_PATH, "GoBuildProjectSettings"):
		var res := ResourceLoader.load(SETTINGS_PATH, "GoBuildProjectSettings")
		if res is GoBuildProjectSettings:
			var settings := res as GoBuildProjectSettings
			settings.migrate_palettes_to_disk()
			return settings
	# Migrate from the legacy root-level path if present.
	if ResourceLoader.exists(_LEGACY_PATH):
		var legacy := ResourceLoader.load(_LEGACY_PATH)
		if legacy is GoBuildProjectSettings:
			var migrated := legacy as GoBuildProjectSettings
			migrated.resource_path = SETTINGS_PATH
			ResourceSaver.save(migrated, SETTINGS_PATH)
			push_warning(
					"GoBuild: migrated settings from '%s' to '%s'."
					% [_LEGACY_PATH, SETTINGS_PATH]
					+ " You may delete the old file from res://.")
			migrated.migrate_palettes_to_disk()
			return migrated
	# File absent or wrong type — create a fresh one and persist it so the
	# user can find and edit it in the FileSystem dock.
	var fresh := GoBuildProjectSettings.new()
	fresh.resource_path = SETTINGS_PATH
	ResourceSaver.save(fresh, SETTINGS_PATH)
	return fresh


## Scan the project filesystem for [GoBuildMaterialPalette] [code].tres[/code]
## files and return them sorted alphabetically by [member GoBuildMaterialPalette.palette_name].
##
## Uses [method ResourceLoader.load] with a type hint so only files whose
## script class matches [GoBuildMaterialPalette] are loaded.  Files that fail
## to load are silently skipped.
static func discover_palettes() -> Array[GoBuildMaterialPalette]:
	var result: Array[GoBuildMaterialPalette] = []
	var files := _collect_tres_files("res://")
	for path: String in files:
		if not ResourceLoader.exists(path, "GoBuildMaterialPalette"):
			continue
		var res := ResourceLoader.load(path, "GoBuildMaterialPalette")
		if res is GoBuildMaterialPalette:
			result.append(res as GoBuildMaterialPalette)
	result.sort_custom(_compare_palette_name)
	return result


## Ensure a Default palette exists on disk.  If no palette named "Default"
## is found by [method discover_palettes], creates one at
## [constant DEFAULT_PALETTE_PATH] with four standard blockout materials.
##
## Returns the newly created Default palette, or [code]null[/code] if one
## already exists.
static func ensure_default_palette() -> GoBuildMaterialPalette:
	var discovered := discover_palettes()
	for pal: GoBuildMaterialPalette in discovered:
		if pal.palette_name == "Default":
			return null
	var pal := GoBuildMaterialPalette.new()
	pal.palette_name = "Default"
	pal.resource_path = DEFAULT_PALETTE_PATH
	var metre_mat := _load_or_null("res://addons/go_build/go_build_material.tres")
	if metre_mat != null:
		pal.materials.append(metre_mat)
	pal.materials.append(GoBuildMaterials.white_material())
	pal.materials.append(GoBuildMaterials.grey_material())
	pal.materials.append(GoBuildMaterials.checker_material())
	ResourceSaver.save(pal, DEFAULT_PALETTE_PATH)
	EditorInterface.get_resource_filesystem().update_file(DEFAULT_PALETTE_PATH)
	return pal


## Migrate palettes from the deprecated [member palettes] array to standalone
## [code].tres[/code] files on disk, then clear the array and re-save settings.
##
## Each palette that does not already have a [code].resource_path[/code] is saved
## to [code]res://materials/<palette_name>_palette.tres[/code].  Palettes that
## already exist on disk are skipped.  After migration, [member palettes] is
## cleared and the settings file is re-saved.
func migrate_palettes_to_disk() -> void:
	if palettes.is_empty():
		return
	var migrated: Array[GoBuildMaterialPalette] = []
	for pal: GoBuildMaterialPalette in palettes:
		if pal == null:
			continue
		if pal.resource_path != "" and pal.resource_path != SETTINGS_PATH:
			migrated.append(pal)
			continue
		var safe_name := pal.palette_name.to_snake_case()
		if safe_name.is_empty():
			safe_name = "palette"
		var save_path := "res://materials/%s_palette.tres" % safe_name
		DirAccess.make_dir_recursive_absolute("res://materials/")
		ResourceSaver.save(pal, save_path)
		EditorInterface.get_resource_filesystem().update_file(save_path)
		migrated.append(pal)
	palettes.clear()
	ResourceSaver.save(self, SETTINGS_PATH)
	EditorInterface.get_resource_filesystem().update_file(SETTINGS_PATH)


## Persist any in-memory changes back to [constant SETTINGS_PATH].
func save() -> void:
	ResourceSaver.save(self, SETTINGS_PATH)


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

## Recursively collect all [code].tres[/code] file paths under [param dir].
static func _collect_tres_files(dir: String) -> PackedStringArray:
	var result := PackedStringArray()
	var da := DirAccess.open(dir)
	if da == null:
		return result
	da.include_hidden = false
	da.include_navigational = false
	da.list_dir_begin()
	var item := da.get_next()
	while item != "":
		var full := dir.path_join(item)
		if da.current_is_dir():
			var sub := _collect_tres_files(full)
			for p: String in sub:
				result.append(p)
		elif item.get_extension() == "tres":
			result.append(full)
		item = da.get_next()
	return result


## Compare two palettes by name for sorting.  Falls back to resource path.
static func _compare_palette_name(a: GoBuildMaterialPalette, b: GoBuildMaterialPalette) -> bool:
	var na: String = a.palette_name if a.palette_name != "" else a.resource_path
	var nb: String = b.palette_name if b.palette_name != "" else b.resource_path
	return na.naturalnocasecmp_to(nb) < 0


## Load a resource, returning [code]null[/code] on any failure.
static func _load_or_null(path: String) -> Resource:
	if not ResourceLoader.exists(path):
		return null
	var res := ResourceLoader.load(path)
	if res == null:
		return null
	return res