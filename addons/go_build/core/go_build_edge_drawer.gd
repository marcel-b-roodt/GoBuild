## Edge-mode operations drawer for the GoBuild editor panel.
##
## Hosts Extrude, Bevel, Bridge/Fill, Loop Cut, Hard, Soft, and Rip buttons.
##
## Drop into any [VBoxContainer] with [method Node.add_child].  After adding:
##   - Call [method GoBuildDrawer.set_plugin] once.
##   - Call [method GoBuildDrawer.set_target] whenever the active
##     [GoBuildMeshInstance] changes.
##   - Call [method GoBuildDrawer.refresh_buttons] on selection-changed events.
@tool
class_name GoBuildEdgeDrawer
extends GoBuildDrawer

# Self-preloads — dependency order.
const _SEL_MGR_SCRIPT_E       := preload("res://addons/go_build/core/selection_manager.gd")
const _MESH_INST_SCRIPT_E     := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _DRAWER_SCRIPT_E        := preload("res://addons/go_build/core/go_build_drawer.gd")
const _MESH_SCRIPT_E          := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _EDGE_SCRIPT_E          := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _PARAM_PREVIEW_SCRIPT_E := preload("res://addons/go_build/core/go_build_param_preview.gd")
const _EDGE_EXTRUDE_SCRIPT_E  := \
		preload("res://addons/go_build/mesh/operations/edge_extrude_operation.gd")
const _BEVEL_SCRIPT_E         := \
		preload("res://addons/go_build/mesh/operations/bevel_operation.gd")
const _BRIDGE_SCRIPT_E        := \
		preload("res://addons/go_build/mesh/operations/bridge_operation.gd")
const _LOOP_CUT_SCRIPT_E      := \
		preload("res://addons/go_build/mesh/operations/loop_cut_operation.gd")
const _HARD_EDGE_SCRIPT_E     := \
		preload("res://addons/go_build/mesh/operations/hard_edge_operation.gd")
const _RIP_SCRIPT_E            := \
		preload("res://addons/go_build/mesh/operations/rip_operation.gd")
const _DISSOLVE_SCRIPT_E      := \
		preload("res://addons/go_build/mesh/operations/dissolve_operation.gd")

const _EDGE_EXTRUDE_DEFAULT_WIDTH: float = 0.5
const _BEVEL_DEFAULT_WIDTH: float = 0.01

# Buttons — exposed for tests.
var _extrude_edge_btn: Button = null
var _bevel_btn:        Button = null
var _bridge_btn:       Button = null
var _loop_cut_btn:     Button = null
var _hard_edge_btn:    Button = null
var _soft_edge_btn:    Button = null
var _rip_btn:          Button = null
var _dissolve_btn:     Button = null


func _ready() -> void:
	_setup_drawer("Edge")

	var grid := GridContainer.new()
	grid.columns = 2
	_content.add_child(grid)

	_extrude_edge_btn = _op_button("Extrude",
		"Extrude selected boundary edge(s) into new quad faces (Shift+drag).\n"
		+ "Requires Edge mode with \u22651 boundary edge selected.")
	_extrude_edge_btn.pressed.connect(_on_extrude_edge_pressed)
	grid.add_child(_extrude_edge_btn)
	_register_op(_extrude_edge_btn, _cond_edge_any)

	_bevel_btn = _op_button("Bevel",
		"Bevel selected edge(s) at 0.01 units width.\n"
		+ "Requires Edge mode with \u22651 edge selected.")
	_bevel_btn.pressed.connect(_on_bevel_pressed)
	grid.add_child(_bevel_btn)
	_register_op(_bevel_btn, _cond_edge_any)

	_bridge_btn = _op_button("Bridge/Fill",
		"Bridge two boundary edge loops with a quad strip, or fill a closed\n"
		+ "boundary loop with a single face (F). Auto-detects from topology.\n"
		+ "Requires Edge mode with \u22652 boundary edges selected.")
	_bridge_btn.pressed.connect(_on_bridge_pressed)
	grid.add_child(_bridge_btn)
	_register_op(_bridge_btn, _cond_edge_bridge)

	_loop_cut_btn = _op_button("Loop Cut",
		"Insert an edge loop through a quad ring at the midpoint of the\n"
		+ "selected edge(s). Requires Edge mode with \u22651 edge selected.")
	_loop_cut_btn.pressed.connect(_on_loop_cut_pressed)
	grid.add_child(_loop_cut_btn)
	_register_op(_loop_cut_btn, _cond_edge_any)

	_hard_edge_btn = _op_button("Hard",
		"Mark selected edge(s) as hard: adjacent faces will not average normals\n"
		+ "across the edge even if they share the same smooth group.\n"
		+ "Requires Edge mode with \u22651 edge selected.")
	_hard_edge_btn.pressed.connect(_on_hard_edge_pressed)
	grid.add_child(_hard_edge_btn)
	_register_op(_hard_edge_btn, _cond_edge_any)

	_soft_edge_btn = _op_button("Soft",
		"Clear the hard-edge flag on selected edge(s): adjacent faces with the\n"
		+ "same smooth group will resume averaging normals.\n"
		+ "Requires Edge mode with \u22651 edge selected.")
	_soft_edge_btn.pressed.connect(_on_soft_edge_pressed)
	grid.add_child(_soft_edge_btn)
	_register_op(_soft_edge_btn, _cond_edge_any)

	_rip_btn = _op_button("Rip",
		"Rip selected edges out of unselected faces, creating an open seam (V).\n"
		+ "Requires Edge mode with \u22651 edge selected.")
	_rip_btn.pressed.connect(_on_rip_pressed)
	grid.add_child(_rip_btn)
	_register_op(_rip_btn, _cond_edge_any)

	_dissolve_btn = _op_button("Dissolve",
		"Dissolve selected edge(s), merging the two adjacent faces into one.\n"
		+ "Requires Edge mode with \u22651 interior edge selected.")
	_dissolve_btn.pressed.connect(_on_dissolve_pressed)
	grid.add_child(_dissolve_btn)
	_register_op(_dissolve_btn, _cond_edge_any)


# ---------------------------------------------------------------------------
# External trigger entry points
# ---------------------------------------------------------------------------

## Equivalent to pressing the Extrude Edge button.
func trigger_extrude_edge() -> void:
	_on_extrude_edge_pressed()


## Equivalent to pressing the Bevel button.
func trigger_bevel() -> void:
	_on_bevel_pressed()


## Equivalent to pressing the Bridge button.
func trigger_bridge() -> void:
	_on_bridge_pressed()


## Equivalent to pressing the Loop Cut button.
func trigger_loop_cut() -> void:
	_on_loop_cut_pressed()


## Equivalent to pressing the Hard Edge button.
func trigger_hard_edge() -> void:
	_on_hard_edge_pressed()


## Equivalent to pressing the Soft Edge button.
func trigger_soft_edge() -> void:
	_on_soft_edge_pressed()


## Equivalent to pressing the Rip button.
func trigger_rip() -> void:
	_on_rip_pressed()


## Equivalent to pressing the Dissolve button.
func trigger_dissolve() -> void:
	_on_dissolve_pressed()


# ---------------------------------------------------------------------------
# Conditions
# ---------------------------------------------------------------------------

func _cond_edge_any() -> bool:
	return _target != null \
			and _target.selection.get_mode() == SelectionManager.Mode.EDGE \
			and not _target.selection.get_selected_edges().is_empty()


func _cond_edge_bridge() -> bool:
	if _target == null or _target.go_build_mesh == null:
		return false
	if _target.selection.get_mode() != SelectionManager.Mode.EDGE:
		return false
	var count: int = 0
	for ei: int in _target.selection.get_selected_edges():
		if ei < _target.go_build_mesh.edges.size() \
				and _target.go_build_mesh.edges[ei].is_boundary():
			count += 1
	return count >= 2


# ---------------------------------------------------------------------------
# Operation handlers
# ---------------------------------------------------------------------------

func _on_extrude_edge_pressed() -> void:
	if _target == null or _plugin == null:
		return
	if _target.selection.get_mode() != SelectionManager.Mode.EDGE:
		return
	var sel_edges: Array[int] = _target.selection.get_selected_edges()
	if sel_edges.is_empty():
		return
	var edges_to_extrude: Array[int] = []
	edges_to_extrude.assign(sel_edges)
	var target_ref: GoBuildMeshInstance = _target
	var last_new_edges: Array[int] = []

	var preview := GoBuildParamPreview.new()
	preview.action_name = "Extrude Edge"
	preview.param_label = "Distance"
	preview.param_start = _EDGE_EXTRUDE_DEFAULT_WIDTH
	preview.param_min   = -100.0
	preview.param_max   = 100.0
	preview.radial      = false
	preview.snap_step   = 0.1
	preview.apply_fn    = func(p: float) -> void:
		last_new_edges.clear()
		var result: Array[int] = EdgeExtrudeOperation.apply(
				_target.go_build_mesh, edges_to_extrude, p)
		last_new_edges.assign(result)
	preview.post_commit_fn = _make_select_edges_fn(target_ref, last_new_edges)
	_plugin.call("begin_param_preview", preview)


func _on_bevel_pressed() -> void:
	if _target == null or _plugin == null:
		return
	if _target.selection.get_mode() != SelectionManager.Mode.EDGE:
		return
	var sel_edges: Array[int] = _target.selection.get_selected_edges()
	if sel_edges.is_empty():
		return
	var edges_to_bevel: Array[int] = []
	edges_to_bevel.assign(sel_edges)

	var preview := GoBuildParamPreview.new()
	preview.action_name = "Bevel Edge"
	preview.param_label = "Width"
	preview.param_start = _BEVEL_DEFAULT_WIDTH
	preview.param_min   = 0.0001
	preview.radial      = false
	preview.snap_step   = 0.05
	preview.apply_fn    = func(p: float) -> void: \
			BevelOperation.apply(_target.go_build_mesh, edges_to_bevel, p)
	_plugin.call("begin_param_preview", preview)


func _on_bridge_pressed() -> void:
	if _target == null or _plugin == null:
		return
	if _target.selection.get_mode() != SelectionManager.Mode.EDGE:
		return
	var sel_edges: Array[int] = _target.selection.get_selected_edges()
	if sel_edges.size() < 2:
		return
	var edges_to_bridge: Array[int] = []
	edges_to_bridge.assign(sel_edges)
	_run_op("Bridge Edge Loops",
			func(): BridgeOperation.apply(_target.go_build_mesh, edges_to_bridge))


func _on_loop_cut_pressed() -> void:
	if _target == null or _plugin == null:
		return
	if _target.selection.get_mode() != SelectionManager.Mode.EDGE:
		return
	var sel_edges: Array[int] = _target.selection.get_selected_edges()
	if sel_edges.is_empty():
		return
	var edges_to_cut: Array[int] = []
	edges_to_cut.assign(sel_edges)

	# Project the seed edge into screen space to determine the visual drag direction.
	# screen_dir points from vertex_a to vertex_b in viewport pixels (normalised).
	# The parameter delta = dot(cursor_offset, screen_dir) × units_per_pixel, so
	# dragging along the edge moves the cut in the matching visual direction whether
	# the edge runs horizontally, vertically, or diagonally on screen.
	var upp: float = 0.004
	var screen_dir: Vector2 = Vector2(1.0, 0.0)  # safe fallback — horizontal
	var sv: SubViewport = EditorInterface.get_editor_viewport_3d(0)
	if sv != null:
		var cam: Camera3D = sv.get_camera_3d()
		if cam != null:
			var gbm: GoBuildMesh = _target.go_build_mesh
			var seed_e: GoBuildEdge = gbm.edges[edges_to_cut[0]]
			var va_w: Vector3 = _target.global_transform \
					* gbm.vertices[seed_e.vertex_a]
			var vb_w: Vector3 = _target.global_transform \
					* gbm.vertices[seed_e.vertex_b]
			var sv_a: Vector2 = cam.unproject_position(va_w)
			var sv_b: Vector2 = cam.unproject_position(vb_w)
			var dir: Vector2 = sv_b - sv_a
			# Only replace the fallback when the edge projects to a non-degenerate
			# length (edge nearly perpendicular to view → keep horizontal fallback).
			if dir.length() > 1.0:
				screen_dir = dir.normalized()

	var preview := GoBuildParamPreview.new()
	preview.action_name      = "Loop Cut"
	preview.param_label      = "Position"
	preview.param_start      = 0.5
	preview.param_min        = 0.0
	preview.param_max        = 1.0
	preview.units_per_pixel  = upp
	preview.screen_direction = screen_dir
	preview.scale_by_gizmo   = false
	preview.snap_to_start    = true
	preview.snap_threshold   = 0.04
	preview.snap_step        = 0.1
	preview.radial           = false
	preview.apply_fn         = func(p: float) -> void: \
			LoopCutOperation.apply(_target.go_build_mesh, edges_to_cut, p)
	_plugin.call("begin_param_preview", preview)


func _on_hard_edge_pressed() -> void:
	if _target == null or _plugin == null:
		return
	if _target.selection.get_mode() != SelectionManager.Mode.EDGE:
		return
	var sel_edges: Array[int] = _target.selection.get_selected_edges()
	if sel_edges.is_empty():
		return
	var edges: Array[int] = []
	edges.assign(sel_edges)
	_run_op(
		"Hard Edge",
		func(): HardEdgeOperation.apply(_target.go_build_mesh, edges, true),
		false,
	)


func _on_soft_edge_pressed() -> void:
	if _target == null or _plugin == null:
		return
	if _target.selection.get_mode() != SelectionManager.Mode.EDGE:
		return
	var sel_edges: Array[int] = _target.selection.get_selected_edges()
	if sel_edges.is_empty():
		return
	var edges: Array[int] = []
	edges.assign(sel_edges)
	_run_op(
		"Soft Edge",
		func(): HardEdgeOperation.apply(_target.go_build_mesh, edges, false),
		false,
	)


func _on_rip_pressed() -> void:
	if _target == null or _plugin == null:
		return
	if _target.selection.get_mode() != SelectionManager.Mode.EDGE:
		return
	var sel_edges: Array[int] = _target.selection.get_selected_edges()
	if sel_edges.is_empty():
		return
	var edges_to_rip: Array[int] = []
	edges_to_rip.assign(sel_edges)

	var gbm: GoBuildMesh = _target.go_build_mesh
	gbm.rebuild_edges()

	var vertex_set: Dictionary = {}
	var face_set: Dictionary = {}
	for ei: int in edges_to_rip:
		if ei < 0 or ei >= gbm.edges.size():
			continue
		var edge: GoBuildEdge = gbm.edges[ei]
		vertex_set[edge.vertex_a] = true
		vertex_set[edge.vertex_b] = true
		for fi: int in edge.face_indices:
			face_set[fi] = true

	var rip_verts: Array[int] = []
	for vi: int in vertex_set:
		rip_verts.append(vi)
	var rip_faces: Array[int] = []
	for fi: int in face_set:
		rip_faces.append(fi)

	var direction: Vector3 = RipOperation.compute_rip_direction(gbm, rip_faces)
	GoBuildDebug.log("[RipEdge] edges=%s verts=%s faces=%s direction=%s" \
			% [str(edges_to_rip), str(rip_verts), str(rip_faces), str(direction)])
	var world_direction: Vector3 = _target.global_transform.basis * direction
	direction = direction.normalized()

	var screen_dir: Vector2 = Vector2(1.0, 0.0)
	var sv: SubViewport = EditorInterface.get_editor_viewport_3d(0)
	if sv != null:
		var cam: Camera3D = sv.get_camera_3d()
		if cam != null:
			var centroid: Vector3 = Vector3.ZERO
			var vcount: int = 0
			for vi: int in rip_verts:
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
	preview.action_name = "Rip Edge"
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
		var result: Array[int] = RipOperation.apply_edge_drag(
				_target.go_build_mesh, edges_to_rip, direction, p)
		last_ripped_verts.assign(result)
	preview.post_commit_fn = func() -> void:
		if target_ref == null or not is_instance_valid(target_ref):
			return
		GoBuildDebug.log("[RipEdge] post_commit_fn: last_ripped=%s" % str(last_ripped_verts))
		if last_ripped_verts.is_empty():
			return
		var ripped_verts: Array[int] = []
		ripped_verts.assign(last_ripped_verts)
		var timer: SceneTreeTimer = target_ref.get_tree().create_timer(0.0)
		timer.timeout.connect(func() -> void:
			if target_ref == null or not is_instance_valid(target_ref):
				return
			target_ref.selection.set_mode(SelectionManager.Mode.VERTEX)
			target_ref.selection.set_selected_vertices(ripped_verts)
			target_ref.update_gizmos()
		)
	_plugin.call("begin_param_preview", preview)


func _on_dissolve_pressed() -> void:
	if _target == null or _plugin == null:
		return
	if _target.selection.get_mode() != SelectionManager.Mode.EDGE:
		return
	var sel_edges: Array[int] = _target.selection.get_selected_edges()
	if sel_edges.is_empty():
		return
	var edges: Array[int] = []
	edges.assign(sel_edges)
	_run_op("Dissolve Edges",
			func(): DissolveOperation.dissolve_edges(_target.go_build_mesh, edges),
			false)
