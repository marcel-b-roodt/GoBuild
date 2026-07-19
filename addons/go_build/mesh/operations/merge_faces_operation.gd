## Merges two or more adjacent selected faces into a single n-gon face.
##
## All selected faces that share edges form merged groups.  Each group is
## replaced by a single face whose vertex ring is the outer boundary of the
## group (interior edges are dissolved).  UVs, smooth groups, and material
## indices are inherited from the first face in each group.
##
## Faces that are not adjacent to any other selected face are left unchanged.
##
## The operation is pure data — it does not bake or trigger any side-effects.
## Wrap it in [method GoBuildMeshInstance.apply_operation] to get undo/redo.
class_name MergeFacesOperation
extends RefCounted

# Self-preloads — dependency order:
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")


## Merge selected faces that share edges into single n-gon faces.
##
## [param face_indices] must contain at least 2 indices.  Faces are grouped
## by adjacency (connected via shared edges).  Each connected group is merged
## into one face.  Isolated faces (not adjacent to any other selected face)
## are left unchanged.
##
## After merging:
## - Interior edges (shared by two selected faces) are removed.
## - Boundary edges (shared with an unselected face or a mesh boundary) are kept.
## - [method GoBuildMesh.rebuild_edges] is called at the end.
static func apply(mesh: GoBuildMesh, face_indices: Array[int]) -> void:
	if mesh == null or face_indices.size() < 2:
		return

	var valid: Array[int] = []
	for fi: int in face_indices:
		if fi >= 0 and fi < mesh.faces.size():
			valid.append(fi)
	if valid.size() < 2:
		return

	# Build a set of selected face indices for fast lookup.
	var selected_set: Dictionary = {}
	for fi: int in valid:
		selected_set[fi] = true

	# Group selected faces by adjacency (BFS via shared edges).
	var visited: Dictionary = {}
	var groups: Array = []

	for start_fi: int in valid:
		if visited.has(start_fi):
			continue
		var group: Array[int] = []
		var queue: Array[int] = [start_fi]
		while not queue.is_empty():
			var fi: int = queue.pop_back()
			if visited.has(fi):
				continue
			visited[fi] = true
			group.append(fi)
			# Find adjacent selected faces via shared edges.
			for edge_idx: int in _face_edge_indices(mesh, fi):
				if edge_idx < 0 or edge_idx >= mesh.edges.size():
					continue
				var edge: GoBuildEdge = mesh.edges[edge_idx]
				for other_fi: int in _faces_of_edge(mesh, edge_idx):
					if selected_set.has(other_fi) and not visited.has(other_fi):
						queue.append(other_fi)
		if group.size() >= 2:
			groups.append(group)

	if groups.is_empty():
		return

	# For each group, build the boundary vertex ring and create a merged face.
	var faces_to_remove: Dictionary = {}
	var new_faces: Array[GoBuildFace] = []

	for group: Array[int] in groups:
		# Collect all edges of all faces in the group.
		# An edge is "interior" if both its faces are in the group.
		# An edge is "boundary" if only one of its faces is in the group.
		var interior_edge_set: Dictionary = {}
		var boundary_edge_set: Dictionary = {}
		for fi: int in group:
			faces_to_remove[fi] = true
			for edge_idx: int in _face_edge_indices(mesh, fi):
				if edge_idx < 0 or edge_idx >= mesh.edges.size():
					continue
				if interior_edge_set.has(edge_idx):
					continue
				if boundary_edge_set.has(edge_idx):
					# This edge appeared as boundary from one face, now it's
					# shared by two faces in the group — it's interior.
					boundary_edge_set.erase(edge_idx)
					interior_edge_set[edge_idx] = true
					continue
				# Check if the other face of this edge is also in the group.
				var both_in_group: bool = true
				var edge_faces: Array[int] = _faces_of_edge(mesh, edge_idx)
				if edge_faces.size() < 2:
					both_in_group = false
				else:
					for ef: int in edge_faces:
						if not selected_set.has(ef):
							both_in_group = false
							break
				if both_in_group:
					interior_edge_set[edge_idx] = true
				else:
					boundary_edge_set[edge_idx] = true

		# The boundary edges form the outer ring of the merged face.
		# Walk them in order to produce a vertex ring.
		if boundary_edge_set.is_empty():
			continue

		# Build a mapping: vertex → list of boundary edges incident to it.
		var vert_to_boundary_edges: Dictionary = {}
		for edge_idx: int in boundary_edge_set:
			var edge: GoBuildEdge = mesh.edges[edge_idx]
			if not vert_to_boundary_edges.has(edge.vertex_a):
				vert_to_boundary_edges[edge.vertex_a] = []
			vert_to_boundary_edges[edge.vertex_a].append(edge_idx)
			if not vert_to_boundary_edges.has(edge.vertex_b):
				vert_to_boundary_edges[edge.vertex_b] = []
			vert_to_boundary_edges[edge.vertex_b].append(edge_idx)

		# Walk the boundary edges starting from an arbitrary edge.
		var first_edge_idx: int = boundary_edge_set.keys()[0]
		var ring: Array[int] = []  # vertex indices forming the boundary ring
		var current_edge_idx: int = first_edge_idx
		var current_vert: int = mesh.edges[current_edge_idx].vertex_a
		var start_vert: int = current_vert

		# Safety: limit iterations to avoid infinite loops.
		var max_iter: int = boundary_edge_set.size() + 2
		while max_iter > 0:
			max_iter -= 1
			ring.append(current_vert)
			# Find the next boundary edge that is NOT the one we came from
			# and starts from current_vert.
			var next_edge_idx: int = -1
			var edges_from_vert = vert_to_boundary_edges.get(current_vert, [])
			for eidx: int in edges_from_vert:
				if eidx == current_edge_idx:
					continue
				var e: GoBuildEdge = mesh.edges[eidx]
				if e.vertex_a == current_vert or e.vertex_b == current_vert:
					next_edge_idx = eidx
					break
			if next_edge_idx == -1:
				break
			var next_edge: GoBuildEdge = mesh.edges[next_edge_idx]
			if next_edge.vertex_a == current_vert:
				current_vert = next_edge.vertex_b
			else:
				current_vert = next_edge.vertex_a
			current_edge_idx = next_edge_idx
			if current_vert == start_vert:
				break

		if ring.size() < 3:
			continue

		# Create a merged face from the boundary ring.
		var merged_face: GoBuildFace = GoBuildFace.new()
		merged_face.vertex_indices = ring
		# Inherit material_index and smooth_group from the first face in the group.
		var first_face: GoBuildFace = mesh.faces[group[0]]
		merged_face.material_index = first_face.material_index
		merged_face.smooth_group = first_face.smooth_group
		# Compute UVs for the merged face using the first vertex's UV
		# from the face that contains it.
		var uv_map: Dictionary = {}
		for fi: int in group:
			var face: GoBuildFace = mesh.faces[fi]
			for j: int in face.vertex_indices.size():
				var vi: int = face.vertex_indices[j]
				if not uv_map.has(vi):
					uv_map[vi] = face.uvs[j]
		for vi: int in ring:
			if uv_map.has(vi):
				merged_face.uvs.append(uv_map[vi])
			else:
				merged_face.uvs.append(Vector2.ZERO)
		new_faces.append(merged_face)

	# Remove merged faces (in reverse order to preserve indices).
	var remove_list: Array[int] = []
	for fi: int in faces_to_remove:
		remove_list.append(fi)
	remove_list.sort()
	for i: int in range(remove_list.size() - 1, -1, -1):
		mesh.faces.remove_at(remove_list[i])

	# Append new merged faces.
	for f: GoBuildFace in new_faces:
		mesh.faces.append(f)

	mesh.rebuild_edges()


## Return the edge indices associated with a face.
static func _face_edge_indices(mesh: GoBuildMesh, face_idx: int) -> Array[int]:
	var result: Array[int] = []
	if mesh._face_to_edges.is_empty():
		return result
	if face_idx >= mesh._face_to_edges.size():
		return result
	var edges: Array[int] = mesh._face_to_edges[face_idx]
	result.assign(edges)
	return result


## Return the face indices of both faces sharing an edge.
static func _faces_of_edge(mesh: GoBuildMesh, edge_idx: int) -> Array[int]:
	var result: Array[int] = []
	if edge_idx < 0 or edge_idx >= mesh.edges.size():
		return result
	# Use the adjacency cache if available.
	if not mesh._face_to_edges.is_empty():
		for fi: int in mesh.faces.size():
			if mesh._face_to_edges[fi].has(edge_idx):
				result.append(fi)
		return result
	# Fallback: scan face vertex pairs.
	var edge: GoBuildEdge = mesh.edges[edge_idx]
	for fi: int in mesh.faces.size():
		var face: GoBuildFace = mesh.faces[fi]
		for j: int in face.vertex_indices.size():
			var v0: int = face.vertex_indices[j]
			var v1: int = face.vertex_indices[(j + 1) % face.vertex_indices.size()]
			if (v0 == edge.vertex_a and v1 == edge.vertex_b) \
					or (v0 == edge.vertex_b and v1 == edge.vertex_a):
				result.append(fi)
				break
	return result