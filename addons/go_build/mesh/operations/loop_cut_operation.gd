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
##   va        : int   — vertex index of edge side A in this face
##   vb        : int   — vertex index of edge side B in this face
##
## Each dict represents one quad face and the pair of vertices (va, vb) that
## form the entry edge of the ring walk in that face.  The cut will be inserted
## between va and vb.
##
## [param already_cut] is the set of face indices cut by earlier ring passes.
## The walk terminates (without including the face) if it hits an already-cut
## face, a non-quad face, or a boundary edge on the far side.
static func _collect_ring(
		mesh: GoBuildMesh,
		seed_ei: int,
		already_cut: Dictionary,
) -> Array:
	var ring: Array = []

	var seed: GoBuildEdge = mesh.edges[seed_ei]

	# Walk in one direction from the seed edge, then the other.
	# Each half-walk returns an ordered list of (face, va, vb) entries.
	var half_a: Array = _walk_half(mesh, seed.vertex_a, seed.vertex_b, already_cut)
	var half_b: Array = _walk_half(mesh, seed.vertex_b, seed.vertex_a, already_cut)

	# Detect closed loop: the ring closes when both walks end at the same face
	# (i.e. the last face in half_a and the last face in half_b are the same as
	# the seed face — or they converge).  For a closed loop we skip the
	# duplicate face that would appear at the junction.
	#
	# Simpler approach: combine half_b (reversed, since it walked the other way)
	# with half_a.  If both ends reach the same face that is already in the list
	# (a closed loop), the final entry is a duplicate and must be dropped.
	var combined: Array = []
	# half_b entries walked in reverse direction — prepend them before the seed
	# face entries in half_a.  half_b[0] is the face immediately on the other
	# side of the seed edge from half_a[0].
	for i: int in range(half_b.size() - 1, -1, -1):
		combined.append(half_b[i])
	for entry in half_a:
		combined.append(entry)

	# Deduplicate: if closed loop, the last entry repeats the first.
	if combined.size() >= 2:
		var first_fi: int = combined[0]["face_idx"]
		var last_fi: int  = combined[combined.size() - 1]["face_idx"]
		if first_fi == last_fi:
			combined.resize(combined.size() - 1)

	ring = combined
	return ring


## Walk one half of the ring starting from a face containing edge (va, vb).
##
## Returns an Array of {face_idx, va, vb} Dictionaries in walk order.
## [param va] and [param vb] are the entry-edge vertices for the first face.
## The "opposite edge" in each quad is the pair of vertices diagonally across
## from the entry edge: for quad [A, B, C, D] with entry edge A→B,
## the opposite edge is C→D (indices 2 and 3 in a CCW quad).
static func _walk_half(
		mesh: GoBuildMesh,
		va: int,
		vb: int,
		already_cut: Dictionary,
) -> Array:
	var result: Array = []

	# Find the face that contains edge va→vb or vb→va and has not been cut yet.
	# We pick the first valid face.
	var ei: int = _find_edge_index(mesh, va, vb)
	if ei == -1:
		return result

	var edge: GoBuildEdge = mesh.edges[ei]
	var cur_fi: int = -1
	for fi: int in edge.face_indices:
		if not already_cut.has(fi) and mesh.faces[fi].vertex_indices.size() == 4:
			cur_fi = fi
			break
	if cur_fi == -1:
		return result

	var cur_va: int = va
	var cur_vb: int = vb
	var visited: Dictionary = {}

	while cur_fi != -1:
		if visited.has(cur_fi) or already_cut.has(cur_fi):
			break
		var face: GoBuildFace = mesh.faces[cur_fi]
		if face.vertex_indices.size() != 4:
			break

		visited[cur_fi] = true
		result.append({"face_idx": cur_fi, "va": cur_va, "vb": cur_vb})

		# Find the opposite edge in this quad.
		# A quad has vertices [v0, v1, v2, v3] in order.  If the entry edge is
		# v_k → v_{k+1}, the opposite edge is v_{k+2} → v_{k+3} (mod 4).
		var pos_a: int = -1
		for k: int in 4:
			if face.vertex_indices[k] == cur_va:
				# Check that the next vertex is cur_vb (or prev — can enter reversed).
				var next_k: int = (k + 1) % 4
				var prev_k: int = (k + 3) % 4
				if face.vertex_indices[next_k] == cur_vb or face.vertex_indices[prev_k] == cur_vb:
					pos_a = k
					break
		if pos_a == -1:
			break  # Entry edge not found in face — degenerate, stop.

		# Determine entry direction so opposite is always across the quad.
		var next_a: int = (pos_a + 1) % 4
		var forward: bool = face.vertex_indices[next_a] == cur_vb

		var opp_va_pos: int
		var opp_vb_pos: int
		if forward:
			# Entry a→b at pos_a → pos_a+1; opposite edge at pos_a+2 → pos_a+3.
			opp_va_pos = (pos_a + 2) % 4
			opp_vb_pos = (pos_a + 3) % 4
		else:
			# Entry b→a at pos_a → (pos_a+3 is cur_vb); opposite at pos_a+2 → pos_a+1
			# (i.e. the pair across from cur_va using the reversed direction).
			opp_va_pos = (pos_a + 2) % 4
			opp_vb_pos = (pos_a + 1) % 4

		var opp_va: int = face.vertex_indices[opp_va_pos]
		var opp_vb: int = face.vertex_indices[opp_vb_pos]

		# The opposite edge becomes the entry edge for the next face.
		# Find the edge and then pick the adjacent face that is not cur_fi.
		var opp_ei: int = _find_edge_index(mesh, opp_va, opp_vb)
		if opp_ei == -1:
			break

		var opp_edge: GoBuildEdge = mesh.edges[opp_ei]
		var next_fi: int = -1
		for fi: int in opp_edge.face_indices:
			if fi != cur_fi and not visited.has(fi) \
					and mesh.faces[fi].vertex_indices.size() == 4 \
					and not already_cut.has(fi):
				next_fi = fi
				break

		# Prepare the entry edge for the next face: the new entry is the
		# opposite edge of the current face as seen from the next face.
		cur_va = opp_va
		cur_vb = opp_vb
		cur_fi = next_fi  # May be -1 → loop exits.

	return result


## Find the edge index in [param mesh] that connects [param va] and [param vb].
## Returns -1 if not found.
static func _find_edge_index(mesh: GoBuildMesh, va: int, vb: int) -> int:
	for ei: int in mesh.edges.size():
		if mesh.edges[ei].connects(va, vb):
			return ei
	return -1


# ---------------------------------------------------------------------------
# Ring cutting
# ---------------------------------------------------------------------------

## Split each quad face in [param ring] at position [param t] along the entry edge.
##
## For each face {face_idx, va, vb}:
##   1. Add (or reuse) a cut vertex on edge va→vb at position lerp(va, vb, t).
##   2. Add (or reuse) a cut vertex on the opposite edge vb_opp→va_opp at t.
##   3. Replace the original face with two new quads split at the cut line.
##
## Edge midpoints that lie on a shared edge between two consecutive ring faces
## are reused (keyed by canonical min_max vertex pair + t) so no T-junctions
## form along the cut line.
static func _cut_ring(
		mesh: GoBuildMesh,
		ring: Array,
		t: float,
		cut_faces: Dictionary,
) -> void:
	# Key: "%d_%d_%.6f" % [min(va, vb), max(va, vb), t] → new vertex index.
	var cut_verts: Dictionary = {}

	for entry in ring:
		var fi: int       = entry["face_idx"]
		var entry_va: int = entry["va"]
		var entry_vb: int = entry["vb"]

		var face: GoBuildFace = mesh.faces[fi]
		# Quad vertex order: [v0, v1, v2, v3] CCW from outside.
		# Locate the entry edge inside the face.
		var pos_a: int = -1
		for k: int in 4:
			if face.vertex_indices[k] == entry_va:
				var next_k: int = (k + 1) % 4
				var prev_k: int = (k + 3) % 4
				if face.vertex_indices[next_k] == entry_vb \
						or face.vertex_indices[prev_k] == entry_vb:
					pos_a = k
					break
		if pos_a == -1:
			continue  # Defensive — should not happen.

		# Determine direction.
		var next_a: int = (pos_a + 1) % 4
		var forward: bool = face.vertex_indices[next_a] == entry_vb

		var idx0: int  # entry_va's ring position
		var idx1: int  # entry_vb's ring position  (entry edge: idx0→idx1)
		var idx2: int  # opposite_vb's ring position
		var idx3: int  # opposite_va's ring position (opposite edge: idx2→idx3 mirrored)
		if forward:
			idx0 = pos_a
			idx1 = (pos_a + 1) % 4
			idx2 = (pos_a + 2) % 4
			idx3 = (pos_a + 3) % 4
		else:
			idx0 = pos_a
			idx1 = (pos_a + 3) % 4
			idx2 = (pos_a + 2) % 4
			idx3 = (pos_a + 1) % 4

		var v0: int = face.vertex_indices[idx0]  # entry_va
		var v1: int = face.vertex_indices[idx1]  # entry_vb
		var v2: int = face.vertex_indices[idx2]  # far_vb
		var v3: int = face.vertex_indices[idx3]  # far_va

		# Cut vertex on entry edge v0→v1.
		var key01: String = "%d_%d_%.6f" % [mini(v0, v1), maxi(v0, v1), t]
		if not cut_verts.has(key01):
			# Insert at lerp(v0→v1, t), but orient consistently by always
			# lerping from the lower to the higher index regardless of direction.
			var lerp_pos: Vector3
			if v0 < v1:
				lerp_pos = mesh.vertices[v0].lerp(mesh.vertices[v1], t)
			else:
				lerp_pos = mesh.vertices[v1].lerp(mesh.vertices[v0], 1.0 - t)
			cut_verts[key01] = mesh.vertices.size()
			mesh.vertices.append(lerp_pos)
		var m01: int = cut_verts[key01]

		# Cut vertex on opposite edge v3→v2 (the mirror of the entry edge).
		# Opposite edge connects v3 to v2 (they are the vertices of the far side
		# in the same traversal direction as v0→v1).  We use the same canonical
		# min/max key so adjacent ring faces share the vertex.
		var key32: String = "%d_%d_%.6f" % [mini(v3, v2), maxi(v3, v2), t]
		if not cut_verts.has(key32):
			var lerp_pos: Vector3
			if v3 < v2:
				lerp_pos = mesh.vertices[v3].lerp(mesh.vertices[v2], t)
			else:
				lerp_pos = mesh.vertices[v2].lerp(mesh.vertices[v3], 1.0 - t)
			cut_verts[key32] = mesh.vertices.size()
			mesh.vertices.append(lerp_pos)
		var m32: int = cut_verts[key32]

		# Build two replacement quads.
		# Original face CCW winding was [v0, v1, v2, v3].
		# After cut with m01 on v0→v1 and m32 on v3→v2:
		#   Quad A: [v0, m01, m32, v3]
		#   Quad B: [m01, v1, v2, m32]
		# Both preserve CCW-from-outside winding.
		var qa := GoBuildFace.new()
		qa.vertex_indices = [v0, m01, m32, v3]
		qa.uvs = [Vector2(0.0, 0.0), Vector2(t, 0.0), Vector2(t, 1.0), Vector2(0.0, 1.0)]
		qa.material_index = face.material_index
		qa.smooth_group   = face.smooth_group

		var qb := GoBuildFace.new()
		qb.vertex_indices = [m01, v1, v2, m32]
		qb.uvs = [Vector2(t, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(t, 1.0)]
		qb.material_index = face.material_index
		qb.smooth_group   = face.smooth_group

		mesh.faces[fi] = qa
		mesh.faces.append(qb)

		cut_faces[fi] = true
