## Viewport-anchored popup panels for tool workflows.
##
## Static helpers that build a plain [PanelContainer] (NOT a [PopupPanel] —
## popups close on outside clicks, which swallows tool anchor clicks) with a
## title plus label/button rows, anchored to a corner of the 3D viewport.
## The caller owns the returned panel's lifetime (hide via [method hide_popup],
## or free the container's child when the tool ends).
@tool
class_name GoBuildPopupServer
extends RefCounted

const _POPUP_MARGIN: float = 16.0

## Anchors: "top-right", "top-left", "bottom-right", "bottom-left".
static func show_popup(
		container: Control,
		title: String,
		rows: Array,
		vp_rect: Rect2,
		anchor: String = "top-right",
) -> PanelContainer:
	var popup := PanelContainer.new()
	var vbox := VBoxContainer.new()
	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(title_label)
	for row: Dictionary in rows:
		var btn := Button.new()
		btn.text = str(row.get("label", ""))
		var action: Callable = row.get("on_pressed", Callable())
		if action.is_valid():
			btn.pressed.connect(action)
		vbox.add_child(btn)
	popup.add_child(vbox)
	container.add_child(popup)
	var size := popup.get_minimum_size()
	var pos := Vector2(_POPUP_MARGIN, _POPUP_MARGIN)
	if anchor.contains("right"):
		pos.x = vp_rect.size.x - size.x - _POPUP_MARGIN
	if anchor.contains("bottom"):
		pos.y = vp_rect.size.y - size.y - _POPUP_MARGIN
	popup.position = pos
	popup.show()
	return popup


## Remove a popup created by [method show_popup] (safe on already-freed).
static func hide_popup(popup: PanelContainer) -> void:
	if popup != null and is_instance_valid(popup):
		popup.queue_free()