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

## Minimum pick radius below which we fall back to the constant.
## Prevents the pick target from becoming unusably tiny at extreme zoom.
const _MIN_PICK_RADIUS_PX: float = 6.0

## Multiplier applied to the projected visual half-size to circumscribe
## the cube face (sqrt(2) ≈ 1.414).  A cube's face diagonal extends
## sqrt(2) × half from centre, so this makes the pick circle exactly
## cover the visible corners of a face-on cube.
const _CUBE_CIRCUMSCRIBE: float = 1.4142

## Same multiplier for edge ribbon (slightly wider strip, not a square).
const _RIBBON_CIRCUMSCRIBE: float = 1.5


## Compute the vertex pick radius in pixels by projecting the visual cube
## corner to screen, matching exactly how the cube is drawn.
##
## This uses the same projection-based approach as the plane and view-plane
## gizmo handles: project a known world-space offset from the cube centre to
## screen, measure the pixel distance, and use that as the pick radius.
## This guarantees the pick radius stays in sync with the visual size at
## every viewport resolution, zoom level, and camera mode — without needing
## a separate scale-constant that must be manually updated.
##
## [param world_pos] is the world-space position of the vertex being picked.
## On perspective cameras, the projected size varies with distance, so each
## vertex gets its own pick radius.  The gizmo scale makes the cube
## roughly distance-independent, but projecting per-vertex is both more
## accurate and more self-syncing.
##
## Falls back to [constant VERTEX_PICK_RADIUS_PX] when the camera or its
## viewport is unavailable (headless / unit-test contexts).
static func compute_vertex_pick_radius_from_world(
		camera: Camera3D,
		world_pos: Vector3,
		gizmo_scale: float,
) -> float:
	if camera == null:
		return VERTEX_PICK_RADIUS_PX
	# Project the cube centre and a corner offset to screen.
	# The corner is VERTEX_CUBE_HALF * gizmo_scale in world units, along
	# (1,1,1) normalised — which is what _draw_vertices uses.
	if not camera.is_position_in_frustum(world_pos):
		return VERTEX_PICK_RADIUS_PX
	var centre_screen: Vector2 = camera.unproject_position(world_pos)
	# Build a local-space corner offset matching the gizmo draw code.
	# _draw_vertices uses cube_half = VERTEX_CUBE_HALF * gizmo_scale.
	var corner_world: Vector3 = world_pos + Vector3.ONE * (VERTEX_CUBE_HALF * gizmo_scale)
	if not camera.is_position_in_frustum(corner_world):
		# The corner is behind the camera — fall back to formula.
		return _fallback_vertex_pick_radius(camera)
	var corner_screen: Vector2 = camera.unproject_position(corner_world)
	var projected_half_px: float = centre_screen.distance_to(corner_screen)
	# The projected half-size is the screen distance from cube centre to one
	# corner (3D diagonal).  For a face-on cube, the face diagonal pixel
	# distance equals this value, so circumscribing the face needs
	# multiplying by sqrt(2)/sqrt(3).  But the 3D diagonal on screen is
	# already sufficient for a generous hit target — just use it directly
	# with a small comfort multiplier.
	var pick_r: float = maxf(projected_half_px * _CUBE_CIRCUMSCRIBE, _MIN_PICK_RADIUS_PX)
	return pick_r


## Compute the edge pick radius in pixels using the same projection approach,
## scaled by the ribbon ratio.
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
## [param threshold_px]: fixed pick radius override in pixels.
## Pass [code]-1.0[/code] (default) to auto-compute from the camera viewport
## via [method compute_vertex_pick_radius_from_world] so the hitbox matches the cube.
static func find_nearest_vertex(
		camera: Camera3D,
		click_pos: Vector2,
		node: GoBuildMeshInstance,
		gbm: GoBuildMesh,
		threshold_px: float = -1.0,
) -> int:
	var gt: Transform3D = node.global_transform
	# Use the node's world position as the reference point for gizmo scale,
	# exactly like GoBuildGizmo._redraw() does for drawing vertices.
	var gizmo_scale: float = _compute_gizmo_scale_at(camera, node.global_position)
	var pick_r: float = compute_vertex_pick_radius_from_world(
			camera, node.global_position, gizmo_scale) \
			if threshold_px < 0.0 else threshold_px
	var pick_r_sq: float = pick_r * pick_r

	var best_idx: int = -1
	var best_dist_sq: float = pick_r_sq

	for idx: int in gbm.vertices.size():
		var world_pos: Vector3 = gt * gbm.vertices[idx]
		if not camera.is_position_in_frustum(world_pos):
			continue
		var screen_pos: Vector2 = camera.unproject_position(world_pos)
		var dist_sq: float = screen_pos.distance_squared_to(click_pos)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_idx = idx

	return best_idx


# ---------------------------------------------------------------------------
# Edge picking
# ---------------------------------------------------------------------------

## Return the index of the nearest edge whose projected screen segment comes
## within [param threshold_px] pixels of [param click_pos], or [code]-1[/code].
static func find_nearest_edge(
		camera: Camera3D,
		click_pos: Vector2,
		node: GoBuildMeshInstance,
		gbm: GoBuildMesh,
		threshold_px: float = -1.0,
) -> int:
	var gt: Transform3D = node.global_transform
	var gizmo_scale: float = _compute_gizmo_scale_at(camera, node.global_position)
	var pick_r: float = compute_edge_pick_radius_from_world(
			camera, node.global_position, gizmo_scale) \
			if threshold_px < 0.0 else threshold_px
	var best_idx: int = -1
	var best_dist: float = pick_r

	for idx: int in gbm.edges.size():
		var edge: GoBuildEdge = gbm.edges[idx]
		var wa: Vector3 = gt * gbm.vertices[edge.vertex_a]
		var wb: Vector3 = gt * gbm.vertices[edge.vertex_b]
		if not camera.is_position_in_frustum(wa) and not camera.is_position_in_frustum(wb):
			continue
		var sa: Vector2 = camera.unproject_position(wa)
		var sb: Vector2 = camera.unproject_position(wb)
		var dist: float = point_to_segment_dist(click_pos, sa, sb)
		if dist < best_dist:
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


