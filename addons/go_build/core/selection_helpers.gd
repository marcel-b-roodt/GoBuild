## Pure static helpers for topology-based selection operations.
##
## All methods are headless-safe (no EditorPlugin dependencies) and operate
## on [GoBuildMesh] data.  This makes them easy to test with GdUnit4 and to
## call from gizmos, the panel, context menus, and keyboard handlers.
##
## Requires that [method GoBuildMesh.rebuild_edges] has been called on the
## mesh before using any method here (the adjacency caches must be up to date).
@tool
class_name SelectionHelpers
extends RefCounted

# Self-preloads — dependency order.
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT := preload("res://addons/go_build/mesh/go_build_edge.gd")


# ---------------------------------------------------------------------------
# Grow selection
# ---------------------------------------------------------------------------

## Expand [param indices] by one topological ring: add all vertices that share
## an edge with any currently selected vertex.
static func grow_vertices(mesh: GoBuildMesh, indices: Array[int]) -> Array[int]:
	if indices.is_empty() or mesh.edges.is_empty():
		return indices.duplicate()
	var result_set: Dictionary = {}
	for vi: int in indices:
		result_set[vi] = true
		var edge_indices: Array = mesh._vertex_to_edges.get(vi, [])
		for ei: int in edge_indices:
			var ed: GoBuildEdge = mesh.edges[ei]
			result_set[ed.vertex_a] = true
			result_set[ed.vertex_b] = true
	var result: Array[int] = []
	for vi: int in result_set:
		result.append(vi)
	return result


## Expand [param indices] by one topological ring: add all edges that share a
## vertex with any currently selected edge.
static func grow_edges(mesh: GoBuildMesh, indices: Array[int]) -> Array[int]:
	if indices.is_empty() or mesh.edges.is_empty():
		return indices.duplicate()
	var result_set: Dictionary = {}
	for ei: int in indices:
		result_set[ei] = true
		var ed: GoBuildEdge = mesh.edges[ei]
		var va_edges: Array = mesh._vertex_to_edges.get(ed.vertex_a, [])
		for adj_ei: int in va_edges:
			result_set[adj_ei] = true
		var vb_edges: Array = mesh._vertex_to_edges.get(ed.vertex_b, [])
		for adj_ei: int in vb_edges:
			result_set[adj_ei] = true
	var result: Array[int] = []
	for ei: int in result_set:
		result.append(ei)
	return result


## Expand [param indices] by one topological ring: add all faces that share an
## edge with any currently selected face.
static func grow_faces(mesh: GoBuildMesh, indices: Array[int]) -> Array[int]:
	if indices.is_empty() or mesh.edges.is_empty():
		return indices.duplicate()
	var result_set: Dictionary = {}
	for fi: int in indices:
		result_set[fi] = true
		var edge_indices: Array = mesh._face_to_edges[fi] as Array
		if edge_indices == null:
			continue
		for ei: int in edge_indices:
			var ed: GoBuildEdge = mesh.edges[ei]
			for adj_fi: int in ed.face_indices:
				result_set[adj_fi] = true
	var result: Array[int] = []
	for fi: int in result_set:
		result.append(fi)
	return result


# ---------------------------------------------------------------------------
# Shrink selection
# ---------------------------------------------------------------------------

## Remove vertices from [param indices] that have at least one unselected
## neighbour vertex (i.e., keep only interior vertices of the selection).
static func shrink_vertices(mesh: GoBuildMesh, indices: Array[int]) -> Array[int]:
	if indices.is_empty() or mesh.edges.is_empty():
		return []
	var selected_set: Dictionary = {}
	for vi: int in indices:
		selected_set[vi] = true
	var result: Array[int] = []
	for vi: int in indices:
		var all_selected: bool = true
		var edge_indices: Array = mesh._vertex_to_edges.get(vi, [])
		for ei: int in edge_indices:
			var ed: GoBuildEdge = mesh.edges[ei]
			var other: int = ed.vertex_b if ed.vertex_a == vi else ed.vertex_a
			if not selected_set.has(other):
				all_selected = false
				break
		if all_selected:
			result.append(vi)
	return result


## Remove edges from [param indices] that have at least one vertex shared with
## an unselected edge (i.e., keep only interior edges of the selection).
static func shrink_edges(mesh: GoBuildMesh, indices: Array[int]) -> Array[int]:
	if indices.is_empty() or mesh.edges.is_empty():
		return []
	var selected_set: Dictionary = {}
	for ei: int in indices:
		selected_set[ei] = true
	var result: Array[int] = []
	for ei: int in indices:
		var ed: GoBuildEdge = mesh.edges[ei]
		var va_edges: Array = mesh._vertex_to_edges.get(ed.vertex_a, [])
		var vb_edges: Array = mesh._vertex_to_edges.get(ed.vertex_b, [])
		var all_neighbours_selected: bool = true
		for adj_ei: int in va_edges:
			if not selected_set.has(adj_ei):
				all_neighbours_selected = false
				break
		if all_neighbours_selected:
			for adj_ei: int in vb_edges:
				if not selected_set.has(adj_ei):
					all_neighbours_selected = false
					break
		if all_neighbours_selected:
			result.append(ei)
	return result


## Remove faces from [param indices] that have at least one edge shared with an
## unselected face (i.e., keep only interior faces of the selection).
static func shrink_faces(mesh: GoBuildMesh, indices: Array[int]) -> Array[int]:
	if indices.is_empty() or mesh.edges.is_empty():
		return []
	var selected_set: Dictionary = {}
	for fi: int in indices:
		selected_set[fi] = true
	var result: Array[int] = []
	for fi: int in indices:
		var all_selected: bool = true
		var edge_indices: Array = mesh._face_to_edges[fi] as Array
		if edge_indices == null:
			continue
		for ei: int in edge_indices:
			var ed: GoBuildEdge = mesh.edges[ei]
			for adj_fi: int in ed.face_indices:
				if not selected_set.has(adj_fi):
					all_selected = false
					break
			if not all_selected:
				break
		if all_selected:
			result.append(fi)
	return result