## GoBuild editor side-panel dock.
##
## Displayed in the bottom-left dock slot while the plugin is active.
## Shows the currently selected [GoBuildMeshInstance] and its mesh statistics.
## Future stages will add toolbar buttons for all modelling operations.
@tool
class_name GoBuildPanel
extends VBoxContainer

# Self-preloads: Godot's startup scan reaches go_build_panel.gd before
# selection_manager.gd and go_build_mesh_instance.gd alphabetically.
# Explicit preloads here ensure those class names are registered before
# this script's own class-level type annotations are resolved.
const _DEBUG_SCRIPT          := preload("res://addons/go_build/core/go_build_debug.gd")
const _SEL_MGR_SCRIPT        := preload("res://addons/go_build/core/selection_manager.gd")
const _MESH_INSTANCE_SCRIPT  := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _EXTRUDE_SCRIPT  := preload("res://addons/go_build/mesh/operations/extrude_operation.gd")
const _FNORMALS_SCRIPT := preload("res://addons/go_build/mesh/operations/flip_normals_operation.gd")
const _DELETE_SCRIPT   := preload("res://addons/go_build/mesh/operations/delete_operation.gd")
const _WELD_SCRIPT          := preload("res://addons/go_build/mesh/operations/weld_operation.gd")
const _EDGE_EXTRUDE_SCRIPT := \
		preload("res://addons/go_build/mesh/operations/edge_extrude_operation.gd")
const _BEVEL_SCRIPT := \
		preload("res://addons/go_build/mesh/operations/bevel_operation.gd")
const _BRIDGE_SCRIPT := \
		preload("res://addons/go_build/mesh/operations/bridge_operation.gd")
const _SUBDIVIDE_SCRIPT := \
		preload("res://addons/go_build/mesh/operations/subdivide_operation.gd")
const _LOOP_CUT_SCRIPT := \
		preload("res://addons/go_build/mesh/operations/loop_cut_operation.gd")
const _PARAM_PREVIEW_SCRIPT := \
		preload("res://addons/go_build/core/go_build_param_preview.gd")

const _VERSION := "0.1.0"

## Default extrude distance in local mesh units.
const _EXTRUDE_DEFAULT_DISTANCE: float = 0.5

## Default bevel width in local mesh units.
const _BEVEL_DEFAULT_WIDTH: float = 0.01

var _status_label: Label
var _stats_label: Label
var _mode_buttons: Array[Button] = []
var _extrude_btn: Button       = null
var _flip_btn: Button          = null
var _extrude_edge_btn: Button  = null
var _bevel_btn: Button         = null
var _bridge_btn: Button        = null
var _subdivide_btn: Button     = null
var _loop_cut_btn: Button      = null
var _delete_btn: Button        = null
var _merge_btn: Button         = null
var _weld_btn: Button          = null
var _cull_check: CheckBox      = null

## Registry of all operation buttons and their enable-condition callables.
## Populated by [method _register_op] during [method _ready].
## Iterated by [method _update_ops_buttons] to update enabled/disabled state.
var _op_entries: Array = []
var _context_label: Label      = null
var _target: GoBuildMeshInstance = null
var _plugin: EditorPlugin = null


## Called by the owning [EditorPlugin] immediately after the panel is docked.
## Required so [method _insert_shape] can access [method EditorPlugin.get_undo_redo].
func set_plugin(plugin: EditorPlugin) -> void:
	_plugin = plugin


## Called by the plugin whenever the transform mode or a held modifier changes.
## Shows the active operation name in the panel; hides the label when empty.
func update_context(text: String) -> void:
	if _context_label == null:
		return
	_context_label.text = text
	_context_label.visible = not text.is_empty()


func _ready() -> void:
	name = "GoBuild"
	custom_minimum_size = Vector2(180, 0)

	# ── Header ──────────────────────────────────────────────────────────
	var header := Label.new()
	header.text = "GoBuild  v" + _VERSION
	header.add_theme_font_size_override("font_size", 13)
	add_child(header)

	add_child(HSeparator.new())

	# ── Edit Mode ────────────────────────────────────────────────────────
	var mode_label := Label.new()
	mode_label.text = "── Edit Mode ──"
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	mode_label.add_theme_font_size_override("font_size", 11)
	add_child(mode_label)

	var mode_row := HBoxContainer.new()
	add_child(mode_row)

	var mode_names: Array[String] = ["Object", "Vertex", "Edge", "Face"]
	# Default shortcut keys shown in the tooltip.  The actual binding is stored
	# in EditorSettings and can be changed via Editor → Editor Settings → gobuild/shortcuts.
	var mode_keys: Array[String]  = ["1", "2", "3", "4"]
	for i: int in mode_names.size():
		var btn := Button.new()
		btn.text = mode_names[i]
		btn.toggle_mode = true
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 11)
		btn.tooltip_text = (
				"%s mode  (shortcut: %s)\n"
				+ "Rebind: Editor \u2192 Editor Settings \u2192 gobuild/shortcuts"
		) % [mode_names[i], mode_keys[i]]
		btn.pressed.connect(_on_mode_button_pressed.bind(i))
		mode_row.add_child(btn)
		_mode_buttons.append(btn)

	# Object mode active by default.
	_mode_buttons[SelectionManager.Mode.OBJECT].button_pressed = true

	_context_label = Label.new()
	_context_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_context_label.add_theme_font_size_override("font_size", 11)
	_context_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	_context_label.text = ""
	_context_label.visible = false
	add_child(_context_label)

	add_child(HSeparator.new())

	# ── Create Shape ─────────────────────────────────────────────────────
	var create_label := Label.new()
	create_label.text = "── Create Shape ──"
	create_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	create_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	create_label.add_theme_font_size_override("font_size", 11)
	add_child(create_label)

	var grid := GridContainer.new()
	grid.columns = 2
	add_child(grid)

	var shapes: Array = [
		["Cube",      func(): return CubeGenerator.generate()],
		["Plane",     func(): return PlaneGenerator.generate()],
		["Cylinder",  func(): return CylinderGenerator.generate()],
		["Sphere",    func(): return SphereGenerator.generate()],
		["Cone",      func(): return ConeGenerator.generate()],
		["Torus",     func(): return TorusGenerator.generate()],
		["Staircase", func(): return StaircaseGenerator.generate()],
		["Arch",      func(): return ArchGenerator.generate()],
	]
	for shape_data: Array in shapes:
		var btn := Button.new()
		btn.text = shape_data[0]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_insert_shape.bind(shape_data[1], "GoBuild" + shape_data[0]))
		grid.add_child(btn)

	add_child(HSeparator.new())

	# ── Modelling Operations ──────────────────────────────────────────────
	# Operations are grouped by the edit mode they require.
	add_child(_section_label("── Vertex ──"))

	var vert_grid := GridContainer.new()
	vert_grid.columns = 2
	add_child(vert_grid)

	_merge_btn = _op_button("Merge",
		"Merge selected vertices to their centroid (M).\n"
		+ "Requires Vertex mode with ≥2 vertices selected.")
	_merge_btn.pressed.connect(_on_merge_pressed)
	vert_grid.add_child(_merge_btn)
	_register_op(_merge_btn, _cond_vertex_merge)

	_weld_btn = _op_button("Weld",
		"Merge all vertices within 0.0001 units (Merge by Distance).\n"
		+ "Requires Vertex mode.")
	_weld_btn.pressed.connect(_on_weld_pressed)
	vert_grid.add_child(_weld_btn)
	_register_op(_weld_btn, _cond_vertex_any)

	add_child(_section_label("── Edge ──"))

	var edge_grid := GridContainer.new()
	edge_grid.columns = 2
	add_child(edge_grid)

	_extrude_edge_btn = _op_button("Extrude",
		"Extrude selected boundary edge(s) into new quad faces (Shift+drag).\n"
		+ "Requires Edge mode with ≥1 boundary edge selected.")
	_extrude_edge_btn.pressed.connect(_on_extrude_edge_pressed)
	edge_grid.add_child(_extrude_edge_btn)
	_register_op(_extrude_edge_btn, _cond_edge_boundary)

	_bevel_btn = _op_button("Bevel",
		"Bevel selected edge(s) at 0.1 units width.\n"
		+ "Requires Edge mode with ≥1 edge selected.")
	_bevel_btn.pressed.connect(_on_bevel_pressed)
	edge_grid.add_child(_bevel_btn)
	_register_op(_bevel_btn, _cond_edge_any)

	_bridge_btn = _op_button("Bridge",
		"Bridge two open boundary edge loops with a quad strip (F).\n"
		+ "Requires Edge mode with ≥2 boundary edges from two distinct loops.")
	_bridge_btn.pressed.connect(_on_bridge_pressed)
	edge_grid.add_child(_bridge_btn)
	_register_op(_bridge_btn, _cond_edge_bridge)

	_loop_cut_btn = _op_button("Loop Cut",
		"Insert an edge loop through a quad ring at the midpoint of the\n"
		+ "selected edge(s). Requires Edge mode with ≥1 edge selected.")
	_loop_cut_btn.pressed.connect(_on_loop_cut_pressed)
	edge_grid.add_child(_loop_cut_btn)
	_register_op(_loop_cut_btn, _cond_edge_any)

	add_child(_section_label("── Face ──"))

	var face_grid := GridContainer.new()
	face_grid.columns = 2
	add_child(face_grid)

	_extrude_btn = _op_button("Extrude",
		"Extrude selected face(s) by %.2f units along their normal.\n" % _EXTRUDE_DEFAULT_DISTANCE
		+ "Requires Face mode with ≥1 face selected.")
	_extrude_btn.pressed.connect(_on_extrude_pressed)
	face_grid.add_child(_extrude_btn)
	_register_op(_extrude_btn, _cond_face_any)

	_subdivide_btn = _op_button("Subdivide",
		"Subdivide selected face(s): each N-gon becomes N quads.\n"
		+ "Requires Face mode with ≥1 face selected.")
	_subdivide_btn.pressed.connect(_on_subdivide_pressed)
	face_grid.add_child(_subdivide_btn)
	_register_op(_subdivide_btn, _cond_face_any)

	_flip_btn = _op_button("Flip Normals",
		"Reverse the outward normal of selected face(s) by flipping winding order.\n"
		+ "Requires Face mode with ≥1 face selected.")
	_flip_btn.pressed.connect(_on_flip_normals_pressed)
	face_grid.add_child(_flip_btn)
	_register_op(_flip_btn, _cond_face_any)

	add_child(_section_label("── General ──"))

	var general_grid := GridContainer.new()
	general_grid.columns = 2
	add_child(general_grid)

	_delete_btn = _op_button("Delete",
		"Delete selected vertices, edges, or faces (Del / X).\n"
		+ "Orphaned vertices are removed automatically.")
	_delete_btn.pressed.connect(_on_delete_pressed)
	general_grid.add_child(_delete_btn)
	_register_op(_delete_btn, _cond_any_selection)

	add_child(HSeparator.new())

	# ── Status ───────────────────────────────────────────────────────────
	_status_label = Label.new()
	_status_label.text = "No mesh selected."
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status_label)

	# ── Stats ────────────────────────────────────────────────────────────
	_stats_label = Label.new()
	_stats_label.add_theme_color_override("font_color",
			Color(0.65, 0.65, 0.65))
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_stats_label)

	add_child(HSeparator.new())

	# ── Hint ─────────────────────────────────────────────────────────────
	var hint := Label.new()
	hint.text = "Select a GoBuildMeshInstance\nnode to begin editing."
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 11)
	add_child(hint)

	add_child(HSeparator.new())

	# ── Debug toggle ──────────────────────────────────────────────────────
	# Routes all [GoBuild] prints through GoBuildDebug.log() — silent when off.
	var dbg_toggle := CheckBox.new()
	dbg_toggle.text = "Debug logging"
	dbg_toggle.button_pressed = GoBuildDebug.enabled
	dbg_toggle.add_theme_font_size_override("font_size", 11)
	dbg_toggle.toggled.connect(func(on: bool) -> void: GoBuildDebug.enabled = on)
	add_child(dbg_toggle)

	# ── Back-face toggle ──────────────────────────────────────────────────
	# Disables culling on the active mesh while editing so both sides of every
	# face are visible.  Off by default; useful for diagnosing flipped normals.
	_cull_check = CheckBox.new()
	_cull_check.text = "Show back-faces"
	_cull_check.button_pressed = false
	_cull_check.add_theme_font_size_override("font_size", 11)
	_cull_check.tooltip_text = (
		"Disable back-face culling on the mesh while editing.\n"
		+ "Useful for spotting flipped normals and inside-out geometry.\n"
		+ "Has no effect outside the editor."
	)
	_cull_check.toggled.connect(_on_cull_check_toggled)
	add_child(_cull_check)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Update the panel to reflect [param target].
## Pass [code]null[/code] to clear the selection display.
func set_target(target: GoBuildMeshInstance) -> void:
	# Clear the back-face override on the old target before switching.
	if _target != null and is_instance_valid(_target):
		_target.set_edit_cull_override(false)

	# Disconnect from old target's selection signals.
	if _target != null and _target.selection.mode_changed.is_connected(_on_target_mode_changed):
		_target.selection.mode_changed.disconnect(_on_target_mode_changed)
	if _target != null and _target.selection.selection_changed.is_connected(_update_ops_buttons):
		_target.selection.selection_changed.disconnect(_update_ops_buttons)
	if _target != null and _target.mesh_changed.is_connected(_refresh):
		_target.mesh_changed.disconnect(_refresh)

	_target = target

	if _target != null:
		_target.selection.mode_changed.connect(_on_target_mode_changed)
		_target.selection.selection_changed.connect(_update_ops_buttons)
		_target.mesh_changed.connect(_refresh)
		_sync_mode_buttons(_target.selection.get_mode())
		# Apply the current checkbox state so the new node matches immediately.
		if _cull_check != null:
			_target.set_edit_cull_override(_cull_check.button_pressed)
	else:
		_sync_mode_buttons(SelectionManager.Mode.OBJECT)

	_update_ops_buttons()
	_refresh()


## Apply the mode button state that corresponds to [param new_mode].
## Called via the signal from the target's [SelectionManager].
func set_edit_mode(new_mode: SelectionManager.Mode) -> void:
	if _target != null:
		_target.selection.set_mode(new_mode)
	_sync_mode_buttons(new_mode)


## Called by external code (e.g. the right-click context menu in plugin.gd)
## to trigger an extrude on the current selection.
## Equivalent to pressing the Extrude panel button.
func trigger_extrude() -> void:
	_on_extrude_pressed()


## Called by external code (e.g. the right-click context menu)
## to flip the normals of the current face selection.
## Equivalent to pressing the Flip Normals panel button.
func trigger_flip_normals() -> void:
	_on_flip_normals_pressed()


## Called by external code (e.g. the plugin keyboard handler or the right-click
## context menu) to delete the current selection.
## Dispatches to the appropriate [DeleteOperation] entry point based on the
## active edit mode.  Equivalent to pressing the Delete panel button.
func trigger_delete() -> void:
	_on_delete_pressed()


## Called by external code (e.g. the M keyboard shortcut or the right-click
## context menu) to merge the current vertex selection.
## Equivalent to pressing the Merge panel button.
func trigger_merge() -> void:
	_on_merge_pressed()


## Called by external code (e.g. the right-click context menu)
## to weld (merge by distance) vertices in the current mesh.
## Equivalent to pressing the Weld panel button.
func trigger_weld() -> void:
	_on_weld_pressed()


## Called by external code (e.g. the right-click context menu)
## to bevel the current edge selection with the parameter preview.
## Equivalent to pressing the Bevel panel button.
func trigger_bevel() -> void:
	_on_bevel_pressed()


## Called by external code (e.g. the right-click context menu)
## to subdivide the current face selection.
## Equivalent to pressing the Subdivide panel button.
func trigger_subdivide() -> void:
	_on_subdivide_pressed()


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _refresh() -> void:
	if _target == null or _target.go_build_mesh == null:
		_status_label.text = "No mesh selected."
		_stats_label.text = ""
		return

	var gbm: GoBuildMesh = _target.go_build_mesh
	_status_label.text = "Editing:  %s" % _target.name

	var vert_count: int = gbm.vertices.size()
	var face_count: int = gbm.faces.size()
	var edge_count: int = gbm.edges.size()
	_stats_label.text = "Verts: %d   Faces: %d   Edges: %d" % [
		vert_count, face_count, edge_count,
	]


## Create a [GoBuildMeshInstance] populated by [param mesh_callable] and
## insert it at the root of the currently edited scene with full undo/redo.
func _insert_shape(mesh_callable: Callable, node_name: String) -> void:
	if not Engine.is_editor_hint():
		return
	if not _plugin:
		push_warning("GoBuild: cannot insert shape — plugin reference not set")
		return

	var scene_root: Node = EditorInterface.get_edited_scene_root()
	if not scene_root:
		push_warning("GoBuild: no open scene — create or open a scene first")
		return

	var node := GoBuildMeshInstance.new()
	node.name = node_name
	node.go_build_mesh = mesh_callable.call()

	var ur: EditorUndoRedoManager = _plugin.get_undo_redo()
	ur.create_action("Insert " + node_name)
	ur.add_do_method(scene_root, "add_child", node, true)
	ur.add_do_method(node, "set_owner", scene_root)
	ur.add_undo_method(scene_root, "remove_child", node)
	ur.add_undo_reference(node)
	ur.commit_action()

	# Auto-select the new node so _edit() fires immediately and the user can
	# switch to a sub-element mode without first having to click the node in
	# the scene tree or viewport.
	var es: EditorSelection = EditorInterface.get_selection()
	es.clear()
	es.add_node(node)


## Called when one of the mode radio buttons is pressed.
##
## Routes through the plugin's [method EditorPlugin.switch_mode] so that
## [method Node3D.update_gizmos] is always called — even when the mode is
## unchanged (a no-op in SelectionManager).  Falls back to direct
## [method SelectionManager.set_mode] if the plugin reference is not set.
##
## The plugin's [method _on_mode_changed] handler (connected to the
## [signal SelectionManager.mode_changed] signal) takes care of the editor
## tool shortcut and gizmo refresh for all sources.
func _on_mode_button_pressed(mode_index: int) -> void:
	var new_mode: SelectionManager.Mode = mode_index as SelectionManager.Mode
	GoBuildDebug.log("[GoBuild] PANEL._on_mode_button_pressed  mode_index=%d  target_null=%s" \
			% [mode_index, str(_target == null)])
	if _plugin != null:
		_plugin.call("switch_mode", new_mode)
	elif _target != null:
		_target.selection.set_mode(new_mode)
	_sync_mode_buttons(new_mode)


## Called when the target's [SelectionManager] emits [signal SelectionManager.mode_changed].
## Keeps the panel buttons in sync when the plugin changes mode via keyboard shortcut.
func _on_target_mode_changed(new_mode: SelectionManager.Mode) -> void:
	_sync_mode_buttons(new_mode)
	_update_ops_buttons()


## Press exactly the button that corresponds to [param active_mode] and
## release all others (radio-button behaviour).
func _sync_mode_buttons(active_mode: SelectionManager.Mode) -> void:
	for i: int in _mode_buttons.size():
		_mode_buttons[i].set_pressed_no_signal(i == active_mode as int)


## Create a styled section-header [Label] for the operations area.
func _section_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	lbl.add_theme_font_size_override("font_size", 11)
	return lbl


## Create a standard disabled operation [Button] with tooltip.
func _op_button(text: String, tooltip: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 11)
	btn.tooltip_text = tooltip
	btn.disabled = true
	return btn


# ---------------------------------------------------------------------------
# Button-registry helpers
# ---------------------------------------------------------------------------

## Register [param btn] so [method _update_ops_buttons] will enable it when
## [param condition].call() returns [code]true[/code] and disable it otherwise.
## Call once per button inside [method _ready], immediately after the button is
## added to its parent container.
func _register_op(btn: Button, condition: Callable) -> void:
	_op_entries.append({"button": btn, "condition": condition})


## [code]true[/code] when Vertex mode is active and ≥2 vertices are selected.
func _cond_vertex_merge() -> bool:
	return _target != null \
			and _target.selection.get_mode() == SelectionManager.Mode.VERTEX \
			and _target.selection.get_selected_vertices().size() >= 2


## [code]true[/code] when Vertex mode is active (selection may be empty).
func _cond_vertex_any() -> bool:
	return _target != null \
			and _target.selection.get_mode() == SelectionManager.Mode.VERTEX


## [code]true[/code] when Edge mode is active and ≥1 edge is selected.
func _cond_edge_any() -> bool:
	return _target != null \
			and _target.selection.get_mode() == SelectionManager.Mode.EDGE \
			and not _target.selection.get_selected_edges().is_empty()


## [code]true[/code] when Edge mode is active and ≥1 selected edge is a
## boundary (single-face) edge.
func _cond_edge_boundary() -> bool:
	if _target == null or _target.go_build_mesh == null:
		return false
	if _target.selection.get_mode() != SelectionManager.Mode.EDGE:
		return false
	for ei: int in _target.selection.get_selected_edges():
		if ei < _target.go_build_mesh.edges.size() \
				and _target.go_build_mesh.edges[ei].is_boundary():
			return true
	return false


## [code]true[/code] when Edge mode is active and ≥2 selected edges are
## boundary edges (the minimum required by Bridge).
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


## [code]true[/code] when Face mode is active and ≥1 face is selected.
func _cond_face_any() -> bool:
	return _target != null \
			and _target.selection.get_mode() == SelectionManager.Mode.FACE \
			and not _target.selection.get_selected_faces().is_empty()


## [code]true[/code] when there is at least one selected element in the
## current non-Object edit mode.
func _cond_any_selection() -> bool:
	if _target == null:
		return false
	match _target.selection.get_mode():
		SelectionManager.Mode.VERTEX:
			return not _target.selection.get_selected_vertices().is_empty()
		SelectionManager.Mode.EDGE:
			return not _target.selection.get_selected_edges().is_empty()
		SelectionManager.Mode.FACE:
			return not _target.selection.get_selected_faces().is_empty()
	return false


# ---------------------------------------------------------------------------
# Button-state update
# ---------------------------------------------------------------------------

## Enable or disable every registered operation button based on the current
## mode and selection.  Each button evaluates its own condition independently,
## so a crash in one condition cannot prevent the others from updating.
## Called on mode change, selection change, and mesh change.
func _update_ops_buttons() -> void:
	for entry in _op_entries:
		entry.button.disabled = not entry.condition.call()



## Apply [param op_callable] as a single undo/redo [param action_name] on the
## active target, then refresh the panel UI.
## Set [param clear_selection] to [code]false[/code] when the operation should keep
## the current selection (e.g. Flip Normals).
func _run_op(
		action_name: String,
		op_callable: Callable,
		clear_selection: bool = true,
) -> void:
	if _target == null or _plugin == null:
		return
	_target.apply_operation(action_name, op_callable, _plugin.get_undo_redo())
	if clear_selection:
		_target.selection.clear()
	_target.update_gizmos()
	_update_ops_buttons()
	_refresh()


## Public entry-point so [GoBuildGizmoPlugin] can trigger edge extrude via
## keyboard shortcut (Shift+E while in Edge mode).
func trigger_extrude_edge() -> void:
	_on_extrude_edge_pressed()


## Extrude the selected boundary edges, creating new quad faces.
## Requires Edge mode with at least one boundary edge selected.
## Pushes a single undo/redo action via [method GoBuildMeshInstance.apply_operation].
func _on_extrude_edge_pressed() -> void:
	if _target == null or _plugin == null:
		return
	if _target.selection.get_mode() != SelectionManager.Mode.EDGE:
		return
	var sel_edges: Array[int] = _target.selection.get_selected_edges()
	if sel_edges.is_empty():
		return

	# Filter to boundary edges only before passing to the operation.
	var boundary_edges: Array[int] = []
	for ei: int in sel_edges:
		if _target.go_build_mesh.edges[ei].is_boundary():
			boundary_edges.append(ei)
	if boundary_edges.is_empty():
		return

	# Capture to a local so the Callable closure captures the right set.
	var edges_to_extrude: Array[int] = []
	edges_to_extrude.assign(boundary_edges)

	var new_edge_indices: Array[int] = []
	var ur: EditorUndoRedoManager = _plugin.get_undo_redo()
	_target.apply_operation(
		"Extrude Edge",
		func(): new_edge_indices = EdgeExtrudeOperation.apply(
				_target.go_build_mesh, edges_to_extrude),
		ur,
	)

	# Select the newly created boundary edges so the user can immediately drag them.
	_target.selection.clear()
	for ei: int in new_edge_indices:
		_target.selection.select_edge(ei)
	_target.update_gizmos()
	_update_ops_buttons()
	_refresh()


## Bevel the selected edge(s) by [constant _BEVEL_DEFAULT_WIDTH].
## Requires Edge mode with at least one edge selected.
## Pushes a single undo/redo action via [method GoBuildMeshInstance.apply_operation].
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
	preview.action_name    = "Bevel Edge"
	preview.param_label    = "Width"
	preview.param_start    = _BEVEL_DEFAULT_WIDTH
	preview.param_min      = 0.0001
	preview.apply_fn       = func(p: float) -> void: \
			BevelOperation.apply(_target.go_build_mesh, edges_to_bevel, p)
	_plugin.call("begin_param_preview", preview)


## Public entry-point for the F keyboard shortcut (Bridge in Edge mode).
func trigger_bridge() -> void:
	_on_bridge_pressed()


## Bridge two selected boundary edge loops with a quad strip.
## Requires Edge mode with ≥2 boundary edges from two distinct loops.
## Pushes a single undo/redo action via [method GoBuildMeshInstance.apply_operation].
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


## Extrude the currently selected faces.
## Requires Face mode and at least one selected face.
## Enters parameter-preview mode — drag to adjust extrude distance, LMB to commit.
func _on_extrude_pressed() -> void:
	if _target == null or _plugin == null:
		return
	if _target.selection.get_mode() != SelectionManager.Mode.FACE:
		return
	var sel_faces: Array[int] = _target.selection.get_selected_faces()
	if sel_faces.is_empty():
		return
	var faces_to_extrude: Array[int] = []
	faces_to_extrude.assign(sel_faces)
	var preview := GoBuildParamPreview.new()
	preview.action_name = "Extrude Face"
	preview.param_label = "Distance"
	preview.param_start = _EXTRUDE_DEFAULT_DISTANCE
	preview.param_min   = -100.0
	preview.param_max   = 100.0
	preview.apply_fn    = func(p: float) -> void: \
			ExtrudeOperation.apply(_target.go_build_mesh, faces_to_extrude, p)
	_plugin.call("begin_param_preview", preview)


## Subdivide the currently selected faces into quads.
## Requires Face mode and at least one selected face.
## Pushes a single undo/redo action via [method GoBuildMeshInstance.apply_operation].
func _on_subdivide_pressed() -> void:
	if _target == null or _plugin == null:
		return
	if _target.selection.get_mode() != SelectionManager.Mode.FACE:
		return
	var sel_faces: Array[int] = _target.selection.get_selected_faces()
	if sel_faces.is_empty():
		return
	var faces_to_subdivide: Array[int] = []
	faces_to_subdivide.assign(sel_faces)
	_run_op("Subdivide Face",
			func(): SubdivideOperation.apply(_target.go_build_mesh, faces_to_subdivide))


## Flip the outward normals of the currently selected faces.
## Requires Face mode and at least one selected face.
## Pushes a single undo/redo action via [method GoBuildMeshInstance.apply_operation].
func _on_flip_normals_pressed() -> void:
	if _target == null or _plugin == null:
		return
	if _target.selection.get_mode() != SelectionManager.Mode.FACE:
		return
	var sel_faces: Array[int] = _target.selection.get_selected_faces()
	if sel_faces.is_empty():
		return
	var faces_to_flip: Array[int] = []
	faces_to_flip.assign(sel_faces)
	_run_op("Flip Normals",
			func(): FlipNormalsOperation.apply(_target.go_build_mesh, faces_to_flip),
			false)


## Delete the currently selected vertices, edges, or faces.
## Dispatches to [DeleteOperation] based on the active edit mode.
## Pushes a single undo/redo action via [method GoBuildMeshInstance.apply_operation].
func _on_delete_pressed() -> void:
	if _target == null or _plugin == null:
		return
	var mode: SelectionManager.Mode = _target.selection.get_mode()
	var ur: EditorUndoRedoManager = _plugin.get_undo_redo()

	match mode:
		SelectionManager.Mode.FACE:
			var sel: Array[int] = _target.selection.get_selected_faces()
			if sel.is_empty():
				return
			var to_delete: Array[int] = []
			to_delete.assign(sel)
			_target.apply_operation(
				"Delete Face",
				func(): DeleteOperation.apply_faces(_target.go_build_mesh, to_delete),
				ur,
			)

		SelectionManager.Mode.EDGE:
			var sel: Array[int] = _target.selection.get_selected_edges()
			if sel.is_empty():
				return
			var to_delete: Array[int] = []
			to_delete.assign(sel)
			_target.apply_operation(
				"Delete Edge",
				func(): DeleteOperation.apply_edges(_target.go_build_mesh, to_delete),
				ur,
			)

		SelectionManager.Mode.VERTEX:
			var sel: Array[int] = _target.selection.get_selected_vertices()
			if sel.is_empty():
				return
			var to_delete: Array[int] = []
			to_delete.assign(sel)
			_target.apply_operation(
				"Delete Vertex",
				func(): DeleteOperation.apply_vertices(_target.go_build_mesh, to_delete),
				ur,
			)

		_:
			return  # Object mode — nothing to delete here.

	# Clear selection after delete: indices are no longer valid after compaction.
	_target.selection.clear()
	_target.update_gizmos()
	_update_ops_buttons()
	_refresh()


## Called when the Show back-faces checkbox is toggled.
func _on_cull_check_toggled(enabled: bool) -> void:
	if _target != null:
		_target.set_edit_cull_override(enabled)


## Merge selected vertices to their centroid.
## Requires Vertex mode and at least 2 selected vertices.
## Pushes a single undo/redo action via [method GoBuildMeshInstance.apply_operation].
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


## Weld all vertices within 0.0001 units of each other (Merge by Distance).
## Requires Vertex mode.
## Pushes a single undo/redo action via [method GoBuildMeshInstance.apply_operation].
func _on_weld_pressed() -> void:
	if _target == null or _plugin == null:
		return
	if _target.selection.get_mode() != SelectionManager.Mode.VERTEX:
		return
	_run_op("Weld Vertices",
			func(): WeldOperation.apply_weld_by_threshold(_target.go_build_mesh))


## Public entry-point for keyboard shortcut or context-menu trigger.
func trigger_loop_cut() -> void:
	_on_loop_cut_pressed()


## Insert an edge loop through the quad ring(s) seeded by the selected edge(s).
## Requires Edge mode with at least one edge selected.
## Enters parameter-preview mode — drag to position the loop cut, LMB to commit.
## Near the midpoint (t ≈ 0.5), the cut snaps precisely to the midpoint.
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
	preview.radial           = false
	preview.apply_fn         = func(p: float) -> void: \
			LoopCutOperation.apply(_target.go_build_mesh, edges_to_cut, p)
	_plugin.call("begin_param_preview", preview)
