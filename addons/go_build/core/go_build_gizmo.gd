## Per-node viewport overlay for a [GoBuildMeshInstance].
##
## Created by [GoBuildGizmoPlugin._create_gizmo]. Draws vertices, edges, and
## face centres as coloured overlays driven by the node's [SelectionManager].
##
## [b]Drawing rules:[/b]
## - OBJECT mode — no sub-element overlay.
## - VERTEX mode — faint context edges + vertex handle dots.
## - EDGE mode   — edge lines only (selected = orange, unselected = white).
## - FACE mode   — faint context edges + face-centre handle dots.
##
## Redraw is triggered from [code]plugin.gd[/code] via [method Node3D.update_gizmos]
## whenever the [SelectionManager] emits a signal.
##
## [b]Note:[/b] [method EditorPlugin.update_overlays] only repaints the 2D
## screen-space overlay ([method EditorPlugin._forward_3d_draw_over_viewport]).
## To repaint these gizmo handles you must call [method Node3D.update_gizmos]
## on the [GoBuildMeshInstance] node directly.
##
## [b]Note:[/b] The plugin is accessed via the untyped [method get_plugin] call
## (no [code]GoBuildGizmoPlugin[/code] type annotation here) to avoid a circular
## script-load dependency between the two gizmo files.
@tool
class_name GoBuildGizmo
extends EditorNode3DGizmo

# Self-preloads: Godot's startup scan processes core/ before mesh/ alphabetically.
# GoBuildMesh, GoBuildEdge, and GoBuildFace are used as compile-time type
# annotations (function parameters, typed for-loop variables) so they must be
# registered before this script is compiled.
const _FACE_SCRIPT          := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT          := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT          := preload("res://addons/go_build/mesh/go_build_mesh.gd")
# SelectionManager: same scan-order issue within core/ ('go' < 'se').
const _SEL_MGR_SCRIPT := preload("res://addons/go_build/core/selection_manager.gd")

## Handle ID base for the 3-axis transform handles.
## Must be large enough to never collide with vertex or face-centre handle IDs.
## Matches [constant GoBuildGizmoPlugin.AXIS_HANDLE_OFFSET].
const AXIS_HANDLE_OFFSET: int = 1_000_000
const _AXIS_X_ID: int = AXIS_HANDLE_OFFSET + 0
const _AXIS_Y_ID: int = AXIS_HANDLE_OFFSET + 1
const _AXIS_Z_ID: int = AXIS_HANDLE_OFFSET + 2

## Handle ID base for the 3-axis rotate ring handles.
## Must be distinct from AXIS_HANDLE_OFFSET range.
## Matches [constant GoBuildGizmoPlugin.ROT_HANDLE_OFFSET].
const ROT_HANDLE_OFFSET: int  = 2_000_000
const _ROT_RING_SEGMENTS: int = 32
const _ROT_RING_RADIUS: float = 1.05  # slightly larger than _ARROW_LENGTH

## Length of each axis arrow in local mesh units.
const _ARROW_LENGTH: float = 0.8
## Half-size (local mesh units) of the wireframe cube drawn at each vertex.
const _VERTEX_CUBE_HALF: float = 0.03


## Rebuild all viewport overlays for the attached [GoBuildMeshInstance].
## Called by the editor when [method Node3D.update_gizmos] is invoked.
func _redraw() -> void:
	clear()

	var node := get_node_3d() as GoBuildMeshInstance
	if node == null:
		return

	var gbm: GoBuildMesh = node.go_build_mesh
	if gbm == null or gbm.vertices.is_empty():
		return

	# Access the plugin without a type annotation — GoBuildGizmoPlugin is the
	# runtime type, but importing it here would create a circular script dependency.
	var plugin = get_plugin()
	if plugin == null:
		return

	var sel: SelectionManager = node.selection

	match sel.get_mode():
		SelectionManager.Mode.OBJECT:
			pass  # Mesh renders normally; no sub-element overlay needed.

		SelectionManager.Mode.VERTEX:
			_draw_context_edges(gbm, plugin.mat_edge_context)
			_draw_vertices(gbm, sel, plugin.mat_vertex_normal, plugin.mat_vertex_selected)

		SelectionManager.Mode.EDGE:
			_draw_edges(gbm, sel, plugin.mat_edge_normal, plugin.mat_edge_selected)

		SelectionManager.Mode.FACE:
				_draw_context_edges(gbm, plugin.mat_edge_context)
				_draw_face_centres(gbm, sel, plugin.mat_face_normal, plugin.mat_face_fill)

	# Draw the 3-axis translate handle whenever any sub-element is selected.
	if sel.get_mode() != SelectionManager.Mode.OBJECT and not sel.is_empty():
		var centroid := _compute_selection_centroid(gbm, sel)
		_draw_transform_handles(centroid, plugin)


# ---------------------------------------------------------------------------
# Drawing sub-routines
# ---------------------------------------------------------------------------

## Draw all edges as faint lines — provides spatial context in vertex / face modes.
func _draw_context_edges(gbm: GoBuildMesh, mat: Material) -> void:
	if gbm.edges.is_empty():
		return
	var lines := PackedVector3Array()
	lines.resize(gbm.edges.size() * 2)
	var i := 0
	for edge: GoBuildEdge in gbm.edges:
		lines[i]     = gbm.vertices[edge.vertex_a]
		lines[i + 1] = gbm.vertices[edge.vertex_b]
		i += 2
	add_lines(lines, mat)


## Draw all edges, colouring selected ones orange and unselected ones white.
func _draw_edges(
		gbm: GoBuildMesh,
		sel: SelectionManager,
		mat_normal: Material,
		mat_selected: Material,
) -> void:
	var lines_normal   := PackedVector3Array()
	var lines_selected := PackedVector3Array()

	for idx: int in gbm.edges.size():
		var edge: GoBuildEdge = gbm.edges[idx]
		var va: Vector3 = gbm.vertices[edge.vertex_a]
		var vb: Vector3 = gbm.vertices[edge.vertex_b]
		if sel.is_edge_selected(idx):
			lines_selected.append(va)
			lines_selected.append(vb)
		else:
			lines_normal.append(va)
			lines_normal.append(vb)

	if not lines_normal.is_empty():
		add_lines(lines_normal, mat_normal)
	if not lines_selected.is_empty():
		add_lines(lines_selected, mat_selected)


## Return the 24 line-segment endpoints (12 edges × 2 points) that form a
## wireframe cube of half-size [param half] centred on [param pos].
func _cube_lines_at(pos: Vector3, half: float) -> PackedVector3Array:
	var h: float = half
	# 8 corners labelled by the sign-combination of each axis component.
	var c: Array[Vector3] = [
		pos + Vector3(-h, -h, -h), pos + Vector3( h, -h, -h),
		pos + Vector3( h,  h, -h), pos + Vector3(-h,  h, -h),
		pos + Vector3(-h, -h,  h), pos + Vector3( h, -h,  h),
		pos + Vector3( h,  h,  h), pos + Vector3(-h,  h,  h),
	]
	return PackedVector3Array([
		c[0], c[1],  c[1], c[2],  c[2], c[3],  c[3], c[0],   # back face
		c[4], c[5],  c[5], c[6],  c[6], c[7],  c[7], c[4],   # front face
		c[0], c[4],  c[1], c[5],  c[2], c[6],  c[3], c[7],   # connecting edges
	])


## Draw all vertices as cube-wireframe widgets.
## Selected vertices use the highlight material (orange, no depth test) so they
## are always visible even when inside geometry.
## Unselected vertices use the normal line material (white, depth-tested).
func _draw_vertices(
		gbm: GoBuildMesh,
		sel: SelectionManager,
		mat_normal: Material,
		mat_selected: Material,
) -> void:
	var lines_normal   := PackedVector3Array()
	var lines_selected := PackedVector3Array()

	for idx: int in gbm.vertices.size():
		var cube := _cube_lines_at(gbm.vertices[idx], _VERTEX_CUBE_HALF)
		if sel.is_vertex_selected(idx):
			lines_selected.append_array(cube)
		else:
			lines_normal.append_array(cube)

	if not lines_normal.is_empty():
		add_lines(lines_normal, mat_normal)
	if not lines_selected.is_empty():
		add_lines(lines_selected, mat_selected)


## Draw face overlays in Face mode.
##
## - Unselected faces: a billboard centre dot (teal) so the user can see all
##   faces even when none are selected.
## - Selected faces: a fan-triangulated semi-transparent filled mesh so the
##   entire face surface is highlighted, plus no centre dot (the fill is
##   visually sufficient).
##
## [param mat_normal] — billboard dot material for unselected face centres.
## [param mat_fill]   — alpha-transparent surface material for selected faces.
func _draw_face_centres(
		gbm: GoBuildMesh,
		sel: SelectionManager,
		mat_normal: Material,
		mat_fill: Variant,
) -> void:
	var pts_normal := PackedVector3Array()
	var ids_normal := PackedInt32Array()
	var fill_verts := PackedVector3Array()

	var id_offset: int = gbm.vertices.size()

	for idx: int in gbm.faces.size():
		var face: GoBuildFace = gbm.faces[idx]
		if face.vertex_indices.size() < 3:
			continue

		if sel.is_face_selected(idx):
			# Fan-triangulate the face to build the fill mesh.
			var v0: Vector3 = gbm.vertices[face.vertex_indices[0]]
			for tri: int in range(face.vertex_indices.size() - 2):
				fill_verts.append(v0)
				fill_verts.append(gbm.vertices[face.vertex_indices[tri + 1]])
				fill_verts.append(gbm.vertices[face.vertex_indices[tri + 2]])
		else:
			# Centre dot for unselected faces.
			var centre := Vector3.ZERO
			for vi: int in face.vertex_indices:
				centre += gbm.vertices[vi]
			centre /= face.vertex_indices.size()
			pts_normal.append(centre)
			ids_normal.append(id_offset + idx)

	if not pts_normal.is_empty():
		add_handles(pts_normal, mat_normal, ids_normal, true)

	if not fill_verts.is_empty():
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = fill_verts
		var fill_mesh := ArrayMesh.new()
		fill_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		add_mesh(fill_mesh, mat_fill)


# ---------------------------------------------------------------------------
# Transform handle helpers
# ---------------------------------------------------------------------------

## Compute the mean position of all vertices implied by the current selection.
func _compute_selection_centroid(gbm: GoBuildMesh, sel: SelectionManager) -> Vector3:
	var sum := Vector3.ZERO
	var count := 0
	match sel.get_mode():
		SelectionManager.Mode.VERTEX:
			for idx: int in sel.get_selected_vertices():
				sum += gbm.vertices[idx]
				count += 1
		SelectionManager.Mode.EDGE:
			for eidx: int in sel.get_selected_edges():
				var edge: GoBuildEdge = gbm.edges[eidx]
				sum += gbm.vertices[edge.vertex_a]
				sum += gbm.vertices[edge.vertex_b]
				count += 2
		SelectionManager.Mode.FACE:
			for fidx: int in sel.get_selected_faces():
				for vidx: int in gbm.faces[fidx].vertex_indices:
					sum += gbm.vertices[vidx]
					count += 1
	return sum / count if count > 0 else Vector3.ZERO


## Draw the 3-axis translate widget centred on [param centroid].
## Materials are accessed via untyped [method Object.get] to avoid a circular
## import dependency with [GoBuildGizmoPlugin].
func _draw_transform_handles(centroid: Vector3, plugin: EditorNode3DGizmoPlugin) -> void:
	var tip_x := centroid + Vector3(_ARROW_LENGTH, 0.0, 0.0)
	var tip_y := centroid + Vector3(0.0, _ARROW_LENGTH, 0.0)
	var tip_z := centroid + Vector3(0.0, 0.0, _ARROW_LENGTH)

	add_lines(PackedVector3Array([centroid, tip_x]), plugin.get("mat_axis_line_x"))
	add_lines(PackedVector3Array([centroid, tip_y]), plugin.get("mat_axis_line_y"))
	add_lines(PackedVector3Array([centroid, tip_z]), plugin.get("mat_axis_line_z"))

	add_handles(PackedVector3Array([tip_x]), plugin.get("mat_axis_x"),
			PackedInt32Array([AXIS_HANDLE_OFFSET + 0]), true)
	add_handles(PackedVector3Array([tip_y]), plugin.get("mat_axis_y"),
			PackedInt32Array([AXIS_HANDLE_OFFSET + 1]), true)
	add_handles(PackedVector3Array([tip_z]), plugin.get("mat_axis_z"),
			PackedInt32Array([AXIS_HANDLE_OFFSET + 2]), true)

	_draw_rotate_rings(centroid, plugin)


## Draw three rotation-ring overlays (one per axis) centred on [param centroid].
##
## Ring colour matches the corresponding axis material.
## The handle dot for each ring sits at the first point on the ring
## (angle = 0), which lies along the chosen tangent direction:
## - X ring (YZ plane): handle dot at [code]centroid + UP * radius[/code]
## - Y ring (XZ plane): handle dot at [code]centroid + BACK * radius[/code]
## - Z ring (XY plane): handle dot at [code]centroid + RIGHT * radius[/code]
func _draw_rotate_rings(centroid: Vector3, plugin: EditorNode3DGizmoPlugin) -> void:
	# X-axis rotation ring — in the YZ plane (tangent=UP, bitangent=BACK).
	_draw_rotate_ring(centroid, Vector3.UP, Vector3.BACK,
			_ROT_RING_RADIUS, plugin.get("mat_axis_line_x"),
			ROT_HANDLE_OFFSET + 0, plugin.get("mat_axis_x"))
	# Y-axis rotation ring — in the XZ plane (tangent=BACK, bitangent=RIGHT).
	_draw_rotate_ring(centroid, Vector3.BACK, Vector3.RIGHT,
			_ROT_RING_RADIUS, plugin.get("mat_axis_line_y"),
			ROT_HANDLE_OFFSET + 1, plugin.get("mat_axis_y"))
	# Z-axis rotation ring — in the XY plane (tangent=RIGHT, bitangent=UP).
	_draw_rotate_ring(centroid, Vector3.RIGHT, Vector3.UP,
			_ROT_RING_RADIUS, plugin.get("mat_axis_line_z"),
			ROT_HANDLE_OFFSET + 2, plugin.get("mat_axis_z"))


## Draw a single rotation ring as [_ROT_RING_SEGMENTS] line segments, plus a
## billboard handle dot at the zero-angle position ([param tangent] direction).
func _draw_rotate_ring(
		centre: Vector3,
		tangent: Vector3,
		bitangent: Vector3,
		radius: float,
		mat_line: Variant,
		handle_id: int,
		mat_dot: Variant,
) -> void:
	var lines := PackedVector3Array()
	lines.resize(_ROT_RING_SEGMENTS * 2)
	for i: int in _ROT_RING_SEGMENTS:
		var a0: float = float(i)       / _ROT_RING_SEGMENTS * TAU
		var a1: float = float(i + 1)   / _ROT_RING_SEGMENTS * TAU
		lines[i * 2]     = centre + (tangent * cos(a0) + bitangent * sin(a0)) * radius
		lines[i * 2 + 1] = centre + (tangent * cos(a1) + bitangent * sin(a1)) * radius
	add_lines(lines, mat_line)
	# Handle dot at angle = 0 (tangent direction).
	add_handles(PackedVector3Array([centre + tangent * radius]),
			mat_dot, PackedInt32Array([handle_id]), true)
