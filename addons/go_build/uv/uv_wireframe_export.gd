## Exports the UV wireframe of a [GoBuildMesh] as a PNG image.
##
## Renders all UV edges as lines on a transparent or solid background at a
## configurable resolution.  The output is suitable as a painting guide in
## external applications like Krita, Photoshop, or Substance Painter.
@tool
class_name UvWireframeExport
extends RefCounted


const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")

## Default export resolution (width and height in pixels).
const _DEFAULT_SIZE: int = 1024

## Wireframe line colour.
const _WIRE_COLOR := Color(1.0, 1.0, 1.0, 1.0)

## Background colour (transparent by default).
const _BG_COLOR := Color(0.0, 0.0, 0.0, 0.0)

## Line width in pixels (approximate — uses line thickness via multi-pixel drawing).
const _LINE_WIDTH: int = 2


## Render the UV wireframe to an [Image] at the given resolution and return it.
## [param mesh] is the [GoBuildMesh] to export.
## [param size] is the width and height of the output image in pixels.
## [param wire_color] is the colour for the wireframe lines.
## [param bg_color] is the background colour (use transparent for overlay).
static func render_image(
		mesh: GoBuildMesh,
		size: int = _DEFAULT_SIZE,
		wire_color: Color = _WIRE_COLOR,
		bg_color: Color = _BG_COLOR,
) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(bg_color)

	if mesh.faces.is_empty():
		return img

	# Build a map from UV coordinates to pixel coordinates.
	# UV (0,0) = top-left, UV (1,1) = bottom-right.
	# Godot Image: (0,0) = top-left, which matches UV convention.
	for face: GoBuildFace in mesh.faces:
		if face.uvs.size() < 2:
			continue
		for i: int in face.uvs.size():
			var uv_a: Vector2 = face.uvs[i]
			var uv_b: Vector2 = face.uvs[(i + 1) % face.uvs.size()]
			_draw_line(img,
				_uv_to_px(uv_a, size),
				_uv_to_px(uv_b, size),
				wire_color, _LINE_WIDTH)

	return img


## Render the UV wireframe and save it to [param path] as a PNG.
## Returns [code]true[/code] if the file was saved successfully.
static func save_png(
		path: String,
		mesh: GoBuildMesh,
		size: int = _DEFAULT_SIZE,
		wire_color: Color = _WIRE_COLOR,
		bg_color: Color = _BG_COLOR,
) -> bool:
	var img := render_image(mesh, size, wire_color, bg_color)
	return img.save_png(path) == OK


## Convert a UV coordinate to a pixel coordinate in the image.
## UV (0,0) maps to top-left; UV (1,1) maps to bottom-right.
## Clamp to valid image bounds.
static func _uv_to_px(uv: Vector2, size: int) -> Vector2i:
	var px: int = clampi(roundi(uv.x * size), 0, size - 1)
	var py: int = clampi(roundi(uv.y * size), 0, size - 1)
	return Vector2i(px, py)


## Draw an anti-aliased line on [param img] using Bresenham's algorithm
## with configurable width.  Draws perpendicular pixels on either side
## of the line to simulate line width.
static func _draw_line(
		img: Image,
		a: Vector2i,
		b: Vector2i,
		color: Color,
		width: int,
) -> void:
	var half: int = maxi(width / 2, 0)
	var dx: int = absi(b.x - a.x)
	var dy: int = absi(b.y - a.y)
	var sx: int = 1 if a.x < b.x else -1
	var sy: int = 1 if a.y < b.y else -1
	var err: int = dx - dy
	var x: int = a.x
	var y: int = a.y
	var w: int = img.get_width()
	var h: int = img.get_height()

	while true:
		for ox: int in range(-half, half + 1):
			for oy: int in range(-half, half + 1):
				var px: int = x + ox
				var py: int = y + oy
				if px >= 0 and px < w and py >= 0 and py < h:
					img.set_pixel(px, py, color)
		if x == b.x and y == b.y:
			break
		var e2: int = 2 * err
		if e2 > -dy:
			err -= dy
			x += sx
		if e2 < dx:
			err += dx
			y += sy