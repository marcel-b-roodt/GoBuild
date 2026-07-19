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

## Handle ID base for the 3-axis scale handles.
## Matches [constant GoBuildGizmoPlugin.SCALE_HANDLE_OFFSET].
const SCALE_HANDLE_OFFSET: int = 3_000_000
## Handle ID base for the 3-axis planar translate handles.
## Planes: 0=XY (normal=Z), 1=YZ (normal=X), 2=XZ (normal=Y).
## Matches [constant GoBuildGizmoPlugin.PLANE_HANDLE_OFFSET].
const PLANE_HANDLE_OFFSET: int = 4_000_000
## Handle ID for the viewport-plane (camera-space) drag handle.
## Matches [constant GoBuildGizmoPlugin.VIEW_PLANE_HANDLE_ID].
const VIEW_PLANE_HANDLE_ID: int = 5_000_000
## Handle ID for the uniform (all-axis) scale handle at the selection centroid.
## Matches [constant GoBuildGizmoPlugin.UNIFORM_SCALE_HANDLE_ID].
const UNIFORM_SCALE_HANDLE_ID: int = 6_000_000

## Length of each axis arrow in local mesh units.
## Public so [GoBuildGizmoPlugin] can compute handle screen positions for hit-testing.
## Also mirrored as [constant GoBuildGizmoPlugin.ARROW_LENGTH].
const ARROW_LENGTH: float = 0.8
## Height of the cone arrowhead along the axis direction.
## Also mirrored as [constant GoBuildGizmoPlugin.CONE_HEIGHT].
const CONE_HEIGHT: float  = 0.18
## Cone constants removed — [GoBuildGizmoPlugin] now owns _CONE_RADIUS and
## _CONE_SEGMENTS and builds the cones once in setup() as cached ArrayMesh objects.
## Half-size coefficient for the solid filled cube drawn at each vertex handle.
## This value is multiplied by the gizmo scale factor (camera-distance-dependent)
## in [method _draw_vertices] so the cubes appear at a roughly constant screen
## size regardless of zoom level.
## Calibrated at half the previous wireframe value — the solid fill reads more
## clearly at smaller sizes than the wireframe did.
##
## [b]Public[/b] so [PickingHelper] can derive a matching pick radius from the
## same value — both must stay in sync.
const VERTEX_CUBE_HALF: float = 0.03
## Half-width ratio for selected-edge ribbons (relative to VERTEX_CUBE_HALF).
## Selected edges are thicker than unselected ones for clear visual emphasis.
const _EDGE_SELECTED_RIBBON_RATIO: float = 0.3
## Half-width ratio for unselected-edge ribbons (relative to VERTEX_CUBE_HALF).
## Unselected edges are drawn thinner so they're visible but subordinate.
const _EDGE_UNSELECTED_RIBBON_RATIO: float = 0.13
## Offset of each planar-handle square's centre from the selection centroid along
## each of its two axes (local mesh units × gizmo scale).
## Must match [constant GoBuildGizmoPlugin.PLANE_INNER_OFFSET].
const PLANE_INNER_OFFSET: float = 0.25
## Rendered half-size of the planar-handle square (local mesh units × scale).
## Canonical mesh is ±1; scaled by [code]PLANE_HALF * s[/code] at draw time.
## Must match [constant GoBuildGizmoPlugin.PLANE_HALF].
const PLANE_HALF: float         = 0.10
## Rendered half-size of the scale-handle cube.
## Canonical mesh is ±1; scaled by [code]SCALE_CUBE_HALF * s[/code] at draw time.
## Must match [constant GoBuildGizmoPlugin.SCALE_CUBE_HALF].
const SCALE_CUBE_HALF: float    = 0.07
## Rendered half-size of the viewport-plane drag-handle square.
## Must match [constant GoBuildGizmoPlugin.VIEW_PLANE_HALF].
const VIEW_PLANE_HALF: float    = 0.07
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
		gizmo_s = 1.0
	# Camera forward in local space — used by edge ribbons to face the viewer.
	var cam_fwd_local: Vector3 = Vector3.BACK
	var cam: Camera3D = plugin.call("get_editor_camera")
	if cam != null:
		var cam_fwd_world: Vector3 = -cam.global_basis.z
		cam_fwd_local = (node.global_transform.affine_inverse().basis) * cam_fwd_world
		if cam_fwd_local.length_squared() < 1e-9:
			cam_fwd_local = Vector3.BACK
		else:
			cam_fwd_local = cam_fwd_local.normalized()

	match sel.get_mode():
		SelectionManager.Mode.OBJECT:
			pass  # Mesh renders normally; no sub-element overlay needed.

		SelectionManager.Mode.VERTEX:
			var edge_mat: Material = plugin.mat_edge_context_depth \
					if not plugin.xray_mode else plugin.mat_edge_context
			_draw_context_edges(gbm, edge_mat, cam_fwd_local, gizmo_s)
			var vert_norm: Material = plugin.mat_vertex_normal_depth \
					if not plugin.xray_mode else plugin.mat_vertex_normal
			_draw_vertices(gbm, sel, vert_norm, plugin.mat_vertex_selected, gizmo_s)

		SelectionManager.Mode.EDGE:
			var edge_norm: Material = plugin.mat_edge_normal_depth \
					if not plugin.xray_mode else plugin.mat_edge_normal
			_draw_edges(gbm, sel, edge_norm, plugin.mat_edge_selected,
					plugin.get("mat_edge_selected_ribbon"), gizmo_s, cam_fwd_local)

		SelectionManager.Mode.FACE:
			var edge_mat: Material = plugin.mat_edge_context_depth \
					if not plugin.xray_mode else plugin.mat_edge_context
			_draw_context_edges(gbm, edge_mat, cam_fwd_local, gizmo_s)
			_draw_face_centres(gbm, sel, plugin.mat_face_normal, plugin.mat_face_fill)

	# Normal visualiser overlay (drawn in all sub-element modes when toggled on).
	if plugin.show_face_normals:
		_draw_face_normals(gbm, plugin.mat_normal_face, gizmo_s)
	if plugin.show_vertex_normals:
		_draw_vertex_normals(gbm, plugin.mat_normal_vertex, gizmo_s)

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

## Draw all edges as thin prisms — provides spatial context in vertex / face modes.
## Half-width is [constant _EDGE_UNSELECTED_RIBBON_RATIO] × [constant VERTEX_CUBE_HALF] × scale.
func _draw_context_edges(
		gbm: GoBuildMesh,
		mat: Material,
		cam_forward: Vector3 = Vector3.FORWARD,
		scale: float = 1.0,
) -> void:
	if gbm.edges.is_empty():
		return
	var hw: float = VERTEX_CUBE_HALF * _EDGE_UNSELECTED_RIBBON_RATIO * scale
	var ribbon_verts := PackedVector3Array()
	for edge: GoBuildEdge in gbm.edges:
		var va: Vector3 = gbm.vertices[edge.vertex_a]
		var vb: Vector3 = gbm.vertices[edge.vertex_b]
		var tris: PackedVector3Array = _edge_prism_tris(va, vb, hw, cam_forward)
		if not tris.is_empty():
			ribbon_verts.append_array(tris)
	if ribbon_verts.is_empty():
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = ribbon_verts
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	add_mesh(m, mat)


## Draw all edges, colouring selected ones as orange prism quads and
## unselected ones as thinner prism quads.
##
## Selected edges are rendered as 3-face prisms (six triangles per edge)
## with half-width [code]VERTEX_CUBE_HALF * scale[/code].
## Unselected edges are drawn as thinner prisms at
## [code]VERTEX_CUBE_HALF * _EDGE_UNSELECTED_RIBBON_RATIO * scale[/code].
##
## Both use [method _edge_prism_tris] so they appear consistently thick
## from every viewing angle.
##
## [param mat_selected_ribbon] — solid orange mesh material for selected edge quads.
## When [code]null[/code] (should not happen in practice) falls back to
## [param mat_selected] via add_lines.
## [param scale] — gizmo scale from [method GoBuildGizmoPlugin.compute_world_gizmo_scale].
## [param cam_forward] — camera forward direction in local space, used to orient
## the prism faces towards the viewer.
func _draw_edges(
		gbm: GoBuildMesh,
		sel: SelectionManager,
		mat_normal: Material,
		mat_selected: Material,
		mat_selected_ribbon: Variant = null,
		scale: float = 1.0,
		cam_forward: Vector3 = Vector3.FORWARD,
) -> void:
	var lines_selected_fb   := PackedVector3Array()
	var sel_ribbon_verts    := PackedVector3Array()
	var norm_ribbon_verts   := PackedVector3Array()
	var use_ribbon: bool    = mat_selected_ribbon != null
	var hw_sel: float       = VERTEX_CUBE_HALF * _EDGE_SELECTED_RIBBON_RATIO * scale
	var hw_norm: float       = VERTEX_CUBE_HALF * _EDGE_UNSELECTED_RIBBON_RATIO * scale

	for idx: int in gbm.edges.size():
		var edge: GoBuildEdge = gbm.edges[idx]
		var va: Vector3 = gbm.vertices[edge.vertex_a]
		var vb: Vector3 = gbm.vertices[edge.vertex_b]
		if sel.is_edge_selected(idx):
			if use_ribbon:
				sel_ribbon_verts.append_array(_edge_prism_tris(va, vb, hw_sel, cam_forward))
			else:
				lines_selected_fb.append(va)
				lines_selected_fb.append(vb)
		else:
			norm_ribbon_verts.append_array(_edge_prism_tris(va, vb, hw_norm, cam_forward))

	if not norm_ribbon_verts.is_empty():
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = norm_ribbon_verts
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		add_mesh(m, mat_normal)

	if use_ribbon and not sel_ribbon_verts.is_empty():
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = sel_ribbon_verts
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		add_mesh(m, mat_selected_ribbon as Material)
	elif not lines_selected_fb.is_empty():
		add_lines(lines_selected_fb, mat_selected)


## Build the 36 triangle vertices (12 triangles, 6 faces × 2 tris) for a solid
## axis-aligned cube of half-size [param half] centred on [param pos].
##
## Used to batch multiple vertex cubes into a single [ArrayMesh] so [method _draw_vertices]
## calls [method EditorNode3DGizmo.add_mesh] exactly twice per redraw (once for
## unselected, once for selected) rather than once per vertex group.
func _solid_cube_tris_at(pos: Vector3, half: float) -> PackedVector3Array:
	var h: float = half
	return PackedVector3Array([
		# +X face
		pos + Vector3(h,-h,-h), pos + Vector3(h, h,-h), pos + Vector3(h, h, h),
		pos + Vector3(h,-h,-h), pos + Vector3(h, h, h), pos + Vector3(h,-h, h),
		# -X face
		pos + Vector3(-h,-h, h), pos + Vector3(-h, h, h), pos + Vector3(-h, h,-h),
		pos + Vector3(-h,-h, h), pos + Vector3(-h, h,-h), pos + Vector3(-h,-h,-h),
		# +Y face
		pos + Vector3(-h, h,-h), pos + Vector3(-h, h, h), pos + Vector3(h, h, h),
		pos + Vector3(-h, h,-h), pos + Vector3(h, h, h), pos + Vector3(h, h,-h),
		# -Y face
		pos + Vector3(-h,-h, h), pos + Vector3(-h,-h,-h), pos + Vector3(h,-h,-h),
		pos + Vector3(-h,-h, h), pos + Vector3(h,-h,-h), pos + Vector3(h,-h, h),
		# +Z face
		pos + Vector3(-h,-h, h), pos + Vector3(h,-h, h), pos + Vector3(h, h, h),
		pos + Vector3(-h,-h, h), pos + Vector3(h, h, h), pos + Vector3(-h, h, h),
		# -Z face
		pos + Vector3(h,-h,-h), pos + Vector3(-h,-h,-h), pos + Vector3(-h, h,-h),
		pos + Vector3(h,-h,-h), pos + Vector3(-h, h,-h), pos + Vector3(h, h,-h),
	])


## Build 18 triangle vertices (6 triangles, 3 ribbon quads) forming a 3-face
## prism along [param va]→[param vb] with world-space half-width [param hw].
##
## Three flat ribbon quads are oriented at 0°, 60°, and 120° rotations around
## the edge axis, creating a hexagonal cross-section appearance.  This looks
## more "spherical" than a single flat quad — there are always at least two
## faces visible from any viewing angle, avoiding the flat-sided look.
##
## The first ribbon is oriented towards [param cam_forward] so the most visible
## face always faces the camera.
##
## Returns an empty array when the edge is degenerate (zero length).
func _edge_prism_tris(
		va: Vector3,
		vb: Vector3,
		hw: float,
		cam_forward: Vector3 = Vector3.FORWARD,
) -> PackedVector3Array:
	var d: Vector3 = vb - va
	if d.length_squared() < 1e-9:
		return PackedVector3Array()
	d = d.normalized()
	var up: Vector3 = Vector3.UP
	if abs(d.dot(up)) > 0.9:
		up = Vector3.RIGHT
	var perp: Vector3
	if cam_forward.length_squared() > 1e-6:
		perp = d.cross(cam_forward.normalized())
		if perp.length_squared() < 1e-9:
			perp = d.cross(up).normalized()
		else:
			perp = perp.normalized()
	else:
		perp = d.cross(up).normalized()
	perp = perp.normalized() * hw
	var perp2: Vector3 = d.cross(perp).normalized() * hw
	var result := PackedVector3Array()
	var offsets: Array[Vector3] = [
		perp,
		perp * -0.5 + perp2 * 0.86602540378,   # cos(60°) = 0.5, sin(60°) ≈ 0.866
		perp * -0.5 - perp2 * 0.86602540378,
	]
	for offset: Vector3 in offsets:
		var pa: Vector3 = va + offset
		var pb: Vector3 = va - offset
		var pc: Vector3 = vb + offset
		var pd: Vector3 = vb - offset
		result.append(pa)
		result.append(pb)
		result.append(pc)
		result.append(pb)
		result.append(pd)
		result.append(pc)
	return result


## Draw all vertices as solid filled cube handles.
##
## Unselected vertices use a near-black solid cube; selected vertices use an
## orange solid cube matching the face-selection colour.  Both materials use
## [code]no_depth_test[/code] so cubes are always visible on top of the mesh
## geometry (vertex positions are exactly on the surface and would otherwise
## z-fight with or be occluded by the opaque mesh faces).
##
## All vertex cubes for a given state are batched into one [ArrayMesh] so
## [method EditorNode3DGizmo.add_mesh] is called exactly twice per redraw.
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
	var fill_normal   := PackedVector3Array()
	var fill_selected := PackedVector3Array()
	var cube_half: float = VERTEX_CUBE_HALF * scale

	# Determine whether the coincident-group map is ready.
	var has_groups: bool = gbm.coincident_groups.size() == gbm.vertices.size()

	# group_id → { "pos": Vector3, "selected": bool }
	var group_data: Dictionary = {}

	for idx: int in gbm.vertices.size():
		var group_id: int = gbm.coincident_groups[idx] if has_groups else idx
		var is_sel: bool = sel.is_vertex_selected(idx)
		if group_data.has(group_id):
			if is_sel and not group_data[group_id]["selected"]:
				group_data[group_id]["selected"] = true
		else:
			group_data[group_id] = { "pos": gbm.vertices[idx], "selected": is_sel }

	for entry: Dictionary in group_data.values():
		var cube := _solid_cube_tris_at(entry["pos"], cube_half)
		if entry["selected"]:
			fill_selected.append_array(cube)
		else:
			fill_normal.append_array(cube)

	if not fill_normal.is_empty():
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = fill_normal
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		add_mesh(m, mat_normal)
	if not fill_selected.is_empty():
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = fill_selected
		var ms := ArrayMesh.new()
		ms.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		add_mesh(ms, mat_selected)
	GoBuildDebug.log("[GoBuild] GIZMO._draw_vertices  n=%d  sel=%d  half=%.4f" \
			% [fill_normal.size(), fill_selected.size(), cube_half])


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
# Normal visualiser
# ---------------------------------------------------------------------------

## Draw face normals as lines from each face centroid along its outward normal.
## Length is scaled by [param gizmo_s] to keep a constant screen size.
func _draw_face_normals(gbm: GoBuildMesh, mat: Material, gizmo_s: float) -> void:
	if gbm.faces.is_empty():
		return
	var length: float = gizmo_s * 0.3
	var lines := PackedVector3Array()
	lines.resize(gbm.faces.size() * 2)
	var i := 0
	for face: GoBuildFace in gbm.faces:
		if face.vertex_indices.size() < 3:
			continue
		var centre := Vector3.ZERO
		for vi: int in face.vertex_indices:
			centre += gbm.vertices[vi]
		centre /= face.vertex_indices.size()
		var normal: Vector3 = gbm.compute_face_normal(face)
		lines[i]     = centre
		lines[i + 1] = centre + normal * length
		i += 2
	if i > 0:
		lines = lines.slice(0, i)
		add_lines(lines, mat)


## Draw vertex normals (averaged from adjacent face normals) as lines from each
## vertex along its averaged normal direction.  Length is scaled by
## [param gizmo_s] to keep a constant screen size.
func _draw_vertex_normals(gbm: GoBuildMesh, mat: Material, gizmo_s: float) -> void:
	if gbm.vertices.is_empty() or gbm.faces.is_empty():
		return
	var length: float = gizmo_s * 0.25
	# Pre-compute face normals.
	var face_normals: Array[Vector3] = []
	face_normals.resize(gbm.faces.size())
	for fi: int in gbm.faces.size():
		face_normals[fi] = gbm.compute_face_normal(gbm.faces[fi])
	# Accumulate per-vertex normal (area-weighted average).
	var vert_normals: PackedVector3Array = []
	vert_normals.resize(gbm.vertices.size())
	var lines := PackedVector3Array()
	for vi: int in gbm.vertices.size():
		var n := Vector3.ZERO
		for fi: int in gbm.faces_of_vertex(vi):
			n += face_normals[fi]
		if n.length_squared() > 1e-8:
			n = n.normalized()
			lines.append(gbm.vertices[vi])
			lines.append(gbm.vertices[vi] + n * length)
	if not lines.is_empty():
		add_lines(lines, mat)


# ---------------------------------------------------------------------------
# Transform handle helpers
# ---------------------------------------------------------------------------

## Compute the mean position of all vertices implied by the current selection.
func _compute_selection_centroid(gbm: GoBuildMesh, sel: SelectionManager) -> Vector3:
	var sum := Vector3.ZERO
	var count := 0
	var vcount: int = gbm.vertices.size()
	match sel.get_mode():
		SelectionManager.Mode.VERTEX:
			for idx: int in sel.get_selected_vertices():
				if idx >= 0 and idx < vcount:
					sum += gbm.vertices[idx]
					count += 1
		SelectionManager.Mode.EDGE:
			for eidx: int in sel.get_selected_edges():
				if eidx < 0 or eidx >= gbm.edges.size():
					continue
				var edge: GoBuildEdge = gbm.edges[eidx]
				if edge.vertex_a >= 0 and edge.vertex_a < vcount:
					sum += gbm.vertices[edge.vertex_a]
					count += 1
				if edge.vertex_b >= 0 and edge.vertex_b < vcount:
					sum += gbm.vertices[edge.vertex_b]
					count += 1
		SelectionManager.Mode.FACE:
			for fidx: int in sel.get_selected_faces():
				if fidx < 0 or fidx >= gbm.faces.size():
					continue
				for vidx: int in gbm.faces[fidx].vertex_indices:
					if vidx >= 0 and vidx < vcount:
						sum += gbm.vertices[vidx]
						count += 1
	return sum / count if count > 0 else Vector3.ZERO


## Dispatch transform handle drawing based on [member GoBuildGizmoPlugin.transform_mode].
##
## - TRANSLATE (0): axis arrows + planar squares + viewport-plane square.
## - ROTATE    (1): rotation rings only.
## - SCALE     (2): axis arrows with cube tips.
##
## The mode is read via [method Object.get] to avoid a circular preload dependency
## with [GoBuildGizmoPlugin].
func _draw_transform_handles(centroid: Vector3, s: float, plugin: EditorNode3DGizmoPlugin) -> void:
	var tmode: int = int(plugin.get("transform_mode"))
	var tspace: int = int(plugin.get("transform_space"))
	var world_basis: Basis = Basis()
	if tspace == 1 and get_node_3d() != null:
		world_basis = get_node_3d().global_transform.basis.inverse()
	if tmode == 1:   # GoBuildGizmoPlugin.TransformMode.ROTATE
		_draw_rotate_rings(centroid, s, plugin, world_basis)
		return
	if tmode == 2:   # GoBuildGizmoPlugin.TransformMode.SCALE
		_draw_scale_handles(centroid, s, plugin, world_basis)
		return
	# TRANSLATE (default = 0)
	_draw_translate_handles(centroid, s, plugin, world_basis)
	_draw_plane_handles(centroid, s, plugin, world_basis)
	_draw_viewport_plane_handle(centroid, s, plugin)


## Draw the 3-axis translate arrow widget (shafts + cone arrowheads + billboard dots).
## Extracted from the old [method _draw_transform_handles] to allow mode dispatch.
func _draw_translate_handles(
		centroid: Vector3, s: float, plugin: EditorNode3DGizmoPlugin,
		world_basis: Basis = Basis(),
) -> void:
	var arr: float = ARROW_LENGTH * s
	var axis_x := world_basis * Vector3.RIGHT
	var axis_y := world_basis * Vector3.UP
	var axis_z := world_basis * Vector3.BACK
	var tip_x := centroid + axis_x * arr
	var tip_y := centroid + axis_y * arr
	var tip_z := centroid + axis_z * arr

	# Resolve hover state.
	var hov: int        = int(plugin.get("_hovered_handle_id"))
	var hover_line      = plugin.get("mat_handle_hover_line")
	var hover_dot       = plugin.get("mat_handle_hover_dot")
	var hover_cone      = plugin.get("mat_handle_hover_cone")

	# ── Axis shafts ──────────────────────────────────────────────────────────
	add_lines(PackedVector3Array([centroid, tip_x]),
			hover_line if hov == AXIS_HANDLE_OFFSET + 0 else plugin.get("mat_axis_line_x"))
	add_lines(PackedVector3Array([centroid, tip_y]),
			hover_line if hov == AXIS_HANDLE_OFFSET + 1 else plugin.get("mat_axis_line_y"))
	add_lines(PackedVector3Array([centroid, tip_z]),
			hover_line if hov == AXIS_HANDLE_OFFSET + 2 else plugin.get("mat_axis_line_z"))

	# ── Cone arrowheads ───────────────────────────────────────────────────────
	var basis_s := Basis().scaled(Vector3.ONE * s)
	var off: float = (ARROW_LENGTH - CONE_HEIGHT) * s
	var cone_basis_x := basis_s
	var cone_basis_y := basis_s
	var cone_basis_z := basis_s
	if not world_basis.is_equal_approx(Basis()):
		cone_basis_x = world_basis * basis_s
		cone_basis_y = world_basis * basis_s
		cone_basis_z = world_basis * basis_s
	add_mesh(plugin.get("cone_mesh_x"),
			hover_cone if hov == AXIS_HANDLE_OFFSET + 0 else plugin.get("mat_cone_x"),
			Transform3D(cone_basis_x, centroid + axis_x * off))
	add_mesh(plugin.get("cone_mesh_y"),
			hover_cone if hov == AXIS_HANDLE_OFFSET + 1 else plugin.get("mat_cone_y"),
			Transform3D(cone_basis_y, centroid + axis_y * off))
	add_mesh(plugin.get("cone_mesh_z"),
			hover_cone if hov == AXIS_HANDLE_OFFSET + 2 else plugin.get("mat_cone_z"),
			Transform3D(cone_basis_z, centroid + axis_z * off))

	# ── Billboard handle dots at each tip ─────────────────────────────────────
	add_handles(PackedVector3Array([tip_x]),
			hover_dot if hov == AXIS_HANDLE_OFFSET + 0 else plugin.get("mat_axis_x"),
			PackedInt32Array([AXIS_HANDLE_OFFSET + 0]), true)
	add_handles(PackedVector3Array([tip_y]),
			hover_dot if hov == AXIS_HANDLE_OFFSET + 1 else plugin.get("mat_axis_y"),
			PackedInt32Array([AXIS_HANDLE_OFFSET + 1]), true)
	add_handles(PackedVector3Array([tip_z]),
			hover_dot if hov == AXIS_HANDLE_OFFSET + 2 else plugin.get("mat_axis_z"),
			PackedInt32Array([AXIS_HANDLE_OFFSET + 2]), true)


## Draw three planar drag-handle squares in the translate gizmo.
##
## Each square sits at [code]centroid + (u_hat + v_hat) * PLANE_INNER_OFFSET * s[/code]
## and has a half-size of [code]PLANE_HALF * s[/code].  Colour matches the
## excluded-axis convention (XY=blue/Z, YZ=red/X, XZ=green/Y).
## A billboard handle dot is registered at each centre for picking.
func _draw_plane_handles(
		centroid: Vector3, s: float, plugin: EditorNode3DGizmoPlugin,
		world_basis: Basis = Basis(),
) -> void:
	var inner: float  = PLANE_INNER_OFFSET * s
	var hov: int      = int(plugin.get("_hovered_handle_id"))
	var hover_mat     = plugin.get("mat_handle_hover_cone")
	var basis_s       = Basis().scaled(Vector3.ONE * PLANE_HALF * s)
	var axis_x := world_basis * Vector3.RIGHT
	var axis_y := world_basis * Vector3.UP
	var axis_z := world_basis * Vector3.BACK

	var plane_basis: Basis = world_basis * basis_s

	# XY plane (normal=Z, colour=blue): square in XY at (inner, inner, 0)
	var cxy := centroid + (axis_x + axis_y) * inner
	add_mesh(plugin.get("plane_quad_mesh_xy"),
			hover_mat if hov == PLANE_HANDLE_OFFSET + 0 else plugin.get("mat_plane_z"),
			Transform3D(plane_basis, cxy))
	add_handles(PackedVector3Array([cxy]),
			hover_mat if hov == PLANE_HANDLE_OFFSET + 0 else plugin.get("mat_axis_z"),
			PackedInt32Array([PLANE_HANDLE_OFFSET + 0]), true)

	# YZ plane (normal=X, colour=red): square in YZ at (0, inner, inner)
	var cyz := centroid + (axis_y + axis_z) * inner
	add_mesh(plugin.get("plane_quad_mesh_yz"),
			hover_mat if hov == PLANE_HANDLE_OFFSET + 1 else plugin.get("mat_plane_x"),
			Transform3D(plane_basis, cyz))
	add_handles(PackedVector3Array([cyz]),
			hover_mat if hov == PLANE_HANDLE_OFFSET + 1 else plugin.get("mat_axis_x"),
			PackedInt32Array([PLANE_HANDLE_OFFSET + 1]), true)

	# XZ plane (normal=Y, colour=green): square in XZ at (inner, 0, inner)
	var cxz := centroid + (axis_x + axis_z) * inner
	add_mesh(plugin.get("plane_quad_mesh_xz"),
			hover_mat if hov == PLANE_HANDLE_OFFSET + 2 else plugin.get("mat_plane_y"),
			Transform3D(plane_basis, cxz))
	add_handles(PackedVector3Array([cxz]),
			hover_mat if hov == PLANE_HANDLE_OFFSET + 2 else plugin.get("mat_axis_y"),
			PackedInt32Array([PLANE_HANDLE_OFFSET + 2]), true)


## Draw the viewport-plane drag handle — a small white/grey square at the centroid.
## Dragging this handle moves the selection freely along the plane facing the camera.
func _draw_viewport_plane_handle(
		centroid: Vector3, s: float, plugin: EditorNode3DGizmoPlugin,
) -> void:
	var hov: int  = int(plugin.get("_hovered_handle_id"))
	var hover_mat = plugin.get("mat_handle_hover_cone")
	var basis_s   = Basis().scaled(Vector3.ONE * VIEW_PLANE_HALF * s)
	# Use the XY-plane quad mesh (oriented in local XY; acceptable approximation).
	add_mesh(plugin.get("plane_quad_mesh_xy"),
			hover_mat if hov == VIEW_PLANE_HANDLE_ID else plugin.get("mat_view_plane"),
			Transform3D(basis_s, centroid))
	add_handles(PackedVector3Array([centroid]),
			hover_mat if hov == VIEW_PLANE_HANDLE_ID else plugin.get("mat_view_plane"),
			PackedInt32Array([VIEW_PLANE_HANDLE_ID]), true)


## Draw the 3-axis scale widget: axis shafts + solid cube tips.
func _draw_scale_handles(
		centroid: Vector3, s: float, plugin: EditorNode3DGizmoPlugin,
		world_basis: Basis = Basis(),
) -> void:
	var arr: float = ARROW_LENGTH * s
	var axis_x := world_basis * Vector3.RIGHT
	var axis_y := world_basis * Vector3.UP
	var axis_z := world_basis * Vector3.BACK
	var tip_x := centroid + axis_x * arr
	var tip_y := centroid + axis_y * arr
	var tip_z := centroid + axis_z * arr

	var hov: int        = int(plugin.get("_hovered_handle_id"))
	var hover_line      = plugin.get("mat_handle_hover_line")
	var hover_dot       = plugin.get("mat_handle_hover_dot")
	var hover_cube      = plugin.get("mat_handle_hover_cone")

	# Axis shafts
	add_lines(PackedVector3Array([centroid, tip_x]),
			hover_line if hov == SCALE_HANDLE_OFFSET + 0 else plugin.get("mat_axis_line_x"))
	add_lines(PackedVector3Array([centroid, tip_y]),
			hover_line if hov == SCALE_HANDLE_OFFSET + 1 else plugin.get("mat_axis_line_y"))
	add_lines(PackedVector3Array([centroid, tip_z]),
			hover_line if hov == SCALE_HANDLE_OFFSET + 2 else plugin.get("mat_axis_line_z"))

	# Scale cube tips — small solid cubes at the shaft ends.
	var basis_s = Basis().scaled(Vector3.ONE * SCALE_CUBE_HALF * s)
	var scale_basis: Basis = world_basis * basis_s
	add_mesh(plugin.get("scale_cube_mesh"),
			hover_cube if hov == SCALE_HANDLE_OFFSET + 0 else plugin.get("mat_cone_x"),
			Transform3D(scale_basis, tip_x))
	add_mesh(plugin.get("scale_cube_mesh"),
			hover_cube if hov == SCALE_HANDLE_OFFSET + 1 else plugin.get("mat_cone_y"),
			Transform3D(scale_basis, tip_y))
	add_mesh(plugin.get("scale_cube_mesh"),
			hover_cube if hov == SCALE_HANDLE_OFFSET + 2 else plugin.get("mat_cone_z"),
			Transform3D(scale_basis, tip_z))

	# Billboard handle dots for picking
	add_handles(PackedVector3Array([tip_x]),
			hover_dot if hov == SCALE_HANDLE_OFFSET + 0 else plugin.get("mat_axis_x"),
			PackedInt32Array([SCALE_HANDLE_OFFSET + 0]), true)
	add_handles(PackedVector3Array([tip_y]),
			hover_dot if hov == SCALE_HANDLE_OFFSET + 1 else plugin.get("mat_axis_y"),
			PackedInt32Array([SCALE_HANDLE_OFFSET + 1]), true)
	add_handles(PackedVector3Array([tip_z]),
			hover_dot if hov == SCALE_HANDLE_OFFSET + 2 else plugin.get("mat_axis_z"),
			PackedInt32Array([SCALE_HANDLE_OFFSET + 2]), true)

	# Uniform scale handle — white/grey square at centroid, scales all 3 axes equally.
	var basis_c := Basis().scaled(Vector3.ONE * VIEW_PLANE_HALF * s)
	add_mesh(plugin.get("plane_quad_mesh_xy"),
			hover_cube if hov == UNIFORM_SCALE_HANDLE_ID else plugin.get("mat_view_plane"),
			Transform3D(basis_c, centroid))
	add_handles(PackedVector3Array([centroid]),
			hover_cube if hov == UNIFORM_SCALE_HANDLE_ID else plugin.get("mat_view_plane"),
			PackedInt32Array([UNIFORM_SCALE_HANDLE_ID]), true)




## Draw three rotation-ring overlays (one per axis) centred on [param centroid].
##
## Ring colour matches the corresponding axis material, or the hover highlight
## material when [member GoBuildGizmoPlugin._hovered_handle_id] matches the ring ID.
## The handle dot for each ring sits at the first point on the ring
## (angle = 0), which lies along the chosen tangent direction:
## - X ring (YZ plane): handle dot at [code]centroid + UP * radius[/code]
## - Y ring (XZ plane): handle dot at [code]centroid + BACK * radius[/code]
## - Z ring (XY plane): handle dot at [code]centroid + RIGHT * radius[/code]
func _draw_rotate_rings(
		centroid: Vector3, s: float, plugin: EditorNode3DGizmoPlugin,
		world_basis: Basis = Basis(),
) -> void:
	var ring_r: float = ROT_RING_RADIUS * s
	var hov: int      = int(plugin.get("_hovered_handle_id"))
	var hover_line    = plugin.get("mat_handle_hover_line")
	var hover_dot     = plugin.get("mat_handle_hover_dot")

	var up := world_basis * Vector3.UP
	var back := world_basis * Vector3.BACK
	var right := world_basis * Vector3.RIGHT

	# X-axis rotation ring — in the YZ plane (tangent=UP, bitangent=BACK).
	_draw_rotate_ring(centroid, up, back, ring_r,
			hover_line if hov == ROT_HANDLE_OFFSET + 0 else plugin.get("mat_axis_line_x"),
			ROT_HANDLE_OFFSET + 0,
			hover_dot  if hov == ROT_HANDLE_OFFSET + 0 else plugin.get("mat_axis_x"))
	# Y-axis rotation ring — in the XZ plane (tangent=BACK, bitangent=RIGHT).
	_draw_rotate_ring(centroid, back, right, ring_r,
			hover_line if hov == ROT_HANDLE_OFFSET + 1 else plugin.get("mat_axis_line_y"),
			ROT_HANDLE_OFFSET + 1,
			hover_dot  if hov == ROT_HANDLE_OFFSET + 1 else plugin.get("mat_axis_y"))
	# Z-axis rotation ring — in the XY plane (tangent=RIGHT, bitangent=UP).
	_draw_rotate_ring(centroid, right, up, ring_r,
			hover_line if hov == ROT_HANDLE_OFFSET + 2 else plugin.get("mat_axis_line_z"),
			ROT_HANDLE_OFFSET + 2,
			hover_dot  if hov == ROT_HANDLE_OFFSET + 2 else plugin.get("mat_axis_z"))


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
