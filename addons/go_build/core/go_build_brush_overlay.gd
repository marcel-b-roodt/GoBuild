## Viewport overlay for the vertex paint brush: cursor circle (world-space
## radius projected through the camera, screen-space fallback when the ray
## misses the mesh) and the bottom-left paint info label.
##
## Stateless — the plugin passes the painter/brush state in each frame.
class_name GoBuildBrushOverlay
extends RefCounted

# Self-preloads — dependency order.
const _PAINTER_SCRIPT := preload(
		"res://addons/go_build/vertex_paint/go_build_vertex_painter.gd")
const _BRUSH_SCRIPT := preload(
		"res://addons/go_build/vertex_paint/go_build_vertex_paint_brush.gd")


## Draw the brush cursor circle at the hit point showing the brush radius.
## When the ray doesn't hit the mesh, draws a simpler circle at the mouse
## position with a fixed screen-space size so the cursor is always visible.
static func draw_brush_cursor(
		overlay: Control,
		painter: GoBuildVertexPainter,
		brush: GoBuildVertexPaintBrush,
		edited_node: GoBuildMeshInstance,
		camera: Camera3D,
		draw_shadowed_text: Callable,
) -> void:
	if painter == null or brush == null or edited_node == null:
		return
	var draw_pos: Vector2 = brush.get_mouse_2d_pos()
	if draw_pos == Vector2.INF:
		draw_pos = brush.get_cursor_screen_pos()
	if draw_pos == Vector2.INF:
		return
	var world_pos: Vector3 = brush.get_cursor_world_pos()
	if camera == null:
		return
	if world_pos == Vector3.INF:
		var radius: float = painter.get_brush_radius()
		var fallback_radius: float = radius * 20.0
		fallback_radius = clampf(fallback_radius, 4.0, 60.0)
		overlay.draw_arc(draw_pos, fallback_radius, 0.0, TAU, 64,
			Color(1.0, 1.0, 1.0, 0.35), 1.0, true)
		var fb_strength: float = painter.get_brush_strength()
		var fb_inner: float = fallback_radius * fb_strength
		if fb_inner > 1.0:
			overlay.draw_arc(draw_pos, fb_inner, 0.0, TAU, 64,
					Color(1.0, 0.85, 0.35, 0.35), 1.0, true)
		_draw_paint_info(overlay, painter, draw_shadowed_text)
		return
	var avg_scale: float = (
			edited_node.scale.x + edited_node.scale.y + edited_node.scale.z) / 3.0
	var local_radius: float = painter.get_brush_radius() / avg_scale \
			if avg_scale > 0.001 else painter.get_brush_radius()
	var local_hit: Vector3 = edited_node.to_local(world_pos)
	var offset_local: Vector3 = local_hit + Vector3(local_radius, 0.0, 0.0)
	var offset_world: Vector3 = edited_node.to_global(offset_local)
	var center_screen: Vector2 = camera.unproject_position(world_pos)
	var offset_screen: Vector2 = camera.unproject_position(offset_world)
	var screen_radius: float = (offset_screen - center_screen).length()
	screen_radius = clampf(screen_radius, 4.0, 400.0)
	var color: Color = Color(1.0, 1.0, 1.0, 0.7)
	overlay.draw_arc(draw_pos, screen_radius, 0.0, TAU, 64, color, 1.5, true)
	# Strength inner circle: fills from centre to strength percentage of the radius.
	var strength: float = painter.get_brush_strength()
	var inner_radius: float = screen_radius * strength
	if inner_radius > 1.0:
		overlay.draw_arc(draw_pos, inner_radius, 0.0, TAU, 64,
				Color(1.0, 0.85, 0.35, 0.55), 1.0, true)
	_draw_paint_info(overlay, painter, draw_shadowed_text)


## Draw the paint mode info overlay (bottom-left of viewport).
static func _draw_paint_info(
		overlay: Control,
		painter: GoBuildVertexPainter,
		draw_shadowed_text: Callable,
) -> void:
	var font: Font = ThemeDB.fallback_font
	var fsize: int = 12
	var m: float = 8.0
	var blend_names: Dictionary = {
		0: "Mix", 1: "Add", 2: "Subtract", 3: "Multiply",
	}
	var blend_name: String = blend_names.get(painter.get_blend_mode(), "Mix")
	var radius_str: String = "R: %.2f" % painter.get_brush_radius()
	var strength_str: String = "S: %.0f%%" % (painter.get_brush_strength() * 100.0)
	var line1: String = "Paint | %s | %s | %s" % [blend_name, radius_str, strength_str]
	var line2: String = "Alt+Click=Eyedropper  Alt+S=Size  Alt+D=Strength  Shift+A=Cycle Blend"
	var line3: String = "Alt+Q/W/E/R=Channels  Alt+T=Isolate  Alt+1-5=Target"
	var y: float = overlay.size.y - m - 18.0 - 18.0 - 18.0
	draw_shadowed_text.call(overlay, font, Vector2(m, y), line1, fsize,
			Color(0.65, 1.0, 0.65, 0.90))
	draw_shadowed_text.call(overlay, font, Vector2(m, y + 18.0), line2, fsize,
			Color(0.65, 0.85, 1.0, 0.75))
	draw_shadowed_text.call(overlay, font, Vector2(m, y + 36.0), line3, fsize,
			Color(0.65, 0.85, 1.0, 0.75))