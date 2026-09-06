## Live symmetry support for [GoBuildMeshInstance].
##
## Symmetry is defined by an object-LOCAL mirror plane through the mesh
## origin: X (YZ plane), Y (XZ plane), or Z (XY plane).  While enabled,
## every modelling action is mirrored live:
##
##  - Drag transforms (translate / rotate / scale / inset): each moved
##    vertex's mirrored partner moves with it (pure math per frame).
##  - Structural operations (extrude, bevel, subdivide, loop cut…): a
##    materialize pass appended after the op duplicates any face that has
##    no mirrored counterpart and welds the seam, so new geometry gains
##    its twin automatically.
##
## Pure static helpers only — no editor dependencies — so the maths is
## unit-testable headless.
@tool
class_name GoBuildSymmetry
extends RefCounted

# Self-preloads — dependency order.
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")

const _EPSILON: float = 1e-4


## Mirror [param point] across the axis-aligned plane through the origin
## for [param axis] (0 = X/YZ plane, 1 = Y/XZ plane, 2 = Z/XY plane).
static func mirror_point(point: Vector3, axis: int) -> Vector3:
	match axis:
		0: return Vector3(-point.x, point.y, point.z)
		1: return Vector3(point.x, -point.y, point.z)
		2: return Vector3(point.x, point.y, -point.z)
	return point


## True when [param point] lies on the mirror plane for [param axis].
## The optional [param epsilon] lets the drag path widen the threshold
## to survive float noise from prior ops.
static func on_plane(point: Vector3, axis: int, epsilon: float = _EPSILON) -> bool:
	return absf(_axis_value(point, axis)) < epsilon


## Mirror [param delta] across the plane for [param axis]: components along
## the plane normal negate, in-plane components stay.
static func mirror_delta(delta: Vector3, axis: int) -> Vector3:
	return mirror_point(delta, axis)


## Build a map from each vertex's index to its mirror partner's index.
##
## Partners are found by position hashing (quantised to 1e-3), independent of
## topology, so it works for welded or per-face-grid vertex layouts.  A vertex
## exactly on the plane maps to itself.  Vertices with no mirrored twin map
## to -1.
## Returns { vertex_index: partner_index } (-1 = no twin).
static func build_partner_map(mesh: GoBuildMesh, axis: int) -> Dictionary:
	var result: Dictionary = {}
	# Bucket raw positions → candidate lookups use mirror_point(v): a partner
	# of v is any vertex whose position equals mirror_point(v) (within a
	# small tolerance for quantisation boundary jitter).
	var buckets: Dictionary = {}
	for i: int in mesh.vertices.size():
		var key := _bucket_key(mesh.vertices[i])
		if not buckets.has(key):
			buckets[key] = []
		(buckets[key] as Array).append(i)
	for i: int in mesh.vertices.size():
		var mp: Vector3 = mirror_point(mesh.vertices[i], axis)
		var mirror_key := _bucket_key(mp)
		var candidates: Array = buckets.get(mirror_key, [])
		var best: int = -1
		var best_d: float = 1e-4
		for ci: int in candidates:
			var d: float = mp.distance_squared_to(mesh.vertices[ci])
			if d < best_d:
				best_d = d
				best = ci
		result[i] = best
	return result


## Count faces that have NO mirrored counterpart (by mirrored vertex-position
## signature).  Pure helper for tests and for materialize's fast path.
static func count_unmirrored_faces(mesh: GoBuildMesh, axis: int) -> int:
	return _unmirrored_faces(mesh, axis).size()


## Append mirrored twins for every face without one, welding the seam:
## new vertices are added, mirrored faces appended in reversed winding order
## so CCW-from-outside survives, and [method GoBuildMesh.finalize] handles the
## vertex merge.  Material / smooth groups / UV data are copied.
## Returns the number of faces added.
static func materialize(mesh: GoBuildMesh, axis: int) -> int:
	var unmirrored: Array[int] = _unmirrored_faces(mesh, axis)
	if unmirrored.is_empty():
		return 0
	var partner: Dictionary = build_partner_map(mesh, axis)
	var vert_base: int = mesh.vertices.size()

	# Mirror vertex position for each vert with no partner (partner == -1 or
	# partner points back at an on-plane vert whose mirror already exists).
	var new_positions: Array[Vector3] = []
	var remap: Dictionary = {}
	for i: int in mesh.vertices.size():
		var p: int = partner.get(i, -1)
		if p >= 0:
			# Partner exists — mirrored face will reference the partner directly.
			remap[i] = p
		else:
			remap[i] = vert_base + new_positions.size()
			new_positions.append(mirror_point(mesh.vertices[i], axis))
	for pos: Vector3 in new_positions:
		mesh.vertices.append(pos)

	var added := 0
	for fi: int in unmirrored:
		var face: GoBuildFace = mesh.faces[fi]
		var nf := GoBuildFace.new()
		var mirrored_ring: Array[int] = []
		for vi: int in face.vertex_indices:
			mirrored_ring.append(remap[vi])
		mirrored_ring.reverse()   # Reversal flips winding — mirrored across a plane.
		nf.vertex_indices = mirrored_ring
		nf.material_index = face.material_index
		nf.smooth_group = face.smooth_group
		# Mirror the UVs horizontally so textures keep spatial coherence.
		var muvs: Array[Vector2] = []
		muvs.assign(face.uvs)
		for uv: Vector2 in muvs:
			uv.x = 1.0 - uv.x
		nf.uvs = muvs
		nf.uv_projection_mode = face.uv_projection_mode
		nf.uv_scale = face.uv_scale
		nf.uv_offset = face.uv_offset
		nf.uv_seam_rotation = face.uv_seam_rotation
		mesh.faces.append(nf)
		added += 1

	mesh.finalize()
	return added


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

## Indices of faces whose mirrored position set matches no existing face.
## Compares position fingerprints (quantised + sorted), so per-face-grid
## vertex layouts (duplicate positions, distinct indices) compare correctly.
static func _unmirrored_faces(mesh: GoBuildMesh, axis: int) -> Array[int]:
	var existing: Dictionary = {}
	for face: GoBuildFace in mesh.faces:
		existing[_face_fp(mesh, face, 1.0, axis)] = true

	var result: Array[int] = []
	for fi: int in mesh.faces.size():
		# Mirror direction: -1 mirrors the normal axis so the lookup key is
		# the mirrored face's fingerprint.
		if not existing.has(_face_fp(mesh, mesh.faces[fi], -1.0, axis)):
			result.append(fi)
	return result


## Sorted, quantised vertex-position fingerprint of [param face].
## [param dir] 1.0 → raw positions; -1.0 → positions mirrored
## across the plane for [param axis].
static func _face_fp(mesh: GoBuildMesh, face: GoBuildFace, dir: float, axis: int) -> String:
	var parts: Array[String] = []
	for vi: int in face.vertex_indices:
		parts.append(_pos_key(_mirror_axis_component(mesh.vertices[vi], axis, dir)))
	parts.sort()
	return "|".join(parts)


## Position → quantised string.
static func _pos_key(p: Vector3) -> String:
	var q: Vector3 = p * 1000.0
	return "%d,%d,%d" % [roundi(q.x), roundi(q.y), roundi(q.z)]


static func _mirror_axis_component(p: Vector3, axis: int, dir: float) -> Vector3:
	if dir >= 0.0:
		return p
	match axis:
		0: return Vector3(-p.x, p.y, p.z)
		1: return Vector3(p.x, -p.y, p.z)
		2: return Vector3(p.x, p.y, -p.z)
	return p


static func _bucket_key(v: Vector3) -> String:
	return "%d_%d_%d" % [roundi(v.x * 1000.0), roundi(v.y * 1000.0), roundi(v.z * 1000.0)]


static func _axis_value(v: Vector3, axis: int) -> float:
	match axis:
		0: return v.x
		1: return v.y
		2: return v.z
	return 0.0