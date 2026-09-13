## Generates a [GoBuildMesh] representing a prism extruded from an arbitrary
## polygon outline. The base polygon is defined by an ordered list of 3D
## vertices lying on a common plane; the prism extends along [param height]
## in the direction of the polygon's outward normal.
##
## The polygon must have at least 3 vertices and should be wound CCW when
## viewed from outside (the direction the normal points toward). If the
## winding is reversed, the generator will detect it and flip both the base
## face and side faces so the result is always outward-facing.
##
## [param cap_bottom] and [param cap_top] control whether the base and/or
## extruded cap faces are generated. At least one cap is required for a
## valid closed mesh.
class_name PolygonGenerator
extends RefCounted

# Self-preloads — dependency order.
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")


## Generate a prism [GoBuildMesh] from a polygon outline.
##
## [param points]         Ordered 3D vertices of the polygon base (>= 3).
## [param height]         Extrusion distance along the normal (must be > 0).
## [param cap_bottom]     Generate the base cap face.
## [param cap_top]        Generate the extruded cap face.
## [param material_index] Material slot for all faces.
## [param override_normal] If provided, use this as the extrusion direction
##                          instead of computing from the polygon. Use this when
##                          the draw controller knows the surface normal (e.g.
##                          polygons drawn on slopes).
static func generate(
		points: Array[Vector3] = [],
		height: float = 1.0,
		cap_bottom: bool = true,
		cap_top: bool = true,
		material_index: int = 0,
		override_normal: Vector3 = Vector3.ZERO,
) -> GoBuildMesh:
	assert(points.size() >= 3, "PolygonGenerator: need at least 3 points")
	assert(height > 0.0, "PolygonGenerator: height must be > 0")

	var mesh := GoBuildMesh.new()
	var n: int = points.size()

	# Determine the extrusion normal.
	# Priority: override_normal (from surface hit) > Newell computed > UP.
	# This ensures height always goes "outward" from the surface the user
	# clicked on, or UP when drawing in open space.
	var normal: Vector3
	if override_normal != Vector3.ZERO:
		normal = override_normal.normalized()
	else:
		normal = _compute_newell_normal(points)
		if normal == Vector3.ZERO:
			normal = Vector3.UP
		else:
			normal = normal.normalized()

	# Ensure the polygon is wound CCW when viewed from the normal direction.
	# If the winding disagrees with the normal, reverse the point order so
	# the side faces produce correct outward normals.
	var cross_sum: float = 0.0
	for i: int in n:
		var cur: Vector3 = points[i]
		var nxt: Vector3 = points[(i + 1) % n]
		var e1: Vector3 = nxt - cur
		var e2: Vector3 = points[(i + 2) % n] - nxt
		cross_sum += e1.cross(e2).dot(normal)
	if cross_sum < 0.0:
		points.reverse()

	var offset: Vector3 = normal * height

	# ── Compute centroid for local-space centering ─────────────────────────
	var centroid: Vector3 = Vector3.ZERO
	for p: Vector3 in points:
		centroid += p
	centroid /= float(n)

	# ── Base vertices (indices 0 .. n-1) ──────────────────────────────────
	for p: Vector3 in points:
		mesh.vertices.append(p - centroid)

	# ── Top-ring vertices (indices n .. 2n-1) ─────────────────────────────
	for p: Vector3 in points:
		mesh.vertices.append(p - centroid + offset)

	# ── Side faces ────────────────────────────────────────────────────────
	# Winding [bottom_a, bottom_b, top_b, top_a] is CCW from outside.
	for i: int in n:
		var i_next: int = (i + 1) % n
		var side := GoBuildFace.new()
		side.vertex_indices = [i, i_next, n + i_next, n + i]
		side.material_index = material_index
		var edge_len: float = points[i].distance_to(points[i_next])
		side.uvs = [
			Vector2(0.0, 0.0),
			Vector2(edge_len, 0.0),
			Vector2(edge_len, height),
			Vector2(0.0, height),
		]
		mesh.faces.append(side)

	# ── Cap faces ──────────────────────────────────────────────────────────
	# Single n-gon per cap (the outline ring).  The bake pipeline's
	# Triangulate.triangulate_face is convexity-gated (fan convex, ear-clip
	# concave), so a concave cap n-gon bakes correctly — and the knife
	# works on the face ring instead of pre-shattered fan diagonals.
	#
	# Base cap (bottom): wound CW from outside (-normal direction).
	# Top cap: wound CCW from outside (+normal direction).
	if cap_bottom:
		var base_uvs: Array[Vector2] = _planar_uv(points, -normal)
		var base := GoBuildFace.new()
		var base_ring: Array[int] = []
		base_ring.resize(n)
		for i: int in n:
			base_ring[i] = n - 1 - i
		base.vertex_indices = base_ring
		base.material_index = material_index
		var base_uvs_rev: Array[Vector2] = []
		base_uvs_rev.resize(n)
		for i: int in n:
			base_uvs_rev[i] = base_uvs[n - 1 - i]
		base.uvs = base_uvs_rev
		mesh.faces.append(base)

	if cap_top:
		var top_uvs: Array[Vector2] = _planar_uv(points, normal)
		var top := GoBuildFace.new()
		var top_ring: Array[int] = []
		top_ring.resize(n)
		for i: int in n:
			top_ring[i] = n + i
		top.vertex_indices = top_ring
		top.material_index = material_index
		top.uvs = top_uvs
		mesh.faces.append(top)

	mesh.finalize()
	return mesh


## Compute the Newell normal for an ordered list of 3D points.
static func _compute_newell_normal(points: Array[Vector3]) -> Vector3:
	var n := Vector3.ZERO
	var vc: int = points.size()
	for i in vc:
		var cur: Vector3 = points[i]
		var nxt: Vector3 = points[(i + 1) % vc]
		n.x += (cur.y - nxt.y) * (cur.z + nxt.z)
		n.y += (cur.z - nxt.z) * (cur.x + nxt.x)
		n.z += (cur.x - nxt.x) * (cur.y + nxt.y)
	return n


## Generate planar UVs for a polygon face projected onto its plane.
## Projects onto the two dominant axes and normalises to [0, 1].
static func _planar_uv(points: Array[Vector3], normal: Vector3) -> Array[Vector2]:
	var uvs: Array[Vector2] = []
	uvs.resize(points.size())

	# Pick dominant axes.
	var abs_n := normal.abs()
	var u_axis: int  # 0=X, 1=Y, 2=Z
	var v_axis: int
	if abs_n.x >= abs_n.y and abs_n.x >= abs_n.z:
		u_axis = 2; v_axis = 1  # YZ plane
	elif abs_n.y >= abs_n.x and abs_n.y >= abs_n.z:
		u_axis = 0; v_axis = 2  # XZ plane
	else:
		u_axis = 0; v_axis = 1  # XY plane

	var min_u: float = INF
	var min_v: float = INF
	var max_u: float = -INF
	var max_v: float = -INF
	for p: Vector3 in points:
		var u: float = _axis_value(p, u_axis)
		var v: float = _axis_value(p, v_axis)
		min_u = minf(min_u, u)
		min_v = minf(min_v, v)
		max_u = maxf(max_u, u)
		max_v = maxf(max_v, v)

	var range_u: float = maxf(max_u - min_u, 0.001)
	var range_v: float = maxf(max_v - min_v, 0.001)

	for i: int in points.size():
		var u: float = (_axis_value(points[i], u_axis) - min_u) / range_u
		var v: float = (_axis_value(points[i], v_axis) - min_v) / range_v
		uvs[i] = Vector2(u, v)

	return uvs


static func _axis_value(v: Vector3, axis: int) -> float:
	match axis:
		0: return v.x
		1: return v.y
		2: return v.z
		_: return v.x