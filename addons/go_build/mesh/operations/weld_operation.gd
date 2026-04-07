## Weld / Merge vertices operation for [GoBuildMesh].
##
## Two entry points cover the two common workflows:
##
##   [method apply_merge]          — collapse a explicit set of selected vertices
##                                   to their geometric centroid (Blender "Merge at
##                                   Center").  Requires at least 2 vertex indices.
##
##   [method apply_weld_by_threshold] — scan every pair of vertices in the mesh;
##                                   any pair closer than [param threshold] is
##                                   merged to the midpoint of the group centroid.
##                                   Equivalent to Blender "Merge by Distance".
##
## Both paths share the same post-merge clean-up:
##   1. Build a remap table (old vertex index → canonical survivor index).
##   2. Rewrite every [member GoBuildFace.vertex_indices] through the map.
##   3. Remove faces that became degenerate (< 3 distinct vertex indices).
##   4. Compact the vertex array to remove unreferenced vertices.
##   5. Call [method GoBuildMesh.rebuild_edges].
@tool
class_name WeldOperation
extends RefCounted

# Self-preloads — dependency order.
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")


## Merge the vertices at [param vertex_indices] on [param mesh] to their centroid.
##
## All indices in [param vertex_indices] are remapped to the canonical vertex
## (the one with the lowest index in the set).  That vertex's position is moved
## to the mean of the group.  Requires at least 2 valid indices; invalid
## (out-of-range) indices are silently skipped.
## [method GoBuildMesh.rebuild_edges] is called automatically on completion.
static func apply_merge(mesh: GoBuildMesh, vertex_indices: Array[int]) -> void:
	if mesh == null or vertex_indices.size() < 2:
		return

	# Filter to valid, unique indices.
	var valid: Array[int] = _unique_valid(mesh, vertex_indices)
	if valid.size() < 2:
		return

	# Compute centroid of the group.
	var centroid := Vector3.ZERO
	for vi: int in valid:
		centroid += mesh.vertices[vi]
	centroid /= float(valid.size())

	# The canonical survivor is the lowest index in the set.
	var canonical: int = valid[0]
	mesh.vertices[canonical] = centroid

	# Build remap: every other index in the group → canonical.
	var remap: Dictionary = {}
	for i: int in range(1, valid.size()):
		remap[valid[i]] = canonical

	_apply_remap_and_clean(mesh, remap)


## Merge all vertex pairs on [param mesh] within [param threshold] distance.
##
## Uses a union-find structure to group all vertices that are mutually within
## range.  Each group's canonical vertex (lowest index) is repositioned to the
## group centroid before remapping.
## [method GoBuildMesh.rebuild_edges] is called automatically on completion.
## Typical threshold: 0.0001 (clean up floating-point seams).
static func apply_weld_by_threshold(mesh: GoBuildMesh, threshold: float = 0.0001) -> void:
	if mesh == null or mesh.vertices.size() < 2:
		return

	var n: int = mesh.vertices.size()
	var parent: Array[int] = []
	parent.resize(n)
	for i: int in n:
		parent[i] = i

	var t_sq: float = threshold * threshold
	for i: int in n:
		for j: int in range(i + 1, n):
			if mesh.vertices[i].distance_squared_to(mesh.vertices[j]) <= t_sq:
				_union(parent, i, j)

	# Group members by canonical root.
	var groups: Dictionary = {}   # root → Array[int]
	for i: int in n:
		var root: int = _find(parent, i)
		if not groups.has(root):
			groups[root] = [] as Array
		(groups[root] as Array).append(i)

	# For groups larger than 1: move canonical to centroid, build remap.
	var remap: Dictionary = {}
	for root: int in groups:
		var members: Array = groups[root]
		if members.size() < 2:
			continue
		# Canonical = lowest index in the group (union-find root may not be lowest).
		var sorted_m: Array = members.duplicate()
		sorted_m.sort()
		var canonical: int = sorted_m[0]
		var centroid := Vector3.ZERO
		for vi: int in sorted_m:
			centroid += mesh.vertices[vi]
		centroid /= float(sorted_m.size())
		mesh.vertices[canonical] = centroid
		for i: int in range(1, sorted_m.size()):
			remap[sorted_m[i]] = canonical

	if remap.is_empty():
		return  # Nothing to merge.

	_apply_remap_and_clean(mesh, remap)


# ---------------------------------------------------------------------------
# Shared post-merge clean-up
# ---------------------------------------------------------------------------

## Apply [param remap] to all face vertex indices, remove degenerate faces,
## compact the vertex array, and rebuild edges.
##
## [param remap] maps old vertex index → canonical survivor index.
## Vertices not in the map are left unchanged.
static func _apply_remap_and_clean(mesh: GoBuildMesh, remap: Dictionary) -> void:
	# Rewrite face indices through the remap.
	for face: GoBuildFace in mesh.faces:
		for k: int in face.vertex_indices.size():
			var old_vi: int = face.vertex_indices[k]
			if remap.has(old_vi):
				face.vertex_indices[k] = remap[old_vi]

	# Remove degenerate faces: any face where the set of distinct vertex indices
	# has fewer than 3 elements is no longer a valid polygon.
	var new_faces: Array[GoBuildFace] = []
	for face: GoBuildFace in mesh.faces:
		if _has_enough_distinct_verts(face):
			new_faces.append(face)
	mesh.faces = new_faces

	_compact_vertices(mesh)
	mesh.rebuild_edges()


## Returns true when [param face] has at least 3 distinct vertex indices.
static func _has_enough_distinct_verts(face: GoBuildFace) -> bool:
	var seen: Dictionary = {}
	for vi: int in face.vertex_indices:
		seen[vi] = true
	return seen.size() >= 3


## Remove unreferenced vertices and remap [member GoBuildFace.vertex_indices].
## Identical to the compact step in DeleteOperation.
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


# ---------------------------------------------------------------------------
# Union-find helpers
# ---------------------------------------------------------------------------

static func _find(parent: Array[int], i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]   # Path compression (halving).
		i = parent[i]
	return i


static func _union(parent: Array[int], a: int, b: int) -> void:
	var ra: int = _find(parent, a)
	var rb: int = _find(parent, b)
	if ra != rb:
		# Always attach the higher root to the lower so the canonical root
		# is also the lowest index in the group.
		if ra < rb:
			parent[rb] = ra
		else:
			parent[ra] = rb


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Return sorted unique valid vertex indices from [param indices].
static func _unique_valid(mesh: GoBuildMesh, indices: Array[int]) -> Array[int]:
	var seen: Dictionary = {}
	for vi: int in indices:
		if vi >= 0 and vi < mesh.vertices.size():
			seen[vi] = true
	var result: Array[int] = []
	result.assign(seen.keys())
	result.sort()
	return result
