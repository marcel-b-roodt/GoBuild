## Unified drag / operation controller for GoBuild.
##
## Owns the full begin → update → commit/cancel lifecycle for both gizmo-handle
## drags and param-preview operations.  Replaces the duplicated logic that was
## spread across [SelectionInputController].
##
## Each interaction creates a [GoBuildDragOperation] and passes it to [method begin].
## The controller drives the [GoBuildMouseTracker], selects the correct
## [GoBuildDeltaStrategy] function, applies the result, manages deferred baking,
## and wires undo/redo on commit.
##
## This controller is intentionally a [RefCounted] — it has no scene-tree
## dependency and can be unit-tested without a running editor.
@tool
class_name GoBuildDragController
extends RefCounted

# Self-preloads (dependency order).
const _DRAG_OP_SCRIPT     := preload("res://addons/go_build/core/go_build_drag_operation.gd")
const _DELTA_STRAT_SCRIPT := preload("res://addons/go_build/core/go_build_delta_strategy.gd")
const _MOUSE_TRACKER_SCRIPT := preload("res://addons/go_build/core/go_build_mouse_tracker.gd")
const _MESH_INSTANCE_SCRIPT := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _MESH_SCRIPT          := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _FACE_SCRIPT          := preload("res://addons/go_build/mesh/go_build_face.gd")
const _TRANSFORM_HELPERS_SCRIPT := preload(
		"res://addons/go_build/core/go_build_transform_helpers.gd")

## Precision multiplier applied when Shift is held during a drag.
const _PRECISION_MULTIPLIER_VAL: float = 0.1

var _op: GoBuildDragOperation = null
var _tracker: GoBuildMouseTracker = GoBuildMouseTracker.new()

var _active: bool = false

## When true, the controller only drives overlay display — the SIC or legacy
## handler owns mesh mutation, deferred bakes, and undo wiring.  The controller
## must NOT restore snapshots, call apply_fn, or schedule bakes.
var _overlay_only: bool = false

var _apply_scheduled: bool = false
var _apply_node: GoBuildMeshInstance = null
var _apply_target_param: float = 0.0
var _apply_target_vec: Vector3 = Vector3.ZERO

var _cached_camera: Camera3D = null

## Raw cumulative deltas — always accumulate, never snap.  These are the source
## of truth for the total displacement since drag start.
var _raw_translate: Vector3 = Vector3.ZERO
var _raw_angle: float = 0.0
var _raw_scale: float = 1.0
var _raw_inset: float = 0.0

var _overlay_anchor: Vector2 = Vector2.ZERO
var _overlay_vp_size: Vector2 = Vector2.ZERO

var _editor_plugin: EditorPlugin = null


func setup(editor_plugin: EditorPlugin) -> void:
	_editor_plugin = editor_plugin


func begin(op: GoBuildDragOperation, overlay_only: bool = false) -> void:
	_op = op
	_active = true
	_overlay_only = overlay_only
	_apply_scheduled = false
	_apply_node = null
	_apply_target_param = 0.0
	_apply_target_vec = Vector3.ZERO
	_cached_camera = null
	_raw_translate = Vector3.ZERO
	_raw_angle = 0.0
	_raw_scale = 1.0
	_raw_inset = 0.0

	_compute_initial_world_size(op)

	if _is_gizmo_mode():
		if op.node != null and is_instance_valid(op.node):
			op.node.begin_preview()
			op.preview_mode = true

	var radial: bool = op.delta_mode == GoBuildDragOperation.DeltaMode.PARAM_RADIAL \
			or op.delta_mode == GoBuildDragOperation.DeltaMode.INSET
	_tracker.begin(
			Vector2.ZERO,
			Vector2(1280, 720),
			radial,
			op.screen_direction,
			op.units_per_pixel)

	_capture_viewport_info()


func begin_with_initial_apply(op: GoBuildDragOperation) -> void:
	begin(op)
	if op.node != null and is_instance_valid(op.node):
		if op.apply_fn.is_valid():
			op.apply_fn.call(op.param_start)
		op.param = op.param_start
		if op.preview_mode:
			op.node.begin_preview()
			op.node.bake_preview()
		else:
			op.node.bake()
		op.node.update_gizmos()


func update(
		camera: Camera3D,
		pixel_offset: Vector2,
		shift_pressed: bool,
		ctrl_pressed: bool,
) -> void:
	if not _active or _op == null:
		return
	_cached_camera = camera

	if _is_gizmo_mode():
		_update_gizmo_drag(camera, pixel_offset, shift_pressed, ctrl_pressed)
	else:
		_update_param_drag()


func handle_motion_event(mm: InputEventMouseMotion) -> void:
	if not _active or _op == null:
		return
	if not _tracker.is_active():
		return
	_tracker.reset_filter()
	_tracker.feed(mm)
	if _is_gizmo_mode():
		var frame_delta: Vector2 = mm.relative
		var shift_pressed: bool = mm.shift_pressed
		var ctrl_pressed: bool = mm.ctrl_pressed
		if _cached_camera != null:
			_update_gizmo_drag(_cached_camera, frame_delta, shift_pressed, ctrl_pressed)
		if _editor_plugin != null:
			_editor_plugin.update_overlays()
	else:
		_update_param_drag()
		if _editor_plugin != null:
			_editor_plugin.update_overlays()


## Feed a raw pixel delta for non-CAPTURED gizmo drags.
## Uses the tracker for overlay display but takes per-frame delta directly.
func handle_motion_raw(
		frame_delta: Vector2,
		shift_pressed: bool,
		ctrl_pressed: bool,
		camera: Camera3D,
) -> void:
	if not _active or _op == null:
		return
	if _is_gizmo_mode():
		_update_gizmo_drag(camera, frame_delta, shift_pressed, ctrl_pressed)
	else:
		_update_param_drag()


func commit() -> void:
	if not _active or _op == null:
		return
	var op: GoBuildDragOperation = _op

	if _overlay_only:
		_clear_deferred_state()
		_end()
		return

	if op.node != null and is_instance_valid(op.node):
		if not _is_gizmo_mode():
			_flush_param_apply_sync(op.node, op.param)
		else:
			GoBuildDebug.log("[GoBuild] DC.commit  gizmo mode  preview=%s" % op.preview_mode)
			_flush_gizmo_apply_sync(op.node)

		if op.preview_mode:
			op.node.end_preview()
		if op.node.auto_uv_mode != GoBuildFace.UvMode.NONE:
			op.node._apply_auto_uv()
		op.node.go_build_mesh.rebuild_coincident_groups()
		op.node.bake()

		var after_snapshot: Dictionary = op.node.go_build_mesh.take_snapshot()
		op.node.update_gizmos()

		if _editor_plugin != null:
			var ur: EditorUndoRedoManager = _editor_plugin.get_undo_redo()
			ur.create_action(op.action_name)
			ur.add_do_method(op.node, "restore_and_bake", after_snapshot)
			ur.add_undo_method(op.node, "restore_and_bake", op.snapshot)
			ur.commit_action(false)

		if op.post_commit_fn.is_valid():
			op.post_commit_fn.call()

	_clear_deferred_state()
	_end()


func cancel() -> void:
	if not _active or _op == null:
		return
	var op: GoBuildDragOperation = _op

	GoBuildDebug.log("[GoBuild] DC.cancel  overlay=%s  preview=%s" % [
			_overlay_only, op.preview_mode])
	if not _overlay_only:
		if op.node != null and is_instance_valid(op.node):
			if op.preview_mode:
				op.node.end_preview()
			op.node.restore_and_bake(op.snapshot)

	_clear_deferred_state()
	_end()


func is_active() -> bool:
	return _active


func is_overlay_only() -> bool:
	return _overlay_only


func get_cached_camera() -> Camera3D:
	if _cached_camera == null and Engine.is_editor_hint():
		var sv: SubViewport = EditorInterface.get_editor_viewport_3d(0)
		if sv != null:
			_cached_camera = sv.get_camera_3d()
	return _cached_camera


func get_operation() -> GoBuildDragOperation:
	return _op


func get_overlay_data() -> Dictionary:
	if not _active or _op == null:
		return {}
	var data: Dictionary = {}
	data["anchor"] = _overlay_anchor
	data["vp_size"] = _overlay_vp_size
	data["indicator_pos"] = _tracker.get_indicator_pos()
	data["virtual_pos"] = _tracker.get_virtual_pos()
	data["delta"] = _tracker.get_delta()
	data["param"] = _op.param
	data["param_start"] = _op.param_start
	data["label"] = _op.overlay_label
	data["param_label"] = _get_param_label()
	if _is_gizmo_mode():
		data["is_gizmo"] = true
		data["cumulative_translate"] = _op._gizmo_cumulative_translate
		data["cumulative_angle"] = _op._gizmo_cumulative_angle
		data["cumulative_scale"] = _op._gizmo_cumulative_scale
	return data


func get_overlay_text() -> String:
	if not _active or _op == null:
		return ""
	if _is_gizmo_mode():
		return _gizmo_value_text()
	var snap_hint: String = ""
	if _op.snap_to_start:
		snap_hint = "  [near %.2f snaps]" % _op.param_start
	return "%s: %.4f%s   LMB=accept   RMB/Esc=cancel" % [
		_op.overlay_label, _op.param, snap_hint]


func get_tracker() -> GoBuildMouseTracker:
	return _tracker


func is_param_mode() -> bool:
	return _active and _op != null and not _is_gizmo_mode()


## Set the current param value from an external source (e.g. SIC driving the
## param preview).  This keeps the overlay text in sync without the controller
## computing param from its own tracker during overlay-only mode.
func set_param(value: float) -> void:
	if _op != null:
		_op.param = value


## Re-anchor the gizmo drag after a cursor warp.  Bakes the current cumulative
## delta into [member GoBuildDragOperation.initial_vertex_positions] so that
## the mesh state is preserved, then resets the cumulative deltas and the
## tracker so subsequent frames build from zero.
func reanchor() -> void:
	if _op == null or _op.node == null or not is_instance_valid(_op.node):
		return
	var gbm: GoBuildMesh = _op.node.go_build_mesh
	if gbm == null:
		return
	for idx: int in _op.initial_vertex_positions:
		if idx < gbm.vertices.size():
			_op.initial_vertex_positions[idx] = gbm.vertices[idx]
	_raw_translate = Vector3.ZERO
	_raw_angle = 0.0
	_raw_scale = 1.0
	_raw_inset = 0.0
	_tracker.begin(
			_overlay_anchor,
			_tracker.get_viewport_size(),
			_tracker._radial,
			_tracker._screen_direction,
			_tracker._sensitivity)


func set_viewport_info(anchor: Vector2, vp_size: Vector2) -> void:
	_overlay_anchor = anchor
	_overlay_vp_size = vp_size
	_tracker.begin(
			anchor,
			vp_size,
			_tracker._radial,
			_tracker._screen_direction,
			_tracker._sensitivity)


# ---------------------------------------------------------------------------
# Internal — mode query
# ---------------------------------------------------------------------------

func _is_gizmo_mode() -> bool:
	if _op == null:
		return false
	return _op.delta_mode == GoBuildDragOperation.DeltaMode.AXIS_PROJECT \
		or _op.delta_mode == GoBuildDragOperation.DeltaMode.PLANE_PROJECT \
		or _op.delta_mode == GoBuildDragOperation.DeltaMode.VIEWPORT_PLANE_PROJECT \
		or _op.delta_mode == GoBuildDragOperation.DeltaMode.ROTATE \
		or _op.delta_mode == GoBuildDragOperation.DeltaMode.SCALE_AXIS \
		or _op.delta_mode == GoBuildDragOperation.DeltaMode.SCALE_UNIFORM \
		or _op.delta_mode == GoBuildDragOperation.DeltaMode.INSET


# ---------------------------------------------------------------------------
# Internal — gizmo drag
# ---------------------------------------------------------------------------

func _update_gizmo_drag(
		camera: Camera3D,
		frame_delta: Vector2,
		shift_pressed: bool,
		ctrl_pressed: bool,
) -> void:
	var op: GoBuildDragOperation = _op
	var node: GoBuildMeshInstance = op.node
	if node == null or not is_instance_valid(node):
		return
	var gbm: GoBuildMesh = node.go_build_mesh
	if gbm == null:
		return

	var precision_mult: float = _PRECISION_MULTIPLIER_VAL if shift_pressed else 1.0
	var snap_enabled: bool = ctrl_pressed
	var snap_step: float = op.snap_step
	var world_centroid: Vector3 = node.global_transform * op.drag_centroid
	var node_xform: Transform3D = node.global_transform

	_apply_gizmo_strategy(op, camera, frame_delta, world_centroid, node_xform,
			precision_mult, snap_enabled, snap_step)
	if not _overlay_only:
		_schedule_gizmo_apply(node)


func _apply_gizmo_strategy(
		op: GoBuildDragOperation,
		camera: Camera3D,
		frame_delta: Vector2,
		world_centroid: Vector3,
		node_xform: Transform3D,
		precision_mult: float,
		snap_enabled: bool,
		snap_step: float,
) -> void:
	var result: GoBuildDeltaStrategy.StrategyResult = _compute_frame_result(
			op, camera, frame_delta, world_centroid, node_xform,
			precision_mult, snap_enabled, snap_step)
	if result != null:
		_apply_strategy_result(op, result)


func _compute_frame_result(
		op: GoBuildDragOperation,
		camera: Camera3D,
		frame_delta: Vector2,
		world_centroid: Vector3,
		node_xform: Transform3D,
		precision_mult: float,
		snap_enabled: bool,
		snap_step: float,
) -> GoBuildDeltaStrategy.StrategyResult:
	var world_axis: Vector3 = op.world_axis.normalized()

	# Raw accumulators always grow by the un-snapped per-frame delta.
	# Snap is applied to a copy for display/mutation — never overwriting the
	# raw total — so small deltas can cross grid boundaries over multiple frames.
	var frame_result: GoBuildDeltaStrategy.StrategyResult
	var local_centroid: Vector3 = op.drag_centroid

	match op.delta_mode:
		GoBuildDragOperation.DeltaMode.AXIS_PROJECT:
			frame_result = GoBuildDeltaStrategy.axis_project_frame(
					frame_delta, camera, world_centroid,
					world_axis, node_xform, precision_mult)
			_raw_translate += frame_result.vec_value
			var result_val: Vector3 = _raw_translate
			if snap_enabled:
				result_val = _snap_translate(result_val, local_centroid,
						node_xform, snap_step, op.snap_mode)
			var total_result := GoBuildDeltaStrategy.StrategyResult.new()
			total_result.vec_value = result_val
			return total_result

		GoBuildDragOperation.DeltaMode.PLANE_PROJECT:
			frame_result = GoBuildDeltaStrategy.plane_project_frame(
					frame_delta, camera, world_centroid,
					world_axis, node_xform, precision_mult)
			_raw_translate += frame_result.vec_value
			var result_val: Vector3 = _raw_translate
			if snap_enabled:
				result_val = _snap_translate(result_val, local_centroid,
						node_xform, snap_step, op.snap_mode)
			var total_result := GoBuildDeltaStrategy.StrategyResult.new()
			total_result.vec_value = result_val
			return total_result

		GoBuildDragOperation.DeltaMode.VIEWPORT_PLANE_PROJECT:
			frame_result = GoBuildDeltaStrategy.viewport_plane_project_frame(
					frame_delta, camera, world_centroid,
					node_xform, precision_mult)
			_raw_translate += frame_result.vec_value
			var result_val: Vector3 = _raw_translate
			if snap_enabled:
				result_val = _snap_translate(result_val, local_centroid,
						node_xform, snap_step, op.snap_mode)
			var total_result := GoBuildDeltaStrategy.StrategyResult.new()
			total_result.vec_value = result_val
			return total_result

		GoBuildDragOperation.DeltaMode.ROTATE:
			var rot_world_axis: Vector3
			if op.transform_space == 1:  # WORLD
				rot_world_axis = _TRANSFORM_HELPERS_SCRIPT.get_local_axis(
						op.axis_index)
			else:
				rot_world_axis = (node_xform.basis * _TRANSFORM_HELPERS_SCRIPT \
						.get_local_axis(op.axis_index)).normalized()
			frame_result = GoBuildDeltaStrategy.rotate_frame(
					frame_delta, camera, world_centroid,
					rot_world_axis,
					precision_mult)
			_raw_angle += frame_result.float_value
			var result_val: float = _raw_angle
			if snap_enabled:
				result_val = snappedf(result_val, deg_to_rad(snap_step))
			var total_result := GoBuildDeltaStrategy.StrategyResult.new()
			total_result.float_value = result_val
			return total_result

		GoBuildDragOperation.DeltaMode.SCALE_AXIS:
			frame_result = GoBuildDeltaStrategy.scale_axis_frame(
					frame_delta, camera, world_centroid,
					world_axis, op.initial_world_size, precision_mult)
			_raw_scale += frame_result.float_value
			var result_val: float = _raw_scale
			if snap_enabled:
				result_val = snappedf(result_val, snap_step)
			var total_result := GoBuildDeltaStrategy.StrategyResult.new()
			total_result.float_value = result_val
			return total_result

		GoBuildDragOperation.DeltaMode.SCALE_UNIFORM:
			frame_result = GoBuildDeltaStrategy.scale_uniform_frame(
					frame_delta, camera, world_centroid,
					-camera.global_transform.basis.z,
					op.initial_world_size, precision_mult)
			_raw_scale += frame_result.float_value
			var result_val: float = _raw_scale
			if snap_enabled:
				result_val = snappedf(result_val, snap_step)
			var total_result := GoBuildDeltaStrategy.StrategyResult.new()
			total_result.float_value = result_val
			return total_result

		GoBuildDragOperation.DeltaMode.INSET:
			frame_result = GoBuildDeltaStrategy.inset_frame(
					frame_delta, precision_mult)
			_raw_inset += frame_result.float_value
			var result_val: float = clampf(_raw_inset, 0.0, 1.0)
			if snap_enabled:
				result_val = snappedf(result_val, snap_step)
			var total_result := GoBuildDeltaStrategy.StrategyResult.new()
			total_result.float_value = result_val
			return total_result

	return null


## Snap a translate delta based on [param snap_mode].
##
## [code]WORLD_GRID[/code] (default): snaps the centroid's final world position
## to absolute grid lines, so objects naturally land on grid crossings regardless
## of their starting offset.
##
## [code]DELTA_GRID[/code]: snaps the cumulative displacement to grid increments,
## matching the behaviour of older GoBuild versions where each drag shifts by
## multiples of the grid step from the drag start position.
static func _snap_translate(
		raw_delta: Vector3,
		local_centroid: Vector3,
		node_xform: Transform3D,
		snap_step: float,
		snap_mode: int,
) -> Vector3:
	match snap_mode:
		GoBuildDragOperation.SnapMode.WORLD_GRID:
			var tentative_local: Vector3 = local_centroid + raw_delta
			var snapped_world: Vector3 = (node_xform * tentative_local).snapped(
					Vector3.ONE * snap_step)
			return node_xform.inverse() * snapped_world - local_centroid
		GoBuildDragOperation.SnapMode.DELTA_GRID:
			return raw_delta.snapped(Vector3.ONE * snap_step)
	return raw_delta


func _apply_strategy_result(
		op: GoBuildDragOperation,
		result: GoBuildDeltaStrategy.StrategyResult,
) -> void:
	var node: GoBuildMeshInstance = op.node
	var mutate: bool = not _overlay_only
	match op.delta_mode:
		GoBuildDragOperation.DeltaMode.AXIS_PROJECT:
			if mutate:
				_apply_vertex_translate(node, op, result.vec_value)
			op._gizmo_cumulative_translate = result.vec_value
		GoBuildDragOperation.DeltaMode.PLANE_PROJECT:
			if mutate:
				_apply_vertex_translate(node, op, result.vec_value)
			op._gizmo_cumulative_translate = result.vec_value
		GoBuildDragOperation.DeltaMode.VIEWPORT_PLANE_PROJECT:
			if mutate:
				_apply_vertex_translate(node, op, result.vec_value)
			op._gizmo_cumulative_translate = result.vec_value
		GoBuildDragOperation.DeltaMode.ROTATE:
			if mutate:
				var local_axis: Vector3
				if op.transform_space == 1:  # WORLD
					var inv_basis: Basis = op.node.global_transform.basis.inverse()
					local_axis = (inv_basis * _TRANSFORM_HELPERS_SCRIPT.get_local_axis(op.axis_index)).normalized()
				else:
					local_axis = _TRANSFORM_HELPERS_SCRIPT.get_local_axis(op.axis_index)
				_apply_vertex_rotate(node, op, local_axis, op.drag_centroid, result.float_value)
			op._gizmo_cumulative_angle = result.float_value
		GoBuildDragOperation.DeltaMode.SCALE_AXIS:
			if mutate:
				var local_axis: Vector3
				if op.transform_space == 1:  # WORLD
					var inv_basis: Basis = op.node.global_transform.basis.inverse()
					local_axis = (inv_basis * _TRANSFORM_HELPERS_SCRIPT.get_local_axis(op.axis_index)).normalized()
				else:
					local_axis = _TRANSFORM_HELPERS_SCRIPT.get_local_axis(op.axis_index)
				_apply_vertex_scale_axis(op, local_axis, result.float_value)
			op._gizmo_cumulative_scale = result.float_value
		GoBuildDragOperation.DeltaMode.SCALE_UNIFORM:
			if mutate:
				_apply_vertex_scale_uniform(op, op.drag_centroid, result.float_value)
			op._gizmo_cumulative_scale = result.float_value
		GoBuildDragOperation.DeltaMode.INSET:
			if mutate:
				_apply_inset(op, result.float_value)
			op._gizmo_cumulative_scale = result.float_value


func _apply_vertex_translate(
		node: GoBuildMeshInstance,
		op: GoBuildDragOperation,
		delta_local: Vector3,
) -> void:
	var gbm: GoBuildMesh = node.go_build_mesh
	for idx: int in op.initial_vertex_positions:
		gbm.vertices[idx] = op.initial_vertex_positions[idx] + delta_local


func _apply_vertex_rotate(
		node: GoBuildMeshInstance,
		op: GoBuildDragOperation,
		local_axis: Vector3,
		local_centroid: Vector3,
		angle: float,
) -> void:
	var gbm: GoBuildMesh = node.go_build_mesh
	for idx: int in op.initial_vertex_positions:
		var local_pos: Vector3 = op.initial_vertex_positions[idx] - local_centroid
		gbm.vertices[idx] = local_centroid + local_pos.rotated(local_axis, angle)


func _apply_vertex_scale_axis(
		op: GoBuildDragOperation,
		local_axis: Vector3,
		scale_ratio: float,
) -> void:
	if op.node == null:
		return
	var gbm: GoBuildMesh = op.node.go_build_mesh
	var local_centroid: Vector3 = op.drag_centroid
	for idx: int in op.initial_vertex_positions:
		var local_pos: Vector3 = op.initial_vertex_positions[idx] - local_centroid
		var along: float = local_pos.dot(local_axis)
		var perp: Vector3 = local_pos - local_axis * along
		gbm.vertices[idx] = local_centroid + perp + local_axis * along * scale_ratio


func _apply_vertex_scale_uniform(
		op: GoBuildDragOperation,
		local_centroid: Vector3,
		scale_ratio: float,
) -> void:
	if op.node == null:
		return
	var gbm: GoBuildMesh = op.node.go_build_mesh
	for idx: int in op.initial_vertex_positions:
		gbm.vertices[idx] = local_centroid \
				+ (op.initial_vertex_positions[idx] - local_centroid) * scale_ratio


func _apply_inset(op: GoBuildDragOperation, amount: float) -> void:
	if op.node == null:
		return
	var gbm: GoBuildMesh = op.node.go_build_mesh
	for idx: int in op.initial_vertex_positions:
		if op.inset_centroids.has(idx):
			var init_pos: Vector3 = op.initial_vertex_positions[idx]
			var centroid: Vector3 = op.inset_centroids[idx]
			gbm.vertices[idx] = lerp(init_pos, centroid, amount)


func _schedule_gizmo_apply(node: GoBuildMeshInstance) -> void:
	_apply_node = node
	if not _apply_scheduled:
		_apply_scheduled = true
		call_deferred("_flush_gizmo_apply_deferred")


func _flush_gizmo_apply_deferred() -> void:
	_apply_scheduled = false
	if _apply_node == null or not is_instance_valid(_apply_node) or _op == null:
		_apply_node = null
		return
	var node: GoBuildMeshInstance = _apply_node
	_apply_node = null
	if _op.preview_mode:
		if node.auto_uv_mode != GoBuildFace.UvMode.NONE:
			node._apply_auto_uv()
		node.bake_preview()
	elif _op.vertex_update_mode:
		node.bake_vertex_positions()
	else:
		node.bake()
	node.update_gizmos()
	if _editor_plugin != null:
		_editor_plugin.update_overlays()


func _flush_gizmo_apply_sync(node: GoBuildMeshInstance) -> void:
	_apply_scheduled = false
	_apply_node = null
	if _op == null:
		return
	if _op.preview_mode:
		if node.auto_uv_mode != GoBuildFace.UvMode.NONE:
			node._apply_auto_uv()
		node.bake_preview()
	elif _op.vertex_update_mode:
		node.bake_vertex_positions()
	else:
		if node.auto_uv_mode != GoBuildFace.UvMode.NONE:
			node._apply_auto_uv()
		node.bake()


# ---------------------------------------------------------------------------
# Internal — param drag
# ---------------------------------------------------------------------------

func _update_param_drag() -> void:
	var op: GoBuildDragOperation = _op
	var tracker_delta: float = _tracker.get_delta()
	var precision_mult: float = _tracker.get_precision_multiplier()
	var precision_offset: float = _tracker.get_precision_offset()

	var raw: float = op.param_start + precision_offset \
			+ tracker_delta * op.units_per_pixel * precision_mult
	var clamped: float = clampf(raw, op.param_min, op.param_max)
	var hit_bound: bool = clamped != raw
	if op.snap_to_start and absf(clamped - op.param_start) < op.snap_threshold:
		clamped = op.param_start

	op.param = clamped
	var denom: float = op.units_per_pixel * precision_mult
	if hit_bound and not is_zero_approx(denom):
		var consumed_delta: float = (clamped - op.param_start - precision_offset) / denom
		_tracker.fold_clamp_excess(consumed_delta)

	if not _overlay_only:
		_schedule_param_apply(op.node, op.param)


func _schedule_param_apply(node: GoBuildMeshInstance, target: float) -> void:
	_apply_node = node
	_apply_target_param = target
	if not _apply_scheduled:
		_apply_scheduled = true
		call_deferred("_flush_param_apply_deferred")


func _flush_param_apply_deferred() -> void:
	_apply_scheduled = false
	var node := _apply_node
	var target := _apply_target_param
	_apply_node = null
	if node == null or not is_instance_valid(node) or _op == null:
		return
	_do_param_apply(node, target)


func _do_param_apply(node: GoBuildMeshInstance, target: float) -> void:
	if _op == null:
		return
	node.go_build_mesh.restore_snapshot(_op.snapshot)
	_op.apply_fn.call(target)
	if node.auto_uv_mode != GoBuildFace.UvMode.NONE:
		node._apply_auto_uv()
	node.bake_preview()
	if _editor_plugin != null:
		_editor_plugin.update_overlays()


func _flush_param_apply_sync(node: GoBuildMeshInstance, target_param: float) -> void:
	_apply_scheduled = false
	_apply_node = null
	if _op == null:
		return
	node.go_build_mesh.restore_snapshot(_op.snapshot)
	_op.apply_fn.call(target_param)
	if node.auto_uv_mode != GoBuildFace.UvMode.NONE:
		node._apply_auto_uv()


# ---------------------------------------------------------------------------
# Internal — helpers
# ---------------------------------------------------------------------------

func _end() -> void:
	_tracker.end()
	_active = false
	_overlay_only = false
	_op = null
	_apply_scheduled = false
	_apply_node = null
	_apply_target_param = 0.0
	_apply_target_vec = Vector3.ZERO
	_raw_translate = Vector3.ZERO
	_raw_angle = 0.0
	_raw_scale = 1.0
	_raw_inset = 0.0
	_cached_camera = null


func _clear_deferred_state() -> void:
	_apply_scheduled = false
	_apply_node = null
	_apply_target_param = 0.0


## Compute the world-space extent of the selected vertices along the drag axis.
## Used as [member GoBuildDragOperation.initial_world_size] for scale strategies.
func _compute_initial_world_size(op: GoBuildDragOperation) -> void:
	op.initial_world_size = 1.0
	if op.node == null or not is_instance_valid(op.node):
		return
	if op.initial_vertex_positions.is_empty():
		return
	var min_p: float = INF
	var max_p: float = -INF
	var axis: Vector3
	match op.delta_mode:
		GoBuildDragOperation.DeltaMode.SCALE_AXIS:
			axis = _TRANSFORM_HELPERS_SCRIPT.get_local_axis(op.axis_index)
		GoBuildDragOperation.DeltaMode.SCALE_UNIFORM:
			axis = Vector3.ONE.normalized()
		_:
			return
	for idx: int in op.initial_vertex_positions:
		var proj: float = op.initial_vertex_positions[idx].dot(axis)
		if proj < min_p:
			min_p = proj
		if proj > max_p:
			max_p = proj
	var size: float = max_p - min_p
	if size < 1e-5:
		size = 1.0
	op.initial_world_size = size


func _capture_viewport_info() -> void:
	if not Engine.is_editor_hint():
		return
	var sv: SubViewport = EditorInterface.get_editor_viewport_3d(0)
	_overlay_vp_size = Vector2(1280, 720)
	if sv != null:
		var vp_parent := sv.get_parent() as Control
		if vp_parent != null:
			_overlay_vp_size = Vector2(vp_parent.size)
		if sv.get_camera_3d() != null:
			_cached_camera = sv.get_camera_3d()
	_overlay_anchor = _overlay_vp_size * 0.5


func _get_param_label() -> String:
	if _op == null:
		return ""
	return _op.overlay_label


func _gizmo_value_text() -> String:
	if _op == null:
		return ""
	if _op.delta_mode == GoBuildDragOperation.DeltaMode.INSET:
		return "inset %.3f" % _op._gizmo_cumulative_scale
	if _op.delta_mode == GoBuildDragOperation.DeltaMode.SCALE_AXIS \
			or _op.delta_mode == GoBuildDragOperation.DeltaMode.SCALE_UNIFORM:
		return "%.2fx" % _op._gizmo_cumulative_scale
	if _op.delta_mode == GoBuildDragOperation.DeltaMode.ROTATE:
		return "%.1f°" % rad_to_deg(_op._gizmo_cumulative_angle)
	var t: Vector3 = _op._gizmo_cumulative_translate
	return "Δ %.3f, %.3f, %.3f" % [t.x, t.y, t.z]