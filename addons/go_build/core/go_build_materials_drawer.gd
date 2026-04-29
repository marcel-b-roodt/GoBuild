## Self-contained Materials drawer for the GoBuild editor panel.
##
## Manages palette selection, material slot assignment, quickset prototype
## materials, and the live slot preview list.
##
## Drop it into any VBoxContainer with [method add_child].  After adding, call
## [method set_plugin] and [method set_project_settings] once, then call
## [method set_target] whenever the selected [GoBuildMeshInstance] changes.
##
## The owning panel is responsible for calling [method refresh] on
## mesh-changed events and [method refresh_buttons] on selection-changed events.
@tool
class_name GoBuildMaterialsDrawer
extends VBoxContainer

# Self-preloads — dependency order.
const _SEL_MGR_SCRIPT    := preload("res://addons/go_build/core/selection_manager.gd")
const _MESH_INST_SCRIPT  := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _MATERIALS_SCRIPT  := preload("res://addons/go_build/core/go_build_materials.gd")
const _MAT_ASSIGN_SCRIPT := \
		preload("res://addons/go_build/mesh/operations/material_assign_operation.gd")
const _PALETTE_SCRIPT    := \
		preload("res://addons/go_build/core/go_build_material_palette.gd")
const _SETTINGS_SCRIPT   := \
		preload("res://addons/go_build/core/go_build_project_settings.gd")

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _plugin: EditorPlugin                  = null
var _target: GoBuildMeshInstance           = null
var _project_settings: GoBuildProjectSettings = null

# UI widgets
var _palette_option:      OptionButton         = null
var _apply_palette_btn:   Button               = null
var _settings_picker:     EditorResourcePicker = null
var _mat_palette_vbox:    VBoxContainer        = null
var _material_slot_spin:  SpinBox              = null
var _assign_material_btn: Button               = null
var _qs_checker_btn:      Button               = null
var _qs_white_btn:        Button               = null
var _qs_grey_btn:         Button               = null

## Registry of [Button] → [Callable] condition pairs.
var _op_entries: Array = []


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Provide the owning [EditorPlugin] so operations can access [method EditorPlugin.get_undo_redo].
func set_plugin(plugin: EditorPlugin) -> void:
	_plugin = plugin


## Point the drawer at a new mesh instance (or [code]null[/code] to clear).
func set_target(target: GoBuildMeshInstance) -> void:
	_target = target


## Update the active project settings and reconnect change signals.
## Pass [code]null[/code] to detach from any existing settings resource.
func set_project_settings(settings: GoBuildProjectSettings) -> void:
	if _project_settings != null \
			and _project_settings.changed.is_connected(_rebuild_palette_dropdown):
		_project_settings.changed.disconnect(_rebuild_palette_dropdown)
	_project_settings = settings
	if _settings_picker != null:
		_settings_picker.edited_resource = settings
	if settings != null:
		settings.changed.connect(_rebuild_palette_dropdown)
	_rebuild_palette_dropdown()


## Full refresh: update button states and rebuild the live material slot list.
## Call this whenever the mesh data changes (e.g. after any mesh operation).
func refresh() -> void:
	refresh_buttons()
	_rebuild_mat_palette()


## Lightweight refresh: update button enabled/disabled states only.
## Call this on selection-changed events where the slot list has not changed.
func refresh_buttons() -> void:
	for entry in _op_entries:
		entry.button.disabled = not entry.condition.call()


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Drawer header — mirrors _make_drawer() on GoBuildPanel exactly.
	var btn := Button.new()
	btn.text = "\u25b6  Materials"
	btn.toggle_mode = true
	btn.button_pressed = false
	btn.flat = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 11)
	add_child(btn)

	var ctn := VBoxContainer.new()
	ctn.visible = false
	add_child(ctn)

	btn.toggled.connect(func(pressed: bool) -> void:
		ctn.visible = pressed
		btn.text = ("\u25bc  " if pressed else "\u25b6  ") + "Materials"
	)

	# ── Settings resource picker ─────────────────────────────────────────
	var settings_row := HBoxContainer.new()
	ctn.add_child(settings_row)

	var settings_lbl := Label.new()
	settings_lbl.text = "Settings:"
	settings_lbl.add_theme_font_size_override("font_size", 11)
	settings_row.add_child(settings_lbl)

	_settings_picker = EditorResourcePicker.new()
	_settings_picker.base_type = "GoBuildProjectSettings"
	_settings_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_picker.tooltip_text = (
			"The active GoBuildProjectSettings resource.\n"
			+ "Drag a .tres from the FileSystem to use a different settings file.\n"
			+ "Defaults to res://addons/go_build/go_build_settings.tres (created automatically)."
	)
	_settings_picker.resource_changed.connect(_on_settings_resource_changed)
	settings_row.add_child(_settings_picker)

	# ── Palette row ──────────────────────────────────────────────────────
	var pal_row := HBoxContainer.new()
	ctn.add_child(pal_row)

	var pal_lbl := Label.new()
	pal_lbl.text = "Palette:"
	pal_lbl.add_theme_font_size_override("font_size", 11)
	pal_row.add_child(pal_lbl)

	_palette_option = OptionButton.new()
	_palette_option.flat = true
	_palette_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_palette_option.add_theme_font_size_override("font_size", 11)
	_palette_option.tooltip_text = (
			"Select a project palette to apply.\n"
			+ "Add palettes by editing go_build_settings.tres in the FileSystem dock."
	)
	pal_row.add_child(_palette_option)

	_apply_palette_btn = _op_button("Apply",
			"Copy the selected palette's materials into the mesh's material_slots.\n"
			+ "Existing face material_index values are unchanged; only the slot "
			+ "objects are replaced.")
	_apply_palette_btn.pressed.connect(_on_apply_palette_pressed)
	pal_row.add_child(_apply_palette_btn)
	_register_op(_apply_palette_btn, _cond_palette_apply)

	var pal_refresh_btn := Button.new()
	pal_refresh_btn.text = "\u21ba"
	pal_refresh_btn.flat = true
	pal_refresh_btn.tooltip_text = "Reload palettes from go_build_settings.tres."
	pal_refresh_btn.pressed.connect(_rebuild_palette_dropdown)
	pal_row.add_child(pal_refresh_btn)

	# ── Slot assignment ──────────────────────────────────────────────────
	var mat_grid := GridContainer.new()
	mat_grid.columns = 2
	ctn.add_child(mat_grid)

	var slot_lbl := Label.new()
	slot_lbl.text = "Slot:"
	slot_lbl.add_theme_font_size_override("font_size", 11)
	mat_grid.add_child(slot_lbl)

	_material_slot_spin = SpinBox.new()
	_material_slot_spin.min_value = 0
	_material_slot_spin.max_value = 15
	_material_slot_spin.step = 1
	_material_slot_spin.rounded = true
	_material_slot_spin.value = 0
	_material_slot_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mat_grid.add_child(_material_slot_spin)

	_assign_material_btn = _op_button("Assign to Faces",
		"Assign selected face(s) to the chosen material slot.\n"
		+ "Add materials to slots via the Inspector (go_build_mesh \u2192 material_slots).\n"
		+ "Requires Face mode with \u22651 face selected.")
	_assign_material_btn.pressed.connect(_on_assign_material_pressed)
	mat_grid.add_child(_assign_material_btn)
	_register_op(_assign_material_btn, _cond_face_any)

	# Spacer so the button is 2-wide in the grid.
	mat_grid.add_child(Control.new())

	# ── Quicksets ────────────────────────────────────────────────────────
	var qs_lbl := Label.new()
	qs_lbl.text = "Quicksets:"
	qs_lbl.add_theme_font_size_override("font_size", 11)
	qs_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	ctn.add_child(qs_lbl)

	var qs_grid := GridContainer.new()
	qs_grid.columns = 3
	ctn.add_child(qs_grid)

	_qs_checker_btn = _op_button("Checker",
		"Apply a procedural B&W checker material to selected faces.\n"
		+ "One tile = one mesh unit, matching UV scale 1.0 for instant scale feedback.\n"
		+ "Requires Face mode with \u22651 face selected.")
	_qs_checker_btn.pressed.connect(_on_quickset_pressed.bind(0, GoBuildMaterials.checker_material))
	qs_grid.add_child(_qs_checker_btn)
	_register_op(_qs_checker_btn, _cond_face_any)

	_qs_white_btn = _op_button("White",
		"Apply a solid-white prototype material to selected faces.\n"
		+ "Requires Face mode with \u22651 face selected.")
	_qs_white_btn.pressed.connect(_on_quickset_pressed.bind(1, GoBuildMaterials.white_material))
	qs_grid.add_child(_qs_white_btn)
	_register_op(_qs_white_btn, _cond_face_any)

	_qs_grey_btn = _op_button("Grey",
		"Apply a mid-grey prototype material to selected faces.\n"
		+ "Requires Face mode with \u22651 face selected.")
	_qs_grey_btn.pressed.connect(_on_quickset_pressed.bind(2, GoBuildMaterials.grey_material))
	qs_grid.add_child(_qs_grey_btn)
	_register_op(_qs_grey_btn, _cond_face_any)

	# ── Live slot list ────────────────────────────────────────────────────
	var slots_hdr := Label.new()
	slots_hdr.text = "Slots:"
	slots_hdr.add_theme_font_size_override("font_size", 11)
	slots_hdr.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	ctn.add_child(slots_hdr)

	_mat_palette_vbox = VBoxContainer.new()
	_mat_palette_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctn.add_child(_mat_palette_vbox)


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _op_button(text: String, tooltip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 11)
	b.tooltip_text = tooltip
	b.disabled = true
	return b


func _register_op(b: Button, condition: Callable) -> void:
	_op_entries.append({"button": b, "condition": condition})


## Run [param op_callable] as a single undo/redo action, then update gizmos.
## The owning panel's [method _refresh] is driven by the mesh_changed signal
## that [method GoBuildMeshInstance.bake] emits, so no explicit refresh call
## is needed here.
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


# ---------------------------------------------------------------------------
# Conditions
# ---------------------------------------------------------------------------

## [code]true[/code] when Face mode is active and \u22651 face is selected.
func _cond_face_any() -> bool:
	return _target != null \
			and _target.selection.get_mode() == SelectionManager.Mode.FACE \
			and not _target.selection.get_selected_faces().is_empty()


## [code]true[/code] when settings are loaded, a palette is selected, and a
## target mesh is present.
func _cond_palette_apply() -> bool:
	return _target != null \
			and _project_settings != null \
			and not _project_settings.palettes.is_empty() \
			and _palette_option != null \
			and _palette_option.selected >= 0


# ---------------------------------------------------------------------------
# Operation handlers
# ---------------------------------------------------------------------------

func _on_apply_palette_pressed() -> void:
	if _target == null or _plugin == null or _project_settings == null:
		return
	if _palette_option == null or _palette_option.selected < 0:
		return
	var palette: GoBuildMaterialPalette = \
			_project_settings.palettes[_palette_option.selected]
	if palette == null:
		return
	var new_slots: Array[Material] = []
	new_slots.assign(palette.materials)
	_run_op(
		"Apply Material Palette",
		func(): _target.go_build_mesh.material_slots = new_slots,
		false,
	)


func _on_settings_resource_changed(resource: Resource) -> void:
	if resource is GoBuildProjectSettings:
		_project_settings = resource as GoBuildProjectSettings
	elif resource == null:
		_project_settings = GoBuildProjectSettings.load_or_create()
		if _settings_picker != null:
			_settings_picker.edited_resource = _project_settings
	_rebuild_palette_dropdown()


## Repopulate [member _palette_option] from the project-wide palette list.
## Safe to call before [member _project_settings] is assigned (no-ops).
func _rebuild_palette_dropdown() -> void:
	if _palette_option == null:
		return
	_palette_option.clear()
	if _project_settings == null:
		return
	for pal: GoBuildMaterialPalette in _project_settings.palettes:
		var display: String
		if pal == null:
			display = "(null)"
		elif pal.palette_name != "":
			display = pal.palette_name
		else:
			var path: String = pal.resource_path
			display = path.get_file() if path != "" else "(unnamed)"
		_palette_option.add_item(display)
	refresh_buttons()


## Rebuild the live slot list.  Clears and repopulates [member _mat_palette_vbox]
## with one row per entry in [member GoBuildMesh.material_slots].
## Shows a placeholder label when no slots exist.
func _rebuild_mat_palette() -> void:
	for child in _mat_palette_vbox.get_children():
		_mat_palette_vbox.remove_child(child)
		child.queue_free()
	if _target == null or _target.go_build_mesh == null:
		return
	var slots: Array[Material] = _target.go_build_mesh.material_slots
	if slots.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "  (no slots \u2014 assign via Inspector)"
		empty_lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
		empty_lbl.add_theme_font_size_override("font_size", 10)
		_mat_palette_vbox.add_child(empty_lbl)
		return
	for i: int in slots.size():
		var mat: Material = slots[i]
		var row := HBoxContainer.new()
		_mat_palette_vbox.add_child(row)

		var idx_lbl := Label.new()
		idx_lbl.text = "[%d]" % i
		idx_lbl.custom_minimum_size.x = 26
		idx_lbl.add_theme_font_size_override("font_size", 10)
		row.add_child(idx_lbl)

		# Swatch: texture thumbnail when available, albedo colour otherwise.
		if mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture != null:
			var tex_rect := TextureRect.new()
			tex_rect.texture = (mat as BaseMaterial3D).albedo_texture
			tex_rect.custom_minimum_size = Vector2(16, 16)
			tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex_rect.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			tex_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(tex_rect)
		else:
			var swatch := ColorRect.new()
			swatch.custom_minimum_size = Vector2(14, 14)
			swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			if mat is BaseMaterial3D:
				swatch.color = (mat as BaseMaterial3D).albedo_color
			elif mat == null:
				swatch.color = Color(0.25, 0.25, 0.25)
			else:
				swatch.color = Color(0.5, 0.5, 0.5)
			row.add_child(swatch)

		var mat_name: String
		if mat == null:
			mat_name = "(null)"
		elif mat.resource_name != "":
			mat_name = mat.resource_name
		elif mat.resource_path != "":
			mat_name = mat.resource_path.get_file()
		else:
			mat_name = mat.get_class()
		var name_lbl := Label.new()
		name_lbl.text = mat_name
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.clip_text = true
		name_lbl.add_theme_font_size_override("font_size", 10)
		name_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
		row.add_child(name_lbl)

		var use_btn := Button.new()
		use_btn.text = "Use"
		use_btn.tooltip_text = (
			"Assign selected face(s) to material slot %d.\n"
			+ "Requires Face mode with \u22651 face selected." % i
		)
		use_btn.custom_minimum_size.x = 34
		use_btn.pressed.connect(_on_palette_slot_assign_pressed.bind(i))
		row.add_child(use_btn)


func _on_palette_slot_assign_pressed(slot_index: int) -> void:
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
		"Assign Material Slot %d" % slot_index,
		func(): MaterialAssignOperation.apply(_target.go_build_mesh, faces, slot_index),
		false,
	)


func _on_assign_material_pressed() -> void:
	if _target == null or _plugin == null:
		return
	if _target.selection.get_mode() != SelectionManager.Mode.FACE:
		return
	var sel_faces: Array[int] = _target.selection.get_selected_faces()
	if sel_faces.is_empty():
		return
	var faces: Array[int] = []
	faces.assign(sel_faces)
	var slot: int = int(_material_slot_spin.value)
	_run_op(
		"Assign Material Slot %d" % slot,
		func(): MaterialAssignOperation.apply(_target.go_build_mesh, faces, slot),
		false,
	)


func _on_quickset_pressed(slot_index: int, material_factory: Callable) -> void:
	if _target == null or _plugin == null:
		return
	if _target.selection.get_mode() != SelectionManager.Mode.FACE:
		return
	var sel_faces: Array[int] = _target.selection.get_selected_faces()
	if sel_faces.is_empty():
		return
	var faces: Array[int] = []
	faces.assign(sel_faces)
	var mat: Material = material_factory.call()
	_run_op(
		"Assign Quickset Material",
		func(): MaterialAssignOperation.apply(_target.go_build_mesh, faces, slot_index, mat),
		false,
	)
