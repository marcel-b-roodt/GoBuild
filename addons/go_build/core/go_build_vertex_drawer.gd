## Vertex-mode operations drawer for the GoBuild editor panel.
##
## Hosts the Merge, Weld, and Rip buttons.
##
## Drop into any [VBoxContainer] with [method Node.add_child].  After adding:
##   - Call [method GoBuildDrawer.set_plugin] once.
##   - Call [method GoBuildDrawer.set_target] whenever the active
##     [GoBuildMeshInstance] changes.
##   - Call [method GoBuildDrawer.refresh_buttons] on selection-changed events.
@tool
class_name GoBuildVertexDrawer
extends GoBuildDrawer

# Self-preloads — dependency order.
# GoBuildDrawer already preloads SelectionManager and GoBuildMeshInstance, but
# those must be listed here too because this script is compiled independently
# and Godot's startup scan may reach it before its parent class is cached.
const _SEL_MGR_SCRIPT_V    := preload("res://addons/go_build/core/selection_manager.gd")
const _MESH_INST_SCRIPT_V  := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _DRAWER_SCRIPT       := preload("res://addons/go_build/core/go_build_drawer.gd")
const _WELD_SCRIPT         := preload("res://addons/go_build/mesh/operations/weld_operation.gd")
const _RIP_SCRIPT          := preload("res://addons/go_build/mesh/operations/rip_operation.gd")

# Buttons — exposed for tests.
var _merge_btn: Button = null
var _weld_btn:  Button = null
var _rip_btn:   Button = null


func _ready() -> void:
	_setup_drawer("Vertex")

	var grid := GridContainer.new()
	grid.columns = 2
	_content.add_child(grid)

	_merge_btn = _op_button("Merge",
		"Merge selected vertices to their centroid (M).\n"
		+ "Requires Vertex mode with \u22652 vertices selected.")
	_merge_btn.pressed.connect(_on_merge_pressed)
	grid.add_child(_merge_btn)
	_register_op(_merge_btn, _cond_vertex_merge)

	_weld_btn = _op_button("Weld",
		"Weld all vertices within 0.0001 units (Merge by Distance).\n"
		+ "Requires Vertex mode.")
	_weld_btn.pressed.connect(_on_weld_pressed)
	grid.add_child(_weld_btn)
	_register_op(_weld_btn, _cond_vertex_any)

	_rip_btn = _op_button("Rip",
		"Rip selected vertices out of unselected faces, creating an open seam (V).\n"
		+ "Requires Vertex mode with \u22651 vertex selected.")
	_rip_btn.pressed.connect(_on_rip_pressed)
	grid.add_child(_rip_btn)
	_register_op(_rip_btn, _cond_vertex_rip)


# ---------------------------------------------------------------------------
# External trigger entry points
# ---------------------------------------------------------------------------

## Equivalent to pressing the Merge button.
func trigger_merge() -> void:
	_on_merge_pressed()


## Equivalent to pressing the Weld button.
func trigger_weld() -> void:
	_on_weld_pressed()


## Equivalent to pressing the Rip button.
func trigger_rip() -> void:
	_on_rip_pressed()


# ---------------------------------------------------------------------------
# Conditions
# ---------------------------------------------------------------------------

func _cond_vertex_merge() -> bool:
	return _target != null \
			and _target.selection.get_mode() == SelectionManager.Mode.VERTEX \
			and _target.selection.get_selected_vertices().size() >= 2


func _cond_vertex_any() -> bool:
	return _target != null \
			and _target.selection.get_mode() == SelectionManager.Mode.VERTEX


func _cond_vertex_rip() -> bool:
	if _target == null or _target.go_build_mesh == null:
		return false
	if _target.selection.get_mode() != SelectionManager.Mode.VERTEX:
		return false
	var sel_verts: Array[int] = _target.selection.get_selected_vertices()
	if sel_verts.is_empty():
		return false
	var gbm: GoBuildMesh = _target.go_build_mesh
	gbm.rebuild_edges()
	for vi: int in sel_verts:
		if vi >= gbm.vertices.size():
			continue
		var adjacent: Array[int] = gbm.faces_of_vertex(vi)
		var sel_count: int = 0
		var unsel_count: int = 0
		for fi: int in adjacent:
			if _target.selection.is_face_selected(fi):
				sel_count += 1
			else:
				unsel_count += 1
		if sel_count > 0 and unsel_count > 0:
			return true
	return false


# ---------------------------------------------------------------------------
# Operation handlers
# ---------------------------------------------------------------------------

func _on_merge_pressed() -> void:
	if _target == null or _plugin == null:
		return
	if _target.selection.get_mode() != SelectionManager.Mode.VERTEX:
		return
	var sel_verts: Array[int] = _target.selection.get_selected_vertices()
	if sel_verts.size() < 2:
		return
	var to_merge: Array[int] = []
	to_merge.assign(sel_verts)
	_run_op("Merge Vertices",
			func(): WeldOperation.apply_merge(_target.go_build_mesh, to_merge))


func _on_weld_pressed() -> void:
	if _target == null or _plugin == null:
		return
	if _target.selection.get_mode() != SelectionManager.Mode.VERTEX:
		return
	_run_op("Weld Vertices",
			func(): WeldOperation.apply_weld_by_threshold(_target.go_build_mesh))


func _on_rip_pressed() -> void:
	if _target == null or _plugin == null:
		return
	if _target.selection.get_mode() != SelectionManager.Mode.VERTEX:
		return
	var sel_verts: Array[int] = _target.selection.get_selected_vertices()
	if sel_verts.is_empty():
		return
	var to_rip: Array[int] = []
	to_rip.assign(sel_verts)
	var sel_faces: Array[int] = _target.selection.get_selected_faces()
	var faces_for_rip: Array[int] = []
	if not sel_faces.is_empty():
		faces_for_rip.assign(sel_faces)
	_run_op("Rip Vertices",
			func(): RipOperation.apply_vertices(_target.go_build_mesh, to_rip, faces_for_rip),
			false)
