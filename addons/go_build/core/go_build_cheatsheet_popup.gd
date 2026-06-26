## Scannable cheatsheet popup for all GoBuild hotkeys and gestures.
##
## Opened via the "Help" button in the panel header.
## Displays hotkeys organised by category in a balanced two-column layout.
@tool
class_name GoBuildCheatsheetPopup
extends PopupPanel

const _SECTION_COLOR := Color(0.7, 0.85, 1.0)
const _KEY_BG_COLOR := Color(0.25, 0.28, 0.32)
const _DESC_COLOR := Color(0.85, 0.85, 0.85)
const _ROW_SPACING := 2
const _SECTION_SPACING := 8
const _COL_SPACING := 24
const _FONT_SIZE := 13
const _KEY_FONT_SIZE := 12


func _ready() -> void:
	var content := _build_content()
	add_child(content)
	content.minimum_size_changed.connect(func() -> void:
			size = Vector2i(content.get_combined_minimum_size() + Vector2(24, 24))
	)
	size = Vector2i(content.get_combined_minimum_size() + Vector2(24, 24))
	close_requested.connect(func() -> void: queue_free())


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
		hide()
		queue_free()


static func _build_content() -> HBoxContainer:
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", _COL_SPACING)

	var sections: Array[Dictionary] = _get_sections()
	var mid_point: int = _find_midpoint(sections)

	var left_col := VBoxContainer.new()
	left_col.add_theme_constant_override("separation", _SECTION_SPACING)
	var right_col := VBoxContainer.new()
	right_col.add_theme_constant_override("separation", _SECTION_SPACING)

	for i: int in sections.size():
		var target: VBoxContainer = left_col if i < mid_point else right_col
		var section: Dictionary = sections[i]
		_add_section(target, section)

	root.add_child(left_col)
	root.add_child(right_col)
	return root


static func _find_midpoint(sections: Array[Dictionary]) -> int:
	var total_rows: int = 0
	for section: Dictionary in sections:
		total_rows += section.rows.size()
	var accum: int = 0
	for i: int in sections.size():
		accum += sections[i].rows.size()
		if accum >= total_rows / 2:
			return i + 1
	return sections.size()


static func _add_section(parent: VBoxContainer, section: Dictionary) -> void:
	var title_label := Label.new()
	title_label.text = section.title
	title_label.add_theme_font_size_override("font_size", _FONT_SIZE + 1)
	title_label.add_theme_color_override("font_color", _SECTION_COLOR)
	parent.add_child(title_label)

	for row: Dictionary in section.rows:
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 6)
		var key_label := Label.new()
		key_label.text = row.key
		key_label.add_theme_font_size_override("font_size", _KEY_FONT_SIZE)
		key_label.add_theme_color_override("font_color", Color.WHITE)
		key_label.add_theme_color_override("font_outline_color", Color.BLACK)
		key_label.add_theme_constant_override("outline_size", 1)
		key_label.custom_minimum_size = Vector2(170, 0)
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hbox.add_child(key_label)

		var desc_label := Label.new()
		desc_label.text = row.desc
		desc_label.add_theme_font_size_override("font_size", _FONT_SIZE)
		desc_label.add_theme_color_override("font_color", _DESC_COLOR)
		hbox.add_child(desc_label)
		desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		parent.add_child(hbox)

	var sep := HSeparator.new()
	parent.add_child(sep)


static func _get_sections() -> Array[Dictionary]:
	var sections: Array[Dictionary] = []
	sections.append({
		title = "── Mode ──",
		rows = [
			{key = "1", desc = "Object mode"},
			{key = "2", desc = "Vertex mode"},
			{key = "3", desc = "Edge mode"},
			{key = "4", desc = "Face mode"},
		]
	})
	sections.append({
		title = "── Selection ──",
		rows = [
			{key = "LMB", desc = "Select element"},
			{key = "Shift + LMB", desc = "Add to selection"},
			{key = "Ctrl + LMB", desc = "Toggle selection"},
			{key = "LMB Drag", desc = "Box select"},
			{key = "Ctrl + =", desc = "Grow selection"},
			{key = "Ctrl + -", desc = "Shrink selection"},
		{key = "Alt + Click (Edge)", desc = "Cycle Loop / Path to edge"},
		{key = "Alt + Click (Face)", desc = "Select Path to face"},
			{key = "Ctrl+Alt + Click", desc = "Select Ring"},
		]
	})
	sections.append({
		title = "── Transform ──",
		rows = [
			{key = "W", desc = "Translate (Move)"},
			{key = "E", desc = "Rotate"},
			{key = "R", desc = "Scale"},
			{key = "Ctrl", desc = "Snap to grid (drag)"},
			{key = "Shift", desc = "Precision mode (10%)"},
			{key = "Alt + Drag", desc = "Vertex snap"},
		]
	})
	sections.append({
		title = "── Modelling ──",
		rows = [
			{key = "Shift + Drag (Face)", desc = "Extrude face"},
			{key = "Shift + Drag (Edge)", desc = "Extrude edge"},
			{key = "Shift + Scale (Face)", desc = "Inset face"},
			{key = "F", desc = "Bridge / Fill edges"},
			{key = "M", desc = "Merge vertices"},
			{key = "Delete / X", desc = "Delete elements"},
		]
	})
	sections.append({
		title = "── Context Menu ──",
		rows = [
			{key = "Right-click", desc = "Context menu"},
			{key = "Select Similar →", desc = "By material / normals / etc."},
		]
	})
	sections.append({
		title = "── General ──",
		rows = [
			{key = "Esc", desc = "Cancel operation"},
		]
	})
	return sections
