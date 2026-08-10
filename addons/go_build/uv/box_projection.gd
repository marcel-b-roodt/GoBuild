## Auto UV box projection for GoBuild faces.
##
## Projects each selected face independently onto the axis-aligned plane implied
## by its dominant normal.  When [param transform] is [constant Transform3D.IDENTITY]
## (the default), projection uses local mesh-space coordinates.  Pass the
## node's [member Node3D.global_transform] to project in world space so that UVs
## tile seamlessly across multiple instances and update live as the object moves.
##
## Contrast with [PlanarProjection]: planar resets UV origin per-face (every
## face starts at (0, 0)), so sibling faces do not share UV coordinates at
## shared edges.  Box projection preserves world-space position divided by
## [param units_per_tile], giving seamless tiling across co-planar or
## axis-aligned adjacent faces.
class_name BoxProjection
extends RefCounted

# Self-preloads — dependency order:
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _UV_UTILS_SCRIPT := preload("res://addons/go_build/uv/uv_projection_utils.gd")


## Reproject [param face_indices] using box (triplanar) mapping.
##
## [param units_per_tile] is the mesh-space size of one texture repeat.
## A value of 1.0 means a 1 m × 1 m prototype texture repeats once per metre.
##
## [param transform] maps local vertices into the projection space.  Pass
## [constant Transform3D.IDENTITY] (default) for local-space projection, or pass
## the node’s [member Node3D.global_transform] for world-space projection.
##
## [param offset] is added to every UV coordinate after projection, in UV space.
static func apply(
		mesh: GoBuildMesh,
		face_indices: Array[int],
		units_per_tile: float = 1.0,
		transform: Transform3D = Transform3D.IDENTITY,
		offset: Vector2 = Vector2.ZERO,
) -> void:
	if mesh == null or units_per_tile <= 0.0:
		return
	for face_idx: int in face_indices:
		if face_idx < 0 or face_idx >= mesh.faces.size():
			continue
		_apply_to_face(mesh, mesh.faces[face_idx], units_per_tile, transform, offset)


static func _apply_to_face(
		mesh: GoBuildMesh,
		face: GoBuildFace,
		units_per_tile: float,
		transform: Transform3D,
		offset: Vector2,
) -> void:
	var vc: int = face.vertex_indices.size()
	if vc < 3:
		return

	var local_normal: Vector3 = mesh.compute_face_normal(face)
	# Transform normal into projection space (inverse-transpose = basis for
	# uniform-scale or orthogonal transforms; normalise to handle scale).
	var normal: Vector3 = (transform.basis * local_normal).normalized()
	face.uvs.resize(vc)
	for i: int in vc:
		var point: Vector3 = transform * mesh.vertices[face.vertex_indices[i]]
		face.uvs[i] = UVProjectionUtils.project_to_dominant_axis(point, normal) / units_per_tile + offset
