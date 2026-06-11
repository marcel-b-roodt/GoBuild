## Screen-space and ray-cast picking utilities for the GoBuild 3D viewport.
##
## Camera-dependent methods project mesh element positions into screen space
## using the editor camera; all distances are in pixels unless noted.
##
## The two pure-math helpers ([method point_to_segment_dist] and
## [method ray_triangle_intersect]) are public so they can be unit-tested
## independently of the Godot scene tree.
@tool
class_name PickingHelper
extends RefCounted

# ---------------------------------------------------------------------------
# Self-preloads — dependency order matters.
#
# Godot's startup scan processes addons/go_build/core/ alphabetically, which
# means it reaches picking_helper.gd ('pi') BEFORE mesh/ ('me').
# GoBuildFace, GoBuildEdge, GoBuildMesh, and GoBuildMeshInstance are therefore
# not yet registered when this script is first compiled.
# Explicit preloads here force the full dependency chain to resolve regardless
# of scan order — the same pattern used by go_build_gizmo.gd and go_build_panel.gd.
# ---------------------------------------------------------------------------
const _FACE_SCRIPT          := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT          := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT          := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _MESH_INSTANCE_SCRIPT := preload("res://addons/go_build/core/go_build_mesh_instance.gd")

## Screen-space radius (px) within which a vertex handle is selectable.
## This constant is a fixed fallback used in headless / test contexts where
## no real camera viewport is available.  Runtime code calls
## [method compute_vertex_pick_radius_from_world] instead so the hitbox matches
## the drawn cube at every viewport size.
const VERTEX_PICK_RADIUS_PX: float = 12.0

## Half-size of the vertex cube widget in local mesh space.
## MUST mirror [constant GoBuildGizmo.VERTEX_CUBE_HALF] — kept in sync by
## convention.  Any change to the draw constant must be reflected here.
const VERTEX_CUBE_HALF: float = 0.03

## Gizmo scale factors — mirror [constant GoBuildGizmoPlugin.GIZMO_SCREEN_FACTOR]
## and [constant GoBuildGizmoPlugin.GIZMO_ORTHO_SCALE].  Same sync rule applies.
const _GIZMO_SCREEN_FACTOR: float = 0.25   # perspective cameras
const _GIZMO_ORTHO_SCALE:   float = 0.10   # orthographic cameras

## Ratio of edge ribbon half-width to vertex cube half-size.
## MUST mirror the ratio used in GoBuildGizmo._draw_edges().
const _EDGE_RIBBON_RATIO: float = 0.8

## Screen-space radius (px) fallback for headless / test contexts where
## no camera is available.
const EDGE_PICK_RADIUS_PX: float = 8.0

## Minimum pick radius below which we fall back to a comfortable floor.
## Prevents the pick target from becoming unusably tiny at extreme zoom.
## 10 px is roughly the size of a fingertip touch target on a standard display.
const _MIN_PICK_RADIUS_PX: float = 10.0

## Multiplier applied to the projected visual half-size for vertex picking.
##
## The projection measures the screen distance from cube centre to the (1,1,1)
## corner — this is the 3D diagonal on screen.  The drawn face diagonal varies
## with viewing angle but is always ≤ the 3D diagonal, so multiplying by
## [constant _CUBE_CIRCUMSCRIBE] guarantees the hit target covers the face.
##
## A value of 2.0 gives a click target twice the 3D diagonal (≈ 2.8× the face
## diagonal), which is comfortably generous and matches common DCC tool UX where
## the click target is noticeably larger than the drawn element.
const _CUBE_CIRCUMSCRIBE: float = 2.0

## Same multiplier for edge ribbon picking.  Slightly smaller than the cube
## multiplier because edges are one-dimensional hit targets — the sausage-shaped
## pick zone around the edge centreline is inherently easier to hit than a point.
const _RIBBON_CIRCUMSCRIBE: float = 1.8


## Compute the vertex pick radius in pixels by projecting the visual cube
## corner to screen, accounting for the node's transform.
##
## Projects a local-space offset through the full global transform so that
## non-uniform scale and rotation are correctly reflected in the pick size.
## This guarantees the pick radius stays in sync with the drawn cube at
## every viewport resolution, zoom level, and camera mode.
##
## [param camera] is the editor camera.
## [param gt] is the node's global transform (local → world).
## [param local_pos] is the vertex position in local (mesh) space.
## [param gizmo_scale] is the world-space gizmo scale factor.
##
## Falls back to [constant VERTEX_PICK_RADIUS_PX] when the camera or its
## viewport is unavailable (headless / unit-test contexts).
static func compute_vertex_pick_radius_from_local(
		camera: Camera3D,
		gt: Transform3D,
		local_pos: Vector3,
		gizmo_scale: float,
) -> float:
	if camera == null:
		return VERTEX_PICK_RADIUS_PX
	var world_pos: Vector3 = gt * local_pos
	if not camera.is_position_in_frustum(world_pos):
		return VERTEX_PICK_RADIUS_PX
	var centre_screen: Vector2 = camera.unproject_position(world_pos)
	# Project a local-space corner offset through the full global transform.
	# This correctly accounts for rotation and non-uniform scale.
	var corner_local: Vector3 = local_pos + Vector3.ONE * (VERTEX_CUBE_HALF * gizmo_scale)
	var corner_world: Vector3 = gt * corner_local
	if not camera.is_position_in_frustum(corner_world):
		return _fallback_vertex_pick_radius(camera)
	var corner_screen: Vector2 = camera.unproject_position(corner_world)
	var projected_half_px: float = centre_screen.distance_to(corner_screen)
	var pick_r: float = maxf(projected_half_px * _CUBE_CIRCUMSCRIBE, _MIN_PICK_RADIUS_PX)
	return pick_r


## Compatibility wrapper: compute pick radius from a world-space position.
## Used by callers that don't have a local position.
## Prefers [method compute_vertex_pick_radius_from_local] when the local
## position and transform are available.
static func compute_vertex_pick_radius_from_world(
		camera: Camera3D,
		world_pos: Vector3,
		gizmo_scale: float,
) -> float:
	if camera == null:
		return VERTEX_PICK_RADIUS_PX
	if not camera.is_position_in_frustum(world_pos):
		return VERTEX_PICK_RADIUS_PX
	var centre_screen: Vector2 = camera.unproject_position(world_pos)
	var corner_world: Vector3 = world_pos + Vector3.ONE * (VERTEX_CUBE_HALF * gizmo_scale)
	if not camera.is_position_in_frustum(corner_world):
		return _fallback_vertex_pick_radius(camera)
	var corner_screen: Vector2 = camera.unproject_position(corner_world)
	var projected_half_px: float = centre_screen.distance_to(corner_screen)
	var pick_r: float = maxf(projected_half_px * _CUBE_CIRCUMSCRIBE, _MIN_PICK_RADIUS_PX)
	return pick_r


## Compute the edge pick radius in pixels by projecting a local-space offset
## through the node's transform, matching the ribbon half-width.
static func compute_edge_pick_radius_from_local(
		camera: Camera3D,
		gt: Transform3D,
		local_pos: Vector3,
		gizmo_scale: float,
) -> float:
	if camera == null:
		return EDGE_PICK_RADIUS_PX
	var world_pos: Vector3 = gt * local_pos
	if not camera.is_position_in_frustum(world_pos):
		return EDGE_PICK_RADIUS_PX
	var centre_screen: Vector2 = camera.unproject_position(world_pos)
	var edge_local: Vector3 = local_pos + Vector3.ONE * (
			VERTEX_CUBE_HALF * _EDGE_RIBBON_RATIO * gizmo_scale)
	var edge_world: Vector3 = gt * edge_local
	if not camera.is_position_in_frustum(edge_world):
		return _fallback_edge_pick_radius(camera)
	var edge_screen: Vector2 = camera.unproject_position(edge_world)
	var projected_half_px: float = centre_screen.distance_to(edge_screen)
	var pick_r: float = maxf(projected_half_px * _RIBBON_CIRCUMSCRIBE, _MIN_PICK_RADIUS_PX)
	return pick_r


## Compatibility wrapper: compute edge pick radius from a world-space position.
static func compute_edge_pick_radius_from_world(
		camera: Camera3D,
		world_pos: Vector3,
		gizmo_scale: float,
) -> float:
	if camera == null:
		return EDGE_PICK_RADIUS_PX
	if not camera.is_position_in_frustum(world_pos):
		return EDGE_PICK_RADIUS_PX
	var centre_screen: Vector2 = camera.unproject_position(world_pos)
	var edge_world: Vector3 = world_pos + Vector3.ONE * (
			VERTEX_CUBE_HALF * _EDGE_RIBBON_RATIO * gizmo_scale)
	if not camera.is_position_in_frustum(edge_world):
		return _fallback_edge_pick_radius(camera)
	var edge_screen: Vector2 = camera.unproject_position(edge_world)
	var projected_half_px: float = centre_screen.distance_to(edge_screen)
	var pick_r: float = maxf(projected_half_px * _RIBBON_CIRCUMSCRIBE, _MIN_PICK_RADIUS_PX)
	return pick_r


## Formula-based fallback for headless/test contexts.
## Derived from the same constants used by the gizmo scale formula.
static func _fallback_vertex_pick_radius(camera: Camera3D) -> float:
	if camera == null:
		return VERTEX_PICK_RADIUS_PX
	var vp: Viewport = camera.get_viewport()
	if vp == null:
		return VERTEX_PICK_RADIUS_PX
	var h: float = vp.get_visible_rect().size.y
	if h < 1.0:
		return VERTEX_PICK_RADIUS_PX
	var half_px: float
	if camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
		half_px = VERTEX_CUBE_HALF * _GIZMO_SCREEN_FACTOR * h * 0.5
	else:
		half_px = VERTEX_CUBE_HALF * _GIZMO_ORTHO_SCALE * h
	return maxf(half_px * _CUBE_CIRCUMSCRIBE, _MIN_PICK_RADIUS_PX)


static func _fallback_edge_pick_radius(camera: Camera3D) -> float:
	if camera == null:
		return EDGE_PICK_RADIUS_PX
	var vp: Viewport = camera.get_viewport()
	if vp == null:
		return EDGE_PICK_RADIUS_PX
	var h: float = vp.get_visible_rect().size.y
	if h < 1.0:
		return EDGE_PICK_RADIUS_PX
	var half_px: float
	if camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
		half_px = VERTEX_CUBE_HALF * _EDGE_RIBBON_RATIO * _GIZMO_SCREEN_FACTOR * h * 0.5
	else:
		half_px = VERTEX_CUBE_HALF * _EDGE_RIBBON_RATIO * _GIZMO_ORTHO_SCALE * h
	return maxf(half_px * _RIBBON_CIRCUMSCRIBE, _MIN_PICK_RADIUS_PX)


# ---------------------------------------------------------------------------
# Vertex picking
# ---------------------------------------------------------------------------

## Return the index of the nearest vertex whose projected screen position is
## within [param threshold_px] pixels of [param click_pos], or [code]-1[/code].
##
## When multiple candidates are within threshold the one with the smallest
## squared screen distance wins.
##
## When [param threshold_px] is [code]-1.0[/code] (default), each vertex gets its
## own pick radius computed from its local-space offset through the node's
## global transform.  This correctly handles perspective (closer vertices appear
## larger) and non-uniform scale / rotation on the node.
static func find_nearest_vertex(
		camera: Camera3D,
		click_pos: Vector2,
		node: GoBuildMeshInstance,
		gbm: GoBuildMesh,
		threshold_px: float = -1.0,
) -> int:
	var gt: Transform3D = node.global_transform
	var gizmo_scale: float = _compute_gizmo_scale_at(camera, node.global_position)
	var use_per_vertex: bool = threshold_px < 0.0
	var global_pick_r: float
	if not use_per_vertex:
		global_pick_r = threshold_px

	var best_idx: int = -1
	var best_dist_sq: float = INF

	for idx: int in gbm.vertices.size():
		var local_pos: Vector3 = gbm.vertices[idx]
		var world_pos: Vector3 = gt * local_pos
		if not camera.is_position_in_frustum(world_pos):
			continue
		var screen_pos: Vector2 = camera.unproject_position(world_pos)
		var dist_sq: float = screen_pos.distance_squared_to(click_pos)
		var pick_r: float
		if use_per_vertex:
			pick_r = compute_vertex_pick_radius_from_local(
					camera, gt, local_pos, gizmo_scale)
		else:
			pick_r = global_pick_r
		if dist_sq <= pick_r * pick_r and dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_idx = idx

	return best_idx


# ---------------------------------------------------------------------------
# Edge picking
# ---------------------------------------------------------------------------

## Return the index of the nearest edge whose projected screen segment comes
## within [param threshold_px] pixels of [param click_pos], or [code]-1[/code].
##
## When [param threshold_px] is [code]-1.0[/code] (default), the edge pick radius
## is computed per-edge-midpoint through the node's global transform so it
## correctly accounts for perspective and non-uniform scale.
static func find_nearest_edge(
		camera: Camera3D,
		click_pos: Vector2,
		node: GoBuildMeshInstance,
		gbm: GoBuildMesh,
		threshold_px: float = -1.0,
) -> int:
	var gt: Transform3D = node.global_transform
	var gizmo_scale: float = _compute_gizmo_scale_at(camera, node.global_position)
	var use_per_edge: bool = threshold_px < 0.0
	var global_pick_r: float
	if not use_per_edge:
		global_pick_r = threshold_px

	var best_idx: int = -1
	var best_dist: float = INF

	for idx: int in gbm.edges.size():
		var edge: GoBuildEdge = gbm.edges[idx]
		var wa: Vector3 = gt * gbm.vertices[edge.vertex_a]
		var wb: Vector3 = gt * gbm.vertices[edge.vertex_b]
		if not camera.is_position_in_frustum(wa) and not camera.is_position_in_frustum(wb):
			continue
		var sa: Vector2 = camera.unproject_position(wa)
		var sb: Vector2 = camera.unproject_position(wb)
		var dist: float = point_to_segment_dist(click_pos, sa, sb)
		var pick_r: float
		if use_per_edge:
			# Use the edge midpoint's local position for pick-radius computation.
			var mid_local: Vector3 = (gbm.vertices[edge.vertex_a] + gbm.vertices[edge.vertex_b]) * 0.5
			pick_r = compute_edge_pick_radius_from_local(
					camera, gt, mid_local, gizmo_scale)
		else:
			pick_r = global_pick_r
		if dist < pick_r and dist < best_dist:
			best_dist = dist
			best_idx = idx

	return best_idx


# ---------------------------------------------------------------------------
# Face picking
# ---------------------------------------------------------------------------

## Return the index of the face hit nearest to the camera by a ray cast
## through [param click_pos], or [code]-1[/code] if no face is hit.
##
## Uses Möller–Trumbore ray–triangle intersection (two-sided) after
## fan-triangulating each face from vertex 0.
static func find_nearest_face(
		camera: Camera3D,
		click_pos: Vector2,
		node: GoBuildMeshInstance,
		gbm: GoBuildMesh,
) -> int:
	# Convert the camera ray to the node's local space so vertex positions
	# can be used directly without transforming every vertex.
	var inv_gt: Transform3D = node.global_transform.affine_inverse()
	var ray_origin: Vector3 = inv_gt * camera.project_ray_origin(click_pos)
	# Normalise after basis transform to handle non-uniform scale gracefully.
	var ray_dir: Vector3 = (inv_gt.basis * camera.project_ray_normal(click_pos)).normalized()

	var best_idx: int = -1
	var best_t: float = INF

	for idx: int in gbm.faces.size():
		var face: GoBuildFace = gbm.faces[idx]
		if face.vertex_indices.size() < 3:
			continue
		# Fan-triangulate from vertex 0.
		var v0: Vector3 = gbm.vertices[face.vertex_indices[0]]
		for tri: int in range(face.vertex_indices.size() - 2):
			var v1: Vector3 = gbm.vertices[face.vertex_indices[tri + 1]]
			var v2: Vector3 = gbm.vertices[face.vertex_indices[tri + 2]]
			var t: float = ray_triangle_intersect(ray_origin, ray_dir, v0, v1, v2)
			if t >= 0.0 and t < best_t:
				best_t = t
				best_idx = idx

	return best_idx


# ---------------------------------------------------------------------------
# Box / rect picking  (camera-dependent; scene-runner tests deferred)
# ---------------------------------------------------------------------------

## Return indices of all vertices whose projected screen position falls inside
## [param rect] (a normalised [Rect2] in viewport pixels).
##
## Vertices behind the camera are skipped via [method Camera3D.is_position_in_frustum].
static func find_vertices_in_rect(
		camera: Camera3D,
		rect: Rect2,
		node: GoBuildMeshInstance,
		gbm: GoBuildMesh,
) -> Array[int]:
	var result: Array[int] = []
	var gt: Transform3D = node.global_transform
	for idx: int in gbm.vertices.size():
		var world_pos: Vector3 = gt * gbm.vertices[idx]
		if not camera.is_position_in_frustum(world_pos):
			continue
		if rect.has_point(camera.unproject_position(world_pos)):
			result.append(idx)
	return result


## Return indices of all edges where at least one endpoint projects into [param rect].
##
## This matches Blender's "touch" box-select behaviour for edges.
static func find_edges_in_rect(
		camera: Camera3D,
		rect: Rect2,
		node: GoBuildMeshInstance,
		gbm: GoBuildMesh,
) -> Array[int]:
	var result: Array[int] = []
	var gt: Transform3D = node.global_transform
	for idx: int in gbm.edges.size():
		var edge: GoBuildEdge = gbm.edges[idx]
		var wa: Vector3 = gt * gbm.vertices[edge.vertex_a]
		var wb: Vector3 = gt * gbm.vertices[edge.vertex_b]
		var in_a: bool = camera.is_position_in_frustum(wa) \
				and rect.has_point(camera.unproject_position(wa))
		var in_b: bool = camera.is_position_in_frustum(wb) \
				and rect.has_point(camera.unproject_position(wb))
		if in_a or in_b:
			result.append(idx)
	return result


## Return indices of all faces whose screen-projected centroid falls inside [param rect].
##
## The centroid is the arithmetic mean of the face's vertex positions.
static func find_faces_in_rect(
		camera: Camera3D,
		rect: Rect2,
		node: GoBuildMeshInstance,
		gbm: GoBuildMesh,
) -> Array[int]:
	var result: Array[int] = []
	var gt: Transform3D = node.global_transform
	for idx: int in gbm.faces.size():
		var face: GoBuildFace = gbm.faces[idx]
		if face.vertex_indices.is_empty():
			continue
		var centroid: Vector3 = Vector3.ZERO
		for vi: int in face.vertex_indices:
			centroid += gbm.vertices[vi]
		centroid /= float(face.vertex_indices.size())
		var world_pos: Vector3 = gt * centroid
		if not camera.is_position_in_frustum(world_pos):
			continue
		if rect.has_point(camera.unproject_position(world_pos)):
			result.append(idx)
	return result


# ---------------------------------------------------------------------------
# Pure-math helpers (public for unit tests)
# ---------------------------------------------------------------------------

## Return the shortest Euclidean distance from point [param p] to the 2-D
## line segment [param a]→[param b].
static func point_to_segment_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq < 1e-9:
		return p.distance_to(a)
	var t: float = clamp((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Möller–Trumbore ray–triangle intersection (two-sided).
##
## Returns the parametric distance [code]t[/code] along [param ray_dir] at the
## intersection point, or [code]-1.0[/code] if there is no intersection.
## A small positive epsilon guards against self-intersection at [code]t ≈ 0[/code].
##
## [param ray_dir] does not need to be normalised but should have consistent
## units with [param ray_origin] and the triangle vertices.
static func ray_triangle_intersect(
		ray_origin: Vector3,
		ray_dir: Vector3,
		v0: Vector3,
		v1: Vector3,
		v2: Vector3,
) -> float:
	const EPSILON: float = 1e-7
	var edge1: Vector3 = v1 - v0
	var edge2: Vector3 = v2 - v0
	var h: Vector3     = ray_dir.cross(edge2)
	var a: float       = edge1.dot(h)
	# Two-sided: accept hits from either face direction.
	if abs(a) < EPSILON:
		return -1.0   # Ray is parallel to the triangle.
	var f: float   = 1.0 / a
	var s: Vector3 = ray_origin - v0
	var u: float   = f * s.dot(h)
	if u < 0.0 or u > 1.0:
		return -1.0
	var q: Vector3 = s.cross(edge1)
	var v: float   = f * ray_dir.dot(q)
	if v < 0.0 or u + v > 1.0:
		return -1.0
	var t: float = f * edge2.dot(q)
	return t if t >= EPSILON else -1.0


# ---------------------------------------------------------------------------
# Gizmo scale (mirrors GoBuildGizmoPlugin.compute_world_gizmo_scale)
# ---------------------------------------------------------------------------

## Compute the world-space gizmo scale factor at [param world_pos], using the
## same formula as [method GoBuildGizmoPlugin.compute_world_gizmo_scale].
##
## This makes the pick radius match the drawn gizmo size at every zoom level
## and camera mode, without requiring a reference to the gizmo plugin.
##
## Falls back to [code]1.0[/code] when no camera is available (headless/tests).
static func _compute_gizmo_scale_at(camera: Camera3D, world_pos: Vector3) -> float:
	if camera == null:
		return 1.0
	var dist: float = camera.global_position.distance_to(world_pos)
	if camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
		return maxf(dist * tan(deg_to_rad(camera.fov * 0.5)) * _GIZMO_SCREEN_FACTOR, 0.01)
	return maxf(camera.size * _GIZMO_ORTHO_SCALE, 0.01)


