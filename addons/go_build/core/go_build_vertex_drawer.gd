## Vertex-mode operations drawer for the GoBuild editor panel.
##
## Hosts the Merge and Weld buttons.
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

# Buttons — exposed for tests.
var _merge_btn: Button = null
var _weld_btn:  Button = null


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
		"Merge all vertices within 0.0001 units (Merge by Distance).\n"
		+ "Requires Vertex mode.")
	_weld_btn.pressed.connect(_on_weld_pressed)
	grid.add_child(_weld_btn)
	_register_op(_weld_btn, _cond_vertex_any)


# ---------------------------------------------------------------------------
# External trigger entry points
# ---------------------------------------------------------------------------

## Equivalent to pressing the Merge button.
func trigger_merge() -> void:
	_on_merge_pressed()


## Equivalent to pressing the Weld button.
func trigger_weld() -> void:
	_on_weld_pressed()


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
