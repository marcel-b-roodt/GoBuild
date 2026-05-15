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
const _DEBUG_SCRIPT            := preload("res://addons/go_build/core/go_build_debug.gd")
const _SEL_MGR_SCRIPT          := preload("res://addons/go_build/core/selection_manager.gd")
const _MESH_INSTANCE_SCRIPT    := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _SETTINGS_SCRIPT         := \
		preload("res://addons/go_build/core/go_build_project_settings.gd")
const _DRAWER_SCRIPT           := preload("res://addons/go_build/core/go_build_drawer.gd")
const _CREATE_DRAWER_SCRIPT    := \
		preload("res://addons/go_build/core/go_build_create_drawer.gd")
const _VERTEX_DRAWER_SCRIPT    := \
		preload("res://addons/go_build/core/go_build_vertex_drawer.gd")
const _EDGE_DRAWER_SCRIPT      := \
		preload("res://addons/go_build/core/go_build_edge_drawer.gd")
const _FACE_DRAWER_SCRIPT      := \
		preload("res://addons/go_build/core/go_build_face_drawer.gd")
const _UV_DRAWER_SCRIPT        := \
		preload("res://addons/go_build/core/go_build_uv_drawer.gd")
const _SURFACE_DRAWER_SCRIPT   := \
		preload("res://addons/go_build/core/go_build_surface_drawer.gd")
const _MATERIALS_DRAWER_SCRIPT := \
		preload("res://addons/go_build/core/go_build_materials_drawer.gd")
const _GENERAL_DRAWER_SCRIPT   := \
		preload("res://addons/go_build/core/go_build_general_drawer.gd")
const _SHAPE_CATALOG_SCRIPT    := \
		preload("res://addons/go_build/mesh/generators/shape_creation_catalog.gd")

const _PLUGIN_CFG_PATH := "res://addons/go_build/plugin.cfg"

var _status_label: Label
var _stats_label: Label
var _context_label: Label      = null
var _mode_buttons: Array[Button] = []
var _target: GoBuildMeshInstance = null
var _plugin: EditorPlugin = null
var _auto_uv_option: OptionButton = null

## Collapsible drawer subcomponents.
var _create_drawer:   GoBuildCreateDrawer   = null
var _vertex_drawer:   GoBuildVertexDrawer   = null
var _edge_drawer:     GoBuildEdgeDrawer     = null
var _face_drawer:     GoBuildFaceDrawer     = null
var _uv_drawer:       GoBuildUvDrawer       = null
var _surface_drawer:  GoBuildSurfaceDrawer  = null
var _materials_drawer: GoBuildMaterialsDrawer = null
var _general_drawer:  GoBuildGeneralDrawer  = null



## Called by the owning [EditorPlugin] immediately after the panel is docked.
## Called by the owning [EditorPlugin] immediately after the panel is docked.
## Passes the plugin reference to all drawer subcomponents.
func set_plugin(plugin: EditorPlugin) -> void:
	_plugin = plugin
	for drawer in [_create_drawer, _vertex_drawer, _edge_drawer, _face_drawer,
			_uv_drawer, _surface_drawer, _materials_drawer, _general_drawer]:
		if drawer != null:
			drawer.set_plugin(plugin)


## Called by the owning [EditorPlugin] after project settings are loaded.
## Triggers palette auto-discovery so the dropdown is populated.
func set_project_settings(settings: GoBuildProjectSettings) -> void:
	if _materials_drawer != null:
		_materials_drawer.set_project_settings(settings)


## Called by the plugin whenever the transform mode or a held modifier changes.
## Shows the active operation name in the panel; hides the label when empty.
func update_context(text: String) -> void:
	if _context_label == null:
		return
	_context_label.text = text
	_context_label.visible = not text.is_empty()


func _ready() -> void:
	name = "GoBuild"

	# ── Header ──────────────────────────────────────────────────────────
	var header := Label.new()
	header.text = "GoBuild  v" + _get_plugin_version()
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

	# ── Modelling Operations ──────────────────────────────────────────────
	_create_drawer = GoBuildCreateDrawer.new()
	add_child(_create_drawer)

	_vertex_drawer = GoBuildVertexDrawer.new()
	add_child(_vertex_drawer)

	_edge_drawer = GoBuildEdgeDrawer.new()
	add_child(_edge_drawer)

	_face_drawer = GoBuildFaceDrawer.new()
	add_child(_face_drawer)

	_uv_drawer = GoBuildUvDrawer.new()
	add_child(_uv_drawer)

	_surface_drawer = GoBuildSurfaceDrawer.new()
	add_child(_surface_drawer)

	_materials_drawer = GoBuildMaterialsDrawer.new()
	add_child(_materials_drawer)

	_general_drawer = GoBuildGeneralDrawer.new()
	add_child(_general_drawer)
	_sync_legacy_handles()

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


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Update the panel to reflect [param target].
## Pass [code]null[/code] to clear the selection display.
func set_target(target: GoBuildMeshInstance) -> void:
	# Cancel any active UV param preview before switching targets.
	if _uv_drawer != null:
		_uv_drawer.cancel_preview()

	# Disconnect from old target's selection signals.
	if _target != null and _target.selection.mode_changed.is_connected(_on_target_mode_changed):
		_target.selection.mode_changed.disconnect(_on_target_mode_changed)
	if _target != null and _target.selection.selection_changed.is_connected(_update_ops_buttons):
		_target.selection.selection_changed.disconnect(_update_ops_buttons)
	if _target != null and _target.mesh_changed.is_connected(_refresh):
		_target.mesh_changed.disconnect(_refresh)

	_target = target
	_sync_legacy_handles()
	for drawer in [_create_drawer, _vertex_drawer, _edge_drawer, _face_drawer,
			_uv_drawer, _surface_drawer, _materials_drawer, _general_drawer]:
		if drawer != null:
			drawer.set_target(target)

	if _target != null:
		_target.selection.mode_changed.connect(_on_target_mode_changed)
		_target.selection.selection_changed.connect(_update_ops_buttons)
		_target.mesh_changed.connect(_refresh)
		_sync_mode_buttons(_target.selection.get_mode())
	else:
		_sync_mode_buttons(SelectionManager.Mode.OBJECT)

	_update_ops_buttons()
	_refresh()
	_sync_legacy_handles()


## Legacy bridge for tests and older call sites.
## Auto UV now lives in [GoBuildGeneralDrawer], but this panel-level field/method
## is kept as a thin wrapper so existing tests and scripts remain valid.
func _on_auto_uv_mode_selected(index: int) -> void:
	if _general_drawer == null:
		return
	_general_drawer._on_auto_uv_mode_selected(index)


## Legacy bridge for tests and older call sites.
func _supports_shape_preview(shape_name: String) -> bool:
	return ShapeCreationCatalog.supports_preview(shape_name)


## Legacy bridge for tests and older call sites.
func _default_shape_params(shape_name: String) -> Dictionary:
	return ShapeCreationCatalog.default_params(shape_name)


## Legacy bridge for tests and older call sites.
func _build_shape_mesh(shape_name: String, params: Dictionary) -> GoBuildMesh:
	return ShapeCreationCatalog.build_mesh(shape_name, params)


## Apply the mode button state that corresponds to [param new_mode].
## Called via the signal from the target's [SelectionManager].
func set_edit_mode(new_mode: SelectionManager.Mode) -> void:
	if _target != null:
		_target.selection.set_mode(new_mode)
	_sync_mode_buttons(new_mode)


func trigger_extrude() -> void:
	if _face_drawer != null: _face_drawer.trigger_extrude()

func trigger_extrude_edge() -> void:
	if _edge_drawer != null: _edge_drawer.trigger_extrude_edge()

func trigger_flip_normals() -> void:
	if _face_drawer != null: _face_drawer.trigger_flip_normals()

func trigger_delete() -> void:
	if _general_drawer != null: _general_drawer.trigger_delete()

func trigger_merge() -> void:
	if _vertex_drawer != null: _vertex_drawer.trigger_merge()

func trigger_weld() -> void:
	if _vertex_drawer != null: _vertex_drawer.trigger_weld()

func trigger_bevel() -> void:
	if _edge_drawer != null: _edge_drawer.trigger_bevel()

func trigger_bridge() -> void:
	if _edge_drawer != null: _edge_drawer.trigger_bridge()

func trigger_loop_cut() -> void:
	if _edge_drawer != null: _edge_drawer.trigger_loop_cut()

func trigger_hard_edge() -> void:
	if _edge_drawer != null: _edge_drawer.trigger_hard_edge()

func trigger_soft_edge() -> void:
	if _edge_drawer != null: _edge_drawer.trigger_soft_edge()

func trigger_subdivide() -> void:
	if _face_drawer != null: _face_drawer.trigger_subdivide()

func trigger_inset() -> void:
	if _face_drawer != null: _face_drawer.trigger_inset()

func trigger_flat() -> void:
	if _surface_drawer != null: _surface_drawer.trigger_flat()

func trigger_smooth() -> void:
	if _surface_drawer != null: _surface_drawer.trigger_smooth()

func trigger_auto_smooth() -> void:
	if _surface_drawer != null: _surface_drawer.trigger_auto_smooth()

func trigger_planar_uv() -> void:
	if _uv_drawer != null: _uv_drawer.trigger_planar_uv()

func trigger_box_uv() -> void:
	if _uv_drawer != null: _uv_drawer.trigger_box_uv()

func trigger_cylindrical_uv() -> void:
	if _uv_drawer != null: _uv_drawer.trigger_cylindrical_uv()

func trigger_spherical_uv() -> void:
	if _uv_drawer != null: _uv_drawer.trigger_spherical_uv()


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _refresh() -> void:
	if _materials_drawer != null:
		_materials_drawer.refresh()
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
## Opens/closes the mode-specific drawers and refreshes button states.
func _on_target_mode_changed(new_mode: SelectionManager.Mode) -> void:
	_sync_mode_buttons(new_mode)
	_update_ops_buttons()
	match new_mode:
		SelectionManager.Mode.OBJECT:
			if _create_drawer  != null: _create_drawer.set_open(true)
			if _vertex_drawer  != null: _vertex_drawer.set_open(false)
			if _edge_drawer    != null: _edge_drawer.set_open(false)
			if _face_drawer    != null: _face_drawer.set_open(false)
			if _uv_drawer	   != null: _uv_drawer.set_open(false)
			if _surface_drawer != null: _surface_drawer.set_open(false)
		SelectionManager.Mode.VERTEX:
			if _create_drawer  != null: _create_drawer.set_open(false)
			if _vertex_drawer  != null: _vertex_drawer.set_open(true)
			if _edge_drawer    != null: _edge_drawer.set_open(false)
			if _face_drawer    != null: _face_drawer.set_open(false)
			if _uv_drawer	   != null: _uv_drawer.set_open(false)
			if _surface_drawer != null: _surface_drawer.set_open(false)
		SelectionManager.Mode.EDGE:
			if _create_drawer  != null: _create_drawer.set_open(false)
			if _vertex_drawer  != null: _vertex_drawer.set_open(false)
			if _edge_drawer    != null: _edge_drawer.set_open(true)
			if _face_drawer    != null: _face_drawer.set_open(false)
			if _uv_drawer	   != null: _uv_drawer.set_open(false)
			if _surface_drawer != null: _surface_drawer.set_open(false)
		SelectionManager.Mode.FACE:
			if _create_drawer  != null: _create_drawer.set_open(false)
			if _vertex_drawer  != null: _vertex_drawer.set_open(false)
			if _edge_drawer    != null: _edge_drawer.set_open(false)
			if _face_drawer    != null: _face_drawer.set_open(true)
			if _uv_drawer	   != null: _uv_drawer.set_open(true)
			if _surface_drawer != null: _surface_drawer.set_open(true)


## Press exactly the button that corresponds to [param active_mode] and
## release all others (radio-button behaviour).
func _sync_mode_buttons(active_mode: SelectionManager.Mode) -> void:
	for i: int in _mode_buttons.size():
		_mode_buttons[i].set_pressed_no_signal(i == active_mode as int)


# ---------------------------------------------------------------------------
# Button-state update
# ---------------------------------------------------------------------------

## Refresh all drawer button enabled states based on the current mode/selection.
## Called on mode change, selection change, and mesh change.
func _update_ops_buttons() -> void:
	for drawer in [_create_drawer, _vertex_drawer, _edge_drawer, _face_drawer,
			_uv_drawer, _surface_drawer, _materials_drawer, _general_drawer]:
		if drawer != null:
			drawer.refresh_buttons()


func _sync_legacy_handles() -> void:
	_auto_uv_option = _general_drawer._auto_uv_option if _general_drawer != null else null


## Return the plugin version from plugin.cfg so panel text stays in sync.
## Falls back to "unknown" if the config cannot be loaded.
func _get_plugin_version() -> String:
	var cfg := ConfigFile.new()
	var err: Error = cfg.load(_PLUGIN_CFG_PATH)
	if err != OK:
		return "unknown"
	var version: Variant = cfg.get_value("plugin", "version", "unknown")
	return str(version)
