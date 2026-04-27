## 2D canvas that draws the UV layout of the active [GoBuildMeshInstance].
##
## Displays all face UVs as wireframe polygons in the 0-1 UV tile.
## Selected faces are highlighted.  Supports pan (middle-mouse drag) and
## zoom (scroll wheel).
##
## Add as a child of [GoBuildUvPanel].  Call [method set_target] when the
## active mesh node changes; the canvas auto-refreshes whenever the mesh
## emits [signal GoBuildMeshInstance.mesh_changed] or when
## [method queue_redraw] is called externally.
@tool
class_name GoBuildUvCanvas
extends Control

# Self-preloads — compile-time type references.
const _SEL_MGR_SCRIPT        := preload("res://addons/go_build/core/selection_manager.gd")
const _MESH_INSTANCE_SCRIPT  := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _FACE_SCRIPT           := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MESH_SCRIPT           := preload("res://addons/go_build/mesh/go_build_mesh.gd")

# ---------------------------------------------------------------------------
# Colours
# ---------------------------------------------------------------------------
const _BG_COLOR           := Color(0.12, 0.12, 0.12)
const _TILE_BG_COLOR      := Color(0.17, 0.17, 0.17)
const _TILE_BORDER_COLOR  := Color(0.55, 0.55, 0.55)
const _HALF_LINE_COLOR    := Color(0.30, 0.30, 0.30)
const _FACE_WIRE_COLOR    := Color(0.45, 0.65, 1.0, 0.75)
const _SEL_FILL_COLOR     := Color(1.0, 0.70, 0.20, 0.18)
const _SEL_WIRE_COLOR     := Color(1.0, 0.85, 0.35, 1.0)

# ---------------------------------------------------------------------------
# View state
# ---------------------------------------------------------------------------
const _ZOOM_MIN:     float = 40.0
const _ZOOM_MAX:     float = 8000.0
const _ZOOM_DEFAULT: float = 180.0

## Pixels per UV unit.
var _zoom: float = _ZOOM_DEFAULT
## Pan offset in pixels, relative to the canvas centre.
var _pan: Vector2 = Vector2.ZERO

## True while the user is middle-mouse dragging.
var _dragging:           bool     = false
var _drag_start_mouse:   Vector2  = Vector2.ZERO
var _drag_start_pan:     Vector2  = Vector2.ZERO

## The mesh node being visualised (may be null).
var _target: GoBuildMeshInstance = null


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Switch to visualising [param node].
##
## Disconnects the previous target's [signal GoBuildMeshInstance.mesh_changed]
## signal and reconnects to the new one.
func set_target(node: GoBuildMeshInstance) -> void:
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


## Draw the UV-space tile (0-1 range) with border and half-way grid lines.
func _draw_grid() -> void:
	var tl := _uv_to_canvas(Vector2(0.0, 0.0))
	var br := _uv_to_canvas(Vector2(1.0, 1.0))
	draw_rect(Rect2(tl, br - tl), _TILE_BG_COLOR)
	draw_rect(Rect2(tl, br - tl), _TILE_BORDER_COLOR, false, 1.0)
	var mid_x := (tl.x + br.x) * 0.5
	var mid_y := (tl.y + br.y) * 0.5
	draw_line(Vector2(mid_x, tl.y), Vector2(mid_x, br.y), _HALF_LINE_COLOR, 0.5)
	draw_line(Vector2(tl.x, mid_y), Vector2(br.x, mid_y), _HALF_LINE_COLOR, 0.5)


## Draw every face's UV polygon, highlighting selected faces.
func _draw_faces() -> void:
	var gbm: GoBuildMesh = _target.go_build_mesh
	var selected: Array[int] = []
	if _target.selection.get_mode() == SelectionManager.Mode.FACE:
		selected = _target.selection.get_selected_faces()

	for fi: int in gbm.faces.size():
		var face: GoBuildFace = gbm.faces[fi]
		if face.uvs.size() < 3:
			continue

		var pts := PackedVector2Array()
		for uv: Vector2 in face.uvs:
			pts.append(_uv_to_canvas(uv))

		var is_sel: bool = selected.has(fi)
		# Close the polygon loop.
		var closed_pts: PackedVector2Array = pts + PackedVector2Array([pts[0]])

		if is_sel:
			draw_polygon(pts, PackedColorArray([_SEL_FILL_COLOR]))
		draw_polyline(closed_pts, _SEL_WIRE_COLOR if is_sel else _FACE_WIRE_COLOR, 1.0)


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


# ---------------------------------------------------------------------------
# Input — pan and zoom
# ---------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, 1.1)
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / 1.1)
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
			if _dragging:
				_drag_start_mouse = mb.position
				_drag_start_pan   = _pan
			accept_event()
			return

	if event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_pan = _drag_start_pan + (mm.position - _drag_start_mouse)
		queue_redraw()
		accept_event()


## Zoom toward [param cursor_pos] (canvas pixel coordinates).
func _zoom_at(cursor_pos: Vector2, factor: float) -> void:
	var new_zoom := clampf(_zoom * factor, _ZOOM_MIN, _ZOOM_MAX)
	if new_zoom == _zoom:
		return
	# Adjust pan so the UV coordinate under the cursor stays fixed.
	var uv_under_cursor := (cursor_pos - (size * 0.5 + _pan)) / _zoom
	_pan = cursor_pos - (size * 0.5) - uv_under_cursor * new_zoom
	_zoom = new_zoom
	queue_redraw()
