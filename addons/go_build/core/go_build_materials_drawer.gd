## Self-contained Materials drawer for the GoBuild editor panel.
##
## Manages palette selection, material slot assignment, and the live
## palette material preview list.
##
## Palettes are auto-discovered from the project filesystem. The user can
## create and delete palettes directly from the panel. Material assignment
## works in both Face mode (selected faces) and Object mode (all faces).
##
## The Default palette is always available — shipped as a read-only addon
## resource at [code]res://addons/go_build/default_palette.tres[/code].
@tool
class_name GoBuildMaterialsDrawer
extends GoBuildDrawer

# Self-preloads — dependency order.
const _SEL_MGR_SCRIPT_M   := preload("res://addons/go_build/core/selection_manager.gd")
const _MESH_INST_SCRIPT_M := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _DRAWER_SCRIPT_M    := preload("res://addons/go_build/core/go_build_drawer.gd")
const _MAT_ASSIGN_SCRIPT  := \
		preload("res://addons/go_build/mesh/operations/material_assign_operation.gd")
const _PALETTE_SCRIPT     := \
		preload("res://addons/go_build/core/go_build_material_palette.gd")
const _SETTINGS_SCRIPT    := \
		preload("res://addons/go_build/core/go_build_project_settings.gd")
const _MATERIALS_SCRIPT   := preload("res://addons/go_build/core/go_build_materials.gd")

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _discovered_palettes: Array[GoBuildMaterialPalette] = []
var _connected_palette: GoBuildMaterialPalette = null

# UI widgets
var _palette_option:      OptionButton  = null
var _new_pal_btn:         Button        = null
var _edit_pal_btn:        Button        = null
var _delete_pal_btn:      Button        = null
var _pal_materials_vbox:  VBoxContainer = null


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func set_plugin(plugin: EditorPlugin) -> void:
	super.set_plugin(plugin)


func set_target(target: GoBuildMeshInstance) -> void:
	super.set_target(target)


func refresh() -> void:
	refresh_buttons()
	_rebuild_pal_material_list()


func set_project_settings(_settings: GoBuildProjectSettings) -> void:
	_rebuild_palette_dropdown()


func refresh_palettes() -> void:
	_rebuild_palette_dropdown()


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_setup_drawer("Materials")

	# ── Palette row ──────────────────────────────────────────────────────
	var pal_row := HBoxContainer.new()
	_content.add_child(pal_row)

	_palette_option = OptionButton.new()
	_palette_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_palette_option.add_theme_font_size_override("font_size", 11)
	_palette_option.tooltip_text = (
			"Select a project palette.\n"
			+ "Palettes are auto-discovered from the project filesystem."
	)
	_palette_option.item_selected.connect(_on_palette_selected)
	pal_row.add_child(_palette_option)

	_new_pal_btn = Button.new()
	_new_pal_btn.text = "+ New"
	_new_pal_btn.add_theme_font_size_override("font_size", 11)
	_new_pal_btn.tooltip_text = "Create a new empty palette."
	_new_pal_btn.pressed.connect(_on_new_palette_pressed)
	pal_row.add_child(_new_pal_btn)

	_edit_pal_btn = Button.new()
	_edit_pal_btn.text = "Edit"
	_edit_pal_btn.add_theme_font_size_override("font_size", 11)
	_edit_pal_btn.tooltip_text = (
			"Open the selected palette in the Inspector to add/remove materials.\n"
			+ "The material list refreshes automatically when you save changes."
	)
	_edit_pal_btn.pressed.connect(_on_edit_palette_pressed)
	pal_row.add_child(_edit_pal_btn)

	_delete_pal_btn = Button.new()
	_delete_pal_btn.text = "Del"
	_delete_pal_btn.add_theme_font_size_override("font_size", 11)
	_delete_pal_btn.tooltip_text = "Delete the selected palette from disk."
	_delete_pal_btn.pressed.connect(_on_delete_palette_pressed)
	pal_row.add_child(_delete_pal_btn)

	# ── Palette material list ────────────────────────────────────────────
	_pal_materials_vbox = VBoxContainer.new()
	_pal_materials_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(_pal_materials_vbox)

	if Engine.is_editor_hint():
		var fs := EditorInterface.get_resource_filesystem()
		if not fs.filesystem_changed.is_connected(refresh_palettes):
			fs.filesystem_changed.connect(refresh_palettes)

	_rebuild_palette_dropdown()


func _exit_tree() -> void:
	_disconnect_palette_signal()
	if Engine.is_editor_hint():
		var fs := EditorInterface.get_resource_filesystem()
		if fs.filesystem_changed.is_connected(refresh_palettes):
			fs.filesystem_changed.disconnect(refresh_palettes)


# ---------------------------------------------------------------------------
# Conditions
# ---------------------------------------------------------------------------

func _cond_target_exists() -> bool:
	return _target != null


func _cond_face_any() -> bool:
	return _target != null \
			and _target.selection.get_mode() == SelectionManager.Mode.FACE \
			and not _target.selection.get_selected_faces().is_empty()


func _cond_palette_selected() -> bool:
	return _palette_option != null \
			and _palette_option.selected >= 0 \
			and _palette_option.selected < _discovered_palettes.size()


# ---------------------------------------------------------------------------
# Operation handlers
# ---------------------------------------------------------------------------

func _on_new_palette_pressed() -> void:
	if not Engine.is_editor_hint():
		return
	_show_name_dialog_async("New Palette", "Default", _create_palette_with_name)


func _create_palette_with_name(name_input: String) -> void:
	var pal := GoBuildMaterialPalette.new()
	pal.palette_name = name_input
	var safe_name := name_input.to_snake_case()
	if safe_name.is_empty():
		safe_name = "palette"
	DirAccess.make_dir_recursive_absolute("res://materials/")
	var save_path := "res://materials/%s_palette.tres" % safe_name
	if ResourceLoader.exists(save_path):
		var idx := 1
		while ResourceLoader.exists("res://materials/%s_%d_palette.tres" % [safe_name, idx]):
			idx += 1
		save_path = "res://materials/%s_%d_palette.tres" % [safe_name, idx]
	pal.resource_path = save_path
	ResourceSaver.save(pal, save_path)
	EditorInterface.get_resource_filesystem().update_file(save_path)
	_rebuild_palette_dropdown()
	for i: int in _discovered_palettes.size():
		if _discovered_palettes[i].resource_path == save_path:
			_palette_option.select(i)
			_on_palette_selected(i)
			break


func _on_edit_palette_pressed() -> void:
	if not _cond_palette_selected():
		return
	if not Engine.is_editor_hint():
		return
	var pal: GoBuildMaterialPalette = _discovered_palettes[_palette_option.selected]
	EditorInterface.edit_resource(pal)


func _on_delete_palette_pressed() -> void:
	if not _cond_palette_selected():
		return
	var pal: GoBuildMaterialPalette = _discovered_palettes[_palette_option.selected]
	var path: String = pal.resource_path
	if path.is_empty():
		return
	var delete_fn := func() -> void: _delete_palette_at(path)
	_show_confirm_dialog_async(
			"Delete palette '%s'?" % pal.palette_name,
			"This removes the .tres file from disk. Materials already applied "
			+ "to meshes are unaffected.",
			delete_fn,
	)


func _delete_palette_at(path: String) -> void:
	DirAccess.remove_absolute(path)
	EditorInterface.get_resource_filesystem().update_file(path)
	_rebuild_palette_dropdown()


func _on_palette_selected(_index: int) -> void:
	_connect_palette_signal()
	_rebuild_pal_material_list()
	refresh_buttons()


func _on_slot_inspect_pressed(slot_index: int) -> void:
	if not _cond_palette_selected():
		return
	if not Engine.is_editor_hint():
		return
	var pal: GoBuildMaterialPalette = _discovered_palettes[_palette_option.selected]
	if slot_index < 0 or slot_index >= pal.materials.size():
		return
	var mat: Material = pal.materials[slot_index]
	if mat != null:
		EditorInterface.edit_resource(mat)


func _on_slot_use_pressed(slot_index: int) -> void:
	if _target == null or _plugin == null:
		return
	if not _cond_palette_selected():
		return
	var pal: GoBuildMaterialPalette = _discovered_palettes[_palette_option.selected]
	if slot_index < 0 or slot_index >= pal.materials.size():
		return
	var mat: Material = pal.materials[slot_index]
	if _target.selection.get_mode() == SelectionManager.Mode.FACE:
		var sel_faces: Array[int] = _target.selection.get_selected_faces()
		if sel_faces.is_empty():
			return
		var faces: Array[int] = []
		faces.assign(sel_faces)
		_run_op(
			"Assign Material Slot %d" % slot_index,
			func(): MaterialAssignOperation.apply_to_selected_faces(
					_target.go_build_mesh, faces, slot_index, mat),
			false,
		)
	else:
		var all_face_indices: Array[int] = []
		all_face_indices.resize(_target.go_build_mesh.faces.size())
		for i: int in all_face_indices.size():
			all_face_indices[i] = i
		_run_op(
			"Assign Material Slot %d (All Faces)" % slot_index,
			func(): MaterialAssignOperation.apply(
					_target.go_build_mesh, all_face_indices, slot_index, mat),
			false,
		)


func _on_slot_remove_pressed(slot_index: int) -> void:
	if not _cond_palette_selected():
		return
	var pal: GoBuildMaterialPalette = _discovered_palettes[_palette_option.selected]
	if slot_index < 0 or slot_index >= pal.materials.size():
		return
	pal.materials.remove_at(slot_index)
	ResourceSaver.save(pal, pal.resource_path)
	EditorInterface.get_resource_filesystem().update_file(pal.resource_path)
	_rebuild_pal_material_list()


# ---------------------------------------------------------------------------
# Palette resource signal
# ---------------------------------------------------------------------------

func _connect_palette_signal() -> void:
	_disconnect_palette_signal()
	if not _cond_palette_selected():
		return
	_connected_palette = _discovered_palettes[_palette_option.selected]
	if _connected_palette != null:
		_connected_palette.changed.connect(_on_palette_resource_changed)


func _disconnect_palette_signal() -> void:
	if _connected_palette != null and is_instance_valid(_connected_palette):
		if _connected_palette.changed.is_connected(_on_palette_resource_changed):
			_connected_palette.changed.disconnect(_on_palette_resource_changed)
	_connected_palette = null


func _on_palette_resource_changed() -> void:
	_rebuild_pal_material_list()


# ---------------------------------------------------------------------------
# UI helpers
# ---------------------------------------------------------------------------

func _rebuild_palette_dropdown() -> void:
	if _palette_option == null:
		return
	var prev_selected: int = _palette_option.selected
	var prev_path: String = ""
	if prev_selected >= 0 and prev_selected < _discovered_palettes.size():
		prev_path = _discovered_palettes[prev_selected].resource_path

	_discovered_palettes = GoBuildProjectSettings.discover_palettes()
	_palette_option.clear()
	var new_selected: int = -1
	for i: int in _discovered_palettes.size():
		var pal: GoBuildMaterialPalette = _discovered_palettes[i]
		var display: String
		if pal.palette_name != "":
			display = pal.palette_name
		else:
			var path: String = pal.resource_path
			display = path.get_file() if path != "" else "(unnamed)"
		_palette_option.add_item(display)
		if pal.resource_path == prev_path:
			new_selected = i

	if new_selected < 0 and not _discovered_palettes.is_empty():
		new_selected = 0
	_palette_option.select(new_selected)
	_on_palette_selected(new_selected)
	refresh_buttons()


func _rebuild_pal_material_list() -> void:
	for child in _pal_materials_vbox.get_children():
		_pal_materials_vbox.remove_child(child)
		child.queue_free()
	if not _cond_palette_selected():
		var empty_lbl := Label.new()
		empty_lbl.text = "  (no palette selected)"
		empty_lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
		empty_lbl.add_theme_font_size_override("font_size", 10)
		_pal_materials_vbox.add_child(empty_lbl)
		return
	var pal: GoBuildMaterialPalette = _discovered_palettes[_palette_option.selected]
	if pal.materials.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "  (empty palette — click Edit to add materials)"
		empty_lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
		empty_lbl.add_theme_font_size_override("font_size", 10)
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_pal_materials_vbox.add_child(empty_lbl)
		return
	for i: int in pal.materials.size():
		var mat: Material = pal.materials[i]
		var row := HBoxContainer.new()
		_pal_materials_vbox.add_child(row)

		var preview := _make_material_preview(mat)
		preview.gui_input.connect(_on_preview_input.bind(mat))
		row.add_child(preview)

		var slot_btn := Button.new()
		slot_btn.flat = true
		slot_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot_btn.add_theme_font_size_override("font_size", 10)
		slot_btn.text = "Slot %d" % i
		var mat_name: String
		if mat == null:
			mat_name = "(null)"
		elif mat.resource_name != "":
			mat_name = mat.resource_name
		elif mat.resource_path != "":
			mat_name = mat.resource_path.get_file()
		else:
			mat_name = mat.get_class()
		slot_btn.tooltip_text = mat_name + "\nClick to open in Inspector."
		slot_btn.pressed.connect(_on_slot_inspect_pressed.bind(i))
		row.add_child(slot_btn)

		var use_btn := Button.new()
		use_btn.text = "Use"
		use_btn.tooltip_text = _build_use_tooltip(i)
		use_btn.custom_minimum_size.x = 34
		use_btn.add_theme_font_size_override("font_size", 10)
		use_btn.pressed.connect(_on_slot_use_pressed.bind(i))
		row.add_child(use_btn)

		var remove_btn := Button.new()
		remove_btn.text = "\u00d7"
		remove_btn.tooltip_text = "Remove this material from the palette."
		remove_btn.add_theme_font_size_override("font_size", 10)
		remove_btn.pressed.connect(_on_slot_remove_pressed.bind(i))
		row.add_child(remove_btn)


func _make_material_preview(mat: Material) -> Control:
	var container := MarginContainer.new()
	container.custom_minimum_size = Vector2(64, 64)
	container.add_theme_constant_override("margin_left", 2)
	container.add_theme_constant_override("margin_top", 2)
	container.add_theme_constant_override("margin_right", 2)
	container.add_theme_constant_override("margin_bottom", 2)

	if mat is BaseMaterial3D:
		var bmat: BaseMaterial3D = mat as BaseMaterial3D
		if bmat.albedo_texture != null:
			var tex_rect := TextureRect.new()
			tex_rect.texture = bmat.albedo_texture
			tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tex_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
			container.add_child(tex_rect)
		else:
			var swatch := ColorRect.new()
			swatch.color = bmat.albedo_color
			swatch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			swatch.size_flags_vertical = Control.SIZE_EXPAND_FILL
			container.add_child(swatch)
	elif mat == null:
		var swatch := ColorRect.new()
		swatch.color = Color(0.25, 0.25, 0.25)
		swatch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		swatch.size_flags_vertical = Control.SIZE_EXPAND_FILL
		container.add_child(swatch)
	else:
		var swatch := ColorRect.new()
		swatch.color = Color(0.5, 0.5, 0.5)
		swatch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		swatch.size_flags_vertical = Control.SIZE_EXPAND_FILL
		container.add_child(swatch)

	return container


func _on_preview_input(event: InputEvent, mat: Material) -> void:
	if not Engine.is_editor_hint():
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if mat != null:
			EditorInterface.edit_resource(mat)


func _build_use_tooltip(slot_index: int) -> String:
	if _target == null:
		return "Assign to material slot %d." % slot_index
	if _target.selection.get_mode() == SelectionManager.Mode.FACE:
		return (
				"Assign selected faces to material slot %d.\n" % slot_index
				+ "Requires Face mode with >=1 face selected."
		)
	return (
			"Assign ALL faces to material slot %d.\n" % slot_index
			+ "In Object mode, this applies the material to the entire mesh."
	)


func _show_name_dialog_async(title: String, default_text: String, on_confirmed: Callable) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = title
	dialog.ok_button_text = "Create"

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size.x = 300
	dialog.add_child(vbox)

	var line_edit := LineEdit.new()
	line_edit.text = default_text
	line_edit.select_all()
	line_edit.placeholder_text = "Palette name"
	vbox.add_child(line_edit)

	var path_lbl := Label.new()
	path_lbl.add_theme_font_size_override("font_size", 10)
	path_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	vbox.add_child(path_lbl)

	var update_path := func(text: String) -> void:
		var safe := text.to_snake_case()
		if safe.is_empty():
			safe = "palette"
		path_lbl.text = "res://materials/%s_palette.tres" % safe
	update_path.call(default_text)

	line_edit.text_changed.connect(update_path)

	EditorInterface.popup_dialog_centered(dialog)
	line_edit.grab_focus.call_deferred()
	line_edit.select_all.call_deferred()

	var on_confirm_fn := func() -> void:
		var name: String = line_edit.text.strip_edges()
		dialog.queue_free()
		if not name.is_empty():
			on_confirmed.call(name)
	var on_cancel_fn := func() -> void:
		dialog.queue_free()
	dialog.confirmed.connect(on_confirm_fn)
	dialog.canceled.connect(on_cancel_fn)


func _show_confirm_dialog_async(title: String, message: String, on_confirmed: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = title
	dialog.dialog_text = message
	dialog.ok_button_text = "Delete"
	dialog.cancel_button_text = "Cancel"
	EditorInterface.popup_dialog_centered(dialog)
	var on_confirm_fn := func() -> void:
		dialog.queue_free()
		on_confirmed.call()
	var on_cancel_fn := func() -> void:
		dialog.queue_free()
	dialog.confirmed.connect(on_confirm_fn)
	dialog.canceled.connect(on_cancel_fn)
