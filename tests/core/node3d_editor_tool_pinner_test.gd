## Unit tests for [Node3DEditorToolPinner] pure-logic helpers.
##
## [method Node3DEditorToolPinner.find_button_by_shortcut] and
## [method Node3DEditorToolPinner.find_button_by_tooltip] are pure functions
## with no editor-tree dependency and are fully testable in headless CI.
##
## The suppress/pin_if_active press mechanics require a live editor button;
## those are covered by mock-button tests below that verify the two-step press
## contract (set_pressed_no_signal + emit_signal) without needing Node3DEditor.
@tool
extends GdUnitTestSuite

var _press_count: int = 0


func _reset_press_count() -> void:
	_press_count = 0


func _on_button_pressed() -> void:
	_press_count += 1


# ---------------------------------------------------------------------------
# Helpers — build a minimal Button with a given shortcut key
# ---------------------------------------------------------------------------

func _make_button_with_key(keycode: Key) -> Button:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	var sc := Shortcut.new()
	sc.events = [ev]
	var btn := Button.new()
	btn.shortcut = sc
	return btn


func _make_button_with_physical_key(keycode: Key) -> Button:
	var ev := InputEventKey.new()
	ev.keycode          = KEY_NONE
	ev.physical_keycode = keycode
	var sc := Shortcut.new()
	sc.events = [ev]
	var btn := Button.new()
	btn.shortcut = sc
	return btn


func _make_button_with_tooltip(tip: String) -> Button:
	var btn := Button.new()
	btn.tooltip_text = tip
	return btn


# ---------------------------------------------------------------------------
# find_button_by_shortcut — direct keycode match
# ---------------------------------------------------------------------------

func test_find_button_by_shortcut_finds_direct_keycode() -> void:
	var root := Node.new()
	add_child(root)
	var btn := _make_button_with_key(KEY_Q)
	root.add_child(btn)
	var result := Node3DEditorToolPinner.find_button_by_shortcut(root, KEY_Q)
	assert_object(result).is_not_null().is_same(btn)
	root.queue_free()


func test_find_button_by_shortcut_finds_physical_keycode() -> void:
	var root := Node.new()
	add_child(root)
	var btn := _make_button_with_physical_key(KEY_V)
	root.add_child(btn)
	var result := Node3DEditorToolPinner.find_button_by_shortcut(root, KEY_V)
	assert_object(result).is_not_null().is_same(btn)
	root.queue_free()


func test_find_button_by_shortcut_returns_null_when_missing() -> void:
	var root := Node.new()
	add_child(root)
	var btn := _make_button_with_key(KEY_Q)
	root.add_child(btn)
	var result := Node3DEditorToolPinner.find_button_by_shortcut(root, KEY_W)
	assert_object(result).is_null()
	root.queue_free()


func test_find_button_by_shortcut_searches_nested_children() -> void:
	var root := Node.new()
	add_child(root)
	var mid := Node.new()
	root.add_child(mid)
	var btn := _make_button_with_key(KEY_E)
	mid.add_child(btn)
	var result := Node3DEditorToolPinner.find_button_by_shortcut(root, KEY_E)
	assert_object(result).is_not_null().is_same(btn)
	root.queue_free()


func test_find_button_by_shortcut_returns_first_match() -> void:
	var root := Node.new()
	add_child(root)
	var btn_a := _make_button_with_key(KEY_R)
	var btn_b := _make_button_with_key(KEY_R)
	root.add_child(btn_a)
	root.add_child(btn_b)
	var result := Node3DEditorToolPinner.find_button_by_shortcut(root, KEY_R)
	assert_object(result).is_same(btn_a)
	root.queue_free()


func test_find_button_by_shortcut_button_with_no_shortcut_skipped() -> void:
	var root := Node.new()
	add_child(root)
	var plain := Button.new()
	root.add_child(plain)
	var result := Node3DEditorToolPinner.find_button_by_shortcut(root, KEY_Q)
	assert_object(result).is_null()
	root.queue_free()


func test_find_button_by_shortcut_empty_tree_returns_null() -> void:
	var root := Node.new()
	add_child(root)
	var result := Node3DEditorToolPinner.find_button_by_shortcut(root, KEY_V)
	assert_object(result).is_null()
	root.queue_free()


# ---------------------------------------------------------------------------
# find_button_by_tooltip
# ---------------------------------------------------------------------------

func test_find_button_by_tooltip_matches_lowercase_keyword() -> void:
	var btn := _make_button_with_tooltip("List Select (Physical)")
	var result := Node3DEditorToolPinner.find_button_by_tooltip([btn], ["list"])
	assert_object(result).is_not_null().is_same(btn)


func test_find_button_by_tooltip_matches_second_keyword() -> void:
	var btn := _make_button_with_tooltip("Pan / Physical Mode")
	var result := Node3DEditorToolPinner.find_button_by_tooltip([btn], ["list", "physical"])
	assert_object(result).is_not_null().is_same(btn)


func test_find_button_by_tooltip_case_insensitive() -> void:
	var btn := _make_button_with_tooltip("LIST SELECT")
	var result := Node3DEditorToolPinner.find_button_by_tooltip([btn], ["list"])
	assert_object(result).is_not_null().is_same(btn)


func test_find_button_by_tooltip_returns_null_when_no_match() -> void:
	var btn := _make_button_with_tooltip("Move Mode (W)")
	var result := Node3DEditorToolPinner.find_button_by_tooltip([btn], ["list", "physical"])
	assert_object(result).is_null()


func test_find_button_by_tooltip_skips_non_button_items() -> void:
	var lbl := Label.new()
	lbl.tooltip_text = "List Select"
	var btn := _make_button_with_tooltip("Physical Mode")
	var result := Node3DEditorToolPinner.find_button_by_tooltip(
			[lbl, btn], ["physical"])
	assert_object(result).is_not_null().is_same(btn)


func test_find_button_by_tooltip_empty_array_returns_null() -> void:
	var result := Node3DEditorToolPinner.find_button_by_tooltip([], ["list"])
	assert_object(result).is_null()


# ---------------------------------------------------------------------------
# Two-step press contract — mock Button in a ButtonGroup
# ---------------------------------------------------------------------------

## Verifies that suppress() calls set_pressed_no_signal(true) and then
## emit_signal("pressed") by checking observable side-effects:
##   1. After suppress(), btn.button_pressed is true (no-signal sets visual).
##   2. The 'pressed' signal was emitted (counter incremented by listener).
func test_suppress_presses_button_and_emits_signal() -> void:
	var group := ButtonGroup.new()
	var btn := Button.new()
	btn.toggle_mode = true
	btn.button_group = group
	add_child(btn)

	_reset_press_count()
	btn.pressed.connect(_on_button_pressed)

	var pinner := Node3DEditorToolPinner.new()
	pinner._button = btn  # inject directly — skip editor walk

	pinner.suppress()

	assert_bool(btn.button_pressed).is_true()
	assert_int(_press_count).is_equal(1)
	btn.queue_free()


func test_suppress_still_emits_when_already_pressed() -> void:
	## suppress() should always emit pressed (to keep tool_mode in sync)
	## even when the visual is already correct.
	var btn := Button.new()
	btn.toggle_mode = true
	add_child(btn)
	btn.set_pressed_no_signal(true)  # pre-set visual

	_reset_press_count()
	btn.pressed.connect(_on_button_pressed)

	var pinner := Node3DEditorToolPinner.new()
	pinner._button = btn

	pinner.suppress()

	assert_int(_press_count).is_equal(1)
	btn.queue_free()


func test_suppress_with_null_button_does_not_crash() -> void:
	var pinner := Node3DEditorToolPinner.new()
	# _button is null, _get_button will also return null (no editor in headless CI)
	pinner.suppress()  # must not throw


# ---------------------------------------------------------------------------
# pin_if_active
# ---------------------------------------------------------------------------

func test_pin_if_active_skips_object_mode() -> void:
	var btn := Button.new()
	btn.toggle_mode = true
	add_child(btn)

	_reset_press_count()
	btn.pressed.connect(_on_button_pressed)

	var pinner := Node3DEditorToolPinner.new()
	pinner._button = btn

	pinner.pin_if_active(SelectionManager.Mode.OBJECT)

	assert_int(_press_count).is_equal(0)
	btn.queue_free()


func test_pin_if_active_presses_in_vertex_mode() -> void:
	var btn := Button.new()
	btn.toggle_mode = true
	add_child(btn)

	_reset_press_count()
	btn.pressed.connect(_on_button_pressed)

	var pinner := Node3DEditorToolPinner.new()
	pinner._button = btn

	pinner.pin_if_active(SelectionManager.Mode.VERTEX)

	assert_int(_press_count).is_equal(1)
	btn.queue_free()


func test_pin_if_active_no_op_when_already_pressed() -> void:
	var btn := Button.new()
	btn.toggle_mode = true
	add_child(btn)
	btn.set_pressed_no_signal(true)

	_reset_press_count()
	btn.pressed.connect(_on_button_pressed)

	var pinner := Node3DEditorToolPinner.new()
	pinner._button = btn

	pinner.pin_if_active(SelectionManager.Mode.FACE)

	assert_int(_press_count).is_equal(0)
	btn.queue_free()


# ---------------------------------------------------------------------------
# invalidate
# ---------------------------------------------------------------------------

func test_invalidate_clears_cached_button() -> void:
	var btn := Button.new()
	var pinner := Node3DEditorToolPinner.new()
	pinner._button = btn
	pinner._button_w = btn
	pinner._button_e = btn
	pinner._button_r = btn
	pinner.invalidate()
	assert_object(pinner._button).is_null()
	assert_object(pinner._button_w).is_null()
	assert_object(pinner._button_e).is_null()
	assert_object(pinner._button_r).is_null()


# ---------------------------------------------------------------------------
# restore_native_tool_mode
# ---------------------------------------------------------------------------

func test_restore_translate_presses_w() -> void:
	var btn_w := Button.new()
	btn_w.toggle_mode = true
	add_child(btn_w)

	var btn_e := Button.new()
	btn_e.toggle_mode = true
	add_child(btn_e)

	var btn_r := Button.new()
	btn_r.toggle_mode = true
	add_child(btn_r)

	_reset_press_count()
	btn_w.pressed.connect(_on_button_pressed)

	var pinner := Node3DEditorToolPinner.new()
	pinner._button_w = btn_w
	pinner._button_e = btn_e
	pinner._button_r = btn_r

	pinner.restore_native_tool_mode(0)

	assert_bool(btn_w.button_pressed).is_true()
	assert_int(_press_count).is_equal(1)
	btn_w.queue_free()
	btn_e.queue_free()
	btn_r.queue_free()


func test_restore_rotate_presses_e() -> void:
	var btn_w := Button.new()
	btn_w.toggle_mode = true
	add_child(btn_w)

	var btn_e := Button.new()
	btn_e.toggle_mode = true
	add_child(btn_e)

	var btn_r := Button.new()
	btn_r.toggle_mode = true
	add_child(btn_r)

	_reset_press_count()
	btn_e.pressed.connect(_on_button_pressed)

	var pinner := Node3DEditorToolPinner.new()
	pinner._button_w = btn_w
	pinner._button_e = btn_e
	pinner._button_r = btn_r

	pinner.restore_native_tool_mode(1)

	assert_bool(btn_e.button_pressed).is_true()
	assert_int(_press_count).is_equal(1)
	btn_w.queue_free()
	btn_e.queue_free()
	btn_r.queue_free()


func test_restore_scale_presses_r() -> void:
	var btn_w := Button.new()
	btn_w.toggle_mode = true
	add_child(btn_w)

	var btn_e := Button.new()
	btn_e.toggle_mode = true
	add_child(btn_e)

	var btn_r := Button.new()
	btn_r.toggle_mode = true
	add_child(btn_r)

	_reset_press_count()
	btn_r.pressed.connect(_on_button_pressed)

	var pinner := Node3DEditorToolPinner.new()
	pinner._button_w = btn_w
	pinner._button_e = btn_e
	pinner._button_r = btn_r

	pinner.restore_native_tool_mode(2)

	assert_bool(btn_r.button_pressed).is_true()
	assert_int(_press_count).is_equal(1)
	btn_w.queue_free()
	btn_e.queue_free()
	btn_r.queue_free()


func test_restore_falls_back_to_w_when_target_invalid() -> void:
	var btn_w := Button.new()
	btn_w.toggle_mode = true
	add_child(btn_w)

	var btn_e := Button.new()
	btn_e.toggle_mode = true
	add_child(btn_e)

	var pinner := Node3DEditorToolPinner.new()
	pinner._button_w = btn_w
	pinner._button_e = btn_e

	_reset_press_count()
	btn_w.pressed.connect(_on_button_pressed)

	# Request rotate (1), but _button_r is null, so W is the fallback.
	pinner.restore_native_tool_mode(1)

	assert_bool(btn_w.button_pressed).is_true()
	assert_int(_press_count).is_equal(1)
	btn_w.queue_free()
	btn_e.queue_free()
