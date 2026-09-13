## Generates a [GoBuildMesh] representing a doorway — an AABB wall with a
## rectangular or arched opening cut through it.
##
## The wall is centred on the origin: [param width] spans X (the wall face),
## [param height] spans Y, and [param depth] spans Z (wall thickness).  The
## opening is centred horizontally and cut through the full depth:
## [param opening_width] X extent, [param opening_height] Y extent measured
## from the wall's base.
##
## [param arched] rounds the opening's top into a semicircular arc of radius
## [code]opening_width / 2[/code] centred on the opening's vertical flanks,
## so the apex reaches [code]opening_height[/code] exactly.  When
## [param arched] is false the opening is a plain rectangle and
## [param segments] is unused.
##
## The opening must not exceed the wall: [param opening_width] < [param width]
## and [param opening_height] < [param height] (asserted).
class_name DoorwayGenerator
extends RefCounted

# Self-preloads — dependency order.
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _UTILS_SCRIPT := preload("res://addons/go_build/mesh/generators/mesh_generator_utils.gd")


## Generate a doorway [GoBuildMesh] centred at the origin.
##
## [param width]           wall extent along X (must be > 0)
## [param height]          wall extent along Y (must be > 0)
## [param depth]           wall thickness along Z (must be > 0)
## [param opening_width]   opening extent along X (must be > 0, < width)
## [param opening_height]  opening extent along Y from the base (0 < oh < height)
## [param arched]          round the opening's top into a semicircle
## [param segments]        arc segments for the arch top (>= 1, arched only)
## [param material_index]  material slot for all faces
static func generate(
		width: float = 2.0,
		height: float = 2.5,
		depth: float = 0.2,
		opening_width: float = 1.0,
		opening_height: float = 2.0,
		arched: bool = false,
		segments: int = 8,
		material_index: int = 0,
) -> GoBuildMesh:
	assert(width          > 0.0, "DoorwayGenerator: width must be > 0")
	assert(height         > 0.0, "DoorwayGenerator: height must be > 0")
	assert(depth          > 0.0, "DoorwayGenerator: depth must be > 0")
	assert(opening_width  > 0.0, "DoorwayGenerator: opening_width must be > 0")
	assert(opening_width  < width, "DoorwayGenerator: opening_width must be < width")
	assert(opening_height > 0.0, "DoorwayGenerator: opening_height must be > 0")
	assert(opening_height < height, "DoorwayGenerator: opening_height must be < height")
	assert(segments >= 1, "DoorwayGenerator: segments must be >= 1")

	if arched:
		return _generate_arched(
				width, height, depth, opening_width, opening_height, segments, material_index)
	return _generate_rectangular(
			width, height, depth, opening_width, opening_height, material_index)


## Rectangular opening: jamb columns + a header band across the FULL wall
## width.  Wall centred on origin, base at y = -height/2.
##
## Decomposition: jambs run base → opening top (their tops buried against
## the header band's bottom, skipped); the header band spans the full
## wall width from the opening top to the wall top — its bottom face is
## the opening ceiling (visible), the strips over the jambs are buried
## (no face).  No buried inner-wall spans above the opening: Open H moves
## the jamb inner walls, ceiling and the front/back split line together.
## 16 faces.  See issues/2026-09-12-doorway-weld-rings.md.
static func _generate_rectangular(
		width: float,
		height: float,
		depth: float,
		ow: float,
		oh: float,
		material_index: int,
) -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	var hw := width * 0.5
	var hh := height * 0.5
	var base := -hh
	var top := hh
	var y_open_top := base + oh
	var r := ow * 0.5
	var hd := depth * 0.5

	# Jamb columns: base → opening top, outside the opening.  Their top
	# faces are buried against the header band above — skip them.
	_add_box_x(mesh, base, y_open_top, depth, r, hw, material_index,
			["top"] as Array[String])       # right
	_add_box_x(mesh, base, y_open_top, depth, -hw, -r, material_index,
			["top"] as Array[String])       # left

	# Header band: opening top → wall top, FULL wall width.  Front,
	# back, top stay whole; the bottom is only the opening ceiling (the
	# strips over the jambs are buried against their tops — no face).
	_add_box_x(mesh, y_open_top, top, depth, -hw, hw, material_index,
			["bottom", "left", "right"] as Array[String])
	MeshGeneratorUtils.add_quad_grid(mesh,
			Vector3(r, y_open_top, hd), Vector3(-r, y_open_top, hd),
			Vector3(-r, y_open_top, -hd), Vector3(r, y_open_top, -hd),
			1, 1, material_index)

	mesh.finalize()
	return mesh


## Arched opening: jambs below the spring line and a head band from the
## spring line to the wall top, minus the semicircular arc void.
##
## Decomposition (all pieces butt cleanly, interior seams invisible):
##   - 2 jamb boxes: x outside the opening, y from base to spring line
##     (tops buried against the head band, skipped)
##   - Head band x ∈ [-width/2, +width/2], y ∈ [spring, wall top]:
##     front/back faces are per-arc-segment strips over the opening
##     (arc → wall top) plus a flat flank strip on each side
##     (spring → wall top over the jambs); the wall-top quad closes it;
##     the reveal quads through the wall thickness form the arched
##     hole surface.  No spandrel boxes, no exposed flank plane above
##     the arc — the opening above the spring line is bounded only by
##     the reveal (Open H moves spring_y, the arc and the reveal with it).
static func _generate_arched(
		width: float,
		height: float,
		depth: float,
		ow: float,
		oh: float,
		segments: int,
		material_index: int,
) -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	var hw := width * 0.5
	var hh := height * 0.5
	var hd := depth * 0.5
	var base := -hh
	var top := hh
	var radius := ow * 0.5
	var spring_y: float = maxf(base + oh - radius, base)  # arc centre height

	# Jamb columns: base → spring line, outside the opening.  Their top
	# faces are buried against the head band's flank strips above — skip.
	_add_box_x(mesh, base, spring_y, depth, radius, hw, material_index,
			["top"] as Array[String])       # right
	_add_box_x(mesh, base, spring_y, depth, -hw, -radius, material_index,
			["top"] as Array[String])       # left

	# ── Arc head: semicircle from -90° (left flank at (-radius, spring_y))
	# to +90° (right flank), apex at (0, spring_y + radius) = opening top.
	#
	# Per sample i (segments + 1 samples):
	#   front arc:  i * 4 + 0     front top: i * 4 + 1
	#   back  arc:  i * 4 + 2     back  top: i * 4 + 3
	var n := segments + 1
	var vert_base: int = mesh.vertices.size()
	for i in range(n):
		var t: float = float(i) / float(segments)
		var angle: float = -PI * 0.5 + PI * t  # -90° → +90°, left → right
		var cos_a := cos(angle)
		var sin_a := sin(angle)
		var ax := sin_a * radius
		var ay := spring_y + cos_a * radius
		mesh.vertices.append(Vector3(ax, ay, hd))    # front arc
		mesh.vertices.append(Vector3(ax, top, hd))   # front top
		mesh.vertices.append(Vector3(ax, ay, -hd))   # back arc
		mesh.vertices.append(Vector3(ax, top, -hd))  # back top

	# Left/right flank strips (spring → wall top over the jambs, front +
	# back) — replace the spandrel boxes; their bottom edges are shared
	# with the jamb tops (buried interface, no face) and their side edges
	# with the outer wall.
	_add_flank_quad(mesh, -hw, -radius, spring_y, top, hd, true, material_index)
	_add_flank_quad(mesh, -hw, -radius, spring_y, top, hd, false, material_index)
	_add_flank_quad(mesh, radius, hw, spring_y, top, hd, true, material_index)
	_add_flank_quad(mesh, radius, hw, spring_y, top, hd, false, material_index)

	for i in range(segments):
		var fa0 := vert_base + i * 4
		var fa1 := vert_base + (i + 1) * 4
		var ft0 := vert_base + i * 4 + 1
		var ft1 := vert_base + (i + 1) * 4 + 1
		var ba0 := vert_base + i * 4 + 2
		var ba1 := vert_base + (i + 1) * 4 + 2
		var bt0 := vert_base + i * 4 + 3
		var bt1 := vert_base + (i + 1) * 4 + 3

		# Front head quad (normal +Z): arc L→R along bottom, ceiling R→L on top.
		var front := GoBuildFace.new()
		front.vertex_indices = [fa0, fa1, ft1, ft0]
		front.material_index = material_index
		front.uvs = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
		mesh.faces.append(front)

		# Back head quad (normal -Z).
		var back := GoBuildFace.new()
		back.vertex_indices = [bt0, bt1, ba1, ba0]
		back.material_index = material_index
		back.uvs = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
		mesh.faces.append(back)

		# Reveal quad: the arched opening surface through the wall thickness,
		# normal pointing into the opening (toward arc centre).
		var reveal := GoBuildFace.new()
		reveal.vertex_indices = [ba0, ba1, fa1, fa0]
		reveal.material_index = material_index
		reveal.uvs = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
		mesh.faces.append(reveal)

	# Wall-top quad (normal +Y): closes the head band between the front/
	# back strips — spans the full wall width.  Skipped when degenerate
	# (apex flush with the wall top: strips have zero height).
	if top - spring_y - radius > 0.0001:
		var cap := GoBuildFace.new()
		cap.vertex_indices = [
			mesh.vertices.size(), mesh.vertices.size() + 1,
			mesh.vertices.size() + 2, mesh.vertices.size() + 3]
		cap.material_index = material_index
		cap.uvs = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
		mesh.vertices.append(Vector3(-hw, top, -hd))
		mesh.vertices.append(Vector3(hw, top, -hd))
		mesh.vertices.append(Vector3(hw, top, hd))
		mesh.vertices.append(Vector3(-hw, top, hd))
		mesh.faces.append(cap)

	mesh.finalize()
	return mesh


## Add one head-band flank strip quad: spring → wall top over the jamb band
## [param x0, param x1], on the front (normal +Z) when [param front] or the
## back (normal -Z) face of the wall.
static func _add_flank_quad(
		mesh: GoBuildMesh,
		x0: float,
		x1: float,
		spring_y: float,
		top: float,
		hd: float,
		front: bool,
		material_index: int,
) -> void:
	var face := GoBuildFace.new()
	if front:
		face.vertex_indices = [
			mesh.vertices.size(), mesh.vertices.size() + 1,
			mesh.vertices.size() + 2, mesh.vertices.size() + 3]
		mesh.vertices.append(Vector3(x0, spring_y, hd))
		mesh.vertices.append(Vector3(x1, spring_y, hd))
		mesh.vertices.append(Vector3(x1, top, hd))
		mesh.vertices.append(Vector3(x0, top, hd))
	else:
		face.vertex_indices = [
			mesh.vertices.size(), mesh.vertices.size() + 1,
			mesh.vertices.size() + 2, mesh.vertices.size() + 3]
		mesh.vertices.append(Vector3(x1, spring_y, -hd))
		mesh.vertices.append(Vector3(x0, spring_y, -hd))
		mesh.vertices.append(Vector3(x0, top, -hd))
		mesh.vertices.append(Vector3(x1, top, -hd))
	face.material_index = material_index
	face.uvs = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	mesh.faces.append(face)


## Add a closed rectangular box spanning [param y0, param y1] × full depth ×
## [param x0, param x1].
## [param skip] omits named faces ("front", "back", "top", "bottom",
## "left", "right") when they are buried against a neighbouring box —
## coincident coplanar faces z-fight.
## Skipped silently when either extent is degenerate.
static func _add_box_x(
		mesh: GoBuildMesh,
		y0: float,
		y1: float,
		depth: float,
		x0: float,
		x1: float,
		material_index: int,
		skip: Array[String] = [],
) -> void:
	if x1 - x0 < 0.0001 or y1 - y0 < 0.0001:
		return
	var hd := depth * 0.5
	# Front (Z+)
	if not skip.has("front"):
		MeshGeneratorUtils.add_quad_grid(mesh,
			Vector3(x0, y0, hd), Vector3(x1, y0, hd),
			Vector3(x1, y1, hd), Vector3(x0, y1, hd), 1, 1, material_index)
	# Back (Z-)
	if not skip.has("back"):
		MeshGeneratorUtils.add_quad_grid(mesh,
			Vector3(x1, y0, -hd), Vector3(x0, y0, -hd),
			Vector3(x0, y1, -hd), Vector3(x1, y1, -hd), 1, 1, material_index)
	# Top (Y+)
	if not skip.has("top"):
		MeshGeneratorUtils.add_quad_grid(mesh,
			Vector3(x0, y1, hd), Vector3(x1, y1, hd),
			Vector3(x1, y1, -hd), Vector3(x0, y1, -hd), 1, 1, material_index)
	# Bottom (Y-)
	if not skip.has("bottom"):
		MeshGeneratorUtils.add_quad_grid(mesh,
			Vector3(x0, y0, -hd), Vector3(x1, y0, -hd),
			Vector3(x1, y0, hd), Vector3(x0, y0, hd), 1, 1, material_index)
	# Right (X+, at x1)
	if not skip.has("right"):
		MeshGeneratorUtils.add_quad_grid(mesh,
			Vector3(x1, y0, hd), Vector3(x1, y0, -hd),
			Vector3(x1, y1, -hd), Vector3(x1, y1, hd), 1, 1, material_index)
	# Left (X-, at x0)
	if not skip.has("left"):
		MeshGeneratorUtils.add_quad_grid(mesh,
			Vector3(x0, y0, -hd), Vector3(x0, y0, hd),
			Vector3(x0, y1, hd), Vector3(x0, y1, -hd), 1, 1, material_index)
