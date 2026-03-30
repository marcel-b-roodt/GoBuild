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
const VERTEX_PICK_RADIUS_PX: float = 12.0
## Screen-space radius (px) within which an edge line is selectable.
const EDGE_PICK_RADIUS_PX: float = 8.0


# ---------------------------------------------------------------------------
# Vertex picking
# ---------------------------------------------------------------------------

## Return the index of the nearest vertex whose projected screen position is
## within [param threshold_px] pixels of [param click_pos], or [code]-1[/code].
##
## When multiple candidates are within threshold the one with the smallest
## squared screen distance wins.
static func find_nearest_vertex(
		camera: Camera3D,
		click_pos: Vector2,
		node: GoBuildMeshInstance,
		gbm: GoBuildMesh,
		threshold_px: float = VERTEX_PICK_RADIUS_PX,
) -> int:
	var gt: Transform3D = node.global_transform
	var best_idx: int = -1
	var best_dist_sq: float = threshold_px * threshold_px

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
		threshold_px: float = EDGE_PICK_RADIUS_PX,
) -> int:
	var gt: Transform3D = node.global_transform
	var best_idx: int = -1
	var best_dist: float = threshold_px

	for idx: int in gbm.edges.size():
		var edge: GoBuildEdge = gbm.edges[idx]
		var wa: Vector3 = gt * gbm.vertices[edge.vertex_a]
		var wb: Vector3 = gt * gbm.vertices[edge.vertex_b]
		# Skip edges whose both endpoints are outside the camera frustum.
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


