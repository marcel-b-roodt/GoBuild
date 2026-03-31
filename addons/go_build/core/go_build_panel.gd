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
const _DEBUG_SCRIPT        := preload("res://addons/go_build/core/go_build_debug.gd")
const _SEL_MGR_SCRIPT      := preload("res://addons/go_build/core/selection_manager.gd")
const _MESH_INSTANCE_SCRIPT := preload("res://addons/go_build/core/go_build_mesh_instance.gd")

const _VERSION := "0.1.0"

var _status_label: Label
var _stats_label: Label
var _mode_buttons: Array[Button] = []
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


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Update the panel to reflect [param target].
## Pass [code]null[/code] to clear the selection display.
func set_target(target: GoBuildMeshInstance) -> void:
	# Disconnect from old target's selection signals.
	if _target != null and _target.selection.mode_changed.is_connected(_on_target_mode_changed):
		_target.selection.mode_changed.disconnect(_on_target_mode_changed)

	_target = target

	if _target != null:
		_target.selection.mode_changed.connect(_on_target_mode_changed)
		_sync_mode_buttons(_target.selection.get_mode())
	else:
		_sync_mode_buttons(SelectionManager.Mode.OBJECT)

	_refresh()


## Apply the mode button state that corresponds to [param new_mode].
## Called via the signal from the target's [SelectionManager].
func set_edit_mode(new_mode: SelectionManager.Mode) -> void:
	if _target != null:
		_target.selection.set_mode(new_mode)
	_sync_mode_buttons(new_mode)


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
## Routes through the plugin's switch_mode() so update_gizmos() is always
## called — even when the mode is unchanged (noop in SelectionManager).
## Previously this called _target.selection.set_mode() directly; that path
## skipped update_gizmos() when mode_changed was not emitted (same-mode press).
func _on_mode_button_pressed(mode_index: int) -> void:
	var new_mode: SelectionManager.Mode = mode_index as SelectionManager.Mode
	GoBuildDebug.log("[GoBuild] PANEL._on_mode_button_pressed  mode_index=%d  target_null=%s" \
			% [mode_index, str(_target == null)])
	if _plugin != null:
		# switch_mode() always calls update_gizmos() via _set_mode(),
		# regardless of whether the mode actually changes.
		_plugin.call("switch_mode", new_mode)
	elif _target != null:
		_target.selection.set_mode(new_mode)
	_sync_mode_buttons(new_mode)


## Called when the target's [SelectionManager] emits [signal SelectionManager.mode_changed].
## Keeps the panel buttons in sync when the plugin changes mode via keyboard shortcut.
func _on_target_mode_changed(new_mode: SelectionManager.Mode) -> void:
	_sync_mode_buttons(new_mode)


## Press exactly the button that corresponds to [param active_mode] and
## release all others (radio-button behaviour).
func _sync_mode_buttons(active_mode: SelectionManager.Mode) -> void:
	for i: int in _mode_buttons.size():
		_mode_buttons[i].set_pressed_no_signal(i == active_mode as int)
