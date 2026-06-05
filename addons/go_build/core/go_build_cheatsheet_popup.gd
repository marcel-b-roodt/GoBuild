## Scannable cheatsheet popup for all GoBuild hotkeys and gestures.
##
## Opened via F1 or the "?" button in the panel header.
## Displays hotkeys organised by category: General, Selection, Transform,
## Modelling, UV.
@tool
class_name GoBuildCheatsheetPopup
extends PopupPanel

const _SECTION_COLOR := Color(0.7, 0.85, 1.0)
const _KEY_BG_COLOR := Color(0.25, 0.28, 0.32)
const _DESC_COLOR := Color(0.85, 0.85, 0.85)
const _ROW_SPACING := 2
const _SECTION_SPACING := 8
const _FONT_SIZE := 12
const _KEY_FONT_SIZE := 11


func _ready() -> void:
	# Build the content when the popup is first shown.
	var content := _build_content()
	add_child(content)
	# Size to content with padding.
	content.minimum_size_changed.connect(func() -> void:
			size = Vector2i(content.get_combined_minimum_size() + Vector2(24, 24))
	)
	size = Vector2i(content.get_combined_minimum_size() + Vector2(24, 24))
	# Close on Escape or clicking outside.
	close_requested.connect(queue_free)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
		hide()
		queue_free()


static func _build_content() -> VBoxContainer:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", _SECTION_SPACING)

	var sections: Array[Dictionary] = _get_sections()
	for section: Dictionary in sections:
		var title_label := Label.new()
		title_label.text = section.title
		title_label.add_theme_font_size_override("font_size", _FONT_SIZE + 1)
		title_label.add_theme_color_override("font_color", _SECTION_COLOR)
		root.add_child(title_label)

		for row: Dictionary in section.rows:
			var hbox := HBoxContainer.new()
			hbox.add_theme_constant_override("separation", 6)
			var key_label := Label.new()
			key_label.text = row.key
			key_label.add_theme_font_size_override("font_size", _KEY_FONT_SIZE)
			key_label.add_theme_color_override("font_color", Color.WHITE)
			key_label.add_theme_color_override("font_outline_color", Color.BLACK)
			key_label.add_theme_constant_override("outline_size", 1)
			key_label.custom_minimum_size = Vector2(180, 0)
			key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			hbox.add_child(key_label)

			var desc_label := Label.new()
			desc_label.text = row.desc
			desc_label.add_theme_font_size_override("font_size", _FONT_SIZE)
			desc_label.add_theme_color_override("font_color", _DESC_COLOR)
			hbox.add_child(desc_label)

			# Make the desc label expand to fill.
			desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

			root.add_child(hbox)

		# Separator between sections (skip after the last).
		var sep := HSeparator.new()
		root.add_child(sep)

	# Remove trailing separator.
	if root.get_child_count() > 0:
		var last := root.get_child(root.get_child_count() - 1)
		if last is HSeparator:
			root.remove_child(last)
			last.queue_free()

	return root


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
		title = "── Transform ──",
		rows = [
			{key = "W", desc = "Translate (Move)"},
			{key = "E", desc = "Rotate"},
			{key = "R", desc = "Scale"},
			{key = "Ctrl", desc = "Snap to grid (while dragging)"},
			{key = "Shift", desc = "Precision mode (10% sensitivity)"},
			{key = "Alt + Drag", desc = "Vertex snap (translate/plane)"},
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
			{key = "Alt + Click (Edge)", desc = "Select Loop"},
			{key = "Alt + Click (Face)", desc = "Select Path to clicked face"},
			{key = "Ctrl+Alt + Click (Edge/Face)", desc = "Select Ring"},
		]
	})
	sections.append({
		title = "── Modelling ──",
		rows = [
			{key = "Shift + Drag (Face)", desc = "Extrude face"},
			{key = "Shift + Drag (Edge)", desc = "Extrude edge"},
			{key = "Shift + Scale (Face)", desc = "Inset face"},
			{key = "F", desc = "Bridge / Fill selected edges"},
			{key = "M", desc = "Merge selected vertices"},
			{key = "Delete / X", desc = "Delete selected elements"},
		]
	})
	sections.append({
		title = "── Context Menu (Right-click) ──",
		rows = [
			{key = "Right-click", desc = "Context menu (elements)"},
			{key = "Select Similar →", desc = "By material / normals / area / etc."},
		]
	})
	sections.append({
		title = "── General ──",
		rows = [
			{key = "Esc", desc = "Cancel current operation"},
			{key = "F1", desc = "Show this cheatsheet"},
		]
	})
	return sections