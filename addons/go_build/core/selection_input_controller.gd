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
const _SHAPE_PLACEMENT_SCRIPT := preload("res://addons/go_build/core/shape_placement.gd")
const _SHAPE_CATALOG_SCRIPT  := preload(
		"res://addons/go_build/mesh/generators/shape_creation_catalog.gd")

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
const _DRAG_CTRL_SCRIPT := preload(
		"res://addons/go_build/core/go_build_drag_controller.gd")
const _DRAG_OP_SCRIPT    := preload(
		"res://addons/go_build/core/go_build_drag_operation.gd")
const _SEL_HELPERS_SCRIPT := preload("res://addons/go_build/core/selection_helpers.gd")

# ---------------------------------------------------------------------------
# Constants (were in plugin.gd)
# ---------------------------------------------------------------------------

## Squared pixel distance a left-drag must travel before it becomes a box select.
const BOX_SELECT_DRAG_THRESHOLD_SQ: float = 25.0  # 5 px

## Screen-space pixel radius for translate cone handle hit-testing.
const _TRANSLATE_HANDLE_PICK_RADIUS_PX: float = 10.0
## Squared screen-space pixel radius for scale cube handle hit-testing.
const _SCALE_HANDLE_PICK_RADIUS_SQ: float   = 144.0  # 12 px
## Squared screen-space pixel radius for planar handle hit-testing.
const _PLANE_HANDLE_PICK_RADIUS_SQ: float   = 225.0  # 15 px
## Squared screen-space pixel radius for viewport-plane handle hit-testing.
const _VIEW_PLANE_PICK_RADIUS_SQ: float     = 196.0  # 14 px
## Multiplier applied to units_per_pixel when Shift is held during a
## param preview drag.  0.1 = precision mode (10% sensitivity).
const _PRECISION_MULTIPLIER: float = 0.1
## Param-preview operation IDs from the context menu.  These operations must
## be deferred until the popup has fully closed and the viewport has reclaimed
## input focus, otherwise MOUSE_MODE_CAPTURED is set while the popup still
## owns focus and motion events never reach _forward_3d_gui_input.
const _DEFERRED_OPS: Array[int] = [20, 21, 23, 30, 31]

# ---------------------------------------------------------------------------
# External references (set by setup())
# ---------------------------------------------------------------------------

var _gizmo_plugin: GoBuildGizmoPlugin = null
var _panel: GoBuildPanel              = null
var _editor_plugin: EditorPlugin      = null
var _drag_controller: GoBuildDragController = null
var _edited_node: GoBuildMeshInstance = null

## When true, the SIC skips drawing its param-preview indicator because the
## DragController is drawing its own.  Set by plugin.gd on each overlay draw.
var _suppress_preview_indicator: bool = false

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
## Mouse mode saved when a gizmo drag starts, so it can be restored on end.
var _gizmo_saved_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE
## New edge indices to select after a gizmo drag completes (e.g. extrude edge).
var _pending_edge_selection: Array[int] = []

# ---------------------------------------------------------------------------
# Right-click context-menu state
# ---------------------------------------------------------------------------

var _right_click_press_pos: Vector2 = Vector2.ZERO
var _right_click_dragged:   bool    = false
var _context_menu_open:     bool    = false
var _context_camera:        Camera3D = null

# ── Loop cycling state ─────────────────────────────────────────────────
## When the user Alt+Clicks the same edge repeatedly, cycle through loop
## options (topology loop → boundary loop → ring).  Stored as the seed edge
## index, the list of options, and the current cycle index.
var _loop_cycle_seed: int = -1
var _loop_cycle_options: Array[Dictionary] = []
var _loop_cycle_index: int = 0

# ── Parameter-preview state ─────────────────────────────────────────────────
## Active preview, or [code]null[/code] when idle.
var _param_preview: GoBuildParamPreview = null
## Accumulated horizontal mouse delta since the preview started.
var _param_preview_delta: float = 0.0
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
## Accumulated parameter contribution from previous precision segments.
## On each Shift toggle, the amount consumed at the previous precision rate
## is folded into this offset so that the visual indicator (anchor-to-cursor
## line) stays in place and only the sensitivity changes.
var _param_preview_precision_offset: float       = 0.0


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Call immediately after construction, before any [method process_input] calls.
func setup(
		gizmo_plugin: GoBuildGizmoPlugin,
		panel: GoBuildPanel,
		editor_plugin: EditorPlugin,
		drag_controller: GoBuildDragController = null,
) -> void:
	_gizmo_plugin  = gizmo_plugin
	_panel         = panel
	_editor_plugin = editor_plugin
	_drag_controller = drag_controller


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
		if _context_menu_open:
			return 1
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
## When the DragController is active in param mode, it handles the indicator
## drawing via plugin.gd, so the SIC skips its own indicator to avoid double-draw.
func draw_overlay(overlay: Control) -> void:
	if _box_select_active:
		var rect: Rect2 = _get_box_select_rect()
		overlay.draw_rect(rect, Color(0.25, 0.45, 0.8, 0.15), true)
		overlay.draw_rect(rect, Color(0.5, 0.7, 1.0, 0.85), false)
	if _param_preview != null and _preview_accepting_motion and not _suppress_preview_indicator:
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
	if _param_preview != null:
		_cancel_param_preview_via_controller(edited_node)
	elif _drag_controller != null and _drag_controller.is_active():
		_drag_controller.cancel()
		_cleanup_preview_state()
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
func begin_param_preview(preview: GoBuildParamPreview, edited_node: GoBuildMeshInstance) -> void:
	_param_preview       = preview
	_param_preview_delta = 0.0
	_param_preview_precision_offset = 0.0
	_edited_node         = edited_node
	# Capture viewport display size for the overlay indicator.
	var sv: SubViewport = EditorInterface.get_editor_viewport_3d(0)
	_preview_vp_size = Vector2(1280, 720)  # safe fallback
	if sv != null:
		var vp_parent := sv.get_parent() as Control
		if vp_parent != null:
			_preview_vp_size = Vector2(vp_parent.size)
	_preview_anchor_vp   = _preview_vp_size * 0.5
	_preview_virtual_pos = _preview_anchor_vp
	# Capture mouse: hides cursor and provides mm.relative deltas regardless of
	# which panel has focus.  Events are intercepted globally by plugin._input()
	# and routed here via process_global_motion/process_global_button, bypassing
	# the viewport's _forward_3d_gui_input which breaks under MOUSE_MODE_CAPTURED
	# after a context-menu popup close.
	_preview_saved_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Defer accepting motion so button-release events in this frame drain first.
	_preview_active          = true
	_preview_accepting_motion = false
	_preview_filter_count     = 2
	_preview_prev_shift      = Input.is_key_pressed(KEY_SHIFT)
	# Defer accepting motion so button-release events drain before accumulation
	# starts.  Filter count skips any large synthetic events that arrive on the
	# first frame (e.g. from a context menu popup close).
	_preview_active          = true
	_preview_accepting_motion = false
	_preview_filter_count     = 2
	_preview_prev_shift      = Input.is_key_pressed(KEY_SHIFT)
	# Sync the drag controller's viewport anchor so its overlay matches ours.
	if _drag_controller != null and _drag_controller.is_active():
		_drag_controller.set_viewport_info(_preview_anchor_vp, _preview_vp_size)
	call_deferred("_accept_preview_motion")


## Called at start of the frame after [method begin_param_preview] to allow
## motion events.  The deferred call lets synthetic warp/click events drain first.
func _accept_preview_motion() -> void:
	_preview_accepting_motion = true

## [code]true[/code] while a parameter-preview is active.
func has_active_param_preview() -> bool:
	return _param_preview != null


## Set whether the SIC should suppress its own param-preview indicator drawing.
## Called each frame by plugin.gd to avoid double-drawing when the DragController
## is providing the indicator.
func set_suppress_preview_indicator(suppress: bool) -> void:
	_suppress_preview_indicator = suppress


## Global input dispatch for events captured via [method EditorPlugin._input].
##
## Called from plugin.gd's [method _input].  When a param preview or gizmo drag
## is active (MOUSE_MODE_CAPTURED), the viewport stops forwarding events through
## _forward_3d_gui_input, so the plugin intercepts them globally and routes
## them here.  Returns [code]true[/code] if the event was consumed and should
## be marked as handled, [code]false[/code] otherwise.
func handle_global_input(event: InputEvent) -> bool:
	if _param_preview != null:
		GoBuildDebug.log("[GoBuild] SIC  handle_global_input  "
				+ "_param_preview != null — routed to param preview")
		if event is InputEventMouseMotion:
			process_global_motion(event as InputEventMouseMotion)
			return true
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
				process_global_button(mb)
				return true
		if event is InputEventKey:
			if (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
				_cancel_param_preview_via_controller(_edited_node)
				return true
		return false
	# Gizmo drag: route motion events to DragController.  Button events
	# (LMB commit, RMB cancel) are handled here because MOUSE_MODE_CAPTURED
	# prevents them from reaching _forward_3d_gui_input.
	if _dragging_handle:
		if event is InputEventMouseMotion:
			if _drag_controller != null and _drag_controller.is_active():
				_drag_controller.handle_motion_event(event as InputEventMouseMotion)
			if _gizmo_plugin != null and _edited_node != null \
					and is_instance_valid(_edited_node):
				_gizmo_plugin.schedule_gizmo_redraw(_edited_node)
			return true
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if not mb.pressed:
				if mb.button_index == MOUSE_BUTTON_LEFT:
					_commit_gizmo_drag()
					return true
				if mb.button_index == MOUSE_BUTTON_RIGHT:
					_cancel_gizmo_drag()
					return true
		if event is InputEventKey:
			if (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
				_cancel_gizmo_drag()
				return true
	return false


## Handle mouse motion during param preview, called from [method EditorPlugin._input]
## when [member _param_preview] is active.  This bypasses the viewport's event
## routing entirely, receiving events regardless of which panel has focus.
## Necessary because MOUSE_MODE_CAPTURED stops forwarding events through
## _forward_3d_gui_input.
func process_global_motion(mm: InputEventMouseMotion) -> void:
	if _param_preview == null:
		return
	if not _preview_accepting_motion:
		return
	if _preview_filter_count > 0:
		if mm.relative.length_squared() > 50.0 * 50.0:
			_preview_filter_count -= 1
			return
		_preview_filter_count = 0
	_preview_virtual_pos += mm.relative
	if _drag_controller != null and _drag_controller.is_active():
		_drag_controller.handle_motion_event(mm)
	_editor_plugin.update_overlays()


## Handle mouse button during param preview, called from [method EditorPlugin._input].
## Commit on LMB, cancel on RMB.
func process_global_button(mb: InputEventMouseButton) -> void:
	if _param_preview == null:
		return
	if not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		_commit_param_preview_via_controller(_edited_node)
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		_cancel_param_preview_via_controller(_edited_node)

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



# ---------------------------------------------------------------------------
# Mouse button dispatch
# ---------------------------------------------------------------------------

func _handle_mouse_button(
		edited_node: GoBuildMeshInstance,
		camera: Camera3D,
		mb: InputEventMouseButton,
) -> int:
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		if _context_menu_open:
			return 1
		var has_gobuild: bool = edited_node != null
		if mb.pressed:
			_cancel_active_drag(edited_node)
			_cancel_box_select(edited_node)
			_right_click_press_pos = mb.position
			_right_click_dragged   = false
			_context_camera = camera
		else:
			if has_gobuild and not _right_click_dragged:
				_show_context_menu_deferred(edited_node, mb.position)
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
		if _drag_controller != null and _drag_controller.is_active():
			_drag_controller.commit()
		_apply_pending_edge_selection(edited_node)
		_dragging_handle  = false
		_active_handle_id = -1
		Input.mouse_mode = _gizmo_saved_mouse_mode
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
	# Alt+click (no drag) = Loop Select; Ctrl+Alt+click = Ring Select.
	# Alt held during drag is vertex snap, handled elsewhere.
	if mb.alt_pressed and edited_node != null:
		return _handle_loop_ring_pick(
				edited_node, camera, _box_select_start,
				mb.shift_pressed, mb.ctrl_pressed)
	return _handle_pick(edited_node, camera, _box_select_start,
			mb.shift_pressed, mb.ctrl_pressed)


func _handle_mouse_motion(
		edited_node: GoBuildMeshInstance,
		camera: Camera3D,
		mm: InputEventMouseMotion,
) -> int:
	if _dragging_handle:
		if _drag_controller != null and _drag_controller.is_active():
			_drag_controller.handle_motion_raw(
					mm.relative, mm.shift_pressed, mm.ctrl_pressed, camera)
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
				started = _start_normal_gizmo_drag(edited_node, _pressed_handle_id)
			if started:
				_dragging_handle   = true
				_active_handle_id  = _pressed_handle_id
				_pressed_handle_id = -1
				_edited_node      = edited_node
				GoBuildDebug.log("[GoBuild] SIC  gizmo drag start  handle=%d  CAPTURED" \
						% _active_handle_id)
				_gizmo_saved_mouse_mode = Input.mouse_mode
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
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
## Builds the DragOperation directly via GoBuildDragController.
## Overrides the snapshot with the pre-extrude state so undo restores the
## full pre-extrude mesh.  Returns false if anything fails.
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
	ExtrudeOperation.apply(gbm, faces, 0.0)
	edited_node.bake()

	# Collect top-ring vertex indices from the selected faces AFTER the extrude.
	var top_ring: Array[int] = []
	for fidx: int in faces:
		for vidx: int in gbm.faces[fidx].vertex_indices:
			if not top_ring.has(vidx):
				top_ring.append(vidx)

	# Build initial_verts dict from only the top-ring (moving) vertices.
	var initial_verts: Dictionary = {}
	for vidx: int in top_ring:
		initial_verts[vidx] = gbm.vertices[vidx]

	var started: bool = _start_gizmo_drag_with_verts(
			edited_node, handle_id, initial_verts, pre_snap, "Extrude Face")
	if not started:
		edited_node.restore_and_bake(pre_snap)
	return started


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
## Builds the DragOperation directly via GoBuildDragController.
## Returns false if anything fails.
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
	var centroids_out: Dictionary = {}
	InsetOperation.apply(gbm, faces, 0.0, centroids_out)
	edited_node.bake()

	# Build initial_verts from all affected vertices.
	var affected: Array[int] = GoBuildTransformHelpers.get_affected_vertex_indices(edited_node)
	if affected.is_empty():
		edited_node.restore_and_bake(pre_snap)
		return false
	var initial_verts: Dictionary = {}
	for idx: int in affected:
		initial_verts[idx] = gbm.vertices[idx]

	var snap_default: float = GoBuildTransformHelpers.get_snap_step(
			_gizmo_plugin.snap_step_override)
	var preview_mode: bool = edited_node.auto_uv_mode != GoBuildFace.UvMode.NONE
	var op := GoBuildDragOperation.create_for_gizmo_handle(
			edited_node,
			handle_id,
			initial_verts,
			pre_snap,
			"Inset Face",
			snap_default,
			_gizmo_plugin.rot_snap_override,
			_gizmo_plugin.scale_snap_override,
			_gizmo_plugin.snap_mode_override,
			centroids_out,
			0.0,
			true,
			preview_mode,
			_gizmo_plugin.transform_space)
	if op == null:
		edited_node.restore_and_bake(pre_snap)
		return false
	_drag_controller.begin(op, false)
	_seed_drag_controller_viewport()
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
## Builds the DragOperation directly via GoBuildDragController.
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
	var new_edge_indices: Array[int] = EdgeExtrudeOperation.apply(gbm, source_edges)
	if new_edge_indices.is_empty():
		return false

	edited_node.bake()

	# Collect the vertex indices for the new boundary edge endpoints.
	_pending_edge_selection.clear()
	_pending_edge_selection.assign(new_edge_indices)
	var new_verts: Array[int] = []
	for ei: int in new_edge_indices:
		var edge: GoBuildEdge = gbm.edges[ei]
		if not new_verts.has(edge.vertex_a):
			new_verts.append(edge.vertex_a)
		if not new_verts.has(edge.vertex_b):
			new_verts.append(edge.vertex_b)

	# Build initial_verts dict from only the new edge vertices.
	var initial_verts: Dictionary = {}
	for vidx: int in new_verts:
		initial_verts[vidx] = gbm.vertices[vidx]

	var started: bool = _start_gizmo_drag_with_verts(
			edited_node, handle_id, initial_verts, pre_snap, "Extrude Edge")
	if not started:
		edited_node.restore_and_bake(pre_snap)
	return started


# ---------------------------------------------------------------------------
# Handle picking
# ---------------------------------------------------------------------------

func _apply_pending_edge_selection(edited_node: GoBuildMeshInstance) -> void:
	if _pending_edge_selection.is_empty():
		return
	if edited_node == null or not is_instance_valid(edited_node):
		_pending_edge_selection.clear()
		return
	var edges: Array[int] = []
	edges.assign(_pending_edge_selection)
	_pending_edge_selection.clear()
	edited_node.selection.set_mode(SelectionManager.Mode.EDGE)
	edited_node.selection.set_selected_edges(edges)


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
	var lc: Vector3 = _gizmo_plugin.get_selection_local_centroid(edited_node)
	var s: float        = _gizmo_plugin.compute_world_gizmo_scale(gt * lc)
	var cone_h: float   = GoBuildGizmoPlugin.CONE_HEIGHT * s
	var local_axes: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var use_basis: Basis = gt.basis
	if _gizmo_plugin.transform_space == GoBuildGizmoPlugin.TransformSpace.WORLD:
		use_basis = Basis()
	for i: int in 3:
		var apex_world: Vector3 = positions[i]
		if not camera.is_position_in_frustum(apex_world):
			continue
		var world_axis: Vector3 = (use_basis * local_axes[i]).normalized()
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
	var inv_basis: Basis = Basis()
	if _gizmo_plugin.transform_space == GoBuildGizmoPlugin.TransformSpace.WORLD:
		inv_basis = gt.basis.inverse()
	var axis_x := inv_basis * Vector3.RIGHT
	var axis_y := inv_basis * Vector3.UP
	var axis_z := inv_basis * Vector3.BACK
	var local_centers: Array[Vector3] = [
		lc + (axis_x + axis_y) * inner,
		lc + (axis_y + axis_z) * inner,
		lc + (axis_x + axis_z) * inner,
	]
	var half: float = GoBuildGizmoPlugin.PLANE_HALF * s
	var plane_edge_offsets: Array[Vector3] = [
		axis_x * half,
		axis_y * half,
		axis_x * half,
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
	var use_basis: Basis = gt.basis
	if _gizmo_plugin.transform_space == GoBuildGizmoPlugin.TransformSpace.WORLD:
		use_basis = Basis()
	var best_id:  int   = -1
	var best_err: float = tol

	for i: int in 3:
		var world_normal: Vector3 = (use_basis * local_normals[i]).normalized()
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
# Loop / Ring selection (Alt+click and Ctrl+Alt+click)
# ---------------------------------------------------------------------------

## Handle Alt+click (Path/Ring Select) and Ctrl+Alt+click (Ring Select).
##
## Edge mode: selects edges (loop/ring of edges from the clicked edge).
## Face mode + Loop (Alt): selects the shortest face path from the last
## selected face to the clicked face.  If nothing is selected yet, just
## selects the clicked face.
## Face mode + Ring (Ctrl+Alt): selects the face ring from the nearest
## edge of the clicked face, using the clicked face as the side.
## Shift adds to current selection; without Shift, replaces the selection.
func _handle_loop_ring_pick(
		edited_node: GoBuildMeshInstance,
		camera: Camera3D,
		click_pos: Vector2,
		additive: bool,
		ring: bool,
) -> int:
	var sel: SelectionManager = edited_node.selection
	var mode: SelectionManager.Mode = sel.get_mode()
	var gbm: GoBuildMesh = edited_node.go_build_mesh
	if gbm == null or gbm.edges.is_empty():
		return 1
	if mode == SelectionManager.Mode.VERTEX:
		return _handle_pick(edited_node, camera, click_pos, additive, false)
	# Capture pre-clear selection for path computation.
	var pre_edges: Array[int] = []
	var pre_faces: Array[int] = []
	if mode == SelectionManager.Mode.EDGE and not ring:
		pre_edges = sel.get_selected_edges()
	elif mode == SelectionManager.Mode.FACE and not ring:
		pre_faces = sel.get_selected_faces()
	if not additive:
		sel.clear()
	if mode == SelectionManager.Mode.EDGE:
		_handle_edge_loop_ring(gbm, edited_node, camera, click_pos, sel, pre_edges, ring)
	elif mode == SelectionManager.Mode.FACE:
		_handle_face_loop_ring(gbm, edited_node, camera, click_pos, sel, pre_faces, ring)
	edited_node.update_gizmos()
	return 1


func _handle_edge_loop_ring(
		gbm: GoBuildMesh,
		edited_node: GoBuildMeshInstance,
		camera: Camera3D,
		click_pos: Vector2,
		sel: SelectionManager,
		pre_edges: Array[int],
		ring: bool,
) -> void:
	var seed_ei: int = PickingHelper.find_nearest_edge(camera, click_pos, edited_node, gbm)
	if seed_ei == -1:
		return
	if ring:
		for ei: int in SelectionHelpers.edge_ring(gbm, seed_ei):
			sel.select_edge(ei)
		_loop_cycle_seed = -1
		return
	# Loop / path mode.
	if not pre_edges.is_empty():
		var start_ei: int = pre_edges[pre_edges.size() - 1]
		if start_ei == seed_ei:
			# Clicked same edge as last selected — cycle loop options.
			if _loop_cycle_seed == seed_ei and not _loop_cycle_options.is_empty():
				_loop_cycle_index = (_loop_cycle_index + 1) % _loop_cycle_options.size()
				var option: Dictionary = _loop_cycle_options[_loop_cycle_index]
				var edges: Array[int] = option["edges"]
				sel.set_selected_edges(edges)
				return
			# First click on this edge — compute and store options for cycling.
			_loop_cycle_options = SelectionHelpers.edge_loop_options(gbm, seed_ei)
			_loop_cycle_seed = seed_ei
			_loop_cycle_index = 0
			var first_option: Dictionary = _loop_cycle_options[0]
			var edges: Array[int] = first_option["edges"]
			sel.set_selected_edges(edges)
			return
		# Check if seed_ei is in the current selection — if so, this is a cycle
		# request on the original loop edge, not a path request.
		if pre_edges.has(seed_ei) and _loop_cycle_seed == seed_ei \
				and not _loop_cycle_options.is_empty():
			_loop_cycle_index = (_loop_cycle_index + 1) % _loop_cycle_options.size()
			var option: Dictionary = _loop_cycle_options[_loop_cycle_index]
			var cycle_edges: Array[int] = option["edges"]
			sel.set_selected_edges(cycle_edges)
			return
		_loop_cycle_seed = -1
		var path: Array[int] = SelectionHelpers.edge_path(gbm, start_ei, seed_ei)
		if path.is_empty():
			sel.select_edge(seed_ei)
		else:
			for ei: int in path:
				sel.select_edge(ei)
	else:
		# No prior selection — compute loop options and select first.
		_loop_cycle_options = SelectionHelpers.edge_loop_options(gbm, seed_ei)
		_loop_cycle_seed = seed_ei
		_loop_cycle_index = 0
		var first_option: Dictionary = _loop_cycle_options[0]
		var edges: Array[int] = first_option["edges"]
		sel.set_selected_edges(edges)


func _handle_face_loop_ring(
		gbm: GoBuildMesh,
		edited_node: GoBuildMeshInstance,
		camera: Camera3D,
		click_pos: Vector2,
		sel: SelectionManager,
		pre_faces: Array[int],
		ring: bool,
) -> void:
	var fi: int = PickingHelper.find_nearest_face(camera, click_pos, edited_node, gbm)
	if fi == -1:
		return
	if ring:
		var seed_ei: int = _nearest_edge_of_face(camera, click_pos, edited_node, gbm, fi)
		if seed_ei != -1:
			for fj: int in SelectionHelpers.face_ring(gbm, seed_ei, fi):
				sel.select_face(fj)
		return
	# Path mode.
	var start_fi: int = -1
	if not pre_faces.is_empty():
		start_fi = pre_faces[pre_faces.size() - 1]
	if start_fi == -1 or start_fi == fi:
		sel.select_face(fi)
		return
	var path: Array[int] = SelectionHelpers.face_path(gbm, start_fi, fi)
	if path.is_empty():
		sel.select_face(fi)
	else:
		for fj: int in path:
			sel.select_face(fj)


## Find the nearest edge of a face to the screen-space click position.
func _nearest_edge_of_face(
		camera: Camera3D,
		click_pos: Vector2,
		edited_node: GoBuildMeshInstance,
		gbm: GoBuildMesh,
		fi: int,
) -> int:
	var face_edges: Array[int] = gbm.edges_of_face(fi)
	if face_edges.is_empty():
		return -1
	var best_ei: int = -1
	var best_dist_sq: float = INF
	var gt: Transform3D = edited_node.global_transform
	for ei: int in face_edges:
		var ed: GoBuildEdge = gbm.edges[ei]
		var va: Vector3 = gt * gbm.vertices[ed.vertex_a]
		var vb: Vector3 = gt * gbm.vertices[ed.vertex_b]
		var pa: Vector2 = camera.unproject_position(va)
		var pb: Vector2 = camera.unproject_position(vb)
		# Distance from click_pos to the 2D line segment pa-pb.
		var ab: Vector2 = pb - pa
		var ap: Vector2 = click_pos - pa
		var t: float = clampf(ap.dot(ab) / ab.dot(ab), 0.0, 1.0)
		var closest: Vector2 = pa + ab * t
		var dist_sq: float = click_pos.distance_squared_to(closest)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_ei = ei
	return best_ei


## Context-menu Face Loop (Path): raycast from the right-click position to
## find the target face, then compute [method SelectionHelpers.face_path] from
## the last selected face to the target face.  Additive: always adds to the
## current selection (Shift is not needed from the context menu).
func _context_face_loop(edited_node: GoBuildMeshInstance) -> void:
	if _context_camera == null:
		return
	var gbm: GoBuildMesh = edited_node.go_build_mesh
	if gbm == null or gbm.edges.is_empty():
		return
	var sel: SelectionManager = edited_node.selection
	var fi: int = PickingHelper.find_nearest_face(
			_context_camera, _right_click_press_pos, edited_node, gbm)
	if fi == -1:
		return
	var selected_faces: Array[int] = sel.get_selected_faces()
	if selected_faces.is_empty():
		sel.select_face(fi)
		edited_node.update_gizmos()
		return
	var start_fi: int = selected_faces[selected_faces.size() - 1]
	var path: Array[int] = SelectionHelpers.face_path(gbm, start_fi, fi)
	if path.is_empty():
		return
	for fj: int in path:
		sel.select_face(fj)
	edited_node.update_gizmos()


## Context-menu Face Ring: raycast from the right-click position to find the
## target face and its nearest edge, then compute the ring from that seed.
func _context_face_ring(edited_node: GoBuildMeshInstance) -> void:
	if _context_camera == null:
		return
	var gbm: GoBuildMesh = edited_node.go_build_mesh
	if gbm == null or gbm.edges.is_empty():
		return
	var sel: SelectionManager = edited_node.selection
	var fi: int = PickingHelper.find_nearest_face(
			_context_camera, _right_click_press_pos, edited_node, gbm)
	if fi == -1:
		return
	var seed_ei: int = _nearest_edge_of_face(
			_context_camera, _right_click_press_pos, edited_node, gbm, fi)
	if seed_ei == -1:
		return
	var face_indices: Array[int] = SelectionHelpers.face_ring(gbm, seed_ei, fi)
	sel.clear()
	for fj: int in face_indices:
		sel.select_face(fj)
	edited_node.update_gizmos()


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

func _cancel_active_drag(_edited_node: GoBuildMeshInstance) -> void:
	var was_dragging_handle: bool = _dragging_handle
	if _drag_controller != null and _drag_controller.is_active():
		_drag_controller.cancel()
	_dragging_handle   = false
	_active_handle_id  = -1
	_pressed_handle_id = -1
	_pending_edge_selection.clear()
	if was_dragging_handle:
		Input.mouse_mode = _gizmo_saved_mouse_mode


## Commit a gizmo drag initiated from global input (LMB release during
## MOUSE_MODE_CAPTURED).  DragController owns bake + undo for all gizmo drags.
func _commit_gizmo_drag() -> void:
	if _edited_node == null or not is_instance_valid(_edited_node):
		_dragging_handle = false
		_active_handle_id = -1
		Input.mouse_mode = _gizmo_saved_mouse_mode
		return
	if _drag_controller != null and _drag_controller.is_active():
		_drag_controller.commit()
	_apply_pending_edge_selection(_edited_node)
	_dragging_handle  = false
	_active_handle_id = -1
	Input.mouse_mode = _gizmo_saved_mouse_mode
	_edited_node.update_gizmos()


## Cancel a gizmo drag (RMB or ESC during MOUSE_MODE_CAPTURED).
func _cancel_gizmo_drag() -> void:
	if _drag_controller != null and _drag_controller.is_active():
		_drag_controller.cancel()
	_dragging_handle   = false
	_active_handle_id  = -1
	_pressed_handle_id = -1
	_pending_edge_selection.clear()
	Input.mouse_mode = _gizmo_saved_mouse_mode


func _cancel_box_select(edited_node: GoBuildMeshInstance) -> void:
	_box_select_started = false
	_box_select_active  = false
	if edited_node != null:
		edited_node.update_gizmos()
	_editor_plugin.update_overlays()


# ---------------------------------------------------------------------------
# Deferred context menu
# ---------------------------------------------------------------------------

## Show the context menu on the next frame so Godot has time to process
## the right-click release and restore the cursor from orbit mode.
func _show_context_menu_deferred(edited_node: GoBuildMeshInstance, at: Vector2) -> void:
	_show_context_menu.call_deferred(edited_node, at)


# ---------------------------------------------------------------------------
# DragController bridge — gizmo drags
# ---------------------------------------------------------------------------

## Start a normal gizmo drag by computing vertex data, snapshot, and DragOperation
## directly via [GoBuildDragController].
## Returns [code]true[/code] if the drag was started successfully.
func _start_normal_gizmo_drag(
		edited_node: GoBuildMeshInstance,
		handle_id: int,
) -> bool:
	if edited_node == null or edited_node.go_build_mesh == null:
		return false
	var gbm: GoBuildMesh = edited_node.go_build_mesh
	var affected: Array[int] = GoBuildTransformHelpers.get_affected_vertex_indices(edited_node)
	if affected.is_empty():
		return false
	var initial_verts: Dictionary = {}
	for idx: int in affected:
		initial_verts[idx] = gbm.vertices[idx]
	var snapshot: Dictionary = gbm.take_snapshot()
	var action_name: String = GoBuildDragOperation.action_name_for_handle(handle_id)
	var snap_default: float = GoBuildTransformHelpers.get_snap_step(
			_gizmo_plugin.snap_step_override)
	var vertex_update_mode: bool = true
	var preview_mode: bool = edited_node.auto_uv_mode != GoBuildFace.UvMode.NONE
	var op := GoBuildDragOperation.create_for_gizmo_handle(
			edited_node,
			handle_id,
			initial_verts,
			snapshot,
			action_name,
			snap_default,
			_gizmo_plugin.rot_snap_override,
			_gizmo_plugin.scale_snap_override,
			_gizmo_plugin.snap_mode_override,
			{},  # no inset centroids
			0.0,  # no inset offset
			vertex_update_mode,
			preview_mode,
			_gizmo_plugin.transform_space)
	if op == null:
		return false
	_drag_controller.begin(op, false)
	_seed_drag_controller_viewport()
	return true


## Start a gizmo drag with a custom set of initial vertex positions and
## snapshot.  Used for extrude and edge-extrude where only a subset of
## vertices should move.  The snapshot should be the pre-operation state so
## undo restores the full pre-operation mesh.
## Returns [code]true[/code] if the drag was started successfully.
func _start_gizmo_drag_with_verts(
		edited_node: GoBuildMeshInstance,
		handle_id: int,
		initial_verts: Dictionary,
		snapshot: Dictionary,
		action_name: String,
) -> bool:
	if edited_node == null or edited_node.go_build_mesh == null:
		return false
	if initial_verts.is_empty():
		return false
	var snap_default: float = GoBuildTransformHelpers.get_snap_step(
			_gizmo_plugin.snap_step_override)
	var preview_mode: bool = edited_node.auto_uv_mode != GoBuildFace.UvMode.NONE
	var op := GoBuildDragOperation.create_for_gizmo_handle(
			edited_node,
			handle_id,
			initial_verts,
			snapshot,
			action_name,
			snap_default,
			_gizmo_plugin.rot_snap_override,
			_gizmo_plugin.scale_snap_override,
			_gizmo_plugin.snap_mode_override,
			{},  # no inset centroids
			0.0,  # no inset offset
			true,  # vertex_update_mode
			preview_mode,
			_gizmo_plugin.transform_space)
	if op == null:
		return false
	_drag_controller.begin(op, false)
	_seed_drag_controller_viewport()
	return true


func _seed_drag_controller_viewport() -> void:
	var vp_size := Vector2(1280.0, 720.0)
	var sv: SubViewport = EditorInterface.get_editor_viewport_3d(0)
	if sv != null:
		var vp_parent := sv.get_parent() as Control
		if vp_parent != null:
			vp_size = Vector2(vp_parent.size)
	_drag_controller.set_viewport_info(vp_size * 0.5, vp_size)


# ---------------------------------------------------------------------------
# Context menu
# ---------------------------------------------------------------------------

## Show a [PopupMenu] at screen position [param at] with operations appropriate
## to the current edit mode and selection.
## Returns [code]true[/code] if a popup was shown (caller should consume the event),
## [code]false[/code] otherwise.
func _show_context_menu(edited_node: GoBuildMeshInstance, at: Vector2) -> bool:
	if edited_node == null:
		return false
	var mode: SelectionManager.Mode = edited_node.selection.get_mode()
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
	_context_menu_open = true
	popup.popup_hide.connect(func() -> void:
		_context_menu_open = false
	)
	popup.popup_hide.connect(popup.queue_free)

	# Add Shape submenu (available in all modes when a GoBuildMeshInstance is selected).
	var shape_submenu := PopupMenu.new()
	var shape_names: Array[String] = ShapeCreationCatalog.all_shapes()
	for i: int in shape_names.size():
		shape_submenu.add_item(shape_names[i], 100 + i)
	shape_submenu.id_pressed.connect(func(id: int) -> void:
		var idx: int = id - 100
		if idx >= 0 and idx < shape_names.size():
			_insert_shape_at_cursor(shape_names[idx], edited_node)
	)
	popup.add_child(shape_submenu)
	popup.add_submenu_item("Add Shape", shape_submenu.get_name())

	if mode != SelectionManager.Mode.OBJECT:
		popup.add_item("Select All", 1)
		if not sel.is_empty():
			popup.add_item("Grow Selection  (Ctrl+=)", 2)
		if not sel.is_empty():
			popup.add_item("Shrink Selection  (Ctrl+-)", 3)
		if mode == SelectionManager.Mode.EDGE:
			if not sel.is_empty():
				popup.add_item("Select Loop  (Alt+Click)", 40)
				popup.add_item("Select Ring  (Ctrl+Alt+Click)", 41)
		elif mode == SelectionManager.Mode.FACE:
			popup.add_item("Select Path  (Alt+Click)", 40)
			popup.add_item("Select Ring  (Ctrl+Alt+Click)", 41)
		if not sel.is_empty():
			_add_similar_submenu(popup, mode, edited_node)

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
				popup.add_item("Bridge/Fill  (F)", 22)
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
				popup.add_item("Add Texture", 37)
				popup.add_separator()
				popup.add_item("Delete", 10)

	var mode_int: int = mode as int
	popup.id_pressed.connect(
			func(id: int) -> void: _on_context_menu_pressed(id, mode_int, edited_node))
	popup.popup(Rect2i(screen_at, Vector2i.ZERO))
	return true


## Add a "Select Similar" submenu to [param popup] with criteria appropriate
## for the current selection [param mode].
func _add_similar_submenu(
		popup: PopupMenu,
		mode: SelectionManager.Mode,
		edited_node: GoBuildMeshInstance,
) -> void:
	var submenu := PopupMenu.new()
	var mode_int: int = mode as int
	match mode:
		SelectionManager.Mode.VERTEX:
			submenu.add_item("Valence", 58)
		SelectionManager.Mode.EDGE:
			submenu.add_item("Length", 55)
			submenu.add_item("Face Count", 56)
			submenu.add_item("Dihedral Angle", 57)
		SelectionManager.Mode.FACE:
			submenu.add_item("Material", 50)
			submenu.add_item("Side Count", 51)
			submenu.add_item("Normal", 52)
			submenu.add_item("Coplanar", 53)
			submenu.add_item("Area", 54)
	popup.add_child(submenu)
	popup.add_submenu_item("Select Similar", submenu.get_name())
	submenu.id_pressed.connect(func(id: int) -> void:
			_on_context_menu_pressed(id, mode_int, edited_node)
	)


func _on_context_menu_pressed(
		id: int,
		mode_int: int,
		edited_node: GoBuildMeshInstance,
) -> void:
	if edited_node == null:
		return
	var sel: SelectionManager = edited_node.selection
	var gbm = edited_node.go_build_mesh
	# Param-preview operations must be deferred until the popup has fully closed
	# and the 3D viewport has reclaimed input focus.  Without deferral,
	# MOUSE_MODE_CAPTURED is set while the popup still owns focus, so motion
	# events never reach _forward_3d_gui_input and the drag is dead.
	if id in _DEFERRED_OPS:
		call_deferred("_deferred_context_op", id)
		return
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
		2:  # Grow Selection
			if _panel != null:
				_panel.trigger_grow()
		3:  # Shrink Selection
			if _panel != null:
				_panel.trigger_shrink()
		40:  # Select Loop
			if mode_int == SelectionManager.Mode.FACE:
				_context_face_loop(edited_node)
			elif _panel != null:
				_panel.trigger_select_loop()
		41:  # Select Ring
			if mode_int == SelectionManager.Mode.FACE:
				_context_face_ring(edited_node)
			elif _panel != null:
				_panel.trigger_select_ring()
		10:  # Delete
			if _panel != null:
				_panel.trigger_delete()
		11:  # Merge vertices
			if _panel != null:
				_panel.trigger_merge()
		12:  # Weld (merge by distance)
			if _panel != null:
				_panel.trigger_weld()
		22:  # Bridge/Fill
			if _panel != null:
				_panel.trigger_bridge()
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
		37:  # Add Texture
			if _panel != null:
				_panel.trigger_add_tex()
		50:  # Select Similar → Material (Face)
			if _panel != null:
				_panel.trigger_select_similar(SelectionHelpers.FaceSimilarCriterion.MATERIAL)
		51:  # Select Similar → Side Count (Face)
			if _panel != null:
				_panel.trigger_select_similar(SelectionHelpers.FaceSimilarCriterion.SIDE_COUNT)
		52:  # Select Similar → Normal (Face)
			if _panel != null:
				_panel.trigger_select_similar(SelectionHelpers.FaceSimilarCriterion.NORMAL)
		53:  # Select Similar → Coplanar (Face)
			if _panel != null:
				_panel.trigger_select_similar(SelectionHelpers.FaceSimilarCriterion.COPLANAR)
		54:  # Select Similar → Area (Face)
			if _panel != null:
				_panel.trigger_select_similar(SelectionHelpers.FaceSimilarCriterion.AREA)
		55:  # Select Similar → Length (Edge)
			if _panel != null:
				_panel.trigger_select_similar(SelectionHelpers.EdgeSimilarCriterion.LENGTH)
		56:  # Select Similar → Face Count (Edge)
			if _panel != null:
				_panel.trigger_select_similar(SelectionHelpers.EdgeSimilarCriterion.FACE_COUNT)
		57:  # Select Similar → Dihedral Angle (Edge)
			if _panel != null:
				_panel.trigger_select_similar(SelectionHelpers.EdgeSimilarCriterion.DIHEDRAL)
		58:  # Select Similar → Valence (Vertex)
			if _panel != null:
				_panel.trigger_select_similar(SelectionHelpers.VertexSimilarCriterion.VALENCE)


## Insert a new [GoBuildMeshInstance] at the right-click position.
##
## Uses [ShapePlacement] to determine the world position and parent.
## On hit, the new node becomes a child of the hit mesh, offset flush
## on the surface.  On miss, it becomes a sibling under the edited node's
## parent (or scene root) at the Y-plane intersection.
## Delegates to [GoBuildCreateDrawer.insert_shape] for the actual insertion.
func _insert_shape_at_cursor(
		shape_name: String,
		edited_node: GoBuildMeshInstance,
) -> void:
	if _editor_plugin == null:
		return

	var camera: Camera3D = _context_camera
	if camera == null:
		camera = EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	if camera == null:
		return

	var align_to_surface: bool = true
	if _panel != null and _panel.get_create_drawer() != null:
		align_to_surface = _panel.get_create_drawer().is_align_to_surface()

	if _panel != null and _panel.get_create_drawer() != null:
		_panel.get_create_drawer().start_shape_draw_at(
				shape_name, camera, _right_click_press_pos, edited_node)


func _deferred_context_op(id: int) -> void:
	if _panel == null:
		return
	match id:
		20:  _panel.trigger_bevel()
		21:  _panel.trigger_extrude_edge()
		23:  _panel.trigger_loop_cut()
		30:  _panel.trigger_extrude()
		31:  _panel.trigger_inset()


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
			_cancel_param_preview_via_controller(edited_node)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if not _preview_accepting_motion:
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if _preview_filter_count > 0:
			if mm.relative.length_squared() > 50.0 * 50.0:
				_preview_filter_count -= 1
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			_preview_filter_count = 0
		_preview_virtual_pos += mm.relative
		if _drag_controller != null and _drag_controller.is_active():
			_drag_controller.handle_motion_event(mm)
		_editor_plugin.update_overlays()
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_commit_param_preview_via_controller(edited_node)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_param_preview_via_controller(edited_node)
			return EditorPlugin.AFTER_GUI_INPUT_STOP

	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _commit_param_preview_via_controller(_edited_node: GoBuildMeshInstance) -> void:
	if _drag_controller != null and _drag_controller.is_active():
		_drag_controller.commit()
	_cleanup_preview_state()


func _cancel_param_preview_via_controller(edited_node: GoBuildMeshInstance) -> void:
	if _drag_controller != null and _drag_controller.is_active():
		_drag_controller.cancel()
	_cleanup_preview_state()
	if edited_node != null and is_instance_valid(edited_node):
		edited_node.update_gizmos()
	if _editor_plugin != null:
		_editor_plugin.update_overlays()


## Reset SIC-side preview bookkeeping after the controller has handled
## commit/cancel.  The controller owns mesh mutation; this only clears
## mouse mode and SIC tracking state.
func _cleanup_preview_state() -> void:
	_preview_accepting_motion = false
	_preview_filter_count     = 0
	_preview_virtual_pos      = Vector2.ZERO
	_preview_active           = false
	Input.mouse_mode = _preview_saved_mouse_mode
	_param_preview             = null
	_param_preview_delta       = 0.0
	_param_preview_precision_offset = 0.0
