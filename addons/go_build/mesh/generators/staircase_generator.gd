## Generates a [GoBuildMesh] representing a straight staircase.
##
## Steps are built along the +Z axis and rise along +Y. The staircase starts
## at the origin (bottom-front corner) and extends in +Z / +Y.
## Produces a closed solid: treads, risers, left/right side wall strips, bottom, and back.
##
## Face order:
##   [code]0 .. steps-1[/code]             tread[i]       (normal +Y)
##   [code]steps .. 2*steps-1[/code]        riser[i]       (normal -Z)
##   [code]2*steps .. 3*steps-1[/code]      left strip[i]  (normal -X)
##   [code]3*steps .. 4*steps-1[/code]     right strip[i]  (normal +X)
##   [code]4*steps[/code]                  bottom          (normal -Y)
##   [code]4*steps + 1[/code]              back            (normal +Z)
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

	# ── Left side wall strips (normal -X) ──────────────────────────────────
	# Each step i gets one quad on the left wall covering the step profile.
	# The quad spans from z=i*sd (riser front) to z=total_depth (back wall)
	# and from y=i*sh (tread bottom) to y=(i+1)*sh (tread top).
	# CCW from -X side: front-bottom → back-bottom → back-top → front-top.
	for i in range(steps):
		var y_bot: float = float(i)     * step_height
		var y_top: float = float(i + 1) * step_height
		var z_front: float = float(i) * step_depth
		MeshGeneratorUtils.add_quad_grid(mesh,
			Vector3(-hw, y_bot, z_front), Vector3(-hw, y_bot, total_depth),
			Vector3(-hw, y_top, total_depth), Vector3(-hw, y_top, z_front),
			1, 1, material_index)

	# ── Right side wall strips (normal +X) ─────────────────────────────────
	# Same as left but mirrored: CCW from +X.
	for i in range(steps):
		var y_bot: float = float(i)     * step_height
		var y_top: float = float(i + 1) * step_height
		var z_front: float = float(i) * step_depth
		MeshGeneratorUtils.add_quad_grid(mesh,
			Vector3(hw, y_bot, total_depth), Vector3(hw, y_bot, z_front),
			Vector3(hw, y_top, z_front), Vector3(hw, y_top, total_depth),
			1, 1, material_index)

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

	WeldOperation.apply_weld_by_threshold(mesh)
	return mesh