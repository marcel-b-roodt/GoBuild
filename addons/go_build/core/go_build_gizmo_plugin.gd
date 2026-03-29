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
var _drag_initial_t: float = INF


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
	match handle_id - AXIS_HANDLE_OFFSET:
		0: return "Move X"
		1: return "Move Y"
		2: return "Move Z"
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

	# Cache per-vertex initial positions so _set_handle can restore + re-translate.
	_drag_initial_verts.clear()
	_drag_initial_t = INF
	var affected := _get_affected_vertex_indices(node)
	for idx: int in affected:
		_drag_initial_verts[idx] = node.go_build_mesh.vertices[idx]

	# Return a full snapshot for undo/cancel.
	return node.go_build_mesh.take_snapshot()


# ---------------------------------------------------------------------------
# Drag: live update
# ---------------------------------------------------------------------------

## Called every frame while the user drags an axis handle.
## Projects the mouse onto the constrained axis and applies a live translation.
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

	var axis_idx: int = handle_id - AXIS_HANDLE_OFFSET
	var local_axis: Vector3 = _get_local_axis(axis_idx)
	var gbm: GoBuildMesh = node.go_build_mesh

	# Compute initial centroid from stored positions.
	var local_centroid := Vector3.ZERO
	for idx: int in _drag_initial_verts:
		local_centroid += _drag_initial_verts[idx]
	local_centroid /= _drag_initial_verts.size()

	var world_centroid: Vector3 = node.global_transform * local_centroid
	var world_axis: Vector3    = (node.global_transform.basis * local_axis).normalized()

	var t_now: float = _project_to_axis(camera, screen_pos, world_centroid, world_axis)

	# Initialise the "zero" on the first call of this drag.
	if _drag_initial_t == INF:
		_drag_initial_t = t_now

	var delta_world: Vector3 = world_axis * (t_now - _drag_initial_t)
	var delta_local: Vector3 = node.global_transform.basis.inverse() * delta_world

	# Restore initial positions then apply the new delta.
	for idx: int in _drag_initial_verts:
		gbm.vertices[idx] = _drag_initial_verts[idx] + delta_local

	node.bake()


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
		ur.create_action("Move Elements")
		ur.add_do_method(node, "restore_and_bake", snapshot_after)
		ur.add_undo_method(node, "restore_and_bake", restore as Dictionary)
		ur.commit_action()

	_drag_initial_t = INF
	_drag_initial_verts.clear()


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
