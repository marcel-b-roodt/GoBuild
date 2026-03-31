## Tracks the active edit mode and the currently selected mesh elements.
##
## Lives on [GoBuildMeshInstance] and is shared with the gizmo and panel so
## every component observes the same selection state.
##
## All index values refer to the corresponding arrays in the owning mesh's
## [GoBuildMesh]: [member GoBuildMesh.vertices], [member GoBuildMesh.edges],
## [member GoBuildMesh.faces].
class_name SelectionManager
extends RefCounted

## Emitted when [method set_mode] changes the active mode.
signal mode_changed(new_mode: Mode)

## Emitted after any mutation to the selected-element sets.
signal selection_changed()

## Available editing modes.
enum Mode {
	OBJECT = 0, ## Whole-object selection; no sub-element picking.
	VERTEX = 1, ## Individual vertex selection.
	EDGE   = 2, ## Individual edge selection.
	FACE   = 3, ## Individual face selection.
}

## The active editing mode. Change via [method set_mode].
var mode: Mode = Mode.OBJECT:
	get:
		return _mode

var _mode: Mode = Mode.OBJECT

var _selected_vertices: Array[int] = []
var _selected_edges:    Array[int] = []
var _selected_faces:    Array[int] = []


# ---------------------------------------------------------------------------
# Mode
# ---------------------------------------------------------------------------

## Switch to [param new_mode] and clear the selection.
## No-op if already in the requested mode.
func set_mode(new_mode: Mode) -> void:
	GoBuildDebug.log("[GoBuild] SEL.set_mode  old=%d  new=%d  noop=%s" \
			% [_mode, new_mode, str(_mode == new_mode)])
	if _mode == new_mode:
		return
	_mode = new_mode
	_selected_vertices.clear()
	_selected_edges.clear()
	_selected_faces.clear()
	mode_changed.emit(_mode)
	selection_changed.emit()


## Returns the active [enum Mode].
func get_mode() -> Mode:
	return _mode


# ---------------------------------------------------------------------------
# Vertex selection
# ---------------------------------------------------------------------------

## Add [param index] to the vertex selection. No-op if already selected.
func select_vertex(index: int) -> void:
	if _selected_vertices.has(index):
		return
	_selected_vertices.append(index)
	selection_changed.emit()


## Remove [param index] from the vertex selection. No-op if not selected.
func deselect_vertex(index: int) -> void:
	var i: int = _selected_vertices.find(index)
	if i == -1:
		return
	_selected_vertices.remove_at(i)
	selection_changed.emit()


## Toggle the vertex at [param index] in / out of the selection.
func toggle_vertex(index: int) -> void:
	if _selected_vertices.has(index):
		deselect_vertex(index)
	else:
		select_vertex(index)


## Returns [code]true[/code] if vertex [param index] is currently selected.
func is_vertex_selected(index: int) -> bool:
	return _selected_vertices.has(index)


## Returns a copy of the selected vertex indices.
func get_selected_vertices() -> Array[int]:
	var out: Array[int] = []
	out.assign(_selected_vertices)
	return out


# ---------------------------------------------------------------------------
# Edge selection
# ---------------------------------------------------------------------------

## Add [param index] to the edge selection. No-op if already selected.
func select_edge(index: int) -> void:
	if _selected_edges.has(index):
		return
	_selected_edges.append(index)
	selection_changed.emit()


## Remove [param index] from the edge selection. No-op if not selected.
func deselect_edge(index: int) -> void:
	var i: int = _selected_edges.find(index)
	if i == -1:
		return
	_selected_edges.remove_at(i)
	selection_changed.emit()


## Toggle the edge at [param index] in / out of the selection.
func toggle_edge(index: int) -> void:
	if _selected_edges.has(index):
		deselect_edge(index)
	else:
		select_edge(index)


## Returns [code]true[/code] if edge [param index] is currently selected.
func is_edge_selected(index: int) -> bool:
	return _selected_edges.has(index)


## Returns a copy of the selected edge indices.
func get_selected_edges() -> Array[int]:
	var out: Array[int] = []
	out.assign(_selected_edges)
	return out


# ---------------------------------------------------------------------------
# Face selection
# ---------------------------------------------------------------------------

## Add [param index] to the face selection. No-op if already selected.
func select_face(index: int) -> void:
	if _selected_faces.has(index):
		return
	_selected_faces.append(index)
	selection_changed.emit()


## Remove [param index] from the face selection. No-op if not selected.
func deselect_face(index: int) -> void:
	var i: int = _selected_faces.find(index)
	if i == -1:
		return
	_selected_faces.remove_at(i)
	selection_changed.emit()


## Toggle the face at [param index] in / out of the selection.
func toggle_face(index: int) -> void:
	if _selected_faces.has(index):
		deselect_face(index)
	else:
		select_face(index)


## Returns [code]true[/code] if face [param index] is currently selected.
func is_face_selected(index: int) -> bool:
	return _selected_faces.has(index)


## Returns a copy of the selected face indices.
func get_selected_faces() -> Array[int]:
	var out: Array[int] = []
	out.assign(_selected_faces)
	return out


# ---------------------------------------------------------------------------
# Bulk helpers
# ---------------------------------------------------------------------------

## Clear all selected elements (without changing mode).
func clear() -> void:
	_selected_vertices.clear()
	_selected_edges.clear()
	_selected_faces.clear()
	selection_changed.emit()


## Returns [code]true[/code] if nothing is selected in any element set.
func is_empty() -> bool:
	return (
		_selected_vertices.is_empty()
		and _selected_edges.is_empty()
		and _selected_faces.is_empty()
	)


## Replace the current vertex selection with [param indices] (bulk assign).
func set_selected_vertices(indices: Array[int]) -> void:
	_selected_vertices.clear()
	_selected_vertices.assign(indices)
	selection_changed.emit()


## Replace the current edge selection with [param indices] (bulk assign).
func set_selected_edges(indices: Array[int]) -> void:
	_selected_edges.clear()
	_selected_edges.assign(indices)
	selection_changed.emit()


## Replace the current face selection with [param indices] (bulk assign).
func set_selected_faces(indices: Array[int]) -> void:
	_selected_faces.clear()
	_selected_faces.assign(indices)
	selection_changed.emit()


