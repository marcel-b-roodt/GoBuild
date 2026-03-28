## A directed edge between two vertices in a [GoBuildMesh].
##
## Edges are derived from face data and rebuilt via [method GoBuildMesh.rebuild_edges].
## Do not modify this data directly; it is owned by the mesh.
class_name GoBuildEdge
extends RefCounted

## Index of the first vertex in [member GoBuildMesh.vertices].
var vertex_a: int = 0

## Index of the second vertex in [member GoBuildMesh.vertices].
var vertex_b: int = 0

## Indices of all faces in [member GoBuildMesh.faces] that share this edge.
## Typically 1 for a boundary edge, 2 for an interior edge.
var face_indices: Array[int] = []


## Returns [code]true[/code] if this edge connects the two given vertex indices
## (order-independent).
func connects(va: int, vb: int) -> bool:
	return (vertex_a == va and vertex_b == vb) or (vertex_a == vb and vertex_b == va)


## Returns [code]true[/code] if this is a boundary edge (only one adjacent face).
func is_boundary() -> bool:
	return face_indices.size() == 1

