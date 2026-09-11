## GoBuild EditorPlugin entry point.
##
## Registers the GoBuildMeshInstance custom type, adds the side-panel dock,
## and wires editor selection so the panel updates when a mesh is selected.
## All viewport mouse input (handle picking, drag, box-select, context menu)
## is delegated to [SelectionInputController].
##
## This script MUST remain GDScript — the plugin must work in every Godot 4
@tool
extends EditorPlugin

# Load the central script registry first so all class_name identifiers are
# registered in Godot's global lookup before any other script compiles.
# This eliminates the per-file self-preload requirement and prevents
# "Nonexistent function 'new'" errors from alphabetical scan-order issues.
const _INIT := preload("res://addons/go_build/go_build_init.gd")

# ---------------------------------------------------------------------------
# Preloads — kept for backward compatibility with existing const references
# in this script.  Order no longer matters because GoBuildInit has already
# registered all class names.
# ---------------------------------------------------------------------------
const _DEBUG_SCRIPT         := preload("res://addons/go_build/core/go_build_debug.gd")
const _FACE_SCRIPT          := preload("res://addons/go_build/mesh/go_build_face.gd")
const _PALETTE_SCRIPT       := preload("res://addons/go_build/core/go_build_material_palette.gd")
const _SETTINGS_SCRIPT      := preload("res://addons/go_build/core/go_build_project_settings.gd")
const _SEL_MGR_SCRIPT       := preload("res://addons/go_build/core/selection_manager.gd")
const _OVERLAY_HINT_SCRIPT  := preload("res://addons/go_build/core/overlay_hint_helper.gd")
const _SEL_DIMS_SCRIPT      := preload("res://addons/go_build/core/selection_dims_helper.gd")
const _MESH_INSTANCE_SCRIPT := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _GIZMO_PLUGIN_SCRIPT  := preload("res://addons/go_build/core/go_build_gizmo_plugin.gd")

const _PICKING_HELPER_SCRIPT := preload("res://addons/go_build/core/picking_helper.gd")
const _PANEL_SCRIPT         := preload("res://addons/go_build/core/go_build_panel.gd")
const _UV_PANEL_SCRIPT      := preload("res://addons/go_build/uv/go_build_uv_panel.gd")
const _VC_PAINTER_SCRIPT   := preload(
		"res://addons/go_build/vertex_paint/go_build_vertex_painter.gd")
const _PAINT_BRUSH_SCRIPT := preload(
		"res://addons/go_build/vertex_paint/go_build_vertex_paint_brush.gd")
const _CONTROLLER_SCRIPT    := preload(
		"res://addons/go_build/core/selection_input_controller.gd")
const _CHEATSHEET_SCRIPT    := preload(
		"res://addons/go_build/core/go_build_cheatsheet_popup.gd")
const _TOOL_PINNER_SCRIPT   := preload(
		"res://addons/go_build/core/node3d_editor_tool_pinner.gd")
const _SNAP_TO_GRID_OP := preload(
		"res://addons/go_build/mesh/operations/snap_to_grid_operation.gd")
const _EDGE_CLASS := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _TRANSFORM_HELPERS := preload(
		"res://addons/go_build/core/go_build_transform_helpers.gd")
const _DRAG_CTRL_SCRIPT    := preload(
		"res://addons/go_build/core/go_build_drag_controller.gd")
const _DRAG_OP_SCRIPT       := preload(
		"res://addons/go_build/core/go_build_drag_operation.gd")
const _SHAPE_DRAW_CTRL_SCRIPT := preload(
		"res://addons/go_build/core/go_build_shape_draw_controller.gd")
const _KNIFE_CTRL_SCRIPT := preload(
		"res://addons/go_build/core/go_build_knife_controller.gd")
const _SHAPE_DRAW_OVERLAY_SCRIPT := preload(
		"res://addons/go_build/core/go_build_shape_draw_overlay.gd")
const _CURSOR_OVERLAY := preload(
		"res://addons/go_build/core/go_build_cursor_overlay.gd")
const _DROP_CONVERTER_SCRIPT := preload(
		"res://addons/go_build/core/go_build_material_drop_converter.gd")
const _EXPORT_INSPECTOR_SCRIPT := preload(
		"res://addons/go_build/export/go_build_export_inspector_plugin.gd")
const _ICON                 := preload("res://addons/go_build/go_build.svg")


## EditorSettings keys for the four mode-switch shortcuts.
const _SHORTCUT_OBJECT := "gobuild/shortcuts/object_mode"
const _SHORTCUT_VERTEX := "gobuild/shortcuts/vertex_mode"
const _SHORTCUT_EDGE   := "gobuild/shortcuts/edge_mode"
const _SHORTCUT_FACE   := "gobuild/shortcuts/face_mode"

## Snap step presets shown in the toolbar picker.
## Index 0 is the "Editor" fallback (reads Godot editor grid step).
## All other values are in metres.
const _SNAP_PRESETS: Array[float] = [-1.0, 0.1, 0.25, 0.5, 1.0, 2.0]
const _SNAP_LABELS:  Array[String] = [
	"Editor", "0.1 m", "0.25 m", "0.5 m", "1 m", "2 m"
]

## Rotation snap presets (degrees).
const _ROT_SNAP_PRESETS: Array[float] = [5.0, 15.0, 30.0, 45.0, 60.0, 90.0]
const _ROT_SNAP_LABELS:  Array[String] = ["5", "15", "30", "45", "60", "90"]
const _ROT_SNAP_DEFAULT_IDX: int = 1   # 15

## Scale snap presets (ratio step).
const _SCALE_SNAP_PRESETS: Array[float] = [0.1, 0.2, 0.5, 1.0]
const _SCALE_SNAP_LABELS:  Array[String] = ["0.1", "0.2", "0.5", "1.0"]
const _SCALE_SNAP_DEFAULT_IDX: int = 0   # 0.1

## Snap mode labels shown in the toolbar dropdown.
const _SNAP_MODE_LABELS: Array[String] = ["Hybrid", "World", "Delta"]

## Snap settings state (indices into the label arrays) for the summary
## label and the settings panel. (indices into the label arrays) for the live
## summary shown on the Snap MenuButton.
## Transform space labels shown in the toolbar dropdown.
const _TRANSFORM_SPACE_LABELS: Array[String] = ["Local", "World"]

var _panel: GoBuildPanel                         = null
var _panel_scroll: ScrollContainer               = null
var _uv_panel: GoBuildUvPanel                    = null
var _vc_painter: GoBuildVertexPainter            = null
var _paint_brush: GoBuildVertexPaintBrush        = null
var _project_settings: GoBuildProjectSettings    = null
var _edited_node: GoBuildMeshInstance            = null
var _gizmo_plugin: GoBuildGizmoPlugin            = null
var _export_inspector: GoBuildExportInspectorPlugin = null
var _input_controller: SelectionInputController  = null
var _drag_controller: GoBuildDragController       = null
var _shape_draw_controller: GoBuildShapeDrawController = null
## Knife tool controller; active only while the user is cutting (Face mode).
var _knife_controller: GoBuildKnifeController = null
var _draw_overlay: Control = null
## True while a Godot drag-and-drop is in progress over the viewport.
## Used to detect the end of a drag so we can apply the cached material.
var _drag_was_active: bool = false
## Last known mouse position in the 3D viewport during a drag (SubViewport-local).
var _drag_mouse_pos: Vector2 = Vector2.ZERO
## Whether Ctrl was held during the drag (for surface-slot assignment).
var _drag_ctrl_held: bool = false
# Modifier cache — refreshed in _input on every event; per-frame paths
# read these instead of polling Input.
var _mod_shift: bool = false
var _mod_ctrl: bool = false
var _mod_alt: bool = false
## Cached material that Godot's editor set during a drag.
var _drag_cached_material: Material = null
## Snapshot of the GoBuildMesh before the drag preview started.
## Restored each frame before applying the preview so changes never accumulate.
var _drag_snapshot: Dictionary = {}
## One-frame delay flag.  When the drag ends, we wait one frame to see if Godot
## re-set an override (successful drop) or not (cancel / Escape / right-click).
var _drag_awaiting_drop: bool = false
var _toolbar: HBoxContainer                      = null
var _toolbar_wrap: PanelContainer                = null
var _toolbar_row: HBoxContainer                  = null
var _cog_menu_btn: MenuButton                    = null

## Edit-mode buttons in the toolbar strip; kept in sync with the
## selection mode (mirrors the panel's own row).
var _toolbar_mode_buttons: Array[Button]         = []
var _snap_settings_btn: Button                   = null
var _snap_settings_label: Label                  = null
var _snap_settings_popup: PopupPanel             = null

## Nested Snap menu state (indices into the label arrays) for the live
## summary shown on the Snap MenuButton.
var _snap_menu_space_idx: int = 0
var _snap_menu_translate_idx: int = 0
var _snap_menu_rot_idx: int = 0
var _snap_menu_scale_idx: int = 0
var _snap_menu_mode_idx: int = 0
var _transform_space_btn: OptionButton           = null
## Keeps the native Physical/V tool mode pinned whenever in a sub-element mode.
var _tool_pinner: Node3DEditorToolPinner         = null
## True when GoBuild is in a sub-element mode (Vertex/Edge/Face).
## Used to detect the Edit→Object transition so the native transform mode
## is restored.
var _was_in_edit_mode: bool = false

## Last observed global transform of the edited node while in Object mode.
## Used to detect when the user moves the node so UVs can be refreshed.
var _prev_object_transform: Transform3D          = Transform3D.IDENTITY

## Guards the deferred object-mode UV rebake so at most one [method _flush_object_uv_bake]
## call is queued per rendered frame, no matter how many _process ticks fire.
var _object_uv_bake_scheduled: bool              = false
## Node targeted by the pending object-mode UV bake.
var _object_uv_pending_node: GoBuildMeshInstance = null

# Mode-switch shortcuts (initialised in _enter_tree via EditorSettings).
var _shortcut_object: Shortcut
var _shortcut_vertex: Shortcut
var _shortcut_edge:   Shortcut
var _shortcut_face:   Shortcut


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _enter_tree() -> void:
	add_custom_type(
		"GoBuildMeshInstance",
		"MeshInstance3D",
		_MESH_INSTANCE_SCRIPT,
		_ICON,
	)
	_init_shortcuts()

	_project_settings = GoBuildProjectSettings.load_or_create()
	# Notify the editor filesystem so the file appears in the dock immediately
	# (necessary when the file was just created on this run).
	EditorInterface.get_resource_filesystem().update_file(
			GoBuildProjectSettings.SETTINGS_PATH)
	# Ensure at least one palette exists (creates Default if none found).
	GoBuildProjectSettings.ensure_default_palette()

	_panel = _PANEL_SCRIPT.new()
	_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_panel_scroll = ScrollContainer.new()
	_panel_scroll.name = "GoBuild"
	_panel_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_panel_scroll.add_child(_panel)
	# Place in the upper-left dock alongside Scene, Import, and GoBuild UV so
	# all GoBuild panels live in the same dock group.
	add_control_to_dock(DOCK_SLOT_LEFT_UL, _panel_scroll)
	_panel.set_plugin(self)
	_panel.set_project_settings(_project_settings)

	_uv_panel = _UV_PANEL_SCRIPT.new()
	_uv_panel.name = "GoBuild UV"
	add_control_to_dock(DOCK_SLOT_BOTTOM, _uv_panel)
	_uv_panel.set_plugin(self)
	_panel.set_uv_panel(_uv_panel)

	_vc_painter = _VC_PAINTER_SCRIPT.new()
	_vc_painter.name = "GoBuild Vertex Paint"
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _vc_painter)
	_vc_painter.set_plugin(self)

	_paint_brush = _PAINT_BRUSH_SCRIPT.new()
	_paint_brush.setup(self, _vc_painter)

	_gizmo_plugin = _GIZMO_PLUGIN_SCRIPT.new()
	_gizmo_plugin.setup(self)
	add_node_3d_gizmo_plugin(_gizmo_plugin)

	_export_inspector = _EXPORT_INSPECTOR_SCRIPT.new()
	add_inspector_plugin(_export_inspector)

	_input_controller = _CONTROLLER_SCRIPT.new()
	_drag_controller = _DRAG_CTRL_SCRIPT.new()
	_drag_controller.setup(self)
	_shape_draw_controller = _SHAPE_DRAW_CTRL_SCRIPT.new()
	_input_controller.setup(_gizmo_plugin, _panel, self, _drag_controller)
	_knife_controller = _KNIFE_CTRL_SCRIPT.new()

	_build_toolbar()
	_build_draw_overlay()
	_tool_pinner = Node3DEditorToolPinner.new()
	add_tool_menu_item("GoBuild: Reset Panel Layout", _reset_panel_layout)
	set_process(true)


func _build_toolbar() -> void:
	# GoBuild's own toolbar on its own line: child of the Node3DEditor
	# VBox, right below Godot's native tool row — no mixing with native
	# buttons or their separators.
	_toolbar = HBoxContainer.new()
	_toolbar.add_theme_constant_override("separation", 8)

	# ── 1. GoBuild label + version (from plugin.cfg) ────────────────────
	var title_label := Label.new()
	title_label.text = "GoBuild  v" + _plugin_version()
	title_label.add_theme_font_size_override("font_size", 13)
	_toolbar.add_child(title_label)

	# ── 2. Divider ──────────────────────────────────────────────────────
	_toolbar.add_child(VSeparator.new())

	# ── 3. Edit mode buttons ────────────────────────────────────────────
	var mode_names: Array[String] = ["Object", "Vertex", "Edge", "Face"]
	var mode_keys: Array[String] = ["1", "2", "3", "4"]
	for i: int in mode_names.size():
		var mode_btn := Button.new()
		mode_btn.text = mode_names[i]
		mode_btn.toggle_mode = true
		mode_btn.add_theme_font_size_override("font_size", 11)
		mode_btn.tooltip_text = (
				"%s mode  (shortcut: %s)\n"
				+ "Rebind: Editor \u2192 Editor Settings \u2192 gobuild/shortcuts"
		) % [mode_names[i], mode_keys[i]]
		mode_btn.pressed.connect(_on_toolbar_mode_pressed.bind(i))
		_toolbar.add_child(mode_btn)
		_toolbar_mode_buttons.append(mode_btn)
	_toolbar_mode_buttons[SelectionManager.Mode.OBJECT].button_pressed = true

	# ── 4. Divider ──────────────────────────────────────────────────────
	_toolbar.add_child(VSeparator.new())

	# ── 5 + 6. Snap dropdown and its values ─────────────────────────────
	var snap_btn := Button.new()
	snap_btn.text = "Snap"
	snap_btn.flat = true
	snap_btn.icon = EditorInterface.get_editor_theme().get_icon(
			"GuiOptionArrow", "EditorIcons")
	snap_btn.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	snap_btn.tooltip_text = "Snap settings: mode, translate/rotation/scale step"
	snap_btn.pressed.connect(_on_snap_settings_pressed)
	_toolbar.add_child(snap_btn)
	_snap_settings_btn = snap_btn

	_snap_settings_label = Label.new()
	_update_snap_summary()
	_toolbar.add_child(_snap_settings_label)

	# ── 7. Divider ──────────────────────────────────────────────────────
	_toolbar.add_child(VSeparator.new())

	# ── 8. Space: Local/World ───────────────────────────────────────────
	var space_lbl := Label.new()
	space_lbl.text = "Space:"
	_toolbar.add_child(space_lbl)
	var space_btn := OptionButton.new()
	space_btn.flat = true
	space_btn.tooltip_text = "Gizmo handle orientation: object-local or world axes"
	for label: String in _TRANSFORM_SPACE_LABELS:
		space_btn.add_item(label)
	space_btn.select(_snap_menu_space_idx)
	space_btn.item_selected.connect(_on_transform_space_selected)
	_toolbar.add_child(space_btn)
	_transform_space_btn = space_btn

	# ── 9. Cog (settings) menu ──────────────────────────────────────────
	var cog := MenuButton.new()
	cog.flat = true
	cog.tooltip_text = "GoBuild settings and utilities"
	cog.icon = EditorInterface.get_editor_theme().get_icon(
			"Tools", "EditorIcons")
	var cog_menu: PopupMenu = cog.get_popup()
	cog_menu.add_item("Print Selection")
	cog_menu.add_separator()
	cog_menu.add_check_item("Debug Logging")
	cog_menu.set_item_checked(1, GoBuildDebug.enabled)
	cog_menu.add_check_item("X-Ray (show through mesh)")
	cog_menu.set_item_checked(2, true)
	cog_menu.add_check_item("Face Normals")
	cog_menu.add_check_item("Vertex Normals")
	cog_menu.add_separator()
	cog_menu.add_item("Reset Panel Layout")
	cog_menu.id_pressed.connect(_on_cog_menu_selected)
	_toolbar.add_child(cog)
	_cog_menu_btn = cog

	# ── 10. Docs button ─────────────────────────────────────────────────
	var docs_btn := Button.new()
	docs_btn.icon = EditorInterface.get_editor_theme().get_icon(
			"Help", "EditorIcons")
	docs_btn.flat = true
	docs_btn.tooltip_text = "Show keyboard shortcuts"
	docs_btn.pressed.connect(_on_help_pressed)
	_toolbar.add_child(docs_btn)

	# Theme the strip and place it as its own row under the native bar.
	_toolbar_wrap = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.13, 0.15, 0.55)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	_toolbar_wrap.add_theme_stylebox_override("panel", style)
	_toolbar_wrap.add_child(_toolbar)
	var row := HBoxContainer.new()
	row.add_child(_toolbar_wrap)
	row.add_theme_constant_override("separation", 0)
	var pinner: Node3DEditorToolPinner = _TOOL_PINNER_SCRIPT.new()
	var n3de: Node = pinner._get_node3d_editor_public()
	if n3de != null:
		n3de.add_child(row)
		# Push the row to sit directly under the native toolbar (index 1:
		# 0 is usually the native menu HBox).
		n3de.move_child(row, 1)
	else:
		# Fallback: old in-menu placement.
		add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, row)
	_toolbar_row = row


## Read the plugin version from plugin.cfg (same source the dock header
## uses).
func _plugin_version() -> String:
	var cfg := ConfigFile.new()
	if cfg.load("res://addons/go_build/plugin.cfg") != OK:
		return "?"
	return str(cfg.get_value("plugin", "version", "?"))




func _on_toolbar_mode_pressed(mode_index: int) -> void:
	switch_mode(mode_index as SelectionManager.Mode)
	_sync_toolbar_mode_buttons()


## Mirror the current selection mode onto the toolbar mode buttons.
func _sync_toolbar_mode_buttons() -> void:
	var active: int = SelectionManager.Mode.OBJECT
	if _edited_node != null:
		active = _edited_node.selection.get_mode()
	_sync_toolbar_mode_buttons_value(active)


## Forward target for [method GoBuildPanel._sync_mode_buttons] so
## shortcut-driven changes made before/without the panel still sync.
func sync_toolbar_mode_buttons(active_mode: SelectionManager.Mode) -> void:
	_sync_toolbar_mode_buttons_value(active_mode as int)


func _sync_toolbar_mode_buttons_value(active: int) -> void:
	for i: int in _toolbar_mode_buttons.size():
		_toolbar_mode_buttons[i].set_pressed_no_signal(i == active)


## Open the keyboard-cheatsheet popup from the toolbar Help button.
func _on_help_pressed() -> void:
	var popup: GoBuildCheatsheetPopup = _CHEATSHEET_SCRIPT.new()
	_toolbar.add_child(popup)
	popup.popup_centered()


func _on_cog_menu_selected(id: int) -> void:
	match id:
		0:
			_on_print_selection()
		1:
			var on: bool = not GoBuildDebug.enabled
			GoBuildDebug.enabled = on
			_update_cog_check(1, on)
		2:
			var on: bool = not _gizmo_plugin.xray_mode
			set_xray_mode(on)
			_update_cog_check(2, on)
		3:
			var on: bool = not _gizmo_plugin.show_face_normals
			set_show_face_normals(on)
			_update_cog_check(3, on)
		4:
			var on: bool = not _gizmo_plugin.show_vertex_normals
			set_show_vertex_normals(on)
			_update_cog_check(4, on)
		_:
			_reset_panel_layout()


func _update_cog_check(item_idx: int, on: bool) -> void:
	if _cog_menu_btn == null:
		return
	_cog_menu_btn.get_popup().set_item_checked(item_idx, on)


## Dump the current selection (vertices, edges, faces) with positions/rings
## to the Output panel — debug aid for geometry tooling.
func _on_print_selection() -> void:
	if _edited_node == null or not is_instance_valid(_edited_node) \
			or _edited_node.go_build_mesh == null:
		print("[Selection] no GoBuild object selected")
		return
	var gbm: GoBuildMesh = _edited_node.go_build_mesh
	var sel := _edited_node.selection
	var verts: Array[int] = sel.get_selected_vertices()
	if not verts.is_empty():
		var parts: Array[String] = []
		for vi: int in verts:
			parts.append("%d@%s" % [vi, gbm.vertices[vi]])
		print("[Selection] verts (%d): %s" % [verts.size(), ", ".join(parts)])
	var edges: Array[int] = sel.get_selected_edges()
	if not edges.is_empty():
		var e_parts: Array[String] = []
		for ei: int in edges:
			var e: GoBuildEdge = gbm.edges[ei]
			e_parts.append("%d[%d→%d]" % [ei, e.vertex_a, e.vertex_b])
		print("[Selection] edges (%d): %s" % [edges.size(), ", ".join(e_parts)])
	var faces: Array[int] = sel.get_selected_faces()
	if not faces.is_empty():
		var f_parts: Array[String] = []
		for fi: int in faces:
			f_parts.append("%d ring=%s" % [fi, gbm.faces[fi].vertex_indices])
		print("[Selection] faces (%d): %s" % [faces.size(), "; ".join(f_parts)])
	if verts.is_empty() and edges.is_empty() and faces.is_empty():
		print("[Selection] nothing selected")


func _build_draw_overlay() -> void:
	var vp: SubViewport = EditorInterface.get_editor_viewport_3d(0)
	if vp == null:
		return
	var container: Control = vp.get_parent() as Control
	if container == null:
		return
	_draw_overlay = Control.new()
	_draw_overlay.name = "GoBuildDrawOverlay"
	_draw_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw_overlay.visible = false
	_draw_overlay.draw.connect(_on_draw_overlay)
	container.add_child(_draw_overlay)


func _update_draw_overlay() -> void:
	if _draw_overlay == null or not is_instance_valid(_draw_overlay):
		return
	# Show overlay if shape draw is active OR if a material drag is in progress
	# on a selected GoBuild object.
	var show_overlay: bool = false
	if _shape_draw_controller != null and _shape_draw_controller.is_active() \
			and _edited_node == null:
		show_overlay = true
	if _drag_cached_material != null and _edited_node != null \
			and is_instance_valid(_edited_node) \
			and _edited_node.go_build_mesh != null:
		show_overlay = true
	if not show_overlay:
		_draw_overlay.visible = false
		_draw_overlay.queue_redraw()
		return
	if not _draw_overlay.is_inside_tree():
		return
	_draw_overlay.visible = true
	_draw_overlay.queue_redraw()


func _on_draw_overlay() -> void:
	if _shape_draw_controller != null and _shape_draw_controller.is_active():
		_draw_shape_draw_overlay(_draw_overlay)
	# Draw material drag hint (only for selected GoBuild objects).
	if _drag_cached_material != null and _edited_node != null \
			and is_instance_valid(_edited_node) \
			and _edited_node.go_build_mesh != null:
		_draw_material_drag_hint(_draw_overlay)


func _exit_tree() -> void:
	remove_custom_type("GoBuildMeshInstance")
	remove_tool_menu_item("GoBuild: Reset Panel Layout")

	if _toolbar:
		# _toolbar lives inside _toolbar_wrap and is freed with it.
		_toolbar = null
	if _toolbar_wrap and is_instance_valid(_toolbar_wrap):
		_toolbar_wrap.queue_free()
		_toolbar_wrap = null
	if _toolbar_row and is_instance_valid(_toolbar_row):
		_toolbar_row.get_parent().remove_child(_toolbar_row)
		_toolbar_row.queue_free()
		_toolbar_row = null
		_cog_menu_btn = null
		_toolbar_mode_buttons = []
		_snap_settings_btn = null
		_snap_settings_label = null
		_snap_settings_popup = null
		_transform_space_btn = null

	if _panel:
		remove_control_from_docks(_panel_scroll)
		_panel_scroll.queue_free()
		_panel_scroll = null
		_panel = null

	if _uv_panel:
		remove_control_from_docks(_uv_panel)
		_uv_panel.queue_free()
		_uv_panel = null

	if _vc_painter:
		remove_control_from_docks(_vc_painter)
		_vc_painter.queue_free()
		_vc_painter = null

	_project_settings = null
	_disconnect_node_signals()
	_cleanup_drag_state()
	_edited_node = null

	if _draw_overlay != null and is_instance_valid(_draw_overlay):
		_draw_overlay.queue_free()
		_draw_overlay = null

	if _gizmo_plugin:
		remove_node_3d_gizmo_plugin(_gizmo_plugin)
		_gizmo_plugin = null

	if _export_inspector:
		remove_inspector_plugin(_export_inspector)
		_export_inspector = null

	_input_controller = null
	_object_uv_bake_scheduled = false
	_object_uv_pending_node = null
	set_process(false)
	if _tool_pinner != null:
		_tool_pinner.invalidate()
		_tool_pinner = null


## Remove both dock panels from their current positions and re-add them
## to the default dock slots.  This recovers closed or misplaced panels.
func _reset_panel_layout() -> void:
	if _panel_scroll != null and is_instance_valid(_panel_scroll):
		remove_control_from_docks(_panel_scroll)
	if _uv_panel != null and is_instance_valid(_uv_panel):
		remove_control_from_docks(_uv_panel)
	if _vc_painter != null and is_instance_valid(_vc_painter):
		remove_control_from_docks(_vc_painter)
	# Re-add to default slots.
	if _panel_scroll != null and is_instance_valid(_panel_scroll):
		add_control_to_dock(DOCK_SLOT_LEFT_UL, _panel_scroll)
	if _uv_panel != null and is_instance_valid(_uv_panel):
		add_control_to_dock(DOCK_SLOT_BOTTOM, _uv_panel)
	if _vc_painter != null and is_instance_valid(_vc_painter):
		add_control_to_dock(DOCK_SLOT_RIGHT_UL, _vc_painter)


## Cancel any active material-drop preview and reset drag state.
## Call when [_edited_node] is being cleared or the plugin is exiting.
func _cleanup_drag_state() -> void:
	if _edited_node != null and is_instance_valid(_edited_node):
		if not _drag_snapshot.is_empty():
			GoBuildMaterialDropConverter.cancel_preview(_edited_node, _drag_snapshot)
		else:
			GoBuildMaterialDropConverter.clear_overrides(_edited_node)
	_drag_cached_material = null
	_drag_snapshot = {}
	_drag_awaiting_drop = false
	_drag_was_active = false


## Per-frame poll (belt-and-suspenders alongside the per-draw-frame check).
func _process(_delta: float) -> void:
	if _edited_node != null and _tool_pinner != null:
		_tool_pinner.pin_if_active(_edited_node.selection.mode)

	# Detect drag-and-drop material assignment.  Godot's 3D viewport handles
	# drops at the C++ level, setting material_override or surface_override_material.
	# We suppress the full-object tint and show a per-face preview via GoBuild's
	# data model (restore from snapshot each frame, apply to hovered face, rebake).
	# On drop: restore from snapshot, apply permanently with undo/redo.
	# On cancel: restore from snapshot, rebake (back to original state).
	# Only operates on _edited_node — unselected objects get Godot's native handling.
	#
	# Drop vs cancel detection: we use a one-frame delay.  When gui_is_dragging()
	# transitions to false, we don't apply immediately.  Instead we set
	# _drag_awaiting_drop = true.  On the next frame, if Godot re-set an override
	# on the node (successful drop), we apply.  If not (cancel), we cancel.
	var dragging: bool = get_viewport().gui_is_dragging()
	if dragging:
		_drag_ctrl_held = _mod_ctrl
		_drag_awaiting_drop = false
		if _edited_node != null and is_instance_valid(_edited_node) \
				and _edited_node.go_build_mesh != null:
			var result := GoBuildMaterialDropConverter.update_preview(
					_edited_node, _drag_cached_material, _drag_snapshot,
					EditorInterface.get_editor_viewport_3d(0).get_camera_3d() \
							if EditorInterface.get_editor_viewport_3d(0) != null else null,
					_drag_mouse_pos, _drag_ctrl_held)
			_drag_cached_material = result["material"]
			_drag_snapshot = result["snapshot"]
	if _drag_was_active and not dragging:
		# Drag just ended — wait one frame to see if Godot set an override (drop)
		# or not (cancel / Escape / right-click).
		_drag_awaiting_drop = true
	if _drag_awaiting_drop:
		_drag_awaiting_drop = false
		if _edited_node != null and is_instance_valid(_edited_node) \
				and _edited_node.go_build_mesh != null:
			# Check if Godot re-set an override (successful drop).
			if GoBuildMaterialDropConverter.extract_override_material(_edited_node) != null:
				# Successful drop — extract the material and apply.
				var mat: Material = GoBuildMaterialDropConverter.extract_override_material(
						_edited_node)
				GoBuildMaterialDropConverter.clear_overrides_no_bake(_edited_node)
				var vp: SubViewport = EditorInterface.get_editor_viewport_3d(0)
				var camera: Camera3D = vp.get_camera_3d() if vp != null else null
				var applied := GoBuildMaterialDropConverter.apply_drop(
						_edited_node, get_undo_redo(),
						camera, _drag_mouse_pos, _drag_ctrl_held,
						mat, _drag_snapshot)
				if not applied:
					GoBuildMaterialDropConverter.cancel_preview(
							_edited_node, _drag_snapshot)
			else:
				# Cancel (Escape / right-click / no override) — restore.
				GoBuildMaterialDropConverter.cancel_preview(
						_edited_node, _drag_snapshot)
		_drag_cached_material = null
		_drag_snapshot = {}
	_drag_was_active = dragging

	# Live UV refresh in Object mode: schedule a single end-of-frame rebake
	# whenever the node's transform changes.  The flag ensures at most one
	# _flush_object_uv_bake call is deferred per rendered frame, regardless of
	# how many _process ticks fire while the user is dragging.
	if _edited_node != null \
			and _edited_node.selection.get_mode() == SelectionManager.Mode.OBJECT \
			and _edited_node.auto_uv_mode != GoBuildFace.UvMode.NONE:
		var t := _edited_node.global_transform
		if not t.is_equal_approx(_prev_object_transform):
			_prev_object_transform = t
			if _edited_node.needs_world_space_uv_refresh():
				_schedule_object_uv_bake(_edited_node)
	if _shape_draw_controller != null and _shape_draw_controller.is_active():
		_shape_draw_controller.tick()
	_update_draw_overlay()


## Queue a single deferred UV re-apply + bake for the active node in Object mode.
## Subsequent calls within the same frame are no-ops until the flush fires.
func _schedule_object_uv_bake(node: GoBuildMeshInstance) -> void:
	_object_uv_pending_node = node
	if not _object_uv_bake_scheduled:
		_object_uv_bake_scheduled = true
		call_deferred("_flush_object_uv_bake")


## Flush a pending object-mode UV bake.  Invoked at end-of-frame via call_deferred.
func _flush_object_uv_bake() -> void:
	var node: GoBuildMeshInstance = _object_uv_pending_node
	_object_uv_bake_scheduled = false
	_object_uv_pending_node = null
	if node == null or not is_instance_valid(node):
		return
	if _edited_node == null or node != _edited_node:
		return
	if node.selection.get_mode() != SelectionManager.Mode.OBJECT:
		return
	node._apply_auto_uv()
	node.bake_in_place()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_on_editor_focus_regained()


## While the knife is cutting, route viewport mouse/key events to the knife
## controller.  Returns true when the event was consumed.
func _route_knife_input(event: InputEvent) -> bool:
	if _knife_controller == null or not _knife_controller.is_active() \
			or _edited_node == null:
		return false
	if event is InputEventKey and (event as InputEventKey).keycode == KEY_K:
		GoBuildDebug.log("[Knife] K seen in global _input while cutting — toggling off")
	if not (event is InputEventMouseButton or event is InputEventKey):
		return false
	var vp: SubViewport = EditorInterface.get_editor_viewport_3d(0)
	var cam: Camera3D = vp.get_camera_3d() if vp != null else null
	if cam == null:
		return false
	# Global _input positions are WINDOW-space; the knife's pick maths needs
	# SubViewport-local (same rebase the shape-draw controller applies).
	# Without it the recorded point displaces by the dock/panel offset —
	# the "clicks jump across the face" bug (always toward +x here).
	var routed: InputEvent = event
	if event is InputEventMouseButton:
		var vp_parent: Control = vp.get_parent() as Control
		if vp_parent != null:
			routed = event.duplicate()
			(routed as InputEventMouseButton).position -= \
					vp_parent.get_global_rect().position
	if _knife_controller.handle_input(cam, routed, _edited_node) != 0:
		update_overlays()
		get_viewport().set_input_as_handled()
		return true
	return false


## Global input handler.  When a param preview or gizmo drag is active
## (MOUSE_MODE_CAPTURED), the viewport stops forwarding events through
## _forward_3d_gui_input, so the plugin intercepts them globally and delegates
## to [method SelectionInputController.handle_global_input].
##
## Mode-switch keys (1-4) and grow/shrink (Ctrl+=/Ctrl+-) must also be handled
## here because Godot's built-in viewport shortcuts (1-6 for orthographic views)
## consume these keys before [method _forward_3d_gui_input] is called.  The global
## _input callback runs first, letting us intercept and mark them handled.
func _input(event: InputEvent) -> void:
	# Modifier state cache — refreshed on every event; per-frame overlay
	# and preview paths read the cache (no Input polling outside input).
	if event is InputEventWithModifiers:
		_mod_shift = (event as InputEventWithModifiers).shift_pressed
		_mod_ctrl = (event as InputEventWithModifiers).ctrl_pressed
		_mod_alt = (event as InputEventWithModifiers).alt_pressed
	# Track mouse position in SubViewport-local coords during drags for raycasting.
	if event is InputEventMouseMotion:
		if get_viewport().gui_is_dragging():
			var vp: SubViewport = EditorInterface.get_editor_viewport_3d(0)
			if vp != null:
				var vp_parent: Control = vp.get_parent() as Control
				if vp_parent != null:
					_drag_mouse_pos = (event as InputEventMouseMotion).position \
							- vp_parent.get_global_rect().position
	# Knife tool: while cutting, route mouse + key events (Escape/Enter).
	if _route_knife_input(event):
		return
	if _shape_draw_controller != null and _shape_draw_controller.is_active():
		if event is InputEventKey:
			var key := event as InputEventKey
			if key.keycode == KEY_ESCAPE and key.pressed and not key.echo:
				_shape_draw_controller.cancel()
				_hide_draw_param_strip()
				get_viewport().set_input_as_handled()
				return
		if _shape_draw_controller.is_mouse_captured() \
				and (event is InputEventMouseMotion or event is InputEventMouseButton):
			var vp: SubViewport = EditorInterface.get_editor_viewport_3d(0)
			var camera: Camera3D = vp.get_camera_3d() if vp != null else null
			if camera != null:
				var result: int = _shape_draw_controller.handle_input(camera, event)
				if result != 0:
					if not _shape_draw_controller.is_active():
						_hide_draw_param_strip()
					update_overlays()
					get_viewport().set_input_as_handled()
					return
		if _edited_node == null and not _shape_draw_controller.is_mouse_captured():
			if event is InputEventMouseButton or event is InputEventMouseMotion:
				var editor_vp: SubViewport = EditorInterface.get_editor_viewport_3d(0)
				if editor_vp != null:
					var cam: Camera3D = editor_vp.get_camera_3d()
					if cam != null and _is_event_in_viewport(event, editor_vp):
						var vp_event: InputEvent = event
						if event is InputEventMouse:
							var vp_parent: Control = editor_vp.get_parent() as Control
							if vp_parent != null:
								vp_event = event.duplicate()
								(vp_event as InputEventMouse).position -= \
										vp_parent.get_global_rect().position
								if vp_event is InputEventMouseMotion:
									(vp_event as InputEventMouseMotion).relative = \
											(event as InputEventMouseMotion).relative
						var result2: int = _shape_draw_controller.handle_input(cam, vp_event)
						if result2 != 0:
							if not _shape_draw_controller.is_active():
								_hide_draw_param_strip()
							update_overlays()
							get_viewport().set_input_as_handled()
							return
	# Route events to the paint brush when it's in resize mode (CAPTURED mouse).
	# Under MOUSE_MODE_CAPTURED, _forward_3d_gui_input stops receiving events,
	# so the global _input handler must route them instead.
	# Also intercept Alt+S / Alt+D key presses in paint mode here so they
	# never reach the editor's built-in shortcuts (e.g. S = nav).
	# Also intercept Alt+Q/W/E/R to toggle RGBA channel masks,
	# and Alt+1–5 to select target channel.
	if _route_paint_input(event):
		return
	if _input_controller == null:
		return
	if _input_controller.handle_global_input(event):
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if key.echo or not key.pressed:
		return
	# Knife toggle: K works wherever the editor focus is (mirrors 1-4 mode
	# switches, which use this global path because _forward_3d_gui_input only
	# fires when the mouse is over the 3D viewport).
	if key.keycode == KEY_K and not _text_input_has_focus():
		_handle_knife_key()
		if _edited_node != null:
			get_viewport().set_input_as_handled()
		return
	if _handle_mode_switch_in_global(key):
		get_viewport().set_input_as_handled()


## While the vertex painter is active, route its input (paint mode keys and
## resize drag).  Returns true when the event was consumed.
func _route_paint_input(event: InputEvent) -> bool:
	if _paint_brush == null or _vc_painter == null or not _vc_painter.is_paint_mode():
		return false
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.alt_pressed:
			var handled := true
			match key.keycode:
				KEY_Q: _vc_painter.toggle_channel_r()
				KEY_W: _vc_painter.toggle_channel_g()
				KEY_E: _vc_painter.toggle_channel_b()
				KEY_R: _vc_painter.toggle_channel_a()
				KEY_T: _vc_painter.toggle_isolate()
				KEY_1: _vc_painter.select_target_channel(0)
				KEY_2: _vc_painter.select_target_channel(1)
				KEY_3: _vc_painter.select_target_channel(2)
				KEY_4: _vc_painter.select_target_channel(3)
				KEY_5: _vc_painter.select_target_channel(4)
				_: handled = false
			if not handled and (key.keycode == KEY_S or key.keycode == KEY_D):
				var vp: SubViewport = EditorInterface.get_editor_viewport_3d(0)
				var camera: Camera3D = vp.get_camera_3d() if vp != null else null
				if camera != null and _edited_node != null:
					if _paint_brush.handle_input(camera, event, _edited_node) != 0:
						update_overlays()
						get_viewport().set_input_as_handled()
						return true
				handled = true
			if handled:
				get_viewport().set_input_as_handled()
				return true
	if _paint_brush.is_resizing():
		if event is InputEventMouseMotion or event is InputEventMouseButton or event is InputEventKey:
			if _edited_node != null and _vc_painter != null:
				var vp: SubViewport = EditorInterface.get_editor_viewport_3d(0)
				var camera: Camera3D = vp.get_camera_3d() if vp != null else null
				if camera != null and _paint_brush.handle_input(camera, event, _edited_node) != 0:
					update_overlays()
					get_viewport().set_input_as_handled()
					return true
	return false


## Return [code]true[/code] if [param event] occurred inside the 3D editor viewport.
## Used to filter mouse events so the draw controller only processes clicks
## that originated in the 3D viewport, not on editor panels or docks.
func _is_event_in_viewport(event: InputEvent, vp: SubViewport) -> bool:
	if not event is InputEventMouse:
		return false
	var mouse_event: InputEventMouse = event as InputEventMouse
	var vp_parent: Control = vp.get_parent() as Control
	if vp_parent == null:
		return false
	var vp_rect: Rect2 = vp_parent.get_global_rect()
	return vp_rect.has_point(mouse_event.global_position)


## Handle mode-switch shortcuts (1-4) and grow/shrink (Ctrl+=/Ctrl+-) in the
## global _input callback so they take priority over Godot's built-in viewport
## shortcuts.  Returns [code]true[/code] if the event was consumed.
func _handle_mode_switch_in_global(key: InputEventKey) -> bool:
	if _edited_node == null:
		return false
	if _text_input_has_focus():
		return false
	# Grow/Shrink: Ctrl+= / Ctrl+- (only in sub-element modes).
	if key.ctrl_pressed and _panel != null \
			and _edited_node.selection.get_mode() != SelectionManager.Mode.OBJECT:
		match key.keycode:
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
				_panel.trigger_grow()
				return true
			KEY_MINUS, KEY_KP_SUBTRACT:
				_panel.trigger_shrink()
				return true
	# Mode-switch keys (1-4).
	if _shortcut_object.matches_event(key):
		switch_mode(SelectionManager.Mode.OBJECT)
		return true
	if _shortcut_vertex.matches_event(key):
		switch_mode(SelectionManager.Mode.VERTEX)
		return true
	if _shortcut_edge.matches_event(key):
		switch_mode(SelectionManager.Mode.EDGE)
		return true
	if _shortcut_face.matches_event(key):
		switch_mode(SelectionManager.Mode.FACE)
		return true
	return false


func _on_editor_focus_regained() -> void:
	if _edited_node != null and not is_instance_valid(_edited_node):
		GoBuildDebug.log("[GoBuild] PLUGIN._on_editor_focus_regained  edited_node gone — clearing")
		_disconnect_node_signals()
		_cleanup_drag_state()
		_edited_node = null
		if _panel:
			_panel.set_target(null)

	if _edited_node == null:
		return

	GoBuildDebug.log("[GoBuild] PLUGIN._on_editor_focus_regained  node=%s" % _edited_node.name)

	if _input_controller != null:
		_input_controller.cancel_drag(_edited_node)
		if _drag_controller != null:
			_drag_controller.cancel()
		_input_controller.cancel_box_select(_edited_node)

	if _gizmo_plugin:
		remove_node_3d_gizmo_plugin(_gizmo_plugin)
		add_node_3d_gizmo_plugin(_gizmo_plugin)

	_force_gizmo_redraw_deferred(_edited_node)


## Returns [code]true[/code] if a text-input control (LineEdit, SpinBox, TextEdit,
## or CodeEdit) currently holds keyboard focus, indicating that shortcut keys
## should not be processed.  This prevents mode switches (1-4), transform
## shortcuts (W/E/R), and action keys (Delete/X/M/F) from firing while the
## user is typing in a GoBuild spinbox, the Inspector, or any other text field.
func _text_input_has_focus() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	if focus == null:
		return false
	if focus is LineEdit:
		return true
	if focus is SpinBox:
		return true
	if focus is TextEdit:
		return true
	if focus is CodeEdit:
		return true
	return false


# ---------------------------------------------------------------------------
# Selection / editing
# ---------------------------------------------------------------------------

func _handles(object: Object) -> bool:
	return object is GoBuildMeshInstance


func _edit(object: Object) -> void:
	# Capture the current edit mode so we can carry it to the new node.
	var carry_mode: int = SelectionManager.Mode.OBJECT
	if _edited_node != null and is_instance_valid(_edited_node):
		carry_mode = _edited_node.selection.get_mode()
		# Disconnect signals BEFORE mutating the old node's selection so that
		# mode_changed / selection_changed callbacks do not fire into plugin.gd
		# while the node is mid-teardown.
		_disconnect_node_signals()
		# Reset mode to OBJECT so _redraw() draws nothing for the old node.
		# Without this the gizmo keeps drawing its mode overlay (edge lines,
		# face dots, etc.) even after focus switches to a different mesh.
		_edited_node.selection.set_mode(SelectionManager.Mode.OBJECT)
		_edited_node.update_gizmos()
		_edited_node.set_edit_cull_override(false)
	else:
		_disconnect_node_signals()

	_edited_node = object as GoBuildMeshInstance
	# Reset transform tracking so _process triggers an immediate UV refresh on
	# the newly selected node (it will differ from the sentinel IDENTITY value).
	_prev_object_transform = Transform3D.IDENTITY
	_object_uv_bake_scheduled = false
	_object_uv_pending_node = null
	GoBuildDebug.log("[GoBuild] PLUGIN._edit  node=%s  is_null=%s" \
			% [str(object), str(_edited_node == null)])

	if _edited_node != null:
		if not _edited_node.selection.selection_changed.is_connected(_on_selection_changed):
			_edited_node.selection.selection_changed.connect(_on_selection_changed)
		if not _edited_node.selection.mode_changed.is_connected(_on_mode_changed):
			_edited_node.selection.mode_changed.connect(_on_mode_changed)
		if not _edited_node.tree_exiting.is_connected(_on_edited_node_removed):
			_edited_node.tree_exiting.connect(_on_edited_node_removed)
		if not _edited_node.mesh_changed.is_connected(_on_mesh_changed):
			_edited_node.mesh_changed.connect(_on_mesh_changed)
		_force_gizmo_redraw_deferred(_edited_node)
		if _gizmo_plugin:
			remove_node_3d_gizmo_plugin(_gizmo_plugin)
			add_node_3d_gizmo_plugin(_gizmo_plugin)
		_edited_node.update_gizmos()
		# Carry the previous edit mode to the new node (if not OBJECT already).
		if carry_mode != SelectionManager.Mode.OBJECT:
			_edited_node.selection.set_mode(carry_mode as SelectionManager.Mode)
		if _edited_node.selection.mode != SelectionManager.Mode.OBJECT:
			call_deferred("_suppress_native_gizmo")

	if _panel:
		_panel.set_target(_edited_node)
	if _uv_panel:
		_uv_panel.set_target(_edited_node)
	if _vc_painter:
		_vc_painter.set_target(_edited_node)
	if _panel != null and _panel.get_create_drawer() != null:
		_panel.get_create_drawer().maybe_open_param_popup(_edited_node)
	_refresh_panel_context()


func _force_gizmo_redraw_deferred(node: Node3D) -> void:
	await get_tree().process_frame
	if not is_instance_valid(node) or node != _edited_node:
		return
	if _gizmo_plugin == null:
		return
	var has_gizmo: bool = _gizmo_plugin.has_our_gizmo(node)
	GoBuildDebug.log("[GoBuild] PLUGIN._force_gizmo_redraw_deferred  has_gizmo=%s" \
			% str(has_gizmo))
	if has_gizmo:
		node.update_gizmos()
		return
	GoBuildDebug.log("[GoBuild] PLUGIN._force_gizmo_redraw_deferred  no gizmo — force-creating")
	var gizmo: EditorNode3DGizmo = _gizmo_plugin._create_gizmo(node)
	if gizmo == null:
		return
	gizmo.set("_manual_plugin_ref", _gizmo_plugin)
	node.add_gizmo(gizmo)


func _make_visible(visible: bool) -> void:
	if not visible:
		if _input_controller != null and _edited_node != null:
			_input_controller.clear_hover(_edited_node)
		if _edited_node != null:
			_edited_node.set_edit_cull_override(false)
		_disconnect_node_signals()
		_cleanup_drag_state()
		_edited_node = null
		if _panel:
			_panel.set_target(null)
			_panel.update_context("")
		if _uv_panel:
			_uv_panel.set_target(null)
		if _vc_painter:
			_vc_painter.set_target(null)


# ---------------------------------------------------------------------------
# Viewport input — keyboard shortcuts
# ---------------------------------------------------------------------------

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	# Knife tool swallows viewport input while cutting (Esc/right-click exits).
	if _knife_controller != null and _knife_controller.is_active():
		var knife_result: int = _knife_controller.handle_input(
				camera, event, _edited_node)
		if knife_result != 0:
			update_overlays()
			return knife_result
	if event is InputEventKey and (event as InputEventKey).keycode == KEY_K \
			and (event as InputEventKey).pressed:
		GoBuildDebug.log("[Knife] K seen in _forward_3d_gui_input (echo=%s editing=%s)" % [
				str((event as InputEventKey).echo), str(_edited_node != null)])
	if _shape_draw_controller != null and _shape_draw_controller.is_active():
		var result: int = _shape_draw_controller.handle_input(camera, event)
		if result != 0:
			if not _shape_draw_controller.is_active():
				_hide_draw_param_strip()
			update_overlays()
			return result
	# Vertex paint brush intercepts LMB when paint mode is active.
	# When the brush is in resize mode (MOUSE_MODE_CAPTURED), events are routed
	# through the global _input() handler instead — skip here to avoid conflicts.
	if _paint_brush != null and _vc_painter != null and _vc_painter.is_paint_mode():
		if not _paint_brush.is_resizing():
			var brush_result: int = _handle_paint_brush(camera, event)
			if brush_result != 0:
				return brush_result
	if _edited_node == null:
		return 0
	var key_result: int = _handle_keyboard(event)
	if key_result != 0:
		return key_result
	if _input_controller == null:
		return 0
	return _input_controller.process_input(_edited_node, camera, event)


## Draw the box-select rect, param-preview indicator, and mode / modifier hint label.
## When the DragController is active (param or gizmo mode), its overlay data
## drives the indicator.  Otherwise falls back to the legacy paths.
func _forward_3d_draw_over_viewport(overlay: Control) -> void:
	# Belt-and-suspenders: also pin on every viewport render frame.
	if _edited_node != null and _tool_pinner != null:
		_tool_pinner.pin_if_active(_edited_node.selection.mode)
	if _input_controller != null:
		_input_controller.draw_overlay(overlay)
	# Priority: drag-controller (unified indicator + text) > legacy param hint > mode hint.
	var controller_active: bool = _drag_controller != null and _drag_controller.is_active()
	if _input_controller != null:
		_input_controller.set_suppress_preview_indicator(controller_active)
	if controller_active:
		_draw_controller_overlay(overlay)
		_draw_snap_grid(overlay)
	elif _input_controller != null and _input_controller.has_active_param_preview():
		_draw_param_preview_hint(overlay)
	else:
		_draw_mode_hint(overlay)
	_draw_selection_dims(overlay)
	_draw_shape_draw_overlay(overlay)
	_draw_brush_cursor_overlay(overlay)
	if _knife_controller != null and _knife_controller.is_active():
		var vp: SubViewport = EditorInterface.get_editor_viewport_3d(0)
		var cam: Camera3D = vp.get_camera_3d() if vp != null else null
		_knife_controller.draw_overlay(overlay, cam)


func _draw_shape_draw_overlay(overlay: Control) -> void:
	if _shape_draw_controller == null or not _shape_draw_controller.is_active():
		return
	var state_text: String = _shape_draw_controller.build_state_label(_mod_shift, _mod_ctrl)
	var dims_text: String = _shape_draw_controller.build_dims_label()
	if not state_text.is_empty():
		var font: Font = ThemeDB.fallback_font
		var fsize: int = 12
		var m: float = 8.0
		var pos := Vector2(m, overlay.size.y - m - 18.0 - 18.0)
		overlay.draw_string(font, pos + Vector2(1.0, 1.0), state_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.0, 0.0, 0.0, 0.55))
		overlay.draw_string(font, pos, state_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.65, 1.0, 0.65, 0.90))
	if not dims_text.is_empty():
		var font2: Font = ThemeDB.fallback_font
		var fsize2: int = 12
		var m2: float = 8.0
		var w: float = font2.get_string_size(dims_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize2).x
		var pos2 := Vector2(overlay.size.x - w - m2, overlay.size.y - m2 - 18.0)
		overlay.draw_string(font2, pos2 + Vector2(1.0, 1.0), dims_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fsize2, Color(0.0, 0.0, 0.0, 0.55))
		overlay.draw_string(font2, pos2, dims_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fsize2, Color(0.65, 1.0, 0.65, 0.90))
	# Polygon step: crosshair + rubber band at the cursor (same language as
	# the knife tool).
	if _shape_draw_controller.is_polygon_state():
		_draw_polygon_cursor_overlay(overlay)


# ---------------------------------------------------------------------------
# Polygon cursor overlay (Create Polygon — shared with knife)
# ---------------------------------------------------------------------------

## Crosshair + rubber band for Create Polygon's polygon step: rubber band from
## the last placed vertex to the cursor, closing preview when near the start.
func _draw_polygon_cursor_overlay(overlay: Control) -> void:
	var cam := _shape_draw_controller.get_last_camera()
	var cursor := _shape_draw_controller.get_cursor_screen_pos()
	if cam == null or cursor == Vector2.INF:
		return
	var points: Array[Vector3] = _shape_draw_controller.get_polygon_points()
	if points.is_empty():
		_CURSOR_OVERLAY.draw_crosshair(overlay, cursor, false)
		return
	if cam.is_position_behind(points[points.size() - 1]):
		_CURSOR_OVERLAY.draw_crosshair(overlay, cursor, false)
		return
	var last_screen: Vector2 = cam.unproject_position(points[points.size() - 1])
	_CURSOR_OVERLAY.draw_crosshair(overlay, cursor, false)
	_CURSOR_OVERLAY.draw_rubber_band(overlay, last_screen, cursor)
	if points.size() >= 2 and not cam.is_position_behind(points[0]):
		var first_screen: Vector2 = cam.unproject_position(points[0])
		if first_screen.distance_to(cursor) < 14.0:
			_CURSOR_OVERLAY.draw_rubber_band(overlay, last_screen, first_screen)
		else:
			_CURSOR_OVERLAY.draw_closing_preview(overlay, cursor, first_screen)


# ---------------------------------------------------------------------------
# Brush cursor overlay
# ---------------------------------------------------------------------------

## Draw the brush cursor circle at the hit point showing the brush radius.
## When the ray doesn't hit the mesh, draws a simpler circle at the mouse
## position with a fixed screen-space size so the cursor is always visible.
func _draw_brush_cursor_overlay(overlay: Control) -> void:
	if _vc_painter == null or not _vc_painter.is_paint_mode():
		return
	if _paint_brush == null:
		return
	if _edited_node == null:
		return
	var draw_pos: Vector2 = _paint_brush.get_mouse_2d_pos()
	if draw_pos == Vector2.INF:
		draw_pos = _paint_brush.get_cursor_screen_pos()
	if draw_pos == Vector2.INF:
		return
	var world_pos: Vector3 = _paint_brush.get_cursor_world_pos()
	var vp: SubViewport = EditorInterface.get_editor_viewport_3d(0)
	if vp == null:
		return
	var camera: Camera3D = vp.get_camera_3d()
	if camera == null:
		return
	if world_pos == Vector3.INF:
		var radius: float = _vc_painter.get_brush_radius()
		var fallback_radius: float = radius * 20.0
		fallback_radius = clampf(fallback_radius, 4.0, 60.0)
		overlay.draw_arc(draw_pos, fallback_radius, 0.0, TAU, 64,
			Color(1.0, 1.0, 1.0, 0.35), 1.0, true)
		var fb_strength: float = _vc_painter.get_brush_strength()
		var fb_inner: float = fallback_radius * fb_strength
		if fb_inner > 1.0:
			overlay.draw_arc(draw_pos, fb_inner, 0.0, TAU, 64,
					Color(1.0, 0.85, 0.35, 0.35), 1.0, true)
		_draw_paint_mode_info(overlay)
		return
	var radius: float = _vc_painter.get_brush_radius()
	var avg_scale: float = (_edited_node.scale.x + _edited_node.scale.y + _edited_node.scale.z) / 3.0
	var local_radius: float = radius / avg_scale if avg_scale > 0.001 else radius
	var local_hit: Vector3 = _edited_node.to_local(world_pos)
	var offset_local: Vector3 = local_hit + Vector3(local_radius, 0.0, 0.0)
	var offset_world: Vector3 = _edited_node.to_global(offset_local)
	var center_screen: Vector2 = camera.unproject_position(world_pos)
	var offset_screen: Vector2 = camera.unproject_position(offset_world)
	var screen_radius: float = (offset_screen - center_screen).length()
	screen_radius = clampf(screen_radius, 4.0, 400.0)
	var color: Color = Color(1.0, 1.0, 1.0, 0.7)
	overlay.draw_arc(draw_pos, screen_radius, 0.0, TAU, 64, color, 1.5, true)
	# Strength inner circle: fills from centre to strength percentage of the radius.
	var strength: float = _vc_painter.get_brush_strength()
	var inner_radius: float = screen_radius * strength
	if inner_radius > 1.0:
		overlay.draw_arc(draw_pos, inner_radius, 0.0, TAU, 64,
				Color(1.0, 0.85, 0.35, 0.55), 1.0, true)
	# Paint mode info label.
	_draw_paint_mode_info(overlay)


## Draw the paint mode info overlay (bottom-left of viewport).
func _draw_paint_mode_info(overlay: Control) -> void:
	if _vc_painter == null or not _vc_painter.is_paint_mode():
		return
	var font: Font = ThemeDB.fallback_font
	var fsize: int = 12
	var m: float = 8.0
	var blend_names: Dictionary = {
		0: "Mix", 1: "Add", 2: "Subtract", 3: "Multiply",
	}
	var blend_id: int = _vc_painter.get_blend_mode()
	var blend_name: String = blend_names.get(blend_id, "Mix")
	var radius_str: String = "R: %.2f" % _vc_painter.get_brush_radius()
	var strength_str: String = "S: %.0f%%" % (_vc_painter.get_brush_strength() * 100.0)
	var line1: String = "Paint | %s | %s | %s" % [blend_name, radius_str, strength_str]
	var line2: String = "Alt+Click=Eyedropper  Alt+S=Size  Alt+D=Strength  Shift+A=Cycle Blend"
	var line3: String = "Alt+Q/W/E/R=Channels  Alt+T=Isolate  Alt+1-5=Target"
	var y: float = overlay.size.y - m - 18.0 - 18.0 - 18.0
	overlay.draw_string(font, Vector2(m + 1.0, y + 1.0), line1,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.0, 0.0, 0.0, 0.55))
	overlay.draw_string(font, Vector2(m, y), line1,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.65, 1.0, 0.65, 0.90))
	overlay.draw_string(font, Vector2(m + 1.0, y + 18.0 + 1.0), line2,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.0, 0.0, 0.0, 0.55))
	overlay.draw_string(font, Vector2(m, y + 18.0), line2,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.65, 0.85, 1.0, 0.75))
	overlay.draw_string(font, Vector2(m + 1.0, y + 36.0 + 1.0), line3,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.0, 0.0, 0.0, 0.55))
	overlay.draw_string(font, Vector2(m, y + 36.0), line3,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.65, 0.85, 1.0, 0.75))


# ---------------------------------------------------------------------------
# Vertex paint brush input handling — delegates to GoBuildVertexPaintBrush
# ---------------------------------------------------------------------------

## Handle mouse events for the vertex paint brush.
## Returns non-zero if the event was consumed.
func _handle_paint_brush(camera: Camera3D, event: InputEvent) -> int:
	if _edited_node == null or _paint_brush == null or _vc_painter == null:
		return 0
	if not _vc_painter.is_paint_mode():
		_paint_brush.clear_cursor()
		return 0
	var result: int = _paint_brush.handle_input(camera, event, _edited_node)
	# Always refresh the overlay in paint mode so the cursor circle updates
	# even when the brush doesn't consume the event (hovering without painting).
	if event is InputEventMouseMotion:
		update_overlays()
	if result != 0:
		update_overlays()
	return result


func _draw_material_drag_hint(overlay: Control) -> void:
	var vp: SubViewport = EditorInterface.get_editor_viewport_3d(0)
	var camera: Camera3D = vp.get_camera_3d() if vp != null else null
	var hint: String = GoBuildMaterialDropConverter.build_drag_hint(
			_edited_node, camera, _drag_mouse_pos,
			_drag_ctrl_held, _drag_cached_material)
	if hint.is_empty():
		return
	var font: Font = ThemeDB.fallback_font
	var fsize: int = 12
	var m: float = 8.0
	var w: float = font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var pos := Vector2(overlay.size.x - w - m, overlay.size.y - m - 18.0)
	overlay.draw_string(font, pos + Vector2(1.0, 1.0), hint,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.0, 0.0, 0.0, 0.55))
	overlay.draw_string(font, pos, hint,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.75, 0.92, 1.0, 0.92))


func _hide_draw_param_strip() -> void:
	if _panel != null:
		var drawer = _panel.get_create_drawer()
		if drawer != null:
			drawer.hide_param_strip()


func _handle_keyboard(event: InputEvent) -> int:
	if not (event is InputEventKey):
		return 0
	var key := event as InputEventKey
	if key.echo:
		return 0
	# Refresh the overlay hint on any Shift / Ctrl / Alt state change.
	# V is consumed below in _handle_action_key so it never reaches native
	# editor physical-mode — but Alt state changes still need overlay refresh.
	match key.keycode:
		KEY_SHIFT, KEY_CTRL, KEY_ALT:
			update_overlays()
			_refresh_panel_context()
			return 0
	if not key.pressed:
		return 0
	if key.keycode == KEY_ESCAPE:
		if _input_controller != null and \
				(_input_controller.has_active_drag() or _input_controller.has_active_press()):
			_input_controller.cancel_drag(_edited_node)
			if _edited_node:
				_edited_node.update_gizmos()
			return 1
	return _handle_keyboard_shortcut(key)


func _handle_keyboard_shortcut(key: InputEventKey) -> int:
	# Mode-switch (1-4) and grow/shrink (Ctrl+=/Ctrl+-) are handled in
	# _handle_mode_switch_in_global via _input so they take priority over
	# Godot's built-in viewport orthographic shortcuts (1-6).
	if _text_input_has_focus():
		return 0
	var handled: int = _handle_action_key(key.keycode)
	if handled != -1:
		return handled
	return 0


## Handle single-key action shortcuts (W/E/R transform modes, Delete/X, M, F).
## Returns 1 if consumed, 0 if passed through, -1 if not matched.
func _handle_action_key(keycode: Key) -> int:
	match keycode:
		KEY_W:             return _set_transform_mode(GoBuildGizmoPlugin.TransformMode.TRANSLATE)
		KEY_E:             return _set_transform_mode(GoBuildGizmoPlugin.TransformMode.ROTATE)
		KEY_R:             return _set_transform_mode(GoBuildGizmoPlugin.TransformMode.SCALE)
		KEY_V:             return _handle_rip_key()
		KEY_N:             return _handle_normal_vis_key()
		KEY_K:             return _handle_knife_key()
	# Element-mode action keys — handled by helpers to keep return count low.
	var result: int = _handle_element_action_key(keycode)
	return result


## K toggles the knife tool when a GoBuild object is edited (Object or Face
## mode — the cut applies to faces under the picked path).  Esc/right-click
## cancels.  Pass through otherwise.
func _handle_knife_key() -> int:
	GoBuildDebug.log("[Knife] _handle_knife_key: edited=%s controller=%s" % [
			str(_edited_node != null), str(_knife_controller != null)])
	if _edited_node == null or _knife_controller == null:
		return 0
	if _knife_controller.is_active():
		_knife_controller.cancel()
	else:
		_knife_controller.start(_edited_node, self)
	update_overlays()
	return 1


## Handle Delete/X/M/F shortcuts that operate on the current element selection.
## Returns 1 if consumed, 0 if passed through, -1 if not matched.
func _handle_element_action_key(keycode: Key) -> int:
	match keycode:
		KEY_DELETE, KEY_X: return _handle_delete_key()
		KEY_M:             return _handle_merge_key()
		KEY_F:             return _handle_bridge_key()
	return -1  # Not a recognised action key.


## Intercept Delete / X in sub-element modes; pass through in Object mode.
func _handle_delete_key() -> int:
	if _edited_node != null and _panel != null \
			and _edited_node.selection.get_mode() != SelectionManager.Mode.OBJECT:
		_panel.trigger_delete()
		return 1
	return 0


## Intercept M in Vertex mode only; pass through in all other modes.
func _handle_merge_key() -> int:
	if _edited_node != null and _panel != null \
			and _edited_node.selection.get_mode() == SelectionManager.Mode.VERTEX:
		_panel.trigger_merge()
		return 1
	return 0


## Intercept F in Edge mode only; triggers Bridge/Fill.  Pass through otherwise.
func _handle_bridge_key() -> int:
	if _edited_node != null and _panel != null \
			and _edited_node.selection.get_mode() == SelectionManager.Mode.EDGE:
		_panel.trigger_bridge()
		return 1
	return 0


## Intercept V in Vertex or Edge mode; triggers Rip.  Pass through otherwise.
func _handle_rip_key() -> int:
	if _edited_node != null and _panel != null \
			and _edited_node.selection.get_mode() != SelectionManager.Mode.OBJECT:
		_panel.trigger_rip()
		return 1
	return 0


## Intercept N; toggles face normal visualiser on/off.
func _handle_normal_vis_key() -> int:
	if _gizmo_plugin == null:
		return 0
	_gizmo_plugin.show_face_normals = not _gizmo_plugin.show_face_normals
	if _edited_node != null:
		_edited_node.update_gizmos()
	return 1


## Intercept = / + in sub-element modes; triggers Grow Selection.
func _set_transform_mode(mode: GoBuildGizmoPlugin.TransformMode) -> int:
	if _gizmo_plugin == null:
		return 0
	if _input_controller != null:
		_input_controller.cancel_drag(_edited_node)
		_input_controller.clear_hover(_edited_node)
	_gizmo_plugin.transform_mode = mode
	if _edited_node:
		_edited_node.update_gizmos()
	update_overlays()
	_refresh_panel_context()
	# W/E/R shortcuts fire via _shortcut_input on the Window root, which runs
	# before _forward_3d_gui_input — so the native W/E/R button may press itself
	# before GoBuild returns 1 to consume the event.  Defer a re-press of V so
	# it fires at the end of this same frame, after all shortcut processing.
	if _edited_node != null \
			and _edited_node.selection.mode != SelectionManager.Mode.OBJECT:
		call_deferred("_suppress_native_gizmo")
	return 1


# ---------------------------------------------------------------------------
# Shortcut initialisation
# ---------------------------------------------------------------------------

func _init_shortcuts() -> void:
	var es := EditorInterface.get_editor_settings()
	_shortcut_object = _require_shortcut(es, _SHORTCUT_OBJECT, KEY_1)
	_shortcut_vertex = _require_shortcut(es, _SHORTCUT_VERTEX, KEY_2)
	_shortcut_edge   = _require_shortcut(es, _SHORTCUT_EDGE,   KEY_3)
	_shortcut_face   = _require_shortcut(es, _SHORTCUT_FACE,   KEY_4)


func _require_shortcut(es: EditorSettings, setting: String, default_key: Key) -> Shortcut:
	if es.has_setting(setting):
		var existing: Variant = es.get_setting(setting)
		if existing is Shortcut:
			return existing as Shortcut
	var ev := InputEventKey.new()
	ev.keycode = default_key
	var sc := Shortcut.new()
	sc.events = [ev]
	es.set_setting(setting, sc)
	es.set_initial_value(setting, sc, false)
	return sc


## Return the shared [GoBuildProjectSettings] resource for this project.
## Used by the panel and operations to access the global palette library.
func get_project_settings() -> GoBuildProjectSettings:
	return _project_settings


## The plugin's gizmo plugin (X-ray mode state etc.) — input controllers
## read it to keep their picking semantics in step with selection.
func get_gizmo_plugin() -> GoBuildGizmoPlugin:
	return _gizmo_plugin


## Toggle X-Ray mode on the gizmo plugin and force all gizmos to redraw.
func set_xray_mode(enabled: bool) -> void:
	if _gizmo_plugin != null:
		_gizmo_plugin.xray_mode = enabled
	if _edited_node != null:
		_edited_node.update_gizmos()


func set_show_face_normals(enabled: bool) -> void:
	if _gizmo_plugin != null:
		_gizmo_plugin.show_face_normals = enabled
	if _edited_node != null:
		_edited_node.update_gizmos()


func set_show_vertex_normals(enabled: bool) -> void:
	if _gizmo_plugin != null:
		_gizmo_plugin.show_vertex_normals = enabled
	if _edited_node != null:
		_edited_node.update_gizmos()


func switch_mode(mode: SelectionManager.Mode) -> void:
	_set_mode(mode)


func _set_mode(mode: SelectionManager.Mode) -> void:
	if _edited_node == null:
		return
	GoBuildDebug.log("[GoBuild] PLUGIN._set_mode  mode=%d  node=%s" % [mode, _edited_node.name])
	_edited_node.selection.set_mode(mode)
	_edited_node.update_gizmos()


# ---------------------------------------------------------------------------
# Overlay hint
# ---------------------------------------------------------------------------

func _draw_mode_hint(overlay: Control) -> void:
	if _edited_node == null or _gizmo_plugin == null:
		return
	var hint: String = _build_overlay_hint()
	if hint.is_empty():
		return
	var font: Font = ThemeDB.fallback_font
	var fsize: int = 12
	var m: float   = 8.0
	var pos := Vector2(m, overlay.size.y - m)
	overlay.draw_string(font, pos + Vector2(1.0, 1.0), hint,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.0, 0.0, 0.0, 0.55))
	overlay.draw_string(font, pos, hint,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.9, 0.9, 0.9, 0.85))


## Draw the active parameter-preview label in the viewport overlay.
## Shown in place of the mode-hint when a parameter-preview is active.
func _draw_param_preview_hint(overlay: Control) -> void:
	if _input_controller == null:
		return
	var hint: String = _input_controller.get_param_preview_overlay_text()
	if hint.is_empty():
		return
	var font: Font = ThemeDB.fallback_font
	var fsize: int = 13
	var m: float   = 8.0
	var pos := Vector2(m, overlay.size.y - m)
	overlay.draw_string(font, pos + Vector2(1.0, 1.0), hint,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.0, 0.0, 0.0, 0.60))
	overlay.draw_string(font, pos, hint,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(1.0, 0.85, 0.3, 0.95))


## Draw the unified controller overlay in the viewport.
## For param mode: draws the directional indicator (anchor, line, cursor) and
## the parameter value text.
## For gizmo mode: draws the drag value text (delta, angle, scale ratio).
func _draw_controller_overlay(overlay: Control) -> void:
	if _drag_controller == null:
		return
	var data: Dictionary = _drag_controller.get_overlay_data()
	if data.is_empty():
		return
	if _drag_controller.is_param_mode():
		_draw_controller_param_overlay(overlay, data)
	else:
		_draw_controller_gizmo_overlay(overlay)


## Localized snap grid: light line grid on the drag plane around the drag
## centroid, cell = current snap step.  Visible only while Ctrl is held
## during a translate-type gizmo drag.
func _draw_snap_grid(overlay: Control) -> bool:
	if not _mod_ctrl or _drag_controller == null:
		return false
	var cam: Camera3D = _drag_controller.get_cached_camera()
	if cam == null:
		return false
	var grid: Dictionary = _drag_controller.get_snap_grid_data()
	if grid.is_empty():
		return false
	var origin: Vector3 = grid["origin"]
	var step: float = grid["step"]
	var basis: Basis = grid.get("basis", Basis.IDENTITY)
	# Noise-free panels: per basis axis, a ±2-step panel spanned by the
	# other two axes — bright axis-coloured centre lines plus small dim
	# crosses at the lattice points.
	const RADIUS := 2
	const CROSS := 4.0
	const AXES: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	const COLS: Array[Color] = [
		Color(0.86, 0.20, 0.15, 0.60),  # X red
		Color(0.20, 0.75, 0.25, 0.60),  # Y green
		Color(0.20, 0.35, 0.90, 0.60),  # Z blue
	]
	const COL_AXIS: Array[Color] = [
		Color(0.95, 0.35, 0.30, 0.95),
		Color(0.35, 0.95, 0.40, 0.95),
		Color(0.40, 0.55, 1.00, 0.95),
	]
	var extent: float = float(RADIUS) * step
	for axis_idx: int in 3:
		var other_a: Vector3 = basis * AXES[(axis_idx + 1) % 3]
		var other_b: Vector3 = basis * AXES[(axis_idx + 2) % 3]
		var col_a: Color = COLS[(axis_idx + 1) % 3]
		var col_b: Color = COLS[(axis_idx + 2) % 3]
		var axis_a: Color = COL_AXIS[(axis_idx + 1) % 3]
		var axis_b: Color = COL_AXIS[(axis_idx + 2) % 3]
		# Centre lines through the origin (bright, axis-coloured).
		var cl1: Vector3 = origin - other_a * extent
		var cl2: Vector3 = origin + other_a * extent
		if not cam.is_position_behind(cl1) and not cam.is_position_behind(cl2):
			overlay.draw_line(
					cam.unproject_position(cl1),
					cam.unproject_position(cl2), axis_a, 1.0)
		var cl3: Vector3 = origin - other_b * extent
		var cl4: Vector3 = origin + other_b * extent
		if not cam.is_position_behind(cl3) and not cam.is_position_behind(cl4):
			overlay.draw_line(
					cam.unproject_position(cl3),
					cam.unproject_position(cl4), axis_b, 1.0)
		# Interior crosses at the lattice points (plain white, as before).
		for i: int in range(-RADIUS, RADIUS + 1):
			for j: int in range(-RADIUS, RADIUS + 1):
				if i == 0 and j == 0:
					continue
				var p: Vector3 = origin + other_a * (float(i) * step) \
						+ other_b * (float(j) * step)
				if cam.is_position_behind(p):
					continue
				var sp: Vector2 = cam.unproject_position(p)
				overlay.draw_line(sp + Vector2(-CROSS, 0),
						sp + Vector2(CROSS, 0), Color(1, 1, 1, 0.55), 1.0)
				overlay.draw_line(sp + Vector2(0, -CROSS),
						sp + Vector2(0, CROSS), Color(1, 1, 1, 0.55), 1.0)
	return true


func _draw_controller_param_overlay(overlay: Control, data: Dictionary) -> void:
	var anchor: Vector2 = data.get("anchor", Vector2.ZERO)
	var indicator: Vector2 = data.get("indicator_pos", data.get("virtual_pos", Vector2.ZERO))
	var param: float = data.get("param", 0.0)
	var param_start: float = data.get("param_start", param)
	var m := 8.0
	var clamped := Vector2(
			clampf(indicator.x, m, overlay.size.x - m),
			clampf(indicator.y, m, overlay.size.y - m))
	var col_pos  := Color(0.25, 0.85, 0.35, 0.90)
	var col_neg  := Color(0.90, 0.30, 0.25, 0.90)
	var col_line := col_pos if param >= param_start else col_neg
	var col_shad := Color(0.0, 0.0, 0.0, 0.55)
	overlay.draw_line(Vector2(anchor.x, 0.0), Vector2(anchor.x, overlay.size.y),
			Color(1.0, 1.0, 1.0, 0.12), 1.0)
	overlay.draw_line(Vector2(0.0, anchor.y), Vector2(overlay.size.x, anchor.y),
			Color(1.0, 1.0, 1.0, 0.08), 1.0)
	overlay.draw_line(anchor, clamped, col_shad, 4.0)
	overlay.draw_line(anchor, clamped, col_line, 2.5)
	overlay.draw_circle(anchor, 5.5, col_shad)
	overlay.draw_circle(anchor, 4.5, Color.WHITE)
	overlay.draw_circle(anchor, 3.0, Color(0.15, 0.15, 0.15))
	overlay.draw_circle(clamped, 7.5, col_shad)
	overlay.draw_circle(clamped, 6.5, col_line)
	overlay.draw_circle(clamped, 3.5, Color.WHITE)
	var hint: String = _drag_controller.get_overlay_text()
	if not hint.is_empty():
		var font: Font = ThemeDB.fallback_font
		var fsize: int = 13
		var pos := Vector2(m, overlay.size.y - m)
		overlay.draw_string(font, pos + Vector2(1.0, 1.0), hint,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.0, 0.0, 0.0, 0.60))
		overlay.draw_string(font, pos, hint,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(1.0, 0.85, 0.3, 0.95))


func _draw_controller_gizmo_overlay(overlay: Control) -> void:
	if _drag_controller == null:
		return
	var text: String = _drag_controller.get_overlay_text()
	if text.is_empty():
		return
	var precision: bool = _mod_shift
	var text_color: Color = Color(0.5, 0.85, 1.0, 0.92) if precision \
			else Color(1.0, 0.92, 0.4, 0.90)
	var font: Font = ThemeDB.fallback_font
	var fsize: int = 12
	var m: float   = 8.0
	var pos := Vector2(m, overlay.size.y - m - 18.0)
	overlay.draw_string(font, pos + Vector2(1.0, 1.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.0, 0.0, 0.0, 0.55))
	overlay.draw_string(font, pos, text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, text_color)
	if precision:
		var prec_text := "PRECISION"
		overlay.draw_string(font, pos + Vector2(0.0, -14.0) + Vector2(1.0, 1.0), prec_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.0, 0.0, 0.0, 0.45))
		overlay.draw_string(font, pos + Vector2(0.0, -14.0), prec_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, text_color)


func _build_overlay_hint() -> String:
	if _edited_node == null or _gizmo_plugin == null:
		return ""
	return OverlayHintHelper.build_hint(
			_edited_node.selection.get_mode(),
			_gizmo_plugin.transform_mode,
			_mod_shift,
			_mod_ctrl)


## Draw the selection dimensions label in the bottom-right of the overlay.
## Shows edge length (single edge), or bounding-box extents (multi-select or faces),
## or vertex distance / bounding-box extents (vertex selection).
func _draw_selection_dims(overlay: Control) -> void:
	var text: String = _build_selection_dims()
	if text.is_empty():
		return
	var font: Font = ThemeDB.fallback_font
	var fsize: int = 12
	var m: float   = 8.0
	# Measure width so we can right-align without a RichTextLabel node.
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var pos := Vector2(overlay.size.x - w - m, overlay.size.y - m)
	overlay.draw_string(font, pos + Vector2(1.0, 1.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.0, 0.0, 0.0, 0.55))
	overlay.draw_string(font, pos, text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.65, 1.0, 0.65, 0.90))


## Build a human-readable dimension string for the current selection.
## Returns an empty string when in Object mode or nothing is selected.
func _build_selection_dims() -> String:
	if _edited_node == null or not is_instance_valid(_edited_node):
		return ""
	if _edited_node.go_build_mesh == null:
		return ""
	return SelectionDimsHelper.build(
			_edited_node.go_build_mesh,
			_edited_node.selection,
			_edited_node.global_transform)

## Return a short operation name for the panel context label.
## Mirrors [method _build_overlay_hint] but returns only the active operation
## (no mode prefix, no shortcut hints).
func _build_panel_context() -> String:
	if _edited_node == null or _gizmo_plugin == null:
		return ""
	return OverlayHintHelper.build_panel_context(
			_edited_node.selection.get_mode(),
			_gizmo_plugin.transform_mode,
			_mod_shift,
			_mod_ctrl,
			_mod_alt)


## Push the current panel context label text to the panel.
func _refresh_panel_context() -> void:
	if _panel == null:
		return
	_panel.update_context(_build_panel_context())


## Enter parameter-preview mode for the given operation.
## Called from [GoBuildPanel] via [code]_plugin.call("begin_param_preview", preview)[/code].
## Takes a mesh snapshot, optionally scales sensitivity by gizmo scale, creates
## a [GoBuildDragOperation] from the legacy [GoBuildParamPreview], and passes it
## to the [GoBuildDragController].
func begin_param_preview(preview: GoBuildParamPreview) -> void:
	if _input_controller == null or _edited_node == null or _gizmo_plugin == null:
		return
	preview.node     = _edited_node
	preview.snapshot = _edited_node.go_build_mesh.take_snapshot()
	if preview.scale_by_gizmo:
		var s: float = _gizmo_plugin.compute_node_gizmo_scale(_edited_node)
		preview.units_per_pixel *= s

	var op := GoBuildDragOperation.new()
	op.node = _edited_node
	op.snapshot = preview.snapshot
	op.apply_fn = preview.apply_fn
	op.action_name = preview.action_name
	op.overlay_label = preview.param_label
	op.delta_mode = GoBuildDragOperation.DeltaMode.PARAM_LINEAR if not preview.radial \
			else GoBuildDragOperation.DeltaMode.PARAM_RADIAL
	op.param = preview.param_start
	op.param_start = preview.param_start
	op.param_min = preview.param_min
	op.param_max = preview.param_max
	op.units_per_pixel = preview.units_per_pixel
	op.scale_by_gizmo = preview.scale_by_gizmo
	op.snap_to_start = preview.snap_to_start
	op.snap_threshold = preview.snap_threshold
	op.snap_step = preview.snap_step
	op.screen_direction = preview.screen_direction
	op.post_commit_fn = preview.post_commit_fn
	op.preview_mode = true

	_drag_controller.begin_with_initial_apply(op)
	_input_controller.begin_param_preview(preview, _edited_node)
	_refresh_panel_context()
	update_overlays()


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_selection_changed() -> void:
	if _edited_node:
		_edited_node.update_gizmos()
	update_overlays()
	if _uv_panel:
		_uv_panel.refresh()
	if _vc_painter:
		_vc_painter.refresh()


func _on_mesh_changed() -> void:
	update_overlays()


func _on_snap_selected(index: int) -> void:
	if _gizmo_plugin == null:
		return
	_snap_menu_translate_idx = index
	_gizmo_plugin.snap_step_override = _SNAP_PRESETS[index]
	if _shape_draw_controller != null:
		_shape_draw_controller.set_snap_step(_SNAP_PRESETS[index])
	_update_snap_summary()


func _on_rot_snap_selected(index: int) -> void:
	if _gizmo_plugin == null:
		return
	_snap_menu_rot_idx = index
	var deg: float = _ROT_SNAP_PRESETS[index]
	_gizmo_plugin.rot_snap_override = deg
	_update_snap_summary()


func _on_scale_snap_selected(index: int) -> void:
	if _gizmo_plugin == null:
		return
	_snap_menu_scale_idx = index
	_gizmo_plugin.scale_snap_override = _SCALE_SNAP_PRESETS[index]
	_update_snap_summary()


func _on_snap_mode_selected(index: int) -> void:
	if _gizmo_plugin == null:
		return
	_snap_menu_mode_idx = index
	_gizmo_plugin.snap_mode_override = index
	_update_snap_summary()


func _on_transform_space_selected(index: int) -> void:
	if _gizmo_plugin == null:
		return
	_gizmo_plugin.transform_space = index
	if _edited_node:
		_edited_node.update_gizmos()


## Lazy-built popup with one enum dropdown per snap setting.
func _on_snap_settings_pressed() -> void:
	if _gizmo_plugin == null:
		return
	if _snap_settings_popup != null:
		_snap_settings_popup.hide()
		return
	var panel := GridContainer.new()
	panel.columns = 2

	panel.add_child(_make_setting_row_label("Snap Mode"))
	var mode_btn := _make_snap_option_button(
			_SNAP_MODE_LABELS, _snap_menu_mode_idx, _on_snap_mode_selected)
	panel.add_child(mode_btn)

	panel.add_child(_make_setting_row_label("Translate"))
	var translate_btn := _make_snap_option_button(
			_SNAP_LABELS, _current_translate_idx(), _on_snap_selected)
	panel.add_child(translate_btn)

	panel.add_child(_make_setting_row_label("Rotation"))
	var rot_btn := _make_snap_option_button(
			_ROT_SNAP_LABELS, _snap_menu_rot_idx, _on_rot_snap_selected)
	panel.add_child(rot_btn)

	panel.add_child(_make_setting_row_label("Scale"))
	var scale_btn := _make_snap_option_button(
			_SCALE_SNAP_LABELS, _snap_menu_scale_idx, _on_scale_snap_selected)
	panel.add_child(scale_btn)

	# Divider + spanning action row: snap the selection to the grid
	# (per-vertex, deforming — ProBuilder "Snap Selection to Grid").
	panel.columns = 1
	var divider := HSeparator.new()
	divider.modulate.a = 0.5
	panel.add_child(divider)
	var snap_action := Button.new()
	snap_action.text = "Snap Selection to Grid"
	snap_action.tooltip_text = (
			"Snap each selected vertex to its nearest grid cell in world"
			+ " space.\nDeforming: repairs off-grid geometry (topology"
			+ " unchanged).\nStep: the current Translate snap step.")
	snap_action.pressed.connect(_on_snap_selection_to_grid)
	panel.add_child(snap_action)

	var wrap := PanelContainer.new()
	wrap.add_child(panel)
	_snap_settings_popup = PopupPanel.new()
	_snap_settings_popup.add_child(wrap)
	_snap_settings_popup.popup_hide.connect(
			func() -> void:
				_snap_settings_popup.queue_free()
				_snap_settings_popup = null)
	_toolbar.add_child(_snap_settings_popup)
	# Anchor just below the Snap button; PopupPanel auto-closes on
	# outside clicks and stays open for clicks inside (incl. dropdowns).
	# get_global_rect is SubViewport-local; get_screen_position gives
	# OS-window coords so multi-monitor windows land correctly (same
	# conversion the right-click context menu uses).
	var btn_pos: Vector2 = _snap_settings_btn.get_screen_position()
	_snap_settings_popup.reset_size()
	_snap_settings_popup.position = btn_pos + Vector2(
			0.0, _snap_settings_btn.size.y + 2.0)
	_snap_settings_popup.popup()


## Snap every selected vertex to its nearest world-grid cell
## (deforming, ProBuilder "Snap Selection to Grid").  Undoable.
func _on_snap_selection_to_grid() -> void:
	if _edited_node == null or _edited_node.go_build_mesh == null:
		return
	var mesh: GoBuildMesh = _edited_node.go_build_mesh
	# Verts of the selection: direct vertex picks plus every vertex of
	# every picked edge / face (deforming repair on element selections).
	var verts: Array[int] = _edited_node.selection.get_selected_vertices()
	var seen: Dictionary = {}
	for v: int in verts:
		seen[v] = true
	for ei: int in _edited_node.selection.get_selected_edges():
		var edge: GoBuildEdge = mesh.edges[ei]
		for v: int in [edge.vertex_a, edge.vertex_b]:
			if not seen.has(v):
				seen[v] = true
				verts.append(v)
	for fi: int in _edited_node.selection.get_selected_faces():
		for v: int in mesh.faces[fi].vertex_indices:
			if not seen.has(v):
				seen[v] = true
				verts.append(v)
	if verts.is_empty():
		return
	var step: float = _TRANSFORM_HELPERS.get_snap_step(
			_gizmo_plugin.snap_step_override)
	var xform: Transform3D = _edited_node.global_transform
	_edited_node.apply_operation("Snap Selection to Grid",
			func() -> void:
				SnapToGridOperation.apply(mesh, verts, xform, step),
			get_undo_redo())


func _make_setting_row_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _make_snap_option_button(labels: Array[String], active: int,
		handler: Callable) -> OptionButton:
	var button := OptionButton.new()
	for label: String in labels:
		button.add_item(label)
	button.select(active)
	button.item_selected.connect(handler)
	return button


## Translate step index; the -1 preset (Editor grid) shows as "Editor".
func _current_translate_idx() -> int:
	var idx: int = _SNAP_PRESETS.find(_gizmo_plugin.snap_step_override)
	return idx if idx >= 0 else 0


## Read-only summary of the current snap settings, e.g.
## "Hybrid · 1 m · R15° · S0.1" (gizmo Space lives on its own control).
func _update_snap_summary() -> void:
	if _snap_settings_label == null:
		return
	_snap_settings_label.text = "%s · %s · R%s° · S%s" % [
			_SNAP_MODE_LABELS[_snap_menu_mode_idx],
			_SNAP_LABELS[_snap_menu_translate_idx],
			_ROT_SNAP_LABELS[_snap_menu_rot_idx],
			_SCALE_SNAP_LABELS[_snap_menu_scale_idx]]


func _on_mode_changed(mode: SelectionManager.Mode) -> void:
	GoBuildDebug.log("[GoBuild] PLUGIN._on_mode_changed  mode=%d  edited_null=%s" \
			% [mode, str(_edited_node == null)])
	if _input_controller != null:
		_input_controller.cancel_drag(_edited_node)
		if _drag_controller != null:
			_drag_controller.cancel()
		_input_controller.clear_hover(_edited_node)
		_input_controller.cancel_box_select(_edited_node)
	_sync_toolbar_mode_buttons()
	_refresh_panel_context()
	if mode != SelectionManager.Mode.OBJECT:
		_was_in_edit_mode = true
		call_deferred("_suppress_native_gizmo")
	else:
		if _was_in_edit_mode and _tool_pinner != null and _gizmo_plugin != null:
			_tool_pinner.restore_native_tool_mode(_gizmo_plugin.transform_mode)
		_was_in_edit_mode = false


func _on_edited_node_removed() -> void:
	if _input_controller != null:
		_input_controller.cancel_drag(null)
		_input_controller.cancel_box_select(null)
	_cleanup_drag_state()
	_edited_node = null
	if _panel:
		_panel.set_target(null)
	if _uv_panel:
		_uv_panel.set_target(null)
	if _vc_painter:
		_vc_painter.set_target(null)
	update_overlays()


func _disconnect_node_signals() -> void:
	if _edited_node == null:
		return
	if _edited_node.selection.selection_changed.is_connected(_on_selection_changed):
		_edited_node.selection.selection_changed.disconnect(_on_selection_changed)
	if _edited_node.selection.mode_changed.is_connected(_on_mode_changed):
		_edited_node.selection.mode_changed.disconnect(_on_mode_changed)
	if _edited_node.tree_exiting.is_connected(_on_edited_node_removed):
		_edited_node.tree_exiting.disconnect(_on_edited_node_removed)
	if _edited_node.mesh_changed.is_connected(_on_mesh_changed):
		_edited_node.mesh_changed.disconnect(_on_mesh_changed)


# ---------------------------------------------------------------------------
# Native gizmo suppression — delegates to Node3DEditorToolPinner
# ---------------------------------------------------------------------------

## Delegates to [member _tool_pinner] to press the Physical/V button once.
## Called deferred from mode-change handlers and [method _set_transform_mode].
func _suppress_native_gizmo() -> void:
	if _tool_pinner != null:
		_tool_pinner.suppress()
