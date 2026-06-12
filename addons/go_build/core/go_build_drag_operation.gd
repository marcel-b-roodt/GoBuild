@tool
class_name GoBuildDragOperation
extends RefCounted

## Data object describing a single interactive drag/parameter operation.
##
## Created by whatever code initiates the interaction (panel button, context menu,
## gizmo handle press) and handed to [GoBuildDragController] which owns the
## lifecycle: begin → update → commit/cancel.
##
## The controller reads the strategy, apply function, and configuration from this
## object; it never mutates it except for [member param] which is updated each frame.

enum DeltaMode {
	AXIS_PROJECT,
	PLANE_PROJECT,
	VIEWPORT_PLANE_PROJECT,
	ROTATE,
	SCALE_AXIS,
	SCALE_UNIFORM,
	INSET,
	PARAM_RADIAL,
	PARAM_LINEAR,
}

enum SnapMode { WORLD_GRID, DELTA_GRID }

# Self-preloads — dependency order.
const _MESH_INSTANCE_SCRIPT := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _TRANSFORM_HELPERS_SCRIPT := preload(
		"res://addons/go_build/core/go_build_transform_helpers.gd")

# Handle-ID range constants — must stay in sync with GoBuildGizmoPlugin.
const AXIS_HANDLE_OFFSET: int = 1_000_000
const ROT_HANDLE_OFFSET: int = 2_000_000
const SCALE_HANDLE_OFFSET: int = 3_000_000
const PLANE_HANDLE_OFFSET: int = 4_000_000
const VIEW_PLANE_HANDLE_ID: int = 5_000_000
const UNIFORM_SCALE_HANDLE_ID: int = 6_000_000

var node: GoBuildMeshInstance = null
var snapshot: Dictionary = {}
var apply_fn: Callable = Callable()

var action_name: String = ""
var overlay_label: String = "Value"

var delta_mode: DeltaMode = DeltaMode.PARAM_RADIAL

var param: float = 0.0
var param_start: float = 0.0
var param_min: float = 0.0
var param_max: float = INF

var units_per_pixel: float = 0.005
var scale_by_gizmo: bool = true

var snap_to_grid: bool = false
var snap_step: float = 1.0
var snap_mode: SnapMode = SnapMode.WORLD_GRID
var snap_to_start: bool = false
var snap_threshold: float = 0.04

var screen_direction: Vector2 = Vector2(1.0, 0.0)

var axis_index: int = 0
var plane_index: int = 0
var rotation_axis: Vector3 = Vector3.UP
var world_axis: Vector3 = Vector3.ZERO

## Transform coordinate space used for this drag (0 = LOCAL, 1 = WORLD).
## Set by [method create_for_gizmo_handle] from the gizmo plugin's
## [member GoBuildGizmoPlugin.transform_space].
var transform_space: int = 0

var inset_centroids: Dictionary = {}

var preview_mode: bool = false
var vertex_update_mode: bool = false

var vertex_indices: Array[int] = []
var initial_vertex_positions: Dictionary = {}

var drag_centroid: Vector3 = Vector3.ZERO

## Optional callback invoked after a successful commit (LMB accept).
## Signature: [code]() -> void[/code].
## Used to update the selection (e.g. select the new edges after extrude).
var post_commit_fn: Callable = Callable()

var handle_id: int = -1

## World-space size of the selected geometry along [member world_axis] at drag
## start.  Used by accumulated scale strategies to convert pixel offset to a
## scale ratio.  Computed from [member initial_vertex_positions] once at drag
## start.
var initial_world_size: float = 1.0

var _gizmo_cumulative_translate: Vector3 = Vector3.ZERO
var _gizmo_cumulative_angle: float = 0.0
var _gizmo_cumulative_scale: float = 1.0
var _gizmo_inset_offset: float = 0.0


## Return a default undo/redo action name for [param handle_id].
static func action_name_for_handle(handle_id: int) -> String:
	if handle_id >= UNIFORM_SCALE_HANDLE_ID:
		return "Scale Elements (Uniform)"
	if handle_id >= SCALE_HANDLE_OFFSET and handle_id < PLANE_HANDLE_OFFSET:
		return "Scale Elements"
	if handle_id >= ROT_HANDLE_OFFSET and handle_id < SCALE_HANDLE_OFFSET:
		return "Rotate Elements"
	return "Move Elements"


## Factory: create a [GoBuildDragOperation] for a gizmo handle drag.
##
## Populates delta_mode, world_axis, axis_index, snap_step, inset_centroids,
## and all other fields from the given handle ID and drag state.
## [param initial_verts] maps vertex indices to their local-space positions at
## drag start.  [param snapshot] is the full mesh snapshot for undo/redo.
## [param action_name_override] overrides the auto-generated action name.
## [param snap_step_default] is the default snap step (from editor settings).
## [param snap_step_rotate] is the snap step for rotate handles.
## [param snap_step_scale] is the snap step for scale handles.
## [param snap_mode] determines whether translate snap is world-grid (absolute)
## or delta-grid (incremental). See [enum SnapMode].
## [param inset_centroids] maps inner-ring vertex indices to face centroids.
## [param inset_offset] is the accumulated inset offset before drag start.
## [param vertex_update_mode] enables the fast vertex-only bake path.
## [param preview_mode] enables bake_preview instead of full bake during drag.
## [param transform_space] selects LOCAL (object-aligned) or WORLD (global axes)
## orientation for the drag.  When WORLD, axes use identity basis.
static func create_for_gizmo_handle(
		node: GoBuildMeshInstance,
		handle_id: int,
		initial_verts: Dictionary,
		snapshot: Dictionary,
		action_name_override: String,
		snap_step_default: float,
		snap_step_rotate: float,
		snap_step_scale: float,
		snap_mode: SnapMode,
		inset_centroids: Dictionary,
		inset_offset: float,
		vertex_update_mode: bool,
		preview_mode: bool,
		transform_space: int = 0,
) -> GoBuildDragOperation:
	if initial_verts.is_empty() or node == null:
		return null
	var op := GoBuildDragOperation.new()
	op.node = node
	op.snapshot = snapshot
	op.handle_id = handle_id
	op.initial_vertex_positions = initial_verts.duplicate()
	op.action_name = action_name_override
	op.vertex_update_mode = vertex_update_mode
	op.preview_mode = preview_mode
	op.inset_centroids = inset_centroids.duplicate()
	op._gizmo_inset_offset = inset_offset
	op.snap_step = snap_step_default
	op.snap_mode = snap_mode
	op.transform_space = transform_space

	var local_axes: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var use_basis: Basis = node.global_transform.basis
	if transform_space == 1:  # TransformSpace.WORLD
		use_basis = Basis()
	if handle_id >= UNIFORM_SCALE_HANDLE_ID:
		op.delta_mode = DeltaMode.SCALE_UNIFORM
	elif handle_id >= VIEW_PLANE_HANDLE_ID:
		op.delta_mode = DeltaMode.VIEWPORT_PLANE_PROJECT
	elif handle_id >= PLANE_HANDLE_OFFSET:
		var plane_idx: int = handle_id - PLANE_HANDLE_OFFSET
		op.delta_mode = DeltaMode.PLANE_PROJECT
		var plane_normals: Array[Vector3] = [Vector3.BACK, Vector3.RIGHT, Vector3.UP]
		op.world_axis = (use_basis * plane_normals[plane_idx]).normalized()
		op.plane_index = plane_idx
	elif handle_id >= SCALE_HANDLE_OFFSET:
		var axis_idx: int = handle_id - SCALE_HANDLE_OFFSET
		op.delta_mode = DeltaMode.SCALE_AXIS
		op.world_axis = (use_basis * local_axes[axis_idx]).normalized()
		op.axis_index = axis_idx
		op.snap_step = snap_step_scale
	elif handle_id >= ROT_HANDLE_OFFSET:
		var axis_idx: int = handle_id - ROT_HANDLE_OFFSET
		op.delta_mode = DeltaMode.ROTATE
		var local_axis: Vector3 = local_axes[axis_idx]
		op.world_axis = (use_basis * local_axis).normalized()
		op.axis_index = axis_idx
		op.snap_step = snap_step_rotate
	elif not inset_centroids.is_empty():
		op.delta_mode = DeltaMode.INSET
		op.snap_step = snap_step_scale
	else:
		var axis_idx: int = handle_id - AXIS_HANDLE_OFFSET
		op.delta_mode = DeltaMode.AXIS_PROJECT
		op.world_axis = (use_basis * local_axes[axis_idx]).normalized()
		op.axis_index = axis_idx

	op.drag_centroid = _compute_centroid_from_verts(initial_verts)
	return op


static func _compute_centroid_from_verts(verts: Dictionary) -> Vector3:
	if verts.is_empty():
		return Vector3.ZERO
	var sum: Vector3 = Vector3.ZERO
	for idx: int in verts:
		sum += verts[idx]
	return sum / verts.size()