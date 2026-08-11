## Dissolve geometry operation for [GoBuildMesh].
##
## Dissolves selected edges or vertices without leaving holes.
##
##   [method dissolve_edges]   — merge the two faces sharing each edge into one.
##   [method dissolve_vertices] — remove a vertex and merge its surrounding faces.
##
## Dissolve is the inverse of edge split or vertex subdivision: it simplifies
## topology. Unlike [DeleteOperation], dissolve does not create holes — it
## merges adjacent faces to fill the gap left by the removed element.
##
## Boundary edges (edges with only one adjacent face) cannot be dissolved and
## are silently skipped. Similarly, vertices at a corner where dissolving
## would create a degenerate face are skipped.
##
## [method GoBuildMesh.rebuild_edges] is called automatically inside each entry
## point so the derived edge list stays in sync.
@tool
class_name DissolveOperation
extends RefCounted

# Self-preloads — dependency order.
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _DEBUG_SCRIPT := preload("res://addons/go_build/core/go_build_debug.gd")


## Dissolve the edges at [param edge_indices] on [param mesh].
##
## For each edge that has exactly two adjacent faces, the two faces are merged
## into one. The merged face inherits the material, smooth group, and UV
## projection mode of the first adjacent face. Its vertex ring is the union of
## both faces' vertex rings minus the two vertices of the dissolved edge.
##
## Boundary edges (only one adjacent face) are silently skipped.
## [method GoBuildMesh.rebuild_edges] is called on completion.
static func dissolve_edges(mesh: GoBuildMesh, edge_indices: Array[int]) -> void:
	if mesh == null or edge_indices.is_empty():
		return
	if mesh.edges.is_empty():
		mesh.rebuild_edges()

	# Collect edges to dissolve and verify each has exactly 2 adjacent faces.
	var edges_to_dissolve: Array[int] = []
	for ei: int in edge_indices:
		if ei < 0 or ei >= mesh.edges.size():
			continue
		if mesh.edges[ei].face_indices.size() == 2:
			edges_to_dissolve.append(ei)

	if edges_to_dissolve.is_empty():
		return

	GoBuildDebug.log("[DissolveEdges] dissolving %d edges" % edges_to_dissolve.size())

	# Build face pairs to merge. Each pair is [fi_a, fi_b].
	# A face may appear in multiple pairs (dissolving multiple edges of the
	# same face). We process one pair at a time because each merge changes
	# face indices.
	# ponytail: process edges one at a time, rebuilding between each, to
	# keep index consistency simple. For typical dissolve counts (< 10), this
	# is fine. Batch dissolve can be optimized later if throughput matters.
	for ei: int in edges_to_dissolve:
		if ei >= mesh.edges.size():
			continue
		var edge: GoBuildEdge = mesh.edges[ei]
		if edge.face_indices.size() != 2:
			continue
		_merge_face_pair(mesh, edge.face_indices[0], edge.face_indices[1],
				edge.vertex_a, edge.vertex_b)

	mesh.rebuild_edges()


## Dissolve the vertices at [param vertex_indices] on [param mesh].
##
## For each vertex, all faces that reference it are merged into one face. The
## dissolved vertex is removed from the merged face's vertex ring.
##
## Vertices at a corner (only 2 faces meeting, forming an L-shape) are skipped
## because dissolving would produce a degenerate 2-vertex face.
## [method GoBuildMesh.rebuild_edges] is called on completion.
static func dissolve_vertices(mesh: GoBuildMesh, vertex_indices: Array[int]) -> void:
	if mesh == null or vertex_indices.is_empty():
		return
	if mesh.edges.is_empty():
		mesh.rebuild_edges()

	# Expand through coincident groups.
	var expanded: Dictionary = {}
	for vi: int in vertex_indices:
		if vi < 0 or vi >= mesh.vertices.size():
			continue
		for cvi: int in mesh.get_coincident_vertices(vi):
			expanded[cvi] = true

	if expanded.is_empty():
		return

	# Collect vertices to dissolve, filtering out boundary vertices that can't
	# produce a valid result.
	var verts_to_dissolve: Array[int] = []
	for vi: int in expanded:
		verts_to_dissolve.append(vi)

	# ponytail: process vertices one at a time, rebuilding face lookups between
	# each, because _dissolve_single_vertex mutates the face list. For typical
	# dissolve counts (< 10), this is fine.
	for vi: int in verts_to_dissolve:
		if vi >= mesh.vertices.size():
			continue
		# Re-collect face indices each time because the face list changes
		# after each dissolve.
		var face_indices: Array[int] = []
		for fi: int in mesh.faces.size():
			if mesh.faces[fi].vertex_indices.has(vi):
				face_indices.append(fi)

		if face_indices.size() < 3:
			continue

		GoBuildDebug.log("[DissolveVertex] dissolving vi=%d faces=%s" % [vi, str(face_indices)])
		_dissolve_single_vertex(mesh, vi, face_indices)

	mesh.compact_vertices()
	mesh.rebuild_edges()


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


## Merge two faces sharing an edge into one face.
##
## The merged face's vertex ring walks around the combined boundary of both faces,
## skipping the shared edge vertices va and vb. The result is a single face
## covering both original faces with correct CCW winding.
static func _merge_face_pair(
		mesh: GoBuildMesh,
		fi_a: int,
		fi_b: int,
		va: int,
		vb: int,
) -> void:
	if fi_a == fi_b:
		return
	if fi_a >= mesh.faces.size() or fi_b >= mesh.faces.size():
		return

	var face_a: GoBuildFace = mesh.faces[fi_a]
	var face_b: GoBuildFace = mesh.faces[fi_b]
	var ring_a: Array[int] = face_a.vertex_indices
	var ring_b: Array[int] = face_b.vertex_indices
	var uvs_a: Array[Vector2] = face_a.uvs
	var uvs_b: Array[Vector2] = face_b.uvs
	var size_a: int = ring_a.size()
	var size_b: int = ring_b.size()

	# Ensure va is in face_a (swap labels if needed).
	if ring_a.find(va) == -1:
		var tmp: int = va
		va = vb
		vb = tmp

	# Find va and vb in face_a.
	var va_in_a: int = ring_a.find(va)
	var vb_in_a: int = ring_a.find(vb)
	if va_in_a == -1 or vb_in_a == -1:
		return
	# Verify adjacency in face_a.
	var diff: int = (vb_in_a - va_in_a + size_a) % size_a
	if diff != 1 and diff != size_a - 1:
		return

	# Find va in face_b.
	var va_in_b: int = ring_b.find(va)
	if va_in_b == -1:
		return

	# In face_a, walk from the vertex after vb, around the ring, to the vertex
	# before va. This gives us face_a's non-shared boundary in CCW order.
	# face_a: ... va → vb → X → ... → Y → va ...
	#   We want X...Y (everything between vb and va, exclusive).
	var merged_ring: Array[int] = []
	var merged_uvs: Array[Vector2] = []
	var after_vb: int = (vb_in_a + 1) % size_a
	var i: int = after_vb
	while ring_a[i] != va:
		merged_ring.append(ring_a[i])
		if uvs_a.size() == size_a:
			merged_uvs.append(uvs_a[i])
		else:
			merged_uvs.append(Vector2.ZERO)
		i = (i + 1) % size_a

	# In face_b, walk from the vertex after va, around the ring, to the vertex
	# before vb. This gives us face_b's non-shared boundary in CCW order.
	# face_b has the same edge va-vb but traversed in the opposite direction.
	# Starting from va_in_b, the vertex BEFORE va (going CCW) is adjacent to vb
	# on the opposite side from face_a.
	var after_va_b: int = (va_in_b + 1) % size_b
	var j: int = after_va_b
	while ring_b[j] != vb:
		merged_ring.append(ring_b[j])
		if uvs_b.size() == size_b:
			merged_uvs.append(uvs_b[j])
		else:
			merged_uvs.append(Vector2.ZERO)
		j = (j + 1) % size_b

	if merged_ring.size() < 3:
		return

	# Verify winding: the merged face normal should point in roughly the same
	# direction as the original faces' normals. If reversed, flip the ring.
	var merged_normal := Vector3.ZERO
	for k: int in merged_ring.size():
		var cur: int = merged_ring[k]
		var nxt: int = merged_ring[(k + 1) % merged_ring.size()]
		var cur_v: Vector3 = mesh.vertices[cur]
		var nxt_v: Vector3 = mesh.vertices[nxt]
		merged_normal.x += (cur_v.y - nxt_v.y) * (cur_v.z + nxt_v.z)
		merged_normal.y += (cur_v.z - nxt_v.z) * (cur_v.x + nxt_v.x)
		merged_normal.z += (cur_v.x - nxt_v.x) * (cur_v.y + nxt_v.y)
	var ref_normal := mesh.compute_face_normal(face_a) + mesh.compute_face_normal(face_b)
	if ref_normal.length_squared() > 1e-8:
		ref_normal = ref_normal.normalized()
	if merged_normal.length_squared() > 1e-8 and ref_normal.length_squared() > 1e-8:
		if merged_normal.normalized().dot(ref_normal) < 0.0:
			merged_ring.reverse()
			merged_uvs.reverse()

	GoBuildDebug.log(
			"[MergeFacePair] fi_a=%d fi_b=%d va=%d vb=%d merged=%s"
			% [fi_a, fi_b, va, vb, str(merged_ring)])

	# Ensure UV count matches vertex count.
	while merged_uvs.size() < merged_ring.size():
		merged_uvs.append(Vector2.ZERO)
	if merged_uvs.size() > merged_ring.size():
		merged_uvs.resize(merged_ring.size())

	# Replace face_a with the merged face.
	var merged_face := GoBuildFace.new()
	merged_face.vertex_indices = merged_ring
	merged_face.uvs = merged_uvs
	merged_face.material_index = face_a.material_index
	merged_face.smooth_group = face_a.smooth_group
	merged_face.uv_projection_mode = face_a.uv_projection_mode
	merged_face.uv_scale = face_a.uv_scale
	merged_face.uv_offset = face_a.uv_offset
	merged_face.uv_seam_rotation = face_a.uv_seam_rotation

	mesh.faces[fi_a] = merged_face
	mesh.faces.remove_at(fi_b)
	mesh.compact_vertices()
	mesh.rebuild_edges()


## Dissolve a single vertex by merging all its adjacent faces.
##
## Walks around the boundary of the dissolved region, collecting every vertex
## on the boundary ring in correct CCW order. The dissolved vertex is removed,
## and all adjacent faces are replaced with a single merged face.
static func _dissolve_single_vertex(
		mesh: GoBuildMesh,
		vi: int,
		face_indices: Array[int],
) -> void:
	# Pick the starting face and find vi's position in it.
	var start_face: GoBuildFace = mesh.faces[face_indices[0]]
	var vi_local: int = start_face.vertex_indices.find(vi)
	if vi_local == -1:
		return
	var vc: int = start_face.vertex_indices.size()

	# The first "next" vertex: the vertex after vi in the starting face (CCW).
	var start_next: int = start_face.vertex_indices[(vi_local + 1) % vc]

	# Build the boundary ring by walking face-to-face around vi.
	# At each step, we know the edge (vi → current_next) and find the face
	# that contains this edge. Then we walk that face's boundary from
	# current_next to the vertex before vi (the "prev" of vi in that face),
	# collecting all intermediate vertices.
	var ring: Array[int] = []
	var safety: int = mesh.vertices.size() + mesh.faces.size()

	# Walk from current_next around to the "prev" of vi in each face,
	# collecting the arc between vi's two neighbours in that face.
	var current_next: int = start_next
	var current_prev: int = start_face.vertex_indices[(vi_local - 1 + vc) % vc]

	while true:
		if ring.size() > safety:
			return  # broken topology, bail

		# Find the face that contains edge (vi → current_next).
		var found: bool = false
		for fi: int in face_indices:
			if fi >= mesh.faces.size():
				continue
			var f: GoBuildFace = mesh.faces[fi]
			var vi_l: int = f.vertex_indices.find(vi)
			if vi_l == -1:
				continue
			var next_l: int = (vi_l + 1) % f.vertex_indices.size()
			if f.vertex_indices[next_l] == current_next:
				# Found the face. Walk its boundary from current_next to
				# the "prev" of vi, collecting intermediate vertices.
				var prev_l: int = (vi_l - 1 + f.vertex_indices.size()) % f.vertex_indices.size()
				var end_vertex: int = f.vertex_indices[prev_l]
				# Walk from next_l (which is current_next) around to prev_l.
				var k: int = next_l
				while true:
					var v: int = f.vertex_indices[k]
					if v == vi:
						# Skip the dissolved vertex itself.
						pass
					else:
						ring.append(v)
					if v == end_vertex:
						break
					k = (k + 1) % f.vertex_indices.size()
				current_next = end_vertex
				found = true
				break

		if not found:
			break
		if current_next == start_next:
			break

	# The ring wraps around to start_next, so remove the duplicate at the end
	# if the last entry equals start_next.
	if ring.size() > 0 and ring[ring.size() - 1] == start_next:
		ring.remove_at(ring.size() - 1)

	# Deduplicate consecutive identical vertices (can happen if two faces share
	# an edge that isn't the dissolved vertex).
	var deduped: Array[int] = []
	for idx: int in ring.size():
		if deduped.is_empty() or ring[idx] != deduped[deduped.size() - 1]:
			deduped.append(ring[idx])
	# Also check last vs first.
	if deduped.size() > 1 and deduped[0] == deduped[deduped.size() - 1]:
		deduped.remove_at(deduped.size() - 1)
	ring = deduped

	# Verify winding: the merged face normal should point in roughly the same
	# direction as the original faces' normals. If the ring is CW from outside,
	# the Newell normal will point inward. Flip the ring if needed.
	var merged_normal := Vector3.ZERO
	for k: int in ring.size():
		var cur: int = ring[k]
		var nxt: int = ring[(k + 1) % ring.size()]
		var cur_v: Vector3 = mesh.vertices[cur]
		var nxt_v: Vector3 = mesh.vertices[nxt]
		merged_normal.x += (cur_v.y - nxt_v.y) * (cur_v.z + nxt_v.z)
		merged_normal.y += (cur_v.z - nxt_v.z) * (cur_v.x + nxt_v.x)
		merged_normal.z += (cur_v.x - nxt_v.x) * (cur_v.y + nxt_v.y)
	var ref_normal := Vector3.ZERO
	for fi: int in face_indices:
		if fi < mesh.faces.size():
			ref_normal += mesh.compute_face_normal(mesh.faces[fi])
	if ref_normal.length_squared() > 1e-8:
		ref_normal = ref_normal.normalized()
	if merged_normal.length_squared() > 1e-8 and ref_normal.length_squared() > 1e-8:
		if merged_normal.normalized().dot(ref_normal) < 0.0:
			# Winding is flipped — reverse the ring.
			ring.reverse()

	GoBuildDebug.log("[DissolveVertex] vi=%d ring=%s" % [vi, str(ring)])

	if ring.size() < 3:
		return

	# Build the merged face with correct winding.
	var merged_face := GoBuildFace.new()
	merged_face.vertex_indices = ring
	merged_face.uvs = []
	merged_face.uvs.resize(ring.size())
	merged_face.uvs.fill(Vector2.ZERO)
	merged_face.material_index = mesh.faces[face_indices[0]].material_index
	merged_face.smooth_group = mesh.faces[face_indices[0]].smooth_group
	merged_face.uv_projection_mode = mesh.faces[face_indices[0]].uv_projection_mode
	merged_face.uv_scale = mesh.faces[face_indices[0]].uv_scale
	merged_face.uv_offset = mesh.faces[face_indices[0]].uv_offset
	merged_face.uv_seam_rotation = mesh.faces[face_indices[0]].uv_seam_rotation

	# Replace the first face with the merged face and remove the rest.
	mesh.faces[face_indices[0]] = merged_face
	# Remove the other faces in reverse order to keep indices valid.
	for i: int in range(face_indices.size() - 1, 0, -1):
		mesh.faces.remove_at(face_indices[i])

