## Interactive parameter-preview state for a configurable mesh operation.
##
## Created by [GoBuildPanel] when the user presses an operation button that
## supports live-parameter adjustment (Bevel, Extrude, Loop Cut, etc.).
## Passed to [method plugin.begin_param_preview], which:
##   1. Fills in [member node] and [member snapshot] from the active edited node.
##   2. Scales [member units_per_pixel] by the gizmo scale factor unless
##      [member scale_by_gizmo] is [code]false[/code].
##   3. Immediately calls [member apply_fn] with [member param_start] so the
##      default result is visible before the user drags.
##   4. Passes the object to [SelectionInputController] which drives subsequent
##      mouse-motion updates, commit (LMB), and cancel (RMB / Escape).
##
## Mouse-to-parameter mapping:
##   [code]param = clamp(param_start
##       + dot(accumulated_motion, screen_direction) × units_per_pixel,
##       param_min, param_max)[/code]
## [member screen_direction] defaults to [code]Vector2(1,0)[/code] (horizontal),
## which reproduces the legacy behaviour for all radial / horizontal operations.
@tool
class_name GoBuildParamPreview
extends RefCounted

# Self-preloads — dependency order.
const _MESH_INSTANCE_SCRIPT := preload("res://addons/go_build/core/go_build_mesh_instance.gd")

## Mesh node being modified.  Filled by [code]plugin.begin_param_preview[/code].
var node: GoBuildMeshInstance = null
## Deep snapshot of the mesh taken before the preview started.
## Filled by [code]plugin.begin_param_preview[/code].
## Used to restore the mesh on every mouse-motion update and on cancel.
var snapshot: Dictionary = {}

## Callable with signature [code](param: float) -> void[/code].
## Should apply the operation to [member node]'s mesh using [param param].
## Must call [method GoBuildMesh.rebuild_edges] internally if topology changes.
var apply_fn: Callable = Callable()
## Undo/redo action label pushed when the preview is committed (LMB).
var action_name: String = ""
## Short label shown in the viewport overlay (e.g. "Width", "Distance", "Position").
var param_label: String = "Value"

## Current parameter value — updated continuously during mouse motion.
var param: float = 0.0
## Parameter value applied immediately when the preview starts.
var param_start: float = 0.0
## Minimum allowed parameter value (clamped before calling apply_fn).
var param_min: float = 0.0
## Maximum allowed parameter value (clamped before calling apply_fn).
var param_max: float = INF

## Baseline units-of-param change per horizontal screen pixel.
## When [member scale_by_gizmo] is [code]true[/code] (default),
## [code]plugin.begin_param_preview[/code] multiplies this by the
## current gizmo scale factor for scene-consistent sensitivity.
## For normalised parameters (e.g. loop-cut position 0–1) set
## [member scale_by_gizmo] to [code]false[/code] and tune this directly.
var units_per_pixel: float = 0.005
## Whether [code]plugin.begin_param_preview[/code] should multiply
## [member units_per_pixel] by the active gizmo scale.
## Set to [code]false[/code] for normalised (0–1) parameters such as
## loop-cut position, where world scale is irrelevant.
var scale_by_gizmo: bool = true

## When [code]true[/code] and the current param is within
## [member snap_threshold] of [member param_start], snap exactly to
## param_start.  Useful for loop-cut midpoint snapping.
var snap_to_start: bool = false
## Distance from [member param_start] within which the snap fires.
var snap_threshold: float = 0.04
## When [code]true[/code] (default), the parameter is driven by Euclidean
## distance from the anchor in any drag direction (radial mode — dragging
## further from centre always increases the value).
## Set [code]false[/code] for signed linear operations such as Loop Cut
## position where left / right direction is semantically meaningful.
var radial: bool = true
## Normalised screen-space drag direction for linear (non-radial) mode.
## The parameter delta equals [code]dot(cursor_offset, screen_direction) × units_per_pixel[/code].
## Defaults to [code]Vector2(1, 0)[/code] (horizontal).
## Set to the normalised screen-space projection of the seed edge so that
## dragging along the edge direction moves the cut in the correct direction
## regardless of whether the edge runs horizontally, vertically, or diagonally.
var screen_direction: Vector2 = Vector2(1.0, 0.0)

## Optional callback invoked after a successful commit (LMB accept).
## Signature: [code]() -> void[/code].
## Used to update the selection (e.g. select the new edges after extrude).
var post_commit_fn: Callable = Callable()
