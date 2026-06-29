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

## Criteria for "Select Similar" operations on faces.
enum FaceSimilarCriterion {
	MATERIAL,      ## Same material_index
	SIDE_COUNT,    ## Same number of vertex_indices (triangle, quad, n-gon)
	NORMAL,        ## Similar face normal (within tolerance)
	COPLANAR,      ## Same plane (normal + distance from origin)
	AREA,          ## Similar area (within tolerance)
}

## Criteria for "Select Similar" on edges.
enum EdgeSimilarCriterion {
	LENGTH,        ## Similar edge length (within tolerance)
	FACE_COUNT,    ## Same number of adjacent faces (boundary = 1, interior = 2)
	DIHEDRAL,     ## Similar dihedral angle between adjacent faces (within tolerance)
}

## Criteria for "Select Similar" on vertices.
enum VertexSimilarCriterion {
	VALENCE,       ## Same number of connected edges
}

# Self-preloads — dependency order.
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _DEBUG_SCRIPT := preload("res://addons/go_build/core/go_build_debug.gd")

# Select Similar — tolerance thresholds.
# Area and length use relative tolerance: two values match if their
# difference is within this fraction of the larger value.
const _AREA_RELATIVE_TOLERANCE: float = 0.001
const _LENGTH_RELATIVE_TOLERANCE: float = 0.001
# Dihedral angle tolerance in degrees.  Two edges match if their
# dihedral angles differ by less than this threshold.
# 3° is generous enough to group edges that are visually the same
# but differ slightly due to mesh topology (subdivided surfaces,
# slightly non-planar faces, etc.).
const _DIHEDRAL_ANGLE_TOLERANCE: float = 3.0
# Dot-product threshold for normal similarity.  cos(2.5°) ≈ 0.999,
# so faces whose normals differ by up to ~2.5° are considered similar.
const _NORMAL_DOT_THRESHOLD: float = 0.999
# Distance threshold for coplanar comparison.  Two faces with the same
# normal are coplanar if their plane distances differ by less than this.
const _COPLANAR_DIST_THRESHOLD: float = 0.01


# ---------------------------------------------------------------------------
# Weighted pathfinding (shared A* core)
# ---------------------------------------------------------------------------


## A* shortest-path over an element graph.
##
## [param start] is the start element index.
## [param goal] is the goal element index.
## [param neighbors_fn] returns an [Array[int]] of neighbour element indices.
## [param cost_fn] returns the traversal cost from [param from_idx] to [param to_idx].
## [param heuristic_fn] returns an admissible estimate of the remaining cost
## from element [param idx] to the goal.
##
## Returns an [Array[int]] path from [param start] to [param goal]
## (inclusive), or an empty array if no path exists.
static func _astar(
		start: int,
		goal: int,
		neighbors_fn: Callable,
		cost_fn: Callable,
		heuristic_fn: Callable,
) -> Array[int]:
	if start == goal:
		return [start]
	var dist: Dictionary = {}
	dist[start] = 0.0
	var parent: Dictionary = {}
	parent[start] = -1
	# open items: [f_score, h_score, element]
	# h-score tie-breaking: when two nodes have equal f, prefer lower h
	# (closer to goal) for more consistent path choices regardless of direction.
	var start_h: float = heuristic_fn.call(start)
	var open: Array = [[start_h, start_h, start]]
	var visited: Dictionary = {}
	var do_log: bool = _DEBUG_SCRIPT.enabled
	if do_log:
		print("[GoBuild] A* start=%d goal=%d h_start=%.4f" % [start, goal, start_h])
	while not open.is_empty():
		var best_idx: int = 0
		var best_f: float = open[0][0]
		var best_h: float = open[0][1]
		for i: int in range(1, open.size()):
			if open[i][0] < best_f or (open[i][0] == best_f and open[i][1] < best_h):
				best_f = open[i][0]
				best_h = open[i][1]
				best_idx = i
		var cur: int = int(open[best_idx][2])
		open.pop_at(best_idx)
		if visited.has(cur):
			continue
		visited[cur] = true
		if cur == goal:
			break
		var cur_dist: float = dist[cur]
		var neighbors: Array[int] = neighbors_fn.call(cur)
		for nb: int in neighbors:
			if visited.has(nb):
				continue
			var step_cost: float = cost_fn.call(cur, nb)
			var new_dist: float = cur_dist + step_cost
			if not dist.has(nb) or new_dist < dist[nb]:
				dist[nb] = new_dist
				parent[nb] = cur
				var nb_h: float = heuristic_fn.call(nb)
				var f: float = new_dist + nb_h
				open.append([f, nb_h, nb])
				if do_log:
					print("  %d → %d  step=%.4f new_dist=%.4f h=%.4f f=%.4f" % [
						cur, nb, step_cost, new_dist, nb_h, f])
	if not parent.has(goal):
		if do_log:
			print("[GoBuild] A* NO PATH from %d to %d" % [start, goal])
		return []
	var path: Array[int] = []
	var cur_p: int = goal
	while cur_p != -1:
		path.append(cur_p)
		cur_p = int(parent[cur_p])
	path.reverse()
	if do_log:
		print("[GoBuild] A* path length=%d total_dist=%.4f" % [path.size(), dist[goal]])
	return path

# ---------------------------------------------------------------------------
# Face path (shortest weighted path between two faces)
# ---------------------------------------------------------------------------

## Find the shortest weighted path of face indices from [param face_a] to [param face_b].
##
## Uses A* with face-center distance as heuristic.  The cost function penalises
## normal deviation between adjacent faces, so paths prefer coplanar surfaces.
## The heuristic guides the search toward the goal, producing direct paths
## rather than BFS-style expansion that might explore unrelated faces first.
##
## Returns an [Array[int]] of face indices in path order, or an empty array
## if no path exists (disconnected mesh regions).
static func face_path(mesh: GoBuildMesh, face_a: int, face_b: int) -> Array[int]:
	if mesh.faces.is_empty():
		return []
	if face_a < 0 or face_a >= mesh.faces.size() \
			or face_b < 0 or face_b >= mesh.faces.size():
		return []
	if face_a == face_b:
		return [face_a]
	var goal_center: Vector3 = _face_center(mesh, face_b)
	var neighbors_fn: Callable = func(fi: int) -> Array[int]:
		return _adjacent_faces(mesh, fi)
	var cost_fn: Callable = func(from_fi: int, to_fi: int) -> float:
		return _face_edge_cost(mesh, from_fi, to_fi)
	var heuristic_fn: Callable = func(fi: int) -> float:
		return _face_center(mesh, fi).distance_to(goal_center)
	return _astar(face_a, face_b, neighbors_fn, cost_fn, heuristic_fn)


## Return the center point of face [param fi].
static func _face_center(mesh: GoBuildMesh, fi: int) -> Vector3:
	var face: GoBuildFace = mesh.faces[fi]
	var center := Vector3.ZERO
	for vi: int in face.vertex_indices:
		center += mesh.vertices[vi]
	return center / float(face.vertex_indices.size())


## Cost to traverse from face [param from_fi] to face [param to_fi].
##
## Pure geometric distance between face centres.  No normal-deviation penalty:
## on a curved surface like a sphere, the user expects "shortest path" to mean
## the geodesic shortest route, not a detour through coplanar faces.
static func _face_edge_cost(mesh: GoBuildMesh, from_fi: int, to_fi: int) -> float:
	return _face_center(mesh, from_fi).distance_to(_face_center(mesh, to_fi))


## Return face indices adjacent to [param fi] (faces sharing an edge).
static func _adjacent_faces(mesh: GoBuildMesh, fi: int) -> Array[int]:
	var result_set: Dictionary = {}
	var face_edges: Array = mesh.edges_of_face(fi)
	for ei: int in face_edges:
		var ed: GoBuildEdge = mesh.edges[ei]
		for adj_fi: int in ed.face_indices:
			if adj_fi != fi:
				result_set[adj_fi] = true
	var result: Array[int] = []
	for adj_fi: int in result_set:
		result.append(adj_fi)
	return result


# ---------------------------------------------------------------------------
# Edge path (shortest weighted path between two edges)
# ---------------------------------------------------------------------------

## Find the shortest weighted path of edge indices from [param edge_a] to [param edge_b].
##
## Uses A* with Euclidean distance as heuristic.  The cost function penalises
## normal deviation between adjacent faces (preferring coplanar surfaces) and
## vertex-only connections (no shared face).  The heuristic guides the search
## toward the goal, producing direct paths rather than BFS-style breadth-first
## expansion.
##
## Returns an [Array[int]] of edge indices in path order, or an empty array
## if no path exists.
static func edge_path(mesh: GoBuildMesh, edge_a: int, edge_b: int) -> Array[int]:
	if mesh.edges.is_empty():
		return []
	if edge_a < 0 or edge_a >= mesh.edges.size() \
			or edge_b < 0 or edge_b >= mesh.edges.size():
		return []
	if edge_a == edge_b:
		return [edge_a]
	var goal_ed: GoBuildEdge = mesh.edges[edge_b]
	var goal_va: Vector3 = mesh.vertices[goal_ed.vertex_a]
	var goal_vb: Vector3 = mesh.vertices[goal_ed.vertex_b]
	var goal_center: Vector3 = (goal_va + goal_vb) * 0.5
	var neighbors_fn: Callable = func(ei: int) -> Array[int]:
		return _adjacent_edges(mesh, ei)
	var cost_fn: Callable = func(from_ei: int, to_ei: int) -> float:
		return _edge_step_cost(mesh, from_ei, to_ei)
	var heuristic_fn: Callable = func(ei: int) -> float:
		var ed: GoBuildEdge = mesh.edges[ei]
		var center: Vector3 = (mesh.vertices[ed.vertex_a] + mesh.vertices[ed.vertex_b]) * 0.5
		return center.distance_to(goal_center)
	var path: Array[int] = _astar(edge_a, edge_b, neighbors_fn, cost_fn, heuristic_fn)
	if _DEBUG_SCRIPT.enabled:
		var log_parts: PackedStringArray = []
		log_parts.append("[GoBuild] edge_path %d → %d: [%d edges]" % [edge_a, edge_b, path.size()])
		for i: int in path.size():
			var ei: int = path[i]
			var ed: GoBuildEdge = mesh.edges[ei]
			var va: Vector3 = mesh.vertices[ed.vertex_a]
			var vb: Vector3 = mesh.vertices[ed.vertex_b]
			var mid: Vector3 = (va + vb) * 0.5
			log_parts.append("  %d: ei=%d  va=%d vb=%d  mid=(%.2f,%.2f,%.2f)  faces=%s" % [
				i, ei, ed.vertex_a, ed.vertex_b,
				mid.x, mid.y, mid.z,
				str(ed.face_indices)])
			if i > 0:
				var prev_ei: int = path[i - 1]
				var prev_ed: GoBuildEdge = mesh.edges[prev_ei]
				var shares_face: bool = false
				for fi: int in prev_ed.face_indices:
					if fi in ed.face_indices:
						shares_face = true
						break
				var from_center: Vector3 = \
					(mesh.vertices[prev_ed.vertex_a] + mesh.vertices[prev_ed.vertex_b]) * 0.5
				var dist: float = from_center.distance_to(mid)
				log_parts.append("    dist=%.4f  shares_face=%s" % [dist, str(shares_face)])
		print("\n".join(log_parts))
	return path


## Return edge indices adjacent to [param ei] (edges sharing a vertex).
static func _adjacent_edges(mesh: GoBuildMesh, ei: int) -> Array[int]:
	var ed: GoBuildEdge = mesh.edges[ei]
	var result_set: Dictionary = {}
	for vi: int in [ed.vertex_a, ed.vertex_b]:
		var vertex_edges: Array = mesh.edges_of_vertex(vi)
		for adj_ei: int in vertex_edges:
			if adj_ei != ei:
				result_set[adj_ei] = true
	var result: Array[int] = []
	for adj_ei: int in result_set:
		result.append(adj_ei)
	return result


## Cost to step from edge [param from_ei] to adjacent edge [param to_ei].
##
## Pure Euclidean distance between edge midpoints.  Previous versions added a
## vertex-only penalty for edges sharing no face, but this caused paths to take
## detours through face-sharing edges that were geometrically longer than the
## direct route.  Pure geometric distance matches Blender's "shortest path"
## behaviour.
static func _edge_step_cost(mesh: GoBuildMesh, from_ei: int, to_ei: int) -> float:
	var from_ed: GoBuildEdge = mesh.edges[from_ei]
	var to_ed: GoBuildEdge = mesh.edges[to_ei]
	var from_center: Vector3 = \
			(mesh.vertices[from_ed.vertex_a] + mesh.vertices[from_ed.vertex_b]) * 0.5
	var to_center: Vector3 = \
			(mesh.vertices[to_ed.vertex_a] + mesh.vertices[to_ed.vertex_b]) * 0.5
	return from_center.distance_to(to_center)



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


## Remove faces from [param indices] that have at least one edge on the boundary
## of the selection (i.e., an edge that either borders an unselected face or is a
## mesh boundary edge with only one adjacent face).  Keeps only interior faces
## whose every edge is shared with another selected face.
static func shrink_faces(mesh: GoBuildMesh, indices: Array[int]) -> Array[int]:
	if indices.is_empty() or mesh.edges.is_empty():
		return []
	var selected_set: Dictionary = {}
	for fi: int in indices:
		selected_set[fi] = true
	var result: Array[int] = []
	for fi: int in indices:
		var all_shared_and_selected: bool = true
		var edge_indices: Array = mesh._face_to_edges[fi] as Array
		if edge_indices == null:
			continue
		for ei: int in edge_indices:
			var ed: GoBuildEdge = mesh.edges[ei]
			# A face survives only if every edge is shared with another
			# selected face.  Boundary edges (single adjacent face) mean
			# the face is on the mesh boundary and should be removed.
			if ed.face_indices.size() < 2:
				all_shared_and_selected = false
				break
			for adj_fi: int in ed.face_indices:
				if not selected_set.has(adj_fi):
					all_shared_and_selected = false
					break
			if not all_shared_and_selected:
				break
		if all_shared_and_selected:
			result.append(fi)
	return result


# ---------------------------------------------------------------------------
# Loop selection
# ---------------------------------------------------------------------------

## Walk an edge loop starting from [param seed_edge].
##
## An edge loop selects a chain of connected edges that run in the same
## direction as the seed.  At each shared vertex the walk continues "straight
## through" by picking the edge opposite to the arriving edge in the vertex's
## edge pair.  For a valence-4 interior vertex, this means picking the edge
## that does NOT belong to either of the arriving edge's faces.
##
## The loop terminates at boundary vertices (valence != 4) where no opposite
## edge exists, at non-quad faces, or when the loop closes on itself.
##
## Returns an array of edge indices forming the loop, starting from
## [param seed_edge].  A closed loop will not repeat the seed.
static func edge_loop(mesh: GoBuildMesh, seed_edge: int) -> Array[int]:
	if mesh.edges.is_empty() or seed_edge < 0 or seed_edge >= mesh.edges.size():
		return []
	# First, try the standard quad-topology loop (opposite-edge walk).
	var topo_result: Array[int] = _topology_edge_loop(mesh, seed_edge)
	if topo_result.size() > 1:
		return topo_result
	# Topology loop returned only the seed — the quad walk couldn't continue.
	# If the seed is a boundary edge (1 face), fall back to a boundary loop
	# that walks connected boundary edges in both directions.
	var seed_ed: GoBuildEdge = mesh.edges[seed_edge]
	if seed_ed.face_indices.size() == 1:
		return _boundary_edge_loop(mesh, seed_edge)
	# Interior edge with no topology continuation — just the seed.
	return topo_result


## Return all loop/ring selections for [param seed_edge], in order of
## preference: topology loop, boundary loop, ring.  Used by the input
## controller to cycle through options when the user Alt+Clicks the
## same edge repeatedly.
##
## Each entry is a Dictionary with "type" (String) and "edges" (Array[int]).
static func edge_loop_options(mesh: GoBuildMesh, seed_edge: int) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	# 1. Topology loop (opposite-edge walk through quads).
	var topo: Array[int] = _topology_edge_loop(mesh, seed_edge)
	if topo.size() > 1:
		options.append({"type": "loop", "edges": topo})
	# 2. Boundary loop (walk boundary edges, only for boundary edges).
	var seed_ed: GoBuildEdge = mesh.edges[seed_edge]
	if seed_ed.face_indices.size() == 1:
		var boundary: Array[int] = _boundary_edge_loop(mesh, seed_edge)
		if boundary.size() > 1:
			# Avoid duplicating the topology loop result.
			if options.is_empty() or boundary != topo:
				options.append({"type": "boundary", "edges": boundary})
	# 3. Ring (opposite-edge-in-quad walk).
	var ring: Array[int] = edge_ring(mesh, seed_edge)
	if ring.size() > 1:
		options.append({"type": "ring", "edges": ring})
	# If no options found, return just the seed edge.
	if options.is_empty():
		options.append({"type": "single", "edges": [seed_edge]})
	return options


## Quad-topology edge loop: walks "opposite edge at vertex" through
## valence-4 interior vertices.  Terminates at corners, poles, and boundaries.
static func _topology_edge_loop(mesh: GoBuildMesh, seed_edge: int) -> Array[int]:
	var result: Array[int] = []
	var visited: Dictionary = {}
	var seed_ed: GoBuildEdge = mesh.edges[seed_edge]
	result.append(seed_edge)
	visited[seed_edge] = true
	for direction: int in 2:
		var start_vi: int = seed_ed.vertex_a if direction == 0 else seed_ed.vertex_b
		var end_vi: int = seed_ed.vertex_b if direction == 0 else seed_ed.vertex_a
		var walk_dir: Vector3 = mesh.vertices[end_vi] - mesh.vertices[start_vi]
		var momentum_dir: Vector3 = walk_dir
		var next_ei: int = _loop_opposite_edge_at_vertex(mesh, seed_edge, end_vi, walk_dir, momentum_dir)
		if next_ei == -1 or visited.has(next_ei):
			continue
		var cur_ei: int = next_ei
		var prev_ei: int = seed_edge
		while cur_ei != -1 and not visited.has(cur_ei):
			visited[cur_ei] = true
			if direction == 0:
				result.append(cur_ei)
			else:
				result.insert(0, cur_ei)
			var cur_ed: GoBuildEdge = mesh.edges[cur_ei]
			var prev_ed: GoBuildEdge = mesh.edges[prev_ei]
			var arrive_vi: int = cur_ed.vertex_a \
					if (prev_ed.vertex_a == cur_ed.vertex_a or prev_ed.vertex_b == cur_ed.vertex_a) \
					else cur_ed.vertex_b
			var continue_vi: int = cur_ed.vertex_b if arrive_vi == cur_ed.vertex_a else cur_ed.vertex_a
			walk_dir = mesh.vertices[continue_vi] - mesh.vertices[arrive_vi]
			var prev_far_vi: int = prev_ed.vertex_a \
					if prev_ed.vertex_a != arrive_vi else prev_ed.vertex_b
			var prev_dir: Vector3 = (mesh.vertices[arrive_vi] - mesh.vertices[prev_far_vi])
			momentum_dir = (walk_dir + prev_dir)
			if momentum_dir.length_squared() < 0.0001:
				momentum_dir = walk_dir
			var opp_ei: int = _loop_opposite_edge_at_vertex(
					mesh, cur_ei, continue_vi, walk_dir, momentum_dir)
			prev_ei = cur_ei
			cur_ei = opp_ei
	return result


## Boundary edge loop: walks connected boundary edges (edges with exactly
## 1 adjacent face) from [param seed_edge] in both directions.
##
## At each vertex, picks the next boundary edge that (1) shares a face with
## the current edge, and (2) is most aligned with the walk direction.  If
## no face-sharing candidate exists, falls back to alignment alone.  This
## keeps the loop walking along the same face's boundary rather than
## jumping to an unrelated face at T-junctions.
static func _boundary_edge_loop(mesh: GoBuildMesh, seed_edge: int) -> Array[int]:
	var result: Array[int] = []
	var visited: Dictionary = {}
	var seed_ed: GoBuildEdge = mesh.edges[seed_edge]
	result.append(seed_edge)
	visited[seed_edge] = true
	for direction: int in 2:
		var start_vi: int = seed_ed.vertex_a if direction == 0 else seed_ed.vertex_b
		var end_vi: int = seed_ed.vertex_b if direction == 0 else seed_ed.vertex_a
		var walk_dir: Vector3 = mesh.vertices[end_vi] - mesh.vertices[start_vi]
		var cur_ei: int = seed_edge
		var cur_vi: int = end_vi
		while true:
			var cur_ed: GoBuildEdge = mesh.edges[cur_ei]
			var cur_faces: Array = cur_ed.face_indices
			var candidates: Array[int] = []
			var face_candidates: Array[int] = []
			var vertex_edges: Array = mesh.edges_of_vertex(cur_vi)
			for cand_ei: int in vertex_edges:
				if cand_ei == cur_ei:
					continue
				if visited.has(cand_ei):
					continue
				var cand_ed: GoBuildEdge = mesh.edges[cand_ei]
				if cand_ed.face_indices.size() != 1:
					continue
				candidates.append(cand_ei)
				# Check if this candidate shares a face with the current edge.
				for fi: int in cand_ed.face_indices:
					if cur_faces.has(fi):
						face_candidates.append(cand_ei)
						break
			# Prefer face-sharing candidates first; fall back to all candidates.
			var pool: Array[int] = face_candidates if not face_candidates.is_empty() else candidates
			if pool.is_empty():
				break
			# Pick the boundary edge most aligned with walk direction.
			var best_ei: int = -1
			var best_dot: float = -2.0
			var cur_pos: Vector3 = mesh.vertices[cur_vi]
			var walk_norm: Vector3 = walk_dir.normalized()
			for cand_ei: int in pool:
				var cand_ed: GoBuildEdge = mesh.edges[cand_ei]
				var other_vi: int = cand_ed.vertex_a \
						if cand_ed.vertex_a != cur_vi else cand_ed.vertex_b
				var cand_dir: Vector3 = (mesh.vertices[other_vi] - cur_pos).normalized()
				var dot: float = cand_dir.dot(walk_norm)
				if dot > best_dot:
					best_dot = dot
					best_ei = cand_ei
			if best_ei == -1:
				break
			visited[best_ei] = true
			if direction == 0:
				result.append(best_ei)
			else:
				result.insert(0, best_ei)
			var best_ed: GoBuildEdge = mesh.edges[best_ei]
			var next_vi: int = best_ed.vertex_a \
					if best_ed.vertex_a != cur_vi else best_ed.vertex_b
			walk_dir = mesh.vertices[next_vi] - cur_pos
			cur_ei = best_ei
			cur_vi = next_vi
	return result


## Find the edge at [param vi] that is "opposite" to [param ei] in the
## vertex's edge pairing.  For a valence-4 interior vertex, this is the
## edge that does NOT share either of [param ei]'s faces.
##
## When multiple opposite candidates exist (high-valence vertices), disam-
## biguation uses [param momentum_dir] rather than [param walk_dir] alone.
## [param momentum_dir] is the sum of the current walk direction and the
## previous edge direction, smoothed through 90-degree corners.  Candidates
## aligned with the momentum are preferred over those aligned with the raw
## walk direction, which has already turned at corners.
##
## Returns -1 if no opposite edge is found (boundary vertex, T-junction,
## pole, etc.) — the loop walk terminates at such vertices.
static func _loop_opposite_edge_at_vertex(
		mesh: GoBuildMesh,
		ei: int,
		vi: int,
		walk_dir: Vector3,
		momentum_dir: Vector3) -> int:
	var ed: GoBuildEdge = mesh.edges[ei]
	var edge_faces: Array = ed.face_indices
	var vertex_edges: Array = mesh.edges_of_vertex(vi)
	var candidates: Array[int] = []
	for candidate_ei: int in vertex_edges:
		if candidate_ei == ei:
			continue
		var cand_ed: GoBuildEdge = mesh.edges[candidate_ei]
		var shares_face: bool = false
		for fi: int in cand_ed.face_indices:
			if edge_faces.has(fi):
				shares_face = true
				break
		if not shares_face:
			candidates.append(candidate_ei)
	if candidates.is_empty():
		return -1
	if candidates.size() == 1:
		return candidates[0]
	# Multiple opposite candidates — disambiguate using momentum.
	# Momentum bisects the turn at corners so the continuation that
	# keeps the loop going around the mesh is preferred.
	var score_dir: Vector3
	if momentum_dir.length_squared() > 0.0001:
		score_dir = momentum_dir.normalized()
	elif walk_dir.length_squared() > 0.0001:
		score_dir = walk_dir.normalized()
	else:
		return candidates[0]
	var vi_pos: Vector3 = mesh.vertices[vi]
	var best_ei: int = candidates[0]
	var best_dot: float = -2.0
	for candidate_ei: int in candidates:
		var cand_ed: GoBuildEdge = mesh.edges[candidate_ei]
		var other_vi: int = cand_ed.vertex_a if cand_ed.vertex_a != vi else cand_ed.vertex_b
		var other_pos: Vector3 = mesh.vertices[other_vi]
		var cand_dir: Vector3 = (other_pos - vi_pos).normalized()
		var dot: float = cand_dir.dot(score_dir)
		if dot > best_dot:
			best_dot = dot
			best_ei = candidate_ei
	return best_ei


# ---------------------------------------------------------------------------
# Ring selection
# ---------------------------------------------------------------------------

## Walk an edge ring starting from [param seed_edge].
##
## An edge ring selects edges that run parallel to the seed edge across the
## perpendicular strip of quads.  Unlike a loop (which follows connected
## edges through shared vertices), a ring steps to the opposite edge in
## each quad, producing a series of non-connected but parallel edges.
##
## The walk uses vertex tracking to maintain direction consistency,
## following the same pattern as [code]LoopCutOperation._walk_half[/code].
## Each of the seed edge's faces starts one half of the walk; the two
## halves are combined to form the complete ring.
##
## Returns an array of edge indices forming the ring, starting from
## [param seed_edge].  A closed ring will not repeat the seed.
static func edge_ring(mesh: GoBuildMesh, seed_edge: int) -> Array[int]:
	if mesh.edges.is_empty() or seed_edge < 0 or seed_edge >= mesh.edges.size():
		return []
	var result: Array[int] = []
	var visited: Dictionary = {}
	var seed_ed: GoBuildEdge = mesh.edges[seed_edge]
	result.append(seed_edge)
	visited[seed_edge] = true
	# Walk in both directions.  Each direction starts from one of the
	# seed's faces and walks to the opposite edge, then continues.
	# Direction 0 walks from face[0] using va→vb ordering.
	# Direction 1 walks from face[1] using vb→va ordering.
	for direction: int in 2:
		if seed_ed.face_indices.size() <= direction:
			break
		var start_fi: int = seed_ed.face_indices[direction]
		var va: int = seed_ed.vertex_a if direction == 0 else seed_ed.vertex_b
		var vb: int = seed_ed.vertex_b if direction == 0 else seed_ed.vertex_a
		# Enter the start face and find the far (opposite) edge.
		var face: GoBuildFace = mesh.faces[start_fi]
		if face.vertex_indices.size() != 4:
			continue
		var vis: Array[int] = face.vertex_indices
		var pos_a: int = -1
		for k: int in 4:
			if vis[k] == va:
				var next_k: int = (k + 1) % 4
				if vis[next_k] == vb:
					pos_a = k
					break
				var prev_k: int = (k + 3) % 4
				if vis[prev_k] == vb:
					pos_a = k
					break
		if pos_a == -1:
			continue
		var next_a: int = (pos_a + 1) % 4
		var forward: bool = vis[next_a] == vb
		var opp_va: int
		var opp_vb: int
		if forward:
			opp_va = vis[(pos_a + 3) % 4]
			opp_vb = vis[(pos_a + 2) % 4]
		else:
			opp_va = vis[(pos_a + 1) % 4]
			opp_vb = vis[(pos_a + 2) % 4]
		var opp_ei: int = mesh.find_edge(opp_va, opp_vb)
		if opp_ei == -1:
			continue
		var opp_ed: GoBuildEdge = mesh.edges[opp_ei]
		var next_fi: int = -1
		for fi: int in opp_ed.face_indices:
			if fi != start_fi:
				next_fi = fi
				break
		# Continue walking from the far edge onward.
		var cur_ei: int = opp_ei
		var cur_va: int = opp_va
		var cur_vb: int = opp_vb
		var cur_fi: int = next_fi
		while cur_ei != -1 and not visited.has(cur_ei):
			visited[cur_ei] = true
			if direction == 0:
				result.append(cur_ei)
			else:
				result.insert(0, cur_ei)
			if cur_fi == -1:
				break
			var cface: GoBuildFace = mesh.faces[cur_fi]
			if cface.vertex_indices.size() != 4:
				break
			vis = cface.vertex_indices
			pos_a = -1
			for k: int in 4:
				if vis[k] == cur_va:
					var nk: int = (k + 1) % 4
					if vis[nk] == cur_vb:
						pos_a = k
						break
					var pk: int = (k + 3) % 4
					if vis[pk] == cur_vb:
						pos_a = k
						break
			if pos_a == -1:
				break
			next_a = (pos_a + 1) % 4
			forward = vis[next_a] == cur_vb
			if forward:
				opp_va = vis[(pos_a + 3) % 4]
				opp_vb = vis[(pos_a + 2) % 4]
			else:
				opp_va = vis[(pos_a + 1) % 4]
				opp_vb = vis[(pos_a + 2) % 4]
			opp_ei = mesh.find_edge(opp_va, opp_vb)
			if opp_ei == -1:
				break
			opp_ed = mesh.edges[opp_ei]
			next_fi = -1
			for fi: int in opp_ed.face_indices:
				if fi != cur_fi:
					next_fi = fi
					break
			cur_ei = opp_ei
			cur_va = opp_va
			cur_vb = opp_vb
			cur_fi = next_fi
	return result


## Return a strip of faces along the loop direction, starting from the face
## containing the seed edge on the given side.
##
## Unlike the edge loop which returns all edges in the chain, [method face_loop]
## returns only the faces on ONE side of the loop.  Which side is determined by
## [param side_face]: the index of a face sharing the seed edge — the strip
## walks along that face and its successors.  Pass [code]-1[/code] to use the
## seed edge's first face (face_indices[0]).
##
## On a 3x3 grid, edge_loop(e1) returns 3 vertical edges.
## face_loop(e1, f0) returns [f0, f3, f6] — the left column.
## face_loop(e1, f1) returns [f1, f4, f7] — the right column.
static func face_loop(mesh: GoBuildMesh, seed_edge: int, side_face: int = -1) -> Array[int]:
	if mesh.edges.is_empty() or seed_edge < 0 or seed_edge >= mesh.edges.size():
		return []
	var seed_ed: GoBuildEdge = mesh.edges[seed_edge]
	# Determine which side face to start from.
	var start_fi: int = side_face
	if start_fi == -1:
		if seed_ed.face_indices.is_empty():
			return []
		start_fi = seed_ed.face_indices[0]
	# Validate that start_fi shares the seed edge.
	var face_found: bool = false
	for fi: int in seed_ed.face_indices:
		if fi == start_fi:
			face_found = true
			break
	if not face_found:
		return []
	var va: int = seed_ed.vertex_a
	var vb: int = seed_ed.vertex_b
	# Walk the face strip from start_fi along va→vb direction.
	# Each step: find the opposite edge in the current face, step to the
	# face on the other side of that edge, and continue.
	var result: Array[int] = []
	var visited: Dictionary = {}
	var cur_fi: int = start_fi
	while cur_fi != -1 and not visited.has(cur_fi):
		visited[cur_fi] = true
		result.append(cur_fi)
		var face: GoBuildFace = mesh.faces[cur_fi]
		if face.vertex_indices.size() != 4:
			break
		var vis: Array[int] = face.vertex_indices
		var pos_a: int = -1
		for k: int in 4:
			if vis[k] == va:
				var next_k: int = (k + 1) % 4
				if vis[next_k] == vb:
					pos_a = k
					break
				var prev_k: int = (k + 3) % 4
				if vis[prev_k] == vb:
					pos_a = k
					break
		if pos_a == -1:
			break
		var next_a: int = (pos_a + 1) % 4
		var forward: bool = vis[next_a] == vb
		var opp_va: int
		var opp_vb: int
		if forward:
			opp_va = vis[(pos_a + 3) % 4]
			opp_vb = vis[(pos_a + 2) % 4]
		else:
			opp_va = vis[(pos_a + 1) % 4]
			opp_vb = vis[(pos_a + 2) % 4]
		var opp_ei: int = mesh.find_edge(opp_va, opp_vb)
		if opp_ei == -1:
			break
		var opp_ed: GoBuildEdge = mesh.edges[opp_ei]
		var next_fi: int = -1
		for fi: int in opp_ed.face_indices:
			if fi != cur_fi:
				next_fi = fi
				break
		cur_fi = next_fi
		va = opp_va
		vb = opp_vb
	return result


## Return the faces in the ring direction — the quads that form the strip
## perpendicular to the seed edge.
##
## [param side_face] determines which side of the ring to follow (pass [code]-1[/code]
## to use the seed edge's first face).  When both sides produce distinct strips,
## only the strip on the chosen side is returned.
static func face_ring(mesh: GoBuildMesh, seed_edge: int, side_face: int = -1) -> Array[int]:
	var ring_edges: Array[int] = edge_ring(mesh, seed_edge)
	var seed_ed: GoBuildEdge = mesh.edges[seed_edge]
	var side_fi: int = side_face
	if side_fi == -1:
		if seed_ed.face_indices.is_empty():
			return []
		side_fi = seed_ed.face_indices[0]
	var result_set: Dictionary = {}
	for ei: int in ring_edges:
		for fi: int in mesh.edges[ei].face_indices:
			if mesh.faces[fi].vertex_indices.size() == 4:
				result_set[fi] = true
	var result: Array[int] = []
	for fi: int in result_set:
		result.append(fi)
	return result


# ---------------------------------------------------------------------------
# Select Similar
# ---------------------------------------------------------------------------

## Select all faces that are similar to the currently selected faces
## according to [param criterion].
##
## Returns all face indices matching the criterion value(s) found in the
## seed selection. The result always includes the seed faces themselves.
static func similar_faces(
		mesh: GoBuildMesh,
		seed_indices: Array[int],
		criterion: int,
) -> Array[int]:
	if seed_indices.is_empty() or mesh.faces.is_empty():
		return []
	# Collect reference values from seed faces.
	# MATERIAL and SIDE_COUNT use exact-match dictionaries for O(1) lookup.
	# NORMAL, COPLANAR, and AREA use threshold-based fuzzy matching,
	# which requires comparing each face against all reference values.
	var ref_values: Dictionary = {}
	var ref_normals: Array[Vector3] = []
	var ref_planes: Array[Vector4] = []  # (nx, ny, nz, d)
	var ref_areas: Array[float] = []
	match criterion:
		FaceSimilarCriterion.MATERIAL:
			for fi: int in seed_indices:
				ref_values[mesh.faces[fi].material_index] = true
		FaceSimilarCriterion.SIDE_COUNT:
			for fi: int in seed_indices:
				ref_values[mesh.faces[fi].vertex_indices.size()] = true
		FaceSimilarCriterion.NORMAL:
			for fi: int in seed_indices:
				var n: Vector3 = mesh.compute_face_normal(mesh.faces[fi])
				ref_normals.append(n.normalized())
		FaceSimilarCriterion.COPLANAR:
			for fi: int in seed_indices:
				var n: Vector3 = mesh.compute_face_normal(mesh.faces[fi]).normalized()
				var v0: Vector3 = mesh.vertices[mesh.faces[fi].vertex_indices[0]]
				var d: float = n.dot(v0)
				ref_planes.append(Vector4(n.x, n.y, n.z, d))
		FaceSimilarCriterion.AREA:
			for fi: int in seed_indices:
				ref_areas.append(mesh.compute_face_area(mesh.faces[fi]))
	# Scan all faces and collect matches.
	var result: Array[int] = []
	for fi: int in mesh.faces.size():
		var matches: bool = false
		match criterion:
			FaceSimilarCriterion.MATERIAL:
				matches = ref_values.has(mesh.faces[fi].material_index)
			FaceSimilarCriterion.SIDE_COUNT:
				matches = ref_values.has(mesh.faces[fi].vertex_indices.size())
			FaceSimilarCriterion.NORMAL:
				var n: Vector3 = mesh.compute_face_normal(mesh.faces[fi]).normalized()
				for ref_n: Vector3 in ref_normals:
					if n.dot(ref_n) > _NORMAL_DOT_THRESHOLD:
						matches = true
						break
			FaceSimilarCriterion.COPLANAR:
				var n: Vector3 = mesh.compute_face_normal(mesh.faces[fi]).normalized()
				var v0: Vector3 = mesh.vertices[mesh.faces[fi].vertex_indices[0]]
				var d: float = n.dot(v0)
				for ref_p: Vector4 in ref_planes:
					var ref_n: Vector3 = Vector3(ref_p.x, ref_p.y, ref_p.z)
					var ref_d: float = ref_p.w
					if n.dot(ref_n) > _NORMAL_DOT_THRESHOLD and absf(d - ref_d) < _COPLANAR_DIST_THRESHOLD:
						matches = true
						break
			FaceSimilarCriterion.AREA:
				var a: float = mesh.compute_face_area(mesh.faces[fi])
				for ref_a: float in ref_areas:
					var larger: float = maxf(a, ref_a)
					if larger > 0.0 and absf(a - ref_a) / larger < _AREA_RELATIVE_TOLERANCE:
						matches = true
						break
		if matches:
			result.append(fi)
	return result


## Select all edges that are similar to the currently selected edges
## according to [param criterion].
static func similar_edges(
		mesh: GoBuildMesh,
		seed_indices: Array[int],
		criterion: int,
) -> Array[int]:
	if seed_indices.is_empty() or mesh.edges.is_empty():
		return []
	var ref_values: Dictionary = {}
	var ref_lengths: Array[float] = []
	var ref_angles: Array[float] = []
	match criterion:
		EdgeSimilarCriterion.LENGTH:
			for ei: int in seed_indices:
				var ed: GoBuildEdge = mesh.edges[ei]
				var length: float = (mesh.vertices[ed.vertex_b] - mesh.vertices[ed.vertex_a]).length()
				ref_lengths.append(length)
		EdgeSimilarCriterion.FACE_COUNT:
			for ei: int in seed_indices:
				ref_values[mesh.edges[ei].face_indices.size()] = true
		EdgeSimilarCriterion.DIHEDRAL:
			for ei: int in seed_indices:
				ref_angles.append(_compute_dihedral_angle(mesh, ei))
	# Scan all edges and collect matches.
	var result: Array[int] = []
	for ei: int in mesh.edges.size():
		var matches: bool = false
		match criterion:
			EdgeSimilarCriterion.LENGTH:
				var ed: GoBuildEdge = mesh.edges[ei]
				var length: float = (mesh.vertices[ed.vertex_b] - mesh.vertices[ed.vertex_a]).length()
				for ref_l: float in ref_lengths:
					var larger: float = maxf(length, ref_l)
					if larger > 0.0 and absf(length - ref_l) / larger < _LENGTH_RELATIVE_TOLERANCE:
						matches = true
						break
			EdgeSimilarCriterion.FACE_COUNT:
				matches = ref_values.has(mesh.edges[ei].face_indices.size())
			EdgeSimilarCriterion.DIHEDRAL:
				var angle: float = _compute_dihedral_angle(mesh, ei)
				for ref_a: float in ref_angles:
					if absf(angle - ref_a) < _DIHEDRAL_ANGLE_TOLERANCE:
						matches = true
						break
		if matches:
			result.append(ei)
	return result


## Select all vertices that are similar to the currently selected vertices
## according to [param criterion].
static func similar_vertices(
		mesh: GoBuildMesh,
		seed_indices: Array[int],
		criterion: int,
) -> Array[int]:
	if seed_indices.is_empty() or mesh.vertices.is_empty():
		return []
	var ref_values: Dictionary = {}
	match criterion:
		VertexSimilarCriterion.VALENCE:
			for vi: int in seed_indices:
				ref_values[mesh.vertex_valence(vi)] = true
	# Scan all vertices and collect matches.
	var result: Array[int] = []
	for vi: int in mesh.vertices.size():
		var matches: bool = false
		match criterion:
			VertexSimilarCriterion.VALENCE:
				matches = ref_values.has(mesh.vertex_valence(vi))
		if matches:
			result.append(vi)
	return result


# ---------------------------------------------------------------------------
# Select Similar — internal helpers
# ---------------------------------------------------------------------------



## Compute the dihedral angle (in degrees) between the two faces sharing
## edge [param ei]. Returns 180.0 for boundary edges (single face).
static func _compute_dihedral_angle(mesh: GoBuildMesh, ei: int) -> float:
	var ed: GoBuildEdge = mesh.edges[ei]
	if ed.face_indices.size() < 2:
		return 180.0
	var f0: GoBuildFace = mesh.faces[ed.face_indices[0]]
	var f1: GoBuildFace = mesh.faces[ed.face_indices[1]]
	var n0: Vector3 = mesh.compute_face_normal(f0)
	var n1: Vector3 = mesh.compute_face_normal(f1)
	var cosine: float = n0.dot(n1)
	# Clamp to avoid NaN from acos.
	cosine = clampf(cosine, -1.0, 1.0)
	var angle_rad: float = acos(cosine)
	return rad_to_deg(angle_rad)
