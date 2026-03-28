## Generates a [GoBuildMesh] representing a segmented arch (arc).
##
## The arch is a curved strip lying in the XY plane, centred on the origin.
## It spans [param angle_degrees] of arc (default 180° = a full semicircle).
## The strip has a configurable [param thickness] in the radial direction.
##
## Each segment produces one quad face on the outer surface and one on the
## inner surface, plus optional end caps.
class_name ArchGenerator
extends RefCounted

## Generate an arch [GoBuildMesh].
##
## [param outer_radius]    outer radius of the arch ring (must be > 0)
## [param thickness]       radial thickness (must be > 0 and < outer_radius)
## [param angle_degrees]   arc sweep in degrees (must be > 0 and <= 360)
## [param segments]        number of arc segments (must be >= 1)
## [param depth]           depth of the arch along Z (must be > 0)
## [param material_index]  material slot for all faces
static func generate(
		outer_radius: float = 1.0,
		thickness: float = 0.2,
		angle_degrees: float = 180.0,
		segments: int = 8,
		depth: float = 0.2,
		material_index: int = 0,
) -> GoBuildMesh:
	assert(outer_radius  > 0.0, "ArchGenerator: outer_radius must be > 0")
	assert(thickness     > 0.0, "ArchGenerator: thickness must be > 0")
	assert(thickness     < outer_radius, "ArchGenerator: thickness must be < outer_radius")
	assert(angle_degrees > 0.0 and angle_degrees <= 360.0,
		"ArchGenerator: angle_degrees must be in (0, 360]")
	assert(segments >= 1, "ArchGenerator: segments must be >= 1")
	assert(depth > 0.0, "ArchGenerator: depth must be > 0")

	var mesh := GoBuildMesh.new()
	var inner_radius: float = outer_radius - thickness
	var angle_rad: float = deg_to_rad(angle_degrees)
	var hd := depth * 0.5

	# Build (segments+1) pairs of (inner, outer) vertices for front and back faces.
	# Front face at z = +hd, back face at z = -hd.
	# Vertex layout per ring position i:
	#   front outer: i * 4 + 0
	#   front inner: i * 4 + 1
	#   back  outer: i * 4 + 2
	#   back  inner: i * 4 + 3
	for i in range(segments + 1):
		var t: float = float(i) / float(segments)
		var angle: float = -angle_rad * 0.5 + angle_rad * t  # centred on +Y axis
		var cos_a := cos(angle)
		var sin_a := sin(angle)

		mesh.vertices.append(Vector3(sin_a * outer_radius,  cos_a * outer_radius,  hd))  # front outer
		mesh.vertices.append(Vector3(sin_a * inner_radius,  cos_a * inner_radius,  hd))  # front inner
		mesh.vertices.append(Vector3(sin_a * outer_radius,  cos_a * outer_radius, -hd))  # back  outer
		mesh.vertices.append(Vector3(sin_a * inner_radius,  cos_a * inner_radius, -hd))  # back  inner

	# ── Outer face (normal points outward radially) ───────────────────────
	for i in range(segments):
		var fo0: int = i * 4 + 0        # front outer i
		var fo1: int = (i + 1) * 4 + 0  # front outer i+1
		var bo0: int = i * 4 + 2        # back outer i
		var bo1: int = (i + 1) * 4 + 2  # back outer i+1
		var u0: float = float(i)     / float(segments)
		var u1: float = float(i + 1) / float(segments)

		var face := GoBuildFace.new()
		face.vertex_indices = [fo0, fo1, bo1, bo0]  # CCW from outside
		face.material_index = material_index
		face.uvs = [Vector2(u0, 1.0), Vector2(u1, 1.0), Vector2(u1, 0.0), Vector2(u0, 0.0)]
		mesh.faces.append(face)

	# ── Inner face (normal points inward toward arch hollow) ─────────────
	for i in range(segments):
		var fi0: int = i * 4 + 1
		var fi1: int = (i + 1) * 4 + 1
		var bi0: int = i * 4 + 3
		var bi1: int = (i + 1) * 4 + 3
		var u0: float = float(i)     / float(segments)
		var u1: float = float(i + 1) / float(segments)

		var face := GoBuildFace.new()
		face.vertex_indices = [bi0, bi1, fi1, fi0]  # CCW from inside
		face.material_index = material_index
		face.uvs = [Vector2(u0, 0.0), Vector2(u1, 0.0), Vector2(u1, 1.0), Vector2(u0, 1.0)]
		mesh.faces.append(face)

	# ── Front face (normal +Z) ────────────────────────────────────────────
	for i in range(segments):
		var fo0: int = i * 4 + 0
		var fo1: int = (i + 1) * 4 + 0
		var fi0: int = i * 4 + 1
		var fi1: int = (i + 1) * 4 + 1
		var u0: float = float(i)     / float(segments)
		var u1: float = float(i + 1) / float(segments)

		var face := GoBuildFace.new()
		face.vertex_indices = [fo0, fi0, fi1, fo1]  # CCW from front (+Z)
		face.material_index = material_index
		face.uvs = [Vector2(u0, 1.0), Vector2(u0, 0.0), Vector2(u1, 0.0), Vector2(u1, 1.0)]
		mesh.faces.append(face)

	# ── Back face (normal -Z) ─────────────────────────────────────────────
	for i in range(segments):
		var bo0: int = i * 4 + 2
		var bo1: int = (i + 1) * 4 + 2
		var bi0: int = i * 4 + 3
		var bi1: int = (i + 1) * 4 + 3
		var u0: float = float(i)     / float(segments)
		var u1: float = float(i + 1) / float(segments)

		var face := GoBuildFace.new()
		face.vertex_indices = [bo1, bi1, bi0, bo0]  # CCW from back (-Z)
		face.material_index = material_index
		face.uvs = [Vector2(u1, 1.0), Vector2(u1, 0.0), Vector2(u0, 0.0), Vector2(u0, 1.0)]
		mesh.faces.append(face)

	mesh.rebuild_edges()
	return mesh

