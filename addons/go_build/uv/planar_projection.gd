## Auto UV planar projection for GoBuild faces.
##
## Projects each selected face onto the plane implied by its dominant normal
## axis, using 1 mesh unit = 1 texture tile by default. This gives the desired
## blockout behaviour for checker or metre textures: a face spanning 2 units
## across U produces a UV span of 2 and therefore repeats twice.
class_name PlanarProjection
extends RefCounted

# Self-preloads — dependency order:
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")


## Reproject [param face_indices] onto their dominant axis planes.
##
## [param units_per_tile] is the mesh-space size of one texture repeat.
## A value of 1.0 means a 1 m x 1 m prototype texture repeats once per metre.
##
## [param offset] is added to every UV coordinate after projection, in UV space.
## Use this to shift the entire face's UVs without changing the scale.
static func apply(
		mesh: GoBuildMesh,
		face_indices: Array[int],
		units_per_tile: float = 1.0,
		offset: Vector2 = Vector2.ZERO,
) -> void:
	if mesh == null or units_per_tile <= 0.0:
		return
	for face_idx: int in face_indices:
		if face_idx < 0 or face_idx >= mesh.faces.size():
			continue
		_apply_to_face(mesh, mesh.faces[face_idx], units_per_tile, offset)


static func _apply_to_face(
		mesh: GoBuildMesh,
		face: GoBuildFace,
		units_per_tile: float,
		offset: Vector2,
) -> void:
	var vc: int = face.vertex_indices.size()
	if vc < 3:
		return

	var normal: Vector3 = mesh.compute_face_normal(face)
	var projected: Array[Vector2] = []
	projected.resize(vc)

	var min_u: float = INF
	var min_v: float = INF
	for i: int in vc:
		var point: Vector3 = mesh.vertices[face.vertex_indices[i]]
		var uv: Vector2 = _project_point(point, normal)
		projected[i] = uv
		min_u = minf(min_u, uv.x)
		min_v = minf(min_v, uv.y)

	face.uvs.resize(vc)
	for i: int in vc:
		var uv: Vector2 = projected[i]
		face.uvs[i] = Vector2(
			(uv.x - min_u) / units_per_tile,
			(uv.y - min_v) / units_per_tile,
		) + offset


## Project [param point] into a canonical 2D basis chosen from the dominant
## component of [param normal]. Sign flips keep opposite-facing sides from
## mirroring unpredictably.
static func _project_point(point: Vector3, normal: Vector3) -> Vector2:
	var ax: float = absf(normal.x)
	var ay: float = absf(normal.y)
	var az: float = absf(normal.z)

	if ay >= ax and ay >= az:
		return Vector2(point.x, -point.z if normal.y >= 0.0 else point.z)
	if ax >= ay and ax >= az:
		return Vector2(point.z if normal.x >= 0.0 else -point.z, point.y)
	return Vector2(point.x if normal.z >= 0.0 else -point.x, point.y)