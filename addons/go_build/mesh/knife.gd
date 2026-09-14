## Knife cut — pure geometry for splitting faces along a drawn surface path.
##
## Design: docs/knife-cut-design.md
## Three-phase pipeline (the standard geometry-kernel approach):
##   1. RESOLVE — group picked points into per-face runs; interior run ends
##      stay interior (Blender semantics: no invented extension geometry).
##   2. EDGE SPLIT — insert cut vertices into the ring of EVERY face that
##      contains a crossed edge (no T-junctions; neighbours update).
##   3. RE-TESSELLATE — affected faces re-partition around the path and are
##      emitted as NGONS (our face model supports them; bake triangulates).
##      Minimal geometry: the drawn path's edges are the only new edges plus
##      the stitching needed to keep the surface watertight.
##
## The stroke pipeline (controller → apply):
##   picks (3D) + screen-space crossings (tunnel-gated) → owner remap /
##   geometric face re-pick → clamp → group → split at ring exits (graze-
##   checked) → per-run entry/exit crossings → split crossed edges →
##   band assembly (closed loop = island + keyhole/two bands) → emit.
##   Transactional: any failed run rolls the whole op back.
##
## Intentional Blender divergences:
##   - Occlusion culling is ALWAYS on (Blender's X-ray knife cuts hidden
##     geometry; ours never snaps or cuts through the mesh — UX decision).
##   - Interior open-run ends anchor to the nearest ring corner (Blender
##     leaves a loose interior vertex connected only to the path).
##
## All functions are static and depend only on [GoBuildMesh]/[GoBuildFace],
## so the maths is unit-testable headless.
@tool
class_name GoBuildKnife
extends RefCounted

# Self-preloads — dependency order.
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _TRIANGULATE_SCRIPT := preload("res://addons/go_build/mesh/triangulate.gd")

const _EPSILON: float = 1e-5


## Segment-segment intersection of cut segment [param a]-[param b] with edge
## [param e0]-[param e1]; all four points assumed coplanar.
## Returns {} when they do not cross within bounds.
## On hit: { "hit": Vector3, "t": float (0=a..1=b), "u": float (0=e0..1=e1) }
static func edge_hit(a: Vector3, b: Vector3, e0: Vector3, e1: Vector3) -> Dictionary:
	var d1: Vector3 = b - a
	var d2: Vector3 = e1 - e0
	var denom_v: Vector3 = d1.cross(d2)
	var denom: float = denom_v.length_squared()
	if denom < _EPSILON * _EPSILON:
		return {}          # Parallel / collinear — no unique crossing.
	var diff: Vector3 = e0 - a
	var s: float = diff.cross(d2).dot(denom_v) / denom
	var u: float = diff.cross(d1).dot(denom_v) / denom
	if s < -_EPSILON or s > 1.0 + _EPSILON or u < -_EPSILON or u > 1.0 + _EPSILON:
		return {}
	return {
		"hit": e0.lerp(e1, clampf(u, 0.0, 1.0)),
		"t": clampf(s, 0.0, 1.0),
		"u": clampf(u, 0.0, 1.0),
	}


## Where the cut segment [param a]-[param b] enters/exits [param face].
## Returns crossings sorted by "t": each {
##   "pos": int — ring slot of the crossed edge's first vertex,
##   "t", "u": float, "point": Vector3 }.  <2 crossings = no split.
## edge_hit assumes coplanar input; segments running BETWEEN faces are
## skew and produce phantom "hits" anywhere along the ring lines — each
## candidate is rejected unless its hit point actually lies ON the cut
## segment (the segment must pierce the ring edge, not merely graze its
## line: a hit on a ring edge is always in the face plane, so a plane
## test cannot catch phantoms — the 3D point-to-segment distance can).
static func face_crossings(
		a: Vector3,
		b: Vector3,
		mesh: GoBuildMesh,
		face: GoBuildFace,
) -> Array:
	var ring := face.vertex_indices
	var crossings: Array = []
	var ab := b - a
	var ab_len_sq: float = ab.length_squared()
	var tol: float = 1e-3 + sqrt(ab_len_sq) * 1e-3
	for i: int in ring.size():
		var e0: Vector3 = mesh.vertices[ring[i]]
		var e1: Vector3 = mesh.vertices[ring[(i + 1) % ring.size()]]
		var hit := edge_hit(a, b, e0, e1)
		if hit.is_empty():
			continue
		if ab_len_sq > _EPSILON * _EPSILON \
				and _seg_point_dist(a, ab, ab_len_sq,
						hit["hit"] as Vector3) > tol:
			continue   # Skew-segment phantom — the segment misses it.
		crossings.append({
			"pos": i,
			"t": hit["t"],
			"u": hit["u"],
			"point": hit["hit"],
		})
	crossings.sort_custom(func(x, y): return x["t"] < y["t"])
	return crossings


## Distance from the segment [param a] + [param ab]·t (t clamped to [0,1])
## to [param p] (3D).
static func _seg_point_dist(a: Vector3, ab: Vector3, ab_len_sq: float,
		p: Vector3) -> float:
	var t: float = clampf((p - a).dot(ab) / maxf(ab_len_sq, _EPSILON), 0.0, 1.0)
	return (a + ab * t).distance_to(p)


## Split a vertex ring by a chord between two crossings.
## Returns the two sub-rings in the original winding, with cut vertices as
## -1 sentinels where a new vertex is needed at u not in {0,1}.
## Get (or create) the knife cut vertex on edge va→vb at parameter [param t].
## Primary key = POSITION (quantised) so the same physical point reached via
## different edges/directions (path points, re-crossed lines) shares ONE
## vertex; a secondary (edge, t) key maps alias lookups to the same entry.
static func get_or_create_cut_vertex(
		mesh: GoBuildMesh,
		va: int,
		vb: int,
		t_for_va: float,
		cut_verts: Dictionary,
) -> int:
	var pos: Vector3 = mesh.vertices[va].lerp(mesh.vertices[vb], t_for_va)
	var pos_key := "P_%d_%d_%d" % [
			roundi(pos.x * 10000.0), roundi(pos.y * 10000.0), roundi(pos.z * 10000.0)]
	var edge_key := "%d_%d@%.4f" % [
			mini(va, vb), maxi(va, vb), t_for_va if va <= vb else 1.0 - t_for_va]
	if cut_verts.has(pos_key):
		cut_verts[edge_key] = cut_verts[pos_key]
		return cut_verts[pos_key]
	if cut_verts.has(edge_key):
		return cut_verts[edge_key]
	var vi: int = mesh.append_vertex_lerp(va, vb, pos, t_for_va)
	cut_verts[pos_key] = vi
	cut_verts[edge_key] = vi
	return vi


## Crossing for a point that lies on the face's boundary — exactly at a ring
## vertex ([param snapped_vi]) or anywhere on the ring.  {} when interior.
## The returned dict carries "va"/"vb" (the ring-edge vertex INDICES the
## crossing sits on) so phase 2 stays correct even after earlier splits
## shifted ring slots.
static func _endpoint_crossing(
		mesh: GoBuildMesh,
		face: GoBuildFace,
		p: Vector3,
		snapped_vi: int,
) -> Dictionary:
	var ring := face.vertex_indices
	for i: int in ring.size():
		if snapped_vi >= 0 and ring[i] == snapped_vi:
			return {"pos": (i - 1 + ring.size()) % ring.size(), "u": 1.0, "point": p,
					"va": ring[(i - 1 + ring.size()) % ring.size()], "vb": ring[i]}
		var va: Vector3 = mesh.vertices[ring[i]]
		var vb: Vector3 = mesh.vertices[ring[(i + 1) % ring.size()]]
		var edge := vb - va
		var t: float = (p - va).dot(edge) / maxf(edge.length_squared(), _EPSILON)
		if t >= -_EPSILON and t <= 1.0 + _EPSILON \
				and va.lerp(vb, clampf(t, 0.0, 1.0)).distance_to(p) < 1e-3:
			return {"pos": i, "u": clampf(t, 0.0, 1.0), "point": p,
					"va": ring[i], "vb": ring[(i + 1) % ring.size()]}
	return {}


# ---------------------------------------------------------------------------
# Three-phase pipeline
# ---------------------------------------------------------------------------

static func apply(mesh: GoBuildMesh, points: Array, closed: bool = false,
		edge_hits: Array = []) -> bool:
	# 2-point strokes are valid SEAMS (a drawn edge between two ring
	# points) — only an empty stroke bails.
	if mesh == null or points.size() < 2:
		return false
	var v0: int = mesh.vertices.size()
	var e0: int = mesh.edges.size()
	var f0: int = mesh.faces.size()

	var cut_verts: Dictionary = {}   # canonical edge key → vertex index
	var any_split := false

	# ── Phase 1.5: injected screen-space edge crossings — the camera-visible
	# edge pierces the caller computed (controller projects the stroke through
	# the CURRENT camera; a straight 3D segment between picks on adjacent
	# faces tunnels the shared corner edge, but on screen it visibly crosses).
	# The crossing points are inserted INTO the stroke (Blender: the drawn
	# path runs through the crossings — they become on-ring picked points,
	# so run resolution anchors them as members, no T-junctions).
	if not edge_hits.is_empty():
		var order: Array = edge_hits.duplicate()
		order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a["segment"] != b["segment"]:
				return a["segment"] < b["segment"]
			return a["t"] < b["t"])
		var augmented: Array = []
		for s: int in points.size():
			augmented.append(points[s])
			for hit: Dictionary in order:
				if hit["segment"] != s:
					continue
				# A face of the crossed edge hosts the crossing point.
				var ei := mesh.find_edge(hit["edge_a"], hit["edge_b"])
				var fi: int = mesh.edges[ei].face_indices[0] if ei >= 0 \
						and not mesh.edges[ei].face_indices.is_empty() else -1
				augmented.append({
					"face_index": fi,
					"position": hit["point"],
				})
		points = augmented
	# The split vertices ride the affected faces' rings; resolve runs AFTER
	# the injection so each crossing registers as an on-ring member.
	var runs := _resolve_runs(mesh, points, closed)
	if runs.is_empty():
		print("[KnifeGeom] no resolvable runs — nothing to cut")
		return false

	# ── Phase 2: split every crossed edge (both neighbours updated).
	for run: Dictionary in runs:
		_split_run_edges(mesh, run, cut_verts)

	# ── Phase 3: re-tessellate each run's face around its path.
	# Transactional: a failed run (anchor resolution, revisit, bowtie)
	# rolls the whole apply back — a half-applied stroke left orphaned
	# cut verts behind (garbage the undo could not even remove, since
	# the undo snapshot was taken before the op that "succeeded").
	var snapshot := mesh.take_snapshot()
	var ok := true
	for run: Dictionary in runs:
		if not _tessellate_run(mesh, run, cut_verts):
			if not run.get("no_op", false):
				ok = false
				break
	if not ok:
		mesh.restore_snapshot(snapshot)
		print("[KnifeGeom] apply rolled back — a run failed to partition")
		return false
	any_split = true
	# Reconcile: split_edge mutated rings, _emit_ngon re-registered faces —
	# compact_edges drops orphaned old edge objects and remaps the lookup.
	mesh.compact_edges()
	mesh.refresh_edge_face_indices()
	# Fully incremental — persistent edges maintained via split_edge/register;
	# validate catches any drift in debug builds.
	mesh.validate_edge_topology()
	if any_split:
		print("[KnifeGeom] applied: %s (faces=%d verts=%d edges=%d)" % [
				_delta_str(mesh.faces.size() - f0, mesh.vertices.size() - v0,
						mesh.edges.size() - e0),
				mesh.faces.size(), mesh.vertices.size(), mesh.edges.size()])
	return any_split


## Geometry delta as "+Xf +Yv +Ze" (only non-zero terms; "+0f +0v +0e" when all
## zero — a close riding existing edges).
static func _delta_str(df: int, dv: int, de: int) -> String:
	var parts: Array[String] = []
	if df != 0:
		parts.append("%+df" % df)
	if dv != 0:
		parts.append("%+dv" % dv)
	if de != 0:
		parts.append("%+de" % de)
	return " ".join(parts) if not parts.is_empty() else "+0f +0v +0e"


## Screen-space edge crossings (Blender's knife model): project the stroke
## polyline through [param camera] and record where each segment visibly
## crosses a MESH EDGE on screen — the projected path is authoritative, the
## 3D segment between picks on adjacent faces tunnels the shared corner edge.
## The 3D crossing point comes from a ray-edge closest approach: the screen
## crossing's ray (through the camera) intersected with the 3D edge line.
## Returns [{ "segment": int, "edge_a": int, "edge_b": int, "t": float,
## "point": Vector3 }] — "t" = the parameter along edge_a→edge_b.
static func screen_edge_hits(
		mesh: GoBuildMesh,
		points: Array,
		closed: bool,
		camera: Camera3D,
		to_world: Transform3D,
) -> Array:
	var out: Array = []
	var n: int = points.size()
	var seg_count: int = n if closed else n - 1
	for s: int in seg_count:
		var wa: Vector3 = to_world * (points[s]["position"] as Vector3)
		var wb: Vector3 = to_world * (
				points[(s + 1) % n]["position"] as Vector3)
		var sa: Vector2 = camera.unproject_position(wa)
		var sb: Vector2 = camera.unproject_position(wb)
		var seg := sb - sa
		var len_sq: float = seg.length_squared()
		if len_sq < 1e-9:
			continue
		for ei: int in mesh.edges.size():
			var e: GoBuildEdge = mesh.edges[ei]
			var we_a: Vector3 = to_world * mesh.vertices[e.vertex_a]
			var we_b: Vector3 = to_world * mesh.vertices[e.vertex_b]
			# Skip edges the segment endpoint sits on (snapped picks) —
			# those are handled as run members, not piercings.
			var sea: Vector2 = camera.unproject_position(we_a)
			var seb: Vector2 = camera.unproject_position(we_b)
			var eseg := seb - sea
			var e_len_sq: float = eseg.length_squared()
			if e_len_sq < 1e-9:
				continue
			# Screen-space segment-segment intersection.
			var denom_v := seg.x * eseg.y - seg.y * eseg.x
			if absf(denom_v) < 1e-9:
				continue   # Parallel — no unique crossing.
			var diff := sea - sa
			var t := (diff.x * eseg.y - diff.y * eseg.x) / denom_v
			var u := (diff.x * seg.y - diff.y * seg.x) / denom_v
			if t <= 1e-4 or t >= 1.0 - 1e-4 or u <= 1e-4 or u >= 1.0 - 1e-4:
				continue
			# 3D point: ray through the screen crossing vs the edge line.
			var screen_p := sa + seg * t
			var ray_origin: Vector3 = camera.project_ray_origin(screen_p)
			var ray_dir: Vector3 = camera.project_ray_normal(screen_p)
			var hit := _ray_line_closest(ray_origin, ray_dir, we_a, we_b)
			if hit.is_empty():
				continue
			var k: float = hit["u"]
			if k <= 1e-4 or k >= 1.0 - 1e-4:
				continue   # Crossing at the edge's endpoint — a vertex.
			# TUNNELING GATE: inject only when the straight 3D segment
			# actually misses the edge (tunnels past it) — the screen path
			# and the 3D chord must disagree.  A crossing of a COPLANAR
			# edge (previous cuts in the same plane) is found by the
			# resolver's face_crossings; injecting it too created spurious
			# stroke points with wrong host faces and scattered single-face
			# loops into broken runs.
			var seg_d := wb - wa
			var seg_len: float = seg_d.length()
			if seg_len < 1e-9:
				continue
			var seg_dir := seg_d / seg_len
			var to_e := we_a - wa
			var closest_on_seg: float = clampf(to_e.dot(seg_dir), 0.0, seg_len)
			var seg_p := wa + seg_dir * closest_on_seg
			# Point-line distance from the 3D edge line to the segment.
			var e_dir := (we_b - we_a).normalized()
			var e_closest: float = clampf((seg_p - we_a).dot(e_dir),
					0.0, we_a.distance_to(we_b))
			var d3: float = seg_p.distance_to(we_a + e_dir * e_closest)
			# Scale reference: the longer of the two 3D segments.
			var scale_ref: float = maxf(seg_len, we_a.distance_to(we_b))
			if d3 < scale_ref * 0.01:
				continue   # Coplanar/adjacent — the resolver handles it.
			# OCCLUSION CULL: the edge must be VISIBLE at the crossing —
			# the camera ray through the screen crossing point must reach
			# the edge point without a front-facing face in front of it.
			# Without this, edges on the BACK side of the mesh (behind the
			# surface the stroke is drawn on) inject crossings: the stroke
			# gains points on far faces, the resolver's single-face owner
			# fails and the drawn polygon scatters into touch-point runs
			# (the closed quad never resolved as a loop).
			# face_t == INF (ray grazes the silhouette) is NOT free passage:
			# far-side edges project inside the outline too, and preview
			# dots for them drew far behind the mesh.  A crossing outside
			# the silhouette has no front-face hit at all — skip it.
			var edge_s: float = hit["s"]
			var face_t := _nearest_face_ray_t(mesh, to_world, ray_origin,
					ray_dir)
			if face_t == INF:
				continue   # Crossing outside the mesh's screen silhouette.
			if edge_s > face_t + scale_ref * 0.01:
				continue   # The edge point is behind the visible surface.
			out.append({
				"segment": s,
				"edge_a": e.vertex_a, "edge_b": e.vertex_b,
				"t": k,
				"point": to_world.affine_inverse() * hit["point"],
			})
	return out


## Closest approach of the camera ray (origin, unit dir) to the edge line
## (e0, e1).  Returns { "point": Vector3 (on the edge line), "u": float
## (0=e0..1=e1), "dist": float } — {} when parallel.  The caller bounds u.
static func _ray_line_closest(
		origin: Vector3,
		dir: Vector3,
		e0: Vector3,
		e1: Vector3,
) -> Dictionary:
	var e := e1 - e0
	var w := origin - e0
	var a: float = dir.dot(dir)
	var b: float = dir.dot(e)
	var c: float = e.dot(e)
	var d: float = dir.dot(w)
	var f: float = e.dot(w)
	var denom: float = a * c - b * b
	if absf(denom) < 1e-12:
		return {}
	var u: float = (a * f - b * d) / denom   # along the edge
	var s: float = (b * f - c * d) / denom   # along the ray
	var ray_p := origin + dir * s
	var edge_p := e0 + e * u
	return { "point": edge_p, "u": u, "s": s, "dist": ray_p.distance_to(edge_p) }


## Raycast (WORLD-space ray) against every face of [param mesh] transformed
## by [param to_world]; returns the smallest front-facing hit parameter t
## along the ray (INF when nothing is hit).  Mirrors PickingHelper's
## front-face gate (Newell normal + dot cull) so the knife's screen-space
## crossing injection ignores edges hidden behind the visible surface.
static func _nearest_face_ray_t(
		mesh: GoBuildMesh,
		to_world: Transform3D,
		ray_origin: Vector3,
		ray_dir: Vector3,
) -> float:
	var to_local: Transform3D = to_world.affine_inverse()
	var ro: Vector3 = to_local * ray_origin
	var rd: Vector3 = (to_local.basis * ray_dir).normalized()
	var best := INF
	for fi: int in mesh.faces.size():
		var face: GoBuildFace = mesh.faces[fi]
		var ring := face.vertex_indices
		if ring.size() < 3:
			continue
		var verts: Array[Vector3] = []
		for vi: int in ring:
			verts.append(mesh.vertices[vi])
		var n: Vector3 = _TRIANGULATE_SCRIPT.polygon_normal(verts)
		if n.length_squared() < 1e-12 or rd.dot(n) >= 0.0:
			continue
		for tri: Array in _TRIANGULATE_SCRIPT.ear_clip(verts, n):
			var t: float = _ray_triangle(ro, rd, verts[tri[0]],
					verts[tri[1]], verts[tri[2]])
			if t >= 0.0 and t < best:
				best = t
	return best


## Möller–Trumbore ray-triangle (mesh-local, two-sided hit test).
static func _ray_triangle(
		o: Vector3,
		d: Vector3,
		v0: Vector3,
		v1: Vector3,
		v2: Vector3,
) -> float:
	var e1 := v1 - v0
	var e2 := v2 - v0
	var h := d.cross(e2)
	var a: float = e1.dot(h)
	if absf(a) < 1e-9:
		return -1.0
	var f := 1.0 / a
	var s := o - v0
	var u: float = f * s.dot(h)
	if u < 0.0 or u > 1.0:
		return -1.0
	var q := s.cross(e1)
	var v: float = f * d.dot(q)
	if v < 0.0 or u + v > 1.0:
		return -1.0
	var t: float = f * e2.dot(q)
	return t if t >= 1e-9 else -1.0


## Phase 1 — group the picked points into per-face runs over the stroke CYCLE
## (closed strokes wrap: the closing segment last→first is part of the path).
## Blender semantics: interior run ends stay interior (no ray extension, no
## invented geometry); a run is a LOOP only when the whole stroke stays on one
## face.  Run ends get their boundary crossings from the INCOMING/OUTGOING
## segments (where the path pierces the face's ring edges), so single-point
## pass-through faces cut correctly instead of being dropped.
## Returns [{ "face_index", "points", "entry", "exit", "is_loop" }] where
## entry/exit are face_crossings dicts ({ "pos", "t", "u", "point" }) or {}.
## Clamp [param p] to [param face]: inside or on the ring → unchanged; outside
## → the nearest point on the ring (projection onto the closest ring edge).
## Blender keeps every cut point ON the surface; off-face points made the
## closed-loop band stitching fold (bowties).
static func _clamp_to_face(mesh: GoBuildMesh, face: GoBuildFace, p: Vector3) -> Vector3:
	var ring := face.vertex_indices
	if _point_in_poly(mesh, p, ring):
		return p
	var best := p
	var best_d := INF
	for i: int in ring.size():
		var a: Vector3 = mesh.vertices[ring[i]]
		var b: Vector3 = mesh.vertices[ring[(i + 1) % ring.size()]]
		var ab := b - a
		var t: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), _EPSILON), 0.0, 1.0)
		var q: Vector3 = a.lerp(b, t)
		var d: float = q.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = q
	return best


## Point-in-polygon test (face plane, 2D crossing count).  Points within
## [code]1e-4[/code] of the ring count as inside (on-boundary is valid).
static func _point_in_poly(mesh: GoBuildMesh, p: Vector3, ring: Array[int]) -> bool:
	var poly: Array[Vector3] = []
	for vi: int in ring:
		poly.append(mesh.vertices[vi])
	var n: Vector3 = _TRIANGULATE_SCRIPT.polygon_normal(poly)
	if n.length_squared() < _EPSILON * _EPSILON:
		return false
	# On-ring points are inside (the ray test is undefined on the max-y
	# edge — no edge spans the ray at the polygon's extreme y).
	for i: int in ring.size():
		if _point_on_ring_edge(mesh, p, ring[i], ring[(i + 1) % ring.size()]):
			return true
	var origin: Vector3 = mesh.vertices[ring[0]]
	var u := (mesh.vertices[ring[1]] - mesh.vertices[ring[0]]).normalized()
	var w := n.cross(u)
	var pi_p := Vector2(u.dot(p - origin), w.dot(p - origin))
	var inside := false
	var j: int = ring.size() - 1
	for i: int in ring.size():
		var a := Vector2(u.dot(mesh.vertices[ring[i]] - origin),
				w.dot(mesh.vertices[ring[i]] - origin))
		var b := Vector2(u.dot(mesh.vertices[ring[j]] - origin),
				w.dot(mesh.vertices[ring[j]] - origin))
		if (a.y > pi_p.y) != (b.y > pi_p.y):
			# The branch condition guarantees dy != 0 (and can be negative —
			# a downward edge); clamping the denominator to +EPSILON turned
			# every downward edge into interp = ±1e6 and broke the test.
			var interp: float = b.x + (a.x - b.x) * (pi_p.y - b.y) \
					/ (a.y - b.y)
			if pi_p.x < interp:
				inside = not inside
		j = i
	return inside


## One face containing every picked point (boundary counts — _point_in_poly
## accepts on-ring points): the geometric owner for a closed stroke whose
## points were picked under scattered cursor-faces.  Candidates = the first
## point's picked face + the faces sharing its containing ring edge(s).
## Points must also lie ON the candidate's PLANE — _point_in_poly projects
## onto the plane (cross-plane points fold onto ring edges and read as
## "on-boundary"), which collapsed a 4,2,2,4 two-face stroke into a
## single-face loop on the wrong face.
## Returns -1 when no single face holds all points (genuinely multi-face
## stroke — leave the picked grouping alone).
static func _single_face_owner(mesh: GoBuildMesh, picked: Array) -> int:
	# Candidate faces: every point's picked face plus the faces sharing
	# its ring edges/vertices.  A snap-grabbed shared element recorded
	# under the wrong cursor-face sits on the NEIGHBOUR's ring — its
	# adjacency is the only route to the true owner face.
	var candidates: Array = []
	var seen := {}
	for p: Dictionary in picked:
		var fi: int = p["face_index"]
		if fi < 0 or fi >= mesh.faces.size():
			continue
		for fi2: int in [fi] + _faces_adjacent_to_point(mesh,
				mesh.faces[fi], p["position"]):
			if not seen.has(fi2):
				seen[fi2] = true
				candidates.append(fi2)
	for fi: int in candidates:
		var face: GoBuildFace = mesh.faces[fi]
		# Plane gate: the stroke must lie in the candidate's plane (distance
		# to the plane along its normal, tolerance for float noise).
		var ring: Array[int] = face.vertex_indices
		var poly: Array[Vector3] = []
		for vi: int in ring:
			poly.append(mesh.vertices[vi])
		var n := _TRIANGULATE_SCRIPT.polygon_normal(poly)
		if n.length_squared() < _EPSILON * _EPSILON:
			continue
		if _point_to_plane_dist(mesh.vertices[ring[0]], n,
				(picked[0]["position"] as Vector3)) > 1e-3:
			continue
		var all_in := true
		for p: Dictionary in picked:
			if _point_to_plane_dist(mesh.vertices[ring[0]], n,
					p["position"] as Vector3) > 1e-3 \
					or not _point_in_poly(mesh, p["position"], ring):
				all_in = false
				break
		if all_in:
			return fi
	return -1


## Perpendicular distance of [param p] from the plane through [param origin]
## with unit normal [param n] (normalised here — callers pass a fresh normal).
static func _point_to_plane_dist(origin: Vector3, n: Vector3, p: Vector3) -> float:
	return absf(n.normalized().dot(p - origin))


## The face whose polygon contains [param p] (coplanar partitioned
## surfaces: the cursor-face hint [param prefer] is tried first, then
## every face in the mesh).  On-boundary counts as containing.  The point
## must also lie ON the face's PLANE — _point_in_poly projects onto the
## plane and a cross-plane point folds onto a shared edge and reads as
## "inside" (the re-pick then scatters the stroke across planes).
## Returns -1 when no face holds the point.
static func _face_containing(mesh: GoBuildMesh, p: Vector3, prefer: int) -> int:
	var order: Array = []
	if prefer >= 0 and prefer < mesh.faces.size():
		order.append(prefer)
	for fi: int in mesh.faces.size():
		if fi != prefer:
			order.append(fi)
	for fi: int in order:
		if _face_holds(mesh, fi, p):
			return fi
	return -1


## Plane + polygon containment for the re-pick (see _face_containing).
static func _face_holds(mesh: GoBuildMesh, fi: int, p: Vector3) -> bool:
	var ring: Array[int] = mesh.faces[fi].vertex_indices
	var poly: Array[Vector3] = []
	for vi: int in ring:
		poly.append(mesh.vertices[vi])
	var n := _TRIANGULATE_SCRIPT.polygon_normal(poly)
	if n.length_squared() < _EPSILON * _EPSILON:
		return false
	if _point_to_plane_dist(mesh.vertices[ring[0]], n.normalized(), p) > 1e-3:
		return false
	return _point_in_poly(mesh, p, ring)


## Faces sharing a ring edge that the point lies on (or a ring vertex) —
## the neighbour faces through which the same physical point is reachable.
static func _faces_adjacent_to_point(
		mesh: GoBuildMesh,
		face: GoBuildFace,
		p: Vector3,
) -> Array[int]:
	var out: Array[int] = []
	var ring: Array[int] = face.vertex_indices
	for i: int in ring.size():
		var va: int = ring[i]
		var vb: int = ring[(i + 1) % ring.size()]
		var a: Vector3 = mesh.vertices[va]
		var b: Vector3 = mesh.vertices[vb]
		var ab := b - a
		var t: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), _EPSILON),
				0.0, 1.0)
		if a.lerp(b, t).distance_to(p) > 1e-3:
			continue
		var ei: int = mesh.find_edge(va, vb)
		if ei < 0:
			continue
		for fi: int in mesh.edges[ei].face_indices:
			if fi != mesh.faces.find(face) and not out.has(fi):
				out.append(fi)
	return out


static func _resolve_runs(mesh: GoBuildMesh, points: Array, closed: bool) -> Array:
	var picked: Array = []
	for p: Dictionary in points:
		picked.append({"face_index": p["face_index"], "position": p["position"]})
	# A closing click duplicates the first point — drop it so the cycle is
	# p0..p(n-1) with the wrap segment p(n-1)→p0 doing the closing.
	if closed and picked.size() >= 2 \
			and (picked[0]["position"] as Vector3) \
					.distance_to(picked[picked.size() - 1]["position"] as Vector3) < 1e-3:
		picked.pop_back()
	if picked.size() < 2:
		return []

	var n: int = picked.size()
	# ALL strokes (open or closed) with every point on ONE face: remap to
	# that geometric owner.  Snapped picks land on shared ring vertices/edges
	# and are recorded under the CURSOR face — which may be a side face
	# while the drawn chord runs across the cap.  The closed branch handled
	# this; an OPEN 2-point stroke (corner-to-corner seam) never remapped,
	# both runs resolved entry==exit ("single touch point") and inserted
	# nothing.  Open-stroke consensus is only safe when ALL points agree on
	# one owner (an open stroke may legitimately span several faces).
	var owner := _single_face_owner(mesh, picked)
	if owner >= 0:
		for p: Dictionary in picked:
			p["face_index"] = owner
	elif closed:
		# No single face holds the stroke (the drawn polygon spans
		# several coplanar faces — earlier cuts partitioned the
		# surface).  Re-pick each point's face geometrically: the
			# first candidate face (picked face, then ring-adjacent ones)
			# whose polygon contains the point.  Without this, points
			# recorded under one cursor-face keep that face and the runs
			# cut only part of the drawn polygon (half the quad missing).
			for p: Dictionary in picked:
				var fi_cur: int = p["face_index"]
				if fi_cur >= 0 and fi_cur < mesh.faces.size() \
						and _point_in_poly(mesh, p["position"],
								mesh.faces[fi_cur].vertex_indices):
					continue   # Picked face already holds it.
				var fi_new := _face_containing(mesh, p["position"], fi_cur)
				if fi_new >= 0:
					p["face_index"] = fi_new
	# Clamp to the (remapped) face: a click past the face boundary must
	# cut the boundary, not hang the path in empty space (Blender keeps
	# every cut point on the surface; off-face points produced bowties).
	for p: Dictionary in picked:
		p["position"] = _clamp_to_face(mesh, mesh.faces[p["face_index"]],
				p["position"])
	# Group consecutive same-face indices; segment s_i joins picked[i] →
	# picked[(i+1) % n] (wrap only when closed).
	var groups: Array = []
	for i: int in n:
		var fi: int = picked[i]["face_index"]
		if not groups.is_empty() and (groups[groups.size() - 1]["face_index"] as int) == fi:
			(groups[groups.size() - 1]["indices"] as Array).append(i)
		else:
			groups.append({"face_index": fi, "indices": [i]})
	# Closed cycle: a trailing group on the same face as the leading one is
	# the path returning — merge (cycle order: trail → lead).
	if closed and groups.size() > 1 \
			and (groups[0]["face_index"] as int) == (groups[groups.size() - 1]["face_index"] as int):
		var lead: Array = groups[0]["indices"]
		var trail: Array = groups[groups.size() - 1]["indices"]
		var merged: Array = []
		merged.assign(trail)
		merged.append_array(lead)
		groups[0]["indices"] = merged
		groups.pop_back()

	# Same-face groups can still LEAVE their face mid-group: a stroke
	# drawn across coplanar bands (earlier cuts) with all clicks picked
	# under one face index crosses the bands' shared ring edges between
	# clicks.  Split such a group at every geometric ring exit: the
	# crossing point closes the current run and starts the next run on
	# the neighbour face across the crossed edge.  Without this, the
	# neighbour's territory inside the drawn polygon is never cut (the
	# "incomplete quad" — only one face's part was partitioned).
	# OPEN strokes too: with the owner remap above, a snapped pick under a
	# side-face index remaps to the cap — but a genuinely multi-face open
	# stroke (pick A under face X, pick B under face Y) still groups into
	# two touch runs whose segment never re-pierces either face's ring
	# (the chord is skew to both planes).  The exit-split turns the runs
	# into entry/exit-anchored bands on the right faces.
	groups = _split_groups_at_exits(mesh, picked, groups)

	var is_loop: bool = closed and groups.size() == 1
	var resolved: Array = []
	for g: Dictionary in groups:
		var indices: Array = g["indices"]
		var first_i: int = indices[0]
		var last_i: int = indices[indices.size() - 1]
		var face: GoBuildFace = mesh.faces[g["face_index"]]
		var pts: Array = []
		for idx: int in indices:
			pts.append(picked[idx]["position"])
		# Drop consecutive duplicates — off-face clicks clamp to the SAME
		# ring point (same corner/edge spot), and a repeated point makes the
		# path revisit a vertex, which no valid band polygon can absorb.
		var deduped: Array = []
		for p: Variant in pts:
			if deduped.is_empty() \
					or (deduped[deduped.size() - 1] as Vector3).distance_to(p as Vector3) > 1e-3:
				deduped.append(p)
		pts = deduped
		# Entry: where the INCOMING segment pierces this face's ring, closest
		# to the run's first point (largest t).  Open-stroke first run has no
		# incoming segment — fall back to the point itself when it lies on the
		# ring (edge-to-edge cut); otherwise {} (interior loose end).
		var entry: Dictionary = {}
		var prev_i: int = (first_i - 1 + n) % n
		if closed or first_i > 0:
			entry = _crossing_nearest_to_end(mesh, face,
					picked[prev_i]["position"], picked[first_i]["position"])
		# An OPEN-stroke start ON the ring (edge-snapped end) must not shadow
		# the segment's own ring exit: the first pick is where the path STARTS,
		# but the ring edge it crosses (or re-enters through) may lie further
		# along — the run must partition at that crossing too (a 2-point
		# stroke would otherwise resolve as two touch points and cut nothing).
		if entry.is_empty():
			entry = _endpoint_crossing(mesh, face, pts[0], -1)
		if entry.is_empty() and pts.size() >= 2:
			entry = _crossing_nearest(mesh, face,
					picked[first_i]["position"], picked[indices[1]]["position"],
					false)
		if entry.is_empty() and (closed or first_i > 0):
			# The incoming PICK may itself sit on this face's ring (a snap
			# grabbed a shared-edge vertex under the NEIGHBOUR's face index
			# — the run then starts at that member, not at a nearest
			# corner).  The crossing at the segment start (t=0) is excluded
			# from _crossing_nearest_to_end, so test the point directly.
			entry = _endpoint_crossing(mesh, face,
					picked[prev_i]["position"], -1)
		# Exit: where the OUTGOING segment pierces the ring, closest to the
		# run's last point (smallest t).  Open-stroke last run: the point
		# itself when on the ring, else {} (interior loose end).
		var exit: Dictionary = {}
		var next_i: int = (last_i + 1) % n
		if closed or last_i < n - 1:
			exit = _crossing_nearest(mesh, face,
					picked[last_i]["position"], picked[next_i]["position"],
					false)
		if exit.is_empty():
			exit = _endpoint_crossing(mesh, face, pts[pts.size() - 1], -1)
		if exit.is_empty() and pts.size() >= 2:
			# Open-stroke end on the ring: the ring edge the SECOND-to-last
			# segment crosses (toward the last pick) is the run's real exit —
			# without it a 2-point stroke resolves as two touch points.
			exit = _crossing_nearest_to_end(mesh, face,
					picked[indices[indices.size() - 2]]["position"],
					picked[last_i]["position"])
		if exit.is_empty() and (closed or last_i < n - 1):
			# Same for the OUTGOING point (the next run's first point may
			# be a shared ring member this run's path walks toward).
			exit = _endpoint_crossing(mesh, face,
					picked[next_i]["position"], -1)
		resolved.append({
			"face_index": g["face_index"],
			"points": pts,
			"entry": entry,
			"exit": exit,
			"is_loop": is_loop,
		})
	return resolved


## Split same-face groups at geometric ring exits: a segment between two
## picks of one group may leave the group's face (the drawn path crosses
## the shared ring edge into a coplanar neighbour — the clicks were all
## recorded under the same cursor-face).  Each exit truncates the group
## and starts the next group on the neighbour face across the crossed
## edge, so the neighbour's territory inside the drawn polygon gets cut
## too (Blender cuts every face the path crosses).
## The picked entries gain synthetic boundary points at the crossings
## (position-keyed via get_or_create in phase 2 — the same physical
## point on both sides dedupes).
static func _split_groups_at_exits(
		mesh: GoBuildMesh,
		picked: Array,
		groups: Array,
) -> Array:
	var n: int = picked.size()
	var out: Array = []
	for g: Dictionary in groups:
		var indices: Array = g["indices"]
		var fi: int = g["face_index"]
		if fi < 0 or fi >= mesh.faces.size():
			out.append(g)
			continue
		var face: GoBuildFace = mesh.faces[fi]
		var walk: Array = []   # [{ "index": int (picked idx or -1 synthetic), "position", "face_index" }]
		var run_face := fi
		for k: int in indices.size():
			var idx: int = indices[k]
			walk.append({"index": idx, "position": picked[idx]["position"],
					"face_index": run_face})
			if k == indices.size() - 1:
				break
			var next_idx: int = indices[k + 1]
			var seg_a: Vector3 = picked[idx]["position"]
			var seg_b: Vector3 = picked[next_idx]["position"]
			# Does the segment exit the CURRENT run face mid-way?
			var crossings := face_crossings(seg_a, seg_b, mesh, face)
			# Exit = the crossing with the SMALLEST t past the current
			# point (the first ring pierce after leaving seg_a).
			var exit_c: Dictionary = {}
			for c: Dictionary in crossings:
				if c["t"] > 1e-4 and c["t"] < 1.0 - 1e-4:
					exit_c = c
					break
			if exit_c.is_empty():
				continue
			# Graze check: the segment just past the crossing must be
			# OUTSIDE the face — a ring VERTEX graze (the segment clips
			# a corner but stays inside) must not split the run (it
			# threw the rest of the path to the neighbour and reshaped
			# the drawn polygon).
			var past_t: float = minf(exit_c["t"] + 0.05, 1.0)
			var past_p: Vector3 = seg_a.lerp(seg_b, past_t)
			if _point_in_poly(mesh, past_p, face.vertex_indices):
				continue
			# The neighbour face across the crossed ring edge.
			var ei := mesh.find_edge(exit_c["va"], exit_c["vb"])
			var next_fi := -1
			if ei >= 0:
				for fj: int in mesh.edges[ei].face_indices:
					if fj != run_face:
						next_fi = fj
						break
			if next_fi < 0:
				continue
			# Synthetic boundary point at the crossing.
			walk.append({"index": -1, "position": exit_c["point"],
					"face_index": next_fi})
			# The next picked point continues on the neighbour face.
			run_face = next_fi
			picked[next_idx]["face_index"] = next_fi
		# Regroup the walk into same-face runs.
		var cur: Dictionary = {}
		for w: Dictionary in walk:
			if not cur.is_empty() \
					and (cur["face_index"] as int) == w["face_index"]:
				(cur["indices"] as Array).append(w)
			else:
				if not cur.is_empty():
					out.append(cur)
				cur = {"face_index": w["face_index"], "indices": [w]}
		if not cur.is_empty():
			out.append(cur)
	# Rebuild the groups into the resolver's shape: synthetic points get
	# appended to `picked` and the groups reference their indices.
	var result: Array = []
	for g: Dictionary in out:
		var idx_list: Array = []
		for w: Dictionary in g["indices"]:
			if w["index"] == -1:
				picked.append({"face_index": w["face_index"],
						"position": w["position"]})
				idx_list.append(picked.size() - 1)
			else:
				idx_list.append(w["index"])
		result.append({"face_index": g["face_index"], "indices": idx_list})
	return result


## Crossings of segment [param from]→[param to] with [param face]'s ring,
## returning the one nearest to [param to] (largest t — the path ENTERS the
## face there), with "va"/"vb" ring-edge vertex indices added.  Crossings AT
## the segment endpoints (t≈0/1) are excluded — those are picked points, not
## piercings; the on-ring case is handled by the _endpoint_crossing fallback.
## {} when the segment stays inside or misses.
static func _crossing_nearest_to_end(
		mesh: GoBuildMesh,
		face: GoBuildFace,
		from: Vector3,
		to: Vector3,
) -> Dictionary:
	return _crossing_nearest(mesh, face, from, to, true)


## Crossings of segment [param from]→[param to] with [param face]'s ring,
## returning the one nearest to the [param prefer_end] endpoint, with
## "va"/"vb" ring-edge vertex indices added.  Crossings AT the chosen
## endpoint (t≈1 when preferring the end / t≈0 the start) are accepted
## only when the crossing point IS that endpoint (corner crossing);
## other endpoint degenerates are shadow crossings from adjacent ring
## edges at the same corner — skipped.  {} when the segment stays inside
## or misses.
static func _crossing_nearest(
		mesh: GoBuildMesh,
		face: GoBuildFace,
		from: Vector3,
		to: Vector3,
		prefer_end: bool,
) -> Dictionary:
	var crossings := face_crossings(from, to, mesh, face)
	if crossings.is_empty():
		return {}
	var ring := face.vertex_indices
	var end_point: Vector3 = to if prefer_end else from
	# Endpoint ON the ring (within tolerance)?  That corner IS the crossing.
	for c: Dictionary in crossings:
		var near_end: bool = (c["t"] >= 1.0 - _EPSILON) if prefer_end \
				else (c["t"] <= _EPSILON)
		if near_end \
				and (c["point"] as Vector3).distance_to(end_point) < 1e-4:
			c["va"] = ring[c["pos"]]
			c["vb"] = ring[(int(c["pos"]) + 1) % ring.size()]
			return c
	# Otherwise the nearest crossing strictly inside the segment; endpoint
	# degenerates are shadow crossings from adjacent ring edges — skip them.
	var order := range(crossings.size())
	if prefer_end:
		order.reverse()
	for i: int in order:
		var c: Dictionary = crossings[i]
		var at_end: bool = (c["t"] >= 1.0 - _EPSILON) if prefer_end \
				else (c["t"] <= _EPSILON)
		if at_end:
			continue
		c["va"] = ring[c["pos"]]
		c["vb"] = ring[(int(c["pos"]) + 1) % ring.size()]
		return c
	return {}


## Phase 2 — REAL edge split via [method GoBuildMesh.split_edge]: the cut
## vertex is inserted into the ring of EVERY face containing the crossed
## edge, and the edge object splits into both halves (hard state inherited).
## No T-junctions.  Cut vertex indices are recorded on the run as
## "entry_vi"/"exit_vi" (indices are the stable reference across mutations).
## An edge pierced MULTIPLE times by the stroke (path re-crosses a shared
## edge) is split SEQUENTIALLY: after the first split the direct edge is
## gone, so the second cut splits the sub-edge containing its position.
static func _split_run_edges(mesh: GoBuildMesh, run: Dictionary, cut_verts: Dictionary) -> void:
	for key: String in ["entry", "exit"]:
		var cross: Dictionary = run[key]
		if cross.is_empty() or cross["u"] <= _EPSILON or cross["u"] >= 1.0 - _EPSILON:
			continue   # Crossing at a ring vertex — no split needed.
		var cut_vi := _split_edge_at(mesh, cross["va"], cross["vb"],
				cross["u"], cut_verts)
		run[key + "_vi"] = cut_vi


## Split the va→vb line at ring-directed [param u], handling already-split
## lines: the sub-chain between va and vb is read from a face RING (rings
## are the post-split authority — edge objects are stale until reconcile),
## and the sub-edge containing [param u] is split.  Returns the cut vertex
## index (-1 on failure).
static func _split_edge_at(
		mesh: GoBuildMesh,
		va: int,
		vb: int,
		u: float,
		cut_verts: Dictionary,
) -> int:
	var chain := _sub_chain(mesh, va, vb)
	if chain.size() < 2:
		return -1
	var full_len: float = mesh.vertices[va].distance_to(mesh.vertices[vb])
	var acc: float = 0.0
	for k: int in chain.size() - 1:
		var a: int = chain[k]
		var b: int = chain[k + 1]
		var seg_len: float = mesh.vertices[a].distance_to(mesh.vertices[b])
		var seg_t: float = seg_len / maxf(full_len, _EPSILON)
		if u <= acc + seg_t or k == chain.size() - 2:
			var local_u: float = clampf((u - acc) / maxf(seg_t, _EPSILON), 0.0, 1.0)
			return _split_single_edge(mesh, a, b, local_u, cut_verts)
		acc += seg_t
	return -1


## The vertex chain between [param va] and [param vb] along the original
## line, read from a face ring containing both (post-split authority).  Only
## vertices lying ON the va→vb segment are kept, in va→vb order.
static func _sub_chain(mesh: GoBuildMesh, va: int, vb: int) -> Array[int]:
	for fi: int in mesh.faces.size():
		var ring: Array[int] = mesh.faces[fi].vertex_indices
		var start: int = ring.find(va)
		if start == -1 or not ring.has(vb):
			continue
		var chain: Array[int] = [va]
		var k: int = (start + 1) % ring.size()
		while k != start:
			var vi: int = ring[k]
			if _point_on_ring_edge(mesh, mesh.vertices[vi], va, vb):
				chain.append(vi)
			if vi == vb:
				return chain
			k = (k + 1) % ring.size()
	return [va, vb]


## True when [param p] lies on the segment mesh.vertices[va]→mesh.vertices[vb]
## (collinear + within segment, tolerance for float noise).
static func _point_on_ring_edge(mesh: GoBuildMesh, p: Vector3, va: int, vb: int) -> bool:
	var a: Vector3 = mesh.vertices[va]
	var b: Vector3 = mesh.vertices[vb]
	var ab := b - a
	var len_sq: float = ab.length_squared()
	if len_sq < 1e-12:
		return false
	var t: float = (p - a).dot(ab) / len_sq
	if t < -_EPSILON or t > 1.0 + _EPSILON:
		return false
	return a.lerp(b, clampf(t, 0.0, 1.0)).distance_to(p) < 1e-4


## Insert the cut vertex on the DIRECT sub-edge va—vb at [param u] into every
## ring containing that adjacency (ring-based, not split_edge — its edge
## lookup is stale after the first split of this line; apply() reconciles).
static func _split_single_edge(
		mesh: GoBuildMesh,
		va: int,
		vb: int,
		u: float,
		cut_verts: Dictionary,
) -> int:
	if u <= 1e-5:
		return va
	if u >= 1.0 - 1e-5:
		return vb
	var cut_vi := get_or_create_cut_vertex(mesh, va, vb, u, cut_verts)
	for fi: int in mesh.faces.size():
		var ring: Array[int] = mesh.faces[fi].vertex_indices
		for k: int in ring.size():
			var is_fwd: bool = ring[k] == va and ring[(k + 1) % ring.size()] == vb
			var is_bwd: bool = ring[k] == vb and ring[(k + 1) % ring.size()] == va
			if is_fwd or is_bwd:
				ring.insert(k + 1, cut_vi)
				mesh.faces[fi].vertex_indices = ring
				# Keep uvs aligned with the ring: insert a lerped UV at the
				# same slot (the crossing always knows its own parameter).
				var uvs: Array[Vector2] = mesh.faces[fi].uvs
				if uvs.size() == ring.size() - 1 and uvs.size() >= 2:
					var ua: Vector2 = uvs[k]
					var ub: Vector2 = uvs[(k + 1) % uvs.size()]
					uvs.insert(k + 1, ua.lerp(ub, u))
					mesh.faces[fi].uvs = uvs
				break
	return cut_vi


## Split every [param pts] entry lying on a ring edge of [param face]
## (interior of the edge — corners are reused via vertex reuse).  Each hit
## becomes a ring member shared with the neighbour face; the ring is
## re-read after every split and returned.
static func _split_on_edge_points(
		mesh: GoBuildMesh,
		face: GoBuildFace,
		pts: Array,
		ring: Array[int],
		cut_verts: Dictionary,
) -> Array[int]:
	for pi: int in pts.size():
		var p: Vector3 = pts[pi]
		for i: int in ring.size():
			var va: int = ring[i]
			var vb: int = ring[(i + 1) % ring.size()]
			if va == vb:
				continue
			var t: float = (p - mesh.vertices[va]).dot(
					mesh.vertices[vb] - mesh.vertices[va]) \
					/ maxf(mesh.vertices[vb].distance_squared_to(
							mesh.vertices[va]), _EPSILON)
			if t <= _EPSILON or t >= 1.0 - _EPSILON:
				continue   # At a corner — reuse handles it.
			var q: Vector3 = mesh.vertices[va].lerp(mesh.vertices[vb],
					clampf(t, 0.0, 1.0))
			if q.distance_to(p) > 1e-3:
				continue
			var cut_vi := _split_edge_at(mesh, va, vb, clampf(t, 0.0, 1.0),
					cut_verts)
			if cut_vi >= 0:
				# Ring changed — re-read it and restart the scan.
				ring = face.vertex_indices
				break
	return ring


## Phase 3 — re-partition the run's face around the path.
##
## BLENDER-ALIGNED: emits NGON faces (bake triangulates) — minimal geometry:
## the drawn path's edges are the only new edges, plus the stitching needed
## to keep the surface watertight.  Interior run ends connect to their
## nearest ring corner (Blender's loose-end behaviour).
static func _tessellate_run(mesh: GoBuildMesh, run: Dictionary, cut_verts: Dictionary) -> bool:
	var face_index: int = run["face_index"]
	var face: GoBuildFace = mesh.faces[face_index]

	if run.get("is_loop", false):
		return _tessellate_closed_loop(mesh, face, face_index, run, cut_verts)

	var ring: Array[int] = []
	ring.assign(face.vertex_indices)
	var entry: Dictionary = run["entry"]
	var exit: Dictionary = run["exit"]

	# Interior path points lying ON ring edges (edge-snapped clicks) split
	# that edge first — the point becomes a ring member shared with the
	# neighbour, no T-junctions.  Same treatment the closed loop applies to
	# its on-edge points.  Re-read the ring after each split.
	ring = _split_on_edge_points(mesh, face, run["points"], ring, cut_verts)

	var entry_vi := _anchor_vertex(mesh, ring, run, entry, true, cut_verts)
	var exit_vi := _anchor_vertex(mesh, ring, run, exit, false, cut_verts)
	if entry_vi < 0 or exit_vi < 0:
		print("[KnifeGeom] face %d: anchor resolution failed" % face_index)
		return false
	var entry_pos := ring.find(entry_vi)
	var exit_pos := ring.find(exit_vi)
	if entry_pos == -1 or exit_pos == -1:
		print("[KnifeGeom] face %d: anchors not on ring (stale ring refs)" % face_index)
		return false
	if entry_pos == exit_pos:
		# Both ends resolve to the same ring vertex.  A path with an
		# INTERIOR point is still a real cut (interior loose end → nearest
		# corner): the tie broke to the same anchor as the other end because
		# the split vertex sat closest to the loose end — degenerate, but
		# the drawn segment p0→exit must still partition: anchor the loose
		# end at the nearest corner that ISN'T the other anchor and emit
		# [arc from other anchor → tie corner] + [tie corner → path → other
		# anchor].  A path with NO interior points (pure on-ring graze)
		# stays a no-op — the neighbours carry the cut.
		var has_interior := false
		for pt: Variant in run["points"]:
			var on_ring := false
			for vi: int in ring:
				if mesh.vertices[vi].distance_to(pt as Vector3) < 1e-3:
					on_ring = true
					break
			if not on_ring:
				has_interior = true
				break
		if not has_interior:
			print("[KnifeGeom] face %d: single touch point — no partition needed" % face_index)
			run["no_op"] = true
			return false
		# Interior cut with a degenerate anchor pair: re-anchor the loose
		# end to the nearest corner != the other anchor; the generic
		# member-chain partition below then splits the face around the path.
		var other := exit_vi
		var end_p: Vector3 = run["points"][0] if entry.is_empty() \
				else run["points"][run["points"].size() - 1]
		var best_vi := -1
		var best_d := INF
		for vi: int in ring:
			if vi == other:
				continue
			var d: float = mesh.vertices[vi].distance_squared_to(end_p)
			if d < best_d:
				best_d = d
				best_vi = vi
		if best_vi < 0:
			print("[KnifeGeom] face %d: single touch point — no partition needed" % face_index)
			run["no_op"] = true
			return false
		if entry.is_empty():
			entry_vi = best_vi
		else:
			exit_vi = best_vi
		entry_pos = ring.find(entry_vi)
		exit_pos = ring.find(exit_vi)
		print("[KnifeGeom] face %d: interior loose end re-anchored %d→%d" % [
				face_index, other, best_vi])

	# Member-chained partition: every path vertex that IS a ring member
	# (edge-snapped points — phase 2 split them in; snapped corners reused)
	# bounds a band, like the closed loop's member chains.  Consecutive
	# members (in path order) pair with the ring arc between them that
	# contains no other member; the path chunk between the pair closes it.
	# Interior path vertices (not members) stay inside one stretch's chunk.
	var pts: Array = run["points"]
	# A path that revisits the same position twice (non-consecutive — off-face
	# clicks clamped to one corner, then away, then back) cannot partition a
	# face into two simple n-gons: every band would repeat that vertex.
	# Bail BEFORE creating vertices — no orphaned geometry.
	for i: int in pts.size():
		for j: int in range(i + 1, pts.size()):
			if (pts[i] as Vector3).distance_to(pts[j] as Vector3) < 1e-3:
				print("[KnifeGeom] face %d: path revisits a point — no partition" % face_index)
				return false
	# Path vertices in path order, anchors first/last (the resolved
	# entry/exit are the path's ends; mid-path points follow).
	var chain: Array[int] = [entry_vi]
	for i: int in pts.size():
		var vi := _add_path_vertex(mesh, pts[i], cut_verts, ring)
		if vi != entry_vi and vi != exit_vi \
				and (chain.is_empty() or vi != chain[chain.size() - 1]):
			chain.append(vi)
	if chain[chain.size() - 1] != exit_vi:
		chain.append(exit_vi)
	# Member entries: chain positions whose vertex IS a ring member
	# (interior path vertices have no slot — they ride inside a band).
	var member_entries: Array = []   # [{ "slot", "ci" }]
	for ci: int in chain.size():
		var s: int = ring.find(chain[ci])
		if s >= 0:
			member_entries.append({"slot": s, "ci": ci})
	if member_entries.size() < 2:
		return false
	member_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["slot"] < b["slot"])
	# Ring-order partition: every ring arc between consecutive members (in
	# RING order) becomes one band, closed by the path walk from the arc's
	# end member back to its start member.  The path may pass through other
	# members and interior vertices inside a band — interior corners of the
	# band's ring.
	var replaced := false
	for k: int in member_entries.size():
		var sa: int = member_entries[k]["slot"]
		var sb: int = member_entries[(k + 1) % member_entries.size()]["slot"]
		var ca: int = member_entries[k]["ci"]
		var cb: int = member_entries[(k + 1) % member_entries.size()]["ci"]
		# Ring arc sa→sb (ring order).
		var arc: Array[int] = [ring[sa]]
		var i: int = (sa + 1) % ring.size()
		while i != sb:
			arc.append(ring[i])
			i = (i + 1) % ring.size()
		arc.append(ring[sb])
		# Band walk from sb back to sa along the chain — the monotone span
		# between their chain positions, walking TOWARD sa (down when the
		# span is cb→ca descending, up when ascending).
		var walk: Array[int] = []
		var c: int = cb
		while true:
			walk.append(chain[c])
			if c == ca:
				break
			c = (c + 1) % chain.size() if cb < ca else (c - 1 + chain.size()) % chain.size()
		var band: Array[int] = []
		band.assign(arc)
		band.append_array(walk)
		# The first emitted band replaces the original face — the ring arcs
		# cover the whole face; leaving the old quad in place would overlap.
		var emitted: bool = _clean_and_emit(mesh, face,
				-1 if replaced else face_index, band)
		if emitted:
			replaced = true
	print("[KnifeGeom] open run face %d: %d band(s) over %d members" % [
			face_index, member_entries.size(), member_entries.size()])
	return true


## Resolve a run end to a concrete ring vertex index:
##  - boundary crossing with a phase-2 split: the recorded cut vertex.
##  - on-ring crossing at a vertex: that ring vertex.
##  - interior end: the ring vertex NEAREST to the end point.
static func _anchor_vertex(
		mesh: GoBuildMesh,
		ring: Array[int],
		run: Dictionary,
		cross: Dictionary,
		is_start: bool,
		cut_verts: Dictionary,
) -> int:
	var recorded: int = run.get("entry_vi" if is_start else "exit_vi", -1)
	if recorded >= 0:
		return recorded
	if cross.is_empty():
		var end_p: Vector3 = (run["points"][0] if is_start
				else run["points"][run["points"].size() - 1])
		var best := ring[0]
		var best_d := INF
		for vi: int in ring:
			var d: float = mesh.vertices[vi].distance_squared_to(end_p)
			if d < best_d:
				best_d = d
				best = vi
		return best
	# Crossing on a ring edge — use the STABLE vertex indices (va/vb) captured
	# at resolve time; cross["pos"] refers to the pre-split ring and is stale
	# once phase 2 inserted cut vertices (the "degenerate anchors" source).
	var va: int = cross.get("va", ring[cross["pos"] % ring.size()])
	var vb: int = cross.get("vb", ring[(cross["pos"] + 1) % ring.size()])
	if cross["u"] <= _EPSILON:
		return va
	if cross["u"] >= 1.0 - _EPSILON:
		return vb
	# Mid-edge crossing with no phase-2 split recorded (defensive — the cycle
	# resolver splits these in phase 2).  Shared cut_verts keeps it deduped.
	return get_or_create_cut_vertex(mesh, va, vb, cross["u"], cut_verts)


## Closed loop on one face: the loop n-gon REPLACES the original face; the
## surrounding ring band is stitched by mapping each ring VERTEX to its
## nearest loop vertex — consecutive mappings chain, so each ring edge gets
## one band face and each ring→loop spoke is a single shared edge (Blender's
## minimal layout, no bowties).
static func _tessellate_closed_loop(
		mesh: GoBuildMesh,
		face: GoBuildFace,
		face_index: int,
		run: Dictionary,
		cut_verts: Dictionary,
) -> bool:
	var pts: Array = run["points"]
	var loop_pts: Array = []
	if pts.size() >= 2 and pts[0].distance_to(pts[pts.size() - 1]) < 1e-3:
		for i: int in pts.size() - 1:
			loop_pts.append(pts[i])
	else:
		for p: Variant in pts:
			loop_pts.append(p)
	if loop_pts.size() < 3:
		return false
	var face_normal := mesh.compute_face_normal(face)
	var ring: Array[int] = []
	ring.assign(face.vertex_indices)

	# On-edge loop points become RING MEMBERS: a loop point lying on a ring
	# edge (interior) splits that edge — shared with the neighbour face, no
	# T-junctions — exactly like phase 2 does for crossings.  A boundary-
	# hugging loop (D-shape) then chains member→member in the band assembly
	# instead of guessing bridges across boundary corners.
	ring = _split_on_edge_points(mesh, face, loop_pts, ring, cut_verts)
	# Loop vertices: reuse an EXISTING mesh vertex when the drawn point sits on
	# one (snapped corner, phase-2 cut vertex) — Blender adds no geometry for
	# loop points already connected to the mesh.  Ring vertices are matched
	# first (exact position), then the shared cut_verts table.  `ring` here is
	# the POST-SPLIT ring (on-edge loop points are now members).
	var loop_ids: Array[int] = []
	for p: Variant in loop_pts:
		var reused := _add_path_vertex(mesh, p as Vector3, cut_verts, ring)
		loop_ids.append(reused)
	# Collapse consecutive duplicates (a loop riding ring corners/cut verts
	# repeats vertices) — a 2-unique-vertex remainder is degenerate, no cut.
	var deduped: Array[int] = []
	for vi: int in loop_ids:
		if deduped.is_empty() or vi != deduped[deduped.size() - 1]:
			deduped.append(vi)
	while deduped.size() > 1 and deduped[0] == deduped[deduped.size() - 1]:
		deduped.pop_back()
	if deduped.size() < 3:
		print("[KnifeGeom] closed loop rides existing edges — no cut needed")
		return false
	loop_ids = deduped
	print("[KnifeGeom] loop_pts=%s ring=%s loop_ids=%s" % [loop_pts, ring, loop_ids])

	# Zero-geometry close detection: when EVERY loop edge already exists in
	# the current ring (the drawn loop rides existing edges/cut verts), the
	# "cut" is a no-op — undoing the face replacement keeps Blender's
	# add-nothing behaviour.  Checked BEFORE any emission.
	var rides_existing := true
	for j: int in loop_ids.size():
		var a: int = loop_ids[j]
		var b: int = loop_ids[(j + 1) % loop_ids.size()]
		if mesh.find_edge(a, b) == -1:
			rides_existing = false
			break
	if rides_existing:
		print("[KnifeGeom] closed loop rides existing edges — no cut needed")
		return false

	# The island n-gon REPLACES the original face — drawn edges preserved 1:1.
	_emit_ngon(mesh, face, face_index, loop_ids)

	# Surrounding region via TWO-BAND split (Blender's minimal bridge layout,
	# kept manifold): bridge the island to two ring corners — R nearest island
	# corner 0, S nearest the opposite island corner — then the outer region
	# splits into two concave-but-simple band n-gons (outer arc + island arc).
	# Same counts as Blender's keyhole (+n_loop v, +n_loop+2 e, +2 f) without
	# the non-manifold slit.
	#
	# Loop corners that ARE ring vertices (snapped corners, cut verts on ring
	# edges) complicate naive bridges: a bridge landing on a loop member makes
	# the outer arc start on the island.  Handled by walking RING SLOTS: any
	# ring vertex that is a loop member already terminates the island arc, and
	# bands split AT those members — the outer arc between two consecutive
	# loop-member ring slots (possibly with plain ring corners between) forms
	# one band with the island arc between the same two members.
	#
	# Case 1 — no ring slot is a loop member (interior island): two bridges.
	# Case 2 — some ring slots are loop members: the ring band splits at those
	# members; each maximal outer stretch between consecutive members pairs
	# with the island arc between the same members (the members themselves are
	# the bridges — zero extra bridge edges, same counts).
	var member_pos: Array[int] = []
	var member_set := {}
	for i: int in ring.size():
		if loop_ids.has(ring[i]):
			member_pos.append(i)
			member_set[ring[i]] = true
	# The island is the bands' hole: its boundary must be traversed
	# OPPOSITE the ring's CCW direction.  The drawn loop order (loop_ids)
	# is the user's stroke direction — CW or CCW — so gate every island
	# walk on the drawn winding (positive Newell dot = drawn CCW).
	var island_pts: Array[Vector3] = []
	for vi: int in loop_ids:
		island_pts.append(mesh.vertices[vi])
	var island_cw: bool = _TRIANGULATE_SCRIPT.polygon_normal(island_pts) \
			.dot(face_normal) < 0.0
	if member_pos.size() >= 2:
		# Ring members chain the island into the ring directly: each outer
		# stretch between consecutive members becomes one band face, paired
		# with the island arc between the same two members.  The island arc
		# runs from the outer END member back to the outer START member; of
		# the two arcs, the one whose interior corners sit nearest the outer
		# stretch's corners wins (winding-independent, same rule as the
		# interior-island case).
		var n_members: int = member_pos.size()
		for k: int in n_members:
			var pa: int = member_pos[k]
			var pb: int = member_pos[(k + 1) % n_members]
			var band: Array[int] = []
			var i: int = pa
			while true:
				band.append(ring[i])
				i = (i + 1) % ring.size()
				if i == pb:
					band.append(ring[i])
					break
			var ja: int = loop_ids.find(ring[pa])
			var jb: int = loop_ids.find(ring[pb])
			if ja == jb:
				_clean_and_emit(mesh, face, -1, band)
				continue
			# Two members only: both stretches span the same member pair —
			# the arcs must be complementary.  The degenerate stretch (just
			# the two members, sharing the island's direct edge) is covered
			# by that edge already; the other stretch takes the island arc
			# WITH interior (the far side).
			if n_members == 2:
				if band.size() == 2:
					continue   # Island edge covers this stretch.
				# Island part from the band's END member back to the START
				# member; with two members the two directions are the direct
				# edge (empty — belongs to the degenerate stretch) and the
				# far side (with interior) — take the non-empty one.  The
				# island is the band's hole: pick the walk direction whose
				# band with the SMALLER ring area (the wrong walk direction
				# double-counts the island — face + island vs face − island).
				var end_j: int = jb
				var start_j: int = ja
				var band_base: Array[int] = []
				band_base.assign(band)
				var arc: Array[int] = []
				var best_area := INF
				for step_dir: int in [-1, 1]:
					var arc_try: Array[int] = []
					var j: int = (end_j + step_dir + loop_ids.size()) \
							% loop_ids.size()
					while j != start_j:
						arc_try.append(loop_ids[j])
						j = (j + step_dir + loop_ids.size()) % loop_ids.size()
					if arc_try.is_empty():
						continue
					var band_try: Array[int] = []
					band_try.assign(band_base)
					for vi: int in arc_try:
						band_try.append(vi)
					var area := _band_ring_area(mesh, band_try)
					if area < best_area:
						best_area = area
						arc = arc_try
				for vi: int in arc:
					band.append(vi)
				_clean_and_emit(mesh, face, -1, band)
				continue
			# 3+ members: consecutive members partition the island — each
			# stretch pairs with the island arc containing no other member
			# (that member's own stretch owns it), preferring the empty one
			# (direct island edge).  Tie-break between the two remaining
			# candidate arcs: the WRONG arc makes the band's closing edge
			# cut through the island body — detect it structurally: build
			# the band with the arc appended, keep any island corner NOT
			# in the band/island-arc, and pick the arc whose band polygon
			# contains no such corner (winding-independent face-plane test).
			var outer: Array[int] = []
			outer.assign(band)
			var d_via_prev := _arc_corner_distance(mesh, outer,
					_loop_arc_interior(loop_ids, jb, ja, false))
			var d_via_next := _arc_corner_distance(mesh, outer,
					_loop_arc_interior(loop_ids, jb, ja, true))
			var via_next: bool = d_via_next < d_via_prev
			for pick_next: bool in [via_next, not via_next]:
				var arc_int: Array[int] = _loop_arc_interior(loop_ids, jb, ja,
						pick_next)
				# A member on this arc belongs to its own stretch — invalid.
				var has_member := false
				for vi: int in arc_int:
					if member_set.has(vi):
						has_member = true
						break
				if has_member:
					continue
				var band_try: Array[int] = []
				band_try.assign(band)
				for vi: int in arc_int:
					band_try.append(vi)
				# Leftover island corners (not members, not on the chosen
				# arc) must lie OUTSIDE the band polygon.
				var clean := true
				for step: int in range(loop_ids.size()):
					var vi: int = loop_ids[(ja + step) % loop_ids.size()]
					if member_set.has(vi) or arc_int.has(vi):
						continue
					if _point_in_poly(mesh, mesh.vertices[vi], band_try):
						clean = false
						break
				if clean:
					band.append_array(arc_int)
					break
			_clean_and_emit(mesh, face, -1, band)
	elif member_pos.is_empty():
		# Pure interior island: two bridges from ring corner r (nearest island
		# corner 0) and s (nearest the opposite island corner).
		var r := _nearest_ring_vertex(mesh, ring, mesh.vertices[loop_ids[0]])
		var s := _nearest_ring_vertex(mesh, ring,
				mesh.vertices[loop_ids[loop_ids.size() / 2]])
		if r == s:
			# Island hugs one corner: Blender's keyhole degenerate — one
			# double bridge.  Island arc walks the loop the long way round.
			var band: Array[int] = [r, loop_ids[loop_ids.size() - 1]]
			for j: int in range(loop_ids.size() - 2, 0, -1):
				band.append(loop_ids[j])
			band.append(loop_ids[0])
			band.append(r)
			_clean_and_emit(mesh, face, -1, band)
		else:
			var mid: int = loop_ids.size() / 2
			var band_a: Array[int] = [r]
			var pos: int = ring.find(r)
			while ring[pos] != s:
				pos = (pos + 1) % ring.size()
				band_a.append(ring[pos])
			var band_b: Array[int] = [s]
			pos = ring.find(s)
			while ring[pos] != r:
				pos = (pos + 1) % ring.size()
				band_b.append(ring[pos])
			# Pair each outer arc with the island arc on ITS side.  Band A's
			# outer arc ends at s (bridged to island corner mid) and closes
			# at r (bridged to island corner 0) — so its island part runs
			# mid→0, either backward (via mid-1) or forward (via mid+1).
			# Variant chosen structurally: build band_a with each candidate
			# arc; leftover island corners must lie OUTSIDE the band polygon
			# (the wrong arc makes the band swallow part of the island).
			# Metric distance only breaks a tie.  Band B takes the complement.
			var outer_a: Array[int] = []
			outer_a.assign(band_a)
			var d_via_prev := _arc_corner_distance(mesh, outer_a,
					_loop_arc_interior(loop_ids, mid, 0, false))
			var d_via_next := _arc_corner_distance(mesh, outer_a,
					_loop_arc_interior(loop_ids, mid, 0, true))
			var via_prev: bool = d_via_prev <= d_via_next
			var centroid := _island_centroid(mesh, loop_ids)
			var picked_prev := via_prev
			for pick_prev: bool in [via_prev, not via_prev]:
				var band_a_try: Array[int] = []
				band_a_try.assign(band_a)
				if pick_prev:
					band_a_try.append(loop_ids[mid])
					for j: int in range(mid - 1, -1, -1):
						band_a_try.append(loop_ids[j])
				else:
					band_a_try.append(loop_ids[mid])
					for j: int in range(mid + 1, loop_ids.size()):
						band_a_try.append(loop_ids[j])
					band_a_try.append(loop_ids[0])
				# Leftover island corners (not on A's island walk) must lie
				# OUTSIDE the band polygon, and the island centroid must not
				# be swallowed (the wrong walk direction double-counts the
				# island into the band's signed area).
				var clean := true
				for step: int in range(loop_ids.size()):
					var vi: int = loop_ids[(0 + step) % loop_ids.size()]
					if band_a_try.has(vi):
						continue
					if _point_in_poly(mesh, mesh.vertices[vi], band_a_try):
						clean = false
						break
				if clean and _point_in_poly(mesh, centroid, band_a_try):
					clean = false
				if clean:
					band_a = band_a_try
					picked_prev = pick_prev
					break
			if picked_prev:
				# A: mid→0 backward (via mid-1).  B: 0→mid backward via
				# next (the complement — no island edge covered twice).
				band_b.append(loop_ids[0])
				for j: int in range(loop_ids.size() - 1, mid, -1):
					band_b.append(loop_ids[j])
				band_b.append(loop_ids[mid])
			else:
				# A: mid→0 forward (via mid+1).  B: 0→mid forward via prev.
				band_b.append(loop_ids[0])
				for j: int in range(1, mid):
					band_b.append(loop_ids[j])
				band_b.append(loop_ids[mid])
			_clean_and_emit(mesh, face, -1, band_a)
			_clean_and_emit(mesh, face, -1, band_b)
	else:
		# Single member: the island hangs off the boundary at ONE vertex.
		# Blender-parity keyhole: NO bridge edge — the outer region closes
		# on the ring sub-edge into the member, then walks the island far
		# side in the HOLE direction (opposite the ring's CCW — the drawn
		# stroke may wind either way, so pick the walk whose band does NOT
		# swallow the island centroid) and closes on the island edge:
		#   [m, outer walk forward around to c, m, island far side]
		# (m repeats — the attachment slit; _is_ear ignores the coincident
		# twin so ear-clip triangulates the figure-8 fine).
		var p0: int = member_pos[0]
		var m_j: int = loop_ids.find(ring[p0])
		var band: Array[int] = [ring[p0]]
		var i: int = (p0 + 1) % ring.size()
		while i != (p0 - 1 + ring.size()) % ring.size():
			band.append(ring[i])
			i = (i + 1) % ring.size()
		band.append(ring[i])
		band.append(ring[p0])
		# Hole direction: pick the island walk whose band ring area is
		# SMALLER (face − island; the wrong direction double-counts the
		# island as face + island — parity probes are unreliable on the
		# self-touching ring).
		var band_base: Array[int] = []
		band_base.assign(band)
		var best_area := INF
		for step_dir: int in [-1, 1]:
			var band_try: Array[int] = []
			band_try.assign(band_base)
			for step: int in range(1, loop_ids.size()):
				band_try.append(loop_ids[(m_j + step * step_dir
						+ loop_ids.size()) % loop_ids.size()])
			var area := _band_ring_area(mesh, band_try)
			if area < best_area:
				best_area = area
				band = band_try
		_clean_and_emit(mesh, face, -1, band, true)
	print("[KnifeGeom] closed loop: loop_pts=%d ring=%d faces=%d verts=%d edges=%d" % [
			loop_pts.size(), ring.size(), mesh.faces.size(),
			mesh.vertices.size(), mesh.edges.size()])
	return true


## Interior loop corners of the arc from [param ia] to [param ib]: via
## previous indices (backward) or next indices (forward), endpoints excluded.
static func _loop_arc_interior(
		loop_ids: Array[int],
		ia: int,
		ib: int,
		forward: bool,
) -> Array[int]:
	var out: Array[int] = []
	var j: int = ia
	while true:
		j = (j + 1) % loop_ids.size() if forward \
				else (j - 1 + loop_ids.size()) % loop_ids.size()
		if j == ib:
			break
		out.append(loop_ids[j])
	return out


## Mean nearest distance from an arc's interior corners to an outer arc's
## interior corners — the pairing metric for band/island arc assignment.
static func _arc_corner_distance(
		mesh: GoBuildMesh,
		outer: Array[int],
		inner: Array[int],
) -> float:
	if inner.is_empty() or outer.is_empty():
		return 0.0
	var total := 0.0
	for vi: int in inner:
		var best := INF
		for wi: int in outer:
			best = minf(best, mesh.vertices[vi].distance_squared_to(
					mesh.vertices[wi]))
		total += best
	return total / inner.size()


## Mean of the island's vertex positions — the hole-direction probe: the
## WRONG island walk direction double-counts the island, and its centroid
## then lies INSIDE the band polygon (the correct band has the island as a
## hole — centroid outside).
static func _island_centroid(mesh: GoBuildMesh, island: Array[int]) -> Vector3:
	var c := Vector3.ZERO
	for vi: int in island:
		c += mesh.vertices[vi]
	return c / island.size()


## Unsigned area of a band ring (2D shoelace on its own normal plane).
## The hole-direction discriminator: the correct band (island as a hole)
## has signed area = face − island; the wrong walk direction double-counts
## the island (face + island) — always the LARGER magnitude, so the
## smaller wins.  Crossing-parity probes are unreliable on the
## self-touching keyhole rings (double-covered regions read as "outside").
static func _band_ring_area(mesh: GoBuildMesh, band: Array[int]) -> float:
	var pts: Array[Vector3] = []
	for vi: int in band:
		pts.append(mesh.vertices[vi])
	var n := _TRIANGULATE_SCRIPT.polygon_normal(pts)
	var proj := _TRIANGULATE_SCRIPT._project_to_2d(pts, n)
	var signed := 0.0
	for i: int in proj.size():
		var j: int = (i + 1) % proj.size()
		signed += proj[i].x * proj[j].y - proj[j].x * proj[i].y
	return absf(signed) * 0.5


## Collapse consecutive/wrap repeats in an emitted band ring, skip degenerate
## <3-unique rings (island edge already covers the stretch), then emit.
## [param allow_keyhole] passes the deliberate single-member slit through to
## the emitter (one repeated member vertex — Blender-parity).
## Returns true when a polygon was actually emitted.
static func _clean_and_emit(
		mesh: GoBuildMesh,
		face: GoBuildFace,
		face_index: int,
		band: Array[int],
		allow_keyhole: bool = false,
) -> bool:
	var clean: Array[int] = []
	for vi: int in band:
		if clean.is_empty() or vi != clean[clean.size() - 1]:
			clean.append(vi)
	if clean.size() > 1 and clean[0] == clean[clean.size() - 1]:
		clean.pop_back()
	if clean.size() >= 3:
		_emit_ngon(mesh, face, face_index, clean, allow_keyhole)
		return true
	return false


## Nearest ring VERTEX index to [param p] (straight distance, no tie-break —
## corners are distinct).
static func _nearest_ring_vertex(
		mesh: GoBuildMesh,
		ring: Array[int],
		p: Vector3,
) -> int:
	var best := ring[0]
	var best_d := INF
	for vi: int in ring:
		var d: float = mesh.vertices[vi].distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = vi
	return best


## Create (or reuse) a vertex at an interior path point — shared across
## sub-polygons via a quantised position key.  A point coinciding with a
## RING vertex (snapped corner) reuses the existing vertex — Blender adds
## no geometry for loop points already connected to the mesh.
static func _add_path_vertex(
		mesh: GoBuildMesh,
		p: Vector3,
		cut_verts: Dictionary,
		ring: Array[int] = [],
) -> int:
	for vi: int in ring:
		if mesh.vertices[vi].distance_to(p) < 1e-4:
			return vi
	var key := "P_%d_%d_%d" % [
			roundi(p.x * 10000.0), roundi(p.y * 10000.0), roundi(p.z * 10000.0)]
	if cut_verts.has(key):
		return cut_verts[key]
	var vi := mesh.append_vertex_default(p)
	cut_verts[key] = vi
	return vi


## Emit one n-gon face preserving [param face]'s material/smooth/UV data.
## Ring order is verified against the face's normal and reversed if opposed
## (drawn-order polygons can arrive CW).
static func _emit_ngon(
		mesh: GoBuildMesh,
		face: GoBuildFace,
		face_index: int,
		ring_ids: Array[int],
		allow_keyhole: bool = false,
) -> void:
	if ring_ids.size() < 3:
		return
	# Bowtie guard: a repeated vertex inside one ring pinches the polygon
	# (zero-area lobe, flipped shading).  Deliberate keyholes (single-member
	# island slit — Blender parity) pass with allow_keyhole.
	var seen: Dictionary = {}
	for vi: int in ring_ids:
		if seen.has(vi) and not allow_keyhole:
			print("[KnifeGeom] BOWTIE guard: repeated vertex %d in ring %s" % [
					vi, ring_ids])
			return
		seen[vi] = true
	var normal := mesh.compute_face_normal(face)
	var poly_pos: Array[Vector3] = []
	for vi: int in ring_ids:
		poly_pos.append(mesh.vertices[vi])
	var poly_normal := _TRIANGULATE_SCRIPT.polygon_normal(poly_pos)
	var out_ids: Array[int] = []
	out_ids.assign(ring_ids)
	if poly_normal.dot(normal) < 0.0:
		out_ids.reverse()
	# UVs aligned by RING SLOT against the source face's ring (face.uvs is
	# slot-indexed, not vertex-indexed); vertices the source face doesn't
	# know (new interior cut/path verts) interpolate the source face's UV
	# field barycentrically over its ear-clip triangulation — new geometry
	# inherits the original UV layout (re-projecting stretches it).
	var uvs: Array[Vector2] = []
	var src_ring := face.vertex_indices
	var uv_ok: bool = face.uvs.size() == src_ring.size()
	var tri_cache: Array = []
	if uv_ok and src_ring.size() >= 3:
		var tri_pts: Array[Vector3] = []
		for vi: int in src_ring:
			tri_pts.append(mesh.vertices[vi])
		for tri: Array in _TRIANGULATE_SCRIPT.triangulate_face(tri_pts):
			tri_cache.append({
				"p0": tri_pts[tri[0]], "p1": tri_pts[tri[1]],
				"p2": tri_pts[tri[2]],
				"uv0": face.uvs[tri[0]], "uv1": face.uvs[tri[1]],
				"uv2": face.uvs[tri[2]],
			})
	var axis_n := _TRIANGULATE_SCRIPT.polygon_normal(poly_pos)
	for i: int in out_ids.size():
		var vi: int = out_ids[i]
		var uv := Vector2.ZERO
		var slot: int = src_ring.find(vi) if uv_ok else -1
		if slot >= 0:
			uv = face.uvs[slot]
		elif not tri_cache.is_empty():
			uv = _barycentric_uv(mesh.vertices[vi], tri_cache, axis_n)
		else:
			# No source UVs at all — dominant-axis planar projection
			# (1 mesh unit = 1 tile, the Auto UV convention).
			var point := mesh.vertices[vi]
			var an := Vector3(absf(axis_n.x), absf(axis_n.y), absf(axis_n.z))
			var use_x: bool = an.x >= an.y and an.x >= an.z
			var use_y: bool = not use_x and an.y >= an.z
			if use_x:
				uv = Vector2(point.z, point.y)
			elif use_y:
				uv = Vector2(point.x, point.z)
			else:
				uv = Vector2(point.x, point.y)
		uvs.append(uv)
	var nf := GoBuildFace.new()
	nf.vertex_indices = out_ids
	nf.uvs = uvs
	nf.material_index = face.material_index
	nf.smooth_group = face.smooth_group
	print("[KnifeGeom] emit f%s ring=%s" % [
			str(face_index) if face_index >= 0 else "new", out_ids])
	if face_index >= 0:
		# Replacing an existing face: unregister its old edge membership,
		# write the n-gon, then register the new ring — persistent edges
		# stay authoritative without a full rebuild.
		mesh.unregister_face(face_index)
		mesh.faces[face_index] = nf
		mesh.register_face(face_index)
	else:
		mesh.faces.append(nf)
		mesh.register_face(mesh.faces.size() - 1)


## Interpolate a source face's UV field at [param point] barycentrically:
## [param tris] is _emit_ngon's tri_cache ({p0,p1,p2,uv0,uv1,uv2}); the
## triangle containing the point (face-plane 2D) donates its corner UVs.
## Falls back to the nearest triangle's centroid UV for points outside
## every triangle (numerical edges).
static func _barycentric_uv(
		point: Vector3,
		tris: Array,
		axis_n: Vector3,
) -> Vector2:
	var an := Vector3(absf(axis_n.x), absf(axis_n.y), absf(axis_n.z))
	var use_x: bool = an.x >= an.y and an.x >= an.z
	var use_y: bool = not use_x and an.y >= an.z
	var best_d := INF
	var best_uv := Vector2.ZERO
	for tri: Dictionary in tris:
		var p0: Vector3 = tri["p0"]
		var p1: Vector3 = tri["p1"]
		var p2: Vector3 = tri["p2"]
		var uv0: Vector2 = tri["uv0"]
		var uv1: Vector2 = tri["uv1"]
		var uv2: Vector2 = tri["uv2"]
		var a := Vector2.ZERO
		var b := Vector2.ZERO
		var c := Vector2.ZERO
		var q := Vector2.ZERO
		if use_x:
			a = Vector2(p0.z, p0.y); b = Vector2(p1.z, p1.y)
			c = Vector2(p2.z, p2.y); q = Vector2(point.z, point.y)
		elif use_y:
			a = Vector2(p0.x, p0.z); b = Vector2(p1.x, p1.z)
			c = Vector2(p2.x, p2.z); q = Vector2(point.x, point.z)
		else:
			a = Vector2(p0.x, p0.y); b = Vector2(p1.x, p1.y)
			c = Vector2(p2.x, p2.y); q = Vector2(point.x, point.y)
		var det: float = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
		if absf(det) < 1e-9:
			continue
		var w0: float = ((b.y - c.y) * (q.x - c.x)
				+ (c.x - b.x) * (q.y - c.y)) / det
		var w1: float = ((c.y - a.y) * (q.x - c.x)
				+ (a.x - c.x) * (q.y - c.y)) / det
		var w2 := 1.0 - w0 - w1
		var inside: bool = w0 >= -1e-3 and w1 >= -1e-3 and w2 >= -1e-3
		var uv := uv0 * w0 + uv1 * w1 + uv2 * w2
		if inside:
			return uv
		var d := q.distance_squared_to((a + b + c) / 3.0)
		if d < best_d:
			best_d = d
			best_uv = uv
	return best_uv
