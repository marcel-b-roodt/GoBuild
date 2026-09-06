## A directed edge between two vertices in a [GoBuildMesh].
##
## Persistent topology state: maintained incrementally by the mesh's mutation
## helpers ([method GoBuildMesh.register_face], [method GoBuildMesh.unregister_face],
## [method GoBuildMesh.split_edge]); `rebuild_edges()` survives only as the
## load/undo-restore path.  `hard_edge_pairs` on the mesh is the serialization
## authority; `is_hard` is the runtime view.  Do not modify edge data directly.
@tool
class_name GoBuildEdge
extends RefCounted

## Index of the first vertex in [member GoBuildMesh.vertices].
var vertex_a: int = 0

## Index of the second vertex in [member GoBuildMesh.vertices].
var vertex_b: int = 0

## Indices of all faces in [member GoBuildMesh.faces] that share this edge.
## Typically 1 for a boundary edge, 2 for an interior edge.
var face_indices: Array[int] = []

## When [code]true[/code] this edge acts as a normal seam.
## Adjacent faces sharing this edge will not average their normals at shared
## vertices even when they belong to the same smooth group.
## Runtime view of [member GoBuildMesh.hard_edge_pairs] (the serialization
## authority), synced by [method GoBuildMesh.sync_edge_hard_state].
var is_hard: bool = false


## Returns [code]true[/code] if this edge connects the two given vertex indices
## (order-independent).
func connects(va: int, vb: int) -> bool:
	return (vertex_a == va and vertex_b == vb) or (vertex_a == vb and vertex_b == va)


## Returns [code]true[/code] if this is a boundary edge (only one adjacent face).
func is_boundary() -> bool:
	return face_indices.size() == 1

