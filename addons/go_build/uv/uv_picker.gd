## Pure UV hit-testing functions for the UV editor canvas.
##
## All methods are static and take a [GoBuildMesh] plus a query point/rect.
## No editor state or scene tree dependency — safe for headless testing.
@tool
class_name UvPicker
extends RefCounted

const _FACE_SCRIPT           := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MESH_SCRIPT           := preload("res://addons/go_build/mesh/go_build_mesh.gd")

const EDGE_THRESHOLD: float = 0.005


## Return the best face index whose UV polygon contains or is near
## [param uv_pos], or -1 if nothing is close enough.
##
## Point-in-polygon is tried first.  If no face strictly contains the point,
## the face whose closest edge is within [constant EDGE_THRESHOLD] UV units wins.
## When multiple faces overlap, the last face in the array wins (topmost draw).
static func pick_face(mesh: GoBuildMesh, uv_pos: Vector2) -> int:
	if mesh == null:
		return -1
	var hit: int = -1
	var best_edge_dist: float = EDGE_THRESHOLD * EDGE_THRESHOLD
	var any_inside: bool = false

	for fi: int in mesh.faces.size():
		var face: GoBuildFace = mesh.faces[fi]
		if face.uvs.size() < 3:
			continue
		if point_in_polygon(uv_pos, face.uvs):
			hit = fi
			any_inside = true
		elif not any_inside:
			var dist_sq := min_edge_dist_sq(uv_pos, face.uvs)
			if dist_sq < best_edge_dist:
				best_edge_dist = dist_sq
				hit = fi

	return hit


## Return all face indices whose UV polygons contain or are near [param uv_pos].
## Ordered front-to-back (last drawn = last in list).  Used for face cycling.
static func pick_face_all(mesh: GoBuildMesh, uv_pos: Vector2) -> Array[int]:
	if mesh == null:
		return []
	var result: Array[int] = []
	for fi: int in mesh.faces.size():
		var face: GoBuildFace = mesh.faces[fi]
		if face.uvs.size() < 3:
			continue
		if point_in_polygon(uv_pos, face.uvs):
			result.append(fi)
		else:
			var dist_sq := min_edge_dist_sq(uv_pos, face.uvs)
			if dist_sq < EDGE_THRESHOLD * EDGE_THRESHOLD:
				result.append(fi)
	return result


## Return all face indices whose UV polygons intersect a UV-space rectangle.
static func pick_faces_in_rect(mesh: GoBuildMesh, uv_rect: Rect2) -> Array[int]:
	if mesh == null:
		return []
	var result: Array[int] = []
	for fi: int in mesh.faces.size():
		var face: GoBuildFace = mesh.faces[fi]
		if face.uvs.size() < 3:
			continue
		if polygon_intersects_rect(face.uvs, uv_rect):
			result.append(fi)
	return result


## Return the UV vertex handle closest to [param uv_pos] within
## [param radius_px] screen pixels (converted via [param zoom]).
## Returns Vector2i(face_index, uv_index), or Vector2i(-1, -1) if nothing found.
## When [param visible_faces] is non-empty, only vertices from faces in that
## set are considered. An empty dict means all faces are visible.
static func pick_vert(
		mesh: GoBuildMesh, uv_pos: Vector2,
		zoom: float, radius_px: float,
		visible_faces: Dictionary = {}) -> Vector2i:
	if mesh == null:
		return Vector2i(-1, -1)
	var best_fi: int = -1
	var best_vi: int = -1
	var best_dist_sq: float = (radius_px / zoom) * (radius_px / zoom)
	var filter: bool = not visible_faces.is_empty()
	for fi: int in mesh.faces.size():
		if filter and not visible_faces.has(fi):
			continue
		var face: GoBuildFace = mesh.faces[fi]
		for vi: int in face.uvs.size():
			var dsq := uv_pos.distance_squared_to(face.uvs[vi])
			if dsq < best_dist_sq:
				best_dist_sq = dsq
				best_fi = fi
				best_vi = vi
	return Vector2i(best_fi, best_vi)


# ---------------------------------------------------------------------------
# Pure geometry helpers
# ---------------------------------------------------------------------------

## Ray-casting point-in-polygon test in UV space.
static func point_in_polygon(point: Vector2, polygon: Array[Vector2]) -> bool:
	var n: int = polygon.size()
	var inside: bool = false
	var j: int = n - 1
	for i: int in n:
		var vi: Vector2 = polygon[i]
		var vj: Vector2 = polygon[j]
		if ((vi.y > point.y) != (vj.y > point.y)) and \
				(point.x < (vj.x - vi.x) * (point.y - vi.y) / (vj.y - vi.y) + vi.x):
			inside = not inside
		j = i
	return inside


## Minimum squared distance from [param point] to any edge of [param polygon].
static func min_edge_dist_sq(point: Vector2, polygon: Array[Vector2]) -> float:
	var n: int = polygon.size()
	var best: float = INF
	for i: int in n:
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i + 1) % n]
		var ab := b - a
		var ap := point - a
		var t := clampf(ap.dot(ab) / ab.dot(ab), 0.0, 1.0)
		var closest := a + ab * t
		var dsq := point.distance_squared_to(closest)
		if dsq < best:
			best = dsq
	return best


## Check if a UV polygon intersects a UV-space rectangle.
static func polygon_intersects_rect(polygon: Array[Vector2], rect: Rect2) -> bool:
	for uv: Vector2 in polygon:
		if rect.has_point(uv):
			return true
	var corners: Array[Vector2] = [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	]
	for corner: Vector2 in corners:
		if point_in_polygon(corner, polygon):
			return true
	return false


## Compute the UV-space centroid of the given face indices.
static func compute_pivot(mesh: GoBuildMesh, face_indices: Array[int]) -> Vector2:
	if mesh == null:
		return Vector2.ZERO
	var sum := Vector2.ZERO
	var count: int = 0
	for fi: int in face_indices:
		if fi < 0 or fi >= mesh.faces.size():
			continue
		for uv: Vector2 in mesh.faces[fi].uvs:
			sum += uv
			count += 1
	if count == 0:
		return Vector2.ZERO
	return sum / count