## Merges two or more adjacent selected faces into a single n-gon face.
##
## All selected faces that share edges form merged groups.  Each group is
## replaced by a single face whose vertex ring is the outer boundary of the
## group (interior edges are dissolved).  UVs, smooth groups, and material
## indices are inherited from the first face in each group.
##
## The boundary ring is walked in winding-consistent order: after building the
## ring, its Newell normal is compared to the average outward normal of the
## constituent faces.  If they point in opposite directions, the ring is
## reversed so that the merged face has the correct CCW winding (outward normal).
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
## - Interior edges (shared by two selected faces) are dissolved.
## - Boundary edges (shared with an unselected face or a mesh boundary) are kept.
## - The merged face's winding order is corrected so its Newell normal matches
##   the average outward normal of the original faces.
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

	var selected_set: Dictionary = {}
	for fi: int in valid:
		selected_set[fi] = true

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
			var edge_indices: Array[int] = mesh.edges_of_face(fi)
			for edge_idx: int in edge_indices:
				if edge_idx < 0 or edge_idx >= mesh.edges.size():
					continue
				var edge: GoBuildEdge = mesh.edges[edge_idx]
				for other_fi: int in edge.face_indices:
					if selected_set.has(other_fi) and not visited.has(other_fi):
						queue.append(other_fi)
		if group.size() >= 2:
			groups.append(group)

	if groups.is_empty():
		return

	var faces_to_remove: Dictionary = {}
	var new_faces: Array[GoBuildFace] = []

	for group: Array[int] in groups:
		var interior_edge_set: Dictionary = {}
		var boundary_edge_set: Dictionary = {}
		for fi: int in group:
			faces_to_remove[fi] = true
			var edge_indices: Array[int] = mesh.edges_of_face(fi)
			for edge_idx: int in edge_indices:
				if edge_idx < 0 or edge_idx >= mesh.edges.size():
					continue
				if interior_edge_set.has(edge_idx):
					continue
				var edge: GoBuildEdge = mesh.edges[edge_idx]
				var all_in_group: bool = true
				for ef: int in edge.face_indices:
					if not selected_set.has(ef):
						all_in_group = false
						break
				if all_in_group:
					interior_edge_set[edge_idx] = true
				else:
					boundary_edge_set[edge_idx] = true

		if boundary_edge_set.is_empty():
			continue

		# Compute the average outward normal of the constituent faces.
		# This is the reference direction that the merged face's normal must match.
		var avg_normal := Vector3.ZERO
		for fi: int in group:
			avg_normal += mesh.compute_face_normal(mesh.faces[fi])
		if avg_normal.length_squared() > 1e-8:
			avg_normal = avg_normal.normalized()

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
		var ring: Array[int] = []
		var current_edge_idx: int = first_edge_idx
		var current_vert: int = mesh.edges[current_edge_idx].vertex_a
		var start_vert: int = current_vert

		var max_iter: int = boundary_edge_set.size() + 2
		while max_iter > 0:
			max_iter -= 1
			ring.append(current_vert)
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

		# Fix winding: compute the Newell normal of the ring and compare it
		# against the average outward normal of the original faces.  If the ring
		# normal points inward (dot product < 0), reverse the ring so the merged
		# face has CCW winding when viewed from outside.
		var ring_normal := _compute_ring_normal(mesh, ring)
		if ring_normal.dot(avg_normal) < 0.0:
			ring.reverse()

		var merged_face: GoBuildFace = GoBuildFace.new()
		merged_face.vertex_indices = []
		for vi: int in ring:
			merged_face.vertex_indices.append(vi)
		var first_face: GoBuildFace = mesh.faces[group[0]]
		merged_face.material_index = first_face.material_index
		merged_face.smooth_group = first_face.smooth_group
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

	var remove_list: Array[int] = []
	for fi: int in faces_to_remove:
		remove_list.append(fi)
	remove_list.sort()
	for i: int in range(remove_list.size() - 1, -1, -1):
		mesh.faces.remove_at(remove_list[i])

	for f: GoBuildFace in new_faces:
		mesh.faces.append(f)

	mesh.rebuild_edges()


## Compute the Newell normal of a vertex ring (CCW from outside = outward).
static func _compute_ring_normal(mesh: GoBuildMesh, ring: Array[int]) -> Vector3:
	var n := Vector3.ZERO
	var vc: int = ring.size()
	for i in vc:
		var cur: Vector3 = mesh.vertices[ring[i]]
		var nxt: Vector3 = mesh.vertices[ring[(i + 1) % vc]]
		n.x += (cur.y - nxt.y) * (cur.z + nxt.z)
		n.y += (cur.z - nxt.z) * (cur.x + nxt.x)
		n.z += (cur.x - nxt.x) * (cur.y + nxt.y)
	if n.length_squared() < 1e-8:
		return Vector3.UP
	return n.normalized()