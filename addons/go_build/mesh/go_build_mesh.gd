## The internal mesh data model for GoBuild.
##
## Holds a list of vertex positions, an array of [GoBuildFace] objects that
## reference those positions by index, and a derived edge list.
## Call [method bake] to convert to a Godot [ArrayMesh] for rendering.
##
## All modelling operations (extrude, bevel, etc.) operate on this resource
## and then call bake() to update the visible mesh.
class_name GoBuildMesh
extends Resource

## All vertex positions. Faces reference these by index.
var vertices: Array[Vector3] = []

## All faces. Each [GoBuildFace] references vertex positions by index.
var faces: Array[GoBuildFace] = []

## Derived edge list. Rebuilt via [method rebuild_edges] after face changes.
var edges: Array[GoBuildEdge] = []

## Material slots. [code]faces[i].material_index[/code] indexes into this array.
## Slot 0 is always the default material (may be null).
var material_slots: Array[Material] = []

## Coincident-vertex group map.  Parallel to [member vertices] — same size.
## [code]coincident_groups[i][/code] is the canonical group ID for vertex [code]i[/code],
## defined as the lowest vertex index in the coincident set.
## Vertices that share the same 3D position (within a small epsilon) belong to
## the same group and must be moved together during mesh editing operations.
##
## Generators like [CubeGenerator] create per-face vertex grids (via
## [MeshGeneratorUtils.add_quad_grid]) resulting in duplicate vertex positions
## at shared corners (e.g. 24 verts for a cube that has 8 unique corners).
## This map is how the drag system knows to move all copies of a corner together.
##
## Rebuilt automatically by [method rebuild_edges].  Empty until that call.
var coincident_groups: Array[int] = []


# ---------------------------------------------------------------------------
# Bake
# ---------------------------------------------------------------------------

## Convert this [GoBuildMesh] into a Godot [ArrayMesh].
##
## Each unique [code]material_index[/code] found in [member faces] becomes a
## separate surface on the returned mesh. Smooth groups are used to compute
## per-vertex normals; faces with [code]smooth_group == 0[/code] use their
## flat face normal for every vertex.
##
## Returns an empty [ArrayMesh] if there are no faces.
func bake() -> ArrayMesh:
	var array_mesh := ArrayMesh.new()
	if faces.is_empty():
		return array_mesh

	# Pre-compute face normals for all faces once.
	var face_normals: Array[Vector3] = []
	face_normals.resize(faces.size())
	for i in faces.size():
		face_normals[i] = compute_face_normal(faces[i])

	# Build smooth-group normal map:
	# vertex_index → { smooth_group_id: Vector3 (accumulated, then normalised) }
	# Only populated for faces with smooth_group > 0.
	var smooth_normals: Dictionary = {}
	for fi in faces.size():
		var face: GoBuildFace = faces[fi]
		if face.smooth_group == 0:
			continue
		for vi in face.vertex_indices:
			if not smooth_normals.has(vi):
				smooth_normals[vi] = {}
			var gmap: Dictionary = smooth_normals[vi]
			if not gmap.has(face.smooth_group):
				gmap[face.smooth_group] = Vector3.ZERO
			gmap[face.smooth_group] += face_normals[fi]

	for vi in smooth_normals:
		for gid in smooth_normals[vi]:
			smooth_normals[vi][gid] = (smooth_normals[vi][gid] as Vector3).normalized()

	# Find all material indices in use, sorted so surfaces are deterministic.
	var mat_indices: Array[int] = []
	for face in faces:
		if not mat_indices.has(face.material_index):
			mat_indices.append(face.material_index)
	mat_indices.sort()

	# One surface per material index.
	for mat_idx in mat_indices:
		var surface_arrays := _build_surface(mat_idx, face_normals, smooth_normals)
		if surface_arrays.is_empty():
			continue
		array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_arrays)
		var surf_idx: int = array_mesh.get_surface_count() - 1
		if mat_idx < material_slots.size() and material_slots[mat_idx] != null:
			array_mesh.surface_set_material(surf_idx, material_slots[mat_idx])

	return array_mesh


## Build the packed vertex/normal/UV arrays for a single material surface.
## Returns an empty Array if no faces use this material index.
func _build_surface(
		mat_idx: int,
		face_normals: Array[Vector3],
		smooth_normals: Dictionary,
) -> Array:
	var verts  := PackedVector3Array()
	var norms  := PackedVector3Array()
	var uvs_p  := PackedVector2Array()
	var uv2s_p := PackedVector2Array()

	for fi in faces.size():
		var face: GoBuildFace = faces[fi]
		if face.material_index != mat_idx:
			continue

		var fn: Vector3 = face_normals[fi]
		var vc: int = face.vertex_indices.size()

		# Fan triangulation from vertex 0.
		# Winding is reversed ([0, tri+2, tri+1]) so triangles are CW from
		# outside, which is the front-facing convention in Godot 4's Vulkan
		# renderer.  face.vertex_indices deliberately remains CCW-from-outside
		# so that compute_face_normal() (Newell) returns the correct outward
		# normal.
		for tri in range(vc - 2):
			var local_idx: Array[int] = [0, tri + 2, tri + 1]
			for li in local_idx:
				var vi: int = face.vertex_indices[li]
				verts.append(vertices[vi])

				# Normal: smooth group average or flat face normal.
				if face.smooth_group != 0 \
						and smooth_normals.has(vi) \
						and smooth_normals[vi].has(face.smooth_group):
					norms.append(smooth_normals[vi][face.smooth_group])
				else:
					norms.append(fn)

				# UV0 — default Vector2.ZERO if not set.
				uvs_p.append(face.uvs[li] if li < face.uvs.size() else Vector2.ZERO)

				# UV1 (lightmap) — default Vector2.ZERO if not set.
				uv2s_p.append(face.uv2s[li] if li < face.uv2s.size() else Vector2.ZERO)

	if verts.is_empty():
		return []

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]   = verts
	arrays[Mesh.ARRAY_NORMAL]   = norms
	arrays[Mesh.ARRAY_TEX_UV]   = uvs_p
	arrays[Mesh.ARRAY_TEX_UV2]  = uv2s_p
	return arrays


# ---------------------------------------------------------------------------
# Normals
# ---------------------------------------------------------------------------

## Compute the face normal using Newell's method.
## Robust for quads and convex n-gons; handles coplanar vertex sets.
func compute_face_normal(face: GoBuildFace) -> Vector3:
	var n := Vector3.ZERO
	var vc: int = face.vertex_indices.size()
	for i in vc:
		var cur: Vector3 = vertices[face.vertex_indices[i]]
		var nxt: Vector3 = vertices[face.vertex_indices[(i + 1) % vc]]
		n.x += (cur.y - nxt.y) * (cur.z + nxt.z)
		n.y += (cur.z - nxt.z) * (cur.x + nxt.x)
		n.z += (cur.x - nxt.x) * (cur.y + nxt.y)
	if n.length_squared() < 1e-8:
		return Vector3.UP
	return n.normalized()


# ---------------------------------------------------------------------------
# Edge derivation
# ---------------------------------------------------------------------------

## Rebuild [member edges] from the current [member faces] data, then rebuild
## [member coincident_groups] so the two derived structures stay in sync.
## Call this after any operation that adds, removes, or modifies faces.
func rebuild_edges() -> void:
	edges.clear()
	# edge_map: canonical "min_max" key → index in edges array.
	var edge_map: Dictionary = {}

	for fi in faces.size():
		var face: GoBuildFace = faces[fi]
		var vc: int = face.vertex_indices.size()
		for i in vc:
			var va: int = face.vertex_indices[i]
			var vb: int = face.vertex_indices[(i + 1) % vc]
			var key: String = "%d_%d" % [min(va, vb), max(va, vb)]
			if edge_map.has(key):
				var edge: GoBuildEdge = edges[edge_map[key]]
				if not edge.face_indices.has(fi):
					edge.face_indices.append(fi)
			else:
				var edge := GoBuildEdge.new()
				edge.vertex_a = va
				edge.vertex_b = vb
				edge.face_indices.append(fi)
				edge_map[key] = edges.size()
				edges.append(edge)

	rebuild_coincident_groups()


# ---------------------------------------------------------------------------
# Coincident vertex groups
# ---------------------------------------------------------------------------

## Rebuild [member coincident_groups] by detecting all vertex pairs that share
## the same 3D position (within [param epsilon]).
##
## The canonical group ID for each group is the lowest vertex index in that
## group, so [code]coincident_groups[i] == i[/code] means vertex [code]i[/code]
## is either unique or is the canonical representative of its group.
##
## Uses a union–find approach: O(n²) comparisons then one path-compression
## pass.  Acceptable for typical GoBuild mesh sizes (< 2 k vertices).
##
## Called automatically at the end of [method rebuild_edges].
func rebuild_coincident_groups(epsilon: float = 1e-5) -> void:
	var n: int = vertices.size()
	coincident_groups.resize(n)
	# Initialise: every vertex is its own group.
	for i: int in n:
		coincident_groups[i] = i

	var eps_sq: float = epsilon * epsilon
	for i: int in n:
		for j: int in range(i + 1, n):
			if vertices[i].distance_squared_to(vertices[j]) <= eps_sq:
				# Merge groups: replace every occurrence of the higher canonical
				# ID with the lower one so the invariant (canonical = lowest index)
				# is always maintained.
				var ci: int = coincident_groups[i]
				var cj: int = coincident_groups[j]
				if ci == cj:
					continue
				var lo: int = mini(ci, cj)
				var hi: int = maxi(ci, cj)
				for k: int in n:
					if coincident_groups[k] == hi:
						coincident_groups[k] = lo


## Return all vertex indices that share the same coincident group as
## [param vertex_index], including [param vertex_index] itself.
##
## Returns a single-element array if the vertex has no coincident partners,
## or if [member coincident_groups] has not yet been built.
func get_coincident_vertices(vertex_index: int) -> Array[int]:
	var result: Array[int] = []
	if coincident_groups.size() != vertices.size() or vertex_index >= vertices.size():
		result.append(vertex_index)
		return result
	var group_id: int = coincident_groups[vertex_index]
	for i: int in vertices.size():
		if coincident_groups[i] == group_id:
			result.append(i)
	return result


# ---------------------------------------------------------------------------
# Mesh operations
# ---------------------------------------------------------------------------

## Translate a set of vertices by [param delta] in local mesh space.
## [param vertex_indices] may contain duplicates — each unique index is moved once.
## Does not rebuild edges (topology is unchanged by translation).
func translate_vertices(vertex_indices: Array[int], delta: Vector3) -> void:
	for idx: int in vertex_indices:
		vertices[idx] += delta


## Return the mean position of [param vertex_indices] in local mesh space.
## Returns [constant Vector3.ZERO] if the array is empty.
func compute_centroid(vertex_indices: Array[int]) -> Vector3:
	if vertex_indices.is_empty():
		return Vector3.ZERO
	var sum := Vector3.ZERO
	for idx: int in vertex_indices:
		sum += vertices[idx]
	return sum / vertex_indices.size()


# ---------------------------------------------------------------------------
# Undo / Redo snapshots
# ---------------------------------------------------------------------------

## Take a deep copy of the mesh state for undo/redo.
## Store the returned Dictionary and pass it to [method restore_snapshot] to revert.
func take_snapshot() -> Dictionary:
	var verts_copy: Array[Vector3] = []
	verts_copy.assign(vertices)

	var faces_copy: Array[GoBuildFace] = []
	for face in faces:
		var nf := GoBuildFace.new()
		nf.vertex_indices.assign(face.vertex_indices)
		nf.uvs.assign(face.uvs)
		nf.uv2s.assign(face.uv2s)
		nf.material_index = face.material_index
		nf.smooth_group = face.smooth_group
		faces_copy.append(nf)

	var slots_copy: Array[Material] = []
	slots_copy.assign(material_slots)

	return {
		"vertices": verts_copy,
		"faces": faces_copy,
		"material_slots": slots_copy,
	}


## Restore the mesh from a snapshot produced by [method take_snapshot].
## Automatically rebuilds the edge list after restoring.
func restore_snapshot(snapshot: Dictionary) -> void:
	vertices.assign(snapshot["vertices"])
	faces.assign(snapshot["faces"])
	material_slots.assign(snapshot["material_slots"])
	rebuild_edges()

