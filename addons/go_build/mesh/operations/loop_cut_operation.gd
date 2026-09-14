## Loop cut operation for [GoBuildMesh].
##
## Inserts a full edge loop across a quad ring by adding one midpoint vertex on
## every edge that crosses the loop plane, then splitting each affected quad
## face into two new quads at the cut position.
##
## What counts as a "quad ring":
##   Starting from a selected edge [code](va, vb)[/code], the algorithm walks
##   the ring by stepping to the opposite edge of each quad face it encounters —
##   the "opposite" edge in a quad [v0, v1, v2, v3] with known edge [v0, v1] is
##   [v2, v3].  The ring terminates when it either closes back on the start edge
##   or reaches a boundary or non-quad face (no further traversal in that
##   direction).
##
## Cut position:
##   [param t] ∈ [0, 1] controls where between the two edge endpoints the new
##   vertex is inserted.  0.5 (the default) places the cut at the midpoint.
##
## Multiple edge selections:
##   When [param edge_indices] contains more than one edge, each selected edge
##   is treated as the seed for an independent ring walk.  Rings that overlap
##   (i.e. share a face that has already been cut) are skipped in subsequent
##   passes to avoid double-cutting a face.
##
## Non-quad faces:
##   Any face in the ring that is not a quad (vertex count ≠ 4) terminates the
##   ring walk in that direction without cutting the face.  Triangular or
##   n-gon faces are left unchanged.
##
## Edge topology is maintained incrementally: cut vertices are inserted into
## EVERY face ring containing the crossed edge via [method GoBuildMesh.split_edge]
## (no T-junctions), and rewritten faces go through
## [method GoBuildMesh.unregister_face] / [method GoBuildMesh.register_face].
@tool
class_name LoopCutOperation
extends RefCounted

# Self-preloads — dependency order.
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")


## Insert an edge loop seeded by the edges at [param edge_indices].
##
## [param t] is the fractional cut position along each edge (0 = vertex_a,
## 1 = vertex_b, 0.5 = midpoint).  Values outside [0, 1] are clamped.
## Invalid or out-of-range edge indices are silently skipped.
static func apply(
		mesh: GoBuildMesh,
		edge_indices: Array[int],
		t: float = 0.5,
) -> void:
	if mesh == null or edge_indices.is_empty():
		return

	t = clampf(t, 0.0, 1.0)

	# De-duplicate input edge seeds.
	var seeds: Array[int] = GoBuildMesh.unique_valid_indices(
			mesh.edges.size(), edge_indices)
	if seeds.is_empty():
		return

	# Tracks which face indices have already been cut so overlapping ring walks
	# (from multiple seed edges) do not split a face twice.
	var cut_faces: Dictionary = {}

	for seed_ei: int in seeds:
		var ring := _collect_ring(mesh, seed_ei, cut_faces)
		if ring.is_empty():
			continue
		_cut_ring(mesh, ring, t, cut_faces)

	# Reconcile: split_edge + register/unregister mutated rings and edges —
	# drop orphaned edge objects and refresh face refs (knife's pattern).
	mesh.compact_edges()
	mesh.refresh_edge_face_indices()
	mesh.validate_edge_topology()


# ---------------------------------------------------------------------------
# Ring collection
# ---------------------------------------------------------------------------

## Collect the quad ring started from [param seed_ei].
##
## Returns an Array of Dictionaries, each with keys:
##   face_idx  : int   — index into mesh.faces
##   va        : int   — ring-directed entry-edge vertex A
##   vb        : int   — ring-directed entry-edge vertex B
##   opp_va    : int   — ring-directed far-edge vertex A
##   opp_vb    : int   — ring-directed far-edge vertex B
##
## The seed edge is shared by at most two faces.
## [param half_a] walks from face_0 of the seed, [param half_b] walks from face_1
## so the two halves never duplicate a face.  For a closed ring, half_a already
## covers all faces; half_b is not run in that case.
static func _collect_ring(
		mesh: GoBuildMesh,
		seed_ei: int,
		already_cut: Dictionary,
) -> Array:
	var seed: GoBuildEdge = mesh.edges[seed_ei]

	# Identify the (up to) two faces that share the seed edge and are cuttable.
	var start_a: int = -1
	var start_b: int = -1
	for fi: int in seed.face_indices:
		var fvc: int = mesh.faces[fi].vertex_indices.size()
		if not already_cut.has(fi) and (fvc == 4 or fvc == 5):
			if start_a == -1:
				start_a = fi
			else:
				start_b = fi
				break

	if start_a == -1:
		return []

	# Walk from start_a in the va→vb ring direction.
	var half_a: Array = _walk_half(mesh, seed.vertex_a, seed.vertex_b, already_cut, start_a)
	if half_a.is_empty():
		return []

	# Detect a closed ring: the last entry's far edge is the seed edge itself,
	# meaning the walk looped back.  In that case half_a contains every face and
	# we must NOT run half_b (which would traverse all faces again, producing
	# duplicate entries that cause double-cuts and crashes).
	var last: Dictionary = half_a[half_a.size() - 1]
	var ova: int = last["opp_va"]
	var ovb: int = last["opp_vb"]
	var ring_closed: bool = (ova == seed.vertex_a and ovb == seed.vertex_b) \
			or (ova == seed.vertex_b and ovb == seed.vertex_a)

	if ring_closed or start_b == -1:
		return half_a

	# Open ring: walk from start_b in the vb→va direction to cover the other half.
	var half_b: Array = _walk_half(mesh, seed.vertex_b, seed.vertex_a, already_cut, start_b)

	# Combine: reversed half_b (walking toward seed) + half_a (walking away from seed).
	var combined: Array = []
	for i: int in range(half_b.size() - 1, -1, -1):
		combined.append(half_b[i])
	for entry in half_a:
		combined.append(entry)

	# Safety dedup in case both halves converged at the same terminal face.
	if combined.size() >= 2:
		if combined[0]["face_idx"] == combined[combined.size() - 1]["face_idx"]:
			combined.resize(combined.size() - 1)

	return combined


## Walk one half of the ring starting from a face containing edge (va, vb).
##
## Returns an Array of Dictionaries in walk order, each with keys:
##   face_idx  : int — index into mesh.faces
##   va        : int — entry-edge vertex A (ring-directed)
##   vb        : int — entry-edge vertex B (ring-directed)
##   opp_va    : int — far-edge vertex A (ring-directed; becomes next face's va)
##   opp_vb    : int — far-edge vertex B (ring-directed; becomes next face's vb)
##
## [param start_fi] is the face index to begin from — must be one of the faces
## sharing the seed edge (provided by [method _collect_ring]).
static func _walk_half(
		mesh: GoBuildMesh,
		va: int,
		vb: int,
		already_cut: Dictionary,
		start_fi: int,
) -> Array:
	var result: Array = []

	if start_fi == -1 \
			or already_cut.has(start_fi) \
			or (mesh.faces[start_fi].vertex_indices.size() != 4 \
			and mesh.faces[start_fi].vertex_indices.size() != 5):
		return result

	var cur_fi: int = start_fi
	var cur_va: int = va
	var cur_vb: int = vb
	var visited: Dictionary = {}

	while cur_fi != -1:
		if visited.has(cur_fi) or already_cut.has(cur_fi):
			break
		var face: GoBuildFace = mesh.faces[cur_fi]
		var vc_lc: int = face.vertex_indices.size()
		if vc_lc != 4 and vc_lc != 5:
			break

		# Locate cur_va in the face and determine walk direction.
		var pos_a: int = -1
		for k: int in vc_lc:
			if face.vertex_indices[k] == cur_va:
				var next_k: int = (k + 1) % vc_lc
				var prev_k: int = (k + vc_lc - 1) % vc_lc
				if face.vertex_indices[next_k] == cur_vb \
						or face.vertex_indices[prev_k] == cur_vb:
					pos_a = k
					break
		if pos_a == -1:
			break  # Degenerate — entry edge not found.

		var next_a: int = (pos_a + 1) % vc_lc
		var forward: bool = face.vertex_indices[next_a] == cur_vb

		# Compute the far-edge vertices.
		# For a quad (vc=4) the logic is unchanged.
		# For a 5-gon (vc=5, created by bevel endpoint):
		#   The "extra" vertex sits at the corner opposite the entry edge.
		#   We step vc-1 positions from the entry edge vertices to find
		#   the far edge (skipping the extra vertex on the far side).
		var opp_va: int
		var opp_vb: int
		if vc_lc == 4:
			if forward:
				opp_va = face.vertex_indices[(pos_a + 3) % 4]
				opp_vb = face.vertex_indices[(pos_a + 2) % 4]
			else:
				opp_va = face.vertex_indices[(pos_a + 1) % 4]
				opp_vb = face.vertex_indices[(pos_a + 2) % 4]
		else:
			# 5-gon: entry edge is pos_a→next_a (forward) or pos_a←next_a (backward).
			# Far edge is separated by 2 steps on each side.
			if forward:
				# entry: pos_a, pos_a+1; far: pos_a+4, pos_a+3
				opp_va = face.vertex_indices[(pos_a + 4) % 5]
				opp_vb = face.vertex_indices[(pos_a + 3) % 5]
			else:
				# entry: pos_a, pos_a-1; pos_a+1 is also part of entry.
				# far: pos_a+2, pos_a+3
				opp_va = face.vertex_indices[(pos_a + 1) % 5]
				opp_vb = face.vertex_indices[(pos_a + 2) % 5]

		visited[cur_fi] = true
		result.append({"face_idx": cur_fi, "va": cur_va, "vb": cur_vb,
				"opp_va": opp_va, "opp_vb": opp_vb})

		# opp_va/opp_vb become the entry edge for the next face.
		var opp_ei: int = mesh.find_edge(opp_va, opp_vb)
		if opp_ei == -1:
			break

		var opp_edge: GoBuildEdge = mesh.edges[opp_ei]
		var next_fi: int = -1
		for fi: int in opp_edge.face_indices:
			var fvc2: int = mesh.faces[fi].vertex_indices.size()
			if fi != cur_fi and not visited.has(fi) \
					and (fvc2 == 4 or fvc2 == 5) \
					and not already_cut.has(fi):
				next_fi = fi
				break

		cur_va = opp_va
		cur_vb = opp_vb
		cur_fi = next_fi

	return result


# ---------------------------------------------------------------------------
# Ring cutting
# ---------------------------------------------------------------------------

## Split each quad face in [param ring] at position [param t] along the entry edge.
##
## Each ring entry must have keys: face_idx, va, vb, opp_va, opp_vb.
## va→vb is the ring-directed entry edge; opp_va→opp_vb is the ring-directed
## far edge.  lerp(va, vb, t) and lerp(opp_va, opp_vb, t) are consistent across
## all faces so moving t moves the cut line uniformly around the ring.
##
## Cut vertices are created once per crossed edge and inserted into EVERY
## face ring containing that edge via [method GoBuildMesh.split_edge] —
## neighbouring faces outside the ring stay watertight (no T-junctions).
## Replacement faces are the two arcs of the (already split) ring between
## the two cut vertices, so winding and n-gon extras are preserved whatever
## the ring shape.
static func _cut_ring(
		mesh: GoBuildMesh,
		ring: Array,
		t: float,
		cut_faces: Dictionary,
) -> void:
	# Canonical edge key → cut vertex index.  Both faces sharing an edge
	# approach it with the same ring-directed t (adjacent ring entries hand
	# opp_va/opp_vb forward as va/vb); keys normalise vertex order so
	# opposite directions also dedupe.
	var cut_verts: Dictionary = {}

	for entry in ring:
		var fi: int      = entry["face_idx"]
		var va: int      = entry["va"]
		var vb: int      = entry["vb"]
		var ova: int     = entry["opp_va"]
		var ovb: int     = entry["opp_vb"]
		var face: GoBuildFace = mesh.faces[fi]

		# Entry-edge cut: lerp(va→vb, t); far-edge cut: lerp(opp_va→opp_vb, t).
		var m_entry := _get_or_create_cut_vertex(mesh, va, vb, t, cut_verts)
		var m_far := _get_or_create_cut_vertex(mesh, ova, ovb, t, cut_verts)

		# The entry/far edges are now split in the face's ring: … va m_entry vb …
		# and … ova m_far ovb ….  Split the ring into its two arcs at the cut
		# vertices; each arc is one replacement face (CCW preserved by
		# construction, 5-gon bevel extras land on the correct arc).
		var ring2: Array[int] = []
		ring2.assign(face.vertex_indices)
		var arc_a := _ring_arc(ring2, m_entry, m_far)
		var arc_b := _ring_arc(ring2, m_far, m_entry)

		var qa := GoBuildFace.new()
		var qb := GoBuildFace.new()
		qa.vertex_indices = arc_a
		qb.vertex_indices = arc_b
		# Interpolated UVs: cut vertices get lerp of their edge neighbours' UVs;
		# original ring vertices keep their slot UVs.
		for arc: Array[int] in [arc_a, arc_b]:
			var uvs: Array[Vector2] = []
			uvs.resize(arc.size())
			for k: int in arc.size():
				var vi: int = arc[k]
				if vi == m_entry or vi == m_far:
					var edge: Vector2i = _cut_vertex_edge(ring2, vi)
					var u_a: Vector2 = face.uvs[ring2.find(edge.x)] \
							if ring2.find(edge.x) < face.uvs.size() else Vector2.ZERO
					var u_b: Vector2 = face.uvs[ring2.find(edge.y)] \
							if ring2.find(edge.y) < face.uvs.size() else Vector2.ZERO
					uvs[k] = u_a.lerp(u_b, t)
				else:
					var slot: int = ring2.find(vi)
					uvs[k] = face.uvs[slot] if slot < face.uvs.size() else Vector2.ZERO
			if arc == arc_a:
				qa.uvs = uvs
			else:
				qb.uvs = uvs
		qa.material_index = face.material_index
		qa.smooth_group   = face.smooth_group
		qb.material_index = face.material_index
		qb.smooth_group   = face.smooth_group

		# Replace the face: detach from edge topology, write, re-register.
		mesh.unregister_face(fi)
		mesh.faces[fi] = qa
		mesh.register_face(fi)
		mesh.faces.append(qb)
		mesh.register_face(mesh.faces.size() - 1)
		cut_faces[fi] = true


## Walk [param ring] from [param from_vi] to [param to_vi] inclusive in ring
## order (both are ring members).
static func _ring_arc(ring: Array[int], from_vi: int, to_vi: int) -> Array[int]:
	var start: int = ring.find(from_vi)
	var end_i: int = ring.find(to_vi)
	if start == -1 or end_i == -1:
		return []
	var arc: Array[int] = []
	var k: int = start
	while true:
		arc.append(ring[k])
		if k == end_i:
			break
		k = (k + 1) % ring.size()
	return arc


## The pair of ring neighbours (in the pre-split order) that produced
## [param cut_vi] — used to interpolate its UV.  Returns the ring slots of
## the two neighbours as (prev_slot, next_slot).
static func _cut_vertex_edge(ring: Array[int], cut_vi: int) -> Vector2i:
	var pos: int = ring.find(cut_vi)
	var prev: int = ring[(pos - 1 + ring.size()) % ring.size()]
	var next: int = ring[(pos + 1) % ring.size()]
	return Vector2i(prev, next)


## Get (or create) the cut vertex on edge va→vb at ring-directed [param t].
## The vertex is inserted into EVERY face ring containing the edge
## ([method GoBuildMesh.split_edge]) so neighbours stay watertight.
## Keys are canonical (sorted pair + t) — opposite ring directions map to
## the same 3D position via lerp symmetry, so they share the vertex.
static func _get_or_create_cut_vertex(
		mesh: GoBuildMesh,
		va: int,
		vb: int,
		t: float,
		cut_verts: Dictionary,
) -> int:
	var key := "%d_%d_%.6f" % [mini(va, vb), maxi(va, vb), t]
	if cut_verts.has(key):
		return cut_verts[key]
	var pos: Vector3 = mesh.vertices[va].lerp(mesh.vertices[vb], t)
	var vi: int = mesh.append_vertex_lerp(va, vb, pos, t)
	mesh.split_edge(va, vb, vi)
	cut_verts[key] = vi
	return vi
