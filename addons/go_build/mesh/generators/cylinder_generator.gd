## Generates a [GoBuildMesh] representing a cylinder.
##
## The cylinder is centred at the origin, aligned along the Y axis.
## The lateral surface is made of [param sides] quad faces.
## Top and bottom caps are optional triangle fans centred at the axis.
##
## All faces wind CCW for outward normals.
class_name CylinderGenerator
extends RefCounted

## Generate a cylinder [GoBuildMesh].
##
## [param radius]          radius of both caps (must be > 0)
## [param height]          total height along Y (must be > 0)
## [param sides]           number of lateral quad faces (must be >= 3)
## [param cap_top]         include the top disc cap
## [param cap_bottom]      include the bottom disc cap
## [param material_index]  material slot for all faces
static func generate(
		radius: float = 0.5,
		height: float = 1.0,
		sides: int = 16,
		cap_top: bool = true,
		cap_bottom: bool = true,
		material_index: int = 0,
) -> GoBuildMesh:
	assert(radius > 0.0, "CylinderGenerator: radius must be > 0")
	assert(height > 0.0, "CylinderGenerator: height must be > 0")
	assert(sides >= 3, "CylinderGenerator: sides must be >= 3")

	var mesh := GoBuildMesh.new()
	var hh := height * 0.5

	# ── Ring vertices ───────────────────────────────────────────────────
	# Build two rings of vertices: bottom (y=-hh) and top (y=+hh).
	# Index layout: bottom ring 0..sides-1, top ring sides..2*sides-1.
	for i in range(sides):
		var angle: float = TAU * float(i) / float(sides)
		var x := cos(angle) * radius
		var z := -sin(angle) * radius   # -sin keeps CCW winding from outside
		mesh.vertices.append(Vector3(x, -hh, z))  # bottom ring

	for i in range(sides):
		var angle: float = TAU * float(i) / float(sides)
		var x := cos(angle) * radius
		var z := -sin(angle) * radius
		mesh.vertices.append(Vector3(x,  hh, z))  # top ring

	# ── Lateral quads ───────────────────────────────────────────────────
	# Each quad: bottom-i, bottom-(i+1), top-(i+1), top-i (CCW from outside).
	for i in range(sides):
		var b0: int = i
		var b1: int = (i + 1) % sides
		var t0: int = sides + i
		var t1: int = sides + (i + 1) % sides

		var u0: float = float(i)       / float(sides)
		var u1: float = float(i + 1)   / float(sides)

		var face := GoBuildFace.new()
		face.vertex_indices = [b0, b1, t1, t0]
		face.material_index = material_index
		face.uvs = [
			Vector2(u0, 0.0),
			Vector2(u1, 0.0),
			Vector2(u1, 1.0),
			Vector2(u0, 1.0),
		]
		mesh.faces.append(face)

	# ── Cap centres ─────────────────────────────────────────────────────
	if cap_bottom or cap_top:
		var bottom_centre_idx: int = -1
		var top_centre_idx: int    = -1

		if cap_bottom:
			bottom_centre_idx = mesh.vertices.size()
			mesh.vertices.append(Vector3(0.0, -hh, 0.0))

		if cap_top:
			top_centre_idx = mesh.vertices.size()
			mesh.vertices.append(Vector3(0.0,  hh, 0.0))

		# ── Bottom cap (normal -Y): triangle fan, CCW from below ──
		if cap_bottom:
			for i in range(sides):
				var b0: int = i
				var b1: int = (i + 1) % sides
				# Viewed from below (-Y), CCW = b1 → b0 → centre
				var face := GoBuildFace.new()
				face.vertex_indices = [b1, b0, bottom_centre_idx]
				face.material_index = material_index
				var a0 := TAU * float((i + 1) % sides) / float(sides)
				var a1 := TAU * float(i) / float(sides)
				face.uvs = [
					Vector2(cos(a0) * 0.5 + 0.5, sin(a0) * 0.5 + 0.5),
					Vector2(cos(a1) * 0.5 + 0.5, sin(a1) * 0.5 + 0.5),
					Vector2(0.5, 0.5),
				]
				mesh.faces.append(face)

		# ── Top cap (normal +Y): triangle fan, CCW from above ──
		if cap_top:
			for i in range(sides):
				var t0: int = sides + i
				var t1: int = sides + (i + 1) % sides
				# Viewed from above (+Y), CCW = t0 → t1 → centre
				var face := GoBuildFace.new()
				face.vertex_indices = [t0, t1, top_centre_idx]
				face.material_index = material_index
				var a0 := TAU * float(i) / float(sides)
				var a1 := TAU * float((i + 1) % sides) / float(sides)
				face.uvs = [
					Vector2(cos(a0) * 0.5 + 0.5, sin(a0) * 0.5 + 0.5),
					Vector2(cos(a1) * 0.5 + 0.5, sin(a1) * 0.5 + 0.5),
					Vector2(0.5, 0.5),
				]
				mesh.faces.append(face)

	mesh.rebuild_edges()
	return mesh

