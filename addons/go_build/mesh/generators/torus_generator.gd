## Generates a [GoBuildMesh] representing a torus.
##
## The torus is centred at the origin in the XZ plane.
## [param radius_major] is the distance from the torus centre to the tube centre.
## [param radius_minor] is the radius of the tube itself.
## UV: U wraps around the tube cross-section, V wraps around the major ring.
class_name TorusGenerator
extends RefCounted

## Generate a torus [GoBuildMesh].
##
## [param radius_major]   distance from origin to tube centre (must be > 0)
## [param radius_minor]   tube cross-section radius (must be > 0 and < radius_major)
## [param rings]          major-ring segments; must be >= 3
## [param tube_segments]  tube cross-section segments; must be >= 3
## [param material_index] material slot for all faces
static func generate(
		radius_major: float = 0.5,
		radius_minor: float = 0.2,
		rings: int = 24,
		tube_segments: int = 12,
		material_index: int = 0,
) -> GoBuildMesh:
	assert(radius_major > 0.0, "TorusGenerator: radius_major must be > 0")
	assert(radius_minor > 0.0, "TorusGenerator: radius_minor must be > 0")
	assert(radius_minor < radius_major,
		"TorusGenerator: radius_minor must be < radius_major")
	assert(rings        >= 3, "TorusGenerator: rings must be >= 3")
	assert(tube_segments >= 3, "TorusGenerator: tube_segments must be >= 3")

	var mesh := GoBuildMesh.new()

	# ── Vertex grid ──────────────────────────────────────────────────────
	# rings × tube_segments vertices (seam columns duplicated for UV continuity).
	# Index: ring * (tube_segments + 1) + tube
	for ring in range(rings + 1):
		var phi: float = TAU * float(ring) / float(rings)   # major angle
		var cx: float = cos(phi) * radius_major              # ring centre x
		var cz: float = -sin(phi) * radius_major             # ring centre z

		for tube in range(tube_segments + 1):
			var theta: float = TAU * float(tube) / float(tube_segments)   # tube angle
			# Point on tube: offset from ring centre along the outward+up direction
			var dx: float = cos(theta) * cos(phi)
			var dy: float = sin(theta)
			var dz: float = -cos(theta) * sin(phi)
			mesh.vertices.append(Vector3(
				cx + dx * radius_minor,
				dy * radius_minor,
				cz + dz * radius_minor,
			))

	# ── Quad faces ───────────────────────────────────────────────────────
	# Wound CCW from outside (consistent with all other generators) so that
	# compute_face_normal() returns the correct outward normal.
	# Order [i00, i01, i11, i10]: advance along the major ring first, then
	# along the tube, giving CCW winding when viewed from outside the tube.
	for ring in range(rings):
		for tube in range(tube_segments):
			var i00: int =  ring      * (tube_segments + 1) + tube
			var i10: int =  ring      * (tube_segments + 1) + tube + 1
			var i11: int = (ring + 1) * (tube_segments + 1) + tube + 1
			var i01: int = (ring + 1) * (tube_segments + 1) + tube

			var u0: float = float(tube)     / float(tube_segments)
			var u1: float = float(tube + 1) / float(tube_segments)
			var v0: float = float(ring)     / float(rings)
			var v1: float = float(ring + 1) / float(rings)

			var face := GoBuildFace.new()
			# [i00, i01, i11, i10]: CCW from outside; UVs follow their vertex.
			face.vertex_indices = [i00, i01, i11, i10]
			face.material_index = material_index
			face.uvs = [
				Vector2(u0, v0), Vector2(u0, v1),
				Vector2(u1, v1), Vector2(u1, v0),
			]
			mesh.faces.append(face)

	mesh.rebuild_edges()
	return mesh

