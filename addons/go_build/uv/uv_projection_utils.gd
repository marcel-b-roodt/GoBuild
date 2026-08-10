## Shared UV projection utilities used by all UV projection algorithms.
##
## Centralises the dominant-axis projection, seam correction, and UV vertex
## map helpers that were previously duplicated across [PlanarProjection],
## [BoxProjection], [CylindricalProjection], and [SphericalProjection].
class_name UVProjectionUtils
extends RefCounted


## Project [param point] into a canonical 2D basis chosen from the dominant
## component of [param normal].  Sign flips keep opposite-facing sides from
## mirroring unpredictably.
##
## Used by [PlanarProjection] and [BoxProjection].
static func project_to_dominant_axis(point: Vector3, normal: Vector3) -> Vector2:
	var ax: float = absf(normal.x)
	var ay: float = absf(normal.y)
	var az: float = absf(normal.z)

	if ay >= ax and ay >= az:
		return Vector2(point.x, -point.z if normal.y >= 0.0 else point.z)
	if ax >= ay and ax >= az:
		return Vector2(point.z if normal.x >= 0.0 else -point.z, point.y)
	return Vector2(point.x if normal.z >= 0.0 else -point.x, point.y)


## Correct U values for faces that straddle the ±0.5 U discontinuity
## (cylindrical / spherical seam).  For each UV in [param face.uvs], if
## the delta from [code]face.uvs[0].x[/code] exceeds 0.5, shift U by ±1.
##
## Used by [CylindricalProjection] and [SphericalProjection].
static func correct_seam(face: GoBuildFace) -> void:
	var vc: int = face.uvs.size()
	if vc < 2:
		return
	var u0: float = face.uvs[0].x
	for i: int in range(1, vc):
		var delta: float = face.uvs[i].x - u0
		if delta > 0.5:
			face.uvs[i] = Vector2(face.uvs[i].x - 1.0, face.uvs[i].y)
		elif delta < -0.5:
			face.uvs[i] = Vector2(face.uvs[i].x + 1.0, face.uvs[i].y)