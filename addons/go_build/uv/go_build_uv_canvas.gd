## 2D canvas that draws the UV layout of the active [GoBuildMeshInstance].
##
## Displays all face UVs as wireframe polygons in the 0-1 UV tile.
## Selected faces are highlighted.  Supports:
## - Pan (middle-mouse drag) and zoom (scroll wheel).
## - Click a UV face to select it (synced with the 3D viewport).
## - Shift+click adds; Ctrl+click toggles.
## - Drag with left mouse to box-select faces in UV space.
## - W/E/R keys switch transform mode (Move/Rotate/Scale) for selected islands.
## - Left-drag on a selected island to transform its UVs.
@tool
class_name GoBuildUvCanvas
extends Control

## Emitted when the background mode or material index changes (including
## auto-switch), so the panel can update its dropdown.
signal bg_mode_changed

## Transform mode for island manipulation.
enum UvTransformMode {
	MOVE   = 0,
	ROTATE = 1,
	SCALE  = 2,
}

## Background image mode for the UV tile.
enum UvBgMode {
	CHECKER  = 0,
	OFF      = 1,
	## Show the albedo texture from a specific material slot.
	## The slot index is stored in _bg_material_index.
	TEXTURE  = 2,
}

## Selection mode inside the UV editor.
enum UvSelectMode {
	FACE   = 0,
	VERTEX = 1,
}

# Self-preloads — compile-time type references.
const _SEL_MGR_SCRIPT        := preload("res://addons/go_build/core/selection_manager.gd")
const _FACE_SCRIPT           := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MESH_SCRIPT           := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _PICKER_SCRIPT         := preload("res://addons/go_build/uv/uv_picker.gd")
const _ISLAND_XFORM_SCRIPT   := preload("res://addons/go_build/uv/uv_island_transform.gd")
const _VERT_XFORM_SCRIPT     := preload("res://addons/go_build/uv/uv_vertex_transform.gd")

# ---------------------------------------------------------------------------
# Colours
# ---------------------------------------------------------------------------
const _BG_COLOR           := Color(0.12, 0.12, 0.12)
const _TILE_BG_COLOR      := Color(0.17, 0.17, 0.17)
const _TILE_BORDER_COLOR  := Color(0.55, 0.55, 0.55)
const _HALF_LINE_COLOR    := Color(0.30, 0.30, 0.30)
const _CHECKER_LIGHT      := Color(0.35, 0.35, 0.35)
const _CHECKER_DARK       := Color(0.22, 0.22, 0.22)
const _FACE_WIRE_COLOR    := Color(0.45, 0.65, 1.0, 0.75)
const _SEL_FILL_COLOR     := Color(1.0, 0.70, 0.20, 0.18)
const _SEL_WIRE_COLOR     := Color(1.0, 0.85, 0.35, 1.0)
const _BOX_SELECT_COLOR   := Color(0.40, 0.70, 1.0, 0.15)
const _BOX_BORDER_COLOR   := Color(0.40, 0.70, 1.0, 0.60)
const _GIZMO_AXIS_X_COLOR  := Color(0.95, 0.35, 0.35, 0.90)
const _GIZMO_AXIS_Y_COLOR  := Color(0.35, 0.80, 0.40, 0.90)
const _GIZMO_ARROW_SIZE    := 7.0
const _GIZMO_CIRCLE_COLOR := Color(0.35, 0.80, 0.40, 0.80)
const _PIVOT_COLOR        := Color(1.0, 1.0, 1.0, 0.70)
const _VTX_DOT_COLOR     := Color(0.6, 0.85, 1.0, 0.9)
const _VTX_SEL_COLOR     := Color(1.0, 0.85, 0.35, 1.0)
const _VERT_PICK_RADIUS: float = 12.0
const _DELTA_LINE_COLOR  := Color(1.0, 0.92, 0.4, 0.70)
const _DELTA_ARC_COLOR   := Color(1.0, 0.92, 0.4, 0.55)
const _DELTA_TEXT_COLOR  := Color(1.0, 0.92, 0.4, 0.92)
const _PRECISION_TEXT_COLOR := Color(0.5, 0.85, 1.0, 0.92)
const _ORIGIN_MARKER_COLOR := Color(1.0, 1.0, 1.0, 0.50)

# ---------------------------------------------------------------------------
# View state
# ---------------------------------------------------------------------------
const _ZOOM_MIN:     float = 40.0
const _ZOOM_MAX:     float = 8000.0
const _ZOOM_DEFAULT: float = 180.0
const _CLICK_THRESHOLD: float = 8.0

## Pixels per UV unit.
var _zoom: float = _ZOOM_DEFAULT
## Pan offset in pixels, relative to the canvas centre.
var _pan: Vector2 = Vector2.ZERO

## True while the user is middle-mouse dragging (pan view).
var _pan_dragging:       bool    = false
var _pan_drag_start:     Vector2 = Vector2.ZERO
var _pan_drag_start_pan: Vector2 = Vector2.ZERO

## The mesh node being visualised (may be null).
var _target: MeshInstance3D = null

## Reference to the EditorPlugin so UV mutations can access undo/redo.
var _plugin: EditorPlugin = null

## Active transform mode for island editing.
var _transform_mode: UvTransformMode = UvTransformMode.MOVE

## Active background mode (checker / texture / off).
var _bg_mode: UvBgMode = UvBgMode.CHECKER

## Which material slot to display the albedo texture for when
## [member _bg_mode] is [constant UvBgMode.TEXTURE].
var _bg_material_index: int = 0

## When true, the background texture auto-switches to the material
## of the first selected face.
var _auto_switch_bg: bool = true

## When true, only selected faces are drawn; unselected faces are hidden.
var _isolate_selected: bool = false

## UV snap grid size. When > 0 and Ctrl is held during a drag, UV positions
## are snapped to this increment. Default 1/16th of a UV unit (0.0625).
var _uv_snap_size: float = 0.0625

## Active selection mode (face / vertex) in the UV editor.
var _uv_select_mode: UvSelectMode = UvSelectMode.FACE

## Selected UV vertices as PackedVector2i of (face_index, uv_index).
var _selected_uv_verts: Array[Vector2i] = []

## True while dragging selected UV vertices.
var _vert_dragging:      bool     = false
var _vert_drag_state: UvVertexTransform.DragState = null

## Lazily-created checkerboard texture for the UV tile background.
var _checker_tex: ImageTexture = null

## Number of texture repeats for tile rendering (1 = single tile, 2+ = tiling).
var _tile_repeat: int = 1

## True while the user is left-dragging a selected island (UV transform).
var _island_dragging: bool = false
var _island_drag_state: UvIslandTransform.DragState = null

## Box-select state.
var _box_selecting:   bool    = false
var _box_select_start: Vector2 = Vector2.ZERO
var _box_select_end:   Vector2 = Vector2.ZERO

var _left_press_pos: Vector2 = Vector2.ZERO
var _left_moved:     bool    = false

## Keyboard state for modifier keys.
var _shift_held: bool = false
var _ctrl_held:  bool = false

## Face cycling state: on successive clicks at the same spot, cycle through
## overlapping faces instead of always picking the topmost.
var _last_click_uv: Vector2 = Vector2(INF, INF)
var _cycle_candidates: Array[int] = []
var _cycle_index: int = 0


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Switch to visualising [param node].
##
## Disconnects the previous target's [signal GoBuildMeshInstance.mesh_changed]
## signal and reconnects to the new one.
func set_target(node: MeshInstance3D) -> void:
	_cancel_island_drag()
	if _target != null and is_instance_valid(_target):
		if _target.mesh_changed.is_connected(_on_mesh_changed):
			_target.mesh_changed.disconnect(_on_mesh_changed)
		if _target.selection.selection_changed.is_connected(_on_selection_changed):
			_target.selection.selection_changed.disconnect(_on_selection_changed)
	_target = node
	if _target != null:
		_target.mesh_changed.connect(_on_mesh_changed)
		_target.selection.selection_changed.connect(_on_selection_changed)
	reset_view()


## Reset pan and zoom to defaults, centring the 0-1 UV tile in the view.
func reset_view() -> void:
	_zoom = _ZOOM_DEFAULT
	_pan = Vector2(-0.5 * _zoom, -0.5 * _zoom)
	queue_redraw()


## Return the current zoom level (pixels per UV unit).
func get_zoom() -> float:
	return _zoom


## Provide the owning [EditorPlugin] so UV mutations can use undo/redo.
func set_plugin(plugin: EditorPlugin) -> void:
	_plugin = plugin


## Return the active [enum UvTransformMode].
func get_transform_mode() -> UvTransformMode:
	return _transform_mode


## Set the active [enum UvTransformMode] (called by the panel buttons).
func set_transform_mode(mode: UvTransformMode) -> void:
	_transform_mode = mode
	queue_redraw()


## Return the active [enum UvBgMode].
func get_bg_mode() -> UvBgMode:
	return _bg_mode


## Cycle [enum UvBgMode]: Checker -> Off -> TEXTURE (slot 0) -> Checker.
## Note: the UV panel uses a dropdown instead of this cycle method.
func cycle_bg_mode() -> void:
	match _bg_mode:
		UvBgMode.CHECKER:
			_bg_mode = UvBgMode.OFF
		UvBgMode.OFF:
			_bg_mode = UvBgMode.TEXTURE
			_bg_material_index = 0
		UvBgMode.TEXTURE:
			_bg_mode = UvBgMode.CHECKER
	bg_mode_changed.emit()
	queue_redraw()


## Set [enum UvBgMode] directly.
func set_bg_mode(mode: UvBgMode) -> void:
	_bg_mode = mode
	bg_mode_changed.emit()
	queue_redraw()


## Return the material slot index shown in the background texture dropdown.
func get_bg_material_index() -> int:
	return _bg_material_index


## Set which material slot's albedo texture to display as the background.
func set_bg_material_index(idx: int) -> void:
	_bg_material_index = idx
	_bg_mode = UvBgMode.TEXTURE
	bg_mode_changed.emit()
	queue_redraw()


## Return whether auto-switching the background texture on selection is enabled.
func is_auto_switch_bg() -> bool:
	return _auto_switch_bg


## Enable or disable auto-switching the background texture on selection.
func set_auto_switch_bg(enabled: bool) -> void:
	_auto_switch_bg = enabled


## Return whether only selected faces are shown (isolation mode).
func is_isolate_selected() -> bool:
	return _isolate_selected


## Enable or disable isolation mode (show only selected faces).
func set_isolate_selected(enabled: bool) -> void:
	_isolate_selected = enabled
	queue_redraw()


## Return the UV snap grid size (0 = snap disabled).
func get_uv_snap_size() -> float:
	return _uv_snap_size


## Set the UV snap grid size. 0 disables snapping; typical values are
## 0.0625 (1/16), 0.125 (1/8), 0.25 (1/4), 0.5 (1/2).
func set_uv_snap_size(size: float) -> void:
	_uv_snap_size = size


## Return whether snapping is currently active (Ctrl held and snap size > 0).
func is_snapping() -> bool:
	return _ctrl_held and _uv_snap_size > 0.0


## Return the tile repeat count.
func get_tile_repeat() -> int:
	return _tile_repeat


## Set the tile repeat count (0 = single tile, 1+ = surrounding ring count).
func set_tile_repeat(count: int) -> void:
	_tile_repeat = maxi(count, 0)
	queue_redraw()


## Return the active [enum UvSelectMode].
func get_uv_select_mode() -> UvSelectMode:
	return _uv_select_mode


## Set the active [enum UvSelectMode].
func set_uv_select_mode(mode: UvSelectMode) -> void:
	_uv_select_mode = mode
	_selected_uv_verts.clear()
	_cycle_candidates.clear()
	queue_redraw()


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_mesh_changed() -> void:
	_auto_switch_bg_to_selection()
	queue_redraw()


func _on_selection_changed() -> void:
	_auto_switch_bg_to_selection()
	queue_redraw()


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), _BG_COLOR)
	_draw_grid()
	if _target == null or not is_instance_valid(_target):
		return
	if _target.go_build_mesh == null:
		return
	_draw_faces()
	if _uv_select_mode == UvSelectMode.VERTEX:
		_draw_uv_vertices()
	_draw_transform_gizmo()
	if _island_dragging and _island_drag_state != null:
		_draw_drag_overlay()
	if _vert_dragging and _vert_drag_state != null:
		_draw_vert_drag_overlay()
	if _box_selecting:
		_draw_box_select()


## Draw the UV-space tile (0-1 range) with border and half-way grid lines.
## When [member _tile_repeat] > 1, the grid extends symmetrically into
## negative UV space so the 0-1 tile stays centred.
func _draw_grid() -> void:
	var n: int = _tile_repeat
	var lo := -float(n)
	var hi := float(n) + 1.0
	var tl := _uv_to_canvas(Vector2(lo, lo))
	var br := _uv_to_canvas(Vector2(hi, hi))
	var tile_rect := Rect2(tl, br - tl)
	draw_rect(tile_rect, _TILE_BG_COLOR)

	match _bg_mode:
		UvBgMode.CHECKER:
			_ensure_checker_tex()
			_draw_tiled_checker()
		UvBgMode.TEXTURE:
			var tex := _get_bg_texture()
			if tex != null:
				_draw_tiled_texture(tex)

	# Draw tile outlines and grid lines for each repeat.
	var total_lines: int = 2 * n + 2
	for i: int in range(total_lines):
		var f := lo + float(i)
		var h_line_start := _uv_to_canvas(Vector2(lo, f))
		var h_line_end := _uv_to_canvas(Vector2(hi, f))
		draw_line(h_line_start, h_line_end, _TILE_BORDER_COLOR, 1.0)
		var v_line_start := _uv_to_canvas(Vector2(f, lo))
		var v_line_end := _uv_to_canvas(Vector2(f, hi))
		draw_line(v_line_start, v_line_end, _TILE_BORDER_COLOR, 1.0)
		if f != lo and f != hi and f != 0.0 and f != 1.0:
			draw_line(h_line_start, h_line_end, _HALF_LINE_COLOR, 0.5)
			draw_line(v_line_start, v_line_end, _HALF_LINE_COLOR, 0.5)


## Draw the checker texture tiled per unit across the repeat area.
func _draw_tiled_checker() -> void:
	var unit_size_px := _uv_to_canvas(Vector2(1.0, 1.0)) - _uv_to_canvas(Vector2.ZERO)
	var n: int = _tile_repeat
	for iy: int in range(-n, n + 1):
		for ix: int in range(-n, n + 1):
			var cell_tl := _uv_to_canvas(Vector2(float(ix), float(iy)))
			draw_texture_rect(_checker_tex, Rect2(cell_tl, unit_size_px), false)


## Draw the background texture tiled per unit across the repeat area.
func _draw_tiled_texture(tex: Texture2D) -> void:
	var unit_size_px := _uv_to_canvas(Vector2(1.0, 1.0)) - _uv_to_canvas(Vector2.ZERO)
	var n: int = _tile_repeat
	for iy: int in range(-n, n + 1):
		for ix: int in range(-n, n + 1):
			var cell_tl := _uv_to_canvas(Vector2(float(ix), float(iy)))
			draw_texture_rect(tex, Rect2(cell_tl, unit_size_px), false)


## Draw every face's UV polygon, highlighting selected faces.
## Selected faces are drawn last so they appear on top of unselected ones.
## When isolate is active, only faces in the 3D selection are drawn.
## In vertex selection mode, faces are drawn as a dim wireframe without
## selection fill so vertex dots are visually dominant.
func _draw_faces() -> void:
	var gbm: GoBuildMesh = _target.go_build_mesh
	var selected: Array[int] = _target.selection.get_selected_faces()

	var sel_set: Dictionary = {}
	for fi: int in selected:
		sel_set[fi] = true

	var in_vertex_mode: bool = _uv_select_mode == UvSelectMode.VERTEX

	if in_vertex_mode:
		var isolate_vis := _get_isolate_visible_faces()
		for fi: int in gbm.faces.size():
			if _is_isolate_active() and not isolate_vis.has(fi):
				continue
			var face: GoBuildFace = gbm.faces[fi]
			if face.uvs.size() < 3:
				continue
			var pts := PackedVector2Array()
			for uv: Vector2 in face.uvs:
				pts.append(_uv_to_canvas(uv))
			var closed_pts: PackedVector2Array = pts + PackedVector2Array([pts[0]])
			draw_polyline(closed_pts, _FACE_WIRE_COLOR, 1.0)
		return

	# Face mode drawing.
	if not _is_isolate_active():
		for fi: int in gbm.faces.size():
			var face: GoBuildFace = gbm.faces[fi]
			if face.uvs.size() < 3:
				continue
			if sel_set.has(fi):
				continue
			var pts := PackedVector2Array()
			for uv: Vector2 in face.uvs:
				pts.append(_uv_to_canvas(uv))
			var closed_pts: PackedVector2Array = pts + PackedVector2Array([pts[0]])
			draw_polyline(closed_pts, _FACE_WIRE_COLOR, 1.0)

	for fi: int in gbm.faces.size():
		var face: GoBuildFace = gbm.faces[fi]
		if face.uvs.size() < 3:
			continue
		if not sel_set.has(fi):
			continue
		var pts := PackedVector2Array()
		for uv: Vector2 in face.uvs:
			pts.append(_uv_to_canvas(uv))
		var closed_pts: PackedVector2Array = pts + PackedVector2Array([pts[0]])
		draw_polygon(pts, PackedColorArray([_SEL_FILL_COLOR]))
		draw_polyline(closed_pts, _SEL_WIRE_COLOR, 1.0)


## Draw dots at every UV vertex; highlight selected ones.
## When isolate is active, only draw vertices on faces from the 3D selection.
## Selected vertices are drawn in a second pass so they appear on top.
func _draw_uv_vertices() -> void:
	if _target == null or _target.go_build_mesh == null:
		return
	var gbm: GoBuildMesh = _target.go_build_mesh
	var sel_set: Dictionary = {}
	for v: Vector2i in _selected_uv_verts:
		sel_set[v] = true

	var visible_faces := _get_isolate_visible_faces()

	# Pass 1: unselected vertices.
	for fi: int in gbm.faces.size():
		if _is_isolate_active() and not visible_faces.has(fi):
			continue
		var face: GoBuildFace = gbm.faces[fi]
		for vi: int in face.uvs.size():
			if sel_set.has(Vector2i(fi, vi)):
				continue
			var px := _uv_to_canvas(face.uvs[vi])
			draw_circle(px, 3.0, _VTX_DOT_COLOR)

	# Pass 2: selected vertices (drawn on top).
	for fi: int in gbm.faces.size():
		if _is_isolate_active() and not visible_faces.has(fi):
			continue
		var face: GoBuildFace = gbm.faces[fi]
		for vi: int in face.uvs.size():
			if sel_set.has(Vector2i(fi, vi)):
				var px := _uv_to_canvas(face.uvs[vi])
				draw_circle(px, 4.0, _VTX_SEL_COLOR)


## Draw the transform gizmo for selected faces (move axis, rotate ring, scale handles).
func _draw_transform_gizmo() -> void:
	var sel_faces: Array[int] = _get_uv_selected_faces()
	if sel_faces.is_empty():
		return

	var pivot := _compute_pivot(sel_faces)
	var pivot_px := _uv_to_canvas(pivot)

	match _transform_mode:
		UvTransformMode.MOVE:
			var axis_len := 40.0
			var end_x := pivot_px + Vector2(axis_len, 0.0)
			var end_y := pivot_px + Vector2(0.0, -axis_len)
			draw_line(pivot_px, end_x, _GIZMO_AXIS_X_COLOR, 2.0)
			draw_line(pivot_px, end_y, _GIZMO_AXIS_Y_COLOR, 2.0)
			_draw_arrowhead(end_x, 0.0, _GIZMO_AXIS_X_COLOR)
			_draw_arrowhead(end_y, -PI * 0.5, _GIZMO_AXIS_Y_COLOR)
		UvTransformMode.ROTATE:
			var radius := 30.0
			draw_arc(pivot_px, radius, 0.0, TAU, 64, _GIZMO_CIRCLE_COLOR, 1.5)
		UvTransformMode.SCALE:
			var handle_len := 40.0
			var end_x := pivot_px + Vector2(handle_len, 0.0)
			var end_y := pivot_px + Vector2(0.0, -handle_len)
			draw_line(pivot_px, end_x, _GIZMO_AXIS_X_COLOR, 2.0)
			draw_line(pivot_px, end_y, _GIZMO_AXIS_Y_COLOR, 2.0)
			var tip_size := 4.0
			var tip_rect := Vector2(tip_size * 2, tip_size * 2)
			draw_rect(Rect2(end_x - Vector2(tip_size, tip_size), tip_rect), _GIZMO_AXIS_X_COLOR)
			draw_rect(Rect2(end_y - Vector2(tip_size, tip_size), tip_rect), _GIZMO_AXIS_Y_COLOR)

	draw_circle(pivot_px, 3.0, _PIVOT_COLOR)


## Draw the delta/origin overlay during an active island drag.
## Shows the reference pivot, a delta line/arc, and a numeric readout.
func _draw_drag_overlay() -> void:
	var ds: UvIslandTransform.DragState = _island_drag_state
	if ds == null:
		return

	var pivot_px := _uv_to_canvas(ds.pivot)
	var mouse_uv := _canvas_to_uv(get_local_mouse_position())
	var mouse_px := _uv_to_canvas(mouse_uv)

	draw_circle(pivot_px, 6.0, _ORIGIN_MARKER_COLOR)
	draw_circle(pivot_px, 3.0, _PIVOT_COLOR)

	var mode: int = ds.mode
	var text_color: Color = _DELTA_TEXT_COLOR
	if ds.precision:
		text_color = _PRECISION_TEXT_COLOR
	var font: Font = ThemeDB.fallback_font
	var fsize: int = 12
	var label_offset := Vector2(12.0, -8.0)

	match mode:
		UvIslandTransform.MODE_MOVE:
			draw_line(pivot_px, mouse_px, _DELTA_LINE_COLOR, 1.5)
			var dx: float = ds.cumulative_freehand.x
			var dy: float = ds.cumulative_freehand.y
			var text := "Δ %.3f, %.3f" % [dx, dy]
			draw_string(font, mouse_px + label_offset + Vector2(1.0, 1.0), text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.0, 0.0, 0.0, 0.55))
			draw_string(font, mouse_px + label_offset, text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, text_color)

		UvIslandTransform.MODE_ROTATE:
			var angle_start := (ds.start_uv - ds.pivot).angle()
			var radius_px := pivot_px.distance_to(mouse_px) * 0.6
			radius_px = maxf(radius_px, 20.0)
			if not is_zero_approx(ds.cumulative_angle):
				var from_angle := angle_start
				var to_angle := angle_start + ds.cumulative_angle
				var arc_start := mini(from_angle, to_angle)
				var arc_end := maxi(from_angle, to_angle)
				draw_arc(pivot_px, radius_px, arc_start, arc_end, 128, _DELTA_ARC_COLOR, 2.0)
			var deg := rad_to_deg(ds.cumulative_angle)
			var text := "%.1f°" % deg
			var label_pos := pivot_px + Vector2(cos(angle_start + ds.cumulative_angle),
					sin(angle_start + ds.cumulative_angle)) * radius_px
			draw_string(font, label_pos + label_offset + Vector2(1.0, 1.0), text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.0, 0.0, 0.0, 0.55))
			draw_string(font, label_pos + label_offset, text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, text_color)

		UvIslandTransform.MODE_SCALE:
			draw_line(pivot_px, mouse_px, _DELTA_LINE_COLOR, 1.5)
			var text := "%.3fx" % ds.cumulative_scale
			draw_string(font, mouse_px + label_offset + Vector2(1.0, 1.0), text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.0, 0.0, 0.0, 0.55))
			draw_string(font, mouse_px + label_offset, text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, text_color)

	var indicator_y: float = pivot_px.y - 16.0
	if ds.precision:
		var prec_text := "PRECISION"
		draw_string(font, pivot_px + Vector2(10.0, indicator_y) + Vector2(1.0, 1.0), prec_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.0, 0.0, 0.0, 0.45))
		draw_string(font, pivot_px + Vector2(10.0, indicator_y), prec_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, _PRECISION_TEXT_COLOR)
		indicator_y -= 14.0


## Draw the delta overlay during an active vertex drag.
func _draw_vert_drag_overlay() -> void:
	var ds: UvVertexTransform.DragState = _vert_drag_state
	if ds == null:
		return

	var mouse_uv := _canvas_to_uv(get_local_mouse_position())
	var mouse_px := _uv_to_canvas(mouse_uv)

	var text_color: Color = _DELTA_TEXT_COLOR if not ds.precision else _PRECISION_TEXT_COLOR
	var font: Font = ThemeDB.fallback_font
	var fsize: int = 12
	var label_offset := Vector2(12.0, -8.0)

	draw_line(_uv_to_canvas(ds.start_uv), mouse_px, _DELTA_LINE_COLOR, 1.5)
	var dx: float = ds.cumulative_freehand.x
	var dy: float = ds.cumulative_freehand.y
	var text := "Δ %.3f, %.3f" % [dx, dy]
	draw_string(font, mouse_px + label_offset + Vector2(1.0, 1.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.0, 0.0, 0.0, 0.55))
	draw_string(font, mouse_px + label_offset, text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, text_color)

	if ds.precision:
		var prec_text := "PRECISION"
		draw_string(font, mouse_px + Vector2(12.0, -20.0) + Vector2(1.0, 1.0), prec_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.0, 0.0, 0.0, 0.45))
		draw_string(font, mouse_px + Vector2(12.0, -20.0), prec_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, _PRECISION_TEXT_COLOR)


## Draw a filled triangle arrowhead at [param tip] pointing in direction [param angle].
func _draw_arrowhead(tip: Vector2, angle: float, color: Color) -> void:
	var s := _GIZMO_ARROW_SIZE
	var half_base := s * 0.45
	var back := tip - Vector2(cos(angle), sin(angle)) * s
	var perp := Vector2(-sin(angle), cos(angle)) * half_base
	var pts := PackedVector2Array([tip, back + perp, back - perp])
	draw_polygon(pts, PackedColorArray([color]))


## Draw the rubber-band box during box selection.
func _draw_box_select() -> void:
	var rect := Rect2(_box_select_start, _box_select_end - _box_select_start).abs()
	draw_rect(rect, _BOX_SELECT_COLOR)
	draw_rect(rect, _BOX_BORDER_COLOR, false, 1.0)


# ---------------------------------------------------------------------------
# Coordinate transform
# ---------------------------------------------------------------------------

## Map UV-space coordinates to canvas pixel coordinates.
##
## UV (0, 0) maps to the centre of the canvas offset by [member _pan].
## [member _zoom] is the pixel size of one UV unit.
func _uv_to_canvas(uv: Vector2) -> Vector2:
	var centre := size * 0.5
	return centre + _pan + uv * _zoom


## Map canvas pixel coordinates back to UV space.
func _canvas_to_uv(px: Vector2) -> Vector2:
	var centre := size * 0.5
	return (px - centre - _pan) / _zoom


# ---------------------------------------------------------------------------
# Background helpers
# ---------------------------------------------------------------------------

## Ensure the checkerboard [ImageTexture] is created (lazily, once).
func _ensure_checker_tex() -> void:
	if _checker_tex != null:
		return
	var cell_size := 16
	var grid_count := 16
	var dim := cell_size * grid_count
	var img := Image.create(dim, dim, false, Image.FORMAT_RGBA8)
	for y: int in dim:
		for x: int in dim:
			var light := ((x / cell_size) + (y / cell_size)) % 2 == 0
			img.set_pixel(x, y, _CHECKER_LIGHT if light else _CHECKER_DARK)
	var tex := ImageTexture.create_from_image(img)
	tex.resource_name = "go_build_uv_checker"
	_checker_tex = tex


## Return the albedo [Texture2D] from the material slot selected in the
## visibility dropdown, or null if unavailable.
func _get_bg_texture() -> Texture2D:
	if _target == null or _target.go_build_mesh == null:
		return null
	var slots: Array[Material] = _target.go_build_mesh.material_slots
	if slots.is_empty():
		return null
	var idx: int = _bg_material_index
	if idx < 0 or idx >= slots.size():
		return null
	var mat: Material = slots[idx]
	if mat == null:
		return null
	if mat is StandardMaterial3D:
		var smat: StandardMaterial3D = mat
		if smat.albedo_texture != null:
			return smat.albedo_texture
	return null


## Auto-switch the background texture to match the first selected face's
## material, if [member _auto_switch_bg] is enabled.
func _auto_switch_bg_to_selection() -> void:
	if not _auto_switch_bg:
		return
	if _target == null or _target.go_build_mesh == null:
		return
	var selected: Array[int] = _target.selection.get_selected_faces()
	if selected.is_empty():
		return
	var gbm: GoBuildMesh = _target.go_build_mesh
	var first_face: GoBuildFace = gbm.faces[selected[0]]
	var mat_idx: int = first_face.material_index
	if mat_idx < gbm.material_slots.size():
		var mat: Material = gbm.material_slots[mat_idx]
		if mat != null and mat is StandardMaterial3D:
			var smat: StandardMaterial3D = mat as StandardMaterial3D
			if smat.albedo_texture != null:
				_bg_material_index = mat_idx
				_bg_mode = UvBgMode.TEXTURE
				bg_mode_changed.emit()


## Return a Dictionary of face indices that are visible in isolate mode.
## Uses the 3D face selection. Returns an empty dict when isolate is off
## or when no face selection exists (in both cases the caller should treat
## all faces as visible).
func _get_isolate_visible_faces() -> Dictionary:
	if not _isolate_selected:
		return {}
	var selected: Array[int] = []
	if _target != null:
		selected = _target.selection.get_selected_faces()
	if selected.is_empty():
		return {}
	return _make_face_set(selected)


## Return true when isolate is on AND a face selection exists, meaning
## callers should filter to only the faces in [_get_isolate_visible_faces].
## When false, all faces are visible (either isolate is off, or there is no
## selection to isolate to yet — isolate is a no-op in that case).
func _is_isolate_active() -> bool:
	if not _isolate_selected:
		return false
	if _target == null:
		return false
	return not _target.selection.get_selected_faces().is_empty()


## Return a Dictionary set of face indices from an array for O(1) lookup.
func _make_face_set(face_indices: Array[int]) -> Dictionary:
	var d: Dictionary = {}
	for fi: int in face_indices:
		d[fi] = true
	return d


# ---------------------------------------------------------------------------
# UV hit-testing
# ---------------------------------------------------------------------------


## Return the face index whose UV polygon best contains [param uv_pos], or -1.
func _pick_face(uv_pos: Vector2) -> int:
	if _target == null or _target.go_build_mesh == null:
		return -1
	return UvPicker.pick_face(_target.go_build_mesh, uv_pos)


## Return the topmost face at [param uv_pos] that is visible (selected) when
## in isolate mode, or the normal pick result otherwise.
## In isolate mode, if the topmost face is not selected but a candidate is,
## returns the first selected candidate instead of -1.
func _pick_face_visible(uv_pos: Vector2) -> int:
	if not _is_isolate_active():
		return _pick_face(uv_pos)
	var vis_set := _get_isolate_visible_faces()
	var fi := _pick_face(uv_pos)
	if fi >= 0 and vis_set.has(fi):
		return fi
	var candidates := _pick_face_all(uv_pos)
	for c: int in candidates:
		if vis_set.has(c):
			return c
	return -1


## Return all face indices whose UV polygons contain or are near [param uv_pos].
func _pick_face_all(uv_pos: Vector2) -> Array[int]:
	if _target == null or _target.go_build_mesh == null:
		return []
	return UvPicker.pick_face_all(_target.go_build_mesh, uv_pos)


## Return all face indices whose UV polygons intersect a UV-space rectangle.
func _pick_faces_in_rect(uv_rect: Rect2) -> Array[int]:
	if _target == null or _target.go_build_mesh == null:
		return []
	return UvPicker.pick_faces_in_rect(_target.go_build_mesh, uv_rect)


## Return the face indices currently selected in the [SelectionManager].
## Returns the face selection regardless of the active 3D selection mode.
func _get_uv_selected_faces() -> Array[int]:
	if _target == null:
		return []
	return _target.selection.get_selected_faces()


# ---------------------------------------------------------------------------
# Pivot computation
# ---------------------------------------------------------------------------

## Compute the centroid of the UV positions of the given faces.
func _compute_pivot(face_indices: Array[int]) -> Vector2:
	if _target == null or _target.go_build_mesh == null:
		return Vector2.ZERO
	return UvPicker.compute_pivot(_target.go_build_mesh, face_indices)


# ---------------------------------------------------------------------------
# Input — pan and zoom (unchanged)
# ---------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		_handle_mouse_button(mb)
		return

	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_handle_mouse_motion(mm)
		return

	if event is InputEventKey:
		var ek := event as InputEventKey
		_handle_key(ek)
		return


func _handle_mouse_button(mb: InputEventMouseButton) -> void:
	grab_focus()
	# Zoom.
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
		_zoom_at(mb.position, 1.1)
		accept_event()
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
		_zoom_at(mb.position, 1.0 / 1.1)
		accept_event()
		return

	# Pan (middle mouse).
	if mb.button_index == MOUSE_BUTTON_MIDDLE:
		_pan_dragging = mb.pressed
		if _pan_dragging:
			_pan_drag_start = mb.position
			_pan_drag_start_pan = _pan
		accept_event()
		return

	# Selection / island drag (left mouse).
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_begin_left_press(mb.position, mb)
		else:
			_end_left_press(mb.position, mb)
		accept_event()
		return


func _handle_mouse_motion(mm: InputEventMouseMotion) -> void:
	# Update modifier state.
	_shift_held = mm.shift_pressed
	_ctrl_held = mm.ctrl_pressed

	# View pan.
	if _pan_dragging:
		_pan = _pan_drag_start_pan + (mm.position - _pan_drag_start)
		queue_redraw()
		accept_event()
		return

	# Box select drag.
	if _box_selecting:
		_box_select_end = mm.position
		queue_redraw()
		accept_event()
		return

	# Island transform drag.
	if _island_dragging:
		_apply_island_drag(mm.position)
		accept_event()
		return

	# Vertex drag.
	if _vert_dragging:
		_apply_vert_drag(mm.position)
		accept_event()
		return

	# Detect if the left button has moved beyond click threshold.
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not _left_moved:
		if (mm.position - _left_press_pos).length_squared() > _CLICK_THRESHOLD * _CLICK_THRESHOLD:
			_left_moved = true
			_start_drag_or_box_select(mm.position)
		accept_event()
		return


func _handle_key(ek: InputEventKey) -> void:
	if not ek.pressed:
		return
	if ek.keycode == KEY_ESCAPE:
		if _vert_dragging:
			_cancel_vert_drag()
		elif _island_dragging:
			_cancel_island_drag()
		accept_event()
		return
	if ek.keycode == KEY_TAB:
		if _uv_select_mode == UvSelectMode.FACE:
			set_uv_select_mode(UvSelectMode.VERTEX)
		else:
			set_uv_select_mode(UvSelectMode.FACE)
		accept_event()
		return
	if _uv_select_mode == UvSelectMode.VERTEX:
		return
	if ek.keycode == KEY_W:
		_transform_mode = UvTransformMode.MOVE
		queue_redraw()
		accept_event()
		return
	if ek.keycode == KEY_E:
		_transform_mode = UvTransformMode.ROTATE
		queue_redraw()
		accept_event()
		return
	if ek.keycode == KEY_R:
		_transform_mode = UvTransformMode.SCALE
		queue_redraw()
		accept_event()
		return


# ---------------------------------------------------------------------------
# Left-press / release logic
# ---------------------------------------------------------------------------

func _begin_left_press(pos: Vector2, mb: InputEventMouseButton) -> void:
	_shift_held = mb.shift_pressed
	_ctrl_held = mb.ctrl_pressed
	_left_press_pos = pos
	_left_moved = false
	_cancel_island_drag()
	_cancel_vert_drag()


func _end_left_press(pos: Vector2, mb: InputEventMouseButton) -> void:
	_shift_held = mb.shift_pressed
	_ctrl_held = mb.ctrl_pressed

	# Determine if this was a click or a drag based on total movement.
	var drag_dist_sq := (pos - _left_press_pos).length_squared()
	var was_click := drag_dist_sq < _CLICK_THRESHOLD * _CLICK_THRESHOLD

	# If it was really just a click, cancel any accidental drags and do click-select.
	if was_click:
		if _vert_dragging:
			_cancel_vert_drag()
		elif _island_dragging:
			_cancel_island_drag()
		_box_selecting = false
		_box_select_start = Vector2.ZERO
		_box_select_end = Vector2.ZERO
		if _uv_select_mode == UvSelectMode.VERTEX:
			_do_click_select_vert(pos)
		else:
			_do_click_select(pos)
		return

	# Real drag — commit whatever was active.
	if _vert_dragging:
		_commit_vert_drag()
		_vert_dragging = false
		_vert_drag_state = null
		queue_redraw()
		return

	if _island_dragging:
		_commit_island_drag()
		_island_dragging = false
		_island_drag_state = null
		queue_redraw()
		return

	# Box-select finalise.
	if _uv_select_mode == UvSelectMode.VERTEX:
		var rect := Rect2(_box_select_start, _box_select_end - _box_select_start).abs()
		var uv_tl := _canvas_to_uv(rect.position)
		var uv_br := _canvas_to_uv(rect.end)
		var uv_rect := Rect2(uv_tl, uv_br - uv_tl)
		_finish_box_select_vert(uv_rect)
	else:
		_finish_box_select()
	_box_selecting = false
	_box_select_start = Vector2.ZERO
	_box_select_end = Vector2.ZERO
	queue_redraw()


func _start_drag_or_box_select(pos: Vector2) -> void:
	if _target == null or _target.go_build_mesh == null:
		return

	if _uv_select_mode == UvSelectMode.VERTEX:
		if not _selected_uv_verts.is_empty():
			_begin_vert_drag(pos)
			return
		var uv_pos := _canvas_to_uv(pos)
		var isolate_vis := _get_isolate_visible_faces()
		var hit := UvPicker.pick_vert(
			_target.go_build_mesh, uv_pos, _zoom, _VERT_PICK_RADIUS, isolate_vis)
		if hit.x >= 0:
			if not _selected_uv_verts.has(hit):
				_selected_uv_verts.append(hit)
				queue_redraw()
			_begin_vert_drag(pos)
			return
		_box_selecting = true
		_box_select_start = pos
		_box_select_end = pos
		return

	var uv_pos := _canvas_to_uv(pos)
	var sel_faces := _get_uv_selected_faces()
	if not sel_faces.is_empty():
		# Check if any face under the cursor is already selected.
		# In isolate mode, only consider visible (selected) faces for starting a drag.
		var candidates := _pick_face_all(uv_pos)
		if _is_isolate_active():
			var vis_set := _get_isolate_visible_faces()
			var filtered: Array[int] = []
			for c: int in candidates:
				if vis_set.has(c):
					filtered.append(c)
			candidates = filtered
		var start_drag := false
		for c: int in candidates:
			if sel_faces.has(c):
				start_drag = true
				break
		if start_drag:
			_begin_island_drag(pos, sel_faces)
			return

	_box_selecting = true
	_box_select_start = pos
	_box_select_end = pos


# ---------------------------------------------------------------------------
# Click selection
# ---------------------------------------------------------------------------

func _do_click_select(canvas_pos: Vector2) -> void:
	if _target == null or _target.go_build_mesh == null:
		return

	var uv_pos := _canvas_to_uv(canvas_pos)

	# Face cycling: if the click is near the previous click position, cycle
	# through overlapping faces rather than always picking the topmost.
	# In isolate mode, skip cycling since hidden faces are not visible.
	var dist_from_last := uv_pos.distance_squared_to(_last_click_uv)
	var same_spot := dist_from_last < 0.001 and not _cycle_candidates.is_empty()
	if same_spot and not _shift_held and not _ctrl_held and not _is_isolate_active():
		_cycle_index = (_cycle_index + 1) % _cycle_candidates.size()
		var faces: Array[int] = [_cycle_candidates[_cycle_index]]
		_target.selection.set_selected_faces(faces)
		return

	var candidates := _pick_face_all(uv_pos)
	# In isolate mode, only pick from faces that are currently selected/visible.
	if _is_isolate_active():
		var vis_set := _get_isolate_visible_faces()
		var filtered: Array[int] = []
		for c: int in candidates:
			if vis_set.has(c):
				filtered.append(c)
		candidates = filtered
		# In isolate mode, if no visible candidate exists at this point,
		# don't change the selection — the click is on a hidden face.
		if candidates.is_empty():
			return
	_last_click_uv = uv_pos
	_cycle_candidates = candidates
	_cycle_index = 0

	var fi := _pick_face_visible(uv_pos)

	if fi < 0:
		if not _shift_held and not _ctrl_held:
			if not _is_isolate_active():
				_target.selection.clear()
				_cycle_candidates.clear()
		return

	if candidates.size() > 1:
		var idx := candidates.find(fi)
		if idx >= 0:
			_cycle_index = idx

	if _shift_held:
		_target.selection.select_face(fi)
	elif _ctrl_held:
		_target.selection.toggle_face(fi)
	else:
		var faces: Array[int] = [fi]
		_target.selection.set_selected_faces(faces)


# ---------------------------------------------------------------------------
# Box selection
# ---------------------------------------------------------------------------

func _finish_box_select() -> void:
	if _target == null or _target.go_build_mesh == null:
		return

	var rect := Rect2(_box_select_start, _box_select_end - _box_select_start).abs()
	var uv_tl := _canvas_to_uv(rect.position)
	var uv_br := _canvas_to_uv(rect.end)
	var uv_rect := Rect2(uv_tl, uv_br - uv_tl)

	if _uv_select_mode == UvSelectMode.VERTEX:
		_finish_box_select_vert(uv_rect)
		return

	var hits := _pick_faces_in_rect(uv_rect)
	# In isolate mode, only select from faces that are currently visible.
	if _is_isolate_active():
		if hits.is_empty():
			return
		var vis_set := _get_isolate_visible_faces()
		var filtered: Array[int] = []
		for h: int in hits:
			if vis_set.has(h):
				filtered.append(h)
		hits = filtered
		# In isolate mode, if no visible face is in the box, don't change selection.
		if hits.is_empty():
			return
	if hits.is_empty():
		if not _shift_held and not _ctrl_held:
			_target.selection.clear()
		return

	if _shift_held:
		for fi: int in hits:
			_target.selection.select_face(fi)
	elif _ctrl_held:
		for fi: int in hits:
			_target.selection.toggle_face(fi)
	else:
		_target.selection.set_selected_faces(hits)


func _finish_box_select_vert(uv_rect: Rect2) -> void:
	var gbm: GoBuildMesh = _target.go_build_mesh
	var hits: Array[Vector2i] = []
	# In isolate mode, only pick vertices from visible (selected) faces.
	var vis_set := _get_isolate_visible_faces()
	for fi: int in gbm.faces.size():
		if _is_isolate_active() and not vis_set.has(fi):
			continue
		var face: GoBuildFace = gbm.faces[fi]
		for vi: int in face.uvs.size():
			if uv_rect.has_point(face.uvs[vi]):
				hits.append(Vector2i(fi, vi))

	if hits.is_empty():
		if not _shift_held and not _ctrl_held:
			_selected_uv_verts.clear()
			queue_redraw()
		return

	if _shift_held:
		for v: Vector2i in hits:
			if not _selected_uv_verts.has(v):
				_selected_uv_verts.append(v)
	elif _ctrl_held:
		for v: Vector2i in hits:
			var idx := _selected_uv_verts.find(v)
			if idx >= 0:
				_selected_uv_verts.remove_at(idx)
			else:
				_selected_uv_verts.append(v)
	else:
		_selected_uv_verts = hits
	queue_redraw()


# ---------------------------------------------------------------------------
# Island transform — begin / apply / commit
# ---------------------------------------------------------------------------

func _begin_island_drag(canvas_pos: Vector2, sel_faces: Array[int]) -> void:
	_island_dragging = true
	var uv := _canvas_to_uv(canvas_pos)
	var mode: int = _transform_mode
	if _target and _target.go_build_mesh:
		_island_drag_state = UvIslandTransform.begin(
			_target.go_build_mesh, sel_faces, uv, mode)


func _apply_island_drag(canvas_pos: Vector2) -> void:
	if _target == null or _target.go_build_mesh == null or _island_drag_state == null:
		return
	var uv_now := _canvas_to_uv(canvas_pos)
	var sel_faces := _get_uv_selected_faces()
	var snap: float = _uv_snap_size if _ctrl_held else 0.0
	UvIslandTransform.apply(
		_target.go_build_mesh, sel_faces, _island_drag_state, uv_now,
		_shift_held, snap)
	_target.bake_in_place()
	queue_redraw()


func _commit_island_drag() -> void:
	if _target == null or _island_drag_state == null or _plugin == null:
		return
	var snapshot := _island_drag_state.snapshot
	var action_name := "Move UV Island"
	match _transform_mode:
		UvTransformMode.ROTATE:
			action_name = "Rotate UV Island"
		UvTransformMode.SCALE:
			action_name = "Scale UV Island"
	var ur: EditorUndoRedoManager = _plugin.get_undo_redo()
	ur.create_action(action_name)
	ur.add_do_method(self, "_noop")
	ur.add_undo_method(_target, "restore_and_bake", snapshot)
	ur.commit_action()


func _cancel_island_drag() -> void:
	if not _island_dragging or _island_drag_state == null or _target == null:
		_island_dragging = false
		_island_drag_state = null
		return
	_target.restore_and_bake(_island_drag_state.snapshot)
	_island_dragging = false
	_island_drag_state = null
	queue_redraw()


## No-op used as the "do" step of an island transform undo action
## (the transform has already been applied live during the drag).
func _noop() -> void:
	pass


# ---------------------------------------------------------------------------
# Vertex-mode click selection
# ---------------------------------------------------------------------------

func _do_click_select_vert(canvas_pos: Vector2) -> void:
	if _target == null or _target.go_build_mesh == null:
		return

	var uv_pos := _canvas_to_uv(canvas_pos)
	var isolate_vis := _get_isolate_visible_faces()
	var hit := UvPicker.pick_vert(
		_target.go_build_mesh, uv_pos, _zoom, _VERT_PICK_RADIUS, isolate_vis)

	if hit.x < 0:
		if not _shift_held and not _ctrl_held:
			_selected_uv_verts.clear()
			queue_redraw()
		return

	if _shift_held:
		if not _selected_uv_verts.has(hit):
			_selected_uv_verts.append(hit)
	elif _ctrl_held:
		var idx := _selected_uv_verts.find(hit)
		if idx >= 0:
			_selected_uv_verts.remove_at(idx)
		else:
			_selected_uv_verts.append(hit)
	else:
		_selected_uv_verts = [hit]
	queue_redraw()


# ---------------------------------------------------------------------------
# Vertex-mode drag (move selected UV vertices)
# ---------------------------------------------------------------------------

func _begin_vert_drag(canvas_pos: Vector2) -> void:
	_vert_dragging = true
	var uv := _canvas_to_uv(canvas_pos)
	if _target and _target.go_build_mesh:
		_vert_drag_state = UvVertexTransform.begin(
			_target.go_build_mesh, uv)


func _apply_vert_drag(canvas_pos: Vector2) -> void:
	if _target == null or _target.go_build_mesh == null or _vert_drag_state == null:
		return
	var uv_now := _canvas_to_uv(canvas_pos)
	var snap: float = _uv_snap_size if _ctrl_held else 0.0
	var isolate: Dictionary = {}
	if _is_isolate_active():
		isolate = _get_isolate_visible_faces()
	UvVertexTransform.apply(
		_target.go_build_mesh, _selected_uv_verts,
		_vert_drag_state, uv_now, _shift_held, snap, isolate)
	_target.bake_in_place()
	queue_redraw()


func _commit_vert_drag() -> void:
	if _target == null or _vert_drag_state == null or _plugin == null:
		return
	var snapshot := _vert_drag_state.snapshot
	var ur: EditorUndoRedoManager = _plugin.get_undo_redo()
	ur.create_action("Move UV Vertices")
	ur.add_do_method(self, "_noop")
	ur.add_undo_method(_target, "restore_and_bake", snapshot)
	ur.commit_action()


func _cancel_vert_drag() -> void:
	if not _vert_dragging or _vert_drag_state == null or _target == null:
		_vert_dragging = false
		_vert_drag_state = null
		return
	_target.restore_and_bake(_vert_drag_state.snapshot)
	_vert_dragging = false
	_vert_drag_state = null
	queue_redraw()


# ---------------------------------------------------------------------------
# Zoom
# ---------------------------------------------------------------------------

## Zoom toward [param cursor_pos] (canvas pixel coordinates).
func _zoom_at(cursor_pos: Vector2, factor: float) -> void:
	var new_zoom := clampf(_zoom * factor, _ZOOM_MIN, _ZOOM_MAX)
	if new_zoom == _zoom:
		return
	var uv_under_cursor := (cursor_pos - (size * 0.5 + _pan)) / _zoom
	_pan = cursor_pos - (size * 0.5) - uv_under_cursor * new_zoom
	_zoom = new_zoom
	queue_redraw()
