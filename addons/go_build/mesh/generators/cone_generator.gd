## Generates a [GoBuildMesh] representing a cone.
##
## The cone is centred at the origin, apex pointing up (+Y).
## The lateral surface is a triangle fan from the apex down to the base ring.
## The base cap is an optional triangle fan.
##
## All faces wind CCW for outward normals.
class_name ConeGenerator
extends RefCounted

## Generate a cone [GoBuildMesh].
##
## [param radius]         base radius (must be > 0)
## [param height]         total height along Y (must be > 0)
## [param sides]          number of lateral triangle faces (must be >= 3)
## [param cap_bottom]     include the base disc cap
## [param material_index] material slot for all faces
static func generate(
		radius: float = 0.5,
		height: float = 1.0,
		sides: int = 16,
		cap_bottom: bool = true,
		material_index: int = 0,
) -> GoBuildMesh:
	assert(radius > 0.0, "ConeGenerator: radius must be > 0")
	assert(height > 0.0, "ConeGenerator: height must be > 0")
	assert(sides >= 3, "ConeGenerator: sides must be >= 3")

	var mesh := GoBuildMesh.new()
	var hh := height * 0.5

	# ── Base ring vertices (y = -hh) ────────────────────────────────────
	for i in range(sides):
		var angle: float = TAU * float(i) / float(sides)
		mesh.vertices.append(Vector3(cos(angle) * radius, -hh, -sin(angle) * radius))

	# ── Apex vertex (y = +hh) ───────────────────────────────────────────
	var apex_idx: int = mesh.vertices.size()
	mesh.vertices.append(Vector3(0.0, hh, 0.0))

	# ── Lateral triangles ────────────────────────────────────────────────
	# Each lateral face: base-i, base-(i+1), apex  (CCW from outside)
	for i in range(sides):
		var b0: int = i
		var b1: int = (i + 1) % sides
		var u0: float = float(i)     / float(sides)
		var u1: float = float(i + 1) / float(sides)
		var um: float = (u0 + u1) * 0.5

		var face := GoBuildFace.new()
		face.vertex_indices = [b0, b1, apex_idx]
		face.material_index = material_index
		face.uvs = [
			Vector2(u0, 0.0),
			Vector2(u1, 0.0),
			Vector2(um, 1.0),
		]
		mesh.faces.append(face)

	# ── Bottom cap (normal -Y) ───────────────────────────────────────────
	if cap_bottom:
		var centre_idx: int = mesh.vertices.size()
		mesh.vertices.append(Vector3(0.0, -hh, 0.0))

		for i in range(sides):
			var b0: int = i
			var b1: int = (i + 1) % sides
			# CCW from below (-Y): b1 → b0 → centre
			var face := GoBuildFace.new()
			face.vertex_indices = [b1, b0, centre_idx]
			face.material_index = material_index
			var a0 := TAU * float((i + 1) % sides) / float(sides)
			var a1 := TAU * float(i) / float(sides)
			face.uvs = [
				Vector2(cos(a0) * 0.5 + 0.5, sin(a0) * 0.5 + 0.5),
				Vector2(cos(a1) * 0.5 + 0.5, sin(a1) * 0.5 + 0.5),
				Vector2(0.5, 0.5),
			]
			mesh.faces.append(face)

	WeldOperation.apply_weld_by_threshold(mesh)
	return mesh

