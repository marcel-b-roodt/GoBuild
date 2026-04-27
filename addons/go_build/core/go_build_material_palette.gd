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
