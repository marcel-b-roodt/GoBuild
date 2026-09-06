## A named, reusable collection of [Material] references for fast slot swapping.
##
## Save as a [code].tres[/code] resource, then assign it to a
## [GoBuildMeshInstance] via its [code]material_palette[/code] export property.
## Press [b]Apply Palette[/b] in the GoBuild panel to copy
## [member materials] into the mesh's [code]material_slots[/code] array.
##
## Index 0 in [member materials] maps to [code]material_slots[0][/code] (and
## face [code]material_index[/code] 0), and so on.
@tool
class_name GoBuildMaterialPalette
extends Resource

## Human-readable name shown in tooltips and the Inspector.
@export var palette_name: String = ""

## Ordered list of materials.  Indices match face [code]material_index[/code]
## values — [code]materials[0][/code] is applied to faces with
## [code]material_index == 0[/code], etc.
@export var materials: Array[Material] = []


## Return a [code]StandardMaterial3D[/code] with [param path]'s resource as
## albedo — texture files get wrapped fresh, material resources load as-is.
## Reuses [code]resource_name[/code] already on the material.
## Returns [code]null[/code] when the path is not a loadable texture or material.
static func material_from_file(path: String) -> Material:
	if path.is_empty():
		return null
	var lower := path.to_lower()
	if lower.ends_with(".tres") or lower.ends_with(".res"):
		var loaded: Resource = load(path)
		return loaded as Material
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	var tex_name: String = tex.resource_name
	if tex_name == "":
		tex_name = path.get_file().get_basename()
	mat.resource_name = tex_name
	return mat
