## Auto UV spherical projection for GoBuild faces.
##
## Projects each selected face using latitude/longitude (equirectangular) mapping
## centred on the world/local origin.
##
## U = normalised longitude in [0, 1]  (atan2(x, z) / TAU + 0.5).
## V = normalised latitude  in [0, 1]  (0 = north pole / +Y, 1 = south pole / −Y).
##
## Both are divided by [param units_per_tile]:
##   units_per_tile = 1.0  → U and V each span [0, 1] on a unit sphere.
##   units_per_tile = 0.5  → the texture repeats twice per sphere.
##
## When [param transform] is [constant Transform3D.IDENTITY] (the default), vertices
## are projected in local mesh space.  Pass the node's
## [member Node3D.global_transform] to project in world space.
##
## Seam correction: faces whose vertices straddle the atan2 longitude
## discontinuity (the −X/+Z seam near U = 0/1) have their U values nudged
## so the face does not smear across the entire texture width.
##
## Pole handling: vertices at or very near the poles (‖p‖ ≈ 0 or y/‖p‖ ≈ ±1)
## use U = 0.5 (the antimeridian midpoint) to avoid undefined values.
class_name SphericalProjection
extends RefCounted

# Self-preloads — dependency order:
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")


## Reproject [param face_indices] using spherical (equirectangular) mapping.
##
## [param units_per_tile] controls how many texture repeats span the full sphere.
## A value of 1.0 maps a complete UV sphere to the [0, 1] × [0, 1] UV space.
##
## [param transform] maps local vertices into the projection space.  Pass
## [constant Transform3D.IDENTITY] for local-space projection, or the node's
## [member Node3D.global_transform] for world-space projection.
##
## [param offset] is added to every UV coordinate after projection, in UV space.
##
## [param seam_rotation] shifts the longitude seam in degrees.  A value of 180
## moves the seam to the +X/−Z side.
static func apply(
		mesh: GoBuildMesh,
		face_indices: Array[int],
		units_per_tile: float = 1.0,
		transform: Transform3D = Transform3D.IDENTITY,
		offset: Vector2 = Vector2.ZERO,
		seam_rotation: float = 0.0,
) -> void:
	if mesh == null or units_per_tile <= 0.0:
		return
	for face_idx: int in face_indices:
		if face_idx < 0 or face_idx >= mesh.faces.size():
			continue
		_apply_to_face(mesh, mesh.faces[face_idx], units_per_tile, transform, offset, seam_rotation)


static func _apply_to_face(
		mesh: GoBuildMesh,
		face: GoBuildFace,
		units_per_tile: float,
		transform: Transform3D,
		offset: Vector2,
		seam_rotation: float,
) -> void:
	var vc: int = face.vertex_indices.size()
	if vc < 3:
		return

	face.uvs.resize(vc)

	# First pass: compute raw UV per vertex.
	for i: int in vc:
		face.uvs[i] = _spherical_uv(
			transform * mesh.vertices[face.vertex_indices[i]],
			units_per_tile,
			seam_rotation,
		)

	# Seam correction: shift U by ±1 when a vertex is more than 0.5 away from
	# vertex 0 so the face doesn't smear across the full texture width.
	var u0: float = face.uvs[0].x
	for i: int in range(1, vc):
		var delta: float = face.uvs[i].x - u0
		if delta > 0.5:
			face.uvs[i] = Vector2(face.uvs[i].x - 1.0, face.uvs[i].y)
		elif delta < -0.5:
			face.uvs[i] = Vector2(face.uvs[i].x + 1.0, face.uvs[i].y)

	# Apply UV offset.
	if offset != Vector2.ZERO:
		for i: int in vc:
			face.uvs[i] = face.uvs[i] + offset


## Compute the equirectangular UV for a single world-space (or local-space)
## vertex position [param p].
##
## Returns [code]Vector2(U, V)[/code] where U is longitude and V is latitude.
## Both are divided by [param units_per_tile] so 1.0 maps the full sphere to
## the [0, 1] × [0, 1] UV square.
##
## [param seam_rotation] shifts the longitude seam in degrees.
static func _spherical_uv(p: Vector3, units_per_tile: float, seam_rotation: float = 0.0) -> Vector2:
	var r: float = p.length()
	if r < 0.0001:
		# Degenerate: vertex is at the origin; place it at the centre of the UV.
		return Vector2(0.5, 0.5) / units_per_tile

	# Longitude: atan2(x, z) → [−π, π], remap to [0, 1], then apply seam rotation.
	var u: float = fposmod((atan2(p.x, p.z) / TAU + 0.5) + seam_rotation / 360.0, 1.0) / units_per_tile

	# Latitude: acos(y / r) → [0, π], normalise to [0, 1] (0 = north, 1 = south).
	var y_norm: float = clamp(p.y / r, -1.0, 1.0)
	var v: float = acos(y_norm) / (PI * units_per_tile)

	return Vector2(u, v)
