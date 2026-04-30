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
const _SMOOTH_GRP_SCRIPT := \
		preload("res://addons/go_build/mesh/operations/smooth_group_operation.gd")
const _AUTO_SMOOTH_SCRIPT := \
		preload("res://addons/go_build/mesh/operations/auto_smooth_operation.gd")
const _HARD_EDGE_SCRIPT := \
		preload("res://addons/go_build/mesh/operations/hard_edge_operation.gd")
const _DELETE_SCRIPT   := preload("res://addons/go_build/mesh/operations/delete_operation.gd")
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
const _INSET_SCRIPT := \
		preload("res://addons/go_build/mesh/operations/inset_operation.gd")
const _FACE_SCRIPT := \
		preload("res://addons/go_build/mesh/go_build_face.gd")
const _SHAPE_CATALOG_SCRIPT := \
		preload("res://addons/go_build/mesh/generators/shape_creation_catalog.gd")
const _PARAM_PREVIEW_SCRIPT := \
		preload("res://addons/go_build/core/go_build_param_preview.gd")
const _SHAPE_PREVIEW_SCRIPT := \
		preload("res://addons/go_build/core/go_build_shape_preview.gd")
const _SETTINGS_SCRIPT := \
		preload("res://addons/go_build/core/go_build_project_settings.gd")
const _MATERIALS_DRAWER_SCRIPT := \
		preload("res://addons/go_build/core/go_build_materials_drawer.gd")
const _UV_DRAWER_SCRIPT := \
		preload("res://addons/go_build/core/go_build_uv_drawer.gd")
const _VERTEX_DRAWER_SCRIPT := \
		preload("res://addons/go_build/core/go_build_vertex_drawer.gd")

const _PLUGIN_CFG_PATH := "res://addons/go_build/plugin.cfg"

## Default extrude distance in local mesh units.
const _EXTRUDE_DEFAULT_DISTANCE: float = 0.5

## Default edge extrude width in local mesh units.
const _EDGE_EXTRUDE_DEFAULT_WIDTH: float = 0.5

## Default bevel width in local mesh units.
const _BEVEL_DEFAULT_WIDTH: float = 0.01

## Default inset amount (0–1 blend toward centroid).
const _INSET_DEFAULT_AMOUNT: float = 0.1

var _status_label: Label
var _stats_label: Label
var _mode_buttons: Array[Button] = []
var _extrude_btn: Button       = null
var _inset_btn: Button         = null
var _flip_btn: Button          = null
var _smooth_group_spin: SpinBox = null
var _assign_smooth_btn: Button = null
var _flat_btn: Button          = null
var _smooth_btn: Button        = null
var _extrude_edge_btn: Button  = null
var _bevel_btn: Button         = null
var _bridge_btn: Button        = null
var _subdivide_btn: Button     = null
var _hard_edge_btn: Button     = null
var _soft_edge_btn: Button     = null
var _loop_cut_btn: Button      = null
var _delete_btn: Button        = null
var _cull_check: CheckBox      = null
var _auto_uv_option: OptionButton = null
var _shape_preview: GoBuildShapePreview = null

## Collapsible section drawers (Array-style). [0] = header Button, [1] = content VBoxContainer.
var _drawer_create:  Array = []
var _drawer_edge:    Array = []
var _drawer_face:    Array = []
var _drawer_surface: Array = []
var _drawer_general: Array = []

## Extracted subcomponent drawers.
var _vertex_drawer:    GoBuildVertexDrawer    = null
var _materials_drawer: GoBuildMaterialsDrawer = null
var _uv_drawer:        GoBuildUvDrawer        = null

## Auto Smooth controls (Surface drawer).
var _auto_smooth_angle_spin: SpinBox = null
var _auto_smooth_btn:        Button  = null

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
	if _vertex_drawer != null:
		_vertex_drawer.set_plugin(plugin)
	if _materials_drawer != null:
		_materials_drawer.set_plugin(plugin)
	if _uv_drawer != null:
		_uv_drawer.set_plugin(plugin)


## Called by the owning [EditorPlugin] after project settings are loaded.
## Populates the palette dropdown from the project-wide palette library.
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
	custom_minimum_size = Vector2(180, 0)

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

	# ── Create Shape ─────────────────────────────────────────────────────
	_drawer_create = _make_drawer("Create Shape", true)
	var grid := GridContainer.new()
	grid.columns = 2
	_drawer_create[1].add_child(grid)

	for shape_name: String in ShapeCreationCatalog.all_shapes():
		var btn := Button.new()
		btn.text = shape_name
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_shape_button_pressed.bind(shape_name))
		grid.add_child(btn)

	_shape_preview = GoBuildShapePreview.new()
	_shape_preview.accepted.connect(_on_shape_preview_accepted)
	_shape_preview.cancelled.connect(_on_shape_preview_cancelled)
	_drawer_create[1].add_child(_shape_preview)

	# ── Modelling Operations ──────────────────────────────────────────────
	# Vertex
	_vertex_drawer = GoBuildVertexDrawer.new()
	add_child(_vertex_drawer)

	_drawer_edge = _make_drawer("Edge")
	var edge_grid := GridContainer.new()
	edge_grid.columns = 2
	_drawer_edge[1].add_child(edge_grid)

	_extrude_edge_btn = _op_button("Extrude",
		"Extrude selected boundary edge(s) into new quad faces (Shift+drag).\n"
		+ "Requires Edge mode with ≥1 boundary edge selected.")
	_extrude_edge_btn.pressed.connect(_on_extrude_edge_pressed)
	edge_grid.add_child(_extrude_edge_btn)
	_register_op(_extrude_edge_btn, _cond_edge_any)

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

	_hard_edge_btn = _op_button("Hard",
		"Mark selected edge(s) as hard: adjacent faces will not average normals\n"
		+ "across the edge even if they share the same smooth group.\n"
		+ "Requires Edge mode with \u22651 edge selected.")
	_hard_edge_btn.pressed.connect(_on_hard_edge_pressed)
	edge_grid.add_child(_hard_edge_btn)
	_register_op(_hard_edge_btn, _cond_edge_any)

	_soft_edge_btn = _op_button("Soft",
		"Clear the hard-edge flag on selected edge(s): adjacent faces with the\n"
		+ "same smooth group will resume averaging normals.\n"
		+ "Requires Edge mode with \u22651 edge selected.")
	_soft_edge_btn.pressed.connect(_on_soft_edge_pressed)
	edge_grid.add_child(_soft_edge_btn)
	_register_op(_soft_edge_btn, _cond_edge_any)

	_drawer_face = _make_drawer("Face")
	var face_grid := GridContainer.new()
	face_grid.columns = 2
	_drawer_face[1].add_child(face_grid)

	_extrude_btn = _op_button("Extrude",
		"Extrude selected face(s) by %.2f units along their normal.\n" % _EXTRUDE_DEFAULT_DISTANCE
		+ "Requires Face mode with ≥1 face selected.")
	_extrude_btn.pressed.connect(_on_extrude_pressed)
	face_grid.add_child(_extrude_btn)
	_register_op(_extrude_btn, _cond_face_any)

	_inset_btn = _op_button("Inset",
		"Inset selected face(s) toward their centroid (0 = none, 1 = collapse).\n"
		+ "Drag to adjust amount. Requires Face mode with ≥1 face selected.")
	_inset_btn.pressed.connect(_on_inset_pressed)
	face_grid.add_child(_inset_btn)
	_register_op(_inset_btn, _cond_face_any)

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

	_uv_drawer = GoBuildUvDrawer.new()
	add_child(_uv_drawer)

	_drawer_surface = _make_drawer("Surface")

	var surface_grid := GridContainer.new()
	surface_grid.columns = 2
	_drawer_surface[1].add_child(surface_grid)

	var sg_lbl := Label.new()
	sg_lbl.text = "Group:"
	sg_lbl.add_theme_font_size_override("font_size", 11)
	surface_grid.add_child(sg_lbl)

	_smooth_group_spin = SpinBox.new()
	_smooth_group_spin.min_value = 0
	_smooth_group_spin.max_value = 31
	_smooth_group_spin.step = 1
	_smooth_group_spin.rounded = true
	_smooth_group_spin.value = 1
	_smooth_group_spin.tooltip_text = (
		"Smooth group ID to assign.  0 = flat-shaded (no smoothing).\n"
		+ "Faces sharing the same non-zero ID average normals at shared vertices."
	)
	_smooth_group_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	surface_grid.add_child(_smooth_group_spin)

	_assign_smooth_btn = _op_button("Assign",
		"Set selected face(s) to the smooth group shown in the Group spinner.\n"
		+ "Faces in the same non-zero group share averaged normals (smooth shading).\n"
		+ "Requires Face mode with ≥1 face selected.")
	_assign_smooth_btn.pressed.connect(_on_assign_smooth_group_pressed)
	surface_grid.add_child(_assign_smooth_btn)
	_register_op(_assign_smooth_btn, _cond_face_any)

	# Spacer to complete the two-column row.
	surface_grid.add_child(Control.new())

	var sg_quick_grid := GridContainer.new()
	sg_quick_grid.columns = 2
	_drawer_surface[1].add_child(sg_quick_grid)

	_flat_btn = _op_button("Flat",
		"Set selected face(s) to smooth group 0 (flat shading — each face uses\n"
		+ "its own face normal, no interpolation with neighbours).\n"
		+ "Requires Face mode with ≥1 face selected.")
	_flat_btn.pressed.connect(_on_flat_shading_pressed)
	sg_quick_grid.add_child(_flat_btn)
	_register_op(_flat_btn, _cond_face_any)

	_smooth_btn = _op_button("Smooth",
		"Set selected face(s) to smooth group 1, enabling normal averaging with\n"
		+ "all adjacent faces that also belong to group 1.\n"
		+ "Requires Face mode with ≥1 face selected.")
	_smooth_btn.pressed.connect(_on_smooth_shading_pressed)
	sg_quick_grid.add_child(_smooth_btn)
	_register_op(_smooth_btn, _cond_face_any)

	# Auto Smooth row — angle threshold spinner + button.
	var as_row := HBoxContainer.new()
	_drawer_surface[1].add_child(as_row)

	_auto_smooth_angle_spin = SpinBox.new()
	_auto_smooth_angle_spin.min_value = 1.0
	_auto_smooth_angle_spin.max_value = 180.0
	_auto_smooth_angle_spin.step = 1.0
	_auto_smooth_angle_spin.value = 30.0
	_auto_smooth_angle_spin.suffix = "\u00b0"
	_auto_smooth_angle_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_auto_smooth_angle_spin.tooltip_text = (
			"Angle threshold for Auto Smooth.\n"
			+ "Adjacent faces below this angle share averaged normals;\n"
			+ "wider angles form hard creases.  30\u00b0 matches Blender's default."
	)
	as_row.add_child(_auto_smooth_angle_spin)

	_auto_smooth_btn = _op_button("Auto Smooth",
			"Assign smooth groups to ALL faces based on the dihedral angle threshold.\n"
			+ "No face selection needed — the entire mesh is processed at once.\n"
			+ "Pairs of adjacent faces below the threshold share averaged normals;\n"
			+ "faces at or above the threshold get a hard crease.\n"
			+ "Requires a mesh to be selected.")
	_auto_smooth_btn.pressed.connect(_on_auto_smooth_pressed)
	as_row.add_child(_auto_smooth_btn)
	_register_op(_auto_smooth_btn, _cond_has_mesh)
	_materials_drawer = GoBuildMaterialsDrawer.new()
	add_child(_materials_drawer)

	_drawer_general = _make_drawer("General", true)

	var general_grid := GridContainer.new()
	general_grid.columns = 2
	_drawer_general[1].add_child(general_grid)

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
	_drawer_general[1].add_child(dbg_toggle)

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
	_drawer_general[1].add_child(_cull_check)

	# ── Auto UV mode selector ─────────────────────────────────────────────
	# Replaces the old boolean checkbox with a per-projection-type dropdown.
	# "None" disables automatic re-projection after every operation.
	# "Planar" and "Box" project all unoverridden faces after each operation.
	var uv_row := HBoxContainer.new()
	_drawer_general[1].add_child(uv_row)

	var uv_lbl := Label.new()
	uv_lbl.text = "Auto UV:"
	uv_lbl.add_theme_font_size_override("font_size", 11)
	uv_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	uv_row.add_child(uv_lbl)

	_auto_uv_option = OptionButton.new()
	_auto_uv_option.flat = true
	_auto_uv_option.add_item("None",     GoBuildFace.UvMode.NONE)
	_auto_uv_option.add_item("Planar",   GoBuildFace.UvMode.PLANAR)
	_auto_uv_option.add_item("Box",      GoBuildFace.UvMode.BOX)
	_auto_uv_option.add_item("Cylinder", GoBuildFace.UvMode.CYLINDRICAL)
	_auto_uv_option.add_item("Sphere",   GoBuildFace.UvMode.SPHERICAL)
	_auto_uv_option.add_theme_font_size_override("font_size", 11)
	_auto_uv_option.tooltip_text = (
		"Automatically re-project UVs after every operation.\n"
		+ "None     — disabled; preserves any hand-edited UVs.\n"
		+ "Planar   — per-face dominant-axis projection (best for simple shapes).\n"
		+ "Box      — world-space box projection; adjacent faces share UV coords.\n"
		+ "Cylinder — cylindrical wrap around Y axis; U = angle, V = height.\n"
		+ "Sphere   — equirectangular (lat/lon) projection; U = longitude, V = latitude."
	)
	_auto_uv_option.item_selected.connect(_on_auto_uv_mode_selected)
	uv_row.add_child(_auto_uv_option)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Update the panel to reflect [param target].
## Pass [code]null[/code] to clear the selection display.
func set_target(target: GoBuildMeshInstance) -> void:
	# Cancel any active UV param preview before switching targets.
	if _uv_drawer != null:
		_uv_drawer.cancel_preview()

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
	if _vertex_drawer != null:
		_vertex_drawer.set_target(target)
	if _materials_drawer != null:
		_materials_drawer.set_target(target)
	if _uv_drawer != null:
		_uv_drawer.set_target(target)

	if _target != null:
		_target.selection.mode_changed.connect(_on_target_mode_changed)
		_target.selection.selection_changed.connect(_update_ops_buttons)
		_target.mesh_changed.connect(_refresh)
		_sync_mode_buttons(_target.selection.get_mode())
		# Apply the current checkbox state so the new node matches immediately.
		if _cull_check != null:
			_target.set_edit_cull_override(_cull_check.button_pressed)
		if _auto_uv_option != null:
			_auto_uv_option.selected = _target.auto_uv_mode
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
	if _vertex_drawer != null:
		_vertex_drawer.trigger_merge()


## Called by external code (e.g. the right-click context menu)
## to weld (merge by distance) vertices in the current mesh.
## Equivalent to pressing the Weld panel button.
func trigger_weld() -> void:
	if _vertex_drawer != null:
		_vertex_drawer.trigger_weld()


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


## Called by external code (e.g. the face context menu)
## to project planar UVs onto the current face selection.
func trigger_planar_uv() -> void:
	if _uv_drawer != null:
		_uv_drawer.trigger_planar_uv()


## Called by external code (e.g. the right-click context menu)
## to apply box UV projection onto the current face selection.
func trigger_box_uv() -> void:
	if _uv_drawer != null:
		_uv_drawer.trigger_box_uv()


## Called by external code (e.g. the right-click context menu)
## to apply cylindrical UV projection onto the current face selection.
func trigger_cylindrical_uv() -> void:
	if _uv_drawer != null:
		_uv_drawer.trigger_cylindrical_uv()


## Called by external code (e.g. the right-click context menu)
## to apply spherical UV projection onto the current face selection.
func trigger_spherical_uv() -> void:
	if _uv_drawer != null:
		_uv_drawer.trigger_spherical_uv()


## Called by external code (e.g. the right-click context menu)
## to mark the current edge selection as hard.
func trigger_hard_edge() -> void:
	_on_hard_edge_pressed()


## Called by external code (e.g. the right-click context menu)
## to clear the hard-edge flag on the current edge selection.
func trigger_soft_edge() -> void:
	_on_soft_edge_pressed()


## Called by external code (e.g. the right-click context menu)
## to flat-shade the current face selection (smooth_group = 0).
func trigger_flat() -> void:
	_on_flat_shading_pressed()


## Called by external code (e.g. the right-click context menu)
## to smooth-shade the current face selection (smooth_group = 1).
func trigger_smooth() -> void:
	_on_smooth_shading_pressed()


## Called by external code (e.g. the right-click context menu)
## to auto-smooth the whole mesh at the panel's current angle threshold.
func trigger_auto_smooth() -> void:
	_on_auto_smooth_pressed()


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


func _on_shape_button_pressed(shape_name: String) -> void:
	if not ShapeCreationCatalog.supports_preview(shape_name):
		# Shapes without parameters (Cube, Plane) insert immediately.
		if _shape_preview != null and _shape_preview.is_active():
			_shape_preview.cancel()
		var params := ShapeCreationCatalog.default_params(shape_name)
		_insert_shape(func() -> GoBuildMesh:
				return ShapeCreationCatalog.build_mesh(shape_name, params),
				ShapeCreationCatalog.node_name(shape_name))
		return

	if not Engine.is_editor_hint():
		return
	var scene_root: Node = EditorInterface.get_edited_scene_root()
	if scene_root == null:
		push_warning("GoBuild: no open scene — create or open a scene first")
		return
	_shape_preview.start(shape_name, scene_root)


func _on_shape_preview_accepted(shape_key: String, params: Dictionary) -> void:
	_insert_shape(func() -> GoBuildMesh:
			return ShapeCreationCatalog.build_mesh(shape_key, params),
			ShapeCreationCatalog.node_name(shape_key))


func _on_shape_preview_cancelled() -> void:
	pass  # Nothing extra needed; GoBuildShapePreview already cleaned up.


func _supports_shape_preview(shape_name: String) -> bool:
	return _SHAPE_CATALOG_SCRIPT.supports_preview(shape_name)


func _shape_node_name(shape_name: String) -> String:
	return _SHAPE_CATALOG_SCRIPT.node_name(shape_name)


func _default_shape_params(shape_name: String) -> Dictionary:
	return _SHAPE_CATALOG_SCRIPT.default_params(shape_name)


func _build_shape_mesh(shape_name: String, params: Dictionary) -> GoBuildMesh:
	return _SHAPE_CATALOG_SCRIPT.build_mesh(shape_name, params)


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
	# Seed slot 0 with the default GoBuild metre material so new shapes
	# render with the standard look rather than an unshaded surface.
	var _default_mat: Material = load("res://addons/go_build/go_build_material.tres")
	if _default_mat != null and node.go_build_mesh != null:
		node.go_build_mesh.material_slots = [_default_mat]

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
## Keeps the panel buttons in sync and syncs drawers to the new mode:
## opens the relevant sections and closes the irrelevant ones so the user
## always sees what is useful without manual scrolling.
func _on_target_mode_changed(new_mode: SelectionManager.Mode) -> void:
	_sync_mode_buttons(new_mode)
	_update_ops_buttons()
	# Drawers to open vs. close per mode.
	# All mode-specific drawers are collected here so we can close the ones
	# that are not relevant without touching always-visible drawers.
	var open_set: Array = []
	var close_set: Array = []
	match new_mode:
		SelectionManager.Mode.OBJECT:
			open_set  = [_drawer_create]
			close_set = [_drawer_edge, _drawer_face, _drawer_surface]
			if _vertex_drawer != null: _vertex_drawer.set_open(false)
		SelectionManager.Mode.VERTEX:
			if _vertex_drawer != null: _vertex_drawer.set_open(true)
			close_set = [_drawer_edge, _drawer_face, _drawer_surface]
		SelectionManager.Mode.EDGE:
			open_set  = [_drawer_edge]
			close_set = [_drawer_face, _drawer_surface]
			if _vertex_drawer != null: _vertex_drawer.set_open(false)
		SelectionManager.Mode.FACE:
			open_set  = [_drawer_face, _drawer_surface]
			close_set = [_drawer_edge]
			if _vertex_drawer != null: _vertex_drawer.set_open(false)
	for d: Array in open_set:
		_open_drawer(d)
	for d: Array in close_set:
		_close_drawer(d)


## Press exactly the button that corresponds to [param active_mode] and
## release all others (radio-button behaviour).
func _sync_mode_buttons(active_mode: SelectionManager.Mode) -> void:
	for i: int in _mode_buttons.size():
		_mode_buttons[i].set_pressed_no_signal(i == active_mode as int)


## Create a collapsible drawer section and add it to [code]self[/code].
##
## Returns [code][header_button, content_vbox][/code]. Add all child controls
## to [code]result[1][/code]. [param open] sets the initial expanded state.
func _make_drawer(title: String, open: bool = false) -> Array:
	var btn := Button.new()
	btn.text = ("\u25bc  " if open else "\u25b6  ") + title
	btn.toggle_mode = true
	btn.button_pressed = open
	btn.flat = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 11)
	add_child(btn)
	var ctn := VBoxContainer.new()
	ctn.visible = open
	add_child(ctn)
	btn.toggled.connect(func(pressed: bool) -> void:
		ctn.visible = pressed
		btn.text = ("\u25bc  " if pressed else "\u25b6  ") + title
	)
	return [btn, ctn]


## Expand [param drawer] if it is currently collapsed (no-op when already open).
## [param drawer] must be the [Array] returned by [method _make_drawer].
func _open_drawer(drawer: Array) -> void:
	if drawer.is_empty() or drawer[0] == null:
		return
	var btn: Button        = drawer[0]
	var ctn: VBoxContainer = drawer[1]
	if ctn.visible:
		return
	ctn.visible = true
	btn.set_pressed_no_signal(true)
	# Replace leading arrow character.
	btn.text = btn.text.replace("\u25b6  ", "\u25bc  ")


## Collapse [param drawer] if it is currently expanded (no-op when already closed).
## [param drawer] must be the [Array] returned by [method _make_drawer].
func _close_drawer(drawer: Array) -> void:
	if drawer.is_empty() or drawer[0] == null:
		return
	var btn: Button        = drawer[0]
	var ctn: VBoxContainer = drawer[1]
	if not ctn.visible:
		return
	ctn.visible = false
	btn.set_pressed_no_signal(false)
	btn.text = btn.text.replace("\u25bc  ", "\u25b6  ")


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



## [code]true[/code] when a mesh instance is targeted and its mesh is non-null.
## Used for whole-mesh operations (e.g. Auto Smooth) that require no selection.
func _cond_has_mesh() -> bool:
	return _target != null and _target.go_build_mesh != null


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
	if _vertex_drawer != null:
		_vertex_drawer.refresh_buttons()
	if _materials_drawer != null:
		_materials_drawer.refresh_buttons()
	if _uv_drawer != null:
		_uv_drawer.refresh_buttons()


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


## Extrude the selected edges, entering parameter-preview mode so the user
## can drag to set the extrude distance.
## Requires Edge mode with at least one edge selected.
func _on_extrude_edge_pressed() -> void:
	if _target == null or _plugin == null:
		return
	if _target.selection.get_mode() != SelectionManager.Mode.EDGE:
		return
	var sel_edges: Array[int] = _target.selection.get_selected_edges()
	if sel_edges.is_empty():
		return

	# Capture to a local so the Callable closure captures the right set.
	var edges_to_extrude: Array[int] = []
	edges_to_extrude.assign(sel_edges)

	var preview := GoBuildParamPreview.new()
	preview.action_name = "Extrude Edge"
	preview.param_label = "Distance"
	preview.param_start = _EDGE_EXTRUDE_DEFAULT_WIDTH
	preview.param_min   = 0.0
	preview.param_max   = 100.0
	preview.apply_fn    = func(p: float) -> void: \
			EdgeExtrudeOperation.apply(_target.go_build_mesh, edges_to_extrude, p)
	_plugin.call("begin_param_preview", preview)


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


## Public entry-point for the right-click context menu.
func trigger_inset() -> void:
	_on_inset_pressed()


## Inset the selected faces, entering parameter-preview mode.
## Amount is a blend factor: 0 = no inset, 1 = fully collapsed to centroid.
## Clamped to [0, 1] so inset can never overshoot the face centroid.
## Requires Face mode with at least one face selected.
func _on_inset_pressed() -> void:
	if _target == null or _plugin == null:
		return
	if _target.selection.get_mode() != SelectionManager.Mode.FACE:
		return
	var sel_faces: Array[int] = _target.selection.get_selected_faces()
	if sel_faces.is_empty():
		return
	var faces_to_inset: Array[int] = []
	faces_to_inset.assign(sel_faces)
	var preview := GoBuildParamPreview.new()
	preview.action_name = "Inset Face"
	preview.param_label = "Amount"
	preview.param_start = _INSET_DEFAULT_AMOUNT
	preview.param_min   = 0.0
	preview.param_max   = 1.0
	preview.apply_fn    = func(p: float) -> void: \
			InsetOperation.apply(_target.go_build_mesh, faces_to_inset, p)
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


## Assign the smooth group ID from the spinner to all selected faces.
func _on_assign_smooth_group_pressed() -> void:
	if _target == null or _plugin == null:
		return
	if _target.selection.get_mode() != SelectionManager.Mode.FACE:
		return
	var sel_faces: Array[int] = _target.selection.get_selected_faces()
	if sel_faces.is_empty():
		return
	var faces: Array[int] = []
	faces.assign(sel_faces)
	var group_id: int = int(_smooth_group_spin.value)
	_run_op(
		"Assign Smooth Group %d" % group_id,
		func(): SmoothGroupOperation.apply(_target.go_build_mesh, faces, group_id),
		false,
	)


## Flat-shade selected faces (smooth_group = 0).
func _on_flat_shading_pressed() -> void:
	if _target == null or _plugin == null:
		return
	if _target.selection.get_mode() != SelectionManager.Mode.FACE:
		return
	var sel_faces: Array[int] = _target.selection.get_selected_faces()
	if sel_faces.is_empty():
		return
	var faces: Array[int] = []
	faces.assign(sel_faces)
	_run_op(
		"Flat Shading",
		func(): SmoothGroupOperation.apply(_target.go_build_mesh, faces, 0),
		false,
	)


## Smooth-shade selected faces (smooth_group = 1).
func _on_smooth_shading_pressed() -> void:
	if _target == null or _plugin == null:
		return
	if _target.selection.get_mode() != SelectionManager.Mode.FACE:
		return
	var sel_faces: Array[int] = _target.selection.get_selected_faces()
	if sel_faces.is_empty():
		return
	var faces: Array[int] = []
	faces.assign(sel_faces)
	_run_op(
		"Smooth Shading",
		func(): SmoothGroupOperation.apply(_target.go_build_mesh, faces, 1),
		false,
	)


## Apply auto smooth to the whole mesh with the angle set in the spinner.
func _on_auto_smooth_pressed() -> void:
	if _target == null or _plugin == null or _target.go_build_mesh == null:
		return
	var angle_deg: float = _auto_smooth_angle_spin.value if _auto_smooth_angle_spin != null else 30.0
	_run_op(
			"Auto Smooth",
			func(): AutoSmoothOperation.apply(_target.go_build_mesh, angle_deg),
			false,
	)


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


## Called when the Auto UV mode selector changes.
## Applies the new projection immediately to all unoverridden faces so the
## viewport updates without requiring the user to drag or operate.
func _on_auto_uv_mode_selected(index: int) -> void:
	if _target == null:
		return
	var new_mode := _auto_uv_option.get_item_id(index) as GoBuildFace.UvMode
	_target.auto_uv_mode = new_mode
	if new_mode != GoBuildFace.UvMode.NONE and _plugin != null:
		# Push an undoable action; _do_operation will call _apply_auto_uv() after
		# the no-op, applying the new mode to all unoverridden faces.
		_run_op("Set Auto UV Mode", func(): pass, false)


## Return the plugin version from plugin.cfg so panel text stays in sync.
## Falls back to "unknown" if the config cannot be loaded.
func _get_plugin_version() -> String:
	var cfg := ConfigFile.new()
	var err: Error = cfg.load(_PLUGIN_CFG_PATH)
	if err != OK:
		return "unknown"
	var version: Variant = cfg.get_value("plugin", "version", "unknown")
	return str(version)



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


## Mark selected edge(s) as hard: adjacent faces won't average normals across them.
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


## Clear the hard-edge flag on selected edge(s): normals will average across them.
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
