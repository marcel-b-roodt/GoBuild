## Gizmo plugin — creates [GoBuildGizmo] instances and owns shared materials.
##
## Register with [method EditorPlugin.add_node_3d_gizmo_plugin] in [code]plugin.gd[/code].
## Materials are created once in [method setup] and reused by every gizmo instance.
@tool
class_name GoBuildGizmoPlugin
extends EditorNode3DGizmoPlugin

# Self-preloads (dependency order):
# go_build_gizmo.gd transitively loads the mesh types; explicit preloads here
# make this file self-sufficient per the self-preload rule.
const _GIZMO_SCRIPT         := preload("res://addons/go_build/core/go_build_gizmo.gd")
const _FACE_SCRIPT          := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT          := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT          := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _SEL_MGR_SCRIPT       := preload("res://addons/go_build/core/selection_manager.gd")
const _MESH_INSTANCE_SCRIPT := preload("res://addons/go_build/core/go_build_mesh_instance.gd")

## Must match [constant GoBuildGizmo.AXIS_HANDLE_OFFSET].
const AXIS_HANDLE_OFFSET: int = 1_000_000
## Must match [constant GoBuildGizmo.ROT_HANDLE_OFFSET].
const ROT_HANDLE_OFFSET: int  = 2_000_000

# ── Colour palette ────────────────────────────────────────────────────────
const COLOR_UNSELECTED  := Color(0.85, 0.85, 0.85, 1.0)
const COLOR_SELECTED    := Color(1.0,  0.55, 0.0,  1.0)
const COLOR_FACE_HINT   := Color(0.4,  0.8,  1.0,  1.0)
const COLOR_CONTEXT     := Color(0.55, 0.55, 0.55, 0.5)
const COLOR_AXIS_X      := Color(1.0,  0.2,  0.2,  1.0)   ## Red — X axis.
const COLOR_AXIS_Y      := Color(0.2,  0.9,  0.2,  1.0)   ## Green — Y axis.
const COLOR_AXIS_Z      := Color(0.2,  0.4,  1.0,  1.0)   ## Blue — Z axis.

# ── Shared materials ──────────────────────────────────────────────────────
var mat_edge_normal:     StandardMaterial3D
var mat_edge_selected:   StandardMaterial3D
var mat_edge_context:    StandardMaterial3D
var mat_vertex_normal:   StandardMaterial3D
var mat_vertex_selected: StandardMaterial3D
var mat_face_normal:     StandardMaterial3D
var mat_face_selected:   StandardMaterial3D
## Axis shaft line materials.
var mat_axis_line_x:     StandardMaterial3D
var mat_axis_line_y:     StandardMaterial3D
var mat_axis_line_z:     StandardMaterial3D
## Axis tip handle (billboard dot) materials.
var mat_axis_x:          StandardMaterial3D
var mat_axis_y:          StandardMaterial3D
var mat_axis_z:          StandardMaterial3D

var _editor_plugin: EditorPlugin = null

# ── Drag state (populated by _get_handle_value, cleared by _commit_handle) ──
## Vertex index → original position before the current drag started.
var _drag_initial_verts: Dictionary = {}
## Axis-line parameter at the moment the drag began (set on first _set_handle call).
## Also used as an "uninitialised" sentinel (value == INF).
var _drag_initial_t: float = INF
## World-space direction from the selection centroid to the first rotate-plane
## hit point. Initialised on the first [_set_handle] call of a rotate drag.
var _drag_start_dir: Vector3 = Vector3.ZERO
## World-space rotation axis captured in [_get_handle_value] for rotate drags.
var _drag_world_axis: Vector3 = Vector3.ZERO

func setup(plugin: EditorPlugin) -> void:
	_editor_plugin      = plugin
	mat_edge_normal     = _line_mat(COLOR_UNSELECTED)
	mat_edge_selected   = _line_mat(COLOR_SELECTED)
	mat_edge_context    = _line_mat(COLOR_CONTEXT)
	mat_vertex_normal   = _point_mat(COLOR_UNSELECTED)
	mat_vertex_selected = _point_mat(COLOR_SELECTED)
	mat_face_normal     = _point_mat(COLOR_FACE_HINT)
	mat_face_selected   = _point_mat(COLOR_SELECTED)
	mat_axis_line_x     = _line_mat(COLOR_AXIS_X)
	mat_axis_line_y     = _line_mat(COLOR_AXIS_Y)
	mat_axis_line_z     = _line_mat(COLOR_AXIS_Z)
	mat_axis_x          = _point_mat(COLOR_AXIS_X)
	mat_axis_y          = _point_mat(COLOR_AXIS_Y)
	mat_axis_z          = _point_mat(COLOR_AXIS_Z)


func _get_name() -> String:
	return "GoBuildMeshInstance"


func _get_priority() -> int:
	return 1


func _has_gizmo(for_node_3d: Node3D) -> bool:
	return for_node_3d is GoBuildMeshInstance


func _create_gizmo(for_node_3d: Node3D) -> EditorNode3DGizmo:
	if not for_node_3d is GoBuildMeshInstance:
		return null
	return _GIZMO_SCRIPT.new()


func request_redraw() -> void:
	if _editor_plugin:
		_editor_plugin.update_overlays()


# ---------------------------------------------------------------------------
# Axis handle name (shown in the Godot handle tooltip)
# ---------------------------------------------------------------------------

func _get_handle_name(
		_gizmo: EditorNode3DGizmo,
		handle_id: int,
		_secondary: bool,
) -> String:
	const MOVE_NAMES = ["Move X",   "Move Y",   "Move Z"]
	const ROT_NAMES  = ["Rotate X", "Rotate Y", "Rotate Z"]
	if handle_id >= ROT_HANDLE_OFFSET:
		var rot_idx: int = handle_id - ROT_HANDLE_OFFSET
		return ROT_NAMES[rot_idx] if rot_idx < 3 else ""
	var move_idx: int = handle_id - AXIS_HANDLE_OFFSET
	if move_idx >= 0 and move_idx < 3:
		return MOVE_NAMES[move_idx]
	return ""


# ---------------------------------------------------------------------------
# Drag: capture initial state
# ---------------------------------------------------------------------------

## Called by the editor at the start of a handle drag.
## Returns a full mesh snapshot used as the undo/cancel restore value.
func _get_handle_value(
		gizmo: EditorNode3DGizmo,
		handle_id: int,
		_secondary: bool,
) -> Variant:
	if handle_id < AXIS_HANDLE_OFFSET:
		return null
	var node := gizmo.get_node_3d() as GoBuildMeshInstance
	if node == null or node.go_build_mesh == null:
		return null

	# Cache per-vertex initial positions so _set_handle can restore + re-apply.
	_drag_initial_verts.clear()
	_drag_initial_t = INF
	_drag_start_dir = Vector3.ZERO
	var affected := _get_affected_vertex_indices(node)
	for idx: int in affected:
		_drag_initial_verts[idx] = node.go_build_mesh.vertices[idx]

	# For rotate drags, pre-compute the world axis so _set_handle can use it.
	if handle_id >= ROT_HANDLE_OFFSET:
		var local_axis: Vector3 = _get_local_axis(handle_id - ROT_HANDLE_OFFSET)
		_drag_world_axis = (node.global_transform.basis * local_axis).normalized()

	# Return a full snapshot for undo/cancel.
	return node.go_build_mesh.take_snapshot()


# ---------------------------------------------------------------------------
# Drag: live update
# ---------------------------------------------------------------------------

## Called every frame while the user drags a handle.
## Dispatches to translate or rotate sub-logic based on [param handle_id].
func _set_handle(
		gizmo: EditorNode3DGizmo,
		handle_id: int,
		_secondary: bool,
		camera: Camera3D,
		screen_pos: Vector2,
) -> void:
	if handle_id < AXIS_HANDLE_OFFSET or _drag_initial_verts.is_empty():
		return
	var node := gizmo.get_node_3d() as GoBuildMeshInstance
	if node == null:
		return

	if handle_id >= ROT_HANDLE_OFFSET:
		_apply_rotate_drag(node, handle_id - ROT_HANDLE_OFFSET, camera, screen_pos)
	else:
		_apply_translate_drag(node, handle_id - AXIS_HANDLE_OFFSET, camera, screen_pos)


# ---------------------------------------------------------------------------
# Drag: commit or cancel
# ---------------------------------------------------------------------------

## Called when the drag ends.  On cancel, restores the mesh to [param restore].
## On confirm, pushes a single undo/redo action.
func _commit_handle(
		gizmo: EditorNode3DGizmo,
		handle_id: int,
		_secondary: bool,
		restore: Variant,
		cancel: bool,
) -> void:
	if handle_id < AXIS_HANDLE_OFFSET:
		return
	var node := gizmo.get_node_3d() as GoBuildMeshInstance
	if node == null:
		return

	if cancel:
		node.restore_and_bake(restore as Dictionary)
	else:
		var snapshot_after: Dictionary = node.go_build_mesh.take_snapshot()
		var ur: EditorUndoRedoManager = _editor_plugin.get_undo_redo()
		var action_name: String = \
				"Rotate Elements" if handle_id >= ROT_HANDLE_OFFSET else "Move Elements"
		ur.create_action(action_name)
		ur.add_do_method(node, "restore_and_bake", snapshot_after)
		ur.add_undo_method(node, "restore_and_bake", restore as Dictionary)
		ur.commit_action()

	_drag_initial_t = INF
	_drag_initial_verts.clear()
	_drag_start_dir  = Vector3.ZERO
	_drag_world_axis = Vector3.ZERO


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Return the local-space unit vector for axis index 0=X, 1=Y, 2=Z.
func _get_local_axis(axis_idx: int) -> Vector3:
	match axis_idx:
		0: return Vector3.RIGHT
		1: return Vector3.UP
		2: return Vector3.BACK
	return Vector3.ZERO


## Apply a translate drag along axis [param axis_idx] to all cached vertices.
func _apply_translate_drag(
		node: GoBuildMeshInstance,
		axis_idx: int,
		camera: Camera3D,
		screen_pos: Vector2,
) -> void:
	var local_axis: Vector3  = _get_local_axis(axis_idx)
	var gbm: GoBuildMesh     = node.go_build_mesh
	var local_centroid: Vector3 = _compute_drag_centroid()
	var world_centroid: Vector3 = node.global_transform * local_centroid
	var world_axis: Vector3  = (node.global_transform.basis * local_axis).normalized()

	var t_now: float = _project_to_axis(camera, screen_pos, world_centroid, world_axis)

	if _drag_initial_t == INF:
		_drag_initial_t = t_now

	var delta_world: Vector3 = world_axis * (t_now - _drag_initial_t)
	var delta_local: Vector3 = node.global_transform.basis.inverse() * delta_world

	for idx: int in _drag_initial_verts:
		gbm.vertices[idx] = _drag_initial_verts[idx] + delta_local

	node.bake()


## Apply a rotate drag around axis [param axis_idx] to all cached vertices.
## Uses [method Vector3.signed_angle_to] to compute the delta angle each frame.
func _apply_rotate_drag(
		node: GoBuildMeshInstance,
		axis_idx: int,
		camera: Camera3D,
		screen_pos: Vector2,
) -> void:
	var local_axis: Vector3  = _get_local_axis(axis_idx)
	var gbm: GoBuildMesh     = node.go_build_mesh
	var local_centroid: Vector3 = _compute_drag_centroid()
	var world_centroid: Vector3 = node.global_transform * local_centroid

	# Project mouse ray onto the plane perpendicular to the rotation axis.
	var hit: Vector3 = _project_to_rotation_plane(
			camera, screen_pos, world_centroid, _drag_world_axis)
	if hit == Vector3.INF:
		return

	var dir: Vector3 = hit - world_centroid
	if dir.length_squared() < 1e-7:
		return
	dir = dir.normalized()

	# Initialise the reference direction on the first frame.
	if _drag_initial_t == INF:
		_drag_start_dir = dir
		_drag_initial_t = 0.0
		return

	# delta_angle is signed: positive = CCW around the world axis.
	var delta_angle: float = _drag_start_dir.signed_angle_to(dir, _drag_world_axis)

	for idx: int in _drag_initial_verts:
		var local_pos: Vector3 = _drag_initial_verts[idx] - local_centroid
		gbm.vertices[idx] = local_centroid + local_pos.rotated(local_axis, delta_angle)

	node.bake()


## Return the arithmetic mean of the cached initial vertex positions.
func _compute_drag_centroid() -> Vector3:
	var c := Vector3.ZERO
	for idx: int in _drag_initial_verts:
		c += _drag_initial_verts[idx]
	return c / _drag_initial_verts.size()


## Project [param screen_pos] onto the world-space line through
## [param axis_origin] along [param axis_dir] and return the parametric t.
## Uses the line-to-line closest-approach formula.
func _project_to_axis(
		camera: Camera3D,
		screen_pos: Vector2,
		axis_origin: Vector3,
		axis_dir: Vector3,
) -> float:
	var cam_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var cam_dir: Vector3   = camera.project_ray_normal(screen_pos)
	var r: Vector3 = axis_origin - cam_origin
	var b: float   = axis_dir.dot(cam_dir)
	var c: float   = axis_dir.dot(r)
	var f: float   = cam_dir.dot(r)
	var denom: float = 1.0 - b * b
	if abs(denom) < 1e-7:
		return 0.0  # Axis and camera ray are nearly parallel.
	return (b * f - c) / denom


## Project [param screen_pos] onto the plane defined by [param plane_origin]
## and [param plane_normal].  Returns [code]Vector3.INF[/code] if the camera
## ray is parallel to the plane or hits from behind.
func _project_to_rotation_plane(
		camera: Camera3D,
		screen_pos: Vector2,
		plane_origin: Vector3,
		plane_normal: Vector3,
) -> Vector3:
	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3    = camera.project_ray_normal(screen_pos)
	return _ray_plane_intersect(ray_origin, ray_dir, plane_origin, plane_normal)


## Pure-math ray-plane intersection (no camera dependency).
## Returns [code]Vector3.INF[/code] when the ray is parallel to the plane or
## the intersection is behind [param ray_origin].
## Public so it can be unit-tested directly.
static func _ray_plane_intersect(
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


## Collect unique vertex indices affected by the current selection on [param node].
func _get_affected_vertex_indices(node: GoBuildMeshInstance) -> Array[int]:
	var sel: SelectionManager = node.selection
	var gbm: GoBuildMesh = node.go_build_mesh
	if gbm == null:
		return []
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
	return result


## Create an unshaded line material.
func _line_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color    = color
	mat.render_priority = 1
	return mat


## Create an unshaded billboard point material rendered on top of geometry.
func _point_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color    = color
	mat.no_depth_test   = true
	mat.render_priority = 2
	return mat
