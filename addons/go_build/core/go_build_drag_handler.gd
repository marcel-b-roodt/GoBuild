## Drag handler for [GoBuildGizmoPlugin].
##
## Owns all per-drag state ([member _drag_initial_verts], [member _drag_restore],
## etc.), the deferred-bake / deferred-gizmo-redraw queues, all
## [code]_apply_*_drag[/code] methods, and the geometry helpers that drive them.
##
## Extracted from [GoBuildGizmoPlugin] to keep that class under ~900 lines and
## to cleanly separate "draw / pick / Godot API overrides" (plugin) from
## "drag math / state" (this handler).
##
## [GoBuildGizmoPlugin] instantiates one handler at class-level and exposes thin
## wrapper methods ([method GoBuildGizmoPlugin.begin_drag],
## [method GoBuildGizmoPlugin.update_drag], [method GoBuildGizmoPlugin.commit_drag])
## that delegate here.
@tool
class_name GoBuildDragHandler
extends RefCounted

# Self-preloads (dependency order).
const _FACE_SCRIPT          := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MESH_INSTANCE_SCRIPT := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _MESH_SCRIPT          := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _EDGE_SCRIPT          := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _SEL_MGR_SCRIPT       := preload("res://addons/go_build/core/selection_manager.gd")
const _DRAG_OP_SCRIPT       := preload("res://addons/go_build/core/go_build_drag_operation.gd")

## Handle-ID range constants — must stay in sync with [GoBuildGizmoPlugin] and
## [GoBuildGizmo].  Duplicated here so the handler is self-contained.
const AXIS_HANDLE_OFFSET:      int = 1_000_000
const ROT_HANDLE_OFFSET:       int = 2_000_000
const SCALE_HANDLE_OFFSET:     int = 3_000_000
const PLANE_HANDLE_OFFSET:     int = 4_000_000
const VIEW_PLANE_HANDLE_ID:    int = 5_000_000
const UNIFORM_SCALE_HANDLE_ID: int = 6_000_000

## Precision multiplier applied when Shift is held during a drag.
const PRECISION_MULTIPLIER: float = 0.1

# ── Snap overrides ───────────────────────────────────────────────────────────
## Ctrl-snap step override; -1.0 = use editor grid step.
## Written by [code]plugin.gd[/code] via the passthrough property on
## [GoBuildGizmoPlugin].
var snap_step_override: float = -1.0
## Ctrl-snap step for rotation in degrees.  Default 15°.
var rot_snap_override: float = 15.0
## Ctrl-snap step for scale ratio.  Default 0.1 (snaps to 0.1, 0.2, 0.3 …).
var scale_snap_override: float = 0.1
## True when Shift is held during a drag (precision mode).
var precision_active: bool = false

# ── Drag state ──────────────────────────────────────────────────────────────
## Vertex index → original position before the current drag started.
var _drag_initial_verts: Dictionary = {}
## Axis-line parameter at the moment the drag began.
## Also used as an "uninitialised" sentinel (value == INF).
var _drag_initial_t: float = INF
## World-space direction from the selection centroid to the first rotate-plane
## hit point.  Initialised on the first update call of a rotate drag.
## Reused by plane and inset drags to store the initial world-space hit position
## or initial screen position respectively.
var _drag_start_dir: Vector3 = Vector3.ZERO
## World-space rotation axis for rotate drags.
var _drag_world_axis: Vector3 = Vector3.ZERO
## Full mesh snapshot taken at the start of a drag — used for cancel / undo.
## Set by both [method init_drag_capture] (native Godot path) and
## [method begin_drag] (custom path) so [method commit_drag] always has a
## valid restore target regardless of which path started the drag.
var _drag_restore: Dictionary = {}
## Optional action-name override.  When non-empty, [method commit_drag] uses
## this string instead of [method _drag_action_name].  Cleared by
## [method reset_drag_state].
var _drag_action_name_override: String = ""
## When true, [method update_drag] routes to [method _apply_inset_drag]
## regardless of handle_id.  Set by [method begin_inset_drag].
## When true, [method _apply_inset_drag] routes to inner-ring blending.
## Set by [method begin_inset_drag]; cleared by [method reset_drag_state].
var _inset_mode: bool = false
## Maps inner-ring vertex index → local-space face centroid.
## Populated by [method begin_inset_drag]; cleared by [method reset_drag_state].
var _inset_centroids: Dictionary = {}
## Accumulated inset amount from before the last precision toggle.
## When Shift state changes during an inset drag, the current amount is captured
## here so the offset-based computation restarts from zero relative to the new
## anchor, preserving the full 0→1 inset range from the original vertex positions.
var _inset_amount_offset: float = 0.0
## When true, [method _flush_pending_bake] routes to
## [method GoBuildMeshInstance.bake_vertex_positions] instead of
## [method GoBuildMeshInstance.bake].  Set by [method begin_drag]; cleared by
## [method reset_drag_state] so the commit/cancel full-bake is never skipped.
var _drag_vertex_update_mode: bool = false
## When true, live drag updates are rendered via [method GoBuildMeshInstance.bake_preview]
## instead of [method GoBuildMeshInstance.bake] so mesh resource assignment is
## avoided while the drag is in progress.
var _drag_preview_mode: bool = false
## Cumulative delta values for overlay readout.
var _drag_cumulative_translate: Vector3 = Vector3.ZERO
var _drag_cumulative_angle: float = 0.0
var _drag_cumulative_scale: float = 1.0
var _drag_current_handle_id: int = -1
## Previous Shift state during a drag.  When Shift changes during a drag,
## [method _reanchor_if_precision_changed] snapshots the current vertex
## positions into [member _drag_initial_verts] and resets [member _drag_initial_t]
## so that precision toggle is seamless — no position jump, only sensitivity changes.
var _prev_precision_active: bool = false

# ── Deferred-bake state ─────────────────────────────────────────────────────
var _bake_pending_node: GoBuildMeshInstance = null
var _bake_scheduled:    bool = false

# ── Deferred-gizmo-redraw state ─────────────────────────────────────────────
var _gizmo_redraw_pending_node: GoBuildMeshInstance = null
var _gizmo_redraw_scheduled:    bool = false


# ---------------------------------------------------------------------------
# Native-path helper — called by GoBuildGizmoPlugin._get_handle_value
# ---------------------------------------------------------------------------

## Capture initial vertex positions and mesh snapshot for the native Godot drag
## pipeline.  Called by [method GoBuildGizmoPlugin._get_handle_value].
##
## Stores the snapshot in [member _drag_restore] so [method commit_drag] can use
## it regardless of which pipeline (native or custom) started the drag.
func init_drag_capture(node: GoBuildMeshInstance, handle_id: int) -> void:
	_drag_initial_verts.clear()
	_drag_initial_t  = INF
	_drag_start_dir  = Vector3.ZERO
	_drag_world_axis = Vector3.ZERO
	var affected: Array[int] = _get_affected_vertex_indices(node)
	for idx: int in affected:
		_drag_initial_verts[idx] = node.go_build_mesh.vertices[idx]
	if handle_id >= ROT_HANDLE_OFFSET and handle_id < SCALE_HANDLE_OFFSET:
		var local_axis: Vector3 = _get_local_axis(handle_id - ROT_HANDLE_OFFSET)
		_drag_world_axis = (node.global_transform.basis * local_axis).normalized()
	_drag_restore = node.go_build_mesh.take_snapshot()


## Return [code]true[/code] when no drag is active (vertex cache is empty).
func is_drag_empty() -> bool:
	return _drag_initial_verts.is_empty()


## Return the stored mesh snapshot from the most recently started drag.
func get_drag_restore() -> Dictionary:
	return _drag_restore


## Return true if a drag is currently in progress.
func is_dragging() -> bool:
	return not _drag_initial_verts.is_empty() and _drag_current_handle_id >= AXIS_HANDLE_OFFSET


## Return a human-readable string for the current drag delta.
## Returns empty string when not dragging.
func get_drag_value_text() -> String:
	if not is_dragging():
		return ""
	var hid: int = _drag_current_handle_id
	if _inset_mode:
		return "inset %.3f" % _drag_cumulative_scale
	if hid >= UNIFORM_SCALE_HANDLE_ID:
		return "%.2fx" % _drag_cumulative_scale
	if hid >= VIEW_PLANE_HANDLE_ID:
		return _translate_text()
	if hid >= PLANE_HANDLE_OFFSET:
		return _translate_text()
	if hid >= SCALE_HANDLE_OFFSET:
		return "%.2fx" % _drag_cumulative_scale
	if hid >= ROT_HANDLE_OFFSET:
		var deg := rad_to_deg(_drag_cumulative_angle)
		return "%.1f°" % deg
	return _translate_text()


func _translate_text() -> String:
	var t := _drag_cumulative_translate
	return "Δ %.3f, %.3f, %.3f" % [t.x, t.y, t.z]


## When Shift (precision) state changes during a drag, snapshot the current
## vertex positions into [member _drag_initial_verts] and reset
## [member _drag_initial_t] so that subsequent drag frames re-anchor at the
## current visual position.  This makes precision toggle seamless: only the
## sensitivity changes, with no position jump.
##
## For inset mode, also resets [member _drag_start_dir] to the current screen
## position so the offset-based amount computation starts from zero again.
##
## Call at the start of every [method update_drag] invocation, before any
## drag-specific apply method.
func _reanchor_if_precision_changed(node: GoBuildMeshInstance, screen_pos: Vector2) -> void:
	var shift_now: bool = Input.is_key_pressed(KEY_SHIFT)
	if shift_now == _prev_precision_active:
		return
	_prev_precision_active = shift_now
	_do_reanchor(node, screen_pos)


## Re-anchor the drag reference point after a cursor warp or precision toggle.
## Bakes current vertex positions into [member _drag_initial_verts] and resets
## [member _drag_initial_t] so subsequent drag frames compute deltas from the
## current position instead of the pre-warp anchor.
func _do_reanchor(node: GoBuildMeshInstance, screen_pos: Vector2) -> void:
	var gbm: GoBuildMesh = node.go_build_mesh
	for idx: int in _drag_initial_verts:
		_drag_initial_verts[idx] = gbm.vertices[idx]
	_drag_initial_t = INF
	if _inset_mode:
		_inset_amount_offset = _current_inset_amount(node)
		_drag_start_dir = Vector3(screen_pos.x, screen_pos.y, 0.0)
		_drag_initial_t = 0.0


# ---------------------------------------------------------------------------
# Public drag API
# ---------------------------------------------------------------------------

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

	if handle_id >= ROT_HANDLE_OFFSET and handle_id < SCALE_HANDLE_OFFSET:
		var local_axis: Vector3 = _get_local_axis(handle_id - ROT_HANDLE_OFFSET)
		_drag_world_axis = (node.global_transform.basis * local_axis).normalized()

	_drag_restore = node.go_build_mesh.take_snapshot()
	_drag_cumulative_translate = Vector3.ZERO
	_drag_cumulative_angle = 0.0
	_drag_cumulative_scale = 1.0
	_inset_amount_offset = 0.0
	_prev_precision_active = Input.is_key_pressed(KEY_SHIFT)
	# Engage the fast vertex-position-only bake path for the duration of this drag.
	_drag_vertex_update_mode = true
	_drag_preview_mode = node.auto_uv_mode != GoBuildFace.UvMode.NONE
	if _drag_preview_mode:
		node.begin_preview()
	return true


## Apply the in-progress drag to [param node] given the current [param camera]
## and mouse [param screen_pos].
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
	_drag_current_handle_id = handle_id
	precision_active = Input.is_key_pressed(KEY_SHIFT)
	_reanchor_if_precision_changed(node, screen_pos)
	if _inset_mode:
		_apply_inset_drag(node, camera, screen_pos)
		return
	if handle_id >= UNIFORM_SCALE_HANDLE_ID:
		_apply_uniform_scale_drag(node, camera, screen_pos)
	elif handle_id >= VIEW_PLANE_HANDLE_ID:
		_apply_viewport_plane_drag(node, camera, screen_pos)
	elif handle_id >= PLANE_HANDLE_OFFSET:
		_apply_plane_drag(node, handle_id - PLANE_HANDLE_OFFSET, camera, screen_pos)
	elif handle_id >= SCALE_HANDLE_OFFSET:
		_apply_scale_drag(node, handle_id - SCALE_HANDLE_OFFSET, camera, screen_pos)
	elif handle_id >= ROT_HANDLE_OFFSET:
		_apply_rotate_drag(node, handle_id - ROT_HANDLE_OFFSET, camera, screen_pos)
	else:
		_apply_translate_drag(node, handle_id - AXIS_HANDLE_OFFSET, camera, screen_pos)


## Finalise or cancel the current drag on [param node].
## [param ur] is obtained by the caller ([GoBuildGizmoPlugin]) from
## [method EditorPlugin.get_undo_redo] so the handler stays decoupled from
## the [EditorPlugin] reference.
## On cancel, restores the mesh to [member _drag_restore].
## On confirm, pushes a single undo/redo action using [member _drag_restore] as
## the before-snapshot.
func commit_drag(
		node: GoBuildMeshInstance,
		handle_id: int,
		cancel: bool,
		ur: EditorUndoRedoManager,
) -> void:
	if handle_id < AXIS_HANDLE_OFFSET or node == null:
		return

	# Clear deferred queues before explicit bakes below so a stale deferred call
	# cannot overwrite the restored or committed mesh state.
	_bake_pending_node         = null
	_bake_scheduled            = false
	_gizmo_redraw_pending_node = null
	_gizmo_redraw_scheduled    = false

	if cancel:
		if _drag_preview_mode:
			node.end_preview()
		node.restore_and_bake(_drag_restore)
		node.update_gizmos()
	elif _drag_initial_t != INF:
		# Bake final dragged state before snapshooting so normals are correct.
		if node.auto_uv_mode != GoBuildFace.UvMode.NONE:
			node._apply_auto_uv()
		if _drag_preview_mode:
			node.end_preview()
		node.bake()
		var snapshot_after: Dictionary = node.go_build_mesh.take_snapshot()
		var action_name: String = _drag_action_name_override \
				if not _drag_action_name_override.is_empty() \
				else _drag_action_name(handle_id)
		ur.create_action(action_name)
		ur.add_do_method(node, "restore_and_bake", snapshot_after)
		ur.add_undo_method(node, "restore_and_bake", _drag_restore)
		ur.commit_action()

	reset_drag_state()


## Clear all in-progress drag state.
## Called on mode change, focus loss, node removal, and by [method commit_drag].
func reset_drag_state() -> void:
	_drag_initial_t = INF
	_drag_initial_verts.clear()
	_drag_start_dir  = Vector3.ZERO
	_drag_world_axis = Vector3.ZERO
	_drag_restore    = {}
	_drag_action_name_override = ""
	_drag_vertex_update_mode = false
	_drag_preview_mode = false
	_inset_mode = false
	_inset_centroids.clear()
	_inset_amount_offset = 0.0
	_drag_cumulative_translate = Vector3.ZERO
	_drag_cumulative_angle = 0.0
	_drag_cumulative_scale = 1.0
	_drag_current_handle_id = -1
	precision_active = false
	_prev_precision_active = false
	_bake_pending_node         = null
	_bake_scheduled            = false
	_gizmo_redraw_pending_node = null
	_gizmo_redraw_scheduled    = false


# ---------------------------------------------------------------------------
# DragOperation factory — bridge to GoBuildDragController
# ---------------------------------------------------------------------------

## Create a [GoBuildDragOperation] from the current drag state.
## Must be called after [method begin_drag] (or [method begin_inset_drag] /
## [method begin_extrude_drag]) has succeeded, so the vertex cache and snapshot
## are populated.  Returns [code]null[/code] if no drag is active.
##
## The operation's [member GoBuildDragOperation.delta_mode] is set from
## [param handle_id].  All accumulated state (vertex positions, centroids,
## action name, bake mode) is transferred from this handler's member variables.
func create_drag_operation(node: GoBuildMeshInstance, handle_id: int) -> GoBuildDragOperation:
	if _drag_initial_verts.is_empty() or node == null:
		return null
	var op := GoBuildDragOperation.new()
	op.node = node
	op.snapshot = _drag_restore
	op.action_name = _drag_action_name_override \
			if not _drag_action_name_override.is_empty() \
			else _drag_action_name(handle_id)
	op.handle_id = handle_id
	op.initial_vertex_positions = _drag_initial_verts.duplicate()
	op.drag_centroid = _compute_drag_centroid()
	op.vertex_update_mode = _drag_vertex_update_mode
	op.preview_mode = _drag_preview_mode
	op.inset_centroids = _inset_centroids.duplicate()
	op._gizmo_inset_offset = _inset_amount_offset
	op.snap_step = GoBuildTransformHelpers.get_snap_step(snap_step_override)

	var local_axes: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	if handle_id >= UNIFORM_SCALE_HANDLE_ID:
		op.delta_mode = GoBuildDragOperation.DeltaMode.SCALE_UNIFORM
	elif handle_id >= VIEW_PLANE_HANDLE_ID:
		op.delta_mode = GoBuildDragOperation.DeltaMode.VIEWPORT_PLANE_PROJECT
	elif handle_id >= PLANE_HANDLE_OFFSET:
		var plane_idx: int = handle_id - PLANE_HANDLE_OFFSET
		op.delta_mode = GoBuildDragOperation.DeltaMode.PLANE_PROJECT
		var plane_normals: Array[Vector3] = [Vector3.BACK, Vector3.RIGHT, Vector3.UP]
		op.world_axis = (node.global_transform.basis * plane_normals[plane_idx]).normalized()
		op.plane_index = plane_idx
	elif handle_id >= SCALE_HANDLE_OFFSET:
		var axis_idx: int = handle_id - SCALE_HANDLE_OFFSET
		op.delta_mode = GoBuildDragOperation.DeltaMode.SCALE_AXIS
		op.world_axis = (node.global_transform.basis * local_axes[axis_idx]).normalized()
		op.axis_index = axis_idx
		op.snap_step = scale_snap_override
	elif handle_id >= ROT_HANDLE_OFFSET:
		var axis_idx: int = handle_id - ROT_HANDLE_OFFSET
		op.delta_mode = GoBuildDragOperation.DeltaMode.ROTATE
		var local_axis: Vector3 = local_axes[axis_idx]
		op.world_axis = (node.global_transform.basis * local_axis).normalized()
		op.axis_index = axis_idx
		op.snap_step = rot_snap_override
	elif _inset_mode:
		op.delta_mode = GoBuildDragOperation.DeltaMode.INSET
		op.snap_step = scale_snap_override
	else:
		var axis_idx: int = handle_id - AXIS_HANDLE_OFFSET
		op.delta_mode = GoBuildDragOperation.DeltaMode.AXIS_PROJECT
		op.world_axis = (node.global_transform.basis * local_axes[axis_idx]).normalized()
		op.axis_index = axis_idx

	return op


# ---------------------------------------------------------------------------
# Specialised drag starters
# ---------------------------------------------------------------------------

## Start an inset drag: initialises inset state then begins a normal drag.
## [param centroids] maps each inner-ring vertex index to its local face centroid
## (obtained from [method InsetOperation.apply]).
## Returns false if [method begin_drag] fails.
func begin_inset_drag(
		node: GoBuildMeshInstance,
		handle_id: int,
		centroids: Dictionary,
) -> bool:
	var started: bool = begin_drag(node, handle_id)
	if not started:
		return false
	_inset_mode      = true
	_inset_centroids = centroids
	return true


## Start an extrude drag: begins a normal translate drag then restricts
## [member _drag_initial_verts] to only the extruded cap vertices.
##
## [param top_ring_indices] must be the vertex indices for the extruded cap
## faces [b]after[/b] the extrude operation has replaced them.
## Returns false if [method begin_drag] fails.
func begin_extrude_drag(
		node: GoBuildMeshInstance,
		handle_id: int,
		top_ring_indices: Array[int],
) -> bool:
	var started: bool = begin_drag(node, handle_id)
	if not started:
		return false
	# Overwrite to cap-only: discard coincident base verts that begin_drag added.
	_drag_initial_verts.clear()
	for vidx: int in top_ring_indices:
		_drag_initial_verts[vidx] = node.go_build_mesh.vertices[vidx]
	return true


# ---------------------------------------------------------------------------
# Deferred-bake
# ---------------------------------------------------------------------------

## Schedule a deferred mesh bake for [param node], coalescing multiple
## per-motion-event requests into a single bake per rendered frame.
func _schedule_bake(node: GoBuildMeshInstance) -> void:
	_bake_pending_node = node
	if not _bake_scheduled:
		_bake_scheduled = true
		call_deferred("_flush_pending_bake")


## Flush a pending deferred bake.  Invoked at end-of-frame via call_deferred.
func _flush_pending_bake() -> void:
	_bake_scheduled = false
	if _bake_pending_node != null and is_instance_valid(_bake_pending_node):
		if _bake_pending_node.auto_uv_mode != GoBuildFace.UvMode.NONE:
			_bake_pending_node._apply_auto_uv()
		if _drag_preview_mode:
			_bake_pending_node.bake_preview()
		elif _drag_vertex_update_mode:
			_bake_pending_node.bake_vertex_positions()
		else:
			_bake_pending_node.bake()
	_bake_pending_node = null


# ---------------------------------------------------------------------------
# Deferred-gizmo-redraw
# ---------------------------------------------------------------------------

## Schedule a deferred gizmo redraw for [param node], coalescing multiple
## per-motion-event requests into a single [method Node3D.update_gizmos] call
## per rendered frame.  Called from the drag hot-path in plugin.gd via the
## passthrough on [GoBuildGizmoPlugin].
func schedule_gizmo_redraw(node: GoBuildMeshInstance) -> void:
	_gizmo_redraw_pending_node = node
	if not _gizmo_redraw_scheduled:
		_gizmo_redraw_scheduled = true
		call_deferred("_flush_pending_gizmo_redraw")


## Flush a pending deferred gizmo redraw.  Invoked at end-of-frame via call_deferred.
func _flush_pending_gizmo_redraw() -> void:
	_gizmo_redraw_scheduled = false
	if _gizmo_redraw_pending_node != null and is_instance_valid(_gizmo_redraw_pending_node):
		_gizmo_redraw_pending_node.update_gizmos()
	_gizmo_redraw_pending_node = null


# ---------------------------------------------------------------------------
# Apply methods
# ---------------------------------------------------------------------------

## Apply a translate drag along axis [param axis_idx] to all cached vertices.
## When Ctrl is held, snaps the scalar travel distance to [method _get_snap_step].
## When V is held, snaps the centroid to the nearest non-dragged mesh vertex,
## projected onto the drag axis (vertex snap).
## When Shift is held, reduces movement to 10% (precision mode).
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

	# Vertex snap (V held): project the centroid→snap-vertex vector onto the axis.
	if Input.is_key_pressed(KEY_ALT):
		var snap_world: Vector3 = _find_vertex_snap_world_pos(node, camera, screen_pos)
		if snap_world != Vector3.INF:
			var t_delta: float = (snap_world - world_centroid).dot(world_axis)
			var delta_local: Vector3 = \
					node.global_transform.basis.inverse() * (world_axis * t_delta)
			for idx: int in _drag_initial_verts:
				gbm.vertices[idx] = _drag_initial_verts[idx] + delta_local
			_drag_cumulative_translate = delta_local
			if _drag_initial_t == INF:
				_drag_initial_t = 0.0
			_schedule_bake(node)
			return

	var t_now: float = _project_to_axis(camera, screen_pos, world_centroid, world_axis)

	if _drag_initial_t == INF:
		_drag_initial_t = t_now

	var t_delta: float = t_now - _drag_initial_t
	if Input.is_key_pressed(KEY_CTRL):
		t_delta = snappedf(t_delta, _get_snap_step())
	if precision_active:
		t_delta *= PRECISION_MULTIPLIER
	var delta_world: Vector3 = world_axis * t_delta
	var delta_local: Vector3 = node.global_transform.basis.inverse() * delta_world

	for idx: int in _drag_initial_verts:
		gbm.vertices[idx] = _drag_initial_verts[idx] + delta_local

	_drag_cumulative_translate = delta_local
	_schedule_bake(node)
## Apply a rotate drag around axis [param axis_idx] to all cached vertices.
## Uses [method Vector3.signed_angle_to] to compute the delta angle each frame.
## Shift reduces rotation speed to 10% (precision mode).
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
	if Input.is_key_pressed(KEY_CTRL):
		delta_angle = snappedf(delta_angle, deg_to_rad(rot_snap_override))
	if precision_active:
		delta_angle *= PRECISION_MULTIPLIER

	for idx: int in _drag_initial_verts:
		var local_pos: Vector3 = _drag_initial_verts[idx] - local_centroid
		gbm.vertices[idx] = local_centroid + local_pos.rotated(local_axis, delta_angle)

	_drag_cumulative_angle = delta_angle
	_schedule_bake(node)


## Apply a planar drag for [param plane_idx] (0=XY, 1=YZ, 2=XZ) to all cached
## vertices.  Projects the mouse ray onto the world-space plane that passes through
## the selection centroid with the matching local normal axis, then translates
## vertices by the delta from the first-frame hit point.
## [b]Ctrl held[/b] snaps each component of the world-space delta to the editor
## grid step via [method _get_snap_step].
## [b]V held[/b] snaps the centroid to the nearest non-dragged mesh vertex,
## constrained to move only within the drag plane.
## [b]Shift held[/b] reduces movement to 10% (precision mode).
func _apply_plane_drag(
		node: GoBuildMeshInstance,
		plane_idx: int,
		camera: Camera3D,
		screen_pos: Vector2,
) -> void:
	# Plane normals: XY=Z, YZ=X, XZ=Y.
	var local_normals: Array[Vector3] = [Vector3.BACK, Vector3.RIGHT, Vector3.UP]
	var local_normal: Vector3  = local_normals[plane_idx]
	var gbm: GoBuildMesh       = node.go_build_mesh
	var local_centroid: Vector3 = _compute_drag_centroid()
	var world_centroid: Vector3 = node.global_transform * local_centroid
	var world_normal: Vector3  = (node.global_transform.basis * local_normal).normalized()

	# Vertex snap (V held): move centroid to the nearest non-dragged vertex,
	# but remove the component perpendicular to the plane so movement stays in-plane.
	if Input.is_key_pressed(KEY_ALT):
		var snap_world: Vector3 = _find_vertex_snap_world_pos(node, camera, screen_pos)
		if snap_world != Vector3.INF:
			var raw_delta: Vector3 = snap_world - world_centroid
			raw_delta -= world_normal * raw_delta.dot(world_normal)
			var delta_local: Vector3 = node.global_transform.basis.inverse() * raw_delta
			for idx: int in _drag_initial_verts:
				gbm.vertices[idx] = _drag_initial_verts[idx] + delta_local
			_drag_cumulative_translate = delta_local
			if _drag_initial_t == INF:
				_drag_initial_t = 0.0
			_schedule_bake(node)
			return

	# First frame: record the initial intersection as the drag origin.
	if _drag_initial_t == INF:
		var hit0: Vector3 = _project_to_rotation_plane(camera, screen_pos, world_centroid, world_normal)
		if hit0 == Vector3.INF:
			return
		_drag_start_dir = hit0   # reuse _drag_start_dir as the initial world-space hit
		_drag_initial_t = 0.0
		return

	var hit: Vector3 = _project_to_rotation_plane(camera, screen_pos, world_centroid, world_normal)
	if hit == Vector3.INF:
		return

	var delta_world: Vector3 = hit - _drag_start_dir
	if Input.is_key_pressed(KEY_CTRL):
		delta_world = delta_world.snapped(Vector3.ONE * _get_snap_step())
	if precision_active:
		delta_world *= PRECISION_MULTIPLIER
	var delta_local: Vector3 = node.global_transform.basis.inverse() * delta_world
	for idx: int in _drag_initial_verts:
		gbm.vertices[idx] = _drag_initial_verts[idx] + delta_local
	_drag_cumulative_translate = delta_local
	_schedule_bake(node)


## Apply a per-axis scale drag for [param axis_idx] to all cached vertices.
## Projects the mouse ray onto the axis, computes a scale ratio from the initial
## projection, and scales the per-axis displacement of each vertex from the centroid.
## Shift reduces scale sensitivity (precision mode).
func _apply_scale_drag(
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
	if abs(_drag_initial_t) < 1e-5:
		return   # Avoid division by zero when dragging at the centroid.

	var scale_ratio: float = t_now / _drag_initial_t
	if Input.is_key_pressed(KEY_CTRL):
		scale_ratio = snappedf(scale_ratio, scale_snap_override)
	if precision_active:
		scale_ratio = 1.0 + (scale_ratio - 1.0) * PRECISION_MULTIPLIER
	for idx: int in _drag_initial_verts:
		var local_pos: Vector3 = _drag_initial_verts[idx] - local_centroid
		# Scale only the component along the dragged axis; keep perpendicular unchanged.
		var along: float   = local_pos.dot(local_axis)
		var perp: Vector3  = local_pos - local_axis * along
		gbm.vertices[idx]  = local_centroid + perp + local_axis * along * scale_ratio
	_drag_cumulative_scale = scale_ratio
	_schedule_bake(node)


## Apply a viewport-plane drag to all cached vertices.
## On the first call, records the camera forward vector as the plane normal and
## the initial mouse-plane intersection as the drag origin ([member _drag_start_dir]).
## Subsequent calls translate the selection by [code]hit - _drag_start_dir[/code].
## [b]Ctrl held[/b] snaps the world-space delta to the editor grid step.
## [b]V held[/b] snaps the centroid to the nearest non-dragged mesh vertex.
## [b]Shift held[/b] reduces movement to 10% (precision mode).
func _apply_viewport_plane_drag(
		node: GoBuildMeshInstance,
		camera: Camera3D,
		screen_pos: Vector2,
) -> void:
	var gbm: GoBuildMesh        = node.go_build_mesh
	var local_centroid: Vector3 = _compute_drag_centroid()
	var world_centroid: Vector3 = node.global_transform * local_centroid

	# Vertex snap (V held): snap the centroid directly to the nearest non-dragged
	# vertex world position — no camera-plane constraint.
	if Input.is_key_pressed(KEY_ALT):
		var snap_world: Vector3 = _find_vertex_snap_world_pos(node, camera, screen_pos)
		if snap_world != Vector3.INF:
			var delta_local: Vector3 = \
					node.global_transform.basis.inverse() * (snap_world - world_centroid)
			for idx: int in _drag_initial_verts:
				gbm.vertices[idx] = _drag_initial_verts[idx] + delta_local
			_drag_cumulative_translate = delta_local
			if _drag_initial_t == INF:
				_drag_initial_t = 0.0
			_schedule_bake(node)
			return

	# First frame: capture camera-forward as plane normal + record initial hit.
	if _drag_initial_t == INF:
		_drag_world_axis = -camera.global_transform.basis.z   # camera forward = -Z
		var hit0: Vector3 = _project_to_rotation_plane(
				camera, screen_pos, world_centroid, _drag_world_axis)
		if hit0 == Vector3.INF:
			return
		_drag_start_dir = hit0
		_drag_initial_t = 0.0
		return

	var hit: Vector3 = _project_to_rotation_plane(
			camera, screen_pos, world_centroid, _drag_world_axis)
	if hit == Vector3.INF:
		return

	var delta_world: Vector3 = hit - _drag_start_dir
	if Input.is_key_pressed(KEY_CTRL):
		delta_world = delta_world.snapped(Vector3.ONE * _get_snap_step())
	if precision_active:
		delta_world *= PRECISION_MULTIPLIER
	var delta_local: Vector3 = node.global_transform.basis.inverse() * delta_world
	for idx: int in _drag_initial_verts:
		gbm.vertices[idx] = _drag_initial_verts[idx] + delta_local
	_drag_cumulative_translate = delta_local
	_schedule_bake(node)


## Apply a uniform (all-axis) scale drag. Projects the mouse onto a camera-facing
## plane through the centroid and scales all vertex offsets by current/initial offset.
## Dragging up-right from the centroid increases scale; dragging down-left decreases
## it below 1.0 and can go negative (mirror).
## [b]Ctrl[/b] snaps the ratio to [member scale_snap_override] increments.
## [b]Shift[/b] reduces scale sensitivity (precision mode).
func _apply_uniform_scale_drag(
		node: GoBuildMeshInstance, camera: Camera3D, screen_pos: Vector2,
) -> void:
	var gbm: GoBuildMesh        = node.go_build_mesh
	var local_centroid: Vector3 = _compute_drag_centroid()
	var world_centroid: Vector3 = node.global_transform * local_centroid
	var cam_forward: Vector3    = -camera.global_transform.basis.z
	var hit: Vector3 = _ray_plane_intersect(
			camera.project_ray_origin(screen_pos),
			camera.project_ray_normal(screen_pos),
			world_centroid, cam_forward)
	if hit == Vector3.INF:
		return
	if _drag_initial_t == INF:
		var dist: float = hit.distance_to(world_centroid)
		if dist < 1e-3:
			return
		_drag_initial_t = dist
		_drag_start_dir = hit - world_centroid
		return
	if _drag_initial_t < 1e-3:
		return
	var offset: Vector3 = hit - world_centroid
	var projected: float = offset.dot(_drag_start_dir.normalized())
	var scale_ratio: float = projected / _drag_initial_t
	if Input.is_key_pressed(KEY_CTRL):
		scale_ratio = snappedf(scale_ratio, scale_snap_override)
	if precision_active:
		scale_ratio = 1.0 + (scale_ratio - 1.0) * PRECISION_MULTIPLIER
	for idx: int in _drag_initial_verts:
		gbm.vertices[idx] = local_centroid \
				+ (_drag_initial_verts[idx] - local_centroid) * scale_ratio
	_drag_cumulative_scale = scale_ratio
	_schedule_bake(node)


## Apply an inset drag to the inner-ring vertices created by [method begin_inset_drag].
## On the first frame, records the initial screen position via [member _drag_start_dir].
## Subsequent frames compute an inset amount from the screen-space offset
## along the drag direction and blend each inner vertex from its initial
## position toward its face centroid.
## [b]Ctrl[/b] snaps the amount to [member scale_snap_override] increments.
## [b]Shift[/b] reduces inset speed (precision mode).
func _apply_inset_drag(
		node: GoBuildMeshInstance,
		_camera: Camera3D,
		screen_pos: Vector2,
) -> void:
	if _drag_initial_t == INF:
		_drag_start_dir = Vector3(screen_pos.x, screen_pos.y, 0.0)
		_drag_initial_t = 0.0
		return
	var start_screen := Vector2(_drag_start_dir.x, _drag_start_dir.y)
	var offset: float = (screen_pos - start_screen).dot(Vector2(1.0, 0.0))
	var amount: float = offset * 0.005
	if Input.is_key_pressed(KEY_CTRL):
		amount = snappedf(amount, scale_snap_override)
	if precision_active:
		amount *= PRECISION_MULTIPLIER
	amount = clampf(amount + _inset_amount_offset, 0.0, 1.0)
	var gbm: GoBuildMesh = node.go_build_mesh
	for idx: int in _drag_initial_verts:
		if _inset_centroids.has(idx):
			var init_pos: Vector3 = _drag_initial_verts[idx]
			var centroid: Vector3 = _inset_centroids[idx]
			gbm.vertices[idx] = lerp(init_pos, centroid, amount)
	_drag_cumulative_scale = amount
	_schedule_bake(node)


## Compute the current inset amount from the mesh vertex positions.
## For the first inner-ring vertex found, derives [code]lerp(init, centroid, amount)[/code]
## to recover [code]amount[/code]. Used by [method _reanchor_if_precision_changed]
## to capture the current inset progress before resetting the screen-space anchor.
func _current_inset_amount(node: GoBuildMeshInstance) -> float:
	var gbm: GoBuildMesh = node.go_build_mesh
	for idx: int in _drag_initial_verts:
		if not _inset_centroids.has(idx):
			continue
		var init_pos: Vector3 = _drag_initial_verts[idx]
		var centroid: Vector3 = _inset_centroids[idx]
		var current_pos: Vector3 = gbm.vertices[idx]
		var direction: Vector3 = centroid - init_pos
		var length_sq: float = direction.length_squared()
		if length_sq < 1e-10:
			continue
		var t: float = (current_pos - init_pos).dot(direction) / length_sq
		return clampf(t, 0.0, 1.0)
	return 0.0


## Return the undo/redo action name for [param handle_id].
func _drag_action_name(handle_id: int) -> String:
	if handle_id >= UNIFORM_SCALE_HANDLE_ID:
		return "Scale Elements (Uniform)"
	if handle_id >= SCALE_HANDLE_OFFSET and handle_id < PLANE_HANDLE_OFFSET:
		return "Scale Elements"
	if handle_id >= ROT_HANDLE_OFFSET and handle_id < SCALE_HANDLE_OFFSET:
		return "Rotate Elements"
	return "Move Elements"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Return the grid-snap step from EditorSettings ([code]editors/3d/grid_step[/code]).
## Falls back to [code]1.0[/code] if the key is absent or the editor is not running.
func _get_snap_step() -> float:
	return GoBuildTransformHelpers.get_snap_step(snap_step_override)


## Return the arithmetic mean of the cached initial vertex positions.
func _compute_drag_centroid() -> Vector3:
	var c := Vector3.ZERO
	for idx: int in _drag_initial_verts:
		c += _drag_initial_verts[idx]
	return c / _drag_initial_verts.size()


## Find the world-space position of the mesh vertex nearest to [param screen_pos]
## (measured in screen-space pixels), excluding vertices currently being dragged.
## Returns [code]Vector3.INF[/code] if no eligible vertex is visible.
func _find_vertex_snap_world_pos(
		node: GoBuildMeshInstance,
		camera: Camera3D,
		screen_pos: Vector2,
) -> Vector3:
	var gbm: GoBuildMesh = node.go_build_mesh
	if gbm == null or gbm.vertices.is_empty():
		return Vector3.INF
	var gt: Transform3D = node.global_transform
	var best_dist_sq: float = INF
	var best_pos: Vector3   = Vector3.INF
	for i: int in gbm.vertices.size():
		if _drag_initial_verts.has(i):
			continue
		var world_pos: Vector3 = gt * gbm.vertices[i]
		if not camera.is_position_in_frustum(world_pos):
			continue
		var screen_v: Vector2 = camera.unproject_position(world_pos)
		var dist_sq: float = screen_v.distance_squared_to(screen_pos)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_pos     = world_pos
	return best_pos


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
	return GoBuildTransformHelpers.ray_plane_intersect(
		ray_origin, ray_dir, plane_origin, plane_normal)


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
	return GoBuildTransformHelpers.ray_plane_intersect(
		ray_origin, ray_dir, plane_origin, plane_normal)


## Collect unique vertex indices affected by the current selection on [param node],
## then expand each to include all coincident partners from
## [member GoBuildMesh.coincident_groups].
func _get_affected_vertex_indices(node: GoBuildMeshInstance) -> Array[int]:
	return GoBuildTransformHelpers.get_affected_vertex_indices(node)


## Return the local-space unit vector for axis index 0=X, 1=Y, 2=Z.
static func _get_local_axis(axis_idx: int) -> Vector3:
	return GoBuildTransformHelpers.get_local_axis(axis_idx)
