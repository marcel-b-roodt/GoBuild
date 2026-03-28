## A single polygon face in a [GoBuildMesh].
##
## Stores vertex indices (referencing [member GoBuildMesh.vertices]),
## per-vertex UV channels, a material slot index, and a smooth group ID.
class_name GoBuildFace
extends RefCounted

## Indices into [member GoBuildMesh.vertices]. Minimum 3 (triangle), typically 4 (quad).
var vertex_indices: Array[int] = []

## Per-vertex UV0 coordinates. Must have the same count as [member vertex_indices].
var uvs: Array[Vector2] = []

## Per-vertex lightmap UV coordinates (UV1). May be empty; defaults to Vector2.ZERO on bake.
var uv2s: Array[Vector2] = []

## Index into the material slot array of the parent [GoBuildMesh]. 0 = default material.
var material_index: int = 0

## Smooth group ID.
## [code]0[/code] = flat shading (face normal used for every vertex).
## [code]> 0[/code] = normals are averaged with all faces sharing the same vertex and group.
var smooth_group: int = 0


## Returns [code]true[/code] if the face has the minimum required data to be valid.
func is_valid() -> bool:
	return vertex_indices.size() >= 3 and uvs.size() == vertex_indices.size()


## Returns the number of triangles produced by fan-triangulation from vertex 0.
func triangle_count() -> int:
	return vertex_indices.size() - 2

