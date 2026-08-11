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
const _DISSOLVE_SCRIPT_V  := preload("res://addons/go_build/mesh/operations/dissolve_operation.gd")
const _PARAM_PREVIEW_SCRIPT_V := preload("res://addons/go_build/core/go_build_param_preview.gd")

# Buttons — exposed for tests.
var _merge_btn: Button = null
var _weld_btn:  Button = null
var _rip_btn:   Button = null
var _dissolve_btn: Button = null


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
		"Rip selected vertices, creating an open seam, then drag to move (V).\n"
		+ "Requires Vertex mode with \u22651 vertex that shares faces with unselected geometry.")
	_rip_btn.pressed.connect(_on_rip_pressed)
	grid.add_child(_rip_btn)
	_register_op(_rip_btn, _cond_vertex_rip)

	_dissolve_btn = _op_button("Dissolve",
		"Dissolve selected vertices, merging adjacent faces to fill the gap.\n"
		+ "Requires Vertex mode with \u22651 vertex selected.")
	_dissolve_btn.pressed.connect(_on_dissolve_pressed)
	grid.add_child(_dissolve_btn)
	_register_op(_dissolve_btn, _cond_vertex_any)


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


## Equivalent to pressing the Dissolve button.
func trigger_dissolve() -> void:
	_on_dissolve_pressed()


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
		if gbm.faces_of_vertex(vi).size() > 0:
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

	var gbm: GoBuildMesh = _target.go_build_mesh

	var rip_faces: Array[int] = []
	if faces_for_rip.is_empty():
		gbm.rebuild_edges()
		for vi: int in to_rip:
			for fi: int in gbm.faces_of_vertex(vi):
				rip_faces.append(fi)
	else:
		rip_faces.assign(faces_for_rip)

	var direction: Vector3 = RipOperation.compute_rip_direction(gbm, rip_faces)
	GoBuildDebug.log("[RipVertex] to_rip=%s faces_for_rip=%s direction=%s rip_faces=%s" \
			% [str(to_rip), str(faces_for_rip), str(direction), str(rip_faces)])
	var world_direction: Vector3 = _target.global_transform.basis * direction
	direction = direction.normalized()

	var screen_dir: Vector2 = Vector2(1.0, 0.0)
	var sv: SubViewport = EditorInterface.get_editor_viewport_3d(0)
	if sv != null:
		var cam: Camera3D = sv.get_camera_3d()
		if cam != null:
			var centroid: Vector3 = Vector3.ZERO
			var vcount: int = 0
			for vi: int in to_rip:
				if vi < 0 or vi >= gbm.vertices.size():
					continue
				centroid += gbm.vertices[vi]
				vcount += 1
			if vcount > 0:
				centroid /= vcount
			var world_pos: Vector3 = _target.global_transform * centroid
			var center_screen: Vector2 = cam.unproject_position(world_pos)
			var tip_screen: Vector2 = cam.unproject_position(world_pos + world_direction)
			var dir: Vector2 = tip_screen - center_screen
			if dir.length() > 1.0:
				screen_dir = dir.normalized()

	var preview := GoBuildParamPreview.new()
	preview.action_name = "Rip Vertex"
	preview.param_label = "Distance"
	preview.param_start = 0.5
	preview.param_min   = -100.0
	preview.param_max   = 100.0
	preview.radial      = false
	preview.snap_step   = 0.1
	preview.screen_direction = screen_dir
	var target_ref: GoBuildMeshInstance = _target
	var last_ripped_verts: Array[int] = []
	preview.apply_fn    = func(p: float) -> void:
		last_ripped_verts.clear()
		var result: Array[int] = RipOperation.apply_vertex_drag(
				_target.go_build_mesh, to_rip, faces_for_rip, direction, p)
		last_ripped_verts.assign(result)
	preview.post_commit_fn = func() -> void:
		if target_ref == null or not is_instance_valid(target_ref):
			return
		GoBuildDebug.log("[RipVertex] post_commit_fn: last_ripped=%s" % str(last_ripped_verts))
		if last_ripped_verts.is_empty():
			return
		var ripped_verts: Array[int] = []
		ripped_verts.assign(last_ripped_verts)
		var timer: SceneTreeTimer = target_ref.get_tree().create_timer(0.0)
		timer.timeout.connect(func() -> void:
			if target_ref == null or not is_instance_valid(target_ref):
				return
			target_ref.selection.set_selected_vertices(ripped_verts)
			target_ref.update_gizmos()
		)
	_plugin.call("begin_param_preview", preview)


func _on_dissolve_pressed() -> void:
	if _target == null or _plugin == null:
		return
	if _target.selection.get_mode() != SelectionManager.Mode.VERTEX:
		return
	var sel_verts: Array[int] = _target.selection.get_selected_vertices()
	if sel_verts.is_empty():
		return
	var to_dissolve: Array[int] = []
	to_dissolve.assign(sel_verts)
	_run_op("Dissolve Vertices",
			func(): DissolveOperation.dissolve_vertices(_target.go_build_mesh, to_dissolve))
