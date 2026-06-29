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
const _CATALOG_SCRIPT := preload(
		"res://addons/go_build/mesh/generators/shape_creation_catalog.gd")

## Result of [method find_placement].
##
## [code]parent[/code] is the recommended parent node (may be null for
## no-hit cases, meaning scene root should be used).
## [code]world_pos[/code] is the spawn position in world space.
## [code]hit_normal[/code] is the surface normal at the hit point (or
## [constant Vector3.UP] for plane intersections).
## [code]did_hit[/code] is true when a mesh was raycasted.
## [code]shape_aabb[/code] is the local AABB of the shape being placed,
## set by [method apply_bottom_offset]. Used to compute flush placement.
## [code]align_to_normal[/code] is true when the shape should be rotated so its
## Y axis aligns with the hit normal (set by [method apply_bottom_offset]).
class PlacementResult:
	var parent: GoBuildMeshInstance = null
	var world_pos: Vector3 = Vector3.ZERO
	var hit_normal: Vector3 = Vector3.UP
	var did_hit: bool = false
	var shape_aabb: AABB = AABB()
	var align_to_normal: bool = false


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
		exclude: GoBuildMeshInstance = null,
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
		if mi == exclude:
			continue
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
		if world_normal.is_zero_approx():
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
				# Camera below plane looking away — fallback to origin.
				result.world_pos = Vector3(0.0, plane_y, 0.0)
		else:
			result.world_pos = Vector3(0.0, plane_y, 0.0)
		result.hit_normal = Vector3.UP

	return result


## Construct a [Basis] that rotates the Y axis ([constant Vector3.UP])
## to align with [param normal].  The normal is expected to point **into**
## the surface (inward), so this function negates it to derive the outward
## direction for the Y axis.
##
## For near-vertical normals (within 0.001 of UP or DOWN), returns identity
## (or 180-degree flip for DOWN) to avoid gimbal lock.
## For all other normals, uses two cross products to build an orthonormal basis
## where Y = -normal (outward), Z = project(UP, normal_plane), X = Y x Z.
static func _align_y_to_normal(normal: Vector3) -> Basis:
	var outward: Vector3 = -normal.normalized()
	if absf(outward.dot(Vector3.UP)) > 0.9999:
		if outward.y < 0.0:
			return Basis(Vector3.RIGHT, Vector3.DOWN, Vector3.BACK)
		return Basis.IDENTITY
	var y_axis: Vector3 = outward
	var z_axis: Vector3 = Vector3.UP - y_axis * y_axis.dot(Vector3.UP)
	z_axis = z_axis.normalized()
	var x_axis: Vector3 = y_axis.cross(z_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)


## Compute the offset (in child-local space) so a shape with [param aabb]
## sits flush on a surface with [param hit_normal].
##
## The shape is pushed away from the surface along the normal by the projected
## AABB extent, so its nearest face touches the hit point at any angle.
## When [param align_to_normal] is false and the normal is wall-like (|y| <= 0.5),
## a Y correction shifts the shape so its AABB Y-minimum sits at the click height.
## When [param align_to_normal] is true, the Y correction is skipped because
## the rotation will align the shape's Y axis with the surface, making the
## normal-direction push sufficient.
##
## The returned offset is subtracted from the hit position:
## [code]local_pos = local_hit - offset[/code]
static func _flush_offset(
		aabb: AABB, hit_normal: Vector3,
		align_to_normal: bool = false) -> Vector3:
	if hit_normal.is_zero_approx():
		return Vector3.ZERO
	var mn: Vector3 = aabb.position
	var mx: Vector3 = aabb.position + aabb.size
	if align_to_normal:
		# When the shape's Y axis aligns with hit_normal, the face that
		# touches the surface is the mesh-local -Y face.  Push the origin
		# away from the surface by the distance to that face.
		var bottom_dist: float = absf(mn.y)
		return hit_normal * bottom_dist
	# General case (no rotation): AABB support function.
	var dist: float = mx.x * maxf(hit_normal.x, 0.0) \
			+ mn.x * minf(hit_normal.x, 0.0) \
			+ mx.y * maxf(hit_normal.y, 0.0) \
			+ mn.y * minf(hit_normal.y, 0.0) \
			+ mx.z * maxf(hit_normal.z, 0.0) \
			+ mn.z * minf(hit_normal.z, 0.0)
	var offset: Vector3 = hit_normal * dist
	# Wall hits without normal alignment: shift Y so the shape's
	# AABB Y-minimum sits at the click height, preventing sinking.
	if absf(hit_normal.y) <= 0.5 and mn.y < 0.0:
		offset.y = mn.y
	return offset


## Build a temporary mesh for [param shape_name] with default parameters,
## compute its AABB, and store it on [param placement].
##
## When [param align_to_surface] is true, sets
## [member PlacementResult.align_to_normal] so the shape will be rotated
## to align its Y axis with the hit normal.
## Does [b]not[/b] modify [param placement].world_pos — the offset is applied
## later by [method resolve_parent_and_position].
static func apply_bottom_offset(
		placement: PlacementResult,
		shape_name: String,
		align_to_surface: bool = true,
) -> void:
	var mesh: GoBuildMesh = _CATALOG_SCRIPT.build_mesh(
			shape_name, _CATALOG_SCRIPT.default_params(shape_name))
	if mesh == null:
		return
	placement.shape_aabb = mesh.compute_aabb()
	placement.align_to_normal = align_to_surface


## Resolve the parent node, local position, and local rotation for a new shape.
##
## Given a [PlacementResult] (from [method find_placement]) and the currently
## edited node, determines:
## - [code]parent[/code]: the [Node] under which the new shape should be added
##   (hit mesh, edited node's parent, or scene root)
## - [code]local_pos[/code]: the position in parent-local space at which the
##   shape should be placed, offset so its AABB face sits flush on the hit surface.
## - [code]local_basis[/code]: the [Basis] to apply to the shape's rotation,
##   aligning its Y axis with the hit normal when [member PlacementResult.align_to_normal]
##   is true, or [constant Basis.IDENTITY] otherwise.
##
## When [param align_to_normal] is true, the Y correction in [method _flush_offset]
## is skipped because the rotation handles vertical alignment.
##
## The parent's full transform (scale, rotation) is correctly accounted for via
## [method Transform3D.affine_inverse].
##
## When [param placement] is null (no camera/scene), returns scene_root as parent
## with position at the origin and identity basis.
static func resolve_parent_and_position(
		placement: PlacementResult,
		edited_node: GoBuildMeshInstance,
		scene_root: Node,
) -> Dictionary:
	if placement == null:
		return {"parent": scene_root, "local_pos": Vector3.ZERO,
				"local_basis": Basis.IDENTITY}
	var offset: Vector3 = _flush_offset(placement.shape_aabb, placement.hit_normal,
			placement.align_to_normal)
	var world_basis: Basis = Basis.IDENTITY
	if placement.align_to_normal:
		world_basis = _align_y_to_normal(placement.hit_normal)
	if placement.did_hit and placement.parent != null:
		var parent: Node = placement.parent
		var inv: Transform3D = parent.global_transform.affine_inverse()
		var local_hit: Vector3 = inv * placement.world_pos
		var local_offset: Vector3 = inv.basis * offset
		var local_basis: Basis = inv.basis * world_basis
		return {"parent": parent, "local_pos": local_hit - local_offset,
				"local_basis": local_basis}
	if edited_node != null and edited_node.get_parent() != null:
		var parent: Node = edited_node.get_parent()
		var inv: Transform3D = parent.global_transform.affine_inverse()
		var local_hit: Vector3 = inv * placement.world_pos
		var local_offset: Vector3 = inv.basis * offset
		var local_basis: Basis = inv.basis * world_basis
		return {"parent": parent, "local_pos": local_hit - local_offset,
				"local_basis": local_basis}
	return {"parent": scene_root, "local_pos": placement.world_pos - offset,
			"local_basis": world_basis}