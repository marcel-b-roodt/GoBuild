## Locates and pins the [b]Physical / List-select[/b] tool button inside
## Godot's built-in [code]Node3DEditor[/code] toolbar.
##
## Physical mode (V) is the only native editor tool mode that renders
## [b]no[/b] transform gizmo at the object origin.  By keeping that button
## pressed whenever GoBuild is in a sub-element edit mode, the native
## move/rotate/scale handles stay hidden and only the custom GoBuild
## gizmo handles are visible.
##
## When returning to Object mode, [method restore_native_tool_mode] presses
## the native W/E/R button that matches GoBuild's active [TransformMode],
## keeping the native and GoBuild transform modes in sync.
##
## [b]Why two-step press[/b]: [member BaseButton.button_pressed] (= [code]set_pressed()[/code])
## only updates the ButtonGroup visual — it does [b]not[/b] emit the
## [code]pressed[/code] signal.  [code]Node3DEditor._menu_item_pressed[/code] is
## wired to [code]pressed[/code] in C++, so [code]button_pressed = true[/code] alone
## never changes the C++ [code]tool_mode[/code].
## [code]set_pressed_no_signal(true)[/code] + [code]emit_signal("pressed")[/code]
## is the correct pair: visual update + C++ handler trigger.
##
## [b]Finding the button — two strategies[/b]:
## [br]1. Shortcut scan: recursively walk the [code]Node3DEditor[/code] subtree
##    looking for a [Button] whose [member Button.shortcut] contains an
##    [InputEventKey] with [code]keycode[/code] or [code]physical_keycode[/code]
##    equal to a target key (V, W, E, R, or Q).
## [br]2. Tooltip scan: find the Q (Select) button via the same walk, take its
##    [ButtonGroup], and scan all buttons for one whose [member Control.tooltip_text]
##    contains "list" or "physical".  Strategy 2 is the fallback for Godot
##    builds where [code]ED_SHORTCUT[/code] stores [code]keycode = KEY_NONE[/code].
@tool
class_name Node3DEditorToolPinner
extends RefCounted

# Self-preloads — dependency order.
const _SEL_MGR_SCRIPT := preload("res://addons/go_build/core/selection_manager.gd")

var _button: Button = null
var _button_w: Button = null
var _button_e: Button = null
var _button_r: Button = null


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Press the Physical/List-select (V) button if it is not already active.
## Safe to call every frame; no-ops when the button is already pressed.
func suppress() -> void:
	var btn := _get_button()
	if btn == null:
		return
	if not btn.button_pressed:
		btn.set_pressed_no_signal(true)
	btn.emit_signal("pressed")


## Press the Physical/List-select button only when [param mode] is not
## [constant SelectionManager.Mode.OBJECT].  Intended for per-frame polling.
func pin_if_active(mode: SelectionManager.Mode) -> void:
	if mode == SelectionManager.Mode.OBJECT:
		return
	var btn := _button
	if btn == null or not is_instance_valid(btn):
		_button = null
		suppress()
		return
	if not btn.button_pressed:
		GoBuildDebug.log("[GoBuild] ToolPinner.pin_if_active  re-pressing V button")
		btn.set_pressed_no_signal(true)
		btn.emit_signal("pressed")


## Discard the cached button references (e.g. on plugin unload).
func invalidate() -> void:
	_button = null
	_button_w = null
	_button_e = null
	_button_r = null


## Press the native W/E/R button matching GoBuild's [param transform_mode]
## (TRANSLATE=0, ROTATE=1, SCALE=2).  Falls back to Move (W) if the target
## button cannot be found.  Call when returning to Object mode so the native
## editor gizmo matches what the user was using in GoBuild.
func restore_native_tool_mode(transform_mode: int) -> void:
	_ensure_transform_buttons()
	var btn: Button = null
	match transform_mode:
		0: btn = _button_w
		1: btn = _button_e
		2: btn = _button_r
	if btn == null or not is_instance_valid(btn):
		btn = _button_w
	if btn == null:
		return
	btn.set_pressed_no_signal(true)
	btn.emit_signal("pressed")


## Locate and cache the W/E/R transform buttons from the Node3DEditor toolbar.
## No-ops if they are already cached.
func _ensure_transform_buttons() -> void:
	if _button_w != null and is_instance_valid(_button_w) \
			and _button_e != null and is_instance_valid(_button_e) \
			and _button_r != null and is_instance_valid(_button_r):
		return
	var n3de: Node = _get_node3d_editor()
	if n3de == null:
		return
	_button_w = find_button_by_shortcut(n3de, KEY_W)
	_button_e = find_button_by_shortcut(n3de, KEY_E)
	_button_r = find_button_by_shortcut(n3de, KEY_R)


# ---------------------------------------------------------------------------
# Button lookup — two-strategy approach
# ---------------------------------------------------------------------------

## Locate and cache the Physical/List-select button.  Returns [code]null[/code]
## when neither strategy succeeds (logged via [GoBuildDebug]).
func _get_button() -> Button:
	if _button != null and is_instance_valid(_button):
		return _button
	var n3de: Node = _get_node3d_editor()
	if n3de == null:
		return null
	# Strategy 1: shortcut KEY_V.
	var btn := find_button_by_shortcut(n3de, KEY_V)
	if btn != null:
		_button = btn
		GoBuildDebug.log("[GoBuild] ToolPinner  V button found via shortcut strategy")
		return _button
	# Strategy 2: tooltip scan via Q button's ButtonGroup.
	var btn_q := find_button_by_shortcut(n3de, KEY_Q)
	if btn_q != null and btn_q.button_group != null:
		var group_btns := btn_q.button_group.get_buttons()
		GoBuildDebug.log(
				"[GoBuild] ToolPinner  ButtonGroup has %d buttons" % group_btns.size())
		for idx: int in group_btns.size():
			var gb: Button = group_btns[idx] as Button
			if gb == null:
				continue
			var tip: String = gb.tooltip_text.to_lower()
			GoBuildDebug.log("[GoBuild]   [%d] tooltip=%s  has_shortcut=%s" \
					% [idx, gb.tooltip_text,
					str(gb.shortcut != null and not gb.shortcut.events.is_empty())])
			if "list" in tip or "physical" in tip:
				_button = gb
				GoBuildDebug.log(
						"[GoBuild] ToolPinner  V button found via tooltip scan at index %d" % idx)
				return _button
		GoBuildDebug.log("[GoBuild] ToolPinner  no List/Physical tooltip found in ButtonGroup")
	else:
		GoBuildDebug.log(
				"[GoBuild] ToolPinner  Q button not found or has no ButtonGroup")
	return null


## Get the [code]Node3DEditor[/code] node by walking up from the first
## 3D viewport.  Returns [code]null[/code] if not available.
func _get_node3d_editor() -> Node:
	if not Engine.is_editor_hint():
		return null
	if not ClassDB.class_has_method("EditorInterface", "get_editor_viewport_3d"):
		return null
	var sv := EditorInterface.get_editor_viewport_3d(0)
	if sv == null:
		return null
	return _find_node3d_editor(sv)


## Walk up the scene tree from [param start] until a node whose class name is
## [code]Node3DEditor[/code] is found.  Returns [code]null[/code] if not found.
static func _find_node3d_editor(start: Node) -> Node:
	var node: Node = start.get_parent()
	while node != null:
		if node.get_class() == "Node3DEditor":
			return node
		node = node.get_parent()
	return null


## Recursively search [param root]'s subtree for the first [Button] whose
## [member Button.shortcut] contains an [InputEventKey] with [param keycode]
## matching either [code]keycode[/code] or [code]physical_keycode[/code].
## Returns [code]null[/code] if not found.
static func find_button_by_shortcut(root: Node, keycode: Key) -> Button:
	if root is Button:
		var btn := root as Button
		if btn.shortcut != null:
			for evt: InputEvent in btn.shortcut.events:
				if evt is InputEventKey:
					var key_evt := evt as InputEventKey
					if key_evt.keycode == keycode \
							or key_evt.physical_keycode == keycode:
						return btn
	for child: Node in root.get_children():
		var result := find_button_by_shortcut(child, keycode)
		if result != null:
			return result
	return null


## Find the first [Button] in [param group_buttons] whose
## [member Control.tooltip_text] (lowercased) contains any word in
## [param keywords].  Returns [code]null[/code] if none match.
static func find_button_by_tooltip(
		group_buttons: Array, keywords: Array[String]) -> Button:
	for item: Variant in group_buttons:
		if not (item is Button):
			continue
		var tip: String = (item as Button).tooltip_text.to_lower()
		for kw: String in keywords:
			if kw in tip:
				return item as Button
	return null