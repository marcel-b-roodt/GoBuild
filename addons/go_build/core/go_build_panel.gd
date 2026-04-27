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
const _INSET_SCRIPT := \
		preload("res://addons/go_build/mesh/operations/inset_operation.gd")
const _PLANAR_UV_SCRIPT := \
		preload("res://addons/go_build/uv/planar_projection.gd")
const _BOX_UV_SCRIPT := \
		preload("res://addons/go_build/uv/box_projection.gd")
const _CYLINDRICAL_UV_SCRIPT := \
		preload("res://addons/go_build/uv/cylindrical_projection.gd")
const _SPHERICAL_UV_SCRIPT := \
		preload("res://addons/go_build/uv/spherical_projection.gd")
const _FACE_SCRIPT := \
		preload("res://addons/go_build/mesh/go_build_face.gd")
const _SHAPE_CATALOG_SCRIPT := \
		preload("res://addons/go_build/mesh/generators/shape_creation_catalog.gd")
const _PARAM_PREVIEW_SCRIPT := \
		preload("res://addons/go_build/core/go_build_param_preview.gd")
const _SHAPE_PREVIEW_SCRIPT := \
		preload("res://addons/go_build/core/go_build_shape_preview.gd")
const _UV_PARAM_BOX_SCRIPT := \
		preload("res://addons/go_build/core/go_build_uv_param_box.gd")

const _PLUGIN_CFG_PATH := "res://addons/go_build/plugin.cfg"

## Default extrude distance in local mesh units.
const _EXTRUDE_DEFAULT_DISTANCE: float = 0.5

## Default edge extrude width in local mesh units.
const _EDGE_EXTRUDE_DEFAULT_WIDTH: float = 0.5

## Default bevel width in local mesh units.
const _BEVEL_DEFAULT_WIDTH: float = 0.01

## Default inset amount (0–1 blend toward centroid).
const _INSET_DEFAULT_AMOUNT: float = 0.1

## Default size of one tiled UV repeat in mesh units.
const _PLANAR_UV_UNITS_PER_TILE: float = 1.0

var _status_label: Label
var _stats_label: Label
var _mode_buttons: Array[Button] = []
var _extrude_btn: Button       = null
var _inset_btn: Button         = null
var _flip_btn: Button          = null
var _extrude_edge_btn: Button  = null
var _bevel_btn: Button         = null
var _bridge_btn: Button        = null
var _subdivide_btn: Button     = null
var _planar_uv_btn: Button     = null
var _box_uv_btn: Button        = null
var _cylindrical_uv_btn: Button = null
var _spherical_uv_btn: Button   = null
var _loop_cut_btn: Button      = null
var _delete_btn: Button        = null
var _merge_btn: Button         = null
var _weld_btn: Button          = null
var _cull_check: CheckBox      = null
var _auto_uv_option: OptionButton = null
var _shape_preview: GoBuildShapePreview = null

## Param box shown for all UV projection operations.
var _uv_param_box: GoBuildUvParamBox = null
## Snapshot captured when a UV param preview starts; used to restore on cancel.
var _uv_preview_snapshot: Dictionary = {}
## Face indices captured when a UV param preview starts.
var _uv_preview_faces: Array[int] = []
## Which UV mode is being previewed.
var _uv_preview_mode: GoBuildFace.UvMode = GoBuildFace.UvMode.NONE
## Node world transform captured at UV preview start (for world-space projections).
var _uv_preview_transform: Transform3D = Transform3D.IDENTITY
## True while a UV param preview is active.
var _uv_preview_active: bool = false

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
	var create_label := Label.new()
	create_label.text = "── Create Shape ──"
	create_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	create_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	create_label.add_theme_font_size_override("font_size", 11)
	add_child(create_label)

	var grid := GridContainer.new()
	grid.columns = 2
	add_child(grid)

	for shape_name: String in ShapeCreationCatalog.all_shapes():
		var btn := Button.new()
		btn.text = shape_name
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_shape_button_pressed.bind(shape_name))
		grid.add_child(btn)

	_shape_preview = GoBuildShapePreview.new()
	_shape_preview.accepted.connect(_on_shape_preview_accepted)
	_shape_preview.cancelled.connect(_on_shape_preview_cancelled)
	add_child(_shape_preview)

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

	add_child(_section_label("── Face UV ──"))

	var face_uv_grid := GridContainer.new()
	face_uv_grid.columns = 2
	add_child(face_uv_grid)

	_planar_uv_btn = _op_button("Auto UV",
		"Project selected face(s) onto their dominant axis using %.1f unit tiles.\n"
		% _PLANAR_UV_UNITS_PER_TILE
		+ "Useful for checker or metre textures during blockout.\n"
		+ "Requires Face mode with ≥1 face selected.")
	_planar_uv_btn.pressed.connect(_on_planar_uv_pressed)
	face_uv_grid.add_child(_planar_uv_btn)
	_register_op(_planar_uv_btn, _cond_face_any)

	_box_uv_btn = _op_button("Box UV",
		"Project selected face(s) using world-space box mapping (%.1f unit tiles).\n"
		% _PLANAR_UV_UNITS_PER_TILE
		+ "Adjacent same-axis faces share UV coordinates — no seam at shared edges.\n"
		+ "Requires Face mode with ≥1 face selected.")
	_box_uv_btn.pressed.connect(_on_box_uv_pressed)
	face_uv_grid.add_child(_box_uv_btn)
	_register_op(_box_uv_btn, _cond_face_any)

	_cylindrical_uv_btn = _op_button("Cyl UV",
		"Project selected face(s) using cylindrical mapping around the Y axis (%.1f unit tiles).\n"
		% _PLANAR_UV_UNITS_PER_TILE
		+ "U wraps 0-1 around the Y axis; V scales with height.\n"
		+ "Requires Face mode with \u22651 face selected.")
	_cylindrical_uv_btn.pressed.connect(_on_cylindrical_uv_pressed)
	face_uv_grid.add_child(_cylindrical_uv_btn)
	_register_op(_cylindrical_uv_btn, _cond_face_any)

	_spherical_uv_btn = _op_button("Sphere UV",
		"Project selected face(s) using spherical (equirectangular) mapping (%.1f unit tiles).\n"
		% _PLANAR_UV_UNITS_PER_TILE
		+ "U = longitude (0-1 around Y axis); V = latitude (0 = north / +Y, 1 = south / -Y).\n"
		+ "Requires Face mode with \u22651 face selected.")
	_spherical_uv_btn.pressed.connect(_on_spherical_uv_pressed)
	face_uv_grid.add_child(_spherical_uv_btn)
	_register_op(_spherical_uv_btn, _cond_face_any)

	# UV parameter box — shown below the UV buttons during a live param preview.
	_uv_param_box = GoBuildUvParamBox.new()
	_uv_param_box.params_changed.connect(_on_uv_params_preview)
	_uv_param_box.apply_requested.connect(_on_uv_params_apply)
	_uv_param_box.cancelled.connect(_on_uv_params_cancelled)
	add_child(_uv_param_box)

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

	# ── Auto UV mode selector ─────────────────────────────────────────────
	# Replaces the old boolean checkbox with a per-projection-type dropdown.
	# "None" disables automatic re-projection after every operation.
	# "Planar" and "Box" project all unoverridden faces after each operation.
	var uv_row := HBoxContainer.new()
	add_child(uv_row)

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
	_uv_cancel_preview()

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


## Called by external code (e.g. the face context menu)
## to project planar UVs onto the current face selection.
func trigger_planar_uv() -> void:
	_on_planar_uv_pressed()


## Called by external code (e.g. the right-click context menu)
## to apply box UV projection onto the current face selection.
func trigger_box_uv() -> void:
	_on_box_uv_pressed()


## Called by external code (e.g. the right-click context menu)
## to apply cylindrical UV projection onto the current face selection.
func trigger_cylindrical_uv() -> void:
	_on_cylindrical_uv_pressed()


## Called by external code (e.g. the right-click context menu)
## to apply spherical UV projection onto the current face selection.
func trigger_spherical_uv() -> void:
	_on_spherical_uv_pressed()


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


## Reproject the currently selected faces with dominant-axis planar UVs.
func _on_planar_uv_pressed() -> void:
	_uv_start_preview(GoBuildFace.UvMode.PLANAR, "Auto UV", false)


func _on_box_uv_pressed() -> void:
	_uv_start_preview(GoBuildFace.UvMode.BOX, "Box UV", false)


func _on_cylindrical_uv_pressed() -> void:
	_uv_start_preview(GoBuildFace.UvMode.CYLINDRICAL, "Cyl UV", true)


func _on_spherical_uv_pressed() -> void:
	_uv_start_preview(GoBuildFace.UvMode.SPHERICAL, "Sphere UV", true)


## Begin a UV param-preview for [param mode].
## Takes a mesh snapshot, populates [member _uv_param_box] with the first selected
## face's existing params (if it uses the same mode) and shows the param box.
func _uv_start_preview(
		mode: GoBuildFace.UvMode,
		action_name: String,
		has_seam: bool,
) -> void:
	if _target == null or _plugin == null:
		return
	if _target.selection.get_mode() != SelectionManager.Mode.FACE:
		return
	var sel_faces: Array[int] = _target.selection.get_selected_faces()
	if sel_faces.is_empty():
		return
	# Cancel any previous preview cleanly before starting a new one.
	if _uv_preview_active:
		_uv_cancel_preview()
	# Capture the pre-preview state.
	_uv_preview_snapshot = _target.go_build_mesh.take_snapshot()
	_uv_preview_faces.assign(sel_faces)
	_uv_preview_mode = mode
	_uv_preview_transform = _target.global_transform
	_uv_preview_active = true
	# Seed the param box with the first face's existing params when it already
	# uses the same mode, so the user starts from the last applied values.
	var first: GoBuildFace = _target.go_build_mesh.faces[sel_faces[0]]
	var initial_scale: float = 1.0
	var initial_offset := Vector2.ZERO
	var initial_seam_rot: float = 0.0
	if first.uv_projection_mode == mode:
		initial_scale   = first.uv_scale
		initial_offset  = first.uv_offset
		initial_seam_rot = first.uv_seam_rotation
	_uv_param_box.setup(action_name, has_seam, initial_scale, initial_offset, initial_seam_rot)


## Cancel the active UV param preview and restore the mesh to its pre-preview state.
func _uv_cancel_preview() -> void:
	if not _uv_preview_active:
		return
	_uv_preview_active = false
	if _uv_param_box != null:
		_uv_param_box.hide_box()
	if _target != null and not _uv_preview_snapshot.is_empty():
		_target.go_build_mesh.restore_snapshot(_uv_preview_snapshot)
		_target.bake()
	_uv_preview_snapshot = {}
	_uv_preview_faces = []


## Live-preview handler: restore snapshot, re-project with current params, bake.
## Called by [GoBuildUvParamBox] on every spinbox change.
func _on_uv_params_preview(params: Dictionary) -> void:
	if not _uv_preview_active or _target == null:
		return
	_target.go_build_mesh.restore_snapshot(_uv_preview_snapshot)
	_uv_project_batch(
		_uv_preview_mode,
		_uv_preview_faces,
		params.get("scale", 1.0),
		Vector2(params.get("u_offset", 0.0), params.get("v_offset", 0.0)),
		params.get("seam_rotation", 0.0),
		_uv_preview_transform,
	)
	_target.bake()


## Commit handler: restore snapshot so undo baseline is clean, then run op.
## Called by [GoBuildUvParamBox] when the user clicks Accept.
func _on_uv_params_apply(params: Dictionary) -> void:
	if not _uv_preview_active or _target == null or _plugin == null:
		return
	_uv_preview_active = false
	# Restore to pre-preview state so the undo snapshot captures the original mesh.
	_target.go_build_mesh.restore_snapshot(_uv_preview_snapshot)
	var faces: Array[int] = _uv_preview_faces.duplicate()
	var mode: GoBuildFace.UvMode = _uv_preview_mode
	var xform: Transform3D = _uv_preview_transform
	var scale: float = float(params.get("scale", 1.0))
	var offset := Vector2(float(params.get("u_offset", 0.0)), float(params.get("v_offset", 0.0)))
	var seam_rot: float = float(params.get("seam_rotation", 0.0))
	_uv_preview_snapshot = {}
	_uv_preview_faces = []
	_run_op(
		_uv_action_name(mode),
		func():
			for fi: int in faces:
				var face: GoBuildFace = _target.go_build_mesh.faces[fi]
				face.uv_projection_mode = mode
				face.uv_scale = scale
				face.uv_offset = offset
				face.uv_seam_rotation = seam_rot
			_uv_project_batch(mode, faces, scale, offset, seam_rot, xform),
		false,
	)


## Cancel handler: restore snapshot and bake.
## Called by [GoBuildUvParamBox] when the user clicks Cancel.
func _on_uv_params_cancelled() -> void:
	if not _uv_preview_active or _target == null:
		return
	_uv_preview_active = false
	if not _uv_preview_snapshot.is_empty():
		_target.go_build_mesh.restore_snapshot(_uv_preview_snapshot)
		_target.bake()
	_uv_preview_snapshot = {}
	_uv_preview_faces = []


## Dispatch a UV projection onto [param faces] without creating an undo entry.
func _uv_project_batch(
		mode: GoBuildFace.UvMode,
		faces: Array[int],
		scale: float,
		offset: Vector2,
		seam_rot: float,
		xform: Transform3D,
) -> void:
	match mode:
		GoBuildFace.UvMode.PLANAR:
			PlanarProjection.apply(_target.go_build_mesh, faces, scale, offset)
		GoBuildFace.UvMode.BOX:
			BoxProjection.apply(_target.go_build_mesh, faces, scale, xform, offset)
		GoBuildFace.UvMode.CYLINDRICAL:
			CylindricalProjection.apply(
				_target.go_build_mesh, faces, scale, xform, offset, seam_rot)
		GoBuildFace.UvMode.SPHERICAL:
			SphericalProjection.apply(
				_target.go_build_mesh, faces, scale, xform, offset, seam_rot)


## Return the action name string for [param mode], used in undo history.
func _uv_action_name(mode: GoBuildFace.UvMode) -> String:
	match mode:
		GoBuildFace.UvMode.PLANAR:      return "Auto UV Planar"
		GoBuildFace.UvMode.BOX:         return "Box UV"
		GoBuildFace.UvMode.CYLINDRICAL: return "Cylindrical UV"
		GoBuildFace.UvMode.SPHERICAL:   return "Spherical UV"
	return "UV"


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
