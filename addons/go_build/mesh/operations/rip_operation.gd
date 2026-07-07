## Rip operation for [GoBuildMesh].
##
## Splits selected vertices away from their unselected neighbours, creating an
## open seam.  This is the inverse of Weld: where Weld merges coincident
## vertices, Rip duplicates them so that selected and unselected faces no longer
## share topology.
##
## Two entry points:
##   [method apply_vertices] — rip selected vertices out of unselected faces.
##   [method apply_edges]    — rip along selected edges, splitting shared vertices.
##
## Algorithm for vertex rip:
##   1. For each selected vertex, find all faces that reference it.
##   2. If a vertex is referenced by both selected and unselected faces, duplicate
##      the vertex.  The duplicate takes the place of the original vertex in all
##      *unselected* faces, while the original vertex remains in *selected* faces.
##   3. Remove degenerate faces, compact vertices, rebuild edges.
##
## Algorithm for edge rip:
##   1. Collect all vertex indices from selected edges.
##   2. Select all faces adjacent to those edges.
##   3. Delegate to [method apply_vertices] with the computed vertex and face sets.
##
## In both modes, if every face sharing a vertex is selected, no rip occurs at
## that vertex (it becomes a free-floating vertex with no connection to unselected
## geometry, which is already "ripped").
@tool
class_name RipOperation
extends RefCounted

# Self-preloads — dependency order.
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")


## Rip [param vertex_indices] out of unselected faces on [param mesh].
##
## For each selected vertex that is shared between selected and unselected faces,
## the vertex is duplicated: the original vertex keeps its position in selected
## faces, while a new vertex at the same position replaces it in unselected faces.
## This creates an open seam around the selection boundary.
##
## If [param face_indices] is empty, all faces containing each selected vertex
## are considered "selected" and the rest are "unselected".  This is the typical
## usage when the caller already has a selection in Vertex mode.
##
## If every face sharing a vertex is in the selected set, that vertex is not
## ripped (it is already disconnected from unselected geometry).
##
## [method GoBuildMesh.rebuild_edges] is called automatically on completion.
##
## Returns the set of new vertex indices created by the rip (the duplicates),
## useful for post-rip selection.
static func apply_vertices(
		mesh: GoBuildMesh,
		vertex_indices: Array[int],
		face_indices: Array[int] = [],
) -> Array[int]:
	if mesh == null or vertex_indices.is_empty():
		return []

	mesh.rebuild_edges()

	var sel_verts: Dictionary = {}
	for vi: int in vertex_indices:
		if vi >= 0 and vi < mesh.vertices.size():
			sel_verts[vi] = true

	var sel_faces: Dictionary = {}
	if face_indices.is_empty():
		for vi: int in sel_verts:
			for fi: int in mesh.faces_of_vertex(vi):
				sel_faces[fi] = true
	else:
		for fi: int in face_indices:
			if fi >= 0 and fi < mesh.faces.size():
				sel_faces[fi] = true

	var new_vertex_indices: Array[int] = []
	var remap: Dictionary = {}

	for vi: int in sel_verts:
		var adjacent: Array[int] = mesh.faces_of_vertex(vi)
		var has_selected: bool = false
		var has_unselected: bool = false
		for fi: int in adjacent:
			if sel_faces.has(fi):
				has_selected = true
			else:
				has_unselected = true

		if not has_selected or not has_unselected:
			continue

		var dup_vi: int = mesh.vertices.size()
		mesh.vertices.append(mesh.vertices[vi])
		new_vertex_indices.append(dup_vi)
		remap[vi] = dup_vi

	for fi: int in mesh.faces.size():
		if sel_faces.has(fi):
			continue
		var face: GoBuildFace = mesh.faces[fi]
		for k: int in face.vertex_indices.size():
			var old_vi: int = face.vertex_indices[k]
			if remap.has(old_vi):
				face.vertex_indices[k] = remap[old_vi]
				face.uvs[k] = face.uvs[k] if k < face.uvs.size() else Vector2.ZERO
				if k < face.uv2s.size():
					face.uv2s[k] = face.uv2s[k]

	_remove_degenerate_faces(mesh)
	_compact_vertices(mesh)
	mesh.rebuild_edges()

	return new_vertex_indices


## Rip along [param edge_indices] on [param mesh].
##
## Collects the two endpoint vertices of each selected edge and the faces adjacent
## to those edges, then delegates to [method apply_vertices].  The selected faces
## are those that are adjacent to at least one selected edge, so the rip splits
## the edge boundary out of the surrounding mesh.
##
## [method GoBuildMesh.rebuild_edges] is called automatically on completion.
##
## Returns the set of new vertex indices created by the rip.
static func apply_edges(
		mesh: GoBuildMesh,
		edge_indices: Array[int],
) -> Array[int]:
	if mesh == null or edge_indices.is_empty():
		return []

	mesh.rebuild_edges()

	var sel_edges: Dictionary = {}
	for ei: int in edge_indices:
		if ei >= 0 and ei < mesh.edges.size():
			sel_edges[ei] = true

	var vertex_set: Dictionary = {}
	var face_set: Dictionary = {}
	for ei: int in sel_edges:
		var edge: GoBuildEdge = mesh.edges[ei]
		vertex_set[edge.vertex_a] = true
		vertex_set[edge.vertex_b] = true
		for fi: int in edge.face_indices:
			face_set[fi] = true

	var verts: Array[int] = []
	for vi: int in vertex_set:
		verts.append(vi)
	var faces: Array[int] = []
	for fi: int in face_set:
		faces.append(fi)

	return apply_vertices(mesh, verts, faces)


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

## Remove faces with fewer than 3 distinct vertex indices.
static func _remove_degenerate_faces(mesh: GoBuildMesh) -> void:
	var new_faces: Array[GoBuildFace] = []
	for face: GoBuildFace in mesh.faces:
		var seen: Dictionary = {}
		for vi: int in face.vertex_indices:
			seen[vi] = true
		if seen.size() >= 3:
			new_faces.append(face)
	mesh.faces = new_faces


## Remove unreferenced vertices and remap face indices.
static func _compact_vertices(mesh: GoBuildMesh) -> void:
	var used: Dictionary = {}
	for face: GoBuildFace in mesh.faces:
		for vi: int in face.vertex_indices:
			used[vi] = true

	var old_indices: Array = used.keys()
	old_indices.sort()

	var remap: Dictionary = {}
	var new_verts: Array[Vector3] = []
	for new_vi: int in old_indices.size():
		var old_vi: int = old_indices[new_vi]
		remap[old_vi] = new_vi
		new_verts.append(mesh.vertices[old_vi])

	for face: GoBuildFace in mesh.faces:
		for k: int in face.vertex_indices.size():
			face.vertex_indices[k] = remap[face.vertex_indices[k]]

	mesh.vertices = new_verts