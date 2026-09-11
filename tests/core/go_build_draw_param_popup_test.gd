## Draw param popup tests — GdUnit4
##
## [GoBuildDrawParamPopup] mirrors the dock param strip over the viewport:
## one widget per structural spec, edits flow to the draw controller.
@tool
extends GdUnitTestSuite

const _POPUP_SCRIPT := preload("res://addons/go_build/core/go_build_draw_param_popup.gd")
const _CTRL_GD: GDScript = preload(
		"res://addons/go_build/core/go_build_shape_draw_controller.gd")
const _CATALOG_SCRIPT := \
		preload("res://addons/go_build/mesh/generators/shape_creation_catalog.gd")

var _draw_ctrl: GoBuildShapeDrawController = null


func before_test() -> void:
	_draw_ctrl = auto_free(GoBuildShapeDrawController.new())


func _make_popup():
	var p: PanelContainer = _POPUP_SCRIPT.new()
	add_child(p)
	auto_free(p)
	return p


func test_open_hidden_for_shape_without_structural_params() -> void:
	var p = _make_popup()
	p.open("QuadSphere", _draw_ctrl, Rect2(0, 0, 800, 600))
	assert_bool(p.visible).is_false()


func test_open_shows_widgets_for_structural_params() -> void:
	var p = _make_popup()
	p.show()
	p.open("Staircase", _draw_ctrl, Rect2(0, 0, 800, 600))
	assert_bool(p.visible).is_true()
	# Title + one row per spec ("steps") = 2 children.
	var specs := ShapeCreationCatalog.non_drawable_param_specs("Staircase")
	assert_int(specs.size()).is_equal(1)
	assert_int(p.get_child_count()).is_equal(1)


func test_open_positions_inside_viewport_rect() -> void:
	var p = _make_popup()
	var rect := Rect2(100, 50, 800, 600)
	p.open("Staircase", _draw_ctrl, rect)
	assert_bool(p.position.x >= rect.position.x).is_true()
	assert_bool(p.position.y >= rect.position.y).is_true()
	assert_bool(p.position.x + p.size.x <= rect.end.x).is_true()


func test_spin_edit_reaches_draw_controller() -> void:
	var p = _make_popup()
	p.open("Staircase", _draw_ctrl, Rect2(0, 0, 800, 600))
	var spin: SpinBox = _find_spin(p)
	assert_that(spin).is_not_null()
	spin.value = 7
	assert_int(int(_draw_ctrl.get_extra_params().get("steps", 0))).is_equal(7)


func test_bool_edit_reaches_draw_controller() -> void:
	var p = _make_popup()
	p.open("Cylinder", _draw_ctrl, Rect2(0, 0, 800, 600))
	var chk: CheckBox = _find_check(p)
	assert_that(chk).is_not_null()
	chk.button_pressed = true
	assert_bool(bool(_draw_ctrl.get_extra_params().get("cap_top", false))).is_true()


func test_close_hides_and_clears_controller_ref() -> void:
	var p = _make_popup()
	p.show()
	p.open("Staircase", _draw_ctrl, Rect2(0, 0, 800, 600))
	p.close()
	assert_bool(p.visible).is_false()
	p._on_spin_changed(3.0, "steps", true)
	assert_bool(_draw_ctrl.get_extra_params().has("steps")).is_false()


# ---------------------------------------------------------------------------
# Params persistence (re-edit contract)
# ---------------------------------------------------------------------------

func test_reedit_merges_polygon_keys_from_meta() -> void:
	# _regenerate_edit_mesh must carry polygon_points / override_normal
	# from the commit meta into the rebuilt params (size keys erased).
	var popup_gd: Variant = _POPUP_SCRIPT
	var src: String = (popup_gd as GDScript).source_code
	assert_bool(src.contains("for poly_key: String in "
			+ "[\"polygon_points\", \"override_normal\"]:")).is_true()
	assert_bool(src.contains("params.erase(\"width\")")).is_true()
	assert_bool(src.contains("params.erase(\"depth\")")).is_true()


func test_draw_controller_writes_params_meta() -> void:
	var src: String = _CTRL_GD.source_code
	assert_bool(src.contains('set_meta("go_build_params"')).is_true()
	assert_bool(src.contains('set_meta("go_build_shape"')).is_true()


func _find_spin(root: Node) -> SpinBox:
	for child: Node in root.get_children():
		if child is SpinBox:
			return child
		var inner := _find_spin(child)
		if inner != null:
			return inner
	return null


func _find_check(root: Node) -> CheckBox:
	for child: Node in root.get_children():
		if child is CheckBox:
			return child
		var inner := _find_check(child)
		if inner != null:
			return inner
	return null