## Auto UV cylindrical projection for GoBuild faces.
##
## Projects each selected face by wrapping vertices around the Y axis.
## U = normalised angle in [0, 1] (atan2(x, z) / TAU).
## V = height / units_per_tile.
##
## When [param transform] is [constant Transform3D.IDENTITY] (the default),
## projection uses local mesh-space coordinates.  Pass the node's
## [member Node3D.global_transform] to project in world space.
##
## Seam correction: faces whose vertices straddle the atan2 discontinuity
## (the −X/+Z seam near U = 0/1) have their U values nudged so the face does
## not smear across the entire texture width.  Each vertex's U is shifted by
## +1 when it is more than 0.5 away from the face's first vertex U.
class_name CylindricalProjection
extends RefCounted

# Self-preloads — dependency order:
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")


## Reproject [param face_indices] using cylindrical mapping around the Y axis.
##
## [param units_per_tile] scales the V (height) coordinate so that
## 1.0 means one texture repeat per metre of height.
##
## [param transform] maps local vertices into the projection space.  Pass
## [constant Transform3D.IDENTITY] for local-space projection, or the node's
## [member Node3D.global_transform] for world-space projection.
##
## [param offset] is added to every UV coordinate after projection, in UV space.
##
## [param seam_rotation] shifts the longitude seam in degrees.  A value of 180
## moves the seam to the +X/−Z side; use this to hide the seam on a face that
## would otherwise sit right on the atan2 discontinuity.
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

	# First pass: compute raw UV for each vertex.
	for i: int in vc:
		var p: Vector3 = transform * mesh.vertices[face.vertex_indices[i]]
		# Apply seam_rotation by shifting longitude before normalisation.
		var u: float = fposmod((atan2(p.x, p.z) / TAU + 0.5) + seam_rotation / 360.0, 1.0)
		var v: float = p.y / units_per_tile
		face.uvs[i] = Vector2(u, v)

	# Seam correction: if any vertex U differs from vertex 0 by more than 0.5,
	# shift it by ±1 to reduce the cross-seam smear on a single face.
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
