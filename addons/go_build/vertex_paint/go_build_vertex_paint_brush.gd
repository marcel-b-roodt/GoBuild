## Handles interactive vertex colour painting in the 3D viewport.
##
## Owned by [GoBuildPlugin]. Receives mouse events forwarded from
## [method EditorPlugin._forward_3d_gui_input] when the painter panel is
## active.  Manages brush strokes (mousedown → mousemove → mouseup) as
## single undo actions.
##
## Stroke flow:
##   1. mousedown → take snapshot, record start position
##   2. mousemove → find vertices within brush radius, apply paint
##   3. mouseup → commit undo action, restore snapshot on undo
##
## Also handles the eyedropper (Ctrl+click) and draws the brush cursor
## overlay in the viewport.
##
## The brush uses [class_name PickingHelper] for raycasting and
## [class_name VertexColorOperation] for applying paint.
@tool
class_name GoBuildVertexPaintBrush
extends RefCounted

# Self-preloads — dependency order.
const _MESH_SCRIPT_PB       := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _MESH_INST_SCRIPT_PB := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _VC_OP_SCRIPT_PB      := \
		preload("res://addons/go_build/mesh/operations/vertex_color_operation.gd")

var _plugin: EditorPlugin = null
var _painter: GoBuildVertexPainter = null
var _active: bool = false
var _snapshot: Dictionary = {}
var _painted_vertices: Dictionary = {}  # vi → original Color
var _cursor_screen_pos: Vector2 = Vector2.INF
var _cursor_world_pos: Vector3 = Vector3.INF

# Resize/strength interaction state.
# _resizing_radius: F key held, mouse X movement changes brush radius.
# _resizing_strength: S key held, mouse X movement changes brush strength.
var _resizing_radius: bool = false
var _resizing_strength: bool = false
var _resize_anchor_x: float = 0.0  # mouse X when resize started
var _resize_anchor_val: float = 0.0  # original radius/strength when resize started


## Begin a paint stroke.  Takes a snapshot for undo and enters preview mode.
func begin_stroke(node: GoBuildMeshInstance) -> void:
	if node == null or node.go_build_mesh == null:
		return
	_snapshot = node.go_build_mesh.take_snapshot()
	_painted_vertices.clear()
	_active = true
	node.begin_preview()


## Apply paint at the given world position.  Finds all vertices within
## brush radius and paints them with the current colour, blend mode, and
## channel mask from the painter panel.
func paint_at(
		node: GoBuildMeshInstance,
		world_pos: Vector3,
		radius: float,
		color: Color,
		blend_mode: int,
		channel_mask: int,
		strength: float,
) -> void:
	if not _active or node == null or node.go_build_mesh == null:
		return
	var mesh: GoBuildMesh = node.go_build_mesh
	var local_pos: Vector3 = node.to_local(world_pos)
	var avg_scale: float = (node.scale.x + node.scale.y + node.scale.z) / 3.0
	var local_radius: float = radius / avg_scale if avg_scale > 0.001 else radius
	var painted: bool = paint_vertices_in_radius(mesh, local_pos, local_radius,
		color, blend_mode, channel_mask, strength, _painted_vertices)
	if painted:
		node.bake_preview()


## Static helper: find vertices within [param local_radius] of [param local_pos]
## and paint them.  Used by [method paint_at] and directly by tests.
## [param painted_vertices] is an optional dictionary that maps vertex index →
## original [Color]; entries are added on first hit.
## Returns [code]true[/code] if any vertices were painted, [code]false[/code] otherwise.
static func paint_vertices_in_radius(
		mesh: GoBuildMesh,
		local_pos: Vector3,
		local_radius: float,
		color: Color,
		blend_mode: int,
		channel_mask: int,
		strength: float,
		painted_vertices: Dictionary = {},
) -> bool:
	var radius_sq: float = local_radius * local_radius
	var affected: Array[int] = []
	for i: int in mesh.vertices.size():
		if mesh.vertices[i].distance_squared_to(local_pos) <= radius_sq:
			if not painted_vertices.has(i):
				painted_vertices[i] = mesh.vertex_colors[i] if mesh.vertex_colors.size() > i else Color.WHITE
			affected.append(i)
	if affected.is_empty():
		return false
	var effective_color := Color(color.r, color.g, color.b, color.a)
	if strength < 1.0:
		effective_color = Color(
			color.r * strength,
			color.g * strength,
			color.b * strength,
			color.a * strength
		)
	VertexColorOperation.set_vertices(mesh, affected, effective_color, blend_mode, channel_mask)
	return true


## End the paint stroke.  Commits an undo action that restores the snapshot.
func end_stroke(node: GoBuildMeshInstance, ur: EditorUndoRedoManager) -> void:
	if not _active or node == null:
		_active = false
		return
	var snapshot := _snapshot
	_active = false
	_painted_vertices.clear()
	if snapshot.is_empty():
		return
	# Exit preview mode and do a full bake for the undo record.
	node.end_preview()
	node.bake()
	ur.create_action("Paint Vertex Color")
	ur.add_do_method(node, "bake")
	ur.add_undo_method(node, "restore_and_bake", snapshot)
	ur.commit_action()


## Cancel the stroke without committing undo.
func cancel_stroke(node: GoBuildMeshInstance) -> void:
	if not _active or node == null:
		_active = false
		return
	if not _snapshot.is_empty() and node.go_build_mesh != null:
		node.go_build_mesh.restore_snapshot(_snapshot)
		node.end_preview()
		node.bake()
	_active = false
	_painted_vertices.clear()


func is_active() -> bool:
	return _active


func setup(plugin: EditorPlugin, painter: GoBuildVertexPainter) -> void:
	_plugin = plugin
	_painter = painter


# ---------------------------------------------------------------------------
# Input handling — called from [method EditorPlugin._forward_3d_gui_input]
# ---------------------------------------------------------------------------

## Handle a 3D viewport input event for painting.
## Returns non-zero if the event was consumed.
func handle_input(camera: Camera3D, event: InputEvent, node: GoBuildMeshInstance) -> int:
	if node == null or _painter == null:
		return 0
	if not _painter.is_paint_mode():
		_cursor_world_pos = Vector3.INF
		_cursor_screen_pos = Vector2.INF
		return 0
	if event is InputEventKey:
		return _handle_key(event)
	if event is InputEventMouseMotion:
		return _handle_motion(camera, event, node)
	if event is InputEventMouseButton:
		return _handle_click(camera, event, node)
	return 0


func _handle_key(event: InputEvent) -> int:
	var ek: InputEventKey = event as InputEventKey
	if ek.pressed and not ek.echo:
		if ek.keycode == KEY_A:
			_cycle_blend_mode()
			return 1
		if ek.keycode == KEY_F:
			_resizing_radius = true
			_resize_anchor_x = _cursor_screen_pos.x if _cursor_screen_pos != Vector2.INF else 0.0
			_resize_anchor_val = _painter.get_brush_radius()
			return 1
		if ek.keycode == KEY_S:
			_resizing_strength = true
			_resize_anchor_x = _cursor_screen_pos.x if _cursor_screen_pos != Vector2.INF else 0.0
			_resize_anchor_val = _painter.get_brush_strength()
			return 1
	elif not ek.pressed:
		if ek.keycode == KEY_F and _resizing_radius:
			_resizing_radius = false
			return 1
		if ek.keycode == KEY_S and _resizing_strength:
			_resizing_strength = false
			return 1
	return 0


func _handle_motion(camera: Camera3D, event: InputEvent, node: GoBuildMeshInstance) -> int:
	var mm: InputEventMouseMotion = event as InputEventMouseMotion
	_cursor_screen_pos = mm.position
	_cursor_world_pos = PickingHelper.nearest_face_world_hit(
		camera, mm.position, node, node.go_build_mesh, true)
	if _resizing_radius:
		var dx: float = mm.position.x - _resize_anchor_x
		_painter.set_brush_radius(clampf(_resize_anchor_val + dx * 0.01, 0.01, 10.0))
		return 1
	if _resizing_strength:
		var dx: float = mm.position.x - _resize_anchor_x
		_painter.set_brush_strength(clampf(_resize_anchor_val + dx * 0.005, 0.01, 1.0))
		return 1
	if _active and _cursor_world_pos != Vector3.INF:
		_paint_brush_dab(node, camera, _cursor_world_pos)
		return 1
	return 0


func _handle_click(camera: Camera3D, event: InputEvent, node: GoBuildMeshInstance) -> int:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return 0
	if _resizing_radius or _resizing_strength:
		return 1
	if Input.is_key_pressed(KEY_CTRL):
		if mb.pressed:
			_eyedrop(camera, mb.position, node)
		return 1
	if mb.pressed:
		begin_stroke(node)
		var world_pos: Vector3 = PickingHelper.nearest_face_world_hit(
			camera, mb.position, node, node.go_build_mesh, true)
		if world_pos != Vector3.INF:
			_paint_brush_dab(node, camera, world_pos)
	else:
		end_stroke(node, _plugin.get_undo_redo())
	return 1


## Clear stored cursor position (call when the edited node changes or painter hides).
func clear_cursor() -> void:
	_cursor_world_pos = Vector3.INF
	_cursor_screen_pos = Vector2.INF


func get_cursor_world_pos() -> Vector3:
	return _cursor_world_pos


func get_cursor_screen_pos() -> Vector2:
	return _cursor_screen_pos


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

## Paint a single dab at [param world_pos] using the current painter settings.
func _paint_brush_dab(node: GoBuildMeshInstance, _camera: Camera3D, world_pos: Vector3) -> void:
	paint_at(
		node, world_pos,
		_painter.get_brush_radius(),
		_painter.get_paint_color(),
		_painter.get_blend_mode(),
		_painter.get_channel_mask(),
		_painter.get_brush_strength(),
	)


## Sample the vertex colour at the nearest vertex to [param screen_pos]
## and push it into the painter's colour picker.
func _eyedrop(camera: Camera3D, screen_pos: Vector2, node: GoBuildMeshInstance) -> void:
	if node == null or node.go_build_mesh == null:
		return
	var gbm: GoBuildMesh = node.go_build_mesh
	var vi: int = PickingHelper.find_nearest_vertex(
		camera, screen_pos, node, gbm)
	if vi < 0 or vi >= gbm.vertex_colors.size():
		return
	_painter.set_paint_color(gbm.vertex_colors[vi])


## Cycle through blend modes: Mix → Add → Subtract → Multiply → Mix…
func _cycle_blend_mode() -> void:
	var current: int = _painter.get_blend_mode()
	var modes: Array[int] = [
		VertexColorOperation.BlendMode.MIX,
		VertexColorOperation.BlendMode.ADD,
		VertexColorOperation.BlendMode.SUBTRACT,
		VertexColorOperation.BlendMode.MULTIPLY,
	]
	var idx: int = modes.find(current)
	if idx < 0 or idx >= modes.size() - 1:
		_painter.set_blend_mode(modes[0])
	else:
		_painter.set_blend_mode(modes[idx + 1])


## Whether the user is currently resizing the brush radius (F held).
func is_resizing_radius() -> bool:
	return _resizing_radius


## Whether the user is currently adjusting brush strength (S held).
func is_resizing_strength() -> bool:
	return _resizing_strength