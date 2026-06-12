## Gizmo plugin — creates [GoBuildGizmo] instances and owns shared materials.
##
## Register with [method EditorPlugin.add_node_3d_gizmo_plugin] in [code]plugin.gd[/code].
## Materials are created once in [method setup] and reused by every gizmo instance.
@tool
class_name GoBuildGizmoPlugin
extends EditorNode3DGizmoPlugin

## Transform mode enum — controls which handles are drawn and which drag is applied.
## Switched by W (Translate), E (Rotate), R (Scale) intercepted in plugin.gd.
## Declared before all const to satisfy gdlint class-definitions-order (enum < const).
enum TransformMode { TRANSLATE = 0, ROTATE = 1, SCALE = 2 }

## Transform coordinate space — controls whether gizmo handles follow the
## object's local rotation (LOCAL) or stay aligned to world axes (WORLD).
enum TransformSpace { LOCAL = 0, WORLD = 1 }

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
const _MESH_INSTANCE_SCRIPT  := preload(_MESH_INSTANCE_SCRIPT_PATH)
const _DRAG_OP_SCRIPT        := preload("res://addons/go_build/core/go_build_drag_operation.gd")

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
## Cone geometry constants — kept in sync with the removed per-draw values
## that previously lived in GoBuildGizmo.  Centralised here because
## [method _build_unit_cone] is a static method on this class.
const _CONE_RADIUS:   float = 0.07
const _CONE_SEGMENTS: int   = 8
## Must match [constant GoBuildGizmo.SCALE_HANDLE_OFFSET].
const SCALE_HANDLE_OFFSET:  int   = 3_000_000
## Must match [constant GoBuildGizmo.PLANE_HANDLE_OFFSET].
## Planes: 0=XY (normal=Z, blue), 1=YZ (normal=X, red), 2=XZ (normal=Y, green).
const PLANE_HANDLE_OFFSET:  int   = 4_000_000
## Must match [constant GoBuildGizmo.VIEW_PLANE_HANDLE_ID].
const VIEW_PLANE_HANDLE_ID: int   = 5_000_000
## Centre handle for uniform (all-axis) scale.
## Must match [constant GoBuildGizmo.UNIFORM_SCALE_HANDLE_ID].
const UNIFORM_SCALE_HANDLE_ID: int = 6_000_000
## Offset of each planar-handle square's centre from the selection centroid,
## along each of its two axes (local mesh units × gizmo scale).
## Must match [constant GoBuildGizmo.PLANE_INNER_OFFSET].
const PLANE_INNER_OFFSET: float = 0.25
## Unit half-size for the canonical plane-quad meshes.
## Scaled by [code]PLANE_HALF * s[/code] at draw time.
## Must match [constant GoBuildGizmo.PLANE_HALF].
const PLANE_HALF: float     = 0.10
## Unit half-size for the canonical scale-cube mesh.
## Scaled by [code]SCALE_CUBE_HALF * s[/code] at draw time.
## Must match [constant GoBuildGizmo.SCALE_CUBE_HALF].
const SCALE_CUBE_HALF: float = 0.07
## Unit half-size for the viewport-plane drag-handle quad.
## Must match [constant GoBuildGizmo.VIEW_PLANE_HALF].
const VIEW_PLANE_HALF: float = 0.07

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
## Hover highlight materials — white, render_priority = 4, applied when the
## cursor is over a handle.  Read by [GoBuildGizmo._draw_transform_handles]
## via [method Object.get].
var mat_handle_hover_line: StandardMaterial3D
var mat_handle_hover_dot:  StandardMaterial3D
var mat_handle_hover_cone: StandardMaterial3D
## Semi-transparent planar-handle fill materials.
## [code]mat_plane_x[/code] = YZ plane (normal=X, colour=red).
## [code]mat_plane_y[/code] = XZ plane (normal=Y, colour=green).
## [code]mat_plane_z[/code] = XY plane (normal=Z, colour=blue).
var mat_plane_x: StandardMaterial3D
var mat_plane_y: StandardMaterial3D
var mat_plane_z: StandardMaterial3D
## Semi-transparent fill material for the viewport-plane drag handle (white/grey).
var mat_view_plane: StandardMaterial3D
## Solid mesh material for selected-edge ribbon quads (flat quad per edge).
## Used instead of add_lines for selected edges to achieve a visually thicker
## appearance; Godot 4 / Vulkan does not support line width > 1 px via add_lines.
var mat_edge_selected_ribbon: StandardMaterial3D

## Depth-tested variants for X-Ray off mode — unselected elements are occluded
## by the mesh.  Selected elements always use the no_depth_test versions.
var mat_edge_normal_depth:     StandardMaterial3D
var mat_edge_context_depth:    StandardMaterial3D
var mat_vertex_normal_depth:   StandardMaterial3D

## When true (default), vertex cubes and edge lines are always drawn on top of
## geometry (no_depth_test), making them visible even when occluded.  When false,
## unselected elements use depth-tested materials so they are hidden behind the
## mesh surface.  Selected elements are always drawn on top regardless.
var xray_mode: bool = true

## Active transform mode.  Defaults to TRANSLATE on plugin load.
## Written by plugin.gd when W/E/R is pressed; read by GoBuildGizmo via Object.get().
var transform_mode: TransformMode = TransformMode.TRANSLATE

## Current transform coordinate space (LOCAL or WORLD).
## When LOCAL, gizmo handles follow the object's rotation.
## When WORLD, handles stay aligned to world X/Y/Z axes.
var transform_space: TransformSpace = TransformSpace.LOCAL

## Cached unit-scale cone meshes — built once in [method setup] and reused by
## every [GoBuildGizmo._redraw] call via [method EditorNode3DGizmo.add_mesh]
## with a per-draw [Transform3D] for position and scale.
## Eliminates three [ArrayMesh] allocations + GPU uploads per redraw.
## Canonical geometry: base at local origin, apex at [code]axis * CONE_HEIGHT[/code],
## radius [code]_CONE_RADIUS[/code], using [code]_CONE_SEGMENTS[/code] around the base.
var cone_mesh_x: ArrayMesh
var cone_mesh_y: ArrayMesh
var cone_mesh_z: ArrayMesh

## Canonical plane-quad meshes (unit half-size = 1.0) — built once in [method setup].
## Each quad lies in the named plane (XY, YZ, XZ).  Scaled and positioned at draw time
## via [Transform3D] in [GoBuildGizmo._draw_plane_handles].
## Shared by the view-plane handle (which reuses the XY orientation).
var plane_quad_mesh_xy: ArrayMesh
var plane_quad_mesh_yz: ArrayMesh
var plane_quad_mesh_xz: ArrayMesh
## Canonical unit-half-size (1.0) axis-aligned solid cube mesh for scale handles.
## A single shared mesh — positioned and scaled per-axis at draw time.
var scale_cube_mesh: ArrayMesh

## Ctrl-snap step override.
var snap_step_override: float = -1.0
## Ctrl-snap step for rotation (degrees).
var rot_snap_override: float = 15.0
## Ctrl-snap step for scale ratio.
var scale_snap_override: float = 0.1
## Snap mode: world-grid (absolute) vs delta-grid (incremental).
var snap_mode_override: int = GoBuildDragOperation.SnapMode.WORLD_GRID

## Currently hovered transform handle ID, or [code]-1[/code] when no handle is
## under the cursor.  Written by [code]plugin.gd[/code] via [method _update_hover]
## during idle mouse motion; read by [GoBuildGizmo._draw_transform_handles] via
## [method Object.get] to select the hover highlight materials for that handle.
var _hovered_handle_id: int = -1

var _editor_plugin: EditorPlugin = null

## Deferred-gizmo-redraw state — coalesces multiple per-motion-event requests
## into a single [method Node3D.update_gizmos] call per rendered frame.
var _gizmo_redraw_pending_node: GoBuildMeshInstance = null
var _gizmo_redraw_scheduled: bool = false

func setup(plugin: EditorPlugin) -> void:
	_editor_plugin      = plugin
	# Unselected elements are drawn with no_depth_test so they are always visible
	# on top of the mesh surface.  Without this the vertex cubes and edge lines
	# are z-fighting with (or occluded by) the opaque mesh geometry — the vertex
	# positions are exactly ON the surface, so depth-testing makes them invisible.
	mat_edge_normal     = _line_mat_nodepth(Color(0.05, 0.05, 0.05, 1.0))   # near-black
	mat_edge_selected   = _line_mat_nodepth(COLOR_SELECTED)
	mat_edge_context    = _line_mat_nodepth(Color(0.4, 0.4, 0.4, 1.0))   # dimmer: context only
	# Vertex handles are now solid filled cubes — use _cone_mat (solid, no_depth_test,
	# double-sided) instead of _line_mat_nodepth.  Near-black for unselected, orange for selected.
	mat_vertex_normal   = _cone_mat(Color(0.05, 0.05, 0.05, 1.0))
	mat_vertex_selected = _cone_mat(COLOR_SELECTED)
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
	# Build canonical unit-scale cone meshes once.  GoBuildGizmo._draw_transform_handles
	# applies a per-draw Transform3D to position and scale them, avoiding the
	# three ArrayMesh allocations + GPU uploads that previously happened every _redraw().
	cone_mesh_x = _build_unit_cone(Vector3.RIGHT)
	cone_mesh_y = _build_unit_cone(Vector3.UP)
	cone_mesh_z = _build_unit_cone(Vector3.BACK)
	# Hover highlight materials — white, render_priority = 4 so they draw on
	# top of the normal axis-colour materials (priorities 2–3).
	mat_handle_hover_line = _line_mat_nodepth(Color.WHITE)
	mat_handle_hover_line.render_priority = 4
	mat_handle_hover_dot  = _point_mat(Color.WHITE)
	mat_handle_hover_dot.render_priority  = 4
	mat_handle_hover_cone = _cone_mat(Color.WHITE)
	mat_handle_hover_cone.render_priority = 4
	# Planar-handle fill materials — semi-transparent axis colours.
	mat_plane_x   = _plane_mat(COLOR_AXIS_X)
	mat_plane_y   = _plane_mat(COLOR_AXIS_Y)
	mat_plane_z   = _plane_mat(COLOR_AXIS_Z)
	mat_view_plane = _plane_mat(Color(0.9, 0.9, 0.9, 0.5))
	# Selected-edge ribbon material — solid orange, same as vertex/face selected colour.
	# Used for flat quad ribbons that give selected edges a visually thicker appearance.
	mat_edge_selected_ribbon = _cone_mat(COLOR_SELECTED)
	# Depth-tested material variants — used for unselected elements when xray_mode
	# is off.  Same colours as the no_depth_test versions but with depth test enabled
	# so elements behind the mesh surface are occluded.
	mat_edge_normal_depth   = _line_mat_depth(Color(0.05, 0.05, 0.05, 1.0))
	mat_edge_context_depth  = _line_mat_depth(Color(0.4, 0.4, 0.4, 1.0))
	mat_vertex_normal_depth = _cone_mat_depth(Color(0.05, 0.05, 0.05, 1.0))
	# Planar quad meshes (unit half-size 1.0 — scale at draw time by PLANE_HALF * s).
	plane_quad_mesh_xy = _build_plane_quad_mesh(Vector3.RIGHT, Vector3.UP)   # XY plane
	plane_quad_mesh_yz = _build_plane_quad_mesh(Vector3.UP, Vector3.BACK)    # YZ plane
	plane_quad_mesh_xz = _build_plane_quad_mesh(Vector3.RIGHT, Vector3.BACK) # XZ plane
	# Scale cube mesh (unit half-size 1.0 — scale at draw time by SCALE_CUBE_HALF * s).
	scale_cube_mesh = _build_scale_cube_mesh()

func _get_gizmo_name() -> String:
	return "GoBuild"


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
	if s != null and "go_build" in s.resource_path.to_lower():
		GoBuildDebug.log("[GoBuild] GIZMO_PLUGIN._has_gizmo  node=%s  script=%s  result=%s" \
				% [for_node_3d.name, s.resource_path, str(result)])
	elif "GoBuild" in for_node_3d.name:
		GoBuildDebug.log("[GoBuild] GIZMO_PLUGIN._has_gizmo  node=%s  script_null=%s  result=%s" \
				% [for_node_3d.name, str(s == null), str(result)])
	return result


func _create_gizmo(for_node_3d: Node3D) -> EditorNode3DGizmo:
	var s: Script = for_node_3d.get_script()
	var is_match: bool = s != null \
			and s.resource_path == _MESH_INSTANCE_SCRIPT_PATH
	if not is_match:
		return null
	if has_our_gizmo(for_node_3d):
		GoBuildDebug.log(
				"[GoBuild] GIZMO._create_gizmo SKIP (manual gizmo already attached) node=%s" \
				% for_node_3d.name)
		return null
	GoBuildDebug.log("[GoBuild] GIZMO_PLUGIN._create_gizmo  node=%s  CREATING" % for_node_3d.name)
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
	if handle_id >= VIEW_PLANE_HANDLE_ID:
		return "Move (View Plane)" if handle_id == VIEW_PLANE_HANDLE_ID else ""
	var idx: int
	if handle_id >= PLANE_HANDLE_OFFSET:
		idx = handle_id - PLANE_HANDLE_OFFSET
		const PLANE_NAMES = ["Move XY", "Move YZ", "Move XZ"]
		return PLANE_NAMES[idx] if idx < 3 else ""
	if handle_id >= SCALE_HANDLE_OFFSET:
		idx = handle_id - SCALE_HANDLE_OFFSET
		const SCALE_NAMES = ["Scale X", "Scale Y", "Scale Z"]
		return SCALE_NAMES[idx] if idx < 3 else ""
	if handle_id >= ROT_HANDLE_OFFSET:
		idx = handle_id - ROT_HANDLE_OFFSET
		const ROT_NAMES = ["Rotate X", "Rotate Y", "Rotate Z"]
		return ROT_NAMES[idx] if idx < 3 else ""
	idx = handle_id - AXIS_HANDLE_OFFSET
	if idx >= 0 and idx < 3:
		const MOVE_NAMES = ["Move X", "Move Y", "Move Z"]
		return MOVE_NAMES[idx]
	return ""


# ---------------------------------------------------------------------------
# Drag: capture initial state
# ---------------------------------------------------------------------------

## Schedule a deferred gizmo redraw for [param node], coalescing multiple
## per-motion-event requests into a single [method Node3D.update_gizmos] call
## per rendered frame.
func schedule_gizmo_redraw(node: GoBuildMeshInstance) -> void:
	_gizmo_redraw_pending_node = node
	if not _gizmo_redraw_scheduled:
		_gizmo_redraw_scheduled = true
		call_deferred("_flush_pending_gizmo_redraw")


func _flush_pending_gizmo_redraw() -> void:
	_gizmo_redraw_scheduled = false
	if _gizmo_redraw_pending_node != null and is_instance_valid(_gizmo_redraw_pending_node):
		_gizmo_redraw_pending_node.update_gizmos()
	_gizmo_redraw_pending_node = null


## Compatibility passthrough for tests and legacy callers.
## The implementation lives in [GoBuildTransformHelpers].
func _get_affected_vertex_indices(node: GoBuildMeshInstance) -> Array[int]:
	return GoBuildTransformHelpers.get_affected_vertex_indices(node)


## Compatibility passthrough for tests and legacy callers.
## The implementation lives in [GoBuildTransformHelpers].
func _get_local_axis(axis_idx: int) -> Vector3:
	return GoBuildTransformHelpers.get_local_axis(axis_idx)


## Compatibility passthrough for tests and legacy callers.
static func _ray_plane_intersect(
		ray_origin: Vector3,
		ray_dir: Vector3,
		plane_origin: Vector3,
		plane_normal: Vector3,
) -> Vector3:
	return GoBuildTransformHelpers.ray_plane_intersect(
		ray_origin, ray_dir, plane_origin, plane_normal)


## Compatibility passthrough for tests and legacy callers.
## Mirrors [method GoBuildTransformHelpers.get_snap_step] default behavior.
static func _get_snap_step() -> float:
	return GoBuildTransformHelpers.get_snap_step()


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

	var inv_basis: Basis = Basis()
	if transform_space == TransformSpace.WORLD:
		inv_basis = gt.basis.inverse()
	var axis_x := inv_basis * Vector3.RIGHT
	var axis_y := inv_basis * Vector3.UP
	var axis_z := inv_basis * Vector3.BACK

	var result: Array[Vector3] = [
		gt * (lc + axis_x * arr),                # translate X tip
		gt * (lc + axis_y * arr),                # translate Y tip
		gt * (lc + axis_z * arr),                # translate Z tip
		gt * (lc + axis_y * ring),               # rotate X ring dot
		gt * (lc + axis_z * ring),               # rotate Y ring dot
		gt * (lc + axis_x * ring),               # rotate Z ring dot
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



## Return the local-space centroid of the current selection on [param node].
## Returns [code]Vector3.ZERO[/code] when the selection is empty or no mesh exists.
## Used by [code]plugin.gd[/code] to compute planar-handle pick positions without
## duplicating the centroid calculation.
func get_selection_local_centroid(node: GoBuildMeshInstance) -> Vector3:
	var sel: SelectionManager = node.selection
	var gbm: GoBuildMesh = node.go_build_mesh
	if gbm == null or sel.is_empty():
		return Vector3.ZERO
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
				sum += gbm.vertices[edge.vertex_a] + gbm.vertices[edge.vertex_b]
				count += 2
		SelectionManager.Mode.FACE:
			for fidx: int in sel.get_selected_faces():
				for vidx: int in gbm.faces[fidx].vertex_indices:
					sum += gbm.vertices[vidx]
					count += 1
	return sum / count if count > 0 else Vector3.ZERO

## Build a canonical unit-scale cone [ArrayMesh] for [param axis_dir].
#### Canonical layout: base centre at the local origin, apex at
## [code]axis_dir * CONE_HEIGHT[/code], base radius [code]_CONE_RADIUS[/code].
## Built once per axis in [method setup] and cached in [member cone_mesh_x] /
## [member cone_mesh_y] / [member cone_mesh_z].
##
## [GoBuildGizmo._draw_transform_handles] applies a [Transform3D] at draw time
## — [code]Basis().scaled(Vector3.ONE * s)[/code] for the gizmo scale and a
## translation that puts the apex exactly at the arrow tip — rather than
## rebuilding the mesh each redraw.
static func _build_unit_cone(axis_dir: Vector3) -> ArrayMesh:
	var apex: Vector3       = axis_dir * CONE_HEIGHT
	var base_center         := Vector3.ZERO
	var raw_perp: Vector3   = axis_dir.cross(Vector3.UP)
	var perp1: Vector3
	if raw_perp.length_squared() < 0.001:
		perp1 = axis_dir.cross(Vector3.RIGHT).normalized()
	else:
		perp1 = raw_perp.normalized()
	var perp2: Vector3 = axis_dir.cross(perp1).normalized()

	var verts := PackedVector3Array()
	verts.resize(_CONE_SEGMENTS * 6)
	var vi := 0
	for i: int in _CONE_SEGMENTS:
		var a0: float = float(i)     / _CONE_SEGMENTS * TAU
		var a1: float = float(i + 1) / _CONE_SEGMENTS * TAU
		var rim0: Vector3 = base_center + (perp1 * cos(a0) + perp2 * sin(a0)) * _CONE_RADIUS
		var rim1: Vector3 = base_center + (perp1 * cos(a1) + perp2 * sin(a1)) * _CONE_RADIUS
		verts[vi]     = apex;        verts[vi + 1] = rim0;        verts[vi + 2] = rim1
		verts[vi + 3] = base_center; verts[vi + 4] = rim1;        verts[vi + 5] = rim0
		vi += 6

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


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


## Depth-tested line material — same as [method _line_mat_nodepth] but with
## depth test enabled so unselected edges are occluded by the mesh surface.
func _line_mat_depth(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color    = color
	mat.render_priority = 0
	return mat


## Depth-tested solid material — same as [method _cone_mat] but with depth test
## enabled so unselected vertex cubes are occluded by the mesh surface.
func _cone_mat_depth(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color    = color
	mat.cull_mode       = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 0
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


## Create a semi-transparent filled material for planar drag handles.
## Double-sided so the square is visible from both sides.  Alpha = 40 % so
## the mesh geometry shows through and the square reads as a drag zone.
func _plane_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color    = Color(color.r, color.g, color.b, 0.4)
	mat.transparency    = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode       = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test   = true
	mat.render_priority = 3
	return mat


## Build a canonical unit-half-size (corners at ±1) quad mesh in the plane
## defined by unit vectors [param u] and [param v].
## Scale and position at draw time via [Transform3D].
static func _build_plane_quad_mesh(u: Vector3, v: Vector3) -> ArrayMesh:
	var verts := PackedVector3Array([
		-u - v,  u - v,  u + v,
		-u - v,  u + v, -u + v,
	])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Build a canonical unit-half-size (corners at ±1) axis-aligned solid cube mesh.
## Used for the scale handles.  Scale and position at draw time via [Transform3D].
static func _build_scale_cube_mesh() -> ArrayMesh:
	var h: float = 1.0
	var verts := PackedVector3Array([
		# +X face
		Vector3(h,-h,-h), Vector3(h, h,-h), Vector3(h, h, h),
		Vector3(h,-h,-h), Vector3(h, h, h), Vector3(h,-h, h),
		# -X face
		Vector3(-h,-h, h), Vector3(-h, h, h), Vector3(-h, h,-h),
		Vector3(-h,-h, h), Vector3(-h, h,-h), Vector3(-h,-h,-h),
		# +Y face
		Vector3(-h, h,-h), Vector3(-h, h, h), Vector3(h, h, h),
		Vector3(-h, h,-h), Vector3(h, h, h), Vector3(h, h,-h),
		# -Y face
		Vector3(-h,-h, h), Vector3(-h,-h,-h), Vector3(h,-h,-h),
		Vector3(-h,-h, h), Vector3(h,-h,-h), Vector3(h,-h, h),
		# +Z face
		Vector3(-h,-h, h), Vector3(h,-h, h), Vector3(h, h, h),
		Vector3(-h,-h, h), Vector3(h, h, h), Vector3(-h, h, h),
		# -Z face
		Vector3(h,-h,-h), Vector3(-h,-h,-h), Vector3(-h, h,-h),
		Vector3(h,-h,-h), Vector3(-h, h,-h), Vector3(h, h,-h),
	])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

