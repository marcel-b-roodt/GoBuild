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

## Active transform mode.  Defaults to TRANSLATE on plugin load.
## Written by plugin.gd when W/E/R is pressed; read by GoBuildGizmo via Object.get().
var transform_mode: TransformMode = TransformMode.TRANSLATE

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

## Currently hovered transform handle ID, or [code]-1[/code] when no handle is
## under the cursor.  Written by [code]plugin.gd[/code] via [method _update_hover]
## during idle mouse motion; read by [GoBuildGizmo._draw_transform_handles] via
## [method Object.get] to select the hover highlight materials for that handle.
var _hovered_handle_id: int = -1

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

## Deferred-bake state ─────────────────────────────────────────────────────
## During a drag, InputEventMouseMotion can fire many times per engine frame.
## Calling node.bake() (full ArrayMesh rebuild + GPU upload) on every event is
## the primary source of frame hitches.  Instead we set a dirty flag and let
## _flush_pending_bake coalesce all per-event mutations into a single bake at
## end-of-frame.  The pending node reference is cleared at commit / cancel so
## a stale flush cannot overwrite a restored or committed mesh state.
var _bake_pending_node: GoBuildMeshInstance = null
var _bake_scheduled:    bool = false
## When true, _flush_pending_bake routes to bake_vertex_positions() instead of
## bake().  Set by begin_drag (vertex positions are the only thing changing);
## cleared by reset_drag_state so the commit/cancel full-bake is never skipped.
## bake_vertex_positions() leaves normals stale — always call bake() on commit.
var _drag_vertex_update_mode: bool = false

## Deferred-gizmo-redraw state ──────────────────────────────────────────────
## Mirrors the deferred-bake pattern above but for update_gizmos().
## _redraw() builds PackedVector3Arrays for all edges/vertices and calls
## add_mesh with new ArrayMesh objects (cones) on every invocation — expensive
## when called per-motion-event during a drag.  Coalescing to once per frame
## keeps the overlay responsive without the per-event allocation cost.
## Non-drag callers (selection changes, mode switches) call update_gizmos()
## directly and bypass this throttle — they need an immediate redraw.
var _gizmo_redraw_pending_node: GoBuildMeshInstance = null
var _gizmo_redraw_scheduled:    bool = false

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
	# Planar quad meshes (unit half-size 1.0 — scale at draw time by PLANE_HALF * s).
	plane_quad_mesh_xy = _build_plane_quad_mesh(Vector3.RIGHT, Vector3.UP)   # XY plane
	plane_quad_mesh_yz = _build_plane_quad_mesh(Vector3.UP, Vector3.BACK)    # YZ plane
	plane_quad_mesh_xz = _build_plane_quad_mesh(Vector3.RIGHT, Vector3.BACK) # XZ plane
	# Scale cube mesh (unit half-size 1.0 — scale at draw time by SCALE_CUBE_HALF * s).
	scale_cube_mesh = _build_scale_cube_mesh()


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
	if handle_id >= ROT_HANDLE_OFFSET and handle_id < SCALE_HANDLE_OFFSET:
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

	if handle_id >= VIEW_PLANE_HANDLE_ID:
		_apply_viewport_plane_drag(node, camera, screen_pos)
	elif handle_id >= PLANE_HANDLE_OFFSET:
		_apply_plane_drag(node, handle_id - PLANE_HANDLE_OFFSET, camera, screen_pos)
	elif handle_id >= SCALE_HANDLE_OFFSET:
		_apply_scale_drag(node, handle_id - SCALE_HANDLE_OFFSET, camera, screen_pos)
	elif handle_id >= ROT_HANDLE_OFFSET:
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

	# Clear the deferred-bake queue before any explicit bake below.
	_bake_pending_node = null
	_bake_scheduled    = false
	# Clear deferred gizmo redraw — explicit update_gizmos calls below cover it.
	_gizmo_redraw_pending_node = null
	_gizmo_redraw_scheduled    = false

	if cancel:
		node.restore_and_bake(restore as Dictionary)
		node.update_gizmos()
	elif _drag_initial_t != INF:
		node.bake()   # ensure final dragged state is visible before snapshot
		var snapshot_after: Dictionary = node.go_build_mesh.take_snapshot()
		var ur: EditorUndoRedoManager = _editor_plugin.get_undo_redo()
		var action_name: String = _drag_action_name(handle_id)
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
	_drag_vertex_update_mode = false
	# Clear deferred-bake state.  Any queued _flush_pending_bake call will
	# find _bake_pending_node == null and exit without baking.
	_bake_pending_node = null
	_bake_scheduled    = false
	# Clear deferred-gizmo-redraw state for the same reason.
	_gizmo_redraw_pending_node = null
	_gizmo_redraw_scheduled    = false


## Schedule a deferred mesh bake for [param node], coalescing multiple
## per-motion-event requests into a single bake per rendered frame.
##
## During a fast drag, [InputEventMouseMotion] can fire several times between
## engine frames.  Calling [method GoBuildMeshInstance.bake] on each event
## rebuilds the full [ArrayMesh] and uploads it to the GPU — O(faces) per event.
## This method sets a dirty flag and defers the bake to end-of-frame via
## [method Object.call_deferred], where vertex data has settled to its
## per-frame final position.  Vertex positions and the gizmo overlay are
## still updated every event for responsive feedback.
func _schedule_bake(node: GoBuildMeshInstance) -> void:
	_bake_pending_node = node
	if not _bake_scheduled:
		_bake_scheduled = true
		call_deferred("_flush_pending_bake")


## Flush a pending deferred bake.  Invoked at end-of-frame via call_deferred.
## Guards against a stale flush after commit / cancel by checking
## [member _bake_pending_node] — cleared by [method commit_drag] and
## [method reset_drag_state] before the deferred call fires.
##
## During an active drag ([member _drag_vertex_update_mode] is true), routes to
## [method GoBuildMeshInstance.bake_vertex_positions] — updates only the GPU
## vertex buffer, leaving normals and UVs unchanged.  This avoids the full
## [ArrayMesh] rebuild and cuts GPU upload cost to vertex-positions-only.
## [method commit_drag] always performs a full [method GoBuildMeshInstance.bake]
## afterward to restore correct normals.
func _flush_pending_bake() -> void:
	_bake_scheduled = false
	if _bake_pending_node != null and is_instance_valid(_bake_pending_node):
		if _drag_vertex_update_mode:
			_bake_pending_node.bake_vertex_positions()
		else:
			_bake_pending_node.bake()
	_bake_pending_node = null


## Schedule a deferred gizmo redraw for [param node], coalescing multiple
## per-motion-event requests into a single [method Node3D.update_gizmos] call
## per rendered frame.
##
## [method Node3D.update_gizmos] triggers [method GoBuildGizmo._redraw], which
## allocates [PackedVector3Array] objects for all edges and vertex cubes, and
## calls [method EditorNode3DGizmo.add_mesh] with freshly-built cone meshes
## (3 × [ArrayMesh]) on every invocation.  Calling this per-motion-event during
## a drag causes continuous GDScript allocation pressure and GPU resource churn.
##
## Only use this from the drag hot-path in [code]plugin.gd[/code].  Non-drag
## callers (selection changes, mode switches, cancel) should call
## [method Node3D.update_gizmos] directly — they need an immediate redraw.
func schedule_gizmo_redraw(node: GoBuildMeshInstance) -> void:
	_gizmo_redraw_pending_node = node
	if not _gizmo_redraw_scheduled:
		_gizmo_redraw_scheduled = true
		call_deferred("_flush_pending_gizmo_redraw")


## Flush a pending deferred gizmo redraw.  Invoked at end-of-frame via call_deferred.
## Guards against a stale flush after commit / cancel / reset by checking
## [member _gizmo_redraw_pending_node].
func _flush_pending_gizmo_redraw() -> void:
	_gizmo_redraw_scheduled = false
	if _gizmo_redraw_pending_node != null and is_instance_valid(_gizmo_redraw_pending_node):
		_gizmo_redraw_pending_node.update_gizmos()
	_gizmo_redraw_pending_node = null


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

	if handle_id >= ROT_HANDLE_OFFSET and handle_id < SCALE_HANDLE_OFFSET:
		var local_axis: Vector3 = _get_local_axis(handle_id - ROT_HANDLE_OFFSET)
		_drag_world_axis = (node.global_transform.basis * local_axis).normalized()

	_drag_restore = node.go_build_mesh.take_snapshot()
	# Engage the fast vertex-position-only bake path for the duration of this drag.
	# _flush_pending_bake will call bake_vertex_positions() each frame instead of
	# the full bake(), saving the ArrayMesh rebuild and full GPU upload cost.
	# reset_drag_state() clears this flag; commit_drag() always does a full bake()
	# before calling reset_drag_state() so the final mesh has correct normals.
	_drag_vertex_update_mode = true
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
	if handle_id >= VIEW_PLANE_HANDLE_ID:
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
## On [param cancel], restores the mesh to the snapshot taken in [method begin_drag].
## On confirm, pushes a single undo/redo action.
func commit_drag(node: GoBuildMeshInstance, handle_id: int, cancel: bool) -> void:
	if handle_id < AXIS_HANDLE_OFFSET or node == null:
		return

	# Clear the deferred-bake queue — we handle baking explicitly below so the
	# final visual state is guaranteed correct regardless of frame timing.
	# The queued _flush_pending_bake call will see _bake_pending_node == null
	# and exit without touching the mesh.
	_bake_pending_node = null
	_bake_scheduled    = false
	# Clear the deferred-gizmo-redraw queue for the same reason — the explicit
	# update_gizmos() calls below cover the post-commit redraw.
	_gizmo_redraw_pending_node = null
	_gizmo_redraw_scheduled    = false

	if cancel:
		node.restore_and_bake(_drag_restore)
		node.update_gizmos()
	elif _drag_initial_t != INF:
		# Explicitly bake the final dragged vertex state before snapshotting.
		node.bake()
		var snapshot_after: Dictionary = node.go_build_mesh.take_snapshot()
		var ur: EditorUndoRedoManager = _editor_plugin.get_undo_redo()
		var action_name: String = _drag_action_name(handle_id)
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
## When Ctrl is held, snaps the scalar travel distance to [method _get_snap_step].
## When V is held, snaps the centroid to the nearest non-dragged mesh vertex,
## projected onto the drag axis (vertex snap).
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
	if Input.is_key_pressed(KEY_V):
		var snap_world: Vector3 = _find_vertex_snap_world_pos(node, camera, screen_pos)
		if snap_world != Vector3.INF:
			var t_delta: float = (snap_world - world_centroid).dot(world_axis)
			var delta_local: Vector3 = \
					node.global_transform.basis.inverse() * (world_axis * t_delta)
			for idx: int in _drag_initial_verts:
				gbm.vertices[idx] = _drag_initial_verts[idx] + delta_local
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
	var delta_world: Vector3 = world_axis * t_delta
	var delta_local: Vector3 = node.global_transform.basis.inverse() * delta_world

	for idx: int in _drag_initial_verts:
		gbm.vertices[idx] = _drag_initial_verts[idx] + delta_local

	# Defer the full mesh bake to end-of-frame so multiple motion events
	# per frame coalesce into a single ArrayMesh rebuild + GPU upload.
	# The gizmo overlay (update_gizmos) is called by the plugin.gd caller.
	_schedule_bake(node)


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

	# Defer bake — same throttle as _apply_translate_drag.
	_schedule_bake(node)


## Apply a planar drag for [param plane_idx] (0=XY, 1=YZ, 2=XZ) to all cached
## vertices.  Projects the mouse ray onto the world-space plane that passes through
## the selection centroid with the matching local normal axis, then translates
## vertices by the delta from the first-frame hit point.
## [b]Ctrl held[/b] snaps each component of the world-space delta to the editor
## grid step via [method _get_snap_step].
## [b]V held[/b] snaps the centroid to the nearest non-dragged mesh vertex,
## constrained to move only within the drag plane.
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
	if Input.is_key_pressed(KEY_V):
		var snap_world: Vector3 = _find_vertex_snap_world_pos(node, camera, screen_pos)
		if snap_world != Vector3.INF:
			var raw_delta: Vector3 = snap_world - world_centroid
			raw_delta -= world_normal * raw_delta.dot(world_normal)
			var delta_local: Vector3 = node.global_transform.basis.inverse() * raw_delta
			for idx: int in _drag_initial_verts:
				gbm.vertices[idx] = _drag_initial_verts[idx] + delta_local
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
	var delta_local: Vector3 = node.global_transform.basis.inverse() * delta_world
	for idx: int in _drag_initial_verts:
		gbm.vertices[idx] = _drag_initial_verts[idx] + delta_local
	_schedule_bake(node)


## Apply a per-axis scale drag for [param axis_idx] to all cached vertices.
## Projects the mouse ray onto the axis, computes a scale ratio from the initial
## projection, and scales the per-axis displacement of each vertex from the centroid.
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
	for idx: int in _drag_initial_verts:
		var local_pos: Vector3 = _drag_initial_verts[idx] - local_centroid
		# Scale only the component along the dragged axis; keep perpendicular unchanged.
		var along: float   = local_pos.dot(local_axis)
		var perp: Vector3  = local_pos - local_axis * along
		gbm.vertices[idx]  = local_centroid + perp + local_axis * along * scale_ratio
	_schedule_bake(node)


## Apply a viewport-plane drag to all cached vertices.
## On the first call, records the camera forward vector as the plane normal and
## the initial mouse-plane intersection as the drag origin ([member _drag_start_dir]).
## Subsequent calls translate the selection by [code]hit - _drag_start_dir[/code].
## [b]Ctrl held[/b] snaps the world-space delta to the editor grid step.
## [b]V held[/b] snaps the centroid to the nearest non-dragged mesh vertex,
## constrained to stay in the camera plane (depth component removed).
func _apply_viewport_plane_drag(
		node: GoBuildMeshInstance,
		camera: Camera3D,
		screen_pos: Vector2,
) -> void:
	var gbm: GoBuildMesh        = node.go_build_mesh
	var local_centroid: Vector3 = _compute_drag_centroid()
	var world_centroid: Vector3 = node.global_transform * local_centroid

	# Vertex snap (V held): move centroid to the nearest non-dragged vertex,
	# removing the depth component so movement stays in the camera plane.
	if Input.is_key_pressed(KEY_V):
		var snap_world: Vector3 = _find_vertex_snap_world_pos(node, camera, screen_pos)
		if snap_world != Vector3.INF:
			var cam_forward: Vector3 = -camera.global_transform.basis.z
			var raw_delta: Vector3   = snap_world - world_centroid
			raw_delta -= cam_forward * raw_delta.dot(cam_forward)
			var delta_local: Vector3 = node.global_transform.basis.inverse() * raw_delta
			for idx: int in _drag_initial_verts:
				gbm.vertices[idx] = _drag_initial_verts[idx] + delta_local
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
	var delta_local: Vector3 = node.global_transform.basis.inverse() * delta_world
	for idx: int in _drag_initial_verts:
		gbm.vertices[idx] = _drag_initial_verts[idx] + delta_local
	_schedule_bake(node)


## Return the undo/redo action name for [param handle_id].
func _drag_action_name(handle_id: int) -> String:
	if handle_id >= SCALE_HANDLE_OFFSET and handle_id < PLANE_HANDLE_OFFSET:
		return "Scale Elements"
	if handle_id >= ROT_HANDLE_OFFSET and handle_id < SCALE_HANDLE_OFFSET:
		return "Rotate Elements"
	return "Move Elements"


## Return the grid-snap step from EditorSettings ([code]editors/3d/grid_step[/code]).
## Falls back to [code]1.0[/code] if the key is absent or the editor is not running.
static func _get_snap_step() -> float:
	if not Engine.is_editor_hint():
		return 1.0
	var es: EditorSettings = EditorInterface.get_editor_settings()
	if es.has_setting("editors/3d/grid_step"):
		return maxf(float(es.get_setting("editors/3d/grid_step")), 0.001)
	return 1.0


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


## Return the arithmetic mean of the cached initial vertex positions.
func _compute_drag_centroid() -> Vector3:
	var c := Vector3.ZERO
	for idx: int in _drag_initial_verts:
		c += _drag_initial_verts[idx]
	return c / _drag_initial_verts.size()


## Find the world-space position of the mesh vertex nearest to [param screen_pos]
## (measured in screen-space pixels), excluding vertices currently being dragged.
##
## Skips vertices whose index is in [member _drag_initial_verts] so the snap
## target is always a vertex OTHER than the ones being moved — i.e. the user
## snaps TO a fixed vertex, not to themselves.
##
## Returns [code]Vector3.INF[/code] if no eligible vertex is visible (e.g. the
## entire mesh is selected and all vertices are being dragged).
##
## Used by the vertex-snap branch ([kbd]V[/kbd] modifier) inside
## [method _apply_translate_drag], [method _apply_plane_drag], and
## [method _apply_viewport_plane_drag].
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
			continue   # Do not snap to the dragged vertices themselves.
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


## Build a canonical unit-scale cone [ArrayMesh] for [param axis_dir].
##
## Canonical layout: base centre at the local origin, apex at
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

