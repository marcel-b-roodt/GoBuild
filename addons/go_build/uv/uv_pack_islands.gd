## Re-arranges all UV islands into the 0-1 tile using shelf-based bin-packing.
##
## For each [GoBuildMesh] the algorithm:
## 1. Builds UV islands via flood-fill (faces sharing a UV vertex within epsilon).
## 2. Computes per-island bounding rects in UV space.
## 3. Scales all islands uniformly so the total area fits within [param margin]
##    of the 0-1 tile on each axis.
## 4. Packs islands using a next-fit shelf algorithm (tall-to-short ordering).
##
## Call [method apply] then [code]bake_in_place()[/code] on the owning
## [GoBuildMeshInstance].
@tool
class_name UvPackIslands
extends RefCounted

const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")

const _UV_EPSILON: float = 0.0001


## Pack all UV islands of [param mesh] into the 0-1 tile with a [param margin]
## border around each island.  Returns the number of islands packed.
static func apply(mesh: GoBuildMesh, margin: float = 0.02) -> int:
	if mesh.faces.is_empty():
		return 0

	var islands := _build_islands(mesh)
	if islands.is_empty():
		return 0

	var bboxes := _compute_bboxes(mesh, islands)
	_snap_origins(mesh, islands, bboxes)

	var total_u: float = 0.0
	var total_v: float = 0.0
	for bbox: Rect2 in bboxes:
		total_u += bbox.size.x
		total_v += bbox.size.y
	var scale := _fit_scale(bboxes, margin)

	_scale_islands(mesh, islands, bboxes, scale)

	for i: int in bboxes.size():
		bboxes[i] = Rect2(bboxes[i].position * scale, bboxes[i].size * scale)

	_shelf_pack(mesh, islands, bboxes, margin)

	return islands.size()


# ---------------------------------------------------------------------------
# Island detection — flood-fill on shared UV vertices
# ---------------------------------------------------------------------------

## Build a list of UV islands. Each island is an [Array[int]] of face indices.
## Two faces are connected if they share a UV vertex position (within epsilon).
static func _build_islands(mesh: GoBuildMesh) -> Array[Array]:
	var n: int = mesh.faces.size()
	var visited: Array[bool] = []
	visited.resize(n)
	visited.fill(false)

	var uv_to_faces := _build_uv_vertex_map(mesh)

	var islands: Array[Array] = []
	for fi: int in n:
		if visited[fi]:
			continue
		var island: Array[int] = []
		var stack: Array[int] = [fi]
		while not stack.is_empty():
			var cur: int = stack.pop_back()
			if visited[cur]:
				continue
			visited[cur] = true
			island.append(cur)
			var face: GoBuildFace = mesh.faces[cur]
			for uv: Vector2 in face.uvs:
				var key := _uv_key(uv)
				if uv_to_faces.has(key):
					for nb: int in uv_to_faces[key]:
						if not visited[nb]:
							stack.append(nb)
		islands.append(island)
	return islands


## Map each quantised UV position to the list of face indices that use it.
static func _build_uv_vertex_map(mesh: GoBuildMesh) -> Dictionary:
	var m: Dictionary = {}
	for fi: int in mesh.faces.size():
		var face: GoBuildFace = mesh.faces[fi]
		for uv: Vector2 in face.uvs:
			var key := _uv_key(uv)
			if not m.has(key):
				m[key] = []
			m[key].append(fi)
	return m


## Quantise a UV position to a string key for dictionary lookup (epsilon grouping).
static func _uv_key(uv: Vector2) -> StringName:
	var ix: int = roundi(uv.x / _UV_EPSILON)
	var iy: int = roundi(uv.y / _UV_EPSILON)
	return StringName("%d|%d" % [ix, iy])


# ---------------------------------------------------------------------------
# Bounding boxes and normalization
# ---------------------------------------------------------------------------

## Compute the AABB of each island's UVs.
static func _compute_bboxes(mesh: GoBuildMesh, islands: Array[Array]) -> Array[Rect2]:
	var bboxes: Array[Rect2] = []
	bboxes.resize(islands.size())
	for i: int in islands.size():
		var min_uv := Vector2(INF, INF)
		var max_uv := Vector2(-INF, -INF)
		for fi: int in islands[i]:
			var face: GoBuildFace = mesh.faces[fi]
			for uv: Vector2 in face.uvs:
				min_uv = min_uv.min(uv)
				max_uv = max_uv.max(uv)
		bboxes[i] = Rect2(min_uv, max_uv - min_uv)
	return bboxes


## Shift each island so its origin (min UV) is at (0, 0). This normalises
## positions before scaling and packing.
static func _snap_origins(mesh: GoBuildMesh, islands: Array[Array], bboxes: Array[Rect2]) -> void:
	for i: int in islands.size():
		var offset := bboxes[i].position
		if offset.is_zero_approx():
			continue
		for fi: int in islands[i]:
			var face: GoBuildFace = mesh.faces[fi]
			for j: int in face.uvs.size():
				face.uvs[j] -= offset
		bboxes[i].position = Vector2.ZERO


## Compute a uniform scale factor so the islands roughly fill the 0-1 tile
## with the given margin on each side.
static func _fit_scale(bboxes: Array[Rect2], margin: float) -> float:
	var total_area: float = 0.0
	var max_w: float = 0.0
	var max_h: float = 0.0
	for bbox: Rect2 in bboxes:
		total_area += bbox.size.x * bbox.size.y
		max_w = maxf(max_w, bbox.size.x)
		max_h = maxf(max_h, bbox.size.y)

	var available := 1.0 - 2.0 * margin
	if available <= 0.0:
		return 1.0

	if max_w <= 0.0 or max_h <= 0.0:
		return 1.0

	var scale_from_area := sqrt(total_area) / available * 0.9
	var scale_from_max_u := available / max_w
	var scale_from_max_v := available / max_h
	var scale := minf(scale_from_max_u, scale_from_max_v)
	scale = minf(scale, 1.0 / scale_from_area if scale_from_area > 0.0 else scale)
	return minf(scale, 1.0)


## Apply a uniform scale to all island UVs (after origins are at 0,0).
static func _scale_islands(
		mesh: GoBuildMesh, islands: Array[Array],
		bboxes: Array[Rect2], scale: float) -> void:
	if is_equal_approx(scale, 1.0):
		return
	for i: int in islands.size():
		for fi: int in islands[i]:
			var face: GoBuildFace = mesh.faces[fi]
			for j: int in face.uvs.size():
				face.uvs[j] *= scale
		bboxes[i] = Rect2(bboxes[i].position * scale, bboxes[i].size * scale)


# ---------------------------------------------------------------------------
# Shelf-based packing
# ---------------------------------------------------------------------------

## Pack islands into the 0-1 tile using the next-fit decreasing height
## shelf algorithm.  Islands are sorted tallest-first.
static func _shelf_pack(
		mesh: GoBuildMesh, islands: Array[Array],
		bboxes: Array[Rect2], margin: float) -> void:
	var count: int = islands.size()
	if count == 0:
		return

	var order: Array[int] = []
	order.resize(count)
	for i: int in count:
		order[i] = i
	order.sort_custom(func(a: int, b: int) -> bool:
		return bboxes[a].size.y > bboxes[b].size.y)

	var cursor_u: float = margin
	var shelf_v: float = margin
	var shelf_height: float = 0.0
	var max_u := 1.0 - margin
	var max_v := 1.0 - margin

	for idx: int in order:
		var w: float = bboxes[idx].size.x + margin
		var h: float = bboxes[idx].size.y

		if cursor_u + w > max_u:
			cursor_u = margin
			shelf_v += shelf_height + margin
			shelf_height = 0.0

		if shelf_v + h > max_v:
			continue

		var offset := Vector2(cursor_u - bboxes[idx].position.x, shelf_v - bboxes[idx].position.y)
		if not offset.is_zero_approx():
			_translate_island(mesh, islands[idx], offset)
			bboxes[idx].position += offset

		cursor_u += w
		shelf_height = maxf(shelf_height, h)


static func _translate_island(mesh: GoBuildMesh, island: Array[int], offset: Vector2) -> void:
	for fi: int in island:
		var face: GoBuildFace = mesh.faces[fi]
		for j: int in face.uvs.size():
			face.uvs[j] += offset