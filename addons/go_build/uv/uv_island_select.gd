## Select all faces in the same UV island as a given face.
##
## Uses UV-connected flood-fill (faces sharing a UV vertex within epsilon)
## to find all faces belonging to the same UV island.  This is the same
## algorithm as [code]UvPackIslands._build_islands[/code] but returns only
## the single island containing the seed face, avoiding a full island build.
@tool
class_name UvIslandSelect
extends RefCounted

const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _UV_TOPO_SCRIPT := preload("res://addons/go_build/uv/uv_topology.gd")


## Return all face indices in the UV island that contains [param seed_face].
## Uses a flood-fill from [param seed_face] through shared UV vertices.
## [param mesh] is the [GoBuildMesh] to search.
static func select_island(mesh: GoBuildMesh, seed_face: int) -> Array[int]:
	if mesh.faces.is_empty() or seed_face < 0 or seed_face >= mesh.faces.size():
		return []
	var uv_to_faces := UvTopology.build_uv_vertex_map(mesh)
	var visited: Dictionary = {}
	var result: Array[int] = []
	var stack: Array[int] = [seed_face]
	while not stack.is_empty():
		var cur: int = stack.pop_back()
		if visited.has(cur):
			continue
		visited[cur] = true
		result.append(cur)
		var face: GoBuildFace = mesh.faces[cur]
		for uv: Vector2 in face.uvs:
			var key := UvTopology.uv_key(uv)
			if uv_to_faces.has(key):
				for nb: int in uv_to_faces[key]:
					if not visited.has(nb):
						stack.append(nb)
	return result


## Return all UV islands as an array of face-index arrays, restricted to
## [param face_filter] when non-empty (only filtered faces are seeded and
## only filtered neighbours traversed).  The canonical island flood fill —
## pack and stitch delegate here.
static func build_all_islands(mesh: GoBuildMesh,
		face_filter: Array[int] = []) -> Array[Array]:
	if mesh.faces.is_empty():
		return []
	var filter_set: Dictionary = {}
	if not face_filter.is_empty():
		for fi: int in face_filter:
			filter_set[fi] = true
	var uv_to_faces := UvTopology.build_uv_vertex_map_for(mesh, filter_set) \
			if not filter_set.is_empty() \
			else UvTopology.build_uv_vertex_map(mesh)
	var visited: Dictionary = {}
	var seeds: Array[int] = face_filter if not face_filter.is_empty() \
			else GoBuildMesh.all_face_indices(mesh.faces.size())
	var islands: Array[Array] = []
	for fi: int in seeds:
		if visited.has(fi):
			continue
		var island: Array[int] = []
		var stack: Array[int] = [fi]
		while not stack.is_empty():
			var cur: int = stack.pop_back()
			if visited.has(cur):
				continue
			visited[cur] = true
			island.append(cur)
			var face: GoBuildFace = mesh.faces[cur]
			for uv: Vector2 in face.uvs:
				var key := UvTopology.uv_key(uv)
				if uv_to_faces.has(key):
					for nb: int in uv_to_faces[key]:
						if not visited.has(nb) \
								and (filter_set.is_empty()
										or filter_set.has(nb)):
							stack.append(nb)
		islands.append(island)
	return islands