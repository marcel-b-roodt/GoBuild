## Generates a [GoBuildMesh] representing a straight staircase.
##
## Steps are built along the +Z axis and rise along +Y. The staircase starts
## at the origin (bottom-front corner) and extends in +Z / +Y.
## Produces a closed solid: treads, risers, left/right side walls, bottom, and back.
##
## Face order:
##   [code]0 .. steps-1[/code]       tread[i]   (normal +Y)
##   [code]steps .. 2*steps-1[/code]  riser[i]   (normal -Z)
##   [code]2*steps[/code]             left wall  (normal -X)
##   [code]2*steps + 1[/code]         right wall (normal +X)
##   [code]2*steps + 2[/code]         bottom     (normal -Y)
##   [code]2*steps + 3[/code]         back       (normal +Z)
class_name StaircaseGenerator
extends RefCounted

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
		MeshGeneratorUtils.add_quad_grid(mesh,
			Vector3(-hw, y1, z0), Vector3( hw, y1, z0),
			Vector3( hw, y1, z1), Vector3(-hw, y1, z1),
			1, 1, material_index)

		# Riser (normal -Z)
		MeshGeneratorUtils.add_quad_grid(mesh,
			Vector3( hw, y0, z0), Vector3(-hw, y0, z0),
			Vector3(-hw, y1, z0), Vector3( hw, y1, z0),
			1, 1, material_index)

	# ── Left side wall (normal -X) ────────────────────────────────────────
	# Polygon CCW from -X: bottom-front → bottom-back → top-back,
	# then staircase profile descending (back to front) back to bottom-front.
	var left_face := GoBuildFace.new()
	var left_base: int = mesh.vertices.size()
	mesh.vertices.append(Vector3(-hw, 0.0, 0.0))
	mesh.vertices.append(Vector3(-hw, 0.0, total_depth))
	mesh.vertices.append(Vector3(-hw, total_height, total_depth))
	for i in range(steps - 1, -1, -1):
		mesh.vertices.append(Vector3(-hw, float(i + 1) * step_height, float(i) * step_depth))
		if i > 0:
			mesh.vertices.append(Vector3(-hw, float(i) * step_height, float(i) * step_depth))
	left_face.material_index = material_index
	for k in range(mesh.vertices.size() - left_base):
		var v: Vector3 = mesh.vertices[left_base + k]
		left_face.vertex_indices.append(left_base + k)
		left_face.uvs.append(Vector2(v.z / total_depth, v.y / total_height))
	mesh.faces.append(left_face)

	# ── Right side wall (normal +X) ───────────────────────────────────────
	# Polygon CCW from +X: staircase profile ascending, then bottom-back → bottom-front.
	var right_face := GoBuildFace.new()
	var right_base: int = mesh.vertices.size()
	for i in range(steps):
		mesh.vertices.append(Vector3(hw, float(i + 1) * step_height, float(i) * step_depth))
		mesh.vertices.append(Vector3(hw, float(i + 1) * step_height, float(i + 1) * step_depth))
	mesh.vertices.append(Vector3(hw, 0.0, total_depth))
	mesh.vertices.append(Vector3(hw, 0.0, 0.0))
	right_face.material_index = material_index
	for k in range(mesh.vertices.size() - right_base):
		var v: Vector3 = mesh.vertices[right_base + k]
		right_face.vertex_indices.append(right_base + k)
		right_face.uvs.append(Vector2(v.z / total_depth, v.y / total_height))
	mesh.faces.append(right_face)

	# ── Bottom face (normal -Y) ───────────────────────────────────────────
	MeshGeneratorUtils.add_quad_grid(mesh,
		Vector3(-hw, 0.0, 0.0),        Vector3( hw, 0.0, 0.0),
		Vector3( hw, 0.0, total_depth), Vector3(-hw, 0.0, total_depth),
		1, 1, material_index)

	# ── Back face (normal +Z) ─────────────────────────────────────────────
	MeshGeneratorUtils.add_quad_grid(mesh,
		Vector3(-hw, 0.0,          total_depth), Vector3( hw, 0.0,          total_depth),
		Vector3( hw, total_height, total_depth), Vector3(-hw, total_height, total_depth),
		1, 1, material_index)

	mesh.rebuild_edges()
	return mesh

