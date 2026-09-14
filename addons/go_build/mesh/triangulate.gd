## Triangulation algorithms for polygon faces.
##
## Provides two strategies:
## - [method fan]: O(n) fan triangulation for convex polygons.
## - [method ear_clip]: O(n²) ear-clipping for arbitrary simple polygons
##   (convex or concave).
##
## Fan triangulation is the default for the bake pipeline because most
## GoBuild faces are convex quads or regular n-gons. Ear-clipping is
## used when the polygon outline may be concave (e.g. the polygon draw tool).
class_name Triangulate
extends RefCounted


## Fan-triangulate a convex polygon with [param vertex_count] vertices.
##
## Returns an array of triangles, each as an array of 3 local vertex indices
## in CW-from-outside winding order: [0, tri+2, tri+1]. This matches the
## convention used in [method GoBuildMesh._build_surface] for Godot 4's
## Vulkan front-face winding.
##
## For a quad (vertex_count=4), the result is [[0, 2, 1], [0, 3, 2]].
## For a triangle (vertex_count=3), the result is [[0, 2, 1]].
##
## Only correct for convex polygons. Use [method triangulate_face] for
## possibly-concave polygons (the bake pipeline entry point).
static func fan(vertex_count: int) -> Array:
	assert(vertex_count >= 3, "Triangulate.fan: need at least 3 vertices")
	var tris: Array = []
	for tri: int in range(vertex_count - 2):
		tris.append([0, tri + 2, tri + 1])
	return tris


## Convexity-gated triangulation — the bake pipeline entry point.
##
## Convex polygons (the common case) fan in O(n).  Concave ones ear-clip in
## O(n²) — rare, and only for n-gons drawn across concave outlines, so the
## cost is bounded.  Self-touching rings (keyhole: one vertex repeated
## non-consecutively — the knife's single-member attachment slit) split at
## the repeat into two simple loops, each triangulated separately.
##
## [param points] are the face's ring positions in ring order.  Returns
## triangles as arrays of 3 local indices in the same CW-from-outside
## convention as [method fan] ([0, tri+2, tri+1]).
static func triangulate_face(points: Array[Vector3]) -> Array:
	var vc: int = points.size()
	if vc == 3:
		return [[0, 2, 1]]
	if _is_convex(points):
		return fan(vc)
	# ear_clip returns CCW-when-viewed-from-normal triangles; bake wants the
	# CW-from-outside convention, so reverse each triangle.  Keyhole rings
	# (a vertex repeated non-consecutively — the knife's attachment slit)
	# are simple in index space; _is_ear ignores coincident twins so the
	# clip proceeds normally.
	var tris: Array = []
	var normal := polygon_normal(points)
	for tri: Array in ear_clip(points, normal):
		tris.append([tri[0], tri[2], tri[1]])
	return tris


## O(n) convexity test: project onto the best-fit 2D plane and require every
## consecutive edge triple to turn the same direction.
static func _is_convex(points: Array[Vector3]) -> bool:
	if points.size() <= 3:
		return true
	var projected := _project_to_2d(points, polygon_normal(points))
	var n: int = projected.size()
	var turn_sign := 0.0
	for i: int in n:
		var cross := _cross_2d(projected[i], projected[(i + 1) % n], projected[(i + 2) % n])
		if absf(cross) < 1e-9:
			continue   # Collinear — not a turn, keep scanning.
		if turn_sign == 0.0:
			turn_sign = cross
		elif cross * turn_sign < 0.0:
			return false
	return true


## Newell normal for an arbitrary simple polygon (unit length, ZERO when
## degenerate).  Same algorithm as [method GoBuildMesh.compute_face_normal]
## but usable without a mesh instance.
static func polygon_normal(points: Array[Vector3]) -> Vector3:
	var n := Vector3.ZERO
	var vc := points.size()
	if vc < 3:
		return Vector3.ZERO
	for i in vc:
		var cur: Vector3 = points[i]
		var nxt: Vector3 = points[(i + 1) % vc]
		n.x += (cur.y - nxt.y) * (cur.z + nxt.z)
		n.y += (cur.z - nxt.z) * (cur.x + nxt.x)
		n.z += (cur.x - nxt.x) * (cur.y + nxt.y)
	return n.normalized() if n.length_squared() > 1e-12 else Vector3.ZERO


## Ear-clip triangulation for an arbitrary simple polygon.
##
## [param points] are the 3D vertices of the polygon, ordered CCW when
## viewed from [param normal]. [param normal] is used to project the
## points onto the best-fit 2D plane for the ear test.
##
## Returns an array of triangles, each as 3 original vertex indices in
## CCW order when viewed from the normal direction.
##
## Works for both convex and concave polygons. For convex polygons,
## [method fan] is faster and equivalent.
static func ear_clip(points: Array[Vector3], normal: Vector3) -> Array:
	var n: int = points.size()
	if n == 3:
		return [[0, 1, 2]]

	var projected: Array[Vector2] = _project_to_2d(points, normal)

	# Compute signed area of the projected polygon.
	# If negative, the 2D winding is CW — flip it so ear-clip finds ears.
	var signed_area: float = 0.0
	for i: int in n:
		var j: int = (i + 1) % n
		signed_area += projected[i].x * projected[j].y
		signed_area -= projected[j].x * projected[i].y
	signed_area *= 0.5

	if signed_area < 0.0:
		# CW winding in 2D — reverse the projected points.
		var reversed: Array[Vector2] = []
		reversed.resize(n)
		for i: int in n:
			reversed[i] = projected[n - 1 - i]
		projected = reversed

	var indices: Array[int] = []
	indices.resize(n)
	for i: int in n:
		indices[i] = i

	var tris: Array = []
	var remaining: int = n

	while remaining > 3:
		var ear_found: bool = false
		var count: int = indices.size()
		for i: int in count:
			if indices[i] == -1:
				continue
			var prev_i: int = _prev_active(indices, i)
			var next_i: int = _next_active(indices, i)
			if prev_i == -1 or next_i == -1:
				continue

			var a: int = indices[prev_i]
			var b: int = indices[i]
			var c: int = indices[next_i]

			if _cross_2d(projected[a], projected[b], projected[c]) <= 0.0:
				continue

			if _is_ear(projected, a, b, c):
				tris.append([a, b, c])
				indices[i] = -1
				remaining -= 1
				ear_found = true
				break

		if not ear_found:
			break

	var final_three: Array[int] = []
	for idx: int in indices:
		if idx != -1:
			final_three.append(idx)
	if final_three.size() == 3:
		tris.append(final_three)

	return tris


static func _prev_active(indices: Array[int], i: int) -> int:
	var j: int = (i - 1 + indices.size()) % indices.size()
	while j != i:
		if indices[j] != -1:
			return j
		j = (j - 1 + indices.size()) % indices.size()
	return -1


static func _next_active(indices: Array[int], i: int) -> int:
	var j: int = (i + 1) % indices.size()
	while j != i:
		if indices[j] != -1:
			return j
		j = (j + 1) % indices.size()
	return -1


static func _cross_2d(a: Vector2, b: Vector2, c: Vector2) -> float:
	return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)


static func _is_ear(
	projected: Array[Vector2],
	a: int, b: int, c: int,
) -> bool:
	var pa: Vector2 = projected[a]
	var pb: Vector2 = projected[b]
	var pc: Vector2 = projected[c]
	# Containment against ALL original verts: a keyhole pinch's chain can
	# be clipped away before an overlapping ear is tested — its verts must
	# still veto.  (For simple polygons clipped verts stay on the
	# boundary, so this matches the classic remaining-only test.)
	for idx: int in projected.size():
		if idx == a or idx == b or idx == c:
			continue
		var p: Vector2 = projected[idx]
		# Coincident twins of the candidate's corners (keyhole pinch: the
		# same physical point appears twice) sit ON the triangle — they
		# must not veto the ear.
		if p.distance_squared_to(pa) < 1e-14 \
				or p.distance_squared_to(pb) < 1e-14 \
				or p.distance_squared_to(pc) < 1e-14:
			continue
		if _point_in_triangle(p, pa, pb, pc):
			return false
	# Weakly-simple rings (keyhole pinch: the polygon's chains touch at a
	# repeated point) can have ears whose edges cross a chain segment that
	# was already clipped away — the overlap would hide in earlier
	# triangles.  Test against ALL ORIGINAL edges (the ear's own three
	# edges skipped; a shared endpoint can't produce a proper crossing).
	# For simple polygons clipped verts stay on the boundary, so this is
	# equivalent to the classic remaining-only test.
	var n: int = projected.size()
	for i: int in n:
		var d: int = i
		var e: int = (i + 1) % n
		if (d == a and e == b) or (d == b and e == a) \
				or (d == b and e == c) or (d == c and e == b) \
				or (d == c and e == a) or (d == a and e == c):
			continue
		var pd: Vector2 = projected[d]
		var pe: Vector2 = projected[e]
		if _segments_cross(pa, pb, pd, pe) or _segments_cross(pb, pc, pd, pe) \
				or _segments_cross(pc, pa, pd, pe):
			return false
	return true


## Proper (transversal) segment intersection — shared endpoints and
## collinear touches don't count.
static func _segments_cross(p1: Vector2, p2: Vector2, q1: Vector2, q2: Vector2) -> bool:
	var r := p2 - p1
	var s := q2 - q1
	var denom: float = r.cross(s)
	if absf(r.cross(q1 - p1)) < 1e-9 and absf(r.cross(q2 - p1)) < 1e-9:
		return false   # Collinear — handled by vertex containment.
	var t: float = (q1 - p1).cross(s) / r.cross(s)
	var u: float = (q1 - p1).cross(r) / r.cross(s)
	return t > 1e-6 and t < 1.0 - 1e-6 and u > 1e-6 and u < 1.0 - 1e-6


static func _point_in_triangle(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1: float = _cross_2d(a, b, p)
	var d2: float = _cross_2d(b, c, p)
	var d3: float = _cross_2d(c, a, p)
	var has_neg: bool = (d1 < 0.0) or (d2 < 0.0) or (d3 < 0.0)
	var has_pos: bool = (d1 > 0.0) or (d2 > 0.0) or (d3 > 0.0)
	return not (has_neg and has_pos)


## Project 3D polygon points onto their best-fit 2D plane for ear clipping.
## The projection is chosen so that CCW-when-viewed-from-normal always maps to
## positive signed area in 2D. This requires flipping one axis when the natural
## 2D tangent cross product opposes the normal direction.
##
## Axis choices (e_u × e_v must align with normal):
##   X-dominant, nx > 0: (y, z)    — e_y × e_z = +X ✓
##   X-dominant, nx < 0: (-y, z)   — (-e_y) × e_z = -X ✓
##   Y-dominant, ny > 0: (-x, z)   — (-e_x) × e_z = +Y ✓
##   Y-dominant, ny < 0: (x, z)    — e_x × e_z = -Y ✓
##   Z-dominant, nz > 0: (x, y)    — e_x × e_y = +Z ✓
##   Z-dominant, nz < 0: (-x, y)   — (-e_x) × e_y = -Z ✓
static func _project_to_2d(points: Array[Vector3], normal: Vector3) -> Array[Vector2]:
	var result: Array[Vector2] = []
	result.resize(points.size())
	var abs_n := normal.abs()
	if abs_n.x >= abs_n.y and abs_n.x >= abs_n.z:
		var flip: bool = normal.x < 0.0
		for i: int in points.size():
			var u: float = -points[i].y if flip else points[i].y
			result[i] = Vector2(u, points[i].z)
	elif abs_n.y >= abs_n.x and abs_n.y >= abs_n.z:
		var flip: bool = normal.y > 0.0
		for i: int in points.size():
			var u: float = -points[i].x if flip else points[i].x
			result[i] = Vector2(u, points[i].z)
	else:
		var flip: bool = normal.z < 0.0
		for i: int in points.size():
			var u: float = -points[i].x if flip else points[i].x
			result[i] = Vector2(u, points[i].y)
	return result