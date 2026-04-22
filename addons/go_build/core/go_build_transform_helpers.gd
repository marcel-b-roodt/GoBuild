## Shared pure helpers for drag/gizmo math and selection expansion.
##
## This class intentionally extends RefCounted (not editor-only types) so
## static helpers are safe to call in headless tests and CI script-scan passes.
@tool
class_name GoBuildTransformHelpers
extends RefCounted

# Self-preloads (dependency order).
const _MESH_INSTANCE_SCRIPT := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _MESH_SCRIPT          := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _EDGE_SCRIPT          := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _SEL_MGR_SCRIPT       := preload("res://addons/go_build/core/selection_manager.gd")


## Return the grid-snap step from EditorSettings ([code]editors/3d/grid_step[/code]).
##
## If [param snap_step_override] is positive, it is returned directly.
## Falls back to [code]1.0[/code] if the key is absent or the editor is not
## running (headless / tests).
static func get_snap_step(snap_step_override: float = -1.0) -> float:
	if snap_step_override > 0.0:
		return snap_step_override
	if not Engine.is_editor_hint():
		return 1.0
	var es: EditorSettings = EditorInterface.get_editor_settings()
	if es.has_setting("editors/3d/grid_step"):
		return maxf(float(es.get_setting("editors/3d/grid_step")), 0.001)
	return 1.0


## Return the local-space unit vector for axis index 0=X, 1=Y, 2=Z.
static func get_local_axis(axis_idx: int) -> Vector3:
	match axis_idx:
		0: return Vector3.RIGHT
		1: return Vector3.UP
		2: return Vector3.BACK
	return Vector3.ZERO


## Pure-math ray-plane intersection (no camera dependency).
## Returns [code]Vector3.INF[/code] when the ray is parallel to the plane or
## the intersection is behind [param ray_origin].
static func ray_plane_intersect(
		ray_origin: Vector3,
		ray_dir: Vector3,
		plane_origin: Vector3,
		plane_normal: Vector3,
) -> Vector3:
	var denom: float = plane_normal.dot(ray_dir)
	if abs(denom) < 1e-7:
		return Vector3.INF   # Ray is parallel to the plane.
	var t: float = plane_normal.dot(plane_origin - ray_origin) / denom
	if t < 0.0:
		return Vector3.INF   # Intersection is behind the camera.
	return ray_origin + ray_dir * t


## Collect unique vertex indices affected by the current selection on [param node],
## then expand each to include all coincident partners from
## [member GoBuildMesh.coincident_groups].
static func get_affected_vertex_indices(node: GoBuildMeshInstance) -> Array[int]:
	var sel: SelectionManager = node.selection
	var gbm: GoBuildMesh = node.go_build_mesh
	if gbm == null:
		return []

	# Step 1: collect directly selected / implied vertex indices.
	var result: Array[int] = []
	match sel.get_mode():
		SelectionManager.Mode.VERTEX:
			result.assign(sel.get_selected_vertices())
		SelectionManager.Mode.EDGE:
			for eidx: int in sel.get_selected_edges():
				var edge: GoBuildEdge = gbm.edges[eidx]
				if not result.has(edge.vertex_a):
					result.append(edge.vertex_a)
				if not result.has(edge.vertex_b):
					result.append(edge.vertex_b)
		SelectionManager.Mode.FACE:
			for fidx: int in sel.get_selected_faces():
				for vidx: int in gbm.faces[fidx].vertex_indices:
					if not result.has(vidx):
						result.append(vidx)

	# Step 2: expand to coincident partners.
	if gbm.coincident_groups.size() == gbm.vertices.size():
		var groups_needed: Dictionary = {}
		for idx: int in result:
			groups_needed[gbm.coincident_groups[idx]] = true

		var already_included: Dictionary = {}
		for idx: int in result:
			already_included[idx] = true

		for idx: int in gbm.vertices.size():
			if gbm.coincident_groups[idx] in groups_needed and not already_included.has(idx):
				result.append(idx)
				already_included[idx] = true

	return result