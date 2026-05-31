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


# ---------------------------------------------------------------------------
# Loop selection
# ---------------------------------------------------------------------------

## Walk an edge loop starting from [param seed_edge].
##
## An edge loop follows the "straight through" rule: from each quad face
## sharing the current edge, the algorithm steps to the opposite edge in that
## quad.  The walk terminates at boundaries (1-face edges), poles (vertices
## with valence != 4), non-quad faces, or when the loop closes on itself.
##
## Returns an array of edge indices forming the loop, starting from
## [param seed_edge].  A closed loop will not repeat the seed.
static func edge_loop(mesh: GoBuildMesh, seed_edge: int) -> Array[int]:
	if mesh.edges.is_empty() or seed_edge < 0 or seed_edge >= mesh.edges.size():
		return []
	var result: Array[int] = []
	var visited: Dictionary = {}
	var ed: GoBuildEdge = mesh.edges[seed_edge]
	# Walk in both directions from the seed edge.
	# Direction 0: through face[0], then face[1] of successive edges.
	# Direction 1: through face[1] (if it exists), then face[0] of successive edges.
	# This mirrors the _collect_ring/_walk_half approach from LoopCutOperation.
	for start_face_idx: int in ed.face_indices:
		var current_ei: int = seed_edge
		var current_fi: int = start_face_idx
		var need_reverse: bool = (start_face_idx != ed.face_indices[0]) \
				if ed.face_indices.size() > 1 else false
		# Walk until we hit a boundary, pole, non-quad, or a visited edge.
		while current_ei != -1 and not visited.has(current_ei):
			visited[current_ei] = true
			result.append(current_ei)
			# Check continuation vertex valence.
			# For a loop, we need the continuation vertex (the one NOT shared
			# with the previous edge in the walk).  At poles (valence != 4),
			# the loop terminates.
			var current_ed: GoBuildEdge = mesh.edges[current_ei]
			if mesh.faces[current_fi].vertex_indices.size() != 4:
				break
			var opp_ei: int = mesh.opposite_edge_in_quad(current_fi, current_ei)
			if opp_ei == -1:
				break
			# Check valence of both vertices on the opposite edge.
			var opp_ed: GoBuildEdge = mesh.edges[opp_ei]
			if mesh.vertex_valence(opp_ed.vertex_a) != 4 or \
					mesh.vertex_valence(opp_ed.vertex_b) != 4:
				# At a pole — add the opposite edge but stop.
				if not visited.has(opp_ei):
					visited[opp_ei] = true
					result.append(opp_ei)
				break
			# Find the other face sharing opp_ei.
			var next_fi: int = -1
			for adj_fi: int in opp_ed.face_indices:
				if adj_fi != current_fi:
					next_fi = adj_fi
					break
			current_ei = opp_ei
			current_fi = next_fi
			if next_fi == -1:
				break
	# For single-face edges (boundary), only one direction is valid.
	# The loop already contains all found edges.
	# Deduplicate (seed may appear at start from both directions on closed loops).
	if result.size() > 1 and result[0] == result[result.size() - 1]:
		result.remove_at(result.size() - 1)
	return result


# ---------------------------------------------------------------------------
# Ring selection
# ---------------------------------------------------------------------------

## Walk an edge ring starting from [param seed_edge].
##
## An edge ring selects all edges that run *perpendicular* to the seed edge
## through the connected quad strip.  For each quad face sharing the seed
## edge, the algorithm steps to the opposite edge in that face, then continues
## through the face on the other side.
##
## Returns an array of edge indices forming the ring, starting from
## [param seed_edge]. Terminates at boundaries and non-quad faces.
static func edge_ring(mesh: GoBuildMesh, seed_edge: int) -> Array[int]:
	if mesh.edges.is_empty() or seed_edge < 0 or seed_edge >= mesh.edges.size():
		return []
	var result: Array[int] = []
	var visited: Dictionary = {}
	var ed: GoBuildEdge = mesh.edges[seed_edge]
	# For a ring walk, we traverse through faces sharing the edge,
	# stepping to the opposite edge in each quad.
	for direction: int in range(ed.face_indices.size()):
		var current_ei: int = seed_edge
		var current_fi: int = ed.face_indices[direction]
		while current_ei != -1 and not visited.has(current_ei):
			visited[current_ei] = true
			result.append(current_ei)
			if mesh.faces[current_fi].vertex_indices.size() != 4:
				break
			var opp_ei: int = mesh.opposite_edge_in_quad(current_fi, current_ei)
			if opp_ei == -1:
				break
			# Find the other face sharing opp_ei (not current_fi).
			var opp_ed: GoBuildEdge = mesh.edges[opp_ei]
			var next_fi: int = -1
			for adj_fi: int in opp_ed.face_indices:
				if adj_fi != current_fi:
					next_fi = adj_fi
					break
			current_ei = opp_ei
			current_fi = next_fi
			if next_fi == -1:
				# Boundary edge — ring stops here but we already added it.
				break
	return result


## Return the faces adjacent to the edges in an edge loop.
## For each edge in the loop, includes all faces sharing that edge.
static func face_loop(mesh: GoBuildMesh, seed_edge: int) -> Array[int]:
	var loop_edges: Array[int] = edge_loop(mesh, seed_edge)
	var result_set: Dictionary = {}
	for ei: int in loop_edges:
		for fi: int in mesh.edges[ei].face_indices:
			result_set[fi] = true
	var result: Array[int] = []
	for fi: int in result_set:
		result.append(fi)
	return result


## Return the faces in the ring direction — the quads that form the strip
## perpendicular to the seed edge.
static func face_ring(mesh: GoBuildMesh, seed_edge: int) -> Array[int]:
	var ring_edges: Array[int] = edge_ring(mesh, seed_edge)
	var result_set: Dictionary = {}
	for ei: int in ring_edges:
		for fi: int in mesh.edges[ei].face_indices:
			if mesh.faces[fi].vertex_indices.size() == 4:
				result_set[fi] = true
	var result: Array[int] = []
	for fi: int in result_set:
		result.append(fi)
	return result