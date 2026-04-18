## Bevel edge(s) operation for [GoBuildMesh].
##
## Replaces each selected edge with a bevelled strip of [param segments] quads
## by sliding the edge endpoints a distance of [param width] along the adjacent
## face edges, then filling the gap with new geometry.
##
## Current implementation supports [param segments] = 1 (single bevel face per
## selected edge).  Multi-segment support is deferred to a later pass.
##
## Algorithm for each selected edge [code](va, vb)[/code]:
##   For every face adjacent to the edge:
##     1. Find the neighbour of [code]va[/code] in the face ring that is NOT
##        [code]vb[/code] — the edge may be traversed forward or backward in
##        different adjacent faces, so simply taking "prev" is wrong when
##        "prev" is [code]vb[/code] itself.  Use "next" if "prev" == [code]vb[/code].
##     2. Do the same for [code]vb[/code]: find the neighbour that is NOT
##        [code]va[/code].
##     3. Place new vertices [code]na[/code] and [code]nb[/code] at distance
##        [param width] from [code]va[/code] and [code]vb[/code] along those
##        directions.
##     4. Replace [code]va[/code] / [code]vb[/code] in the face with
##        [code]na[/code] / [code]nb[/code].
##   Add one bevel face spanning [code]na_A, na_B, nb_B, nb_A[/code] across
##   the gap (where A and B are contributions from the two adjacent faces of
##   the original edge).
##
## Edges sharing a vertex with another selected edge use the same slid vertex
## so bevelling two connected edges joins cleanly at their shared corner.
##
## [method GoBuildMesh.rebuild_edges] is called automatically inside
## [method apply].
@tool
class_name BevelOperation
extends RefCounted

# Self-preloads — dependency order.
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")


## Bevel the edges at [param edge_indices] on [param mesh] by [param width].
##
## [param width] is in local mesh-space units and must be > 0.
## [param segments] is reserved for future multi-cut support; only 1 is used now.
## Invalid or degenerate edge indices are silently skipped.
## [method GoBuildMesh.rebuild_edges] is called automatically on completion.
static func apply(
		mesh: GoBuildMesh,
		edge_indices: Array[int],
		width: float,
		_segments: int = 1,
) -> void:
	if mesh == null or edge_indices.is_empty() or width <= 0.0:
		return

	var valid: Array[int] = []
	var seen: Dictionary = {}
	for ei: int in edge_indices:
		if ei >= 0 and ei < mesh.edges.size() and not seen.has(ei):
			seen[ei] = true
			valid.append(ei)
	if valid.is_empty():
		return

	# ── Phase 1: compute slid positions for every (original_vertex, face) ──
	#
	# Key: "%d_%d" % [original_vertex_index, face_index]
	# Value: new vertex index in mesh.vertices for the slid copy.
	#
	# Doing this as a first pass before modifying any face prevents re-entrant
	# index shifting when two selected edges share a vertex.
	var slid: Dictionary = {}

	# Parallel to slid: records the "slide-direction" neighbor vertex for each
	# (original_vertex, face) pair.  Used by Phase 2b to determine the correct
	# insertion order when expanding a cap face's corner vertex.
	var nbr: Dictionary = {}

	# Track which faces need new bevel quads at the end.
	# Each entry is [va_idx, vb_idx, fi0, fi1] where fi0/fi1 are the two
	# adjacent face indices (fi1 may be -1 for a boundary edge).
	var bevel_quads: Array = []

	for ei: int in valid:
		var edge: GoBuildEdge = mesh.edges[ei]
		var va: int = edge.vertex_a
		var vb: int = edge.vertex_b
		var adj_faces: Array[int] = edge.face_indices

		for fi: int in adj_faces:
			var face: GoBuildFace = mesh.faces[fi]
			var vc: int = face.vertex_indices.size()

			# Locate va and vb positions within this face's vertex ring.
			var pos_a: int = -1
			var pos_b: int = -1
			for k: int in vc:
				if face.vertex_indices[k] == va:
					pos_a = k
				if face.vertex_indices[k] == vb:
					pos_b = k

			# Edge might not appear in this face (defensive guard).
			if pos_a == -1 or pos_b == -1:
				continue

			# Slide va: find the neighbour of va that is NOT vb.
			# The edge may appear as va→vb OR vb→va in the face ring, so
			# "prev of va" could be vb itself when the half-edge is reversed.
			var prev_a: int = face.vertex_indices[(pos_a - 1 + vc) % vc]
			var next_a: int = face.vertex_indices[(pos_a + 1) % vc]
			var neighbor_a: int = prev_a if prev_a != vb else next_a
			var dir_a: Vector3 = (mesh.vertices[neighbor_a] - mesh.vertices[va]).normalized()

			# Slide vb: find the neighbour of vb that is NOT va.
			var next_b: int = face.vertex_indices[(pos_b + 1) % vc]
			var prev_b: int = face.vertex_indices[(pos_b - 1 + vc) % vc]
			var neighbor_b: int = next_b if next_b != va else prev_b
			var dir_b: Vector3 = (mesh.vertices[neighbor_b] - mesh.vertices[vb]).normalized()

			var key_a: String = "%d_%d" % [va, fi]
			var key_b: String = "%d_%d" % [vb, fi]

			# Always record the slide-direction neighbors regardless of whether
			# the slid vertex was already computed (needed by Phase 2b).
			nbr[key_a] = neighbor_a
			nbr[key_b] = neighbor_b

			if not slid.has(key_a):
				var new_idx: int = mesh.vertices.size()
				mesh.vertices.append(mesh.vertices[va] + dir_a * width)
				slid[key_a] = new_idx

			if not slid.has(key_b):
				var new_idx: int = mesh.vertices.size()
				mesh.vertices.append(mesh.vertices[vb] + dir_b * width)
				slid[key_b] = new_idx

		# Record the pair for bevel-quad creation (phase 3).
		bevel_quads.append([va, vb, adj_faces])

	# ── Phase 2: replace va/vb with their slid counterparts in every face ──
	# We iterate over all faces so that faces adjacent to two selected edges
	# (sharing a vertex) get both substitutions applied in one pass.
	for fi: int in mesh.faces.size():
		var face: GoBuildFace = mesh.faces[fi]
		for k: int in face.vertex_indices.size():
			var vi: int = face.vertex_indices[k]
			var key: String = "%d_%d" % [vi, fi]
			if slid.has(key):
				face.vertex_indices[k] = slid[key]

	# ── Phase 2b: expand cap faces ─────────────────────────────────────────
	# Any face that is NOT fi0/fi1 but still contains va or vb (e.g. the top
	# or bottom face of a cube) must have that corner vertex replaced in-place
	# by the two slid copies, turning the N-gon into an (N+1)-gon.
	for entry in bevel_quads:
		var va: int  = entry[0]
		var vb: int  = entry[1]
		var flist: Array = entry[2]
		if flist.size() < 2:
			continue
		var fi0: int = flist[0]
		var fi1: int = flist[1]
		var na0: int = slid.get("%d_%d" % [va, fi0], -1)
		var na1: int = slid.get("%d_%d" % [va, fi1], -1)
		var nb0: int = slid.get("%d_%d" % [vb, fi0], -1)
		var nb1: int = slid.get("%d_%d" % [vb, fi1], -1)
		if na0 == -1 or na1 == -1 or nb0 == -1 or nb1 == -1:
			continue
		var N_a0: int = nbr.get("%d_%d" % [va, fi0], -1)
		var N_a1: int = nbr.get("%d_%d" % [va, fi1], -1)
		var N_b0: int = nbr.get("%d_%d" % [vb, fi0], -1)
		var N_b1: int = nbr.get("%d_%d" % [vb, fi1], -1)
		if N_a0 == -1 or N_a1 == -1 or N_b0 == -1 or N_b1 == -1:
			continue
		var skip: Dictionary = {fi0: true, fi1: true}
		_expand_endpoint(mesh, va, na0, N_a0, na1, N_a1, skip)
		_expand_endpoint(mesh, vb, nb0, N_b0, nb1, N_b1, skip)

	# ── Phase 3: add bevel faces ────────────────────────────────────────────
	for entry in bevel_quads:
		var va: int = entry[0]
		var vb: int = entry[1]
		var flist: Array = entry[2]
		_add_bevel_face(mesh, va, vb, flist, slid)

	# ── Phase 4: remove orphaned vertices ───────────────────────────────────
	# The original va/vb vertices are no longer referenced by any face after
	# Phases 2 and 2b.  Compact the vertex array and remap face indices so
	# there are no gaps or dangling indices.
	_compact_vertices(mesh)

	mesh.rebuild_edges()


## Replace [param v_orig] in every face (outside [param skip]) with the two
## slid copies [param n0]/[param n1] in CCW-preserving order.
##
## The insertion order is determined by matching [param N0]/[param N1] (the
## slide-direction neighbours recorded in Phase 1) against the existing ring
## neighbour that precedes [param v_orig].  The slid copy whose direction
## neighbour is that predecessor is inserted first (preserving adjacency).
## Modifies [member GoBuildFace.vertex_indices] and [member GoBuildFace.uvs]
## in-place using [method Array.remove_at] and [method Array.insert] to avoid
## any typed-Array assignment issues in GDScript 4.
static func _expand_endpoint(
		mesh: GoBuildMesh,
		v_orig: int,
		n0: int, N0: int,
		n1: int, N1: int,
		skip: Dictionary,
) -> void:
	for fi: int in mesh.faces.size():
		if skip.has(fi):
			continue
		var face: GoBuildFace = mesh.faces[fi]
		var pos: int = face.vertex_indices.find(v_orig)
		if pos == -1:
			continue
		var vc: int = face.vertex_indices.size()
		var prev_v: int = face.vertex_indices[(pos - 1 + vc) % vc]
		# Determine insertion order: the copy that slides toward prev_v's
		# direction is placed first so it stays adjacent to prev_v in the ring.
		var ins_first: int
		var ins_second: int
		if prev_v == N0:
			ins_first = n0; ins_second = n1
		elif prev_v == N1:
			ins_first = n1; ins_second = n0
		else:
			# Fallback: pick by distance from prev_v to each direction neighbour.
			if mesh.vertices[N0].distance_squared_to(mesh.vertices[prev_v]) \
					< mesh.vertices[N1].distance_squared_to(mesh.vertices[prev_v]):
				ins_first = n0; ins_second = n1
			else:
				ins_first = n1; ins_second = n0
		# In-place splice on Array[int] — avoids untyped-Array assignment.
		face.vertex_indices.remove_at(pos)
		face.vertex_indices.insert(pos, ins_second)
		face.vertex_indices.insert(pos, ins_first)
		# Mirror the expansion in the UV array (duplicate the original UV).
		if face.uvs.size() == vc:
			var uv: Vector2 = face.uvs[pos]
			face.uvs.remove_at(pos)
			face.uvs.insert(pos, uv)
			face.uvs.insert(pos, uv)


## Create the bevel quad spanning the slid vertices of the two adjacent faces.
##
## The correct winding depends on the order that [method GoBuildMesh.rebuild_edges]
## placed the two faces in [member GoBuildEdge.face_indices], so the strip
## normal is verified against the sum of the two adjacent face normals
## (both of which already have their correct outward orientation after Phase 2).
## If the initial winding [na0, nb0, nb1, na1] produces an inward-pointing
## normal it is flipped to [na0, na1, nb1, nb0].
## For a boundary edge (only one adjacent face) no bevel face is added.
static func _add_bevel_face(
		mesh: GoBuildMesh,
		va: int,
		vb: int,
		adj_faces: Array,
		slid: Dictionary,
) -> void:
	if adj_faces.size() < 2:
		return   # Boundary edge — no gap to fill.

	var fi0: int = adj_faces[0]
	var fi1: int = adj_faces[1]

	var key_a0: String = "%d_%d" % [va, fi0]
	var key_b0: String = "%d_%d" % [vb, fi0]
	var key_a1: String = "%d_%d" % [va, fi1]
	var key_b1: String = "%d_%d" % [vb, fi1]

	if not (slid.has(key_a0) and slid.has(key_b0) and slid.has(key_a1) and slid.has(key_b1)):
		return   # Should not happen for valid edges — guard defensively.

	var na0: int = slid[key_a0]
	var nb0: int = slid[key_b0]
	var na1: int = slid[key_a1]
	var nb1: int = slid[key_b1]

	var bevel := GoBuildFace.new()
	bevel.vertex_indices = [na0, nb0, nb1, na1]
	bevel.uvs = [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]
	bevel.material_index = mesh.faces[fi0].material_index
	bevel.smooth_group   = mesh.faces[fi0].smooth_group

	# Verify winding: the strip normal must agree with the outward direction
	# indicated by the sum of the (already-updated) adjacent face normals.
	var hint: Vector3 = \
			mesh.compute_face_normal(mesh.faces[fi0]) + \
			mesh.compute_face_normal(mesh.faces[fi1])
	if hint.length_squared() > 1e-8 \
			and mesh.compute_face_normal(bevel).dot(hint) < 0.0:
		bevel.vertex_indices = [na0, na1, nb1, nb0]

	mesh.faces.append(bevel)


## Remove every vertex not referenced by any face and remap face indices.
## Identical in purpose to WeldOperation._compact_vertices — duplicated here
## to avoid a cross-operation dependency.
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
