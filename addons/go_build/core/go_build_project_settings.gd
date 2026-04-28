## Plugin-wide project settings for GoBuild.
##
## Saved as a [code].tres[/code] resource at
## [code]res://go_build_settings.tres[/code].  The plugin loads this file on
## startup (creating it when absent) and exposes it via
## [method GoBuildPlugin.get_project_settings] so every panel and operation
## can access it without knowing the storage details.
##
## Currently stores the shared palette library. Other global plugin prefs
## (e.g. default grid step, colour themes) will be added here as needed.
@tool
class_name GoBuildProjectSettings
extends Resource

const _SAVE_PATH := "res://go_build_settings.tres"

## Ordered list of [GoBuildMaterialPalette] resources available to all meshes
## in this project.  Indices have no semantic meaning; the panel shows palettes
## by [member GoBuildMaterialPalette.palette_name].
@export var palettes: Array[GoBuildMaterialPalette] = []


# ---------------------------------------------------------------------------
# Static helpers
# ---------------------------------------------------------------------------

## Load the settings resource from [constant _SAVE_PATH], creating and saving
## a fresh one when the file does not yet exist.
static func load_or_create() -> GoBuildProjectSettings:
	if ResourceLoader.exists(_SAVE_PATH, "GoBuildProjectSettings"):
		var res := ResourceLoader.load(_SAVE_PATH, "GoBuildProjectSettings")
		if res is GoBuildProjectSettings:
			return res as GoBuildProjectSettings
	# File absent or wrong type — create a fresh one and persist it immediately
	# so the user can find and edit it in the FileSystem dock.
	var fresh := GoBuildProjectSettings.new()
	fresh.resource_path = _SAVE_PATH
	ResourceSaver.save(fresh, _SAVE_PATH)
	return fresh


## Persist any in-memory changes back to [constant _SAVE_PATH].
func save() -> void:
	ResourceSaver.save(self, _SAVE_PATH)


## Return the index of [param palette] in [member palettes], or [code]-1[/code]
## if it is not found.
func index_of(palette: GoBuildMaterialPalette) -> int:
	for i: int in palettes.size():
		if palettes[i] == palette:
			return i
	return -1


## Add [param palette] to [member palettes] if it is not already present,
## then save.
func add_palette(palette: GoBuildMaterialPalette) -> void:
	if palette == null or index_of(palette) >= 0:
		return
	palettes.append(palette)
	save()


## Remove the palette at [param index] from [member palettes] and save.
func remove_palette_at(index: int) -> void:
	if index < 0 or index >= palettes.size():
		return
	palettes.remove_at(index)
	save()
