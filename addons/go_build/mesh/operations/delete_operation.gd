## Delete geometry operation for [GoBuildMesh].
##
## Removes selected faces, edges, or vertices and compacts the vertex array
## to eliminate orphaned (unreferenced) vertices after the removal.
##
## Three entry points cover the three editing modes:
##   [method apply_faces]    — remove selected faces and their orphaned vertices.
##   [method apply_edges]    — remove all faces adjacent to selected edges, then compact.
##   [method apply_vertices] — remove all faces that reference selected vertices
##                             (including coincident duplicates), then compact.
##
## [method GoBuildMesh.rebuild_edges] is called automatically inside each entry
## point so the derived edge list stays in sync with the new face topology.
@tool
class_name DeleteOperation
extends RefCounted

# Self-preloads — dependency order.
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")


## Delete the faces at [param face_indices] from [param mesh].
##
## Vertices that are no longer referenced by any remaining face are removed and
## all surviving face [member GoBuildFace.vertex_indices] are remapped to stay
## consistent.  [method GoBuildMesh.rebuild_edges] is called automatically on
## completion.  Invalid (out-of-range) indices are silently skipped.
static func apply_faces(mesh: GoBuildMesh, face_indices: Array[int]) -> void:
	if mesh == null or face_indices.is_empty():
		return
	var to_delete: Dictionary = {}
	for fi: int in face_indices:
		if fi >= 0 and fi < mesh.faces.size():
			to_delete[fi] = true
	if to_delete.is_empty():
		return
	_delete_faces_by_set(mesh, to_delete)
	mesh.rebuild_edges()


## Delete all faces adjacent to the edges at [param edge_indices] from [param mesh].
##
## Collects face indices from each selected [member GoBuildEdge.face_indices] and
## delegates to the internal face-delete path.
## [method GoBuildMesh.rebuild_edges] is called automatically on completion.
## Invalid (out-of-range) indices are silently skipped.
static func apply_edges(mesh: GoBuildMesh, edge_indices: Array[int]) -> void:
	if mesh == null or edge_indices.is_empty():
		return
	var face_set: Dictionary = {}
	for ei: int in edge_indices:
		if ei < 0 or ei >= mesh.edges.size():
			continue
		for fi: int in mesh.edges[ei].face_indices:
			face_set[fi] = true
	if face_set.is_empty():
		return
	_delete_faces_by_set(mesh, face_set)
	mesh.rebuild_edges()


## Delete all faces that reference any vertex at [param vertex_indices] in [param mesh].
##
## Each selected vertex index is expanded through
## [method GoBuildMesh.get_coincident_vertices] so that all split copies of a
## shared corner (produced by generators) are treated as a single logical vertex.
## Orphaned vertices are removed and face [member GoBuildFace.vertex_indices]
## are remapped to stay consistent.
## [method GoBuildMesh.rebuild_edges] is called automatically on completion.
## Invalid (out-of-range) indices are silently skipped.
static func apply_vertices(mesh: GoBuildMesh, vertex_indices: Array[int]) -> void:
	if mesh == null or vertex_indices.is_empty():
		return
	# Expand each selected vertex through its coincident group so all duplicate
	# copies of a shared corner are included in the affected set.
	var expanded: Dictionary = {}
	for vi: int in vertex_indices:
		if vi < 0 or vi >= mesh.vertices.size():
			continue
		for cvi: int in mesh.get_coincident_vertices(vi):
			expanded[cvi] = true
	if expanded.is_empty():
		return
	# Collect all faces that reference any vertex in the expanded set.
	var face_set: Dictionary = {}
	for fi: int in mesh.faces.size():
		var face: GoBuildFace = mesh.faces[fi]
		for vi: int in face.vertex_indices:
			if expanded.has(vi):
				face_set[fi] = true
				break
	if face_set.is_empty():
		return
	_delete_faces_by_set(mesh, face_set)
	mesh.rebuild_edges()


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

## Remove every face whose index is a key in [param face_set], then compact
## the vertex array to eliminate orphaned (unreferenced) vertices.
static func _delete_faces_by_set(mesh: GoBuildMesh, face_set: Dictionary) -> void:
	var new_faces: Array[GoBuildFace] = []
	for fi: int in mesh.faces.size():
		if not face_set.has(fi):
			new_faces.append(mesh.faces[fi])
	mesh.faces = new_faces
	_compact_vertices(mesh)


## Remove unreferenced vertices and remap [member GoBuildFace.vertex_indices] accordingly.
##
## After faces are deleted, some vertices may no longer be referenced by any
## remaining face. This method:
##   1. Finds all vertex indices still referenced by [member GoBuildMesh.faces].
##   2. Builds a remap table [code]old_vi → new_vi[/code].
##   3. Rebuilds [member GoBuildMesh.vertices] with only the referenced vertices,
##      preserving their relative order.
##   4. Updates every [member GoBuildFace.vertex_indices] using the remap table.
static func _compact_vertices(mesh: GoBuildMesh) -> void:
	# Collect the set of vertex indices that are still referenced by a face.
	var used: Dictionary = {}
	for face: GoBuildFace in mesh.faces:
		for vi: int in face.vertex_indices:
			used[vi] = true

	# Sort used indices so the new array preserves ascending relative order.
	var old_indices: Array = used.keys()
	old_indices.sort()

	# Build the remap table and the new (compacted) vertex array.
	var remap: Dictionary = {}
	var new_verts: Array[Vector3] = []
	for new_vi: int in old_indices.size():
		var old_vi: int = old_indices[new_vi]
		remap[old_vi] = new_vi
		new_verts.append(mesh.vertices[old_vi])

	# Apply the remap to every face.
	for face: GoBuildFace in mesh.faces:
		for k: int in face.vertex_indices.size():
			face.vertex_indices[k] = remap[face.vertex_indices[k]]

	mesh.vertices = new_verts
