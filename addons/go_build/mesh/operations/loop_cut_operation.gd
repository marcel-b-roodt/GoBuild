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
## [method GoBuildMesh.rebuild_edges] is called automatically inside
## [method apply].
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
## [method GoBuildMesh.rebuild_edges] is called automatically on completion.
static func apply(
		mesh: GoBuildMesh,
		edge_indices: Array[int],
		t: float = 0.5,
) -> void:
	if mesh == null or edge_indices.is_empty():
		return

	t = clampf(t, 0.0, 1.0)

	# De-duplicate input edge seeds.
	var seen_seeds: Dictionary = {}
	var seeds: Array[int] = []
	for ei: int in edge_indices:
		if ei >= 0 and ei < mesh.edges.size() and not seen_seeds.has(ei):
			seen_seeds[ei] = true
			seeds.append(ei)
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

	mesh.rebuild_edges()


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
static func _cut_ring(
		mesh: GoBuildMesh,
		ring: Array,
		t: float,
		cut_faces: Dictionary,
) -> void:
	# Cache key: "%d_%d_%d_%.6f" % [min(a,b), max(a,b), ring_dir_a, t]
	# ring_dir_a: the lower-indexed of the two vertices when the ring says lerp(a→b,t).
	# This encodes both the canonical edge identity AND the ring-directed t, so
	# two faces that share an edge but have it in opposite ring-directions produce
	# different keys and never collide.  That is correct: they want the same 3D
	# position (lerp(a,b,t) == lerp(b,a,1-t) only at t=0.5), but the cache is
	# just a deduplication aid for the case when the SAME ring direction is used
	# (adjacent faces sharing an edge always approach it from the same direction
	# because opp_va/opp_vb from face N become va/vb for face N+1).
	var cut_verts: Dictionary = {}

	for entry in ring:
		var fi: int      = entry["face_idx"]
		var va: int      = entry["va"]
		var vb: int      = entry["vb"]
		var ova: int     = entry["opp_va"]
		var ovb: int     = entry["opp_vb"]
		var face: GoBuildFace = mesh.faces[fi]

		# Entry-edge cut: lerp(va→vb, t).  Key is canonical (min,max) + low vertex
		# so that the same directed edge always maps to the same key.
		var key_entry: String = "%d_%d_%d_%.6f" % [mini(va, vb), maxi(va, vb), mini(va, vb), t]
		if not cut_verts.has(key_entry):
			cut_verts[key_entry] = mesh.vertices.size()
			mesh.vertices.append(mesh.vertices[va].lerp(mesh.vertices[vb], t))
		var m_entry: int = cut_verts[key_entry]

		# Far-edge cut: lerp(opp_va→opp_vb, t).
		var key_far: String = "%d_%d_%d_%.6f" % [mini(ova, ovb), maxi(ova, ovb), mini(ova, ovb), t]
		if not cut_verts.has(key_far):
			cut_verts[key_far] = mesh.vertices.size()
			mesh.vertices.append(mesh.vertices[ova].lerp(mesh.vertices[ovb], t))
		var m_far: int = cut_verts[key_far]

		# Determine winding.
		# The face is stored CCW-from-outside.  Find va's position in the face to
		# decide which replacement-quad order preserves that winding.
		# forward=true : va→vb runs in the face's CCW direction (v_k → v_{k+1}).
		#   Quad A: [va,  m_entry, m_far,  opp_va]
		#   Quad B: [m_entry, vb,  ovb,   m_far ]  (note: ovb==opp_vb)
		# forward=false: va→vb runs against CCW (v_k → v_{k-1}).
		#   Swap order to keep CCW winding:
		#   Quad A: [m_entry, va,  opp_va, m_far]  (reversed A)
		#   Quad B: [vb, m_entry, m_far,  ovb  ]  (reversed B)
		var pos_va: int = face.vertex_indices.find(va)
		var vc_cut: int = face.vertex_indices.size()
		var forward: bool = face.vertex_indices[(pos_va + 1) % vc_cut] == vb

		var qa := GoBuildFace.new()
		var qb := GoBuildFace.new()
		if vc_cut == 4:
			if forward:
				qa.vertex_indices = [va,      m_entry, m_far, ova]
				qa.uvs = [Vector2(0.0, 0.0), Vector2(t, 0.0), Vector2(t, 1.0), Vector2(0.0, 1.0)]
				qb.vertex_indices = [m_entry, vb,      ovb,   m_far]
				qb.uvs = [Vector2(t, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(t, 1.0)]
			else:
				qa.vertex_indices = [m_entry, va,  ova,  m_far]
				qa.uvs = [Vector2(t, 0.0), Vector2(0.0, 0.0), Vector2(0.0, 1.0), Vector2(t, 1.0)]
				qb.vertex_indices = [vb, m_entry, m_far, ovb]
				qb.uvs = [Vector2(1.0, 0.0), Vector2(t, 0.0), Vector2(t, 1.0), Vector2(1.0, 1.0)]
		else:
			# 5-gon: collect vertices between the far edge and the entry edge
			# (the "cap" side) to preserve the extra bevel vertex.
			# Find positions of ova and ovb in the face.
			# For a 5-gon [v0..v4] with entry v0→v1 (forward), far is v4→v3.
			# Side A (contains ova=v4):       [v0, m_entry, m_far, v4]
			# Side B (contains extra vertex): [m_entry, v1, v2, v3, m_far]
			# Collect vertices "between" far and entry on each side.
			var pos_ova: int = face.vertex_indices.find(ova)
			# Walk from pos_ova toward pos_va (step -1 in forward case or +1).
			var side_a_vis: Array[int] = [va, m_entry, m_far, ova]
			# Side B: from ovb to vb, including middle vertices.
			var pos_ovb: int = face.vertex_indices.find(ovb)
			var pos_vb: int  = face.vertex_indices.find(vb)
			var side_b_vis: Array[int] = [m_entry]
			# Walk from vb toward ovb (the "between" vertices).
			var walk: int = pos_vb
			var step_dir: int = 1 if forward else -1
			for _s: int in vc_cut:
				side_b_vis.append(face.vertex_indices[walk])
				if walk == pos_ovb:
					break
				walk = (walk + step_dir + vc_cut) % vc_cut
			side_b_vis.append(m_far)
			qa.vertex_indices = side_a_vis
			qb.vertex_indices = side_b_vis
			qa.uvs = []
			for _u: int in side_a_vis.size():
				qa.uvs.append(Vector2.ZERO)
			qb.uvs = []
			for _u: int in side_b_vis.size():
				qb.uvs.append(Vector2.ZERO)
		qa.material_index = face.material_index
		qa.smooth_group   = face.smooth_group
		qb.material_index = face.material_index
		qb.smooth_group   = face.smooth_group

		mesh.faces[fi] = qa
		mesh.faces.append(qb)
		cut_faces[fi] = true
