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
const _FACE_SCRIPT           := preload("res://addons/go_build/mesh/go_build_face.gd")
const _SEL_MGR_SCRIPT        := preload("res://addons/go_build/core/selection_manager.gd")
const _PICKING_HELPER_SCRIPT := preload("res://addons/go_build/core/picking_helper.gd")
const _MESH_INSTANCE_SCRIPT  := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _GIZMO_PLUGIN_SCRIPT   := preload("res://addons/go_build/core/go_build_gizmo_plugin.gd")
const _DRAG_HANDLER_SCRIPT   := preload("res://addons/go_build/core/go_build_drag_handler.gd")
const _PANEL_SCRIPT          := preload("res://addons/go_build/core/go_build_panel.gd")
const _EXTRUDE_SCRIPT       := preload(
		"res://addons/go_build/mesh/operations/extrude_operation.gd")
const _INSET_SCRIPT         := preload(
		"res://addons/go_build/mesh/operations/inset_operation.gd")
const _EDGE_EXTRUDE_SCRIPT  := preload(
		"res://addons/go_build/mesh/operations/edge_extrude_operation.gd")
const _EDGE_SCRIPT          := preload(
		"res://addons/go_build/mesh/go_build_edge.gd")
const _PARAM_PREVIEW_SCRIPT := preload(
		"res://addons/go_build/core/go_build_param_preview.gd")

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
## Minimum microseconds between full apply+bake flushes during parameter preview.
## Caps mesh rebuilds to ~20 fps so the editor stays responsive.
const _PREVIEW_APPLY_INTERVAL_USEC: int = 50_000  # 50 ms → ~20 fps
## Multiplier applied to units_per_pixel when Shift is held during a
## param preview drag.  0.1 = precision mode (10% sensitivity).
const _PRECISION_MULTIPLIER: float = 0.1

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

# ── Parameter-preview state ─────────────────────────────────────────────────
## Active preview, or [code]null[/code] when idle.
var _param_preview: GoBuildParamPreview = null
## Accumulated horizontal mouse delta since the preview started.
var _param_preview_delta: float = 0.0
## Unified deferred apply — coalesces restore_snapshot + apply_fn + bake + update_gizmos
## to at most once per frame so rapid motion events don't each trigger a full bake.
var _preview_apply_scheduled: bool             = false
var _preview_apply_node: GoBuildMeshInstance   = null
var _preview_apply_target: float               = 0.0
## True when motion arrived since the last flush — prevents infinite reschedule.
var _preview_apply_dirty: bool                 = false
## Timestamp (Engine.get_process_time_usec) of the last completed apply flush.
## Used to throttle bake/apply to a maximum rate so the editor stays responsive.
var _preview_last_apply_usec: int              = 0
## Mouse mode saved at preview start so it can be restored on cancel/commit.
var _preview_saved_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE
## Ignored until call_deferred fires _accept_preview_motion.
## Prevents synthetic events from the triggering button click / popup close
## and from the warp itself from jumping the parameter on the first frame.
var _preview_accepting_motion: bool            = false
## After accepting motion, events whose mm.relative is longer than the large-
## relative threshold are still skipped for this many events.  Handles warp
## synthetic events that arrive one frame later than the deferred gate.
var _preview_filter_count: int                 = 0
## Viewport-local anchor position (centre of the 3D viewport).
## Used for the overlay indicator.
var _preview_anchor_vp: Vector2                = Vector2.ZERO
## SubViewportContainer display pixel size, captured at preview start.
## Used for the overlay indicator drawing.
var _preview_vp_size: Vector2                  = Vector2.ZERO
## True while parameter-preview is active.
## Used by the panel to avoid refreshing stats on every bake_preview call.
var _preview_active: bool = false
## Virtual cursor position in viewport-local space.
## Accumulates mm.relative from the anchor; used to draw the directional
## indicator and to derive _param_preview_delta.
var _preview_virtual_pos: Vector2              = Vector2.ZERO
## Previous Shift state during a param preview.  When Shift changes,
## the current param value is captured as the new param_start and the
## virtual position / anchor are reset so precision toggling doesn't
## cause a jump.
var _preview_prev_shift: bool                   = false


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
	if _param_preview != null:
		return _handle_param_preview_input(edited_node, camera, event)
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


## Draw the box-select rectangle and param-preview indicator.
## Call from [method EditorPlugin._forward_3d_draw_over_viewport].
func draw_overlay(overlay: Control) -> void:
	if _box_select_active:
		var rect: Rect2 = _get_box_select_rect()
		overlay.draw_rect(rect, Color(0.25, 0.45, 0.8, 0.15), true)
		overlay.draw_rect(rect, Color(0.5, 0.7, 1.0, 0.85), false)
	if _param_preview != null and _preview_accepting_motion:
		_draw_preview_indicator(overlay)


## Draw the parameter-preview scrub indicator:
##   • White anchor dot at the warp origin (viewport centre).
##   • Coloured horizontal line from anchor to the current accumulated delta.
##     Green when delta ≥ 0 (increasing param), red when negative.
##   • Tick mark at the live position.
##   • Dashed zero-line across the full height for reference.
func _draw_preview_indicator(overlay: Control) -> void:
	var anchor := _preview_anchor_vp
	# Clamp display position to safe area — the actual delta accumulation is unclamped.
	var m   := 8.0
	var vp  := Vector2(
			clampf(_preview_virtual_pos.x, m, overlay.size.x - m),
			clampf(_preview_virtual_pos.y, m, overlay.size.y - m))

	var col_pos  := Color(0.25, 0.85, 0.35, 0.90)  # green — positive / larger param
	var col_neg  := Color(0.90, 0.30, 0.25, 0.90)  # red   — negative / smaller param
	var col_line := col_pos if _param_preview_delta >= 0.0 else col_neg
	var col_shad := Color(0.0, 0.0, 0.0, 0.55)

	# Faint crosshair at anchor for spatial reference.
	overlay.draw_line(Vector2(anchor.x, 0.0), Vector2(anchor.x, overlay.size.y),
			Color(1.0, 1.0, 1.0, 0.12), 1.0)
	overlay.draw_line(Vector2(0.0, anchor.y), Vector2(overlay.size.x, anchor.y),
			Color(1.0, 1.0, 1.0, 0.08), 1.0)

	# Shadow then coloured directional line from anchor to virtual cursor.
	overlay.draw_line(anchor, vp, col_shad, 4.0)
	overlay.draw_line(anchor, vp, col_line, 2.5)

	# Anchor dot — white ring over dark fill.
	overlay.draw_circle(anchor, 5.5, col_shad)
	overlay.draw_circle(anchor, 4.5, Color.WHITE)
	overlay.draw_circle(anchor, 3.0, Color(0.15, 0.15, 0.15))

	# Virtual-cursor dot — coloured ring with white centre.
	overlay.draw_circle(vp, 7.5, col_shad)
	overlay.draw_circle(vp, 6.5, col_line)
	overlay.draw_circle(vp, 3.5, Color.WHITE)


## Cancel any in-progress handle drag.  Safe to call when idle.
func cancel_drag(edited_node: GoBuildMeshInstance) -> void:
	cancel_param_preview(edited_node)
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
# Parameter-preview
# ---------------------------------------------------------------------------

## Enter parameter-preview mode.  Called by [code]plugin.begin_param_preview[/code]
## after the snapshot and initial apply are already complete.
func begin_param_preview(preview: GoBuildParamPreview) -> void:
	_param_preview       = preview
	_param_preview_delta = 0.0
	# Initialise apply target to param_start so that a commit with zero mouse
	# movement applies the visible default rather than 0.
	_preview_apply_target    = preview.param_start
	_preview_last_apply_usec = 0
	# Capture viewport display size for the overlay indicator.
	var sv: SubViewport = EditorInterface.get_editor_viewport_3d(0)
	_preview_vp_size = Vector2(1280, 720)  # safe fallback
	if sv != null:
		var vp_parent := sv.get_parent() as Control
		if vp_parent != null:
			_preview_vp_size = Vector2(vp_parent.size)
	_preview_anchor_vp   = _preview_vp_size * 0.5
	_preview_virtual_pos = _preview_anchor_vp
	# No warp: the virtual cursor starts at the viewport centre in logic-space
	# regardless of physical cursor position, so warping is never needed and
	# only causes a visible jump when triggering from a context menu.
	_preview_saved_mouse_mode = Input.mouse_mode
	Input.mouse_mode          = Input.MOUSE_MODE_HIDDEN
	# Defer accepting motion so button-release events in this frame drain first.
	# Layer-2 filter (_preview_filter_count) then skips any large synthetic
	# events that arrive one frame later.
	_preview_active          = true
	_preview_accepting_motion = false
	_preview_filter_count     = 4
	_preview_prev_shift      = Input.is_key_pressed(KEY_SHIFT)
	call_deferred("_accept_preview_motion")


## Called at start of the frame after [method begin_param_preview] to allow
## motion events.  The deferred call lets synthetic warp/click events drain first.
func _accept_preview_motion() -> void:
	_preview_accepting_motion = true

## [code]true[/code] while a parameter-preview is active.
func has_active_param_preview() -> bool:
	return _param_preview != null

## One-line overlay text for the active preview.
## Returns an empty string when idle.
func get_param_preview_overlay_text() -> String:
	if _param_preview == null:
		return ""
	var snap_hint: String = ""
	if _param_preview.snap_to_start:
		snap_hint = "  [near %.2f snaps]" % _param_preview.param_start
	return "%s: %.4f%s   LMB=accept   RMB/Esc=cancel" % [
		_param_preview.param_label, _param_preview.param, snap_hint]

## Cancel the active preview and restore the mesh.  Safe to call when idle.
func cancel_param_preview(edited_node: GoBuildMeshInstance) -> void:
	if _param_preview == null:
		return
	_preview_apply_scheduled  = false
	_preview_apply_node       = null
	_preview_apply_dirty      = false
	_preview_apply_target     = 0.0
	_preview_last_apply_usec  = 0
	_preview_accepting_motion = false
	_preview_filter_count     = 0
	_preview_virtual_pos      = Vector2.ZERO
	_preview_active           = false
	Input.mouse_mode = _preview_saved_mouse_mode
	if edited_node != null and is_instance_valid(edited_node):
		edited_node.end_preview()
		edited_node.restore_and_bake(_param_preview.snapshot)
	_param_preview = null
	_param_preview_delta = 0.0


func _schedule_preview_apply(node: GoBuildMeshInstance, target: float) -> void:
	_preview_apply_node   = node
	_preview_apply_target = target
	_preview_apply_dirty  = true
	if not _preview_apply_scheduled:
		_preview_apply_scheduled = true
		call_deferred("_flush_preview_apply")


func _flush_preview_apply() -> void:
	_preview_apply_scheduled = false
	var node := _preview_apply_node
	_preview_apply_node  = null
	_preview_apply_dirty = false
	if node == null or not is_instance_valid(node) or _param_preview == null:
		return
	node.go_build_mesh.restore_snapshot(_param_preview.snapshot)
	_param_preview.apply_fn.call(_preview_apply_target)
	if node.auto_uv_mode != GoBuildFace.UvMode.NONE:
		node._apply_auto_uv()
	node.bake_preview()
	_editor_plugin.update_overlays()


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
			elif _should_edge_extrude_drag(edited_node):
				started = _begin_edge_extrude_drag(edited_node, _pressed_handle_id)
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
			# begin_drag failed (e.g. nothing selected) — fall back to box-select
			# so subsequent motion events are consumed and do not leak to Godot's
			# native W-mode gizmo.
			_pressed_handle_id  = -1
			_box_select_started = true
			_box_select_active  = false
			_box_select_start   = _handle_press_pos
			_box_select_current = mm.position
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
	# Always consume motion while a box-select is pending (threshold not crossed).
	# Without this, the event passes to Godot's native W-mode gizmo which can
	# move the entire node if the editor is not reliably in SELECT mode (Q).
	return 1


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
# Shift+drag → Edge Extrude
# ---------------------------------------------------------------------------

## Returns true when starting a translate drag should edge-extrude rather than move.
## Conditions: Shift held + Edge mode + Translate gizmo + at least one boundary
## edge selected + the pressed handle is a translate-type handle.
func _should_edge_extrude_drag(edited_node: GoBuildMeshInstance) -> bool:
	if not Input.is_key_pressed(KEY_SHIFT):
		return false
	if _gizmo_plugin.transform_mode != GoBuildGizmoPlugin.TransformMode.TRANSLATE:
		return false
	if edited_node.selection.get_mode() != SelectionManager.Mode.EDGE:
		return false
	# Require at least one edge to be selected.
	if edited_node.selection.get_selected_edges().is_empty():
		return false
	# Exclude rotate and scale handles — allow axis / plane / view-plane only.
	var in_rot: bool = _pressed_handle_id >= GoBuildGizmoPlugin.ROT_HANDLE_OFFSET \
			and _pressed_handle_id < GoBuildGizmoPlugin.SCALE_HANDLE_OFFSET
	var in_scale: bool = _pressed_handle_id >= GoBuildGizmoPlugin.SCALE_HANDLE_OFFSET \
			and _pressed_handle_id < GoBuildGizmoPlugin.PLANE_HANDLE_OFFSET
	return not in_rot and not in_scale


## Perform EdgeExtrudeOperation on the selected edges, then start a translate
## drag restricted to the newly created boundary-edge vertices.
## Mirrors [method _begin_extrude_drag] exactly — does NOT touch selection
## mid-setup to avoid firing selection_changed signals during drag init.
## Returns false if anything fails.
func _begin_edge_extrude_drag(
		edited_node: GoBuildMeshInstance,
		handle_id: int,
) -> bool:
	var gbm: GoBuildMesh = edited_node.go_build_mesh
	if gbm == null:
		return false

	# Collect valid edges from the current selection (original indices).
	var source_edges: Array[int] = []
	for ei: int in edited_node.selection.get_selected_edges():
		if ei >= 0 and ei < gbm.edges.size():
			source_edges.append(ei)
	if source_edges.is_empty():
		return false

	# Snapshot BEFORE the operation — this is the undo target.
	var pre_snap: Dictionary = gbm.take_snapshot()

	# Apply at distance 0: new na/nb verts are coincident with va/vb.
	# Returns the new boundary edge indices (na-nb per extruded edge).
	var new_edge_indices: Array[int] = EdgeExtrudeOperation.apply(gbm, source_edges)
	if new_edge_indices.is_empty():
		return false

	edited_node.bake()

	# Collect the vertex indices for the new boundary edge endpoints (na and nb
	# per extruded edge) — these are the only vertices that should move.
	# Do NOT update the selection here; doing so fires selection_changed which
	# calls update_gizmos() synchronously and interferes with drag setup.
	var new_verts: Array[int] = []
	for ei: int in new_edge_indices:
		var edge: GoBuildEdge = gbm.edges[ei]
		if not new_verts.has(edge.vertex_a):
			new_verts.append(edge.vertex_a)
		if not new_verts.has(edge.vertex_b):
			new_verts.append(edge.vertex_b)

	var started: bool = _gizmo_plugin.begin_extrude_drag(edited_node, handle_id, new_verts)
	if not started:
		# Roll back to pre-extrude state.
		edited_node.restore_and_bake(pre_snap)
		return false

	# Override snap with the pre-operation snapshot so undo returns to before extrude.
	_gizmo_plugin._drag_restore              = pre_snap
	_gizmo_plugin._drag_action_name_override = "Extrude Edge"
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
	# Per-plane axis offset (local space) used to project the visual edge to
	# screen for a resolution-independent pick radius. Each vector points
	# along one axis that lies within the corresponding plane:
	#   i=0  XY plane → X axis
	#   i=1  YZ plane → Y axis
	#   i=2  XZ plane → X axis
	var half: float = GoBuildGizmoPlugin.PLANE_HALF * s
	var plane_edge_offsets: Array[Vector3] = [
		Vector3(half, 0.0,  0.0),
		Vector3(0.0,  half, 0.0),
		Vector3(half, 0.0,  0.0),
	]
	for i: int in 3:
		var world_pos: Vector3 = gt * local_centers[i]
		if not camera.is_position_in_frustum(world_pos):
			continue
		var center_screen: Vector2 = camera.unproject_position(world_pos)
		# Compute pick radius from the projected visual half-size so the
		# hitbox matches the drawn square at any viewport resolution.
		# Multiply by 2 to circumscribe the square (covers corners).
		# Fall back to the fixed constant so very small/distant handles
		# remain clickable.
		var edge_world: Vector3 = gt * (local_centers[i] + plane_edge_offsets[i])
		var pick_r_sq: float = _PLANE_HANDLE_PICK_RADIUS_SQ
		if camera.is_position_in_frustum(edge_world):
			pick_r_sq = maxf(
					center_screen.distance_squared_to(
							camera.unproject_position(edge_world)) * 2.0,
					_PLANE_HANDLE_PICK_RADIUS_SQ
			)
		if center_screen.distance_squared_to(click_pos) <= pick_r_sq:
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
		var hit: Vector3 = GoBuildTransformHelpers.ray_plane_intersect(
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


## Deferred hop: called the frame after the click event is fully processed
## so gizmo plugin removal/re-add in _edit() never happens mid-event.
func _hop_to_mesh(other: GoBuildMeshInstance) -> void:
	if not is_instance_valid(other):
		return
	var es := EditorInterface.get_selection()
	es.clear()
	es.add_node(other)


# ---------------------------------------------------------------------------
# Occlusion helper
# ---------------------------------------------------------------------------

## Return the [GoBuildMeshInstance] (other than [param edited_node]) whose face
## is closest to the camera at [param click_pos] and is nearer to the camera
## than the centroid of [param face_idx] on [param edited_node].
##
## Returns [code]null[/code] when no closer mesh is found.
## Used to prevent picking a face that is geometrically occluded by another
## GoBuildMesh in the scene.
func _find_occluding_mesh(
		camera: Camera3D,
		click_pos: Vector2,
		edited_node: GoBuildMeshInstance,
		face_idx: int,
) -> GoBuildMeshInstance:
	var gbm: GoBuildMesh = edited_node.go_build_mesh
	if gbm == null or face_idx < 0 or face_idx >= gbm.faces.size():
		return null

	# Approximate hit depth: world-space centroid of the hit face.
	var face: GoBuildFace = gbm.faces[face_idx]
	var gt: Transform3D   = edited_node.global_transform
	var centroid: Vector3 = Vector3.ZERO
	for vi: int in face.vertex_indices:
		centroid += gt * gbm.vertices[vi]
	centroid /= float(face.vertex_indices.size())
	var hit_dist_sq: float = camera.global_position.distance_squared_to(centroid)

	var ray_from: Vector3  = camera.project_ray_origin(click_pos)
	var ray_dir: Vector3   = camera.project_ray_normal(click_pos)
	var scene_root: Node   = EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return null

	for node: Node in scene_root.find_children("*", "Node3D", true, false):
		if node == edited_node or not (node is GoBuildMeshInstance):
			continue
		var mi: GoBuildMeshInstance = node as GoBuildMeshInstance
		if mi.mesh == null or mi.go_build_mesh == null:
			continue
		# Quick AABB rejection — skip meshes the ray clearly misses.
		var inv: Transform3D = mi.global_transform.affine_inverse()
		var lf: Vector3      = inv * ray_from
		var ld: Vector3      = inv.basis * ray_dir
		if mi.get_aabb().intersects_ray(lf, ld) == null:
			continue
		# Face-level intersection against potential occluder.
		var other_idx: int = PickingHelper.find_nearest_face(
				camera, click_pos, mi, mi.go_build_mesh)
		if other_idx == -1:
			continue
		# Compare centroids as depth proxies.
		var of: GoBuildFace    = mi.go_build_mesh.faces[other_idx]
		var ogt: Transform3D   = mi.global_transform
		var other_c: Vector3   = Vector3.ZERO
		for vi: int in of.vertex_indices:
			other_c += ogt * mi.go_build_mesh.vertices[vi]
		other_c /= float(of.vertex_indices.size())
		if camera.global_position.distance_squared_to(other_c) < hit_dist_sq:
			return mi

	return null


# ---------------------------------------------------------------------------
# Cross-mesh selection helper
# ---------------------------------------------------------------------------

## Walk the edited scene for a [GoBuildMeshInstance] other than [param exclude]
## that the camera ray through [param click_pos] intersects.  Returns the first
## hit (closest is not guaranteed — first in tree order) or [code]null[/code].
func _find_gobuild_at(
		camera: Camera3D,
		click_pos: Vector2,
		exclude: Node3D,
) -> GoBuildMeshInstance:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return null
	var ray_from: Vector3 = camera.project_ray_origin(click_pos)
	var ray_dir:  Vector3 = camera.project_ray_normal(click_pos)
	for node: Node in scene_root.find_children("*", "Node3D", true, false):
		if node == exclude or not (node is GoBuildMeshInstance):
			continue
		var mi := node as GoBuildMeshInstance
		if mi.mesh == null:
			continue
		# Transform ray to local space for AABB test.
		var inv: Transform3D = mi.global_transform.affine_inverse()
		var local_from: Vector3 = inv * ray_from
		var local_dir:  Vector3 = inv.basis * ray_dir
		if mi.get_aabb().intersects_ray(local_from, local_dir) != null:
			return mi
	return null


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
			# Miss — check if a different GoBuildMeshInstance is under the click.
			# Defer the selection change: calling es.add_node() synchronously
			# inside _forward_3d_gui_input triggers _edit() mid-event which
			# removes+re-adds the gizmo plugin and causes Godot to attempt
			# redraw on gizmo instances with a null spatial_node.
			var other := _find_gobuild_at(camera, click_pos, edited_node)
			if other != null:
				call_deferred("_hop_to_mesh", other)
				return 1
			sel.clear()
		return 1

	# Occlusion check — only for face picking.
	# If another GoBuildMeshInstance has a face closer to the camera at this
	# click position, the hit is considered occluded.  Hop to the occluding mesh
	# (non-additive click only) so the user can edit it directly.
	if mode == SelectionManager.Mode.FACE:
		var occluder := _find_occluding_mesh(camera, click_pos, edited_node, hit_idx)
		if occluder != null:
			if not additive and not toggle:
				call_deferred("_hop_to_mesh", occluder)
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
	# Convert viewport-local position to screen (OS window) coordinates.
	# mb.position from _forward_3d_gui_input is relative to the 3D SubViewport.
	# The SubViewport's parent Control holds the viewport at a known screen location.
	var screen_at: Vector2i = Vector2i(at)
	var sv: SubViewport = EditorInterface.get_editor_viewport_3d(0)
	if sv != null:
		var vp_parent := sv.get_parent() as Control
		if vp_parent != null:
			screen_at = Vector2i(vp_parent.get_screen_position() + at)
	var sel: SelectionManager = edited_node.selection
	var popup := PopupMenu.new()
	EditorInterface.get_base_control().add_child(popup)
	popup.popup_hide.connect(popup.queue_free)

	popup.add_item("Select All", 1)

	match mode:
		SelectionManager.Mode.VERTEX:
			if not sel.get_selected_vertices().is_empty():
				popup.add_separator()
				if sel.get_selected_vertices().size() >= 2:
					popup.add_item("Merge at Center  (M)", 11)
				popup.add_item("Weld (Merge by Distance)", 12)
				popup.add_item("Delete", 10)
		SelectionManager.Mode.EDGE:
			if not sel.get_selected_edges().is_empty():
				popup.add_separator()
				popup.add_item("Bevel", 20)
				popup.add_item("Loop Cut", 23)
				popup.add_item("Bridge  (F)", 22)
				popup.add_item("Extrude Edge", 21)
				popup.add_separator()
				popup.add_item("Hard Edge", 24)
				popup.add_item("Soft Edge", 25)
				popup.add_separator()
				popup.add_item("Delete", 10)
		SelectionManager.Mode.FACE:
			if not sel.get_selected_faces().is_empty():
				popup.add_separator()
				popup.add_item("Extrude", 30)
				popup.add_item("Inset", 31)
				popup.add_item("Subdivide", 33)
				popup.add_separator()
				popup.add_item("Flip Normals", 32)
				popup.add_separator()
				popup.add_item("Flat Shading", 34)
				popup.add_item("Smooth Shading", 35)
				popup.add_item("Auto Smooth", 36)
				popup.add_separator()
				popup.add_item("Delete", 10)

	var mode_int: int = mode as int
	popup.id_pressed.connect(
			func(id: int) -> void: _on_context_menu_pressed(id, mode_int, edited_node))
	popup.popup(Rect2i(screen_at, Vector2i.ZERO))


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
		10:  # Delete
			if _panel != null:
				_panel.trigger_delete()
		11:  # Merge vertices
			if _panel != null:
				_panel.trigger_merge()
		12:  # Weld (merge by distance)
			if _panel != null:
				_panel.trigger_weld()
		20:  # Bevel edges
			if _panel != null:
				_panel.trigger_bevel()
		21:  # Extrude edge
			if _panel != null:
				_panel.trigger_extrude_edge()
		22:  # Bridge
			if _panel != null:
				_panel.trigger_bridge()
		23:  # Loop Cut
			if _panel != null:
				_panel.trigger_loop_cut()
		30:  # Extrude face
			if _panel != null:
				_panel.trigger_extrude()
		31:  # Inset face
			if _panel != null:
				_panel.trigger_inset()
		32:  # Flip Normals
			if _panel != null:
				_panel.trigger_flip_normals()
		33:  # Subdivide
			if _panel != null:
				_panel.trigger_subdivide()
		24:  # Hard edge
			if _panel != null:
				_panel.trigger_hard_edge()
		25:  # Soft edge
			if _panel != null:
				_panel.trigger_soft_edge()
		34:  # Flat shading
			if _panel != null:
				_panel.trigger_flat()
		35:  # Smooth shading
			if _panel != null:
				_panel.trigger_smooth()
		36:  # Auto smooth
			if _panel != null:
				_panel.trigger_auto_smooth()


# ---------------------------------------------------------------------------
# Parameter-preview input handling
# ---------------------------------------------------------------------------

func _handle_param_preview_input(
		edited_node: GoBuildMeshInstance,
		_camera: Camera3D,
		event: InputEvent,
) -> int:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and key.keycode == KEY_ESCAPE:
			cancel_param_preview(edited_node)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		# Layer 1 gate: block all motion until deferred _accept_preview_motion fires.
		if not _preview_accepting_motion:
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		# Layer 2 filter: skip large-relative events for the first few events after
		# accepting, which handles synthetic motion from the startup warp and popup
		# close that may arrive one or two frames later.
		if _preview_filter_count > 0:
			if mm.relative.length_squared() > 50.0 * 50.0:
				_preview_filter_count -= 1
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			_preview_filter_count = 0  # first normal-sized event — stop filtering
		_preview_virtual_pos += mm.relative
		# When Shift (precision) state changes, re-anchor the param computation
		# at the current value so there is no jump.
		var shift_now: bool = mm.shift_pressed
		if shift_now != _preview_prev_shift:
			_preview_prev_shift = shift_now
			_param_preview.param_start = _param_preview.param
			if _param_preview.radial:
				_preview_anchor_vp = _preview_virtual_pos
			else:
				_param_preview_delta = 0.0
				_preview_virtual_pos = _preview_anchor_vp
		# Radial: Euclidean distance from anchor in any direction (always >= 0).
		# Linear: project cumulative cursor offset onto the edge's screen-space
		# direction so the cut follows the mouse along the edge's visual axis.
		if _param_preview.radial:
			_param_preview_delta = _preview_virtual_pos.distance_to(_preview_anchor_vp)
		else:
			_param_preview_delta = (_preview_virtual_pos - _preview_anchor_vp) \
					.dot(_param_preview.screen_direction)
		var raw := _param_preview.param_start \
				+ _param_preview_delta * _param_preview.units_per_pixel \
				* (_PRECISION_MULTIPLIER if shift_now else 1.0)
		var new_param := clampf(raw, _param_preview.param_min, _param_preview.param_max)
		if _param_preview.snap_to_start \
				and absf(new_param - _param_preview.param_start) \
				< _param_preview.snap_threshold:
			new_param = _param_preview.param_start
		_param_preview.param = new_param
		# Refresh overlay immediately (cheap) so indicator is always current.
		_editor_plugin.update_overlays()
		# Defer the expensive restore_snapshot + apply_fn + bake + update_gizmos.
		# All events within a frame are coalesced into one mesh rebuild.
		_schedule_preview_apply(edited_node, new_param)
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_commit_param_preview(edited_node)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			cancel_param_preview(edited_node)
			return EditorPlugin.AFTER_GUI_INPUT_STOP

	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _commit_param_preview(edited_node: GoBuildMeshInstance) -> void:
	if _param_preview == null:
		return
	_preview_apply_scheduled  = false
	_preview_apply_node       = null
	_preview_apply_dirty      = false
	_preview_accepting_motion = false
	_preview_filter_count     = 0
	_preview_virtual_pos      = Vector2.ZERO
	_preview_last_apply_usec  = 0
	_preview_active           = false
	Input.mouse_mode = _preview_saved_mouse_mode
	# Capture all needed refs before nulling _param_preview.
	var action_name  := _param_preview.action_name
	var before       := _param_preview.snapshot
	var apply_fn     := _param_preview.apply_fn
	var final_target := _preview_apply_target
	_param_preview        = null
	_param_preview_delta  = 0.0
	_preview_apply_target = 0.0
	if edited_node == null or not is_instance_valid(edited_node):
		return
	# Apply final state synchronously so the mesh is always up-to-date even if
	# the last deferred flush hasn't fired yet (or was throttled).
	edited_node.go_build_mesh.restore_snapshot(before)
	apply_fn.call(final_target)
	if edited_node.auto_uv_mode != GoBuildFace.UvMode.NONE:
		edited_node._apply_auto_uv()
	edited_node.end_preview()
	edited_node.bake()
	# Capture the post-operation snapshot to store as the redo state.
	var final_snapshot := edited_node.go_build_mesh.take_snapshot()
	edited_node.update_gizmos()
	var ur: EditorUndoRedoManager = _editor_plugin.get_undo_redo()
	ur.create_action(action_name)
	ur.add_do_method(edited_node, "restore_and_bake", final_snapshot)
	ur.add_undo_method(edited_node, "restore_and_bake", before)
	# NOTE: do NOT call add_do_reference / add_undo_reference here.
	# Those methods hand lifetime ownership to the UndoRedo system, which calls
	# free() when the action is discarded (e.g. when create_action() clears
	# forward history after an undo).  edited_node is a permanent scene node
	# managed by the scene tree, not by UndoRedo — freeing it via the undo
	# system crashes the editor the next time the node is accessed.
	# commit_action(false): mesh is already in final state — do NOT re-execute
	# the do-method.  Calling it again would bake a second bevel on an already-
	# beveled mesh before the undo system restores final_snapshot, causing a crash.
	ur.commit_action(false)
