## Handles all viewport mouse input for GoBuild: handle picking, handle drags,
## box selection, hover highlight, right-click context menu, and the
## Shift+drag → Extrude shortcut.
##
## Created and owned by [code]plugin.gd[/code].  Receives events forwarded from
## [method EditorPlugin._forward_3d_gui_input] after keyboard handling.
## Holds all drag/box-select/right-click state so [code]plugin.gd[/code] stays
## focused on editor lifecycle, signals, and overlay drawing.
@tool
class_name SelectionInputController
extends RefCounted

# Self-preloads — dependency order:
const _SEL_MGR_SCRIPT       := preload("res://addons/go_build/core/selection_manager.gd")
const _PICKING_HELPER_SCRIPT := preload("res://addons/go_build/core/picking_helper.gd")
const _MESH_INSTANCE_SCRIPT := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _GIZMO_PLUGIN_SCRIPT  := preload("res://addons/go_build/core/go_build_gizmo_plugin.gd")
const _PANEL_SCRIPT         := preload("res://addons/go_build/core/go_build_panel.gd")
const _EXTRUDE_SCRIPT       := preload(
		"res://addons/go_build/mesh/operations/extrude_operation.gd")
const _INSET_SCRIPT         := preload(
		"res://addons/go_build/mesh/operations/inset_operation.gd")

# ---------------------------------------------------------------------------
# Constants (were in plugin.gd)
# ---------------------------------------------------------------------------

## Squared pixel distance a left-drag must travel before it becomes a box select.
const BOX_SELECT_DRAG_THRESHOLD_SQ: float = 25.0  # 5 px

## Screen-space pixel radius for translate cone handle hit-testing.
const _TRANSLATE_HANDLE_PICK_RADIUS_PX: float = 10.0
## Squared screen-space pixel radius for rotate-ring hit-testing.
const _ROTATE_HANDLE_PICK_RADIUS_SQ: float  = 144.0  # 12 px
## Squared screen-space pixel radius for scale cube handle hit-testing.
const _SCALE_HANDLE_PICK_RADIUS_SQ: float   = 144.0  # 12 px
## Squared screen-space pixel radius for planar handle hit-testing.
const _PLANE_HANDLE_PICK_RADIUS_SQ: float   = 225.0  # 15 px
## Squared screen-space pixel radius for viewport-plane handle hit-testing.
const _VIEW_PLANE_PICK_RADIUS_SQ: float     = 196.0  # 14 px

# ---------------------------------------------------------------------------
# External references (set by setup())
# ---------------------------------------------------------------------------

var _gizmo_plugin: GoBuildGizmoPlugin = null
var _panel: GoBuildPanel              = null
var _editor_plugin: EditorPlugin      = null

# ---------------------------------------------------------------------------
# Box-select state
# ---------------------------------------------------------------------------

var _box_select_started: bool    = false
var _box_select_active:  bool    = false
var _box_select_start:   Vector2 = Vector2.ZERO
var _box_select_current: Vector2 = Vector2.ZERO

# ---------------------------------------------------------------------------
# Handle-drag state
# ---------------------------------------------------------------------------

## True once the drag threshold has been crossed and a handle drag is live.
var _dragging_handle:   bool    = false
## ID of the handle currently being dragged.
var _active_handle_id:  int     = -1
## ID of the handle that was pressed but may not yet have started dragging.
var _pressed_handle_id: int     = -1
## Screen position of the mouse-down that started the pending press.
var _handle_press_pos:  Vector2 = Vector2.ZERO

# ---------------------------------------------------------------------------
# Right-click context-menu state
# ---------------------------------------------------------------------------

var _right_click_press_pos: Vector2 = Vector2.ZERO
var _right_click_dragged:   bool    = false


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Call immediately after construction, before any [method process_input] calls.
func setup(
		gizmo_plugin: GoBuildGizmoPlugin,
		panel: GoBuildPanel,
		editor_plugin: EditorPlugin,
) -> void:
	_gizmo_plugin  = gizmo_plugin
	_panel         = panel
	_editor_plugin = editor_plugin


# ---------------------------------------------------------------------------
# Public API — called from plugin.gd
# ---------------------------------------------------------------------------

## Main entry point.  Forward events here from [method EditorPlugin._forward_3d_gui_input]
## after keyboard handling.  Returns 1 to consume the event, 0 to pass through.
func process_input(
		edited_node: GoBuildMeshInstance,
		camera: Camera3D,
		event: InputEvent,
) -> int:
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			if not _right_click_dragged and \
					_right_click_press_pos.distance_squared_to(mm.position) \
					> BOX_SELECT_DRAG_THRESHOLD_SQ:
				_right_click_dragged = true
			return 0
		return _handle_mouse_motion(edited_node, camera, mm)
	if event is InputEventMouseButton:
		return _handle_mouse_button(edited_node, camera, event as InputEventMouseButton)
	return 0


## Draw the box-select rectangle.  Call from [method EditorPlugin._forward_3d_draw_over_viewport].
func draw_overlay(overlay: Control) -> void:
	if not _box_select_active:
		return
	var rect: Rect2 = _get_box_select_rect()
	overlay.draw_rect(rect, Color(0.25, 0.45, 0.8, 0.15), true)
	overlay.draw_rect(rect, Color(0.5, 0.7, 1.0, 0.85), false)


## Cancel any in-progress handle drag.  Safe to call when idle.
func cancel_drag(edited_node: GoBuildMeshInstance) -> void:
	_cancel_active_drag(edited_node)


## Clear the hovered-handle highlight.
func clear_hover(edited_node: GoBuildMeshInstance) -> void:
	_clear_hover(edited_node)


## Cancel box select and refresh overlays/gizmos.
func cancel_box_select(edited_node: GoBuildMeshInstance) -> void:
	_cancel_box_select(edited_node)


## True while a handle drag is live.
func has_active_drag() -> bool:
	return _dragging_handle


## True while a handle press is pending (before drag threshold is crossed).
func has_active_press() -> bool:
	return _pressed_handle_id != -1


# ---------------------------------------------------------------------------
# Mouse button dispatch
# ---------------------------------------------------------------------------

func _handle_mouse_button(
		edited_node: GoBuildMeshInstance,
		camera: Camera3D,
		mb: InputEventMouseButton,
) -> int:
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		if mb.pressed:
			_cancel_active_drag(edited_node)
			_cancel_box_select(edited_node)
			_right_click_press_pos = mb.position
			_right_click_dragged   = false
		elif not _right_click_dragged:
			_show_context_menu(edited_node, mb.position)
		return 0
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			return _handle_mouse_press(edited_node, camera, mb)
		return _handle_mouse_release(edited_node, camera, mb)
	return 0


func _handle_mouse_press(
		edited_node: GoBuildMeshInstance,
		camera: Camera3D,
		mb: InputEventMouseButton,
) -> int:
	var mode: SelectionManager.Mode = edited_node.selection.get_mode()
	if mode == SelectionManager.Mode.OBJECT:
		return 0
	var hit_id: int = _find_hovered_handle_id(edited_node, camera, mb.position)
	if hit_id != -1:
		_pressed_handle_id = hit_id
		_handle_press_pos  = mb.position
		return 1
	_box_select_started = true
	_box_select_active  = false
	_box_select_start   = mb.position
	_box_select_current = mb.position
	return 1


func _handle_mouse_release(
		edited_node: GoBuildMeshInstance,
		camera: Camera3D,
		mb: InputEventMouseButton,
) -> int:
	if _dragging_handle:
		_gizmo_plugin.commit_drag(edited_node, _active_handle_id, false)
		_dragging_handle  = false
		_active_handle_id = -1
		edited_node.update_gizmos()
		return 1
	if _pressed_handle_id != -1:
		_pressed_handle_id = -1
		return 1
	if not _box_select_started:
		return 0
	_box_select_started = false
	if _box_select_active:
		_box_select_active = false
		_editor_plugin.update_overlays()
		_finish_box_select(edited_node, camera, mb.shift_pressed, mb.ctrl_pressed)
		return 1
	return _handle_pick(edited_node, camera, _box_select_start,
			mb.shift_pressed, mb.ctrl_pressed)


func _handle_mouse_motion(
		edited_node: GoBuildMeshInstance,
		camera: Camera3D,
		mm: InputEventMouseMotion,
) -> int:
	if _dragging_handle:
		_gizmo_plugin.update_drag(edited_node, _active_handle_id, camera, mm.position)
		_gizmo_plugin.schedule_gizmo_redraw(edited_node)
		return 1
	if _pressed_handle_id != -1:
		if _handle_press_pos.distance_squared_to(mm.position) > BOX_SELECT_DRAG_THRESHOLD_SQ:
			var started := false
			if _should_inset_drag(edited_node):
				started = _begin_inset_drag(edited_node, _pressed_handle_id)
			elif _should_extrude_drag(edited_node):
				started = _begin_extrude_drag(edited_node, _pressed_handle_id)
			else:
				started = _gizmo_plugin.begin_drag(edited_node, _pressed_handle_id)
			if started:
				_dragging_handle   = true
				_active_handle_id  = _pressed_handle_id
				_pressed_handle_id = -1
				_gizmo_plugin.update_drag(
						edited_node, _active_handle_id, camera, mm.position)
				_gizmo_plugin.schedule_gizmo_redraw(edited_node)
				return 1
			_pressed_handle_id = -1
		return 1
	if not _box_select_started:
		_update_hover(edited_node, camera, mm.position)
		return 0
	_box_select_current = mm.position
	if not _box_select_active:
		if _box_select_start.distance_squared_to(_box_select_current) \
				> BOX_SELECT_DRAG_THRESHOLD_SQ:
			_box_select_active = true
	if _box_select_active:
		_editor_plugin.update_overlays()
		return 1
	return 0


# ---------------------------------------------------------------------------
# Shift+drag → Extrude
# ---------------------------------------------------------------------------

## Returns true when starting a translate drag should extrude instead of move.
## Conditions: Shift held + Face mode + Translate gizmo + faces selected
## + the pressed handle is a translate-type handle (axis, plane, or view-plane).
func _should_extrude_drag(edited_node: GoBuildMeshInstance) -> bool:
	if not Input.is_key_pressed(KEY_SHIFT):
		return false
	var ok_mode: bool = \
		edited_node.selection.get_mode() == SelectionManager.Mode.FACE \
		and _gizmo_plugin.transform_mode == GoBuildGizmoPlugin.TransformMode.TRANSLATE \
		and not edited_node.selection.get_selected_faces().is_empty()
	if not ok_mode:
		return false
	# Exclude rotate (2M–3M) and scale (3M–4M) handles; allow axis/plane/view-plane.
	var in_rot_range: bool = _pressed_handle_id >= GoBuildGizmoPlugin.ROT_HANDLE_OFFSET \
			and _pressed_handle_id < GoBuildGizmoPlugin.SCALE_HANDLE_OFFSET
	var in_scale_range: bool = _pressed_handle_id >= GoBuildGizmoPlugin.SCALE_HANDLE_OFFSET \
			and _pressed_handle_id < GoBuildGizmoPlugin.PLANE_HANDLE_OFFSET
	return not in_rot_range and not in_scale_range


## Perform an extrude(0) on the selected faces, then start a translate drag.
## Overrides _drag_restore with the pre-extrude snapshot so undo restores the
## mesh to before the extrude.  Returns false if anything fails.
func _begin_extrude_drag(
		edited_node: GoBuildMeshInstance,
		handle_id: int,
) -> bool:
	var gbm = edited_node.go_build_mesh
	if gbm == null:
		return false
	var faces: Array[int] = edited_node.selection.get_selected_faces()
	if faces.is_empty():
		return false

	# Snapshot BEFORE extrude — this is the undo target.
	var pre_snap: Dictionary = gbm.take_snapshot()

	# Extrude with distance 0: creates top-ring verts at the same positions.
	# ExtrudeOperation.apply also calls mesh.rebuild_edges().
	ExtrudeOperation.apply(gbm, faces, 0.0)

	# Bake so begin_extrude_drag reads the updated (post-extrude) vertex positions.
	edited_node.bake()

	# Collect top-ring vertex indices from the selected faces AFTER the extrude.
	# ExtrudeOperation.apply replaced each face's vertex_indices with the new
	# cap (top-ring) verts. We pass these to begin_extrude_drag so it can
	# restrict _drag_initial_verts to only the cap — see that method's doc for why.
	var top_ring: Array[int] = []
	for fidx: int in faces:
		for vidx: int in gbm.faces[fidx].vertex_indices:
			if not top_ring.has(vidx):
				top_ring.append(vidx)

	var started: bool = _gizmo_plugin.begin_extrude_drag(edited_node, handle_id, top_ring)
	if not started:
		# Couldn't start the drag — roll back the extrude and bail.
		edited_node.restore_and_bake(pre_snap)
		return false

	# Override the snapshot begin_drag stored (post-extrude) with the pre-extrude
	# one so that commit_drag's undo action restores the full pre-extrude state.
	_gizmo_plugin._drag_restore                = pre_snap
	_gizmo_plugin._drag_action_name_override   = "Extrude Face"
	return true


# ---------------------------------------------------------------------------
# Shift+drag → Inset (Scale mode, Face mode)
# ---------------------------------------------------------------------------

## Returns true when a scale drag should inset instead of scale.
## Conditions: Shift held + Face mode + Scale gizmo + faces selected + scale handle.
func _should_inset_drag(edited_node: GoBuildMeshInstance) -> bool:
	if not Input.is_key_pressed(KEY_SHIFT):
		return false
	if _gizmo_plugin.transform_mode != GoBuildGizmoPlugin.TransformMode.SCALE:
		return false
	if edited_node.selection.get_mode() != SelectionManager.Mode.FACE:
		return false
	if edited_node.selection.get_selected_faces().is_empty():
		return false
	return _pressed_handle_id >= GoBuildGizmoPlugin.SCALE_HANDLE_OFFSET


## Perform an inset(0) on the selected faces, then start an inset drag.
## Overrides _drag_restore with the pre-inset snapshot so undo restores the
## mesh to before the inset.  Returns false if anything fails.
func _begin_inset_drag(
		edited_node: GoBuildMeshInstance,
		handle_id: int,
) -> bool:
	var gbm = edited_node.go_build_mesh
	if gbm == null:
		return false
	var faces: Array[int] = edited_node.selection.get_selected_faces()
	if faces.is_empty():
		return false

	var pre_snap: Dictionary = gbm.take_snapshot()

	# Inset at amount=0: creates inner-ring verts at same positions as outer.
	# Populates centroids_out so the drag can animate each inner vert.
	var centroids_out: Dictionary = {}
	InsetOperation.apply(gbm, faces, 0.0, centroids_out)
	edited_node.bake()

	var started: bool = _gizmo_plugin.begin_inset_drag(edited_node, handle_id, centroids_out)
	if not started:
		edited_node.restore_and_bake(pre_snap)
		return false

	_gizmo_plugin._drag_restore              = pre_snap
	_gizmo_plugin._drag_action_name_override = "Inset Face"
	return true


# ---------------------------------------------------------------------------
# Handle picking
# ---------------------------------------------------------------------------

func _find_hovered_handle_id(
		edited_node: GoBuildMeshInstance,
		camera: Camera3D,
		click_pos: Vector2,
) -> int:
	if _gizmo_plugin == null or edited_node == null:
		return -1
	var positions: Array[Vector3] = \
			_gizmo_plugin.get_transform_handle_world_positions(edited_node)
	if positions.is_empty():
		return -1
	match _gizmo_plugin.transform_mode:
		GoBuildGizmoPlugin.TransformMode.ROTATE:
			return _find_rotate_handle(edited_node, camera, click_pos, positions)
		GoBuildGizmoPlugin.TransformMode.SCALE:
			return _find_scale_handle(edited_node, camera, click_pos, positions)
		_:  # TRANSLATE
			return _find_translate_handle(edited_node, camera, click_pos, positions)


func _find_translate_handle(
		edited_node: GoBuildMeshInstance,
		camera: Camera3D,
		click_pos: Vector2,
		positions: Array[Vector3],
) -> int:
	var gt: Transform3D = edited_node.global_transform
	var s: float        = _gizmo_plugin.compute_node_gizmo_scale(edited_node)
	var cone_h: float   = GoBuildGizmoPlugin.CONE_HEIGHT * s
	var local_axes: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	for i: int in 3:
		var apex_world: Vector3 = positions[i]
		if not camera.is_position_in_frustum(apex_world):
			continue
		var world_axis: Vector3 = (gt.basis * local_axes[i]).normalized()
		var base_world: Vector3 = apex_world - world_axis * cone_h
		if PickingHelper.point_to_segment_dist(
				click_pos,
				camera.unproject_position(base_world),
				camera.unproject_position(apex_world)) <= _TRANSLATE_HANDLE_PICK_RADIUS_PX:
			return GoBuildGizmoPlugin.AXIS_HANDLE_OFFSET + i
	return _find_plane_handle(edited_node, camera, click_pos, s)


func _find_plane_handle(
		edited_node: GoBuildMeshInstance,
		camera: Camera3D,
		click_pos: Vector2,
		s: float,
) -> int:
	var gt: Transform3D = edited_node.global_transform
	var lc: Vector3 = _gizmo_plugin.get_selection_local_centroid(edited_node)
	var inner: float = GoBuildGizmoPlugin.PLANE_INNER_OFFSET * s
	var local_centers: Array[Vector3] = [
		lc + Vector3(inner, inner, 0.0),
		lc + Vector3(0.0,  inner, inner),
		lc + Vector3(inner, 0.0,  inner),
	]
	for i: int in 3:
		var world_pos: Vector3 = gt * local_centers[i]
		if not camera.is_position_in_frustum(world_pos):
			continue
		if camera.unproject_position(world_pos).distance_squared_to(click_pos) \
				<= _PLANE_HANDLE_PICK_RADIUS_SQ:
			return GoBuildGizmoPlugin.PLANE_HANDLE_OFFSET + i

	var centroid_world: Vector3 = gt * lc
	if camera.is_position_in_frustum(centroid_world):
		var c_screen: Vector2 = camera.unproject_position(centroid_world)
		# Pick radius = visual square half-size (VIEW_PLANE_HALF * s) projected to
		# screen pixels, multiplied by 2.0 so the hitbox circumscribes the square
		# (covers corners).  Falls back to _VIEW_PLANE_PICK_RADIUS_SQ when the
		# projected edge is outside the frustum.
		var sq_edge_world: Vector3 = \
				gt * (lc + Vector3.UP * (GoBuildGizmoPlugin.VIEW_PLANE_HALF * s))
		var view_r_sq: float
		if camera.is_position_in_frustum(sq_edge_world):
			view_r_sq = c_screen.distance_squared_to(
					camera.unproject_position(sq_edge_world)) * 2.0
		else:
			view_r_sq = _VIEW_PLANE_PICK_RADIUS_SQ
		if c_screen.distance_squared_to(click_pos) <= view_r_sq:
			return GoBuildGizmoPlugin.VIEW_PLANE_HANDLE_ID
	return -1


func _find_rotate_handle(
		edited_node: GoBuildMeshInstance,
		camera: Camera3D,
		click_pos: Vector2,
		_positions: Array[Vector3],
) -> int:
	if _gizmo_plugin == null or edited_node == null:
		return -1
	var lc: Vector3          = _gizmo_plugin.get_selection_local_centroid(edited_node)
	var gt: Transform3D      = edited_node.global_transform
	var world_centroid: Vector3 = gt * lc
	var s: float             = _gizmo_plugin.compute_world_gizmo_scale(world_centroid)
	var ring_r_world: float  = GoBuildGizmoPlugin.ROT_RING_RADIUS * s
	var tol: float           = ring_r_world * 0.2

	var ray_origin: Vector3 = camera.project_ray_origin(click_pos)
	var ray_dir: Vector3    = camera.project_ray_normal(click_pos)

	var local_normals: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var best_id:  int   = -1
	var best_err: float = tol

	for i: int in 3:
		var world_normal: Vector3 = (gt.basis * local_normals[i]).normalized()
		var hit: Vector3 = GoBuildGizmoPlugin._ray_plane_intersect(
				ray_origin, ray_dir, world_centroid, world_normal)
		if hit == Vector3.INF:
			continue
		var ring_err: float = abs(hit.distance_to(world_centroid) - ring_r_world)
		if ring_err < best_err:
			best_err = ring_err
			best_id  = GoBuildGizmoPlugin.ROT_HANDLE_OFFSET + i
	return best_id


func _find_scale_handle(
		edited_node: GoBuildMeshInstance,
		camera: Camera3D,
		click_pos: Vector2,
		positions: Array[Vector3],
) -> int:
	# Uniform scale handle — centroid square, checked first (smaller target).
	var lc: Vector3 = _gizmo_plugin.get_selection_local_centroid(edited_node)
	var centroid_world: Vector3 = edited_node.global_transform * lc
	if camera.is_position_in_frustum(centroid_world):
		if camera.unproject_position(centroid_world).distance_squared_to(click_pos) \
				<= _SCALE_HANDLE_PICK_RADIUS_SQ:
			return GoBuildGizmoPlugin.UNIFORM_SCALE_HANDLE_ID

	# Axis cube tips.
	for i: int in 3:
		var tip_world: Vector3 = positions[i]
		if not camera.is_position_in_frustum(tip_world):
			continue
		if camera.unproject_position(tip_world).distance_squared_to(click_pos) \
				<= _SCALE_HANDLE_PICK_RADIUS_SQ:
			return GoBuildGizmoPlugin.SCALE_HANDLE_OFFSET + i
	return -1


# ---------------------------------------------------------------------------
# Element picking
# ---------------------------------------------------------------------------

func _handle_pick(
		edited_node: GoBuildMeshInstance,
		camera: Camera3D,
		click_pos: Vector2,
		additive: bool,
		toggle: bool,
) -> int:
	var sel: SelectionManager       = edited_node.selection
	var mode: SelectionManager.Mode = sel.get_mode()
	var gbm = edited_node.go_build_mesh

	if mode == SelectionManager.Mode.OBJECT:
		return 0
	if gbm == null:
		return 1

	var hit_idx: int = -1
	match mode:
		SelectionManager.Mode.VERTEX:
			hit_idx = PickingHelper.find_nearest_vertex(camera, click_pos, edited_node, gbm)
		SelectionManager.Mode.EDGE:
			hit_idx = PickingHelper.find_nearest_edge(camera, click_pos, edited_node, gbm)
		SelectionManager.Mode.FACE:
			hit_idx = PickingHelper.find_nearest_face(camera, click_pos, edited_node, gbm)

	if hit_idx == -1:
		if not additive and not toggle:
			sel.clear()
		return 1

	_apply_pick(sel, mode, hit_idx, additive, toggle)
	return 1


func _apply_pick(
		sel: SelectionManager,
		mode: SelectionManager.Mode,
		hit_idx: int,
		additive: bool,
		toggle: bool,
) -> void:
	if toggle:
		match mode:
			SelectionManager.Mode.VERTEX: sel.toggle_vertex(hit_idx)
			SelectionManager.Mode.EDGE:   sel.toggle_edge(hit_idx)
			SelectionManager.Mode.FACE:   sel.toggle_face(hit_idx)
	elif additive:
		match mode:
			SelectionManager.Mode.VERTEX: sel.select_vertex(hit_idx)
			SelectionManager.Mode.EDGE:   sel.select_edge(hit_idx)
			SelectionManager.Mode.FACE:   sel.select_face(hit_idx)
	else:
		sel.clear()
		match mode:
			SelectionManager.Mode.VERTEX: sel.select_vertex(hit_idx)
			SelectionManager.Mode.EDGE:   sel.select_edge(hit_idx)
			SelectionManager.Mode.FACE:   sel.select_face(hit_idx)


# ---------------------------------------------------------------------------
# Box select
# ---------------------------------------------------------------------------

func _get_box_select_rect() -> Rect2:
	return Rect2(
		Vector2(
			min(_box_select_start.x, _box_select_current.x),
			min(_box_select_start.y, _box_select_current.y),
		),
		Vector2(
			abs(_box_select_current.x - _box_select_start.x),
			abs(_box_select_current.y - _box_select_start.y),
		),
	)


func _finish_box_select(
		edited_node: GoBuildMeshInstance,
		camera: Camera3D,
		additive: bool,
		toggle: bool,
) -> void:
	var sel: SelectionManager       = edited_node.selection
	var mode: SelectionManager.Mode = sel.get_mode()
	var gbm = edited_node.go_build_mesh
	if gbm == null:
		return

	var rect: Rect2 = _get_box_select_rect()
	var hit_indices: Array[int] = []
	match mode:
		SelectionManager.Mode.VERTEX:
			hit_indices = PickingHelper.find_vertices_in_rect(
					camera, rect, edited_node, gbm)
		SelectionManager.Mode.EDGE:
			hit_indices = PickingHelper.find_edges_in_rect(
					camera, rect, edited_node, gbm)
		SelectionManager.Mode.FACE:
			hit_indices = PickingHelper.find_faces_in_rect(
					camera, rect, edited_node, gbm)

	if not additive and not toggle:
		sel.clear()

	for idx: int in hit_indices:
		if toggle:
			match mode:
				SelectionManager.Mode.VERTEX: sel.toggle_vertex(idx)
				SelectionManager.Mode.EDGE:   sel.toggle_edge(idx)
				SelectionManager.Mode.FACE:   sel.toggle_face(idx)
		else:
			match mode:
				SelectionManager.Mode.VERTEX: sel.select_vertex(idx)
				SelectionManager.Mode.EDGE:   sel.select_edge(idx)
				SelectionManager.Mode.FACE:   sel.select_face(idx)


# ---------------------------------------------------------------------------
# Hover
# ---------------------------------------------------------------------------

func _update_hover(
		edited_node: GoBuildMeshInstance,
		camera: Camera3D,
		pos: Vector2,
) -> void:
	if _gizmo_plugin == null:
		return
	var new_hover: int = _find_hovered_handle_id(edited_node, camera, pos)
	if new_hover != _gizmo_plugin._hovered_handle_id:
		_gizmo_plugin._hovered_handle_id = new_hover
		_gizmo_plugin.schedule_gizmo_redraw(edited_node)


func _clear_hover(edited_node: GoBuildMeshInstance) -> void:
	if _gizmo_plugin == null:
		return
	if _gizmo_plugin._hovered_handle_id == -1:
		return
	_gizmo_plugin._hovered_handle_id = -1
	_gizmo_plugin.schedule_gizmo_redraw(edited_node)


# ---------------------------------------------------------------------------
# Cancel helpers
# ---------------------------------------------------------------------------

func _cancel_active_drag(edited_node: GoBuildMeshInstance) -> void:
	if _dragging_handle and _gizmo_plugin != null and edited_node != null:
		_gizmo_plugin.commit_drag(edited_node, _active_handle_id, true)
	_dragging_handle   = false
	_active_handle_id  = -1
	_pressed_handle_id = -1
	if _gizmo_plugin != null:
		_gizmo_plugin.reset_drag_state()


func _cancel_box_select(edited_node: GoBuildMeshInstance) -> void:
	_box_select_started = false
	_box_select_active  = false
	if edited_node != null:
		edited_node.update_gizmos()
	_editor_plugin.update_overlays()


# ---------------------------------------------------------------------------
# Context menu
# ---------------------------------------------------------------------------

## Show a [PopupMenu] at screen position [param at] with operations appropriate
## to the current edit mode and selection.  No-op in Object mode.
func _show_context_menu(edited_node: GoBuildMeshInstance, at: Vector2) -> void:
	if edited_node == null:
		return
	var mode: SelectionManager.Mode = edited_node.selection.get_mode()
	if mode == SelectionManager.Mode.OBJECT:
		return
	var sel: SelectionManager = edited_node.selection
	var popup := PopupMenu.new()
	EditorInterface.get_base_control().add_child(popup)
	popup.popup_hide.connect(popup.queue_free)

	popup.add_item("Select All", 1)

	match mode:
		SelectionManager.Mode.VERTEX:
			if not sel.get_selected_vertices().is_empty():
				popup.add_separator()
				popup.add_item("Delete", 10)
				if sel.get_selected_vertices().size() >= 2:
					popup.add_item("Merge at Center  (M)", 11)
		SelectionManager.Mode.EDGE:
			if not sel.get_selected_edges().is_empty():
				popup.add_separator()
				popup.add_item("Bevel   [planned]", 20)
				popup.add_item("Delete", 10)
		SelectionManager.Mode.FACE:
			if not sel.get_selected_faces().is_empty():
				popup.add_separator()
				popup.add_item("Extrude", 30)
				popup.add_item("Inset   [planned]", 31)
				popup.add_separator()
				popup.add_item("Flip Normals", 32)
				popup.add_item("Delete", 10)

	var mode_int: int = mode as int
	popup.id_pressed.connect(
			func(id: int) -> void: _on_context_menu_pressed(id, mode_int, edited_node))
	popup.popup(Rect2i(Vector2i(at), Vector2i.ZERO))


func _on_context_menu_pressed(
		id: int,
		mode_int: int,
		edited_node: GoBuildMeshInstance,
) -> void:
	if edited_node == null:
		return
	var sel: SelectionManager = edited_node.selection
	var gbm = edited_node.go_build_mesh
	match id:
		1:  # Select All
			if gbm == null:
				return
			match mode_int:
				SelectionManager.Mode.VERTEX:
					for i: int in gbm.vertices.size():
						sel.select_vertex(i)
				SelectionManager.Mode.EDGE:
					for i: int in gbm.edges.size():
						sel.select_edge(i)
				SelectionManager.Mode.FACE:
					for i: int in gbm.faces.size():
						sel.select_face(i)
		30:  # Extrude — delegate to panel for undo/redo wiring
			if _panel != null:
				_panel.trigger_extrude()
		32:  # Flip Normals — delegate to panel for undo/redo wiring
			if _panel != null:
				_panel.trigger_flip_normals()
		10:  # Delete — delegate to panel for undo/redo wiring
			if _panel != null:
				_panel.trigger_delete()
		11:  # Merge vertices — delegate to panel for undo/redo wiring
			if _panel != null:
				_panel.trigger_merge()
		_:
			pass  # Planned features: no-op stubs
