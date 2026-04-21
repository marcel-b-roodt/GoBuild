## Bevel edge(s) operation for [GoBuildMesh].
##
## For each selected edge, the two endpoints are slid along their adjacent face
## edges by [param width] units.  The resulting gap is filled with a new quad
## face (the bevel strip).  Adjacent faces have their vertex rings updated to
## reference the new slid vertices.
##
## When two selected edges share a vertex V, V is handled as follows:
##   • In their [b]shared[/b] adjacent face (e.g. F_top on a cube): V is
##     expanded into two slid copies — one per edge — so the face grows by one
##     vertex.
##   • In each edge's [b]other[/b] adjacent face (e.g. F_front / F_right):
##     both copies slide V along the same third edge, so they are [b]merged[/b]
##     into a single averaged vertex.  Both bevel strips end at that vertex,
##     sealing the mesh without any extra face.
##   • In every remaining face that contains V (e.g. F_bottom): V is simply
##     replaced with the merged vertex.
##
## No cap faces are ever added.  The mesh is always sealed by shared vertices.
##
## [method GoBuildMesh.rebuild_edges] is called automatically inside
## [method apply].
@tool
class_name BevelOperation
extends RefCounted

const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")


## Bevel the edges at [param edge_indices] on [param mesh] by [param width].
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

	# vertex_plan[fi][vi] = Array of {idx, slide_nbr} dicts.
	# One entry per selected edge that touches vi in face fi.
	# 1 entry  → simple replacement.
	# 2 entries in same direction → merged (1 averaged vertex).
	# 2 entries in different directions → expansion (face grows by 1 vertex).
	var vertex_plan: Dictionary = _build_vertex_plan(mesh, valid, width)

	var caps_needed: Array[Dictionary] = []

	# Precompute original face normals per edge BEFORE _update_faces modifies
	# the face rings.  At maximum bevel width the plan faces can collapse to
	# zero-area (slid vertex lands exactly on a corner), making their
	# post-update normals unreliable for the strip winding check.
	var edge_hint_normals: Dictionary = {}  # ei → Vector3
	for ei: int in valid:
		var edge: GoBuildEdge = mesh.edges[ei]
		var hint: Vector3 = Vector3.ZERO
		for hint_fi: int in edge.face_indices:
			hint += mesh.compute_face_normal(mesh.faces[hint_fi])
		edge_hint_normals[ei] = hint

	_update_faces(mesh, vertex_plan, width, caps_needed)
	_add_bevel_strips(mesh, valid, vertex_plan, edge_hint_normals)
	_add_endpoint_caps(mesh, caps_needed)
	_compact_vertices(mesh)
	mesh.rebuild_edges()


# ── Phase 1 ───────────────────────────────────────────────────────────────────
# For every (edge, adjacent-face, endpoint) triple: compute the slide offset
# and accumulate it into vertex_plan[face_idx][vertex_idx].
#
# Each entry in the plan is a single {idx, slide_nbr} dict — always exactly
# ONE entry per (face, vertex) pair, regardless of how many selected edges
# touch that vertex in that face.
#
# Corner merge rule (two selected edges sharing vertex V in the same face):
#   The two slide offset vectors are SUMMED.  The single resulting vertex
#   is placed at V + offset_E0 + offset_E1.  Both bevel strips end at this
#   one vertex — no extra cap face is ever needed.
#
# Same-direction duplicate (two edges sliding V toward the same neighbour):
#   The offsets are equal, so summing would double them.  In this case we
#   keep only one (they are identical within floating-point tolerance).
static func _build_vertex_plan(
		mesh: GoBuildMesh,
		valid: Array[int],
		width: float,
) -> Dictionary:
	# raw_offsets[fi][vi] = Array of Vector3 offset contributions, one per edge.
	# raw_nbrs  [fi][vi] = Array of slide_nbr int, parallel to raw_offsets.
	var raw_offsets: Dictionary = {}
	var raw_nbrs: Dictionary   = {}

	for ei: int in valid:
		var edge: GoBuildEdge = mesh.edges[ei]
		var va: int = edge.vertex_a
		var vb: int = edge.vertex_b

		for fi: int in edge.face_indices:
			var face: GoBuildFace = mesh.faces[fi]
			var vc: int = face.vertex_indices.size()
			var pos_a: int = face.vertex_indices.find(va)
			var pos_b: int = face.vertex_indices.find(vb)
			if pos_a == -1 or pos_b == -1:
				continue

			# Slide va along the neighbour that is NOT vb.
			var prev_a: int = face.vertex_indices[(pos_a - 1 + vc) % vc]
			var next_a: int = face.vertex_indices[(pos_a + 1) % vc]
			var nbr_a: int = prev_a if prev_a != vb else next_a

			# Slide vb along the neighbour that is NOT va.
			var prev_b: int = face.vertex_indices[(pos_b - 1 + vc) % vc]
			var next_b: int = face.vertex_indices[(pos_b + 1) % vc]
			var nbr_b: int = next_b if next_b != va else prev_b

			if not raw_offsets.has(fi):
				raw_offsets[fi] = {}
				raw_nbrs[fi]    = {}

			# Perpendicular-to-edge direction within the face plane.
			# Both endpoints share the same perp base so A'B' is always parallel
			# to AB regardless of the adjacent edge lengths or angles.
			var face_normal: Vector3 = mesh.compute_face_normal(face)
			var edge_dir: Vector3 = (mesh.vertices[vb] - mesh.vertices[va]).normalized()
			var perp_base: Vector3 = face_normal.cross(edge_dir)
			var has_perp: bool = perp_base.length_squared() > 1e-8
			if has_perp:
				perp_base = perp_base.normalized()

			for pair in [[va, nbr_a], [vb, nbr_b]]:
				var vi: int    = pair[0]
				var slide: int = pair[1]
				var to_slide: Vector3 = mesh.vertices[slide] - mesh.vertices[vi]
				var offset: Vector3
				if has_perp:
					# Orient perp toward the slide neighbour (into the face).
					var perp: Vector3 = perp_base if to_slide.dot(perp_base) >= 0.0 \
							else -perp_base
					var perp_dist: float = to_slide.dot(perp)
					if perp_dist < 1e-8:
						continue
					var clamped_width: float = minf(width, perp_dist)
					offset = perp * clamped_width
				else:
					# Degenerate face fallback: slide along neighbour direction.
					var edge_len: float = to_slide.length()
					if edge_len < 1e-8:
						continue
					var clamped_width: float = minf(width, edge_len)
					offset = to_slide / edge_len * clamped_width

				if not raw_offsets[fi].has(vi):
					raw_offsets[fi][vi] = []
					raw_nbrs[fi][vi]    = []

				# Deduplicate: skip if an identical slide neighbour is already present
				# (same edge touching the same face via two paths — should not happen,
				# but guard against it).
				if raw_nbrs[fi][vi].has(slide):
					continue

				raw_offsets[fi][vi].append(offset)
				raw_nbrs[fi][vi].append(slide)

	# Build the final plan: one vertex per (fi, vi) pair, position = V + sum(offsets).
	var plan: Dictionary = {}
	for fi in raw_offsets:
		plan[fi] = {}
		for vi in raw_offsets[fi]:
			var total_offset: Vector3 = Vector3.ZERO
			for off: Vector3 in raw_offsets[fi][vi]:
				total_offset += off
			var new_idx: int = mesh.vertices.size()
			mesh.vertices.append(mesh.vertices[vi] + total_offset)
			# slide_nbr stores the first contributing neighbour (used for winding
			# order hints in _add_bevel_strips / _sort_entries_ccw).
			plan[fi][vi] = [{"idx": new_idx, "slide_nbr": raw_nbrs[fi][vi][0]}]

	return plan


# ── Phase 2 ───────────────────────────────────────────────────────────────────
# Walk every face that contains a bevel vertex and update its ring.
#
# Plan face (fi is in vertex_plan for vi):
#   Always exactly 1 entry because Phase 1 sums all offset contributions for
#   that (face, vertex) pair.  Replace vi 1-for-1 with the summed slid vertex.
#
# Non-plan face (fi is NOT in vertex_plan for vi):
#
#   One non-plan face at vi (corner vertex, e.g. plain cube corner):
#     Insert ALL slid copies in CCW order so the face grows smoothly into an
#     N-gon (a 4-gon → 5-gon).  The bevel-strip end edge is shared between the
#     strip and this N-gon — no extra cap face is needed.
#
#   Two or more non-plan faces at vi (midpoint/T vertex, e.g. loop-cut point):
#     Each non-plan face receives exactly ONE slid copy (the best-fit one).
#     A new "anchor" vertex is created on the continuation edge at [param width]
#     units from vi.  It is inserted into each non-plan face ring between the
#     chosen slid copy and the continuation vertex, keeping faces as quads (+1).
#     A cap polygon [chosen0, chosen1, …, anchor] is recorded and added by
#     _add_endpoint_caps to seal the gap.
static func _update_faces(
		mesh: GoBuildMesh, vertex_plan: Dictionary, width: float,
		caps_needed: Array[Dictionary]) -> void:
	# global_slid[vi] = Array of {idx, slide_nbr, plan_fi} — one per plan face.
	var global_slid: Dictionary = {}
	for fi in vertex_plan:
		for vi in vertex_plan[fi]:
			if not global_slid.has(vi):
				global_slid[vi] = []
			var entry: Dictionary = vertex_plan[fi][vi][0].duplicate()
			entry["plan_fi"] = fi
			global_slid[vi].append(entry)

	# ── Precompute per-vertex non-plan face info ──────────────────────────────
	# np_info[vi] = {
	#   "faces":      Array of {fi, k, prev_vi, next_vi, chosen_idx},
	#   "anchor_idx": int  (-1 → N-gon approach, no cap),
	#   "W":          int  (-1 → N-gon approach, else continuation vertex),
	# }
	var np_info: Dictionary = {}
	for vi: int in global_slid:
		var faces_arr: Array = []
		for fi2: int in mesh.faces_of_vertex(vi):
			if vertex_plan.has(fi2) and vertex_plan[fi2].has(vi):
				continue  # plan face — skip
			var face2: GoBuildFace = mesh.faces[fi2]
			var k2: int = face2.vertex_indices.find(vi)
			if k2 == -1:
				continue
			var vc2: int = face2.vertex_indices.size()
			var prev2: int = face2.vertex_indices[(k2 - 1 + vc2) % vc2]
			var next2: int = face2.vertex_indices[(k2 + 1) % vc2]
			var sorted2: Array = _sort_entries_ccw(global_slid[vi], prev2, vi, mesh, next2)
			faces_arr.append({
				"fi": fi2, "k": k2,
				"prev_vi": prev2, "next_vi": next2,
				"chosen_idx": sorted2[0].idx,
			})

		if faces_arr.is_empty():
			continue

		if faces_arr.size() == 1:
			# Single non-plan face → N-gon approach, no cap needed.
			np_info[vi] = {"faces": faces_arr, "anchor_idx": -1, "W": -1}
		else:
			# Multiple non-plan faces → cap approach.
			# W = the vertex that is a ring-neighbour of vi in EVERY non-plan face
			# AND is not itself a plan vertex (not the other bevel endpoint).
			# This is the shared unselected boundary edge vertex at this T-joint.
			# Use the new mesh helper for a clean intersection.
			var plan_verts: Dictionary = {}
			for pfi: int in vertex_plan:
				for pvi: int in vertex_plan[pfi]:
					plan_verts[pvi] = true

			var np_fi_arr: Array[int] = []
			for face_info: Dictionary in faces_arr:
				np_fi_arr.append(face_info["fi"])

			var shared_nbrs: Array[int] = mesh.shared_vertex_neighbours(vi, np_fi_arr)
			# Remove any vertex that is a plan vertex.
			var candidates: Array[int] = []
			for nb: int in shared_nbrs:
				if not plan_verts.has(nb):
					candidates.append(nb)

			# Among candidates pick the closest one (shortest unselected edge) so the
			# cap stays proportional to bevel width, not extended to a far corner.
			var best_w: int  = -1
			var best_dist: float = 1e38
			for nb: int in candidates:
				var d: float = mesh.vertices[vi].distance_squared_to(mesh.vertices[nb])
				if d < best_dist:
					best_dist = d
					best_w    = nb

			# Fallback: use most-common neighbour if no unanimous shared vertex found.
			if best_w == -1:
				var nbr_counts: Dictionary = {}
				for fi_np2: int in np_fi_arr:
					for nb2: int in mesh.vertex_neighbours(vi, [fi_np2]):
						if not plan_verts.has(nb2):
							nbr_counts[nb2] = nbr_counts.get(nb2, 0) + 1
				var best_cnt: int = 0
				for nb: int in nbr_counts:
					if nbr_counts[nb] > best_cnt:
						best_cnt = nbr_counts[nb]
						best_w   = nb

			# Create anchor vertex at [width] along vi → best_w, clamped so the
			# anchor never overshoots W (cap never longer than the unselected edge).
			var anchor_idx: int = -1
			if best_w != -1:
				var to_w: Vector3 = mesh.vertices[best_w] - mesh.vertices[vi]
				var edge_len: float = to_w.length()
				var t_clamp: float = minf(width, edge_len) / edge_len
				anchor_idx = mesh.vertices.size()
				mesh.vertices.append(mesh.vertices[vi] + to_w * t_clamp)
			np_info[vi] = {"faces": faces_arr, "anchor_idx": anchor_idx, "W": best_w}
			# Record the cap polygon for _add_endpoint_caps.
			# The hint normal is computed NOW — before Phase 2 modifies any face
			# rings — so it remains valid even when plan faces collapse to
			# zero-area at maximum bevel width.
			if anchor_idx != -1:
				var chosen_verts: Array[int] = []
				for face_info: Dictionary in faces_arr:
					chosen_verts.append(face_info["chosen_idx"])
				var cap_hint: Vector3 = Vector3.ZERO
				for face_info: Dictionary in faces_arr:
					cap_hint += mesh.compute_face_normal(mesh.faces[face_info["fi"]])
				caps_needed.append({
					"vertices": chosen_verts,
					"anchor":   anchor_idx,
					"mat":      mesh.faces[faces_arr[0]["fi"]].material_index,
					"smooth":   mesh.faces[faces_arr[0]["fi"]].smooth_group,
					"hint":     cap_hint,
				})

	# Build fast-lookup tables derived from np_info.
	# face_use_ngon[vi]        → true  = N-gon; false = single-copy + anchor.
	# face_chosen_map[vi][fi]  → chosen slid-copy index for a specific face.
	var face_use_ngon: Dictionary    = {}
	var face_chosen_map: Dictionary  = {}
	for vi: int in np_info:
		var info: Dictionary = np_info[vi]
		if info["anchor_idx"] == -1:
			face_use_ngon[vi] = true
		else:
			face_use_ngon[vi]  = false
			face_chosen_map[vi] = {}
			for face_info: Dictionary in info["faces"]:
				face_chosen_map[vi][face_info["fi"]] = face_info["chosen_idx"]

	# ── Update face rings ─────────────────────────────────────────────────────
	for fi: int in mesh.faces.size():
		var face: GoBuildFace = mesh.faces[fi]
		var needs_update: bool = false
		for vi: int in face.vertex_indices:
			if global_slid.has(vi):
				needs_update = true
				break
		if not needs_update:
			continue

		var fi_plan: Dictionary = vertex_plan.get(fi, {})
		var old_vis: Array[int] = []
		for vi: int in face.vertex_indices:
			old_vis.append(vi)
		var new_vis: Array[int] = []
		var new_uvs: Array[Vector2] = []
		var has_uvs: bool = face.uvs.size() == old_vis.size()

		for k: int in old_vis.size():
			var vi: int = old_vis[k]
			if not global_slid.has(vi):
				new_vis.append(vi)
				if has_uvs:
					new_uvs.append(face.uvs[k])
				continue

			if fi_plan.has(vi):
				# Plan face: summed-offset vertex — simple 1-for-1 replace.
				new_vis.append(fi_plan[vi][0].idx)
				if has_uvs:
					new_uvs.append(face.uvs[k])
			else:
				# Non-plan face.
				var prev_vi: int = old_vis[(k - 1 + old_vis.size()) % old_vis.size()]
				var next_vi: int = old_vis[(k + 1) % old_vis.size()]
				if face_use_ngon.get(vi, true):
					# N-gon: insert all slid copies in CCW order.
					var sorted_entries: Array = _sort_entries_ccw(
							global_slid[vi], prev_vi, vi, mesh, next_vi)
					for entry: Dictionary in sorted_entries:
						new_vis.append(entry.idx)
						if has_uvs:
							new_uvs.append(face.uvs[k])
				else:
					# Single copy + anchor.  Use precomputed chosen_idx.
					var chosen: int = face_chosen_map[vi].get(fi, -1)
					if chosen == -1:
						# Fallback (should not occur).
						var se: Array = _sort_entries_ccw(
							global_slid[vi], prev_vi, vi, mesh, next_vi)
						chosen = se[0].idx
					# Determine if anchor goes before or after chosen in the ring.
					var info: Dictionary = np_info[vi]
					var anchor: int = info["anchor_idx"]
					var cont_w: int = info["W"]
					if anchor != -1 and cont_w != -1 and cont_w == prev_vi:
						# W is the vertex that PRECEDES vi: anchor goes before chosen.
						new_vis.append(anchor)
						if has_uvs:
							new_uvs.append(face.uvs[k])
					new_vis.append(chosen)
					if has_uvs:
						new_uvs.append(face.uvs[k])
					# Also insert anchor between chosen and the continuation vertex W.
					# W may be either next_vi OR prev_vi depending on ring orientation.
					if anchor != -1 and cont_w != -1:
						if cont_w == next_vi:
							# anchor goes between chosen and next_vi: append now.
							new_vis.append(anchor)
							if has_uvs:
								new_uvs.append(face.uvs[k])

		face.vertex_indices.resize(new_vis.size())
		for k: int in new_vis.size():
			face.vertex_indices[k] = new_vis[k]
		if has_uvs:
			face.uvs.resize(new_uvs.size())
			for k: int in new_uvs.size():
				face.uvs[k] = new_uvs[k]


# Return [param entries] sorted so they appear in CCW order in the ring after
# [param prev_vi] around [param vi].
# Fast path: the entry whose slide_nbr matches prev_vi came from the face that
# shares the prev_vi→vi edge — it belongs immediately after prev_vi.
# Fallback: sort by signed angle from the prev_vi direction.
static func _sort_entries_ccw(
		entries: Array, prev_vi: int, vi: int, mesh: GoBuildMesh,
		next_vi: int = -1) -> Array:
	if entries.size() == 1:
		return entries

	# Fast path: slide_nbr match.
	var first_i: int = -1
	for i: int in entries.size():
		if entries[i].slide_nbr == prev_vi:
			first_i = i
			break
	if first_i != -1:
		var result: Array = [entries[first_i]]
		for i: int in entries.size():
			if i != first_i:
				result.append(entries[i])
		return result

	# Secondary fast path: if a slide_nbr matches next_vi, that entry belongs
	# FIRST in CCW order.  It comes from the plan face sharing the vi→next_vi
	# edge, which is the first plan face encountered after the current non-plan
	# face in the CCW ring around vi.
	if next_vi != -1:
		var next_i: int = -1
		for i: int in entries.size():
			if entries[i].slide_nbr == next_vi:
				next_i = i
				break
		if next_i != -1:
			var result: Array = [entries[next_i]]
			for i: int in entries.size():
				if i != next_i:
					result.append(entries[i])
			return result

	# Angle-based fallback.
	var origin: Vector3 = mesh.vertices[vi]
	var ref_dir: Vector3 = (mesh.vertices[prev_vi] - origin).normalized()
	var avg: Vector3 = Vector3.ZERO
	for entry in entries:
		avg += (mesh.vertices[entry.idx] - origin).normalized()
	var plane_n: Vector3 = ref_dir.cross(avg).normalized()
	if plane_n.length_squared() < 1e-8:
		return entries
	var with_angles: Array = []
	for entry in entries:
		var dir: Vector3 = (mesh.vertices[entry.idx] - origin).normalized()
		with_angles.append({"entry": entry, "angle": ref_dir.signed_angle_to(dir, plane_n)})
	with_angles.sort_custom(func(a, b): return a.angle < b.angle)
	return with_angles.map(func(x): return x.entry)


# ── Phase 3 ───────────────────────────────────────────────────────────────────
# Append one new quad face per selected interior edge.
# The four corners come from vertex_plan: slid copy of va and vb in each of
# the two adjacent faces.  Winding is validated against the precomputed hint
# normals (computed from the original, unmodified face rings in apply()).
static func _add_bevel_strips(
		mesh: GoBuildMesh,
		valid: Array[int],
		vertex_plan: Dictionary,
		edge_hint_normals: Dictionary,
) -> void:
	for ei: int in valid:
		var edge: GoBuildEdge = mesh.edges[ei]
		if edge.face_indices.size() < 2:
			continue

		var va: int = edge.vertex_a
		var vb: int = edge.vertex_b
		var fi0: int = edge.face_indices[0]
		var fi1: int = edge.face_indices[1]

		# Look up the slid copy of va/vb in each adjacent face.
		# For an expand vertex, find the entry whose slide_nbr is NOT the
		# other endpoint of the edge (i.e. not vb for va, not va for vb).
		var na0: int = _plan_idx_not_toward(vertex_plan, fi0, va, vb, mesh)
		var nb0: int = _plan_idx_not_toward(vertex_plan, fi0, vb, va, mesh)
		var na1: int = _plan_idx_not_toward(vertex_plan, fi1, va, vb, mesh)
		var nb1: int = _plan_idx_not_toward(vertex_plan, fi1, vb, va, mesh)
		if na0 == -1 or nb0 == -1 or na1 == -1 or nb1 == -1:
			continue

		var strip := _FACE_SCRIPT.new()
		strip.vertex_indices = [na0, nb0, nb1, na1]
		strip.uvs = [
			Vector2(0.0, 0.0), Vector2(1.0, 0.0),
			Vector2(1.0, 1.0), Vector2(0.0, 1.0),
		]
		strip.material_index = mesh.faces[fi0].material_index
		strip.smooth_group   = mesh.faces[fi0].smooth_group

		var hint: Vector3 = edge_hint_normals.get(ei, Vector3.ZERO)
		if hint.length_squared() > 1e-8 \
				and mesh.compute_face_normal(strip).dot(hint) < 0.0:
			strip.vertex_indices = [na0, na1, nb1, nb0]
		mesh.faces.append(strip)


# ── Phase 3b ─────────────────────────────────────────────────────────────────
# Seal each bevel endpoint that has 2+ non-plan faces with a cap polygon.
# cap["vertices"] holds the chosen slid-copy index from each non-plan face;
# cap["anchor"] is a new vertex at [width] distance along the continuation
# edge.  For 2 non-plan faces this produces a triangle; 3+ produces an N-gon.
static func _add_endpoint_caps(
		mesh: GoBuildMesh, caps_needed: Array[Dictionary]) -> void:
	for cap: Dictionary in caps_needed:
		var verts: Array = cap["vertices"]
		var anchor: int  = cap["anchor"]
		# Build polygon [v0, v1, …, anchor] as a typed Array[int].
		var vis: Array[int] = []
		for v: int in verts:
			vis.append(v)
		vis.append(anchor)
		# Use the precomputed hint (from original face rings before Phase 2
		# modified them).  Fall back to scanning existing faces only if needed.
		var outward: Vector3 = cap.get("hint", Vector3.ZERO)
		if outward.length_squared() < 1e-8:
			for existing: GoBuildFace in mesh.faces:
				if verts[0] in existing.vertex_indices:
					outward += mesh.compute_face_normal(existing)
		var cap_face := _FACE_SCRIPT.new()
		cap_face.vertex_indices.assign(vis)
		var cap_normal: Vector3 = mesh.compute_face_normal(cap_face)
		if outward.length_squared() > 1e-8 and cap_normal.dot(outward) < 0.0:
			vis.reverse()
			cap_face.vertex_indices.assign(vis)
		cap_face.material_index = cap["mat"]
		cap_face.smooth_group   = cap["smooth"]
		mesh.faces.append(cap_face)


# For vertex [param vi] in face [param fi], return the slid index whose
# slide-direction neighbour is NOT [param not_toward].  This selects the
# "outward along the bevel" slid copy (as opposed to the copy that slides
# along the shared edge toward the other endpoint of the edge being bevelled).
static func _plan_idx_not_toward(
		vertex_plan: Dictionary, fi: int, vi: int, not_toward: int,
		mesh: GoBuildMesh) -> int:
	if not vertex_plan.has(fi) or not vertex_plan[fi].has(vi):
		return -1
	var entries: Array = vertex_plan[fi][vi]
	if entries.size() == 1:
		return entries[0].idx
	# Pick the entry whose slide neighbour is further from not_toward.
	var e0: Dictionary = entries[0]
	var e1: Dictionary = entries[1]
	if e0.slide_nbr == not_toward:
		return e1.idx
	if e1.slide_nbr == not_toward:
		return e0.idx
	# Fallback: furthest slide_nbr from not_toward.
	var d0: float = mesh.vertices[e0.slide_nbr].distance_squared_to(
			mesh.vertices[not_toward])
	var d1: float = mesh.vertices[e1.slide_nbr].distance_squared_to(
			mesh.vertices[not_toward])
	return e0.idx if d0 >= d1 else e1.idx


## Remove every vertex not referenced by any face and remap face indices.
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
