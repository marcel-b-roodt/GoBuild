## Generates a [GoBuildMesh] representing a straight staircase.
##
## Steps are built along the +Z axis and rise along +Y. The staircase starts
## at the origin (bottom-front corner) and extends in +Z / +Y. Produces a
## closed solid with minimal topology: treads and risers as quads, each side
## wall as a single concave n-gon following the staircase profile, one bottom
## quad, and one back quad. Concave n-gons triangulate correctly at bake
## time (convexity-gated ear-clipping in [method GoBuildMesh.bake]).
##
## Corner vertices are appended per-face and deduplicated by the
## [method GoBuildMesh.finalize] weld, which also merges them with the
## tread/riser corners so every edge is shared (closed manifold).
##
## Face order:
##   [code]2*i[/code]          tread[i]   (normal +Y)
##   [code]2*i + 1[/code]      riser[i]   (normal -Z)
##   [code]2*steps[/code]      left side  (n-gon, normal -X)
##   [code]2*steps + 1[/code]  right side (n-gon, normal +X)
##   [code]2*steps + 2[/code]  bottom     (normal -Y)
##   [code]2*steps + 3[/code]  back       (normal +Z)
##
## Total face count: [code]2*steps + 4[/code]
class_name StaircaseGenerator
extends RefCounted

# Self-preloads — dependency order.
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")

## Generate a staircase [GoBuildMesh].
##
## [param steps]          number of steps (must be >= 1)
## [param step_width]     width along X axis (must be > 0)
## [param step_height]    rise per step (must be > 0)
## [param step_depth]     run per step (must be > 0)
## [param material_index] material slot for all faces
static func generate(
		steps: int = 4,
		step_width: float = 1.0,
		step_height: float = 0.25,
		step_depth: float = 0.3,
		material_index: int = 0,
		flipped: bool = false,
) -> GoBuildMesh:
	assert(steps      >= 1,   "StaircaseGenerator: steps must be >= 1")
	assert(step_width  > 0.0, "StaircaseGenerator: step_width must be > 0")
	assert(step_height > 0.0, "StaircaseGenerator: step_height must be > 0")
	assert(step_depth  > 0.0, "StaircaseGenerator: step_depth must be > 0")

	var mesh := GoBuildMesh.new()
	var hw: float = step_width * 0.5
	var total_height: float = float(steps) * step_height
	var total_depth: float  = float(steps) * step_depth

	# ── Treads and risers ─────────────────────────────────────────────────
	for i in range(steps):
		var z0: float = float(i)     * step_depth
		var z1: float = float(i + 1) * step_depth
		var y0: float = float(i)     * step_height
		var y1: float = float(i + 1) * step_height

		# Tread (normal +Y)
		# CCW from above: front-left → back-left → back-right → front-right
		MeshGeneratorUtils.add_quad_grid(mesh,
			Vector3(-hw, y1, z0), Vector3(-hw, y1, z1),
			Vector3( hw, y1, z1), Vector3( hw, y1, z0),
			1, 1, material_index)

		# Riser (normal -Z)
		MeshGeneratorUtils.add_quad_grid(mesh,
			Vector3( hw, y0, z0), Vector3(-hw, y0, z0),
			Vector3(-hw, y1, z0), Vector3( hw, y1, z0),
			1, 1, material_index)

	# ── Side walls: single concave profile n-gon each ────────────────────
	# Profile ring (left, viewed from -X): front-bottom → back-bottom →
	# back-top, then down the staircase through every riser/tread corner
	# back to the front. Wound CCW from -X.
	var left_pos: Array[Vector3] = [
		Vector3(-hw, 0.0, 0.0),
		Vector3(-hw, 0.0, total_depth),
		Vector3(-hw, total_height, total_depth),
	]
	for i in range(steps - 1, 0, -1):
		left_pos.append(Vector3(-hw, float(i + 1) * step_height, float(i) * step_depth))
		left_pos.append(Vector3(-hw, float(i) * step_height, float(i) * step_depth))
	left_pos.append(Vector3(-hw, step_height, 0.0))
	_add_ngon(mesh, left_pos, material_index)

	# Right side: same profile mirrored to +X (reversed ring → CCW from +X).
	var right_pos: Array[Vector3] = []
	right_pos.resize(left_pos.size())
	for k: int in left_pos.size():
		var p: Vector3 = left_pos[left_pos.size() - 1 - k]
		right_pos[k] = Vector3(hw, p.y, p.z)
	_add_ngon(mesh, right_pos, material_index)

	# ── Bottom (normal -Y) ────────────────────────────────────────────────
	MeshGeneratorUtils.add_quad_grid(mesh,
		Vector3(-hw, 0.0, 0.0), Vector3( hw, 0.0, 0.0),
		Vector3( hw, 0.0, total_depth), Vector3(-hw, 0.0, total_depth),
		1, 1, material_index)

	# ── Back (normal +Z) ─────────────────────────────────────────────────
	MeshGeneratorUtils.add_quad_grid(mesh,
		Vector3(-hw, 0.0, total_depth), Vector3( hw, 0.0, total_depth),
		Vector3( hw, total_height, total_depth),
		Vector3(-hw, total_height, total_depth),
		1, 1, material_index)

	# ── Flip: mirror along Z through the block centre ────────────────────
	# One post-pass mirrors every vertex (z → total_depth − z) and reverses
	# every face ring, so winding stays CCW-from-outside without per-face
	# special cases. Treads keep their y-levels; the ascent now runs -Z
	# (steps descend along +Z).
	if flipped:
		var all_idx: Array[int] = []
		all_idx.resize(mesh.vertices.size())
		for i: int in all_idx.size():
			all_idx[i] = i
			mesh.vertices[i].z = total_depth - mesh.vertices[i].z
		for face: GoBuildFace in mesh.faces:
			var ring: Array[int] = []
			ring.assign(face.vertex_indices)
			ring.reverse()
			face.vertex_indices = ring
			var uvs: Array[Vector2] = []
			uvs.assign(face.uvs)
			uvs.reverse()
			face.uvs = uvs

	mesh.finalize()
	return mesh


## Append one planar n-gon face from a CCW-from-outside position ring, with
## dominant-axis planar UVs (same convention as PolygonGenerator._planar_uv).
## Vertices are appended raw; the finalize() weld deduplicates them and
## merges with the tread/riser corners.
static func _add_ngon(mesh: GoBuildMesh, positions: Array[Vector3], material_index: int) -> void:
	var ring: Array[int] = []
	ring.resize(positions.size())
	for k: int in positions.size():
		mesh.vertices.append(positions[k])
		ring[k] = mesh.vertices.size() - 1

	var face := GoBuildFace.new()
	face.vertex_indices = ring
	face.material_index = material_index

	# Planar UVs: normalise the ring against its AABB in face space.
	var n := mesh.compute_ring_normal(ring)
	var abs_n := n.abs()
	var u_axis: int
	var v_axis: int
	if abs_n.x >= abs_n.y and abs_n.x >= abs_n.z:
		u_axis = 2; v_axis = 1  # YZ plane
	elif abs_n.y >= abs_n.x and abs_n.y >= abs_n.z:
		u_axis = 0; v_axis = 2  # XZ plane
	else:
		u_axis = 0; v_axis = 1  # XY plane
	var min_u := INF
	var min_v := INF
	var max_u := -INF
	var max_v := -INF
	for p: Vector3 in positions:
		min_u = minf(min_u, p[u_axis])
		min_v = minf(min_v, p[v_axis])
		max_u = maxf(max_u, p[u_axis])
		max_v = maxf(max_v, p[v_axis])
	var range_u: float = maxf(max_u - min_u, 0.001)
	var range_v: float = maxf(max_v - min_v, 0.001)
	var uvs: Array[Vector2] = []
	uvs.resize(positions.size())
	for k: int in positions.size():
		var p: Vector3 = positions[k]
		uvs[k] = Vector2((p[u_axis] - min_u) / range_u, (p[v_axis] - min_v) / range_v)
	face.uvs = uvs
	mesh.faces.append(face)