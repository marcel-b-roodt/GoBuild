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
const _WELD_SCRIPT     := preload("res://addons/go_build/mesh/operations/weld_operation.gd")

const _VERSION := "0.1.0"

## Default extrude distance in local mesh units.
const _EXTRUDE_DEFAULT_DISTANCE: float = 0.5

var _status_label: Label
var _stats_label: Label
var _mode_buttons: Array[Button] = []
var _extrude_btn: Button = null
var _flip_btn: Button    = null
var _delete_btn: Button  = null
var _merge_btn: Button   = null
var _weld_btn: Button    = null
var _cull_check: CheckBox = null
var _target: GoBuildMeshInstance = null
var _plugin: EditorPlugin = null


## Called by the owning [EditorPlugin] immediately after the panel is docked.
## Required so [method _insert_shape] can access [method EditorPlugin.get_undo_redo].
func set_plugin(plugin: EditorPlugin) -> void:
	_plugin = plugin


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
	var ops_label := Label.new()
	ops_label.text = "── Modelling ──"
	ops_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ops_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	ops_label.add_theme_font_size_override("font_size", 11)
	add_child(ops_label)

	var ops_grid := GridContainer.new()
	ops_grid.columns = 2
	add_child(ops_grid)

	_extrude_btn = Button.new()
	_extrude_btn.text = "Extrude"
	_extrude_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_extrude_btn.add_theme_font_size_override("font_size", 11)
	var dist_fmt := "%.2f" % _EXTRUDE_DEFAULT_DISTANCE
	_extrude_btn.tooltip_text = (
		"Extrude selected face(s) by " + dist_fmt
		+ " units along their normal.\nRequires Face mode with at least one face selected."
	)
	_extrude_btn.disabled = true
	_extrude_btn.pressed.connect(_on_extrude_pressed)
	ops_grid.add_child(_extrude_btn)

	_flip_btn = Button.new()
	_flip_btn.text = "Flip Normals"
	_flip_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flip_btn.add_theme_font_size_override("font_size", 11)
	_flip_btn.tooltip_text = (
		"Reverse the outward normal of selected face(s) by flipping their winding order.\n"
		+ "Requires Face mode with at least one face selected."
	)
	_flip_btn.disabled = true
	_flip_btn.pressed.connect(_on_flip_normals_pressed)
	ops_grid.add_child(_flip_btn)

	_delete_btn = Button.new()
	_delete_btn.text = "Delete"
	_delete_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_delete_btn.add_theme_font_size_override("font_size", 11)
	_delete_btn.tooltip_text = (
		"Delete selected vertices, edges, or faces.\n"
		+ "Affected faces are removed; orphaned vertices are compacted away."
	)
	_delete_btn.disabled = true
	_delete_btn.pressed.connect(_on_delete_pressed)
	ops_grid.add_child(_delete_btn)

	_merge_btn = Button.new()
	_merge_btn.text = "Merge"
	_merge_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_merge_btn.add_theme_font_size_override("font_size", 11)
	_merge_btn.tooltip_text = (
		"Merge selected vertices to their centroid (M).\n"
		+ "Requires Vertex mode with at least 2 vertices selected."
	)
	_merge_btn.disabled = true
	_merge_btn.pressed.connect(_on_merge_pressed)
	ops_grid.add_child(_merge_btn)

	_weld_btn = Button.new()
	_weld_btn.text = "Weld"
	_weld_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weld_btn.add_theme_font_size_override("font_size", 11)
	_weld_btn.tooltip_text = (
		"Weld all vertices closer than 0.0001 units together (Merge by Distance).\n"
		+ "Requires Vertex mode."
	)
	_weld_btn.disabled = true
	_weld_btn.pressed.connect(_on_weld_pressed)
	ops_grid.add_child(_weld_btn)

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

	_target = target

	if _target != null:
		_target.selection.mode_changed.connect(_on_target_mode_changed)
		_target.selection.selection_changed.connect(_update_ops_buttons)
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


## Enable or disable the operations buttons based on the current mode and selection.
## Called on mode change and on selection change so the button state is always accurate.
func _update_ops_buttons() -> void:
	if _extrude_btn == null:
		return
	var in_face_mode: bool = _target != null \
			and _target.selection.get_mode() == SelectionManager.Mode.FACE
	var has_faces: bool = in_face_mode \
			and not _target.selection.get_selected_faces().is_empty()
	_extrude_btn.disabled = not has_faces
	if _flip_btn != null:
		_flip_btn.disabled = not has_faces
	if _delete_btn != null:
		var mode: SelectionManager.Mode = \
				_target.selection.get_mode() if _target != null \
				else SelectionManager.Mode.OBJECT
		var has_selection: bool = _target != null and (
				(mode == SelectionManager.Mode.VERTEX \
					and not _target.selection.get_selected_vertices().is_empty()) or
				(mode == SelectionManager.Mode.EDGE \
					and not _target.selection.get_selected_edges().is_empty()) or
				(mode == SelectionManager.Mode.FACE \
					and not _target.selection.get_selected_faces().is_empty())
		)
		_delete_btn.disabled = not has_selection
	var in_vertex_mode: bool = _target != null \
			and _target.selection.get_mode() == SelectionManager.Mode.VERTEX
	var sel_verts: Array[int] = _target.selection.get_selected_vertices() \
			if in_vertex_mode and _target != null else []
	if _merge_btn != null:
		_merge_btn.disabled = sel_verts.size() < 2
	if _weld_btn != null:
		_weld_btn.disabled = not in_vertex_mode


## Extrude the currently selected faces by [constant _EXTRUDE_DEFAULT_DISTANCE].
## Requires Face mode and at least one selected face.
## Pushes a single undo/redo action via [method GoBuildMeshInstance.apply_operation].
func _on_extrude_pressed() -> void:
	if _target == null or _plugin == null:
		return
	if _target.selection.get_mode() != SelectionManager.Mode.FACE:
		return
	var sel_faces: Array[int] = _target.selection.get_selected_faces()
	if sel_faces.is_empty():
		return

	# Capture a copy of the face indices at press time so the Callable closure
	# uses the correct set even if the selection changes during the undo/redo cycle.
	var faces_to_extrude: Array[int] = []
	faces_to_extrude.assign(sel_faces)

	var ur: EditorUndoRedoManager = _plugin.get_undo_redo()
	_target.apply_operation(
		"Extrude Face",
		func(): ExtrudeOperation.apply(
				_target.go_build_mesh, faces_to_extrude, _EXTRUDE_DEFAULT_DISTANCE),
		ur,
	)

	# Clear the selection after the operation — the extruded face indices are
	# now the top faces; keeping them selected with stale state would confuse
	# subsequent operations.
	_target.selection.clear()
	_target.update_gizmos()
	_update_ops_buttons()
	_refresh()


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

	# Capture a copy of the face indices at press time so the Callable closure
	# uses the correct set even if the selection changes during the undo/redo cycle.
	var faces_to_flip: Array[int] = []
	faces_to_flip.assign(sel_faces)

	var ur: EditorUndoRedoManager = _plugin.get_undo_redo()
	_target.apply_operation(
		"Flip Normals",
		func(): FlipNormalsOperation.apply(_target.go_build_mesh, faces_to_flip),
		ur,
	)

	# Keep the face selection — flipped faces remain valid targets for subsequent
	# operations (e.g. flip again to restore, or extrude through the inside).
	_target.update_gizmos()
	_update_ops_buttons()
	_refresh()


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

	var ur: EditorUndoRedoManager = _plugin.get_undo_redo()
	_target.apply_operation(
		"Merge Vertices",
		func(): WeldOperation.apply_merge(_target.go_build_mesh, to_merge),
		ur,
	)

	_target.selection.clear()
	_target.update_gizmos()
	_update_ops_buttons()
	_refresh()


## Weld all vertices within 0.0001 units of each other (Merge by Distance).
## Requires Vertex mode.
## Pushes a single undo/redo action via [method GoBuildMeshInstance.apply_operation].
func _on_weld_pressed() -> void:
	if _target == null or _plugin == null:
		return
	if _target.selection.get_mode() != SelectionManager.Mode.VERTEX:
		return

	var ur: EditorUndoRedoManager = _plugin.get_undo_redo()
	_target.apply_operation(
		"Weld Vertices",
		func(): WeldOperation.apply_weld_by_threshold(_target.go_build_mesh),
		ur,
	)

	_target.selection.clear()
	_target.update_gizmos()
	_update_ops_buttons()
	_refresh()

