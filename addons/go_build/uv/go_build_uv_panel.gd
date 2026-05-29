## Dock panel that hosts the [GoBuildUvCanvas] viewer.
##
## Registered as a second editor dock by [GoBuildPlugin].  When the active
## node changes the plugin calls [method set_target]; the embedded canvas
## automatically redraws on mesh or selection change.
##
## Organised into collapsible drawers:
## - General: selection mode, isolate toggle, background dropdown, repeat.
## - Transform: Move/Rotate/Scale, Add Tex.
## - Operations: Pack, Stitch.
@tool
class_name GoBuildUvPanel
extends VBoxContainer

# Self-preload — ensures GoBuildUvCanvas is registered before use.
const _CANVAS_SCRIPT          := preload("res://addons/go_build/uv/go_build_uv_canvas.gd")
const _MESH_INSTANCE_SCRIPT   := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _MESH_SCRIPT            := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _SEL_MGR_SCRIPT         := preload("res://addons/go_build/core/selection_manager.gd")
const _PACK_SCRIPT            := preload("res://addons/go_build/uv/uv_pack_islands.gd")
const _STITCH_SCRIPT          := preload("res://addons/go_build/uv/uv_stitch_islands.gd")
const _FACE_SCRIPT            := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MATERIAL_ASSIGN_SCRIPT := \
	preload("res://addons/go_build/mesh/operations/material_assign_operation.gd")
const _DRAWER_SCRIPT          := preload("res://addons/go_build/core/go_build_drawer.gd")

# Dropdown item indices — must match the order _rebuild_bg_dropdown adds them.
const _BG_ITEM_CHECKER: int = 0
const _BG_ITEM_OFF: int     = 1
const _TEXTURE_ITEMS_START: int = 3

var _canvas: GoBuildUvCanvas   = null
var _zoom_label: Label        = null
var _plugin: EditorPlugin     = null
var _move_btn: Button         = null
var _rotate_btn: Button       = null
var _scale_btn: Button        = null
var _bg_option: OptionButton  = null
var _isolate_btn: Button      = null
var _pack_btn: Button         = null
var _stitch_btn: Button       = null
var _add_tex_btn: Button      = null
var _select_mode_btn: Button  = null
var _repeat_spin: SpinBox     = null
var _snap_spin: SpinBox        = null
var _tex_file_dialog: EditorFileDialog = null
var _suppress_bg_change: bool  = false
var _tracked_target: GoBuildMeshInstance = null

# Drawer content containers (so we can add children after _setup_drawer).
var _general_content: VBoxContainer  = null
var _transform_content: VBoxContainer = null
var _operations_content: VBoxContainer = null


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Called by the plugin after the dock is registered.
func set_plugin(plugin: EditorPlugin) -> void:
	_plugin = plugin
	if _canvas != null:
		_canvas.set_plugin(plugin)


## Set the active [GoBuildMeshInstance] to display.  Pass [code]null[/code]
## to clear the view (no mesh selected).
func set_target(node: GoBuildMeshInstance) -> void:
	if _tracked_target != null and is_instance_valid(_tracked_target):
		if _tracked_target.mesh_changed.is_connected(_on_target_mesh_changed):
			_tracked_target.mesh_changed.disconnect(_on_target_mesh_changed)
	_tracked_target = node
	if _tracked_target != null:
		if not _tracked_target.mesh_changed.is_connected(_on_target_mesh_changed):
			_tracked_target.mesh_changed.connect(_on_target_mesh_changed)
	if _canvas != null:
		_canvas.set_target(node)
	_rebuild_bg_dropdown()
	_update_zoom_label()


## Force a redraw of the canvas (called by the plugin after selection changes
## that don't trigger mesh_changed, e.g. mode switches).
func refresh() -> void:
	if _canvas != null:
		_canvas.queue_redraw()
	_update_zoom_label()


func _on_target_mesh_changed() -> void:
	_rebuild_bg_dropdown()


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# ---- Header row (always visible) ----
	var header := HBoxContainer.new()
	add_child(header)

	var title := Label.new()
	title.text = "UV View"
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", Color(0.70, 0.70, 0.70))
	header.add_child(title)

	var spacer_h := Control.new()
	spacer_h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer_h)

	_zoom_label = Label.new()
	_zoom_label.text = ""
	_zoom_label.add_theme_font_size_override("font_size", 10)
	_zoom_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	header.add_child(_zoom_label)

	var reset_btn := Button.new()
	reset_btn.text = "Reset"
	reset_btn.flat = true
	reset_btn.tooltip_text = "Reset pan and zoom to default."
	reset_btn.pressed.connect(_on_reset_pressed)
	header.add_child(reset_btn)

	# ---- General drawer ----
	_general_content = _build_drawer("General", true)
	_add_general_controls(_general_content)

	# ---- Transform drawer ----
	_transform_content = _build_drawer("Transform", true)
	_add_transform_controls(_transform_content)

	# ---- Operations drawer ----
	_operations_content = _build_drawer("Operations", false)
	_add_operations_controls(_operations_content)

	# ---- Canvas ----
	_canvas = _CANVAS_SCRIPT.new()
	_canvas.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.clip_contents = true
	add_child(_canvas)
	if _plugin != null:
		_canvas.set_plugin(_plugin)

	_canvas.draw.connect(_update_zoom_label)
	_canvas.draw.connect(_update_transform_buttons)
	_canvas.bg_mode_changed.connect(_on_canvas_bg_mode_changed)


# ---------------------------------------------------------------------------
# Drawer construction
# ---------------------------------------------------------------------------

## Build a collapsible drawer with header and content [VBoxContainer].
## Returns the content [VBoxContainer] so callers can add children.
func _build_drawer(title: String, open: bool) -> VBoxContainer:
	var header_btn := Button.new()
	header_btn.text = ("\u25bc  " if open else "\u25b6  ") + title
	header_btn.toggle_mode = true
	header_btn.button_pressed = open
	header_btn.flat = true
	header_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_btn.add_theme_font_size_override("font_size", 11)
	add_child(header_btn)

	var content := VBoxContainer.new()
	content.visible = open
	add_child(content)

	header_btn.toggled.connect(func(pressed: bool) -> void:
		content.visible = pressed
		header_btn.text = ("\u25bc  " if pressed else "\u25b6  ") + title
	)
	return content


# ---------------------------------------------------------------------------
# General drawer content
# ---------------------------------------------------------------------------

func _add_general_controls(parent: VBoxContainer) -> void:
	# Row 1: Mode, Isolate, BG dropdown.
	var row1 := HBoxContainer.new()
	parent.add_child(row1)

	var mode_label := Label.new()
	mode_label.text = "Mode:"
	mode_label.add_theme_font_size_override("font_size", 10)
	mode_label.add_theme_color_override("font_color", Color(0.70, 0.70, 0.70))
	row1.add_child(mode_label)

	_select_mode_btn = Button.new()
	_select_mode_btn.text = "Face"
	_select_mode_btn.toggle_mode = true
	_select_mode_btn.button_pressed = true
	_select_mode_btn.tooltip_text = "Toggle UV selection mode: Face / Vertex (Tab)"
	_select_mode_btn.pressed.connect(_on_select_mode_pressed)
	row1.add_child(_select_mode_btn)

	_isolate_btn = Button.new()
	_isolate_btn.text = "Isolate"
	_isolate_btn.toggle_mode = true
	_isolate_btn.button_pressed = false
	_isolate_btn.tooltip_text = "Show only selected faces in the UV editor."
	_isolate_btn.pressed.connect(_on_isolate_pressed)
	row1.add_child(_isolate_btn)

	var bg_label := Label.new()
	bg_label.text = "BG:"
	bg_label.add_theme_font_size_override("font_size", 10)
	bg_label.add_theme_color_override("font_color", Color(0.70, 0.70, 0.70))
	row1.add_child(bg_label)

	_bg_option = OptionButton.new()
	_bg_option.tooltip_text = "Select background: Checker, Off, or a material texture."
	_bg_option.item_selected.connect(_on_bg_option_selected)
	row1.add_child(_bg_option)
	_rebuild_bg_dropdown()

	# Row 2: Repeat, Snap.
	var row2 := HBoxContainer.new()
	parent.add_child(row2)

	var repeat_label := Label.new()
	repeat_label.text = "Repeat:"
	repeat_label.add_theme_font_size_override("font_size", 10)
	repeat_label.add_theme_color_override("font_color", Color(0.70, 0.70, 0.70))
	row2.add_child(repeat_label)

	_repeat_spin = SpinBox.new()
	_repeat_spin.min_value = 0
	_repeat_spin.max_value = 8
	_repeat_spin.value = 1
	_repeat_spin.step = 1
	_repeat_spin.tooltip_text = "Number of UV tile repeats shown in the view."
	_repeat_spin.value_changed.connect(_on_repeat_changed)
	row2.add_child(_repeat_spin)

	var snap_label := Label.new()
	snap_label.text = "Snap:"
	snap_label.add_theme_font_size_override("font_size", 10)
	snap_label.add_theme_color_override("font_color", Color(0.70, 0.70, 0.70))
	row2.add_child(snap_label)

	_snap_spin = SpinBox.new()
	_snap_spin.min_value = 0.0
	_snap_spin.max_value = 1.0
	_snap_spin.value = 0.0625
	_snap_spin.step = 0.0625
	_snap_spin.tooltip_text = "UV snap grid size (Ctrl to activate). 0 = off, 0.0625 = 1/16th."
	_snap_spin.value_changed.connect(_on_snap_changed)
	row2.add_child(_snap_spin)


# ---------------------------------------------------------------------------
# Transform drawer content
# ---------------------------------------------------------------------------

func _add_transform_controls(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)

	_move_btn = Button.new()
	_move_btn.text = "Move"
	_move_btn.tooltip_text = "Move UV island (W)"
	_move_btn.toggle_mode = true
	_move_btn.button_pressed = true
	_move_btn.pressed.connect(_on_move_pressed)
	row.add_child(_move_btn)

	_rotate_btn = Button.new()
	_rotate_btn.text = "Rotate"
	_rotate_btn.tooltip_text = "Rotate UV island (E)"
	_rotate_btn.toggle_mode = true
	_rotate_btn.pressed.connect(_on_rotate_pressed)
	row.add_child(_rotate_btn)

	_scale_btn = Button.new()
	_scale_btn.text = "Scale"
	_scale_btn.tooltip_text = "Scale UV island (R)"
	_scale_btn.toggle_mode = true
	_scale_btn.pressed.connect(_on_scale_pressed)
	row.add_child(_scale_btn)

	_add_tex_btn = Button.new()
	_add_tex_btn.text = "Add Tex"
	_add_tex_btn.tooltip_text = "Assign a texture to selected faces by picking an image file."
	_add_tex_btn.pressed.connect(_on_add_tex_pressed)
	row.add_child(_add_tex_btn)


# ---------------------------------------------------------------------------
# Operations drawer content
# ---------------------------------------------------------------------------

func _add_operations_controls(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)

	_pack_btn = Button.new()
	_pack_btn.text = "Pack"
	_pack_btn.tooltip_text = "Pack all UV islands into the 0-1 tile."
	_pack_btn.pressed.connect(_on_pack_pressed)
	row.add_child(_pack_btn)

	_stitch_btn = Button.new()
	_stitch_btn.text = "Stitch"
	_stitch_btn.tooltip_text = "Stitch selected UV islands that share edges."
	_stitch_btn.pressed.connect(_on_stitch_pressed)
	row.add_child(_stitch_btn)


# ---------------------------------------------------------------------------
# Handlers
# ---------------------------------------------------------------------------

func _on_reset_pressed() -> void:
	if _canvas != null:
		_canvas.reset_view()
	_update_zoom_label()


func _on_select_mode_pressed() -> void:
	if _canvas != null:
		if _canvas.get_uv_select_mode() == GoBuildUvCanvas.UvSelectMode.FACE:
			_canvas.set_uv_select_mode(GoBuildUvCanvas.UvSelectMode.VERTEX)
		else:
			_canvas.set_uv_select_mode(GoBuildUvCanvas.UvSelectMode.FACE)
	_update_select_mode_btn()


func _on_move_pressed() -> void:
	if _canvas != null:
		_canvas.set_transform_mode(GoBuildUvCanvas.UvTransformMode.MOVE)
	_update_transform_buttons()


func _on_rotate_pressed() -> void:
	if _canvas != null:
		_canvas.set_transform_mode(GoBuildUvCanvas.UvTransformMode.ROTATE)
	_update_transform_buttons()


func _on_scale_pressed() -> void:
	if _canvas != null:
		_canvas.set_transform_mode(GoBuildUvCanvas.UvTransformMode.SCALE)
	_update_transform_buttons()


func _on_bg_option_selected(index: int) -> void:
	if _suppress_bg_change or _canvas == null:
		return
	if index == _BG_ITEM_CHECKER:
		_canvas.set_bg_mode(GoBuildUvCanvas.UvBgMode.CHECKER)
	elif index == _BG_ITEM_OFF:
		_canvas.set_bg_mode(GoBuildUvCanvas.UvBgMode.OFF)
	else:
		var mat_idx: int = index - _TEXTURE_ITEMS_START
		_canvas.set_bg_material_index(mat_idx)


func _on_isolate_pressed() -> void:
	if _canvas != null:
		_canvas.set_isolate_selected(_isolate_btn.button_pressed)
	_update_isolate_btn_style()


func _update_isolate_btn_style() -> void:
	if _isolate_btn.button_pressed:
		_isolate_btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
		_isolate_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.90, 0.50))
		_isolate_btn.add_theme_color_override("font_pressed_color", Color(1.0, 0.85, 0.35))
		var pressed_bg := StyleBoxFlat.new()
		pressed_bg.bg_color = Color(0.30, 0.25, 0.12)
		pressed_bg.set_corner_radius_all(4)
		pressed_bg.set_content_margin_all(4)
		_isolate_btn.add_theme_stylebox_override("pressed", pressed_bg)
		var hover_bg := StyleBoxFlat.new()
		hover_bg.bg_color = Color(0.35, 0.30, 0.15)
		hover_bg.set_corner_radius_all(4)
		hover_bg.set_content_margin_all(4)
		_isolate_btn.add_theme_stylebox_override("hover", hover_bg)
	else:
		_isolate_btn.remove_theme_color_override("font_color")
		_isolate_btn.remove_theme_color_override("font_hover_color")
		_isolate_btn.remove_theme_color_override("font_pressed_color")
		_isolate_btn.remove_theme_stylebox_override("pressed")
		_isolate_btn.remove_theme_stylebox_override("hover")


func trigger_add_tex() -> void:
	_on_add_tex_pressed()


func _on_add_tex_pressed() -> void:
	if _canvas == null or _canvas._target == null or _canvas._target.go_build_mesh == null:
		return
	if _tex_file_dialog == null:
		_tex_file_dialog = EditorFileDialog.new()
		_tex_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
		_tex_file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
		var filters: PackedStringArray = [
			"*.png ; PNG Image",
			"*.jpg ; JPEG Image",
			"*.svg ; SVG Image",
			"*.webp ; WebP Image",
			"*.bmp ; BMP Image",
			"*.tres ; Material Resource",
		]
		_tex_file_dialog.filters = filters
		_tex_file_dialog.title = "Select Texture or Material"
		_tex_file_dialog.file_selected.connect(_on_tex_file_selected)
		add_child(_tex_file_dialog)
	_tex_file_dialog.popup_centered_clamped(Vector2i(800, 600))


func _on_tex_file_selected(path: String) -> void:
	if _canvas == null or _canvas._target == null or _canvas._target.go_build_mesh == null:
		return
	if _plugin == null:
		return

	var gbm: GoBuildMesh = _canvas._target.go_build_mesh
	var snapshot := gbm.take_snapshot()

	var sel_faces: Array[int] = []
	if _canvas._target.selection.get_mode() == SelectionManager.Mode.FACE:
		sel_faces = _canvas._target.selection.get_selected_faces()
	if sel_faces.is_empty():
		sel_faces.resize(gbm.faces.size())
		for i: int in gbm.faces.size():
			sel_faces[i] = i

	var mat: Material = null
	var mat_slot_idx: int = -1

	if path.to_lower().ends_with(".tres") or path.to_lower().ends_with(".res"):
		var loaded: Resource = load(path)
		if loaded is Material:
			mat = loaded as Material
		else:
			push_warning("GoBuild: Selected file is not a Material resource: %s" % path)
			return
	else:
		var tex: Texture2D = load(path) as Texture2D
		if tex == null:
			push_warning("GoBuild: Could not load texture: %s" % path)
			return

		for i: int in gbm.material_slots.size():
			var slot_mat: Material = gbm.material_slots[i]
			if slot_mat is StandardMaterial3D:
				var smat: StandardMaterial3D = slot_mat as StandardMaterial3D
				if smat.albedo_texture != null \
						and smat.albedo_texture.resource_path == path:
					mat = smat
					mat_slot_idx = i
					break

		if mat == null:
			var new_mat := StandardMaterial3D.new()
			new_mat.albedo_texture = tex
			var tex_name: String = tex.resource_name
			if tex_name == "":
				tex_name = path.get_file().get_basename()
			new_mat.resource_name = tex_name
			mat = new_mat

	if mat_slot_idx < 0:
		mat_slot_idx = gbm.material_slots.size()
		gbm.material_slots.append(null)

	MaterialAssignOperation.apply_to_selected_faces(gbm, sel_faces, mat_slot_idx, mat)

	_canvas._target.bake_in_place()

	var ur: EditorUndoRedoManager = _plugin.get_undo_redo()
	ur.create_action("Add Texture to Faces")
	ur.add_do_method(_canvas._target, "restore_and_bake", gbm.take_snapshot())
	ur.add_undo_method(_canvas._target, "restore_and_bake", snapshot)
	ur.commit_action()

	_rebuild_bg_dropdown()
	_canvas.set_bg_material_index(mat_slot_idx)
	_canvas.queue_redraw()


func _on_repeat_changed(value: float) -> void:
	if _canvas != null:
		_canvas.set_tile_repeat(int(value))


func _on_snap_changed(value: float) -> void:
	if _canvas != null:
		_canvas.set_uv_snap_size(value)


func _on_pack_pressed() -> void:
	if _canvas == null or _canvas._target == null or _canvas._target.go_build_mesh == null:
		return
	var gbm: GoBuildMesh = _canvas._target.go_build_mesh
	var snapshot := gbm.take_snapshot()
	var count := UvPackIslands.apply(gbm)
	_canvas._target.bake_in_place()
	if _plugin != null and count > 0:
		var ur: EditorUndoRedoManager = _plugin.get_undo_redo()
		ur.create_action("Pack UV Islands (%d)" % count)
		ur.add_do_method(_canvas._target, "restore_and_bake", gbm.take_snapshot())
		ur.add_undo_method(_canvas._target, "restore_and_bake", snapshot)
		ur.commit_action()
	_canvas.queue_redraw()


func _on_stitch_pressed() -> void:
	if _canvas == null or _canvas._target == null or _canvas._target.go_build_mesh == null:
		return
	var gbm: GoBuildMesh = _canvas._target.go_build_mesh
	var sel_faces: Array[int] = []
	if _canvas._target.selection.get_mode() == SelectionManager.Mode.FACE:
		sel_faces = _canvas._target.selection.get_selected_faces()
	if sel_faces.is_empty():
		return
	var snapshot := gbm.take_snapshot()
	var count := UvStitchIslands.apply(gbm, sel_faces)
	_canvas._target.bake_in_place()
	if _plugin != null and count > 0:
		var ur: EditorUndoRedoManager = _plugin.get_undo_redo()
		ur.create_action("Stitch UV Islands (%d merged)" % count)
		ur.add_do_method(_canvas._target, "restore_and_bake", gbm.take_snapshot())
		ur.add_undo_method(_canvas._target, "restore_and_bake", snapshot)
		ur.commit_action()
	_canvas.queue_redraw()


func _on_canvas_bg_mode_changed() -> void:
	_sync_bg_dropdown_to_canvas()


# ---------------------------------------------------------------------------
# Dropdown rebuild
# ---------------------------------------------------------------------------

func _rebuild_bg_dropdown() -> void:
	if _bg_option == null:
		return
	_suppress_bg_change = true
	_bg_option.clear()

	_bg_option.add_item("Checker", _BG_ITEM_CHECKER)
	_bg_option.add_item("Off", _BG_ITEM_OFF)
	_bg_option.add_separator()

	if _canvas != null and _canvas._target != null and _canvas._target.go_build_mesh != null:
		var slots: Array[Material] = _canvas._target.go_build_mesh.material_slots
		for i: int in slots.size():
			var mat: Material = slots[i]
			var label: String = "Slot %d" % i
			if mat != null:
				if mat is StandardMaterial3D:
					var smat: StandardMaterial3D = mat as StandardMaterial3D
					if smat.albedo_texture != null:
						var tex_name: String = smat.albedo_texture.resource_name
						var mat_name: String = mat.resource_name
						var display_name: String = mat_name if mat_name != "" else tex_name
						label = "Slot %d (%s)" % [i, display_name]
				elif mat.resource_name != "":
					label = "Slot %d (%s)" % [i, mat.resource_name]
			_bg_option.add_item(label)
	else:
		_bg_option.add_item("(no mesh)")

	_sync_bg_dropdown_to_canvas()
	_suppress_bg_change = false


func _sync_bg_dropdown_to_canvas() -> void:
	if _bg_option == null or _canvas == null:
		return
	_suppress_bg_change = true
	var mode: int = _canvas.get_bg_mode()
	if mode == GoBuildUvCanvas.UvBgMode.CHECKER:
		_bg_option.selected = _BG_ITEM_CHECKER
	elif mode == GoBuildUvCanvas.UvBgMode.OFF:
		_bg_option.selected = _BG_ITEM_OFF
	elif mode == GoBuildUvCanvas.UvBgMode.TEXTURE:
		var mat_idx: int = _canvas.get_bg_material_index()
		var target_idx: int = _TEXTURE_ITEMS_START + mat_idx
		if target_idx < _bg_option.item_count:
			_bg_option.selected = target_idx
	_suppress_bg_change = false


# ---------------------------------------------------------------------------
# UI update helpers
# ---------------------------------------------------------------------------

func _update_zoom_label() -> void:
	if _zoom_label == null or _canvas == null:
		return
	_zoom_label.text = "%d px/uv" % int(_canvas.get_zoom())


func _update_transform_buttons() -> void:
	if _move_btn == null or _canvas == null:
		return
	var mode: int = _canvas.get_transform_mode()
	_move_btn.button_pressed = (mode == GoBuildUvCanvas.UvTransformMode.MOVE)
	_rotate_btn.button_pressed = (mode == GoBuildUvCanvas.UvTransformMode.ROTATE)
	_scale_btn.button_pressed = (mode == GoBuildUvCanvas.UvTransformMode.SCALE)
	_update_select_mode_btn()


func _update_select_mode_btn() -> void:
	if _select_mode_btn == null or _canvas == null:
		return
	var mode: int = _canvas.get_uv_select_mode()
	if mode == GoBuildUvCanvas.UvSelectMode.FACE:
		_select_mode_btn.text = "Face"
		_select_mode_btn.button_pressed = true
	else:
		_select_mode_btn.text = "Vertex"
		_select_mode_btn.button_pressed = false
