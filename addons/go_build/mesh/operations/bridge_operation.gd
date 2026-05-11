## Bridge edge loop operation for [GoBuildMesh].
##
## Connects two open boundary edge loops with a quad strip.
##
## The two loops must each form a continuous chain of connected boundary
## edges (edges with exactly one adjacent face).  The operation walks each
## set of selected edges into an ordered vertex loop, aligns the two loops
## for best winding, then fills the gap with one quad per loop step.
##
## Loop ordering:
##   - Each set of selected boundary edges is walked into a vertex chain by
##     following the shared endpoint between consecutive edges in the set.
##   - The loops are not required to be closed (open chains produce an
##     open quad strip with no cap; closed loops produce a closed strip).
##   - If the two loops have different lengths the shorter loop is left-padded
##     or the last segment is stretched to the end of the longer loop.
##     [b]Loops of equal length produce one quad per step (recommended).[/b]
##
## Orientation:
##   The start of loop B is chosen to minimise the total bridging distance so
##   the quads do not cross.  The winding of B is also flipped if the
##   cross-product of the bridge direction and B's tangent points away from A,
##   so the outward normals of the new faces point outward consistently.
##
## [method GoBuildMesh.rebuild_edges] is called automatically inside
## [method apply].
@tool
class_name BridgeOperation
extends RefCounted

# Self-preloads — dependency order.
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _FILL_SCRIPT := preload("res://addons/go_build/mesh/operations/fill_operation.gd")


## Bridge two open boundary edge loops selected by [param edge_indices].
##
## [param edge_indices] should contain edges from exactly two distinct boundary
## loops.  If fewer than two distinct loops are found the operation is a no-op.
## [method GoBuildMesh.rebuild_edges] is called automatically on completion.
static func apply(mesh: GoBuildMesh, edge_indices: Array[int]) -> void:
	if mesh == null or edge_indices.is_empty():
		return

	# ── 1. Filter to valid boundary edges ──────────────────────────────────
	var valid_edges: Array[int] = []
	var seen: Dictionary = {}
	for ei: int in edge_indices:
		if ei >= 0 and ei < mesh.edges.size() \
				and not seen.has(ei) \
				and mesh.edges[ei].is_boundary():
			seen[ei] = true
			valid_edges.append(ei)
	if valid_edges.size() < 2:
		return

	# ── 2. Split into connected chains ─────────────────────────────────────
	var chains: Array = _split_into_chains(mesh, valid_edges)
	if chains.is_empty():
		return

	# ── 2b. Fill-hole shortcut ──────────────────────────────────────────────
	# If all selected edges belong to a SINGLE closed boundary loop, fill the
	# hole with a single face via FillOperation instead of creating a quad strip.
	if chains.size() == 1:
		FillOperation.apply(mesh, valid_edges)
		return

	# Use the two longest chains if more than two were found (e.g. user had
	# stray selected edges from a third loop).
	chains.sort_custom(func(a: Array, b: Array) -> bool: return a.size() > b.size())
	var loop_a: Array[int] = chains[0]
	var loop_b: Array[int] = chains[1]

	if loop_a.size() < 2 or loop_b.size() < 2:
		return

	# ── 3. Align loop B to loop A ───────────────────────────────────────────
	loop_b = _align_loop(mesh, loop_a, loop_b)

	# ── 3b. Two single-edge case: guarantee non-crossing quad ───────────────
	# When both loops are exactly 2 vertices (one edge each), the general
	# alignment heuristic may produce a crossing quad where both selected edges
	# appear as diagonals rather than opposite sides.  Check the two possible
	# pairings and choose the one with shorter total diagonal length (the
	# non-crossing configuration always has a smaller sum of cross-distances).
	if loop_a.size() == 2 and loop_b.size() == 2:
		var a0: Vector3 = mesh.vertices[loop_a[0]]
		var a1: Vector3 = mesh.vertices[loop_a[1]]
		var b0: Vector3 = mesh.vertices[loop_b[0]]
		var b1: Vector3 = mesh.vertices[loop_b[1]]
		# Pairing 1: [a0,b0,b1,a1] — cross-diagonals are a0↔b1 and a1↔b0.
		var cross1: float = a0.distance_squared_to(b1) + a1.distance_squared_to(b0)
		# Pairing 2: [a0,b1,b0,a1] (reverse b) — cross-diagonals are a0↔b0 and a1↔b1.
		var cross2: float = a0.distance_squared_to(b0) + a1.distance_squared_to(b1)
		# The non-crossing quad has larger cross-diagonal lengths (the diagonals
		# are longer than the sides in a proper bridged quad).  Reverse b only
		# when pairing 1 is the crossing one (its diagonals are shorter).
		if cross1 < cross2:
			loop_b.reverse()

	# ── 4. Resample to the same length (longer loop wins) ──────────────────
	var n: int = maxi(loop_a.size(), loop_b.size()) - 1
	if n < 1:
		return
	var verts_a: Array[int] = _resample_loop(loop_a, n + 1)
	var verts_b: Array[int] = _resample_loop(loop_b, n + 1)

	# ── 5. Fill quad strip ──────────────────────────────────────────────────
	# Source material: first adjacent face among loop_a's source edges.
	var mat_idx: int = 0
	for fi: int in mesh.edges[valid_edges[0]].face_indices:
		mat_idx = mesh.faces[fi].material_index
		break

	for i: int in n:
		var va: int = verts_a[i]
		var va1: int = verts_a[i + 1]
		var vb: int  = verts_b[i]
		var vb1: int = verts_b[i + 1]

		var quad := GoBuildFace.new()
		# Winding [va, vb, vb1, va1] — CCW from outside.
		quad.vertex_indices = [va, vb, vb1, va1]
		quad.uvs = [
			Vector2(float(i) / float(n),       0.0),
			Vector2(float(i) / float(n),       1.0),
			Vector2(float(i + 1) / float(n),   1.0),
			Vector2(float(i + 1) / float(n),   0.0),
		]
		quad.material_index = mat_idx
		mesh.faces.append(quad)

	mesh.rebuild_edges()


# ---------------------------------------------------------------------------
# Chain extraction
# ---------------------------------------------------------------------------

## Split [param edge_indices] into lists of connected vertex chains.
##
## Each chain is an ordered [Array[int]] of vertex indices (not edge indices).
## Edges that are not connected to any other edge in the set start a chain of
## their own.
static func _split_into_chains(mesh: GoBuildMesh, edge_indices: Array[int]) -> Array:
	# Build adjacency: vertex → list of edge indices in the selection.
	var adj: Dictionary = {}
	for ei: int in edge_indices:
		var e: GoBuildEdge = mesh.edges[ei]
		for v: int in [e.vertex_a, e.vertex_b]:
			if not adj.has(v):
				adj[v] = []
			(adj[v] as Array).append(ei)

	# Find chain start vertices: degree 1 in the selection (or degree > 2 edges
	# are split too; for simplicity we use degree == 1 as the walk start).
	# For closed loops every vertex has degree 2 — we pick any vertex as start.
	var visited_edges: Dictionary = {}
	var chains: Array = []

	for start_ei: int in edge_indices:
		if visited_edges.has(start_ei):
			continue

		# Walk starting from vertex_a of start_ei.
		var chain: Array[int] = []
		var e0: GoBuildEdge = mesh.edges[start_ei]
		var prev_v: int = -1
		var cur_v: int = e0.vertex_a
		var cur_ei: int = start_ei

		# Try to find the true start (degree-1 vertex) within this connected component.
		# Do a quick linear scan over the edges in this component to find a degree-1 end.
		var component: Array[int] = _collect_component(mesh, start_ei, edge_indices, adj)
		var start_vertex: int = e0.vertex_a
		for v: int in adj.keys():
			if (adj[v] as Array).size() == 1:
				var candidate_ei: int = (adj[v] as Array)[0]
				if component.has(candidate_ei):
					start_vertex = v
					cur_ei = candidate_ei
					break

		# Walk the chain from start_vertex.
		chain.append(start_vertex)
		prev_v = start_vertex
		var next_v: int = _other_vert(mesh.edges[cur_ei], prev_v)

		while true:
			if visited_edges.has(cur_ei):
				break
			visited_edges[cur_ei] = true
			chain.append(next_v)
			# Find next edge from next_v (not the one we came from).
			var found_next: bool = false
			if adj.has(next_v):
				for nei: int in (adj[next_v] as Array):
					if not visited_edges.has(nei):
						prev_v = next_v
						next_v = _other_vert(mesh.edges[nei], prev_v)
						cur_ei = nei
						found_next = true
						break
			if not found_next:
				break

		if chain.size() >= 2:
			chains.append(chain)

	return chains


## Collect all edge indices reachable from [param start_ei] via the adjacency map.
static func _collect_component(
		mesh: GoBuildMesh,
		start_ei: int,
		_all_edges: Array[int],
		adj: Dictionary,
) -> Array[int]:
	var result: Array[int] = []
	var stack: Array[int] = [start_ei]
	var visited: Dictionary = {}
	while not stack.is_empty():
		var ei: int = stack.pop_back()
		if visited.has(ei):
			continue
		visited[ei] = true
		result.append(ei)
		var e: GoBuildEdge = mesh.edges[ei]
		for v: int in [e.vertex_a, e.vertex_b]:
			if adj.has(v):
				for nei: int in (adj[v] as Array):
					if not visited.has(nei):
						stack.append(nei)
	return result


## Return the endpoint of [param edge] that is not [param v].
static func _other_vert(edge: GoBuildEdge, v: int) -> int:
	return edge.vertex_b if edge.vertex_a == v else edge.vertex_a


# ---------------------------------------------------------------------------
# Loop alignment
# ---------------------------------------------------------------------------

## Rotate / reverse loop B so its start is closest to loop A's start and the
## winding produces outward-facing normals when bridged with loop A.
##
## Returns a new [Array[int]] of the same length as [param loop_b].
static func _align_loop(
		mesh: GoBuildMesh,
		loop_a: Array[int],
		loop_b: Array[int],
) -> Array[int]:
	var n: int = loop_b.size()
	var a0: Vector3 = mesh.vertices[loop_a[0]]

	# Find the vertex in loop_b closest to loop_a[0].
	var best_start: int = 0
	var best_dist: float = INF
	for i: int in n:
		var d: float = a0.distance_squared_to(mesh.vertices[loop_b[i]])
		if d < best_dist:
			best_dist = d
			best_start = i

	# Rotate loop_b so best_start is at index 0.
	var rotated: Array[int] = []
	for i: int in n:
		rotated.append(loop_b[(best_start + i) % n])

	# Check winding: compute the centroid of each loop and the bridge direction.
	var centroid_a := Vector3.ZERO
	for v: int in loop_a:
		centroid_a += mesh.vertices[v]
	centroid_a /= float(loop_a.size())

	var centroid_b := Vector3.ZERO
	for v: int in rotated:
		centroid_b += mesh.vertices[v]
	centroid_b /= float(n)

	# Bridge direction: A → B.
	var bridge_dir: Vector3 = (centroid_b - centroid_a).normalized()

	# Tangent of loop_b at its start (rotated[0] → rotated[1]).
	var tangent_b: Vector3 = Vector3.ZERO
	if n >= 2:
		tangent_b = (mesh.vertices[rotated[1]] - mesh.vertices[rotated[0]]).normalized()

	# If (bridge_dir × tangent_b) · UP < 0 the winding would be inverted.
	# Reverse loop_b so the faces point outward.
	# We use a heuristic: the first quad's normal should have a component away
	# from the centroid of loop_a.
	if n >= 2:
		# Normal of a candidate first quad [a0, b0, b1, a1].
		var a1: Vector3 = mesh.vertices[loop_a[mini(1, loop_a.size() - 1)]]
		var b0: Vector3 = mesh.vertices[rotated[0]]
		var b1: Vector3 = mesh.vertices[rotated[1]]
		var v0: Vector3 = a0
		# Newell normal for the quad.
		var e0: Vector3 = b0 - v0
		var e1: Vector3 = b1 - b0
		var candidate_normal: Vector3 = e0.cross(e1)
		# If the candidate normal points toward loop_a's centroid rather than
		# away from it, reverse loop_b.
		if candidate_normal.dot(centroid_a - b0) > 0.0:
			rotated.reverse()

	var result: Array[int] = []
	result.assign(rotated)
	return result


# ---------------------------------------------------------------------------
# Resampling
# ---------------------------------------------------------------------------

## Resample [param loop] (an ordered Array[int] of vertex indices) to exactly
## [param target_count] indices using nearest-neighbour sampling.
##
## If [param loop] already has [param target_count] entries it is returned
## unchanged. Resampling only occurs when the two loops have different lengths.
static func _resample_loop(loop: Array[int], target_count: int) -> Array[int]:
	if loop.size() == target_count:
		var r: Array[int] = []
		r.assign(loop)
		return r
	var result: Array[int] = []
	var src_n: int = loop.size()
	for i: int in target_count:
		var src_idx: int = int(round(float(i) * float(src_n - 1) / float(target_count - 1)))
		src_idx = clampi(src_idx, 0, src_n - 1)
		result.append(loop[src_idx])
	return result
