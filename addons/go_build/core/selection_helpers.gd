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

# Quantisation tolerances for Select Similar comparisons.
const _NORMAL_TOLERANCE: float = 0.0001
const _AREA_TOLERANCE: float = 0.001
const _LENGTH_TOLERANCE: float = 0.001
const _COPLANAR_DIST_TOLERANCE: float = 0.001
const _DIHEDRAL_TOLERANCE: float = 0.5


# ---------------------------------------------------------------------------
# Face path (shortest path between two faces)
# ---------------------------------------------------------------------------

## Find the shortest path of face indices from [param face_a] to [param face_b].
##
## Two faces are adjacent if they share an edge.  Uses BFS to find the
## shortest path through the face adjacency graph.  The result includes
## both [param face_a] and [param face_b].
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
	# BFS from face_a to face_b.
	# For each face, find adjacent faces (sharing an edge).
	var queue: Array[int] = [face_a]
	var visited: Dictionary = {}
	visited[face_a] = true
	var parent: Dictionary = {}
	parent[face_a] = -1
	while not queue.is_empty():
		var fi: int = queue.pop_front()
		if fi == face_b:
			break
		var adj: Array[int] = _adjacent_faces(mesh, fi)
		for adj_fi: int in adj:
			if not visited.has(adj_fi):
				visited[adj_fi] = true
				parent[adj_fi] = fi
				queue.append(adj_fi)
	if not parent.has(face_b):
		return []
	# Reconstruct path from face_b back to face_a.
	var path: Array[int] = []
	var cur: int = face_b
	while cur != -1:
		path.append(cur)
		cur = int(parent[cur])
	path.reverse()
	return path


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
	var result: Array[int] = []
	var visited: Dictionary = {}
	var seed_ed: GoBuildEdge = mesh.edges[seed_edge]
	result.append(seed_edge)
	visited[seed_edge] = true
	var seed_end: Vector3 = mesh.vertices[seed_ed.vertex_b]
	var seed_start: Vector3 = mesh.vertices[seed_ed.vertex_a]
	var seed_dir: Vector3 = (seed_end - seed_start).normalized()
	# Walk in two directions from the seed.
	# Direction 0 continues from vertex_a toward vertex_b.
	# Direction 1 continues from vertex_b toward vertex_a.
	# Each direction discovers its own loop plane from the first step.
	for direction: int in 2:
		var start_vi: int = seed_ed.vertex_a if direction == 0 else seed_ed.vertex_b
		var end_vi: int = seed_ed.vertex_b if direction == 0 else seed_ed.vertex_a
		var walk_dir: Vector3 = mesh.vertices[end_vi] - mesh.vertices[start_vi]
		# Find the first continuation to establish the loop plane.
		var first_ei: int = _loop_continuation_edge(
				mesh, seed_edge, end_vi, walk_dir, Vector3.ZERO, visited)
		if first_ei == -1 or visited.has(first_ei):
			continue
		# Derive the loop plane from seed_dir and the first step direction.
		var first_ed: GoBuildEdge = mesh.edges[first_ei]
		var first_other_vi: int = first_ed.vertex_a \
				if first_ed.vertex_a != end_vi else first_ed.vertex_b
		var first_step: Vector3 = mesh.vertices[first_other_vi] - mesh.vertices[end_vi]
		var plane_normal: Vector3 = seed_dir.cross(first_step.normalized())
		# If the cross product is near-zero (collinear), the seed edge and
		# first step lie on the same line — no meaningful plane.  Skip
		# plane-based scoring and use walk direction only.
		if plane_normal.length_squared() < 0.0001:
			plane_normal = Vector3.ZERO
		else:
			plane_normal = plane_normal.normalized()
		# Now walk, starting from the first continuation edge.
		var cur_ei: int = first_ei
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
			var opp_ei: int = _loop_continuation_edge(
					mesh, cur_ei, continue_vi, walk_dir, plane_normal, visited)
			prev_ei = cur_ei
			cur_ei = opp_ei
	return result


## Find the edge at [param vi] that continues the loop from [param ei].
##
## Uses a local walk direction ([param walk_dir]) to move forward, and a
## loop plane normal ([param plane_normal]) to prefer candidates that stay
## on the loop plane.  When [param plane_normal] is [Vector3.ZERO] (no
## meaningful plane could be derived from the seed + first step), scoring
## falls back to walk direction only.
##
## Returns -1 only when the vertex has no other edges at all.
static func _loop_continuation_edge(
		mesh: GoBuildMesh,
		ei: int,
		vi: int,
		walk_dir: Vector3,
		plane_normal: Vector3,
		visited: Dictionary) -> int:
	var vertex_edges: Array = mesh.edges_of_vertex(vi)
	var candidates: Array[int] = []
	for candidate_ei: int in vertex_edges:
		if candidate_ei == ei or visited.has(candidate_ei):
			continue
		candidates.append(candidate_ei)
	if candidates.is_empty():
		return -1
	if candidates.size() == 1:
		return candidates[0]
	var vi_pos: Vector3 = mesh.vertices[vi]
	var walk_norm: Vector3 = walk_dir.normalized()
	var has_plane: bool = plane_normal != Vector3.ZERO
	var best_ei: int = candidates[0]
	var best_score: float = -2.0
	for candidate_ei: int in candidates:
		var cand_ed: GoBuildEdge = mesh.edges[candidate_ei]
		var other_vi: int = cand_ed.vertex_a if cand_ed.vertex_a != vi else cand_ed.vertex_b
		var other_pos: Vector3 = mesh.vertices[other_vi]
		var cand_dir: Vector3 = (other_pos - vi_pos).normalized()
		var walk_dot: float = cand_dir.dot(walk_norm)
		# walk_dot must be positive (going forward).  Negative means
		# backtracking — heavily penalised.
		if walk_dot < 0.0:
			walk_dot = -1.0
		var score: float = walk_dot
		if has_plane:
			# Distance of the candidate's far vertex from the loop plane.
			# Vertices on the plane (small distance) are preferred.
			var plane_dist: float = absf((other_pos - vi_pos).dot(plane_normal))
			score -= plane_dist * 2.0
		if score > best_score:
			best_score = score
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
	# Collect the reference values from the seed faces.
	var ref_values: Dictionary = {}
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
				# Quantise normal to grid so near-identical normals match.
				var key: String = _quantise_normal(n)
				ref_values[key] = true
		FaceSimilarCriterion.COPLANAR:
			for fi: int in seed_indices:
				var n: Vector3 = mesh.compute_face_normal(mesh.faces[fi])
				# Plane equation: n·x = d. Use a vertex to find d.
				var v0: Vector3 = mesh.vertices[mesh.faces[fi].vertex_indices[0]]
				var d: float = n.dot(v0)
				var key: String = _quantise_normal(n) + "|" + str(roundf(d * 1000.0) / 1000.0)
				ref_values[key] = true
		FaceSimilarCriterion.AREA:
			for fi: int in seed_indices:
				var a: float = mesh.compute_face_area(mesh.faces[fi])
				ref_values[roundf(a * 1000.0) / 1000.0] = true
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
				var n: Vector3 = mesh.compute_face_normal(mesh.faces[fi])
				matches = ref_values.has(_quantise_normal(n))
			FaceSimilarCriterion.COPLANAR:
				var n: Vector3 = mesh.compute_face_normal(mesh.faces[fi])
				var v0: Vector3 = mesh.vertices[mesh.faces[fi].vertex_indices[0]]
				var d: float = n.dot(v0)
				var key: String = _quantise_normal(n) + "|" + str(roundf(d * 1000.0) / 1000.0)
				matches = ref_values.has(key)
			FaceSimilarCriterion.AREA:
				var a: float = mesh.compute_face_area(mesh.faces[fi])
				matches = ref_values.has(roundf(a * 1000.0) / 1000.0)
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
	match criterion:
		EdgeSimilarCriterion.LENGTH:
			for ei: int in seed_indices:
				var ed: GoBuildEdge = mesh.edges[ei]
				var length: float = (mesh.vertices[ed.vertex_b] - mesh.vertices[ed.vertex_a]).length()
				ref_values[roundf(length * 1000.0) / 1000.0] = true
		EdgeSimilarCriterion.FACE_COUNT:
			for ei: int in seed_indices:
				ref_values[mesh.edges[ei].face_indices.size()] = true
		EdgeSimilarCriterion.DIHEDRAL:
			for ei: int in seed_indices:
				var angle: float = _compute_dihedral_angle(mesh, ei)
				ref_values[roundf(angle * 10.0) / 10.0] = true
	# Scan all edges and collect matches.
	var result: Array[int] = []
	for ei: int in mesh.edges.size():
		var matches: bool = false
		match criterion:
			EdgeSimilarCriterion.LENGTH:
				var ed: GoBuildEdge = mesh.edges[ei]
				var length: float = (mesh.vertices[ed.vertex_b] - mesh.vertices[ed.vertex_a]).length()
				matches = ref_values.has(roundf(length * 1000.0) / 1000.0)
			EdgeSimilarCriterion.FACE_COUNT:
				matches = ref_values.has(mesh.edges[ei].face_indices.size())
			EdgeSimilarCriterion.DIHEDRAL:
				var angle: float = _compute_dihedral_angle(mesh, ei)
				matches = ref_values.has(roundf(angle * 10.0) / 10.0)
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


## Quantise a normal vector to a string key so near-identical normals match.
static func _quantise_normal(n: Vector3) -> String:
	return "%.4f,%.4f,%.4f" % [
		roundf(n.x * 10000.0) / 10000.0,
		roundf(n.y * 10000.0) / 10000.0,
		roundf(n.z * 10000.0) / 10000.0,
	]


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