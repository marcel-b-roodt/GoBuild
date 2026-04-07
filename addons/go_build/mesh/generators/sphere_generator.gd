## Generates a [GoBuildMesh] representing a UV sphere.
##
## The sphere is centred at the origin. Horizontal rings of latitude quads
## run between two polar triangle fans (north and south poles).
## UV mapping uses standard spherical projection: U wraps around the equator,
## V goes from south pole (0) to north pole (1).
class_name SphereGenerator
extends RefCounted

## Generate a UV sphere [GoBuildMesh].
##
## [param radius]          sphere radius (must be > 0)
## [param rings]           horizontal latitude bands; must be >= 2
## [param segments]        longitudinal columns; must be >= 3
## [param material_index]  material slot for all faces
static func generate(
		radius: float = 0.5,
		rings: int = 8,
		segments: int = 16,
		material_index: int = 0,
) -> GoBuildMesh:
	assert(radius   > 0.0, "SphereGenerator: radius must be > 0")
	assert(rings    >= 2,  "SphereGenerator: rings must be >= 2")
	assert(segments >= 3,  "SphereGenerator: segments must be >= 3")

	var mesh := GoBuildMesh.new()

	# ── Vertex grid ──────────────────────────────────────────────────────
	# rows 0..rings  (rings+1 rows, rows 0 and rings are poles)
	# cols 0..segments-1 (seam duplicated as col segments for UV continuity)
	#
	# Row 0     = south pole ring  (all coincide at  y = -radius)
	# Row rings = north pole ring  (all coincide at  y = +radius)
	# Rows 1..rings-1 = latitude bands
	#
	# Index formula: row * (segments + 1) + col
	for row in range(rings + 1):
		var phi: float = PI * float(row) / float(rings)       # 0 (south) → PI (north)
		var y: float   = -cos(phi) * radius
		var r: float   = sin(phi)  * radius                   # horizontal radius at this lat

		for col in range(segments + 1):
			var theta: float = TAU * float(col) / float(segments)
			var x: float = cos(theta) * r
			var z: float = -sin(theta) * r
			mesh.vertices.append(Vector3(x, y, z))

	# ── Lateral quad rings (rows 2 .. rings-1) ───────────────────────────
	# Rows 0→1 are covered by the south pole cap triangles.
	# Rows (rings-1)→rings are covered by the north pole cap triangles.
	for row in range(2, rings):
		for col in range(segments):
			var i00: int = (row - 1) * (segments + 1) + col
			var i10: int = (row - 1) * (segments + 1) + col + 1
			var i11: int =  row      * (segments + 1) + col + 1
			var i01: int =  row      * (segments + 1) + col

			var u0: float = float(col)     / float(segments)
			var u1: float = float(col + 1) / float(segments)
			var v0: float = float(row - 1) / float(rings)
			var v1: float = float(row)     / float(rings)

			var face := GoBuildFace.new()
			face.vertex_indices = [i00, i10, i11, i01]
			face.material_index = material_index
			face.uvs = [
				Vector2(u0, v0), Vector2(u1, v0),
				Vector2(u1, v1), Vector2(u0, v1),
			]
			mesh.faces.append(face)

	# ── South pole cap (row 0 → row 1) ───────────────────────────────────
	for col in range(segments):
		var pole: int = col                                      # row 0 col (all at south pole)
		var b0: int   = 1 * (segments + 1) + col
		var b1: int   = 1 * (segments + 1) + col + 1

		var u0: float = float(col)     / float(segments)
		var u1: float = float(col + 1) / float(segments)
		var um: float = (u0 + u1) * 0.5

		var face := GoBuildFace.new()
		# CCW from outside (outward = downward at south): pole, b1, b0
		face.vertex_indices = [pole, b1, b0]
		face.material_index = material_index
		face.uvs = [Vector2(um, 0.0), Vector2(u1, 1.0 / float(rings)), Vector2(u0, 1.0 / float(rings))]
		mesh.faces.append(face)

	# ── North pole cap (row rings-1 → row rings) ─────────────────────────
	for col in range(segments):
		var t0: int  = (rings - 1) * (segments + 1) + col
		var t1: int  = (rings - 1) * (segments + 1) + col + 1
		var pole: int = rings * (segments + 1) + col          # row rings col (all at north)

		var u0: float = float(col)     / float(segments)
		var u1: float = float(col + 1) / float(segments)
		var um: float = (u0 + u1) * 0.5

		var face := GoBuildFace.new()
		# CCW from outside (outward = upward at north): t0, t1, pole
		face.vertex_indices = [t0, t1, pole]
		face.material_index = material_index
		var v_band: float = float(rings - 1) / float(rings)
		face.uvs = [Vector2(u0, v_band), Vector2(u1, v_band), Vector2(um, 1.0)]
		mesh.faces.append(face)

	WeldOperation.apply_weld_by_threshold(mesh)
	return mesh

