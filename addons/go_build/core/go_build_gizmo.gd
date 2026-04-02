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
## Radius of the rotation ring in local mesh units.
## Public so [GoBuildGizmoPlugin] can compute handle screen positions for hit-testing.
## Also mirrored as [constant GoBuildGizmoPlugin.ROT_RING_RADIUS].
const ROT_RING_RADIUS: float = 1.05  # slightly larger than ARROW_LENGTH

## Length of each axis arrow in local mesh units.
## Public so [GoBuildGizmoPlugin] can compute handle screen positions for hit-testing.
## Also mirrored as [constant GoBuildGizmoPlugin.ARROW_LENGTH].
const ARROW_LENGTH: float = 0.8
## Height of the cone arrowhead along the axis direction.
## Also mirrored as [constant GoBuildGizmoPlugin.CONE_HEIGHT].
const CONE_HEIGHT: float  = 0.18
## Base radius of the cone arrowhead.
const _CONE_RADIUS: float   = 0.07
## Number of segments around the cone base (higher = smoother).
const _CONE_SEGMENTS: int   = 8
## Half-size coefficient for the wireframe cube drawn at each vertex handle.
## This value is multiplied by the gizmo scale factor (camera-distance-dependent)
## in [method _draw_vertices] so the cubes appear at a roughly constant screen
## size regardless of zoom level.
## Calibrated so that at GIZMO_SCREEN_FACTOR = 0.25 and a typical working
## distance the cube projects to ~12 px on screen (small but clearly visible).
##
## [b]Public[/b] so [PickingHelper.compute_vertex_pick_radius_px] can derive a
## matching pick radius — both must stay in sync (see TODO B).
const VERTEX_CUBE_HALF: float = 0.09
## Direct plugin reference — set only when the gizmo is created via the
## manual [method Node3D.add_gizmo] path in [code]plugin.gd[/code].
## When Godot creates the gizmo through the normal [method _create_gizmo]
## pipeline it sets the plugin reference internally, so [method get_plugin]
## works.  When we call [method Node3D.add_gizmo] directly (bypassing the
## C++ pipeline), [method get_plugin] returns null — this field is the
## fallback.  Left null for the engine-managed creation path.
##
## Untyped to avoid a circular script-load dependency with GoBuildGizmoPlugin.
var _manual_plugin_ref = null


## Rebuild all viewport overlays for the attached [GoBuildMeshInstance].
## Called by the editor when [method Node3D.update_gizmos] is invoked.
func _redraw() -> void:
	clear()
	GoBuildDebug.log("[GoBuild] GIZMO._redraw  called")

	var node := get_node_3d() as GoBuildMeshInstance
	if node == null:
		GoBuildDebug.log("[GoBuild] GIZMO._redraw  EARLY RETURN — node is null")
		return

	var gbm: GoBuildMesh = node.go_build_mesh
	if gbm == null or gbm.vertices.is_empty():
		GoBuildDebug.log("[GoBuild] GIZMO._redraw  EARLY RETURN — gbm null=%s  verts=%d" \
				% [str(gbm == null), gbm.vertices.size() if gbm else -1])
		return

	# Access the plugin without a type annotation — GoBuildGizmoPlugin is the
	# runtime type, but importing it here would create a circular script dependency.
	# _manual_plugin_ref is set when the gizmo was attached via Node3D.add_gizmo()
	# directly (bypassing Godot's internal pipeline which normally sets this).
	var plugin = _manual_plugin_ref if _manual_plugin_ref != null else get_plugin()
	if plugin == null:
		GoBuildDebug.log("[GoBuild] GIZMO._redraw  EARLY RETURN — plugin is null")
		return

	var sel: SelectionManager = node.selection
	GoBuildDebug.log("[GoBuild] GIZMO._redraw  mode=%d  verts=%d  faces=%d  sel_empty=%s" \
			% [sel.get_mode(), gbm.vertices.size(), gbm.faces.size(), str(sel.is_empty())])

	# Compute a uniform gizmo scale so vertex cubes and other screen-space
	# elements appear at a constant perceived size regardless of camera distance.
	# Using the node's world origin as the distance reference is a cheap
	# approximation that is close enough for per-vertex sizing.
	# Guard: if the dynamic call returns null (failed lookup) it becomes 0.0 in
	# a typed float, which would make all cubes zero-size and invisible.
	var gizmo_s: float = plugin.call("compute_world_gizmo_scale", node.global_position)
	if gizmo_s < 0.01:
		gizmo_s = 1.0   # safe fallback — method missing or returned null

	match sel.get_mode():
		SelectionManager.Mode.OBJECT:
			pass  # Mesh renders normally; no sub-element overlay needed.

		SelectionManager.Mode.VERTEX:
			_draw_context_edges(gbm, plugin.mat_edge_context)
			_draw_vertices(gbm, sel, plugin.mat_vertex_normal, plugin.mat_vertex_selected, gizmo_s)

		SelectionManager.Mode.EDGE:
			_draw_edges(gbm, sel, plugin.mat_edge_normal, plugin.mat_edge_selected)

		SelectionManager.Mode.FACE:
			_draw_context_edges(gbm, plugin.mat_edge_context)
			_draw_face_centres(gbm, sel, plugin.mat_face_normal, plugin.mat_face_fill)

	# Draw the 3-axis translate handle whenever any sub-element is selected.
	if sel.get_mode() != SelectionManager.Mode.OBJECT and not sel.is_empty():
		var centroid: Vector3 = _compute_selection_centroid(gbm, sel)
		var world_centroid: Vector3 = node.global_transform * centroid
		# Dynamic call — avoids a circular preload dependency with GoBuildGizmoPlugin.
		var s: float = plugin.call("compute_world_gizmo_scale", world_centroid)
		if s < 0.01:
			s = 1.0
		_draw_transform_handles(centroid, s, plugin)


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
## Both materials use [code]no_depth_test[/code] so cubes are always visible
## on top of the mesh geometry (the vertex positions are exactly on the surface
## and would otherwise z-fight with or be occluded by the opaque mesh faces).
##
## [param scale] is the gizmo scale factor from
## [method GoBuildGizmoPlugin.compute_world_gizmo_scale], which makes the
## cubes appear at a roughly constant screen size regardless of camera distance.
##
## Deduplicates by [member GoBuildMesh.coincident_groups] so that split vertices
## at the same 3D position (e.g. the three copies of each cube corner produced by
## [CubeGenerator]) are drawn as a single handle rather than three overlapping ones.
## A group is considered selected if [b]any[/b] of its member indices is selected.
func _draw_vertices(
		gbm: GoBuildMesh,
		sel: SelectionManager,
		mat_normal: Material,
		mat_selected: Material,
		scale: float = 1.0,
) -> void:
	var lines_normal   := PackedVector3Array()
	var lines_selected := PackedVector3Array()
	var cube_half: float = VERTEX_CUBE_HALF * scale

	# Determine whether the coincident-group map is ready.
	# When built (parallel to vertices), use it to deduplicate overlapping handles.
	# When absent (manually constructed mesh, pre-rebuild_edges), fall back to
	# one handle per raw vertex index.
	var has_groups: bool = gbm.coincident_groups.size() == gbm.vertices.size()

	# group_id → { "pos": Vector3, "selected": bool }
	# Populated in one forward pass; we only store the first position seen for
	# each group (all coincident verts share the same position by definition).
	var group_data: Dictionary = {}

	for idx: int in gbm.vertices.size():
		var group_id: int = gbm.coincident_groups[idx] if has_groups else idx
		var is_sel: bool = sel.is_vertex_selected(idx)
		if group_data.has(group_id):
			# A group is selected as soon as any member is selected.
			if is_sel and not group_data[group_id]["selected"]:
				group_data[group_id]["selected"] = true
		else:
			group_data[group_id] = { "pos": gbm.vertices[idx], "selected": is_sel }

	for entry: Dictionary in group_data.values():
		var cube := _cube_lines_at(entry["pos"], cube_half)
		if entry["selected"]:
			lines_selected.append_array(cube)
		else:
			lines_normal.append_array(cube)

	if not lines_normal.is_empty():
		add_lines(lines_normal, mat_normal)
	if not lines_selected.is_empty():
		add_lines(lines_selected, mat_selected)
	GoBuildDebug.log("[GoBuild] GIZMO._draw_vertices  n=%d  sel=%d  half=%.4f" \
			% [lines_normal.size(), lines_selected.size(), cube_half])


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
## [param s] is the gizmo scale factor from [method GoBuildGizmoPlugin.compute_world_gizmo_scale]
## so the handles appear at a constant screen size.
## Materials are accessed via untyped [method Object.get] to avoid a circular
## import dependency with [GoBuildGizmoPlugin].
func _draw_transform_handles(centroid: Vector3, s: float, plugin: EditorNode3DGizmoPlugin) -> void:
	var arr: float = ARROW_LENGTH * s
	var tip_x := centroid + Vector3(arr, 0.0, 0.0)
	var tip_y := centroid + Vector3(0.0, arr, 0.0)
	var tip_z := centroid + Vector3(0.0, 0.0, arr)

	add_lines(PackedVector3Array([centroid, tip_x]), plugin.get("mat_axis_line_x"))
	add_lines(PackedVector3Array([centroid, tip_y]), plugin.get("mat_axis_line_y"))
	add_lines(PackedVector3Array([centroid, tip_z]), plugin.get("mat_axis_line_z"))

	# Solid cone arrowheads — each cone's apex is at the tip; base reaches back CONE_HEIGHT units.
	var cone_h: float = CONE_HEIGHT * s
	var cone_r: float = _CONE_RADIUS * s
	add_mesh(_build_cone_mesh(tip_x, Vector3.RIGHT, cone_h, cone_r), plugin.get("mat_cone_x"))
	add_mesh(_build_cone_mesh(tip_y, Vector3.UP,    cone_h, cone_r), plugin.get("mat_cone_y"))
	add_mesh(_build_cone_mesh(tip_z, Vector3.BACK,  cone_h, cone_r), plugin.get("mat_cone_z"))

	# Billboard handle dots remain at the apex — kept for visual consistency.
	add_handles(PackedVector3Array([tip_x]), plugin.get("mat_axis_x"),
			PackedInt32Array([AXIS_HANDLE_OFFSET + 0]), true)
	add_handles(PackedVector3Array([tip_y]), plugin.get("mat_axis_y"),
			PackedInt32Array([AXIS_HANDLE_OFFSET + 1]), true)
	add_handles(PackedVector3Array([tip_z]), plugin.get("mat_axis_z"),
			PackedInt32Array([AXIS_HANDLE_OFFSET + 2]), true)

	_draw_rotate_rings(centroid, s, plugin)


## Build a small solid cone [ArrayMesh] with its apex at [param apex] pointing
## along [param axis_dir] in local gizmo space.
##
## [param cone_h] and [param cone_r] are the already-scaled height and base radius.
## Both the lateral surface and the base cap are triangulated so the cone looks
## solid from all viewing angles.  The material applied via
## [method EditorNode3DGizmo.add_mesh] must use CULL_DISABLED.
func _build_cone_mesh(
		apex: Vector3,
		axis_dir: Vector3,
		cone_h: float,
		cone_r: float,
) -> ArrayMesh:
	var base_center: Vector3 = apex - axis_dir * cone_h

	var raw_perp: Vector3 = axis_dir.cross(Vector3.UP)
	var perp1: Vector3
	if raw_perp.length_squared() < 0.001:
		perp1 = axis_dir.cross(Vector3.RIGHT).normalized()
	else:
		perp1 = raw_perp.normalized()
	var perp2: Vector3 = axis_dir.cross(perp1).normalized()

	var verts := PackedVector3Array()
	verts.resize(_CONE_SEGMENTS * 6)
	var vi := 0

	for i: int in _CONE_SEGMENTS:
		var a0: float = float(i)       / _CONE_SEGMENTS * TAU
		var a1: float = float(i + 1)   / _CONE_SEGMENTS * TAU
		var rim0: Vector3 = base_center + (perp1 * cos(a0) + perp2 * sin(a0)) * cone_r
		var rim1: Vector3 = base_center + (perp1 * cos(a1) + perp2 * sin(a1)) * cone_r
		verts[vi]     = apex;  verts[vi + 1] = rim0;  verts[vi + 2] = rim1
		verts[vi + 3] = base_center;  verts[vi + 4] = rim1;  verts[vi + 5] = rim0
		vi += 6

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Draw three rotation-ring overlays (one per axis) centred on [param centroid].
##
## Ring colour matches the corresponding axis material.
## The handle dot for each ring sits at the first point on the ring
## (angle = 0), which lies along the chosen tangent direction:
## - X ring (YZ plane): handle dot at [code]centroid + UP * radius[/code]
## - Y ring (XZ plane): handle dot at [code]centroid + BACK * radius[/code]
## - Z ring (XY plane): handle dot at [code]centroid + RIGHT * radius[/code]
func _draw_rotate_rings(centroid: Vector3, s: float, plugin: EditorNode3DGizmoPlugin) -> void:
	var ring_r: float = ROT_RING_RADIUS * s
	# X-axis rotation ring — in the YZ plane (tangent=UP, bitangent=BACK).
	_draw_rotate_ring(centroid, Vector3.UP, Vector3.BACK,
			ring_r, plugin.get("mat_axis_line_x"),
			ROT_HANDLE_OFFSET + 0, plugin.get("mat_axis_x"))
	# Y-axis rotation ring — in the XZ plane (tangent=BACK, bitangent=RIGHT).
	_draw_rotate_ring(centroid, Vector3.BACK, Vector3.RIGHT,
			ring_r, plugin.get("mat_axis_line_y"),
			ROT_HANDLE_OFFSET + 1, plugin.get("mat_axis_y"))
	# Z-axis rotation ring — in the XY plane (tangent=RIGHT, bitangent=UP).
	_draw_rotate_ring(centroid, Vector3.RIGHT, Vector3.UP,
			ring_r, plugin.get("mat_axis_line_z"),
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
