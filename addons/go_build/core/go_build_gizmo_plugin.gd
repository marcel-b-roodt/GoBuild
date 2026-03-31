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
const _GIZMO_SCRIPT_PATH = "res://addons/go_build/core/go_build_gizmo.gd";
const _MESH_INSTANCE_SCRIPT_PATH = "res://addons/go_build/core/go_build_mesh_instance.gd";

const _GIZMO_SCRIPT         := preload(_GIZMO_SCRIPT_PATH)
const _FACE_SCRIPT          := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT          := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT          := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _SEL_MGR_SCRIPT       := preload("res://addons/go_build/core/selection_manager.gd")
const _MESH_INSTANCE_SCRIPT := preload(_MESH_INSTANCE_SCRIPT_PATH)

## Must match [constant GoBuildGizmo.AXIS_HANDLE_OFFSET].
const AXIS_HANDLE_OFFSET: int = 1_000_000
## Must match [constant GoBuildGizmo.ROT_HANDLE_OFFSET].
const ROT_HANDLE_OFFSET: int  = 2_000_000
## Must match [constant GoBuildGizmo.ARROW_LENGTH].
const ARROW_LENGTH: float = 0.8
## Must match [constant GoBuildGizmo.ROT_RING_RADIUS].
const ROT_RING_RADIUS: float = 1.05
## Must match [constant GoBuildGizmo.CONE_HEIGHT].
## Used by [method _is_click_on_transform_handle] in plugin.gd to compute
## the cone-base world position for line-segment hit testing.
const CONE_HEIGHT: float = 0.18

## Scale factor for perspective cameras.
## Calibrated so that the base sizes (ARROW_LENGTH = 0.8 etc.) look correct
## at roughly 5 units from the gizmo centroid with the default 75° FOV.
const GIZMO_SCREEN_FACTOR: float = 0.25
## Scale factor for orthographic cameras (fraction of camera.size).
const GIZMO_ORTHO_SCALE: float = 0.10

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
## Filled semi-transparent overlay for selected faces (Face mode).
var mat_face_fill:        StandardMaterial3D
## Axis shaft line materials.
var mat_axis_line_x:     StandardMaterial3D
var mat_axis_line_y:     StandardMaterial3D
var mat_axis_line_z:     StandardMaterial3D
## Axis tip handle (billboard dot) materials.
var mat_axis_x:          StandardMaterial3D
var mat_axis_y:          StandardMaterial3D
var mat_axis_z:          StandardMaterial3D
## Solid cone arrowhead materials — double-sided, unshaded, drawn on top.
var mat_cone_x:          StandardMaterial3D
var mat_cone_y:          StandardMaterial3D
var mat_cone_z:          StandardMaterial3D

var _editor_plugin: EditorPlugin = null

## Drag state (populated by begin_drag / _get_handle_value, cleared by commit_drag) ──
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
## Full mesh snapshot taken at the start of a drag — used for cancel / undo.
var _drag_restore: Dictionary = {}

func setup(plugin: EditorPlugin) -> void:
	_editor_plugin      = plugin
	# Unselected elements are drawn with no_depth_test so they are always visible
	# on top of the mesh surface.  Without this the vertex cubes and edge lines
	# are z-fighting with (or occluded by) the opaque mesh geometry — the vertex
	# positions are exactly ON the surface, so depth-testing makes them invisible.
	mat_edge_normal     = _line_mat_nodepth(COLOR_UNSELECTED)
	mat_edge_selected   = _line_mat_nodepth(COLOR_SELECTED)
	mat_edge_context    = _line_mat_nodepth(Color(0.4, 0.4, 0.4, 1.0))   # dimmer: context only
	mat_vertex_normal   = _line_mat_nodepth(COLOR_UNSELECTED)
	mat_vertex_selected = _line_mat_nodepth(COLOR_SELECTED)
	mat_face_normal     = _point_mat(COLOR_FACE_HINT)
	mat_face_selected   = _point_mat(COLOR_SELECTED)
	mat_face_fill       = _face_fill_mat()
	mat_axis_line_x     = _line_mat(COLOR_AXIS_X)
	mat_axis_line_y     = _line_mat(COLOR_AXIS_Y)
	mat_axis_line_z     = _line_mat(COLOR_AXIS_Z)
	mat_axis_x          = _point_mat(COLOR_AXIS_X)
	mat_axis_y          = _point_mat(COLOR_AXIS_Y)
	mat_axis_z          = _point_mat(COLOR_AXIS_Z)
	mat_cone_x          = _cone_mat(COLOR_AXIS_X)
	mat_cone_y          = _cone_mat(COLOR_AXIS_Y)
	mat_cone_z          = _cone_mat(COLOR_AXIS_Z)


func _get_name() -> String:
	return "GoBuildMeshInstance"


func _get_priority() -> int:
	return 1


func _has_gizmo(for_node_3d: Node3D) -> bool:
	# Path-based check: comparing resource_path strings is hot-reload-safe.
	# After a script reload the cached preload constant and the node's attached
	# script are logically the same file but different GDScript object instances,
	# so identity comparison (== or `is`) silently returns false.
	var s: Script = for_node_3d.get_script()
	var result: bool = s != null \
			and s.resource_path == _MESH_INSTANCE_SCRIPT_PATH
	# Always print — this fires during add_node_3d_gizmo_plugin and node
	# enter-tree; GoBuildDebug.enabled is typically false at those moments so
	# using GoBuildDebug.log() would silently skip the message.
	if s != null and "go_build" in s.resource_path.to_lower():
		print("[GoBuild] GIZMO_PLUGIN._has_gizmo  node=%s  script=%s  result=%s" \
				% [for_node_3d.name, s.resource_path, str(result)])
	elif "GoBuild" in for_node_3d.name:
		print("[GoBuild] GIZMO_PLUGIN._has_gizmo  node=%s  script_null=%s  result=%s" \
				% [for_node_3d.name, str(s == null), str(result)])
	return result


func _create_gizmo(for_node_3d: Node3D) -> EditorNode3DGizmo:
	var s: Script = for_node_3d.get_script()
	var is_match: bool = s != null \
			and s.resource_path == _MESH_INSTANCE_SCRIPT_PATH
	if not is_match:
		return null
	# Prevent a duplicate if a gizmo was already attached via the manual
	# Node3D.add_gizmo() path in plugin.gd — skip engine-side creation.
	if has_our_gizmo(for_node_3d):
		print("[GoBuild] GIZMO_PLUGIN._create_gizmo  node=%s  SKIP (manual gizmo already attached)" \
				% for_node_3d.name)
		return null
	print("[GoBuild] GIZMO_PLUGIN._create_gizmo  node=%s  CREATING" % for_node_3d.name)
	return _GIZMO_SCRIPT.new()


## Return [code]true[/code] if [param for_node_3d] already has a [GoBuildGizmo]
## in its gizmo list — used to prevent duplicate gizmos when the manual
## [method Node3D.add_gizmo] path and the engine-managed creation path race.
func has_our_gizmo(for_node_3d: Node3D) -> bool:
	for g: Node3DGizmo in for_node_3d.get_gizmos():
		var s: Script = g.get_script()
		if s != null and s.resource_path == _GIZMO_SCRIPT_PATH:
			return true
	return false


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

## Called every frame while the user drags a handle (native Godot pipeline).
##
## Guard: skips if [member _drag_initial_verts] is already populated — meaning
## our custom [method begin_drag] path (plugin.gd) owns the current drag and
## is already applying it.  Prevents two systems writing contradictory deltas.
## In practice this guard is never hit: we run in SELECT mode (KEY_Q) which
## suppresses the native drag pipeline entirely.
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
# Drag: commit or cancel (native Godot pipeline path)
# ---------------------------------------------------------------------------

## Called when the drag ends.  On cancel, restores the mesh to [param restore].
## On confirm, pushes a single undo/redo action.
##
## If [member _drag_initial_t] is still [constant @GDScript.INF] (meaning
## [method _set_handle] was never called — i.e. the user clicked but did not
## drag), no undo action is pushed and the mesh is left unchanged.
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
		node.update_gizmos()
	elif _drag_initial_t != INF:
		var snapshot_after: Dictionary = node.go_build_mesh.take_snapshot()
		var ur: EditorUndoRedoManager = _editor_plugin.get_undo_redo()
		var action_name: String = \
				"Rotate Elements" if handle_id >= ROT_HANDLE_OFFSET else "Move Elements"
		ur.create_action(action_name)
		ur.add_do_method(node, "restore_and_bake", snapshot_after)
		ur.add_undo_method(node, "restore_and_bake", restore as Dictionary)
		ur.commit_action()

	reset_drag_state()


## Clear all in-progress drag state.
## Called on mode change, focus loss, and node removal to ensure a stale drag
## does not corrupt subsequent operations.
func reset_drag_state() -> void:
	_drag_initial_t = INF
	_drag_initial_verts.clear()
	_drag_start_dir  = Vector3.ZERO
	_drag_world_axis = Vector3.ZERO
	_drag_restore    = {}


# ---------------------------------------------------------------------------
# Public drag API — used by plugin.gd (custom drag path for SELECT mode)
# ---------------------------------------------------------------------------
## Godot's native _set_handle pipeline only fires in Move mode (KEY_W).
## We keep the editor in Select mode (KEY_Q) to suppress the node-level
## transform widget, so plugin.gd drives all handle drags through this API.

## Initialise a handle drag for [param handle_id] on [param node].
## Caches initial vertex positions and a full mesh snapshot for undo/cancel.
## Returns [code]true[/code] if the drag was successfully started.
func begin_drag(node: GoBuildMeshInstance, handle_id: int) -> bool:
	if handle_id < AXIS_HANDLE_OFFSET:
		return false
	if node == null or node.go_build_mesh == null:
		return false
	var affected: Array[int] = _get_affected_vertex_indices(node)
	if affected.is_empty():
		return false

	_drag_initial_verts.clear()
	_drag_initial_t   = INF
	_drag_start_dir   = Vector3.ZERO
	_drag_world_axis  = Vector3.ZERO
	for idx: int in affected:
		_drag_initial_verts[idx] = node.go_build_mesh.vertices[idx]

	if handle_id >= ROT_HANDLE_OFFSET:
		var local_axis: Vector3 = _get_local_axis(handle_id - ROT_HANDLE_OFFSET)
		_drag_world_axis = (node.global_transform.basis * local_axis).normalized()

	_drag_restore = node.go_build_mesh.take_snapshot()
	return true


## Apply the in-progress drag to [param node] given the current [param camera]
## and mouse [param screen_pos].  Rebuilds the mesh and gizmo overlay immediately.
func update_drag(
		node: GoBuildMeshInstance,
		handle_id: int,
		camera: Camera3D,
		screen_pos: Vector2,
) -> void:
	if handle_id < AXIS_HANDLE_OFFSET or _drag_initial_verts.is_empty():
		return
	if node == null:
		return
	if handle_id >= ROT_HANDLE_OFFSET:
		_apply_rotate_drag(node, handle_id - ROT_HANDLE_OFFSET, camera, screen_pos)
	else:
		_apply_translate_drag(node, handle_id - AXIS_HANDLE_OFFSET, camera, screen_pos)


## Finalise or cancel the current drag on [param node].
## On [param cancel], restores the mesh to the snapshot taken in [method begin_drag].
## On confirm, pushes a single undo/redo action.
func commit_drag(node: GoBuildMeshInstance, handle_id: int, cancel: bool) -> void:
	if handle_id < AXIS_HANDLE_OFFSET or node == null:
		return

	if cancel:
		node.restore_and_bake(_drag_restore)
		node.update_gizmos()
	elif _drag_initial_t != INF:
		var snapshot_after: Dictionary = node.go_build_mesh.take_snapshot()
		var ur: EditorUndoRedoManager = _editor_plugin.get_undo_redo()
		var action_name: String = \
				"Rotate Elements" if handle_id >= ROT_HANDLE_OFFSET else "Move Elements"
		ur.create_action(action_name)
		ur.add_do_method(node, "restore_and_bake", snapshot_after)
		ur.add_undo_method(node, "restore_and_bake", _drag_restore)
		ur.commit_action()

	reset_drag_state()


# ---------------------------------------------------------------------------
# Handle position query — used by plugin.gd for click hit-testing
# ---------------------------------------------------------------------------

## Return the world-space positions of the six transform handles (3 translate
## tips + 3 rotate-ring dots) for the current selection on [param node].
##
## Returns an empty array when the mode is OBJECT, the selection is empty, or
## no mesh is present.  Positions are scaled for constant screen size.
func get_transform_handle_world_positions(node: GoBuildMeshInstance) -> Array[Vector3]:
	var sel: SelectionManager = node.selection
	if sel.get_mode() == SelectionManager.Mode.OBJECT or sel.is_empty():
		return []
	var gbm: GoBuildMesh = node.go_build_mesh
	if gbm == null:
		return []

	# Compute local-space centroid (mirrors GoBuildGizmo._compute_selection_centroid).
	var sum := Vector3.ZERO
	var count := 0
	match sel.get_mode():
		SelectionManager.Mode.VERTEX:
			for idx: int in sel.get_selected_vertices():
				sum += gbm.vertices[idx]
				count += 1
		SelectionManager.Mode.EDGE:
			for eidx: int in sel.get_selected_edges():
				var edge: GoBuildEdge = gbm.edges[eidx]
				sum += gbm.vertices[edge.vertex_a]
				sum += gbm.vertices[edge.vertex_b]
				count += 2
		SelectionManager.Mode.FACE:
			for fidx: int in sel.get_selected_faces():
				for vidx: int in gbm.faces[fidx].vertex_indices:
					sum += gbm.vertices[vidx]
					count += 1
	if count == 0:
		return []

	var lc: Vector3 = sum / count
	var gt: Transform3D = node.global_transform
	var s: float = compute_world_gizmo_scale(gt * lc)
	var arr: float = ARROW_LENGTH * s
	var ring: float = ROT_RING_RADIUS * s

	var result: Array[Vector3] = [
		gt * (lc + Vector3(arr,  0.0,  0.0)),          # translate X tip
		gt * (lc + Vector3(0.0,  arr,  0.0)),          # translate Y tip
		gt * (lc + Vector3(0.0,  0.0,  arr)),          # translate Z tip
		gt * (lc + Vector3.UP    * ring),               # rotate X ring dot
		gt * (lc + Vector3.BACK  * ring),               # rotate Y ring dot
		gt * (lc + Vector3.RIGHT * ring),               # rotate Z ring dot
	]
	return result


# ---------------------------------------------------------------------------
# Camera / scale helpers
# ---------------------------------------------------------------------------

## Return the [Camera3D] for the primary 3D editor viewport.
## Returns [code]null[/code] during plugin load or if the viewport is unavailable.
func get_editor_camera() -> Camera3D:
	var vp: SubViewport = EditorInterface.get_editor_viewport_3d(0)
	if vp == null:
		return null
	return vp.get_camera_3d()


## Return a uniform scale so gizmo elements at their base sizes appear at a
## roughly constant screen size independent of camera distance.
##
## [param world_centroid] is the world-space point to measure distance from.
func compute_world_gizmo_scale(world_centroid: Vector3) -> float:
	var cam: Camera3D = get_editor_camera()
	if cam == null:
		return 1.0
	var dist: float = cam.global_position.distance_to(world_centroid)
	if cam.projection == Camera3D.PROJECTION_PERSPECTIVE:
		return maxf(dist * tan(deg_to_rad(cam.fov * 0.5)) * GIZMO_SCREEN_FACTOR, 0.01)
	return maxf(cam.size * GIZMO_ORTHO_SCALE, 0.01)


## Convenience wrapper: compute gizmo scale using the node's global position
## as the world-centroid approximation (avoids recomputing the selection centroid).
func compute_node_gizmo_scale(node: GoBuildMeshInstance) -> float:
	return compute_world_gizmo_scale(node.global_position)



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
	node.update_gizmos()  # keep element overlay in sync with moved vertices


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
	node.update_gizmos()  # keep element overlay in sync with rotated vertices


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


## Collect unique vertex indices affected by the current selection on [param node],
## then expand each to include all coincident partners from
## [member GoBuildMesh.coincident_groups].
##
## Generators like [CubeGenerator] create split (per-face) vertex grids, so a
## single logical corner may be represented by several vertex indices at the same
## 3D position.  Without the expansion, dragging vertex 0 of a cube would leave
## the copies on adjacent faces behind.
func _get_affected_vertex_indices(node: GoBuildMeshInstance) -> Array[int]:
	var sel: SelectionManager = node.selection
	var gbm: GoBuildMesh = node.go_build_mesh
	if gbm == null:
		return []

	# ── Step 1: collect directly selected / implied vertex indices ──────────
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

	# ── Step 2: expand to coincident partners ───────────────────────────────
	# coincident_groups is parallel to vertices (same size) when built.
	# Skip expansion when the map hasn't been built yet (e.g. manually
	# constructed test meshes that never called rebuild_edges).
	if gbm.coincident_groups.size() == gbm.vertices.size():
		# Build a set of the group IDs we need to include.
		var groups_needed: Dictionary = {}
		for idx: int in result:
			groups_needed[gbm.coincident_groups[idx]] = true

		# Build a fast-lookup set of what's already in result.
		var already_included: Dictionary = {}
		for idx: int in result:
			already_included[idx] = true

		# Add every vertex whose group is in groups_needed but isn't yet included.
		for idx: int in gbm.vertices.size():
			if gbm.coincident_groups[idx] in groups_needed and not already_included.has(idx):
				result.append(idx)
				already_included[idx] = true

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


## Create an unshaded line material that ignores depth — always drawn on top.
## Used for selected-element highlights so they are never hidden by geometry.
func _line_mat_nodepth(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color    = color
	mat.no_depth_test   = true
	mat.render_priority = 3
	return mat


## Create a semi-transparent filled surface material for face selection overlays.
## Uses the same hue as [constant COLOR_SELECTED] at 30 % opacity, rendered
## double-sided and always on top of geometry.
func _face_fill_mat() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color    = Color(COLOR_SELECTED.r, COLOR_SELECTED.g, COLOR_SELECTED.b, 0.3)
	mat.transparency    = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode       = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test   = true
	mat.render_priority = 2
	return mat


## Create an unshaded solid-cone material.
## Double-sided (CULL_DISABLED) so the cone is visible regardless of viewing angle.
## Drawn on top of geometry (no_depth_test) at the same priority as handle dots.
func _cone_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color    = color
	mat.cull_mode       = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test   = true
	mat.render_priority = 2
	return mat
