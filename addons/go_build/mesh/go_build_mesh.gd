## The internal mesh data model for GoBuild.
##
## Holds a list of vertex positions, an array of [GoBuildFace] objects that
## reference those positions by index, and a derived edge list.
## Call [method bake] to convert to a Godot [ArrayMesh] for rendering.
##
## All modelling operations (extrude, bevel, etc.) operate on this resource
## and then call bake() to update the visible mesh.
@tool
class_name GoBuildMesh
extends Resource

# Self-preloads — dependency order.
# GoBuildFace and GoBuildEdge are referenced as type annotations throughout this
# script (Array[GoBuildFace], Array[GoBuildEdge], func params, typed locals).
# Without explicit preloads, Godot's alphabetical scan may parse this file before
# those classes are registered, causing "Could not find script" errors.
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT := preload("res://addons/go_build/mesh/go_build_edge.gd")

## All vertex positions. Faces reference these by index.
@export var vertices: Array[Vector3] = []

## All faces. Each [GoBuildFace] references vertex positions by index.
@export var faces: Array[GoBuildFace] = []

## Material slots. [code]faces[i].material_index[/code] indexes into this array.
## Slot 0 is always the default material (may be null).
@export var material_slots: Array[Material] = []

## Persisted set of hard edges, stored as canonical vertex-index pairs.
## Each [Vector2i] is [code]Vector2i(min_vi, max_vi)[/code] where [code]min_vi[/code]
## and [code]max_vi[/code] are vertex indices from [member vertices].
## The [member GoBuildEdge.is_hard] flag on each entry in [member edges] is set
## from this array whenever [method rebuild_edges] runs.
@export var hard_edge_pairs: Array[Vector2i] = []

## Derived edge list. Rebuilt via [method rebuild_edges] after face changes.
var edges: Array[GoBuildEdge] = []

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

## Adjacency caches — rebuilt by [method rebuild_edges] alongside [member edges].
##
## These provide O(1) lookups for topology queries that would otherwise require
## O(n) linear scans.  They are invalidated whenever faces change and must be
## rebuilt via [method rebuild_edges] before use.

## Maps vertex index → array of face indices containing that vertex.
var _vertex_to_faces: Dictionary = {}

## Maps vertex index → array of edge indices incident to that vertex.
var _vertex_to_edges: Dictionary = {}

## Maps face index → array of edge indices bordering that face.
## Parallel to [member faces]; [code]_face_to_edges[fi][/code] has the same
## count as [code]faces[fi].vertex_indices[/code] (one edge per side).
var _face_to_edges: Array = []

## Maps canonical edge key [code]"min_max"[/code] → edge index.
## Provides O(1) lookup for [method find_edge] instead of O(E) scan.
var _edge_lookup: Dictionary = {}


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
	_bake_into(array_mesh)
	return array_mesh


## Like [method bake] but clears and repopulates [param target] in place rather
## than allocating a new [ArrayMesh].  The caller retains the same object
## reference, so no property-setter notification fires on the owning node.
## Used by [method GoBuildMeshInstance.bake_preview] to avoid the Godot
## inspector update that re-assigning [member MeshInstance3D.mesh] causes.
func bake_into(target: ArrayMesh) -> void:
	target.clear_surfaces()
	_bake_into(target)


func _bake_into(array_mesh: ArrayMesh) -> void:
	if faces.is_empty():
		return

	# Pre-compute face normals for all faces once.
	var face_normals: Array[Vector3] = []
	face_normals.resize(faces.size())
	for i in faces.size():
		face_normals[i] = compute_face_normal(faces[i])

	# Assign smooth-region IDs.  Each region is a connected set of faces with
	# the same non-zero smooth_group joined through non-hard interior edges.
	# Faces in the same region share averaged per-vertex normals; hard edges and
	# smooth-group boundaries act as normal seams.
	var face_region: Array[int] = _compute_face_regions()

	# Accumulate smooth normals: vertex_index → { region_id: Vector3 (accumulated) }.
	var smooth_normals: Dictionary = {}
	for fi in faces.size():
		var region_id: int = face_region[fi]
		if region_id == -1:
			continue  # flat face — uses its own face normal
		var face: GoBuildFace = faces[fi]
		for vi in face.vertex_indices:
			if not smooth_normals.has(vi):
				smooth_normals[vi] = {}
			var gmap: Dictionary = smooth_normals[vi]
			gmap[region_id] = gmap.get(region_id, Vector3.ZERO) + face_normals[fi]

	for vi in smooth_normals:
		for rid in smooth_normals[vi]:
			smooth_normals[vi][rid] = (smooth_normals[vi][rid] as Vector3).normalized()

	# One surface per material index.
	for mat_idx in _collect_material_indices():
		var surface_arrays := _build_surface(mat_idx, face_normals, face_region, smooth_normals)
		if surface_arrays.is_empty():
			continue
		array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_arrays)
		var surf_idx: int = array_mesh.get_surface_count() - 1
		if mat_idx < material_slots.size() and material_slots[mat_idx] != null:
			array_mesh.surface_set_material(surf_idx, material_slots[mat_idx])

## Assign smooth-region IDs to faces via BFS over non-hard interior edges.
##
## Returns an [Array][int] parallel to [member faces]:
## [code]>= 0[/code] = smooth face (region index); [code]-1[/code] = flat face.
## Faces with the same region ID and a shared smooth vertex will average normals.
##
## Hard edges ([member GoBuildEdge.is_hard]) and smooth-group boundaries are
## treated as seams: no normal averaging crosses them.
func _compute_face_regions() -> Array[int]:
	var result: Array[int] = []
	result.resize(faces.size())
	result.fill(-1)

	if edges.is_empty():
		return result

	# Build face → adjacent edge indices for fast BFS traversal.
	var face_edge_map: Array = []
	face_edge_map.resize(faces.size())
	for fi in faces.size():
		face_edge_map[fi] = []
	for ei in edges.size():
		for fi in edges[ei].face_indices:
			face_edge_map[fi].append(ei)

	var next_region: int = 0
	for start_fi in faces.size():
		if faces[start_fi].smooth_group == 0:
			continue
		if result[start_fi] != -1:
			continue
		var sg: int = faces[start_fi].smooth_group
		var queue: Array[int] = [start_fi]
		result[start_fi] = next_region
		var qi: int = 0
		while qi < queue.size():
			var fi: int = queue[qi]
			qi += 1
			for ei: int in face_edge_map[fi]:
				if edges[ei].is_hard:
					continue
				for fi2: int in edges[ei].face_indices:
					if fi2 == fi:
						continue
					if result[fi2] != -1:
						continue
					if faces[fi2].smooth_group != sg:
						continue
					result[fi2] = next_region
					queue.append(fi2)
		next_region += 1

	return result

## Build packed vertex-position byte arrays for all material surfaces, in the
## same triangle fan order as [method _build_surface].
##
## Returns one [PackedByteArray] per surface (ordered by material index —
## same order as the surfaces in an [ArrayMesh] produced by [method bake]).
## Each byte array contains the raw float32 data for the triangle vertex
## positions ([code]PackedVector3Array.to_byte_array()[/code] layout: 12 bytes
## per [Vector3], x/y/z as little-endian float32).
##
## Used by [method GoBuildMeshInstance.bake_vertex_positions] to update only
## the vertex buffer of an existing [ArrayMesh] surface during a drag, avoiding
## the full mesh rebuild that [method bake] performs.  Normals, UVs, and the
## surface count are left unchanged — call [method bake] on commit to restore
## correct normals.
##
## Returns an empty array if there are no faces.
func build_vertex_position_buffers() -> Array[PackedByteArray]:
	var result: Array[PackedByteArray] = []
	if faces.is_empty():
		return result

	for mat_idx in _collect_material_indices():
		var verts := PackedVector3Array()
		for fi in faces.size():
			var face: GoBuildFace = faces[fi]
			if face.material_index != mat_idx:
				continue
			var vc: int = face.vertex_indices.size()
			# Fan triangulation in the same winding order as _build_surface.
			for tri in range(vc - 2):
				var local_idx: Array[int] = [0, tri + 2, tri + 1]
				for li in local_idx:
					verts.append(vertices[face.vertex_indices[li]])
		result.append(verts.to_byte_array())

	return result


## Return the sorted list of material indices present in [member faces].
## Extracted so [method bake] and [method build_vertex_position_buffers]
## iterate surfaces in the same deterministic order.
func _collect_material_indices() -> Array[int]:
	var mat_indices: Array[int] = []
	for face in faces:
		if not mat_indices.has(face.material_index):
			mat_indices.append(face.material_index)
	mat_indices.sort()
	return mat_indices


## Build the packed vertex/normal/UV arrays for a single material surface.
## Returns an empty Array if no faces use this material index.
## [param face_region] is the region-ID array from [method _compute_face_regions].
func _build_surface(
		mat_idx: int,
		face_normals: Array[Vector3],
		face_region: Array[int],
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

				# Normal: region-based smooth average, or flat face normal.
				var region_id: int = face_region[fi]
				if region_id != -1 \
						and smooth_normals.has(vi) \
						and smooth_normals[vi].has(region_id):
					norms.append(smooth_normals[vi][region_id])
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


## Compute the area of a face using the cross-product fan method.
## Works for convex polygons of any vertex count.
func compute_face_area(face: GoBuildFace) -> float:
	var vc: int = face.vertex_indices.size()
	if vc < 3:
		return 0.0
	var total: float = 0.0
	var v0: Vector3 = vertices[face.vertex_indices[0]]
	for i: int in range(1, vc - 1):
		var v1: Vector3 = vertices[face.vertex_indices[i]]
		var v2: Vector3 = vertices[face.vertex_indices[i + 1]]
		total += (v1 - v0).cross(v2 - v0).length() * 0.5
	return total


# ---------------------------------------------------------------------------
# Edge derivation
# ---------------------------------------------------------------------------

## Rebuild [member edges] from the current [member faces] data, then rebuild
## [member coincident_groups] so the two derived structures stay in sync.
## Call this after any operation that adds, removes, or modifies faces.
func rebuild_edges() -> void:
	edges.clear()
	_vertex_to_faces.clear()
	_vertex_to_edges.clear()
	_face_to_edges.clear()
	_edge_lookup.clear()
	# edge_map: canonical "min_max" key → index in edges array.
	var edge_map: Dictionary = {}

	# Build a fast lookup for persisted hard edges.
	var hard_set: Dictionary = {}
	for pair: Vector2i in hard_edge_pairs:
		hard_set[pair] = true

	# Pre-size _vertex_to_faces.
	for vi: int in vertices.size():
		_vertex_to_faces[vi] = []
		_vertex_to_edges[vi] = []

	# Pre-size _face_to_edges.
	_face_to_edges.resize(faces.size())
	for fi: int in faces.size():
		_face_to_edges[fi] = []
		# Also register each face's vertices in _vertex_to_faces.
		for vi: int in faces[fi].vertex_indices:
			(_vertex_to_faces[vi] as Array).append(fi)

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
				var ei: int = edge_map[key]
				(_face_to_edges[fi] as Array).append(ei)
				if not (_vertex_to_edges[va] as Array).has(ei):
					(_vertex_to_edges[va] as Array).append(ei)
				if not (_vertex_to_edges[vb] as Array).has(ei):
					(_vertex_to_edges[vb] as Array).append(ei)
			else:
				var ei: int = edges.size()
				var edge := GoBuildEdge.new()
				edge.vertex_a = va
				edge.vertex_b = vb
				edge.face_indices.append(fi)
				var pair_key := Vector2i(min(va, vb), max(va, vb))
				edge.is_hard = hard_set.has(pair_key)
				edge_map[key] = ei
				_edge_lookup[key] = ei
				edges.append(edge)
				(_face_to_edges[fi] as Array).append(ei)
				if not (_vertex_to_edges[va] as Array).has(ei):
					(_vertex_to_edges[va] as Array).append(ei)
				if not (_vertex_to_edges[vb] as Array).has(ei):
					(_vertex_to_edges[vb] as Array).append(ei)

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


## Return the axis-aligned bounding box of all vertices in local mesh space.
## Returns a zero-size [AABB] at the origin if there are no vertices.
func compute_aabb() -> AABB:
	if vertices.is_empty():
		return AABB()
	var mn := vertices[0]
	var mx := vertices[0]
	for v: Vector3 in vertices:
		mn = mn.min(v)
		mx = mx.max(v)
	return AABB(mn, mx - mn)


## Take a deep copy of the mesh state for undo/redo.
#
# ---------------------------------------------------------------------------
# Topology helpers
# ---------------------------------------------------------------------------

## Return the edge index of the edge connecting [param va] and [param vb],
## or -1 if no such edge exists.  Uses the O(1) [member _edge_lookup] cache.
func find_edge(va: int, vb: int) -> int:
	var key: String = "%d_%d" % [min(va, vb), max(va, vb)]
	if _edge_lookup.has(key):
		return int(_edge_lookup[key])
	return -1


## Return the indices of all faces that contain [param vi].
## Uses the O(1) [member _vertex_to_faces] cache.
func faces_of_vertex(vi: int) -> Array[int]:
	if _vertex_to_faces.has(vi):
		var arr: Array = _vertex_to_faces[vi]
		var result: Array[int] = []
		result.assign(arr)
		return result
	var result: Array[int] = []
	for fi: int in faces.size():
		if faces[fi].vertex_indices.has(vi):
			result.append(fi)
	return result


## Return the indices of all faces that contain both [param va] and [param vb].
## Uses the O(1) [member _edge_lookup] to find the edge, then returns its faces.
func faces_of_edge(va: int, vb: int) -> Array[int]:
	var ei: int = find_edge(va, vb)
	if ei != -1:
		var result: Array[int] = []
		result.assign(edges[ei].face_indices)
		return result
	var result: Array[int] = []
	for fi: int in faces.size():
		var vis: Array[int] = faces[fi].vertex_indices
		if vis.has(va) and vis.has(vb):
			result.append(fi)
	return result


## Return the edge indices bordering face [param fi].
## Uses the O(1) [member _face_to_edges] cache.
## Returns an empty array if the cache is not built.
func edges_of_face(fi: int) -> Array[int]:
	if fi >= 0 and fi < _face_to_edges.size():
		var arr: Array = _face_to_edges[fi]
		var result: Array[int] = []
		result.assign(arr)
		return result
	return []


## Return edge indices incident to vertex [param vi].
## Uses the O(1) [member _vertex_to_edges] cache.
func edges_of_vertex(vi: int) -> Array[int]:
	if _vertex_to_edges.has(vi):
		var arr: Array = _vertex_to_edges[vi]
		var result: Array[int] = []
		result.assign(arr)
		return result
	return []


## Return the valence (number of incident edges) of vertex [param vi].
## Uses the O(1) [member _vertex_to_edges] cache.
func vertex_valence(vi: int) -> int:
	if _vertex_to_edges.has(vi):
		return (_vertex_to_edges[vi] as Array).size()
	return 0


## Given a face that is a quad (4 vertices) and an edge index
## [param edge_idx] that belongs to that face, return the edge index
## of the opposite edge in the quad.  Returns -1 if the face is not
## a quad or the edge is not in the face.
##
## For a quad face with vertices [A, B, C, D] wound CCW and edge AB,
## the opposite edge is CD.  This is the key primitive for both
## loop walks and ring walks.
func opposite_edge_in_quad(fi: int, edge_idx: int) -> int:
	if fi < 0 or fi >= faces.size():
		return -1
	var face: GoBuildFace = faces[fi]
	if face.vertex_indices.size() != 4:
		return -1
	var ed: GoBuildEdge = edges[edge_idx]
	var vis: Array[int] = face.vertex_indices
	var pa: int = vis.find(ed.vertex_a)
	var pb: int = vis.find(ed.vertex_b)
	if pa == -1 or pb == -1:
		return -1
	if pa > pb:
		var tmp: int = pa
		pa = pb
		pb = tmp
	if (pa == 0 and pb == 1) or (pa == 1 and pb == 2) \
			or (pa == 2 and pb == 3):
		return find_edge(vis[(pa + 2) % 4], vis[(pb + 2) % 4])
	if pa == 0 and pb == 3:
		return find_edge(vis[1], vis[2])
	return -1


## Return the two ring-neighbours of [param vi] in [param face_idx],
## as [code][prev_vi, next_vi][/code] in the face's winding order.
## Returns [code][-1, -1][/code] if [param vi] is not in the face.
func face_neighbours_of(face_idx: int, vi: int) -> Array[int]:
	var vis: Array[int] = faces[face_idx].vertex_indices
	var k: int = vis.find(vi)
	if k == -1:
		return [-1, -1]
	var vc: int = vis.size()
	return [vis[(k - 1 + vc) % vc], vis[(k + 1) % vc]]


## Return all distinct ring-neighbours of [param vi] across all faces that
## contain it, optionally restricted to [param face_indices] when non-empty.
func vertex_neighbours(vi: int, face_indices: Array[int] = []) -> Array[int]:
	var result_set: Dictionary = {}
	var check_set: bool = not face_indices.is_empty()
	for fi: int in faces.size():
		if check_set and not face_indices.has(fi):
			continue
		var vis: Array[int] = faces[fi].vertex_indices
		var k: int = vis.find(vi)
		if k == -1:
			continue
		var vc: int = vis.size()
		result_set[vis[(k - 1 + vc) % vc]] = true
		result_set[(vis[(k + 1) % vc])]     = true
	var result: Array[int] = []
	for nb: int in result_set:
		result.append(nb)
	return result


## Return all distinct ring-neighbours of [param vi] that appear as a neighbour
## in EVERY face in [param face_indices].  Useful for finding a "shared edge"
## vertex at a T-junction.
func shared_vertex_neighbours(vi: int, face_indices: Array[int]) -> Array[int]:
	if face_indices.is_empty():
		return []
	# Count how many faces each neighbour appears in.
	var counts: Dictionary = {}
	for fi: int in face_indices:
		var vis: Array[int] = faces[fi].vertex_indices
		var k: int = vis.find(vi)
		if k == -1:
			continue
		var vc: int = vis.size()
		for delta: int in [-1, 1]:
			var nb: int = vis[(k + delta + vc) % vc]
			counts[nb] = counts.get(nb, 0) + 1
	var required: int = face_indices.size()
	var result: Array[int] = []
	for nb: int in counts:
		if counts[nb] >= required:
			result.append(nb)
	return result


# ---------------------------------------------------------------------------
# Undo / Redo snapshots
# ---------------------------------------------------------------------------
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
		nf.uv_projection_mode = face.uv_projection_mode
		nf.uv_scale = face.uv_scale
		nf.uv_offset = face.uv_offset
		nf.uv_seam_rotation = face.uv_seam_rotation
		faces_copy.append(nf)

	var slots_copy: Array[Material] = []
	slots_copy.assign(material_slots)

	var pairs_copy: Array[Vector2i] = []
	pairs_copy.assign(hard_edge_pairs)

	return {
		"vertices": verts_copy,
		"faces": faces_copy,
		"material_slots": slots_copy,
		"hard_edge_pairs": pairs_copy,
	}


## Restore the mesh from a snapshot produced by [method take_snapshot].
## Deep-copies face objects from the snapshot so subsequent operations cannot
## corrupt the snapshot's face references.  Automatically rebuilds the edge list.
func restore_snapshot(snapshot: Dictionary) -> void:
	vertices.assign(snapshot["vertices"])
	var restored_pairs: Array[Vector2i] = []
	restored_pairs.assign(snapshot.get("hard_edge_pairs", []))
	hard_edge_pairs = restored_pairs
	var fresh_faces: Array[GoBuildFace] = []
	for f: GoBuildFace in snapshot["faces"]:
		var nf := GoBuildFace.new()
		nf.vertex_indices.assign(f.vertex_indices)
		nf.uvs.assign(f.uvs)
		nf.uv2s.assign(f.uv2s)
		nf.material_index = f.material_index
		nf.smooth_group   = f.smooth_group
		nf.uv_projection_mode = f.uv_projection_mode
		nf.uv_scale = f.uv_scale
		nf.uv_offset = f.uv_offset
		nf.uv_seam_rotation = f.uv_seam_rotation
		fresh_faces.append(nf)
	faces.assign(fresh_faces)
	material_slots.assign(snapshot["material_slots"])
	rebuild_edges()

