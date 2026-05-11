## Fill-hole operation for [GoBuildMesh].
##
## Creates a single N-gon face from a closed boundary edge loop.
## The selected edges must form a single connected closed chain of boundary
## edges (edges with exactly one adjacent face).  The operation walks the
## chain into an ordered vertex loop, generates UVs from a local 2D frame,
## validates winding against adjacent faces, and appends the new face.
##
## This is the standalone equivalent of the fill-hole shortcut that was
## previously embedded inside [BridgeOperation].
##
## [method GoBuildMesh.rebuild_edges] is called automatically inside
## [method apply].
@tool
class_name FillOperation
extends RefCounted

# Self-preloads — dependency order.
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")


## Fill a closed boundary edge loop with a single N-gon face.
##
## [param edge_indices] should contain boundary edges that form a single
## closed chain.  The chain is walked into an ordered vertex loop by following
## shared endpoints between consecutive edges.  If fewer than 3 boundary edges
## are found or the chain is not closed, the operation is a no-op.
## [method GoBuildMesh.rebuild_edges] is called automatically on completion.
static func apply(mesh: GoBuildMesh, edge_indices: Array[int]) -> void:
	if mesh == null or edge_indices.is_empty():
		return

	var valid_edges: Array[int] = []
	var seen: Dictionary = {}
	for ei: int in edge_indices:
		if ei >= 0 and ei < mesh.edges.size() \
				and not seen.has(ei) \
				and mesh.edges[ei].is_boundary():
			seen[ei] = true
			valid_edges.append(ei)
	if valid_edges.size() < 3:
		return

	var chain: Array[int] = _walk_chain(mesh, valid_edges)
	if chain.size() < 3:
		return

	if not _is_closed_loop(mesh, chain, valid_edges):
		return

	chain.resize(chain.size() - 1)

	_fill_hole(mesh, chain, valid_edges)
	mesh.rebuild_edges()


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

## Walk the selected edges into an ordered vertex chain.
static func _walk_chain(mesh: GoBuildMesh, valid_edges: Array[int]) -> Array[int]:
	var adj: Dictionary = {}
	for ei: int in valid_edges:
		var e: GoBuildEdge = mesh.edges[ei]
		for v: int in [e.vertex_a, e.vertex_b]:
			if not adj.has(v):
				adj[v] = []
			(adj[v] as Array).append(ei)

	var start_vertex: int = mesh.edges[valid_edges[0]].vertex_a
	for v: int in adj.keys():
		if (adj[v] as Array).size() == 1:
			start_vertex = v
			break

	var visited_edges: Dictionary = {}
	var chain: Array[int] = [start_vertex]
	var prev_v: int = start_vertex
	var cur_ei: int = (adj[start_vertex] as Array)[0]
	var cur_v: int = _other_vert(mesh.edges[cur_ei], prev_v)

	while not visited_edges.has(cur_ei):
		visited_edges[cur_ei] = true
		chain.append(cur_v)
		var found_next: bool = false
		if adj.has(cur_v):
			for nei: int in (adj[cur_v] as Array):
				if not visited_edges.has(nei):
					prev_v = cur_v
					cur_v = _other_vert(mesh.edges[nei], prev_v)
					cur_ei = nei
					found_next = true
					break
		if not found_next:
			break

	return chain


## Check whether the first and last vertices of [param chain] are connected
## by one of the [param valid_edges].
static func _is_closed_loop(mesh: GoBuildMesh, chain: Array[int],
		valid_edges: Array[int]) -> bool:
	if chain.size() < 2:
		return false
	if chain[0] == chain[chain.size() - 1]:
		return true
	var tail: int = chain[chain.size() - 1]
	var head: int = chain[0]
	for ei: int in valid_edges:
		var e: GoBuildEdge = mesh.edges[ei]
		if (e.vertex_a == tail and e.vertex_b == head) \
				or (e.vertex_a == head and e.vertex_b == tail):
			return true
	return false


## Create an N-gon face from the ordered [param chain] of vertex indices.
## Inherits material and smooth-group from adjacent faces, generates UVs from
## a local 2D frame, and validates winding against neighbours.
static func _fill_hole(mesh: GoBuildMesh, chain: Array[int],
		source_edges: Array[int]) -> void:
	var mat_idx: int = 0
	var smooth: int  = 0
	for ei: int in source_edges:
		if ei >= 0 and ei < mesh.edges.size():
			for fi: int in mesh.edges[ei].face_indices:
				mat_idx = mesh.faces[fi].material_index
				smooth  = mesh.faces[fi].smooth_group
				break
		break

	var fill := _FACE_SCRIPT.new()
	fill.vertex_indices = []
	for v: int in chain:
		fill.vertex_indices.append(v)
	fill.material_index = mat_idx
	fill.smooth_group   = smooth

	var centroid := Vector3.ZERO
	for v: int in chain:
		centroid += mesh.vertices[v]
	centroid /= float(chain.size())

	var u_axis: Vector3 = Vector3.RIGHT
	var v_axis: Vector3 = Vector3.FORWARD
	if chain.size() >= 2:
		u_axis = (mesh.vertices[chain[1]] - mesh.vertices[chain[0]]).normalized()
		var normal := Vector3.ZERO
		for k: int in chain.size():
			var p0: Vector3 = mesh.vertices[chain[k]] - centroid
			var p1: Vector3 = mesh.vertices[chain[(k + 1) % chain.size()]] - centroid
			normal += p0.cross(p1)
		normal = normal.normalized()
		if normal.length_squared() > 0.5:
			v_axis = normal.cross(u_axis).normalized()

	fill.uvs = []
	for v: int in chain:
		var p: Vector3 = mesh.vertices[v] - centroid
		fill.uvs.append(Vector2(p.dot(u_axis), p.dot(v_axis)))

	var chain_set: Dictionary = {}
	for v: int in chain:
		chain_set[v] = true
	var neighbour_normal := Vector3.ZERO
	for face: GoBuildFace in mesh.faces:
		var shared: bool = false
		for v: int in face.vertex_indices:
			if chain_set.has(v):
				shared = true
				break
		if shared:
			neighbour_normal += mesh.compute_face_normal(face)
	var fill_normal: Vector3 = mesh.compute_face_normal(fill)
	if neighbour_normal.length_squared() > 1e-8 \
			and fill_normal.dot(neighbour_normal) < 0.0:
		fill.vertex_indices.reverse()
		fill.uvs.reverse()

	mesh.faces.append(fill)


static func _other_vert(edge: GoBuildEdge, v: int) -> int:
	return edge.vertex_b if edge.vertex_a == v else edge.vertex_a