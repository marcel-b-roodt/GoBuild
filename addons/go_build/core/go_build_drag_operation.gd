## Data object describing a single interactive drag/parameter operation.
##
## Replaces both [GoBuildParamPreview] (button-triggered param operations) and
## the ad-hoc drag state in [GoBuildDragHandler] (gizmo-handle drags).
## A [GoBuildDragOperation] is created by whatever code initiates the interaction
## (panel button, context menu, gizmo handle press) and handed to
## [GoBuildDragController] which owns the lifecycle: begin → update → commit/cancel.
##
## The controller reads the strategy, apply function, and configuration from this
## object; it never mutates it except for [member param] which is updated each frame.
@tool
class_name GoBuildDragOperation
extends RefCounted

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

# Self-preloads — dependency order.
const _MESH_INSTANCE_SCRIPT := preload("res://addons/go_build/core/go_build_mesh_instance.gd")

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
var snap_to_start: bool = false
var snap_threshold: float = 0.04

var screen_direction: Vector2 = Vector2(1.0, 0.0)

var axis_index: int = 0
var plane_index: int = 0
var rotation_axis: Vector3 = Vector3.UP
var world_axis: Vector3 = Vector3.ZERO

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