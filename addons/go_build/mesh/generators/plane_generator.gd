## Generates a [GoBuildMesh] representing a flat, upward-facing plane.
##
## The plane lies in the XZ plane (Y = 0), centred at the origin, with its
## normal pointing in the +Y direction. Subdivisions can be specified
## independently for the X and Z axes.
class_name PlaneGenerator
extends RefCounted


## Generate an upward-facing plane [GoBuildMesh] centred at the origin.
##
## [param width]          X extent (must be > 0)
## [param depth]          Z extent (must be > 0)
## [param subdivisions_x] extra column loops; 0 = one quad column
## [param subdivisions_z] extra row loops;    0 = one quad row
## [param material_index] material slot for all faces
static func generate(
		width: float = 1.0,
		depth: float = 1.0,
		subdivisions_x: int = 0,
		subdivisions_z: int = 0,
		material_index: int = 0,
) -> GoBuildMesh:
	assert(width > 0.0, "PlaneGenerator: width must be > 0")
	assert(depth > 0.0, "PlaneGenerator: depth must be > 0")
	assert(subdivisions_x >= 0, "PlaneGenerator: subdivisions_x must be >= 0")
	assert(subdivisions_z >= 0, "PlaneGenerator: subdivisions_z must be >= 0")

	var mesh := GoBuildMesh.new()
	var hw := width * 0.5
	var hd := depth * 0.5

	# Single upward-facing quad (normal +Y), wound CCW when viewed from above.
	# Matches the Top face winding of CubeGenerator.
	MeshGeneratorUtils.add_quad_grid(mesh,
		Vector3(-hw, 0.0,  hd), Vector3( hw, 0.0,  hd),
		Vector3( hw, 0.0, -hd), Vector3(-hw, 0.0, -hd),
		subdivisions_x + 1,
		subdivisions_z + 1,
		material_index)

	mesh.rebuild_edges()
	return mesh

