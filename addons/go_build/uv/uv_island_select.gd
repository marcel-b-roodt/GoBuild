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

const _UV_EPSILON: float = 0.0001


## Return all face indices in the UV island that contains [param seed_face].
## Uses a flood-fill from [param seed_face] through shared UV vertices.
## [param mesh] is the [GoBuildMesh] to search.
static func select_island(mesh: GoBuildMesh, seed_face: int) -> Array[int]:
	if mesh.faces.is_empty() or seed_face < 0 or seed_face >= mesh.faces.size():
		return []
	var uv_to_faces := _build_uv_vertex_map(mesh)
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
			var key := _uv_key(uv)
			if uv_to_faces.has(key):
				for nb: int in uv_to_faces[key]:
					if not visited.has(nb):
						stack.append(nb)
	return result


## Return all UV islands as an array of face-index arrays.
## Mirrors [code]UvPackIslands._build_islands[/code] but is safe to call
## independently (no dependency on UvPackIslands internals).
static func build_all_islands(mesh: GoBuildMesh) -> Array[Array]:
	if mesh.faces.is_empty():
		return []
	var uv_to_faces := _build_uv_vertex_map(mesh)
	var visited: Dictionary = {}
	var islands: Array[Array] = []
	for fi: int in mesh.faces.size():
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
				var key := _uv_key(uv)
				if uv_to_faces.has(key):
					for nb: int in uv_to_faces[key]:
						if not visited.has(nb):
							stack.append(nb)
		islands.append(island)
	return islands


static func _build_uv_vertex_map(mesh: GoBuildMesh) -> Dictionary:
	var m: Dictionary = {}
	for fi: int in mesh.faces.size():
		var face: GoBuildFace = mesh.faces[fi]
		for uv: Vector2 in face.uvs:
			var key := _uv_key(uv)
			if not m.has(key):
				m[key] = []
			m[key].append(fi)
	return m


static func _uv_key(uv: Vector2) -> StringName:
	var ix: int = roundi(uv.x / _UV_EPSILON)
	var iy: int = roundi(uv.y / _UV_EPSILON)
	return StringName("%d|%d" % [ix, iy])