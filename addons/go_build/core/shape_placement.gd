## Placement helper for inserting new shapes at the 3D cursor position.
##
## Casts a ray from the camera through a screen point and finds the best
## world-space position and parent node for a new [GoBuildMeshInstance].
##
## Strategy:
## 1. Raycast against all [GoBuildMeshInstance] nodes in the scene.
## 2. On hit — place as child of the hit node, offset so the shape sits
##    flush on the surface.
## 3. On miss — intersect the ray with a reference Y-plane and place as
##    sibling of the edited node (or under scene root if no edit target).
@tool
class_name ShapePlacement
extends RefCounted

# Self-preloads
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _MESH_INSTANCE_SCRIPT := \
		preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _PICKING_SCRIPT := preload("res://addons/go_build/core/picking_helper.gd")

const _HIT_NORMAL_MIN_DOT: float = 0.01


## Result of [method find_placement].
##
## [code]parent[/code] is the recommended parent node (may be null for
## no-hit cases, meaning scene root should be used).
## [code]world_pos[/code] is the spawn position in world space, already
## offset so the shape sits flush on the hit surface.
## [code]hit_normal[/code] is the surface normal at the hit point (or
## [constant Vector3.UP] for plane intersections).
## [code]did_hit[/code] is true when a mesh was raycasted.
class PlacementResult:
	var parent: GoBuildMeshInstance = null
	var world_pos: Vector3 = Vector3.ZERO
	var hit_normal: Vector3 = Vector3.UP
	var did_hit: bool = false


## Cast a ray from [param camera] through [param screen_pos] and find
## the best placement for a new shape.
##
## [param edited_node] is the currently edited [GoBuildMeshInstance] (used
## for the Y-plane fallback height).  May be null.
##
## Returns a [PlacementResult] with the recommended parent, world position,
## surface normal, and whether a mesh was hit.
static func find_placement(
		camera: Camera3D,
		screen_pos: Vector2,
		edited_node: GoBuildMeshInstance,
) -> PlacementResult:
	var result := PlacementResult.new()
	var scene_root: Node = EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return result

	var ray_from: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)

	# Walk all GoBuildMeshInstance nodes, find closest ray-triangle hit.
	var best_t: float = INF
	var best_node: GoBuildMeshInstance = null
	var best_face_idx: int = -1

	for node: Node in scene_root.find_children("*", "Node3D", true, false):
		if not (node is GoBuildMeshInstance):
			continue
		var mi: GoBuildMeshInstance = node as GoBuildMeshInstance
		if mi.go_build_mesh == null or mi.mesh == null:
			continue
		# Quick AABB rejection.
		var inv: Transform3D = mi.global_transform.affine_inverse()
		var local_from: Vector3 = inv * ray_from
		var local_dir: Vector3 = inv.basis * ray_dir
		if mi.get_aabb().intersects_ray(local_from, local_dir) == null:
			continue
		var face_idx: int = PickingHelper.find_nearest_face(
				camera, screen_pos, mi, mi.go_build_mesh)
		if face_idx == -1:
			continue
		# Compute hit distance for depth comparison.
		var face: GoBuildFace = mi.go_build_mesh.faces[face_idx]
		var gt: Transform3D = mi.global_transform
		var centroid: Vector3 = Vector3.ZERO
		for vi: int in face.vertex_indices:
			centroid += gt * mi.go_build_mesh.vertices[vi]
		centroid /= float(face.vertex_indices.size())
		var dist_sq: float = camera.global_position.distance_squared_to(centroid)
		if dist_sq < best_t:
			best_t = dist_sq
			best_node = mi
			best_face_idx = face_idx

	if best_node != null and best_face_idx >= 0:
		result.did_hit = true
		result.parent = best_node
		# Compute world-space hit point from the closest face.
		var gbm: GoBuildMesh = best_node.go_build_mesh
		var face: GoBuildFace = gbm.faces[best_face_idx]
		var gt: Transform3D = best_node.global_transform
		var inv_gt: Transform3D = gt.affine_inverse()
		var local_from: Vector3 = inv_gt * ray_from
		var local_dir: Vector3 = (inv_gt.basis * ray_dir).normalized()
		# Fan-triangulate to find exact hit point.
		var best_local_t: float = INF
		var best_face_normal: Vector3 = Vector3.UP
		var v0: Vector3 = gbm.vertices[face.vertex_indices[0]]
		for tri: int in range(face.vertex_indices.size() - 2):
			var v1: Vector3 = gbm.vertices[face.vertex_indices[tri + 1]]
			var v2: Vector3 = gbm.vertices[face.vertex_indices[tri + 2]]
			var t: float = PickingHelper.ray_triangle_intersect(
					local_from, local_dir, v0, v1, v2)
			if t >= 0.0 and t < best_local_t:
				best_local_t = t
				var tri_normal: Vector3 = (v2 - v0).cross(v1 - v0)
				if tri_normal.length_squared() > 0.0:
					best_face_normal = tri_normal.normalized()
		var local_hit: Vector3 = local_from + local_dir * best_local_t
		var world_hit: Vector3 = gt * local_hit
		# Transform normal to world space.
		var world_normal: Vector3 = (gt.basis * best_face_normal).normalized()
		if world_normal.dot(Vector3.UP) < _HIT_NORMAL_MIN_DOT and \
				world_normal.dot(Vector3.DOWN) < _HIT_NORMAL_MIN_DOT:
			world_normal = Vector3.UP
		result.hit_normal = world_normal
		result.world_pos = world_hit
	else:
		# No mesh hit — intersect with Y plane at edited node height (or Y=0).
		var plane_y: float = 0.0
		if edited_node != null and is_instance_valid(edited_node):
			plane_y = edited_node.global_position.y
		if not ray_dir.y == 0.0:
			var t_plane: float = (plane_y - ray_from.y) / ray_dir.y
			if t_plane > 0.0:
				result.world_pos = ray_from + ray_dir * t_plane
			else:
				# Camera is below the plane looking away — fallback to origin.
				result.world_pos = Vector3(0.0, plane_y, 0.0)
		else:
			result.world_pos = Vector3(0.0, plane_y, 0.0)
		result.hit_normal = Vector3.UP

	return result


## Compute the offset along [param normal] needed so a shape with local
## [AABB] [param local_aabb] sits flush on the surface.
##
## The offset centres the shape so its bottom face (along the normal direction)
## aligns with the hit point.  For a shape with half-heights [0.5, 0.5, 0.5]
## and normal [constant Vector3.UP], returns [code]0.5[/code].
static func bottom_offset(local_aabb: AABB, normal: Vector3) -> float:
	if normal.is_zero_approx():
		return 0.0
	var half_extents: Vector3 = local_aabb.size * 0.5
	var center: Vector3 = local_aabb.position + half_extents
	# Project the box center-to-bottom vector along the normal.
	# "Bottom" is the side the normal points away from.
	var offset_along: float = half_extents.dot(normal.abs())
	# We also need to correct for the AABB center not being at origin.
	var center_offset: float = center.dot(normal)
	return offset_along - center_offset