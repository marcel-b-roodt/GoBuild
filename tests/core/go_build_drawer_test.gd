## GdUnit4 tests for [GoBuildDrawer] base class.
##
## Verified here (scene-runner approach — drawer added to test-suite scene tree):
##   - Drawer starts closed by default.
##   - _setup_drawer called with open=true starts open.
##   - set_open(true/false) shows/hides _content and updates header text prefix.
##   - refresh_buttons disables buttons when _target is null.
##   - refresh_buttons enables buttons when condition returns true.
##   - refresh_buttons disables buttons when condition returns false.
@tool
extends GdUnitTestSuite

# Self-preloads — dependency order, per the self-preload rule.
const _SEL_MGR_SCRIPT       := preload("res://addons/go_build/core/selection_manager.gd")
const _MESH_INSTANCE_SCRIPT := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _DRAWER_SCRIPT        := preload("res://addons/go_build/core/go_build_drawer.gd")


# ---------------------------------------------------------------------------
# Minimal concrete subclass — used only inside this test file.
# Creates a drawer with a single registered button and an injectable condition.
# ---------------------------------------------------------------------------

class _TestDrawer extends GoBuildDrawer:
	var _btn: Button = null
	var _condition_result: bool = true

	func _ready() -> void:
		_setup_drawer("Test Drawer")
		_btn = _op_button("Do Thing", "Test tooltip")
		_content.add_child(_btn)
		_register_op(_btn, _check_condition)

	func _check_condition() -> bool:
		return _condition_result


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_drawer() -> _TestDrawer:
	var d := _TestDrawer.new()
	add_child(d)
	auto_free(d)
	return d


# ---------------------------------------------------------------------------
# Open / close state
# ---------------------------------------------------------------------------

func test_drawer_starts_closed() -> void:
	var d := _make_drawer()
	assert_bool(d.is_open()).is_false()


func test_setup_drawer_open_starts_open() -> void:
	# A second helper class (_OpenTestDrawer) is defined at the bottom of this
	# file to work around GDScript's restriction on inner class definitions
	# inside functions.
	var d := _OpenTestDrawer.new()
	add_child(d)
	auto_free(d)
	assert_bool(d.is_open()).is_true()


func test_set_open_true_shows_content() -> void:
	var d := _make_drawer()
	d.set_open(true)
	assert_bool(d._content.visible).is_true()


func test_set_open_false_hides_content() -> void:
	var d := _make_drawer()
	d.set_open(true)
	d.set_open(false)
	assert_bool(d._content.visible).is_false()


func test_header_shows_open_prefix_when_open() -> void:
	var d := _make_drawer()
	d.set_open(true)
	assert_bool(d._header_btn.text.begins_with("\u25bc")).is_true()


func test_header_shows_closed_prefix_when_closed() -> void:
	var d := _make_drawer()
	d.set_open(false)
	assert_bool(d._header_btn.text.begins_with("\u25b6")).is_true()


# ---------------------------------------------------------------------------
# refresh_buttons
# ---------------------------------------------------------------------------

func test_refresh_buttons_disables_when_condition_false() -> void:
	var d := _make_drawer()
	d._condition_result = false
	d.refresh_buttons()
	assert_bool(d._btn.disabled).is_true()


func test_refresh_buttons_enables_when_condition_true() -> void:
	var d := _make_drawer()
	d._condition_result = true
	d.refresh_buttons()
	assert_bool(d._btn.disabled).is_false()


func test_refresh_calls_refresh_buttons() -> void:
	var d := _make_drawer()
	d._condition_result = false
	d.refresh()
	assert_bool(d._btn.disabled).is_true()


# ---------------------------------------------------------------------------
# set_plugin / set_target pass-through
# ---------------------------------------------------------------------------

func test_set_target_stores_target() -> void:
	var d := _make_drawer()
	var node: GoBuildMeshInstance = auto_free(GoBuildMeshInstance.new())
	d.set_target(node)
	assert_object(d._target).is_equal(node)


func test_set_target_null_stores_null() -> void:
	var d := _make_drawer()
	var node: GoBuildMeshInstance = auto_free(GoBuildMeshInstance.new())
	d.set_target(node)
	d.set_target(null)
	assert_object(d._target).is_null()


# ---------------------------------------------------------------------------
# Helper classes referenced by tests above.
# GDScript does not allow inner class definitions inside function bodies,
# so these are declared at the outer class scope.
# ---------------------------------------------------------------------------

## Concrete drawer that starts open — used by test_setup_drawer_open_starts_open.
class _OpenTestDrawer extends GoBuildDrawer:
	func _ready() -> void:
		_setup_drawer("Open Test", true)
