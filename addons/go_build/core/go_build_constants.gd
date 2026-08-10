## Shared visual constants for GoBuild gizmos and picking.
##
## Centralises values that must stay in sync between [GoBuildGizmo],
## [GoBuildGizmoPlugin], and [PickingHelper].  Any change here
## automatically propagates to all consumers.
class_name GoBuildConstants
extends RefCounted

## Scale factor for perspective cameras.
## Calibrated so that base sizes look correct at roughly 5 units from the
## gizmo centroid with the default 75° FOV.
const GIZMO_SCREEN_FACTOR: float = 0.25

## Scale factor for orthographic cameras (fraction of camera.size).
const GIZMO_ORTHO_SCALE: float = 0.10

## Half-size of the vertex cube widget in local mesh space.
const VERTEX_CUBE_HALF: float = 0.03

## Half-width ratio for selected-edge ribbons (relative to VERTEX_CUBE_HALF).
const EDGE_SELECTED_RIBBON_RATIO: float = 0.3

## Half-width ratio for unselected-edge ribbons (relative to VERTEX_CUBE_HALF).
## Used by picking to compute a pick radius; intentionally wider than the
## visual ribbon so edge picking is forgiving.
const EDGE_PICK_RIBBON_RATIO: float = 0.6