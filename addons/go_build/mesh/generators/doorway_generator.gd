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
const _DISSOLVE_SCRIPT := preload("res://addons/go_build/mesh/operations/dissolve_operation.gd")
const _EDGE_SCRIPT := preload("res://addons/go_build/mesh/go_build_edge.gd")


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


## Rectangular opening: two jamb columns + a header slab across the top.
## Wall centred on origin, base at y = -height/2.
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
	var hd := depth * 0.5
	var base := -hh
	var top := hh
	var y_open_top := base + oh

	var jamb_w := (width - ow) * 0.5
	var header_h := height - oh

	# Jamb columns: from base to top (jambs run full height so the header
	# sits on top of them — simpler split, no T-junction worries).
	_add_box_x(mesh, base, top, depth, hw - jamb_w, hw, material_index)             # right
	_add_box_x(mesh, base, top, depth, -hw, -hw + jamb_w, material_index)           # left

	# Header slab above the opening.  Its side faces (±X) are buried
	# against the jamb columns' inner faces — skip them (z-fighting).
	if header_h > 0.0:
		_add_box_x(mesh, y_open_top, top, depth, -hw + jamb_w, hw - jamb_w,
				material_index, ["left", "right"] as Array[String])

	mesh.finalize()
	# Post-weld topology repair: dissolve the seam between the header slab
	# and the jamb inner walls at the opening-top plane, then the header's
	# internal front/back seam.  Result: jamb boxes with clean quads, one
	# header through-quad pair, no buried faces.  See
	# issues/2026-09-12-doorway-weld-rings.md.
	_dissolve_header_seam(mesh, y_open_top)
	return mesh


## Arched opening: jambs below the spring line, spandrel boxes above them
## beside the arc, and an arc-to-ceiling head over the opening.
##
## Decomposition (all pieces butt cleanly, interior seams invisible):
##   - 2 jamb boxes: x outside the opening, y from base to spring line
##   - 2 spandrel boxes: same x band, y from spring line to wall top
##   - Arc head across x ∈ [-ow/2, +ow/2]: semicircle centred at
##     (0, spring_y) swept from -90° to +90°, filled up to the wall top with
##     per-segment front/back quads plus a reveal quad through the wall
##     thickness (the arched hole surface).
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
	# faces are buried against the spandrel boxes above — skip them.
	_add_box_x(mesh, base, spring_y, depth, radius, hw, material_index,
			["top"] as Array[String])       # right
	_add_box_x(mesh, base, spring_y, depth, -hw, -radius, material_index,
			["top"] as Array[String])       # left

	# Spandrel boxes: spring line → wall top, same x bands.  Their bottom
	# faces are buried against the jambs below — skip them.
	_add_box_x(mesh, spring_y, top, depth, radius, hw, material_index,
			["bottom"] as Array[String])    # right
	_add_box_x(mesh, spring_y, top, depth, -hw, -radius, material_index,
			["bottom"] as Array[String])    # left

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

	mesh.finalize()
	return mesh


## Add a closed rectangular box spanning [param y0, param y1] × full depth ×
## [param x0, param x1].
## Used for jamb columns / header / side slabs — all axis-aligned boxes.
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


## Dissolve the header seam after [method GoBuildMesh.finalize].
##
## The header slab's bottom edges and the jamb inner walls' top edges meet
## at the opening-top plane ([param y_open_top]).  Two dissolve rounds
## there: (1) edges whose two faces have different axis classes (horizontal
## header bottom ⊥ vertical inner wall), (2) the header's internal front/back
## seam (both face centres above the seam).  The wall-top junction edges
## stay — they are planar T-junctions by design, not seams.
## See issues/2026-09-12-doorway-weld-rings.md.
static func _dissolve_header_seam(mesh: GoBuildMesh, y_open_top: float) -> void:
	for round: int in 4:
		# (a) seam edges: horizontal face ⊥ vertical face at the plane.
		var edges: Array[int] = []
		for ei: int in mesh.edges.size():
			var edge: GoBuildEdge = mesh.edges[ei]
			if edge.face_indices.size() != 2:
				continue
			var mid: Vector3 = (
					(mesh.vertices[edge.vertex_a] + mesh.vertices[edge.vertex_b]) * 0.5)
			if absf(mid.y - y_open_top) >= 0.001:
				continue
			var na: Vector3 = mesh.compute_face_normal(mesh.faces[edge.face_indices[0]])
			var nb: Vector3 = mesh.compute_face_normal(mesh.faces[edge.face_indices[1]])
			if (absf(na.y) > 0.9) != (absf(nb.y) > 0.9):
				edges.append(ei)
		# (b) header-internal seam: both faces' centres sit in the header band.
		if edges.is_empty():
			for ei: int in mesh.edges.size():
				var edge: GoBuildEdge = mesh.edges[ei]
				if edge.face_indices.size() != 2:
					continue
				var mid: Vector3 = (
						(mesh.vertices[edge.vertex_a] + mesh.vertices[edge.vertex_b]) * 0.5)
				if absf(mid.y - y_open_top) >= 0.001:
					continue
				var centre_a := Vector3.ZERO
				for vi: int in mesh.faces[edge.face_indices[0]].vertex_indices:
					centre_a += mesh.vertices[vi]
				centre_a /= float(mesh.faces[edge.face_indices[0]].vertex_indices.size())
				var centre_b := Vector3.ZERO
				for vi: int in mesh.faces[edge.face_indices[1]].vertex_indices:
					centre_b += mesh.vertices[vi]
				centre_b /= float(mesh.faces[edge.face_indices[1]].vertex_indices.size())
				if centre_a.y > y_open_top + 0.001 \
						and centre_b.y > y_open_top + 0.001:
					edges.append(ei)
		if edges.is_empty():
			break
		DissolveOperation.dissolve_edges(mesh, edges)
	mesh.validate_edge_topology()