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
## Redraw is triggered from [code]plugin.gd[/code] via [method EditorPlugin.update_overlays]
## whenever the [SelectionManager] emits a signal.
##
## [b]Note:[/b] The plugin is accessed via the untyped [method get_plugin] call
## (no [code]GoBuildGizmoPlugin[/code] type annotation here) to avoid a circular
## script-load dependency between the two gizmo files.
@tool
class_name GoBuildGizmo
extends EditorNode3DGizmo

# Self-preload: SelectionManager is used in function parameter type annotations,
# which are resolved at compile time.  Godot's startup scan processes this file
# before selection_manager.gd alphabetically, so we force it here.
const _SEL_MGR_SCRIPT := preload("res://addons/go_build/core/selection_manager.gd")


## Rebuild all viewport overlays for the attached [GoBuildMeshInstance].
## Called by the editor when [method EditorPlugin.update_overlays] is invoked.
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
			_draw_face_centres(gbm, sel, plugin.mat_face_normal, plugin.mat_face_selected)


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


## Draw all vertices as billboard handle dots.
## Selected vertices are orange; unselected are white.
## Handle IDs equal the vertex index in [member GoBuildMesh.vertices].
func _draw_vertices(
		gbm: GoBuildMesh,
		sel: SelectionManager,
		mat_normal: Material,
		mat_selected: Material,
) -> void:
	var pts_normal   := PackedVector3Array()
	var ids_normal   := PackedInt32Array()
	var pts_selected := PackedVector3Array()
	var ids_selected := PackedInt32Array()

	for idx: int in gbm.vertices.size():
		if sel.is_vertex_selected(idx):
			pts_selected.append(gbm.vertices[idx])
			ids_selected.append(idx)
		else:
			pts_normal.append(gbm.vertices[idx])
			ids_normal.append(idx)

	if not pts_normal.is_empty():
		add_handles(pts_normal, mat_normal, ids_normal, true)
	if not pts_selected.is_empty():
		add_handles(pts_selected, mat_selected, ids_selected, true)


## Draw face-centre dots as billboard handles.
## Selected centres are orange; unselected are teal.
## Handle IDs = [code]gbm.vertices.size() + face_index[/code] to avoid collision
## with vertex handle IDs.
func _draw_face_centres(
		gbm: GoBuildMesh,
		sel: SelectionManager,
		mat_normal: Material,
		mat_selected: Material,
) -> void:
	var pts_normal   := PackedVector3Array()
	var ids_normal   := PackedInt32Array()
	var pts_selected := PackedVector3Array()
	var ids_selected := PackedInt32Array()

	# Offset face IDs so they cannot collide with vertex IDs.
	var id_offset: int = gbm.vertices.size()

	for idx: int in gbm.faces.size():
		var face: GoBuildFace = gbm.faces[idx]
		# Compute face centre as the mean of its vertex positions.
		var centre := Vector3.ZERO
		for vi: int in face.vertex_indices:
			centre += gbm.vertices[vi]
		centre /= face.vertex_indices.size()

		if sel.is_face_selected(idx):
			pts_selected.append(centre)
			ids_selected.append(id_offset + idx)
		else:
			pts_normal.append(centre)
			ids_normal.append(id_offset + idx)

	if not pts_normal.is_empty():
		add_handles(pts_normal, mat_normal, ids_normal, true)
	if not pts_selected.is_empty():
		add_handles(pts_selected, mat_selected, ids_selected, true)

