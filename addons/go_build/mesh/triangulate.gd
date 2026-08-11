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
## Only correct for convex polygons. Use [method ear_clip] for concave ones.
static func fan(vertex_count: int) -> Array:
	assert(vertex_count >= 3, "Triangulate.fan: need at least 3 vertices")
	var tris: Array = []
	for tri: int in range(vertex_count - 2):
		tris.append([0, tri + 2, tri + 1])
	return tris


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

			if _is_ear(projected, indices, a, b, c):
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
	indices: Array[int],
	a: int, b: int, c: int,
) -> bool:
	var pa: Vector2 = projected[a]
	var pb: Vector2 = projected[b]
	var pc: Vector2 = projected[c]
	for idx: int in indices:
		if idx == -1 or idx == a or idx == b or idx == c:
			continue
		if _point_in_triangle(projected[idx], pa, pb, pc):
			return false
	return true


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