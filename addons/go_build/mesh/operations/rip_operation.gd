## Rip operation for [GoBuildMesh].
##
## Splits selected vertices away from the mesh, creating an open seam, and
## optionally drags the ripped piece along a direction.
## This is the inverse of Weld: where Weld merges coincident vertices, Rip
## duplicates them so the torn piece and the mesh body no longer share topology.
##
## Entry points:
##   [method apply_vertices]    — rip only (no drag).
##   [method apply_vertex_drag] — rip + drag ripped vertices along a direction.
##   [method apply_edges]       — rip along selected edges (no drag).
##   [method apply_edge_drag]   — rip along edges + drag.
##
## Algorithm for vertex rip (with face selection):
##   1. For each selected vertex that appears in both selected and unselected faces,
##      duplicate the vertex.  The duplicate takes the place of the original vertex
##      in *selected* faces, while the original stays in unselected faces.
##      The duplicate vertices are returned so they can be selected after the rip.
##
## Algorithm for vertex rip (without face selection — Vertex mode):
##   1. Compute a rip direction (average normal of adjacent faces).
##   2. For each selected vertex, split its adjacent faces into two groups:
##      "toward" (face normal dot direction >= 0) and "away" (dot < 0).
##      The "toward" faces get the duplicate vertex; the "away" faces keep the original.
##      If all faces are in one group, split at the seam: the half closest to
##      the direction gets the duplicate.
##
## Algorithm for edge rip:
##   1. Collect all vertex indices from selected edges and the faces adjacent
##      to those edges.
##   2. Delegate to [method apply_vertices] with the computed vertex and face sets.
##
## Drag variants apply the rip, then translate the duplicate vertices along
## [param direction] by [param distance].  Because the param preview system restores
## the snapshot before each call, these functions are idempotent.
##
## In both modes, if every face sharing a vertex is in the selected set, no rip
## occurs at that vertex (it is already disconnected from unselected geometry).
@tool
class_name RipOperation
extends RefCounted

# Self-preloads — dependency order.
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")


## Rip [param vertex_indices] on [param mesh].
##
## When [param face_indices] is non-empty, the rip uses those as the "selected"
## face set.  Vertices shared between selected and unselected faces are duplicated:
## the duplicate goes into the selected faces (the ripped piece), the original stays
## with the unselected faces (the mesh body).  The returned indices are the
## duplicates, suitable for post-rip selection.
##
## When [param face_indices] is empty (Vertex mode), the ripped face set is
## computed per-vertex using [param direction].  Faces whose normals align with
## the direction (dot product >= 0) become the "toward" set and receive the
## duplicate vertex.  Faces whose normals oppose the direction (dot product < 0)
## keep the original vertex.  This ensures every selected vertex is ripped even
## when all its faces would otherwise be in one group.
##
## [method GoBuildMesh.rebuild_edges] is called automatically on completion.
##
## Returns the set of new vertex indices created by the rip.
static func apply_vertices(
		mesh: GoBuildMesh,
		vertex_indices: Array[int],
		face_indices: Array[int] = [],
		direction: Vector3 = Vector3.UP,
) -> Array[int]:
	if mesh == null or vertex_indices.is_empty():
		return []

	mesh.rebuild_edges()

	var sel_verts: Dictionary = {}
	for vi: int in vertex_indices:
		if vi >= 0 and vi < mesh.vertices.size():
			sel_verts[vi] = true

	if sel_verts.is_empty():
		return []

	var use_direction: bool = face_indices.is_empty()
	var sel_faces: Dictionary = {}

	if not use_direction:
		for fi: int in face_indices:
			if fi >= 0 and fi < mesh.faces.size():
				sel_faces[fi] = true

	GoBuildDebug.log("[Rip] apply_vertices: verts=%s faces=%s use_direction=%s direction=%s" \
			% [str(vertex_indices), str(face_indices), str(use_direction), str(direction)])
	GoBuildDebug.log("[Rip] mesh before: verts=%d faces=%d edges=%d" \
			% [mesh.vertices.size(), mesh.faces.size(), mesh.edges.size()])

	var new_vertex_indices: Array[int] = []
	var remap: Dictionary = {}

	for vi: int in sel_verts:
		var adjacent: Array[int] = mesh.faces_of_vertex(vi)

		if adjacent.size() < 2:
			GoBuildDebug.log("[Rip] SKIP vertex %d: only %d adjacent faces (need >= 2)" \
					% [vi, adjacent.size()])
			continue

		if use_direction:
			# Direction-based split: each vertex gets its own toward/away groups.
			# Remap directly into each face to avoid cross-vertex conflicts.
			var toward_faces: Dictionary = {}
			var away_faces: Dictionary = {}
			for fi: int in adjacent:
				if fi < 0 or fi >= mesh.faces.size():
					continue
				var face_normal: Vector3 = mesh.compute_face_normal(mesh.faces[fi])
				if face_normal.dot(direction) >= 0.0:
					toward_faces[fi] = true
				else:
					away_faces[fi] = true

			if away_faces.is_empty():
				toward_faces.clear()
				away_faces.clear()
				var first: bool = true
				for fi: int in adjacent:
					if fi < 0 or fi >= mesh.faces.size():
						continue
					if first:
						away_faces[fi] = true
						first = false
					else:
						toward_faces[fi] = true
			elif toward_faces.is_empty():
				toward_faces.clear()
				away_faces.clear()
				var first: bool = true
				for fi: int in adjacent:
					if fi < 0 or fi >= mesh.faces.size():
						continue
					if first:
						toward_faces[fi] = true
						first = false
					else:
						away_faces[fi] = true

			if toward_faces.is_empty() or away_faces.is_empty():
				GoBuildDebug.log("[Rip] SKIP vertex %d: cannot split (toward=%d away=%d)" \
						% [vi, toward_faces.size(), away_faces.size()])
				continue

			GoBuildDebug.log("[Rip] RIP vertex %d: toward=%s away=%s" \
					% [vi, str(toward_faces.keys()), str(away_faces.keys())])
			var dup_vi: int = mesh.vertices.size()
			mesh.vertices.append(mesh.vertices[vi])
			new_vertex_indices.append(dup_vi)
			remap[vi] = dup_vi

			# Remap this vertex directly in its toward_faces.
			# Do NOT add to sel_faces — each vertex handles its own faces.
			for fi: int in toward_faces:
				var face: GoBuildFace = mesh.faces[fi]
				for k: int in face.vertex_indices.size():
					if face.vertex_indices[k] == vi:
						face.vertex_indices[k] = dup_vi

		else:
			# Explicit face selection mode.
			var has_selected: bool = false
			var has_unselected: bool = false
			for fi: int in adjacent:
				if sel_faces.has(fi):
					has_selected = true
				else:
					has_unselected = true

			if not has_unselected:
				GoBuildDebug.log("[Rip] SKIP vertex %d: no unselected faces" % vi)
				continue
			if not has_selected:
				GoBuildDebug.log("[Rip] SKIP vertex %d: no selected faces" % vi)
				continue

			GoBuildDebug.log("[Rip] RIP vertex %d: has_selected=%s has_unselected=%s" \
					% [vi, str(has_selected), str(has_unselected)])
			var dup_vi: int = mesh.vertices.size()
			mesh.vertices.append(mesh.vertices[vi])
			new_vertex_indices.append(dup_vi)
			remap[vi] = dup_vi

	# In explicit face selection mode, remap all selected faces at once.
	# In direction-based mode, faces were already remapped per-vertex above.
	if not use_direction:
		for fi: int in mesh.faces.size():
			if not sel_faces.has(fi):
				continue
			var face: GoBuildFace = mesh.faces[fi]
			for k: int in face.vertex_indices.size():
				var old_vi: int = face.vertex_indices[k]
				if remap.has(old_vi):
					face.vertex_indices[k] = remap[old_vi]

	_remove_degenerate_faces(mesh)
	var compact_remap: Dictionary = _compact_vertices(mesh)
	for i: int in new_vertex_indices.size():
		new_vertex_indices[i] = compact_remap.get(new_vertex_indices[i], new_vertex_indices[i])
	mesh.rebuild_edges()

	GoBuildDebug.log("[Rip] apply_vertices DONE: new_verts=%s remap=%s sel_faces=%s" \
			% [str(new_vertex_indices), str(remap), str(sel_faces.keys())])
	GoBuildDebug.log("[Rip] mesh after: verts=%d faces=%d edges=%d" \
			% [mesh.vertices.size(), mesh.faces.size(), mesh.edges.size()])

	return new_vertex_indices


## Rip [param vertex_indices] and drag the ripped piece by [param distance]
## along [param direction] (in local space).
##
## Idempotent — designed for use with [GoBuildParamPreview] where the snapshot
## is restored before each call.  Performs the rip, then translates all duplicate
## vertices by [code]direction × distance[/code].
##
## Returns the set of new vertex indices created by the rip (after compaction).
static func apply_vertex_drag(
		mesh: GoBuildMesh,
		vertex_indices: Array[int],
		face_indices: Array[int],
		direction: Vector3,
		distance: float,
) -> Array[int]:
	var ripped: Array[int] = apply_vertices(mesh, vertex_indices, face_indices, direction)
	GoBuildDebug.log("[Rip] apply_vertex_drag: ripped=%s direction=%s distance=%.3f" \
			% [str(ripped), str(direction), distance])
	if ripped.is_empty():
		return ripped

	var offset: Vector3 = direction * distance
	GoBuildDebug.log("[Rip] applying offset=%s to %d ripped vertices" % [str(offset), ripped.size()])
	for vi: int in ripped:
		mesh.vertices[vi] = mesh.vertices[vi] + offset

	return ripped


## Rip along [param edge_indices] on [param mesh].
##
## Collects the two endpoint vertices of each selected edge and the faces adjacent
## to those edges, then delegates to [method apply_vertices] with the computed
## vertex and face sets.
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


## Rip along [param edge_indices] and drag the ripped piece by [param distance]
## along [param direction] (in local space).
##
## Idempotent — designed for use with [GoBuildParamPreview].
##
## Returns the set of new vertex indices created by the rip (after compaction).
static func apply_edge_drag(
		mesh: GoBuildMesh,
		edge_indices: Array[int],
		direction: Vector3,
		distance: float,
) -> Array[int]:
	if mesh == null or edge_indices.is_empty():
		return []

	mesh.rebuild_edges()

	var vertex_set: Dictionary = {}
	var face_set: Dictionary = {}
	for ei: int in edge_indices:
		if ei >= 0 and ei < mesh.edges.size():
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

	return apply_vertex_drag(mesh, verts, faces, direction, distance)


## Compute the average outward normal of the ripped faces (in local space).
##
## Used by the drag callers to determine the direction the ripped piece
## should move along.  Returns [code]Vector3.UP[/code] as a fallback if no
## valid normal can be computed.
static func compute_rip_direction(
		mesh: GoBuildMesh,
		face_indices: Array[int],
) -> Vector3:
	if mesh == null or face_indices.is_empty():
		return Vector3.UP

	var avg_normal: Vector3 = Vector3.ZERO
	var count: int = 0
	for fi: int in face_indices:
		if fi < 0 or fi >= mesh.faces.size():
			continue
		var n: Vector3 = mesh.compute_face_normal(mesh.faces[fi])
		avg_normal += n
		count += 1

	if count == 0:
		return Vector3.UP

	avg_normal /= count
	if avg_normal.is_equal_approx(Vector3.ZERO):
		return Vector3.UP

	return avg_normal.normalized()


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
## Returns a Dictionary mapping old vertex indices to new ones.
static func _compact_vertices(mesh: GoBuildMesh) -> Dictionary:
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
	return remap