## 2D canvas that draws the UV layout of the active [GoBuildMeshInstance].
##
## Displays all face UVs as wireframe polygons in the 0-1 UV tile.
## Selected faces are highlighted.  Supports:
## - Pan (middle-mouse drag) and zoom (scroll wheel).
## - Click a UV face to select it (synced with the 3D viewport).
## - Shift+click adds; Ctrl+click toggles.
## - Drag with left mouse to box-select faces in UV space.
## - G/R/S keys switch transform mode (Move/Rotate/Scale) for selected islands.
## - Left-drag on a selected island to transform its UVs.
@tool
class_name GoBuildUvCanvas
extends Control

## Transform mode for island manipulation.
enum UvTransformMode {
	MOVE   = 0,
	ROTATE = 1,
	SCALE  = 2,
}

## Background image mode for the UV tile.
enum UvBgMode {
	CHECKER  = 0,
	TEXTURE  = 1,
	OFF      = 2,
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
const _EDGE_THRESHOLD: float = 0.005

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

## Active selection mode (face / vertex) in the UV editor.
var _uv_select_mode: UvSelectMode = UvSelectMode.FACE

## Selected UV vertices as PackedVector2i of (face_index, uv_index).
var _selected_uv_verts: Array[Vector2i] = []

## True while dragging selected UV vertices.
var _vert_dragging:      bool     = false
var _vert_drag_start_uv: Vector2  = Vector2.ZERO
var _vert_drag_prev_uv: Vector2  = Vector2.ZERO
var _vert_snapshot:      Dictionary = {}

## Lazily-created checkerboard texture for the UV tile background.
var _checker_tex: ImageTexture = null

## Number of texture repeats for tile rendering (1 = single tile, 2+ = tiling).
var _tile_repeat: int = 1

## True while the user is left-dragging a selected island (UV transform).
var _island_dragging:       bool     = false
var _island_drag_start_uv:  Vector2  = Vector2.ZERO
var _island_drag_prev_uv:   Vector2  = Vector2.ZERO
var _island_snapshot:       Dictionary = {}
var _island_pivot:          Vector2  = Vector2.ZERO
var _island_scale_start:    float    = 1.0

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


## Reset pan and zoom to defaults and trigger a redraw.
func reset_view() -> void:
	_zoom = _ZOOM_DEFAULT
	_pan  = Vector2.ZERO
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


## Cycle [enum UvBgMode]: Checker -> Texture -> Off -> Checker.
func cycle_bg_mode() -> void:
	_bg_mode = (_bg_mode + 1) as UvBgMode
	if _bg_mode > UvBgMode.OFF:
		_bg_mode = UvBgMode.CHECKER
	queue_redraw()


## Set [enum UvBgMode] directly.
func set_bg_mode(mode: UvBgMode) -> void:
	_bg_mode = mode
	queue_redraw()


## Return the tile repeat count.
func get_tile_repeat() -> int:
	return _tile_repeat


## Set the tile repeat count (1 = single tile, 2+ = repeated tiling).
func set_tile_repeat(count: int) -> void:
	_tile_repeat = maxi(count, 1)
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
	queue_redraw()


func _on_selection_changed() -> void:
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
	if _box_selecting:
		_draw_box_select()


## Draw the UV-space tile (0-1 range) with border and half-way grid lines.
func _draw_grid() -> void:
	var tl := _uv_to_canvas(Vector2(0.0, 0.0))
	var br := _uv_to_canvas(Vector2(float(_tile_repeat), float(_tile_repeat)))
	var tile_rect := Rect2(tl, br - tl)
	draw_rect(tile_rect, _TILE_BG_COLOR)

	match _bg_mode:
		UvBgMode.CHECKER:
			_ensure_checker_tex()
			if _tile_repeat > 1:
				_draw_tiled_checker(tile_rect, tl, br)
			else:
				draw_texture_rect(_checker_tex, Rect2(
					_uv_to_canvas(Vector2.ZERO),
					_uv_to_canvas(Vector2(1.0, 1.0)) - _uv_to_canvas(Vector2.ZERO)
				), false)
		UvBgMode.TEXTURE:
			var tex := _get_albedo_texture()
			if tex != null:
				draw_texture_rect(tex, tile_rect, false)

	# Draw tile outlines and grid lines for each repeat.
	for i: int in range(_tile_repeat + 1):
		var f := float(i)
		var h_line_start := _uv_to_canvas(Vector2(0.0, f))
		var h_line_end := _uv_to_canvas(Vector2(float(_tile_repeat), f))
		draw_line(h_line_start, h_line_end, _TILE_BORDER_COLOR, 1.0)
		var v_line_start := _uv_to_canvas(Vector2(f, 0.0))
		var v_line_end := _uv_to_canvas(Vector2(f, float(_tile_repeat)))
		draw_line(v_line_start, v_line_end, _TILE_BORDER_COLOR, 1.0)
		if 0 < i and i < _tile_repeat:
			draw_line(h_line_start, h_line_end, _HALF_LINE_COLOR, 0.5)
			draw_line(v_line_start, v_line_end, _HALF_LINE_COLOR, 0.5)


## Draw the checker texture tiled across the visible area.
func _draw_tiled_checker(_visible_rect: Rect2, _tl: Vector2, _br: Vector2) -> void:
	var unit_size_px := _uv_to_canvas(Vector2(1.0, 1.0)) - _uv_to_canvas(Vector2.ZERO)
	for iy: int in range(_tile_repeat):
		for ix: int in range(_tile_repeat):
			var cell_tl := _uv_to_canvas(Vector2(float(ix), float(iy)))
			draw_texture_rect(_checker_tex, Rect2(cell_tl, unit_size_px), false)


## Draw every face's UV polygon, highlighting selected faces.
## Selected faces are drawn last so they appear on top of unselected ones.
func _draw_faces() -> void:
	var gbm: GoBuildMesh = _target.go_build_mesh
	var selected: Array[int] = []
	if _target.selection.get_mode() == SelectionManager.Mode.FACE:
		selected = _target.selection.get_selected_faces()

	# Pass 1: unselected faces (wireframe only).
	for fi: int in gbm.faces.size():
		var face: GoBuildFace = gbm.faces[fi]
		if face.uvs.size() < 3:
			continue
		var is_sel: bool = selected.has(fi)
		if is_sel:
			continue
		var pts := PackedVector2Array()
		for uv: Vector2 in face.uvs:
			pts.append(_uv_to_canvas(uv))
		var closed_pts: PackedVector2Array = pts + PackedVector2Array([pts[0]])
		draw_polyline(closed_pts, _FACE_WIRE_COLOR, 1.0)

	# Pass 2: selected faces (fill + wireframe on top).
	for fi: int in gbm.faces.size():
		var face: GoBuildFace = gbm.faces[fi]
		if face.uvs.size() < 3:
			continue
		var is_sel: bool = selected.has(fi)
		if not is_sel:
			continue
		var pts := PackedVector2Array()
		for uv: Vector2 in face.uvs:
			pts.append(_uv_to_canvas(uv))
		var closed_pts: PackedVector2Array = pts + PackedVector2Array([pts[0]])
		draw_polygon(pts, PackedColorArray([_SEL_FILL_COLOR]))
		draw_polyline(closed_pts, _SEL_WIRE_COLOR, 1.0)


## Draw dots at every UV vertex; highlight selected ones.
func _draw_uv_vertices() -> void:
	if _target == null or _target.go_build_mesh == null:
		return
	var gbm: GoBuildMesh = _target.go_build_mesh
	var sel_set: Dictionary = {}
	for v: Vector2i in _selected_uv_verts:
		sel_set[v] = true

	for fi: int in gbm.faces.size():
		var face: GoBuildFace = gbm.faces[fi]
		for vi: int in face.uvs.size():
			var px := _uv_to_canvas(face.uvs[vi])
			var is_sel: bool = sel_set.has(Vector2i(fi, vi))
			draw_circle(px, 4.0 if is_sel else 3.0, _VTX_SEL_COLOR if is_sel else _VTX_DOT_COLOR)


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


## Return the albedo [Texture2D] from the first material slot, or null.
func _get_albedo_texture() -> Texture2D:
	if _target == null or _target.go_build_mesh == null:
		return null
	var slots: Array[Material] = _target.go_build_mesh.material_slots
	if slots.is_empty() or slots[0] == null:
		return null
	var mat: Material = slots[0]
	if mat is StandardMaterial3D:
		var smat: StandardMaterial3D = mat
		if smat.albedo_texture != null:
			return smat.albedo_texture
	return null


# ---------------------------------------------------------------------------
# UV hit-testing
# ---------------------------------------------------------------------------


## Return the face index whose UV polygon best contains [param uv_pos], or -1.
##
## Uses a point-in-polygon test with an edge proximity fallback.  If the point
## is not strictly inside any polygon, the face whose closest edge is within
## [constant _EDGE_THRESHOLD] UV units wins instead.  This makes clicking near
## edges and corners more reliable.
##
## If multiple faces overlap, the last face in the array wins (topmost draw order).
func _pick_face(uv_pos: Vector2) -> int:
	if _target == null or _target.go_build_mesh == null:
		return -1
	var gbm: GoBuildMesh = _target.go_build_mesh
	var hit: int = -1
	var best_edge_dist: float = _EDGE_THRESHOLD * _EDGE_THRESHOLD
	var any_inside: bool = false

	for fi: int in gbm.faces.size():
		var face: GoBuildFace = gbm.faces[fi]
		if face.uvs.size() < 3:
			continue
		if _point_in_polygon_uv(uv_pos, face.uvs):
			hit = fi
			any_inside = true
		elif not any_inside:
			var dist_sq := _min_edge_dist_sq(uv_pos, face.uvs)
			if dist_sq < best_edge_dist:
				best_edge_dist = dist_sq
				hit = fi

	return hit


## Return all face indices whose UV polygons contain or are near [param uv_pos].
## Ordered front-to-back (last drawn = last in list).  Used for face cycling.
func _pick_face_all(uv_pos: Vector2) -> Array[int]:
	if _target == null or _target.go_build_mesh == null:
		return []
	var gbm: GoBuildMesh = _target.go_build_mesh
	var result: Array[int] = []
	for fi: int in gbm.faces.size():
		var face: GoBuildFace = gbm.faces[fi]
		if face.uvs.size() < 3:
			continue
		if _point_in_polygon_uv(uv_pos, face.uvs):
			result.append(fi)
		else:
			var dist_sq := _min_edge_dist_sq(uv_pos, face.uvs)
			if dist_sq < _EDGE_THRESHOLD * _EDGE_THRESHOLD:
				result.append(fi)
	return result


## Ray-casting point-in-polygon test in UV space.
static func _point_in_polygon_uv(point: Vector2, polygon: Array[Vector2]) -> bool:
	var n: int = polygon.size()
	var inside: bool = false
	var j: int = n - 1
	for i: int in n:
		var vi: Vector2 = polygon[i]
		var vj: Vector2 = polygon[j]
		if ((vi.y > point.y) != (vj.y > point.y)) and \
				(point.x < (vj.x - vi.x) * (point.y - vi.y) / (vj.y - vi.y) + vi.x):
			inside = not inside
		j = i
	return inside


## Minimum squared distance from [param point] to any edge of [param polygon].
static func _min_edge_dist_sq(point: Vector2, polygon: Array[Vector2]) -> float:
	var n: int = polygon.size()
	var best: float = INF
	for i: int in n:
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i + 1) % n]
		var ab := b - a
		var ap := point - a
		var t := clampf(ap.dot(ab) / ab.dot(ab), 0.0, 1.0)
		var closest := a + ab * t
		var dsq := point.distance_squared_to(closest)
		if dsq < best:
			best = dsq
	return best


## Return all face indices whose UV polygons intersect a UV-space rectangle.
func _pick_faces_in_rect(uv_rect: Rect2) -> Array[int]:
	if _target == null or _target.go_build_mesh == null:
		return []
	var gbm: GoBuildMesh = _target.go_build_mesh
	var result: Array[int] = []
	for fi: int in gbm.faces.size():
		var face: GoBuildFace = gbm.faces[fi]
		if face.uvs.size() < 3:
			continue
		if _polygon_intersects_rect(face.uvs, uv_rect):
			result.append(fi)
	return result


## Check if a UV polygon intersects a UV-space rectangle.
## True if any vertex is inside the rect, or any edge crosses the rect boundary.
static func _polygon_intersects_rect(polygon: Array[Vector2], rect: Rect2) -> bool:
	for uv: Vector2 in polygon:
		if rect.has_point(uv):
			return true
	var corners: Array[Vector2] = [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	]
	for corner: Vector2 in corners:
		if _point_in_polygon_uv(corner, polygon):
			return true
	return false


## Return the face indices currently selected in the [SelectionManager],
## but only if the mode is [code]FACE[/code].  Empty otherwise.
func _get_uv_selected_faces() -> Array[int]:
	if _target == null:
		return []
	if _target.selection.get_mode() != SelectionManager.Mode.FACE:
		return []
	return _target.selection.get_selected_faces()


# ---------------------------------------------------------------------------
# Pivot computation
# ---------------------------------------------------------------------------

## Compute the centroid of the UV positions of the given faces.
func _compute_pivot(face_indices: Array[int]) -> Vector2:
	if _target == null or _target.go_build_mesh == null:
		return Vector2.ZERO
	var gbm: GoBuildMesh = _target.go_build_mesh
	var sum := Vector2.ZERO
	var count: int = 0
	for fi: int in face_indices:
		if fi < 0 or fi >= gbm.faces.size():
			continue
		for uv: Vector2 in gbm.faces[fi].uvs:
			sum += uv
			count += 1
	if count == 0:
		return Vector2.ZERO
	return sum / count


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
	if ek.keycode == KEY_G:
		_transform_mode = UvTransformMode.MOVE
		queue_redraw()
		accept_event()
		return
	if ek.keycode == KEY_R:
		_transform_mode = UvTransformMode.ROTATE
		queue_redraw()
		accept_event()
		return
	if ek.keycode == KEY_S:
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
		_vert_snapshot = {}
		queue_redraw()
		return

	if _island_dragging:
		_commit_island_drag()
		_island_dragging = false
		_island_snapshot = {}
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
		_box_selecting = true
		_box_select_start = pos
		_box_select_end = pos
		return

	var uv_pos := _canvas_to_uv(pos)
	var sel_faces := _get_uv_selected_faces()
	if not sel_faces.is_empty():
		# Check if any face under the cursor is already selected.
		var candidates := _pick_face_all(uv_pos)
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

	if _target.selection.get_mode() != SelectionManager.Mode.FACE:
		_target.selection.set_mode(SelectionManager.Mode.FACE)

	var uv_pos := _canvas_to_uv(canvas_pos)

	# Face cycling: if the click is near the previous click position, cycle
	# through overlapping faces rather than always picking the topmost.
	var dist_from_last := uv_pos.distance_squared_to(_last_click_uv)
	var same_spot := dist_from_last < 0.001 and not _cycle_candidates.is_empty()
	if same_spot and not _shift_held and not _ctrl_held:
		_cycle_index = (_cycle_index + 1) % _cycle_candidates.size()
		var faces: Array[int] = [_cycle_candidates[_cycle_index]]
		_target.selection.set_selected_faces(faces)
		return

	var candidates := _pick_face_all(uv_pos)
	_last_click_uv = uv_pos
	_cycle_candidates = candidates
	_cycle_index = 0

	var fi := _pick_face(uv_pos)

	if fi < 0:
		if not _shift_held and not _ctrl_held:
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

	if _target.selection.get_mode() != SelectionManager.Mode.FACE:
		_target.selection.set_mode(SelectionManager.Mode.FACE)

	var hits := _pick_faces_in_rect(uv_rect)
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
	for fi: int in gbm.faces.size():
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
	_island_drag_start_uv = _canvas_to_uv(canvas_pos)
	_island_drag_prev_uv = _island_drag_start_uv
	_island_pivot = _compute_pivot(sel_faces)
	_island_scale_start = 1.0
	if _target and _target.go_build_mesh:
		_island_snapshot = _target.go_build_mesh.take_snapshot()


func _apply_island_drag(canvas_pos: Vector2) -> void:
	if _target == null or _target.go_build_mesh == null:
		return
	var gbm: GoBuildMesh = _target.go_build_mesh
	var uv_now := _canvas_to_uv(canvas_pos)
	var sel_faces := _get_uv_selected_faces()

	match _transform_mode:
		UvTransformMode.MOVE:
			var delta := uv_now - _island_drag_prev_uv
			if delta.is_zero_approx():
				return
			for fi: int in sel_faces:
				if fi < 0 or fi >= gbm.faces.size():
					continue
				var face: GoBuildFace = gbm.faces[fi]
				for i: int in face.uvs.size():
					face.uvs[i] = face.uvs[i] + delta

		UvTransformMode.ROTATE:
			var angle_start := (_island_drag_start_uv - _island_pivot).angle()
			var angle_now := (uv_now - _island_pivot).angle()
			var delta_angle := angle_now - angle_start
			if is_zero_approx(delta_angle):
				return
			var cos_a := cos(delta_angle)
			var sin_a := sin(delta_angle)
			for fi: int in sel_faces:
				if fi < 0 or fi >= gbm.faces.size():
					continue
				var face: GoBuildFace = gbm.faces[fi]
				for i: int in face.uvs.size():
					var rel := face.uvs[i] - _island_pivot
					face.uvs[i] = _island_pivot + Vector2(
						rel.x * cos_a - rel.y * sin_a,
						rel.x * sin_a + rel.y * cos_a
					)

		UvTransformMode.SCALE:
			var dist_start := (_island_drag_start_uv - _island_pivot).length()
			var dist_now := (uv_now - _island_pivot).length()
			if is_zero_approx(dist_start):
				return
			var scale_ratio := dist_now / dist_start
			if is_equal_approx(scale_ratio, _island_scale_start):
				return
			var factor := scale_ratio / _island_scale_start
			factor = maxf(factor, 0.01)
			_island_scale_start = scale_ratio
			for fi: int in sel_faces:
				if fi < 0 or fi >= gbm.faces.size():
					continue
				var face: GoBuildFace = gbm.faces[fi]
				for i: int in face.uvs.size():
					var rel := face.uvs[i] - _island_pivot
					face.uvs[i] = _island_pivot + rel * factor

	_island_drag_prev_uv = uv_now
	_target.bake_in_place()
	queue_redraw()


func _commit_island_drag() -> void:
	if _target == null or _island_snapshot.is_empty() or _plugin == null:
		return
	# Build an undo action that restores the snapshot.
	var snapshot := _island_snapshot
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
	if not _island_dragging or _island_snapshot.is_empty() or _target == null:
		_island_dragging = false
		_island_snapshot = {}
		return
	_target.restore_and_bake(_island_snapshot)
	_island_dragging = false
	_island_snapshot = {}
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
	var gbm: GoBuildMesh = _target.go_build_mesh

	var uv_pos := _canvas_to_uv(canvas_pos)
	var best_fi: int = -1
	var best_vi: int = -1
	var best_dist_sq: float = (_VERT_PICK_RADIUS / _zoom) * (_VERT_PICK_RADIUS / _zoom)

	for fi: int in gbm.faces.size():
		var face: GoBuildFace = gbm.faces[fi]
		for vi: int in face.uvs.size():
			var dsq := uv_pos.distance_squared_to(face.uvs[vi])
			if dsq < best_dist_sq:
				best_dist_sq = dsq
				best_fi = fi
				best_vi = vi

	if best_fi < 0:
		if not _shift_held and not _ctrl_held:
			_selected_uv_verts.clear()
			queue_redraw()
		return

	var key := Vector2i(best_fi, best_vi)

	if _shift_held:
		if not _selected_uv_verts.has(key):
			_selected_uv_verts.append(key)
	elif _ctrl_held:
		var idx := _selected_uv_verts.find(key)
		if idx >= 0:
			_selected_uv_verts.remove_at(idx)
		else:
			_selected_uv_verts.append(key)
	else:
		_selected_uv_verts = [key]
	queue_redraw()


# ---------------------------------------------------------------------------
# Vertex-mode drag (move selected UV vertices)
# ---------------------------------------------------------------------------

func _begin_vert_drag(canvas_pos: Vector2) -> void:
	_vert_dragging = true
	_vert_drag_start_uv = _canvas_to_uv(canvas_pos)
	_vert_drag_prev_uv = _vert_drag_start_uv
	if _target and _target.go_build_mesh:
		_vert_snapshot = _target.go_build_mesh.take_snapshot()


func _apply_vert_drag(canvas_pos: Vector2) -> void:
	if _target == null or _target.go_build_mesh == null:
		return
	var gbm: GoBuildMesh = _target.go_build_mesh
	var uv_now := _canvas_to_uv(canvas_pos)
	var delta := uv_now - _vert_drag_prev_uv
	if delta.is_zero_approx():
		return

	# Build a set of UV positions to move (coincident vertices grouped by position)
	# so that all handles at the same UV point move together.
	var positions_to_move: Dictionary = {}
	for v: Vector2i in _selected_uv_verts:
		var fi: int = v.x
		var vi: int = v.y
		if fi < 0 or fi >= gbm.faces.size():
			continue
		positions_to_move[gbm.faces[fi].uvs[vi]] = true

	# Also find all unselected handles that share a position with a selected one.
	var all_handles: Array[Vector2i] = []
	for fi: int in gbm.faces.size():
		var face: GoBuildFace = gbm.faces[fi]
		for vi: int in face.uvs.size():
			if positions_to_move.has(face.uvs[vi]):
				all_handles.append(Vector2i(fi, vi))

	# Move all identified handles.
	var handled: Dictionary = {}
	for handle: Vector2i in all_handles:
		var hfi: int = handle.x
		var hvi: int = handle.y
		gbm.faces[hfi].uvs[hvi] = gbm.faces[hfi].uvs[hvi] + delta

	_vert_drag_prev_uv = uv_now
	_target.bake_in_place()
	queue_redraw()


func _commit_vert_drag() -> void:
	if _target == null or _vert_snapshot.is_empty() or _plugin == null:
		return
	var snapshot := _vert_snapshot
	var ur: EditorUndoRedoManager = _plugin.get_undo_redo()
	ur.create_action("Move UV Vertices")
	ur.add_do_method(self, "_noop")
	ur.add_undo_method(_target, "restore_and_bake", snapshot)
	ur.commit_action()


func _cancel_vert_drag() -> void:
	if not _vert_dragging or _vert_snapshot.is_empty() or _target == null:
		_vert_dragging = false
		_vert_snapshot = {}
		return
	_target.restore_and_bake(_vert_snapshot)
	_vert_dragging = false
	_vert_snapshot = {}
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