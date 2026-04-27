## A single polygon face in a [GoBuildMesh].
##
## Stores vertex indices (referencing [member GoBuildMesh.vertices]),
## per-vertex UV channels, a material slot index, and a smooth group ID.
@tool
class_name GoBuildFace
extends Resource

## Which UV projection mode was last manually applied to this face.
##
## [constant NONE] means the face defers to the global Auto UV mode on
## [GoBuildMeshInstance].  Any other value means the user explicitly applied a
## projection to this face via the panel or right-click menu, and the global
## auto-mode will leave it untouched.
enum UvMode {
	NONE        = 0, ## No manual projection applied; respects global auto_uv_mode.
	PLANAR      = 1, ## Planar (dominant-axis) projection was manually applied.
	BOX         = 2, ## World-space box projection was manually applied.
	CYLINDRICAL = 3, ## Cylindrical projection around the Y axis was manually applied.
	SPHERICAL   = 4, ## Spherical (latitude/longitude) projection was manually applied.
}

## Indices into [member GoBuildMesh.vertices]. Minimum 3 (triangle), typically 4 (quad).
@export var vertex_indices: Array[int] = []

## Per-vertex UV0 coordinates. Must have the same count as [member vertex_indices].
@export var uvs: Array[Vector2] = []

## Per-vertex lightmap UV coordinates (UV1). May be empty; defaults to Vector2.ZERO on bake.
@export var uv2s: Array[Vector2] = []

## Index into the material slot array of the parent [GoBuildMesh]. 0 = default material.
@export var material_index: int = 0

## Smooth group ID.
## [code]0[/code] = flat shading (face normal used for every vertex).
## [code]> 0[/code] = normals are averaged with all faces sharing the same vertex and group.
@export var smooth_group: int = 0

## Records which UV projection mode was manually applied to this face.
## [constant UvMode.NONE] means the face defers to the global auto UV mode.
@export var uv_projection_mode: UvMode = UvMode.NONE

## UV tiling scale applied during the last manual projection.
## [code]1.0[/code] means one texture repeat per mesh unit; [code]2.0[/code] means two repeats.
## Only meaningful when [member uv_projection_mode] is not [constant UvMode.NONE].
@export var uv_scale: float = 1.0

## UV offset applied after the last manual projection (in UV space).
## Shifts the entire face's UVs by this amount without re-projecting.
## Only meaningful when [member uv_projection_mode] is not [constant UvMode.NONE].
@export var uv_offset: Vector2 = Vector2.ZERO

## Seam rotation offset in degrees applied during the last manual cylindrical or
## spherical projection.  Rotates the longitude seam around the Y axis.
## Only meaningful for [constant UvMode.CYLINDRICAL] and [constant UvMode.SPHERICAL].
@export var uv_seam_rotation: float = 0.0


## Returns [code]true[/code] if the face has the minimum required data to be valid.
func is_valid() -> bool:
	return vertex_indices.size() >= 3 and uvs.size() == vertex_indices.size()


## Returns the number of triangles produced by fan-triangulation from vertex 0.
func triangle_count() -> int:
	return vertex_indices.size() - 2

