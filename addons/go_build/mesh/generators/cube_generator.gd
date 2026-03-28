## Generates a [GoBuildMesh] representing an axis-aligned box (cube / cuboid).
##
## The mesh is centred at the origin. Every face is a quad (or a grid of quads
## when [param subdivisions] > 0), wound counter-clockwise when viewed from
## outside so that [method GoBuildMesh.compute_face_normal] returns an outward
## normal.
##
## Face order (indices 0-5 for subdivisions = 0):
## [code]0[/code] Top (Y+) · [code]1[/code] Bottom (Y-) · [code]2[/code] Front (Z+)
## [code]3[/code] Back (Z-) · [code]4[/code] Right (X+) · [code]5[/code] Left (X-)
class_name CubeGenerator
extends RefCounted


## Generate a cuboid [GoBuildMesh] centred at the origin.
##
## [param width]        X extent (must be > 0)
## [param height]       Y extent (must be > 0)
## [param depth]        Z extent (must be > 0)
## [param subdivisions] extra edge loops per face; 0 = one quad per face
## [param material_index] material slot for all faces
static func generate(
		width: float = 1.0,
		height: float = 1.0,
		depth: float = 1.0,
		subdivisions: int = 0,
		material_index: int = 0,
) -> GoBuildMesh:
	assert(width  > 0.0, "CubeGenerator: width must be > 0")
	assert(height > 0.0, "CubeGenerator: height must be > 0")
	assert(depth  > 0.0, "CubeGenerator: depth must be > 0")
	assert(subdivisions >= 0, "CubeGenerator: subdivisions must be >= 0")

	var mesh := GoBuildMesh.new()
	var hw := width  * 0.5
	var hh := height * 0.5
	var hd := depth  * 0.5
	var s: int = subdivisions + 1  # steps per axis

	# Each face: [v0 bottom-left, v1 bottom-right, v2 top-right, v3 top-left]
	# Winding is CCW when viewed from outside → outward normals via Newell's method.
	# Verified by unit tests for each axis.

	# Top (Y+): viewed from above, CCW = front-left → front-right → back-right → back-left
	MeshGeneratorUtils.add_quad_grid(mesh,
		Vector3(-hw, hh,  hd), Vector3( hw, hh,  hd),
		Vector3( hw, hh, -hd), Vector3(-hw, hh, -hd),
		s, s, material_index)

	# Bottom (Y-): viewed from below, CCW = back-left → back-right → front-right → front-left
	MeshGeneratorUtils.add_quad_grid(mesh,
		Vector3(-hw, -hh, -hd), Vector3( hw, -hh, -hd),
		Vector3( hw, -hh,  hd), Vector3(-hw, -hh,  hd),
		s, s, material_index)

	# Front (Z+): viewed from front, CCW = bottom-left → bottom-right → top-right → top-left
	MeshGeneratorUtils.add_quad_grid(mesh,
		Vector3(-hw, -hh, hd), Vector3( hw, -hh, hd),
		Vector3( hw,  hh, hd), Vector3(-hw,  hh, hd),
		s, s, material_index)

	# Back (Z-): viewed from behind, CCW = bottom-right → bottom-left → top-left → top-right
	MeshGeneratorUtils.add_quad_grid(mesh,
		Vector3( hw, -hh, -hd), Vector3(-hw, -hh, -hd),
		Vector3(-hw,  hh, -hd), Vector3( hw,  hh, -hd),
		s, s, material_index)

	# Right (X+): viewed from right, CCW = front-bottom → back-bottom → back-top → front-top
	MeshGeneratorUtils.add_quad_grid(mesh,
		Vector3(hw, -hh,  hd), Vector3(hw, -hh, -hd),
		Vector3(hw,  hh, -hd), Vector3(hw,  hh,  hd),
		s, s, material_index)

	# Left (X-): viewed from left, CCW = back-bottom → front-bottom → front-top → back-top
	MeshGeneratorUtils.add_quad_grid(mesh,
		Vector3(-hw, -hh, -hd), Vector3(-hw, -hh,  hd),
		Vector3(-hw,  hh,  hd), Vector3(-hw,  hh, -hd),
		s, s, material_index)

	mesh.rebuild_edges()
	return mesh

