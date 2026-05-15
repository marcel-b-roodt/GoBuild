## Unit tests for [GoBuildMouseTracker].
##
## Pure-logic tests — no scene tree required.
## Run via the GdUnit4 panel in the Godot editor.
@tool
extends GdUnitTestSuite

# Self-preloads — dependency order.
const _MOUSE_TRACKER_SCRIPT := preload("res://addons/go_build/core/go_build_mouse_tracker.gd")

func _make() -> GoBuildMouseTracker:
	return GoBuildMouseTracker.new()


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func test_begin_sets_active() -> void:
	var t := _make()
	t.begin(Vector2(640, 360), Vector2(1280, 720), true, Vector2(1, 0), 0.005)
	assert_bool(t.is_active()).is_true()


func test_end_clears_active() -> void:
	var t := _make()
	t.begin(Vector2(640, 360), Vector2(1280, 720), true, Vector2(1, 0), 0.005)
	t.end()
	assert_bool(t.is_active()).is_false()


func test_anchor_matches_begin() -> void:
	var t := _make()
	t.begin(Vector2(500, 400), Vector2(1000, 800), true, Vector2(1, 0), 0.005)
	assert_vector(t.get_anchor()).is_equal(Vector2(500, 400))


func test_viewport_size_matches_begin() -> void:
	var t := _make()
	t.begin(Vector2(640, 360), Vector2(1280, 720), true, Vector2(1, 0), 0.005)
	assert_vector(t.get_viewport_size()).is_equal(Vector2(1280, 720))


func test_virtual_pos_starts_at_anchor() -> void:
	var t := _make()
	var anchor := Vector2(640, 360)
	t.begin(anchor, Vector2(1280, 720), true, Vector2(1, 0), 0.005)
	assert_vector(t.get_virtual_pos()).is_equal(anchor)


func test_delta_starts_at_zero() -> void:
	var t := _make()
	t.begin(Vector2(640, 360), Vector2(1280, 720), true, Vector2(1, 0), 0.005)
	assert_float(t.get_delta()).is_equal_approx(0.0, 0.001)


func test_precision_offset_starts_at_zero() -> void:
	var t := _make()
	t.begin(Vector2(640, 360), Vector2(1280, 720), true, Vector2(1, 0), 0.005)
	assert_float(t.get_precision_offset()).is_equal_approx(0.0, 0.001)


# ---------------------------------------------------------------------------
# Radial delta computation
# ---------------------------------------------------------------------------

func test_radial_delta_from_raw_delta() -> void:
	var t := _make()
	t.begin(Vector2(640, 360), Vector2(1280, 720), true, Vector2(1, 0), 0.005)
	# Move 30 px right and 40 px down: distance = 50
	t.feed_raw_delta(Vector2(30, 40), false)
	assert_float(t.get_delta()).is_equal_approx(50.0, 0.001)


func test_radial_delta_accumulates() -> void:
	var t := _make()
	t.begin(Vector2(640, 360), Vector2(1280, 720), true, Vector2(1, 0), 0.005)
	t.feed_raw_delta(Vector2(30, 0), false)
	t.feed_raw_delta(Vector2(0, 40), false)
	# Total offset from anchor: (30, 40), distance = 50
	assert_float(t.get_delta()).is_equal_approx(50.0, 0.001)


func test_radial_delta_is_always_positive() -> void:
	var t := _make()
	t.begin(Vector2(640, 360), Vector2(1280, 720), true, Vector2(1, 0), 0.005)
	# Move left (negative X) — radial distance is still positive
	t.feed_raw_delta(Vector2(-100, 0), false)
	assert_float(t.get_delta()).is_greater(0.0)


# ---------------------------------------------------------------------------
# Linear delta computation
# ---------------------------------------------------------------------------

func test_linear_delta_horizontal() -> void:
	var t := _make()
	t.begin(Vector2(640, 360), Vector2(1280, 720), false, Vector2(1, 0), 0.005)
	# Move 100 px right: dot(Vector2(100,0), Vector2(1,0)) = 100
	t.feed_raw_delta(Vector2(100, 0), false)
	assert_float(t.get_delta()).is_equal_approx(100.0, 0.001)


func test_linear_delta_vertical_ignored_on_horizontal_direction() -> void:
	var t := _make()
	t.begin(Vector2(640, 360), Vector2(1280, 720), false, Vector2(1, 0), 0.005)
	# Move 0 px horizontally, 100 px vertically: dot((0,100),(1,0)) = 0
	t.feed_raw_delta(Vector2(0, 100), false)
	assert_float(t.get_delta()).is_equal_approx(0.0, 0.001)


func test_linear_delta_diagonal_direction() -> void:
	var t := _make()
	var dir := Vector2(1, 1).normalized()
	t.begin(Vector2(640, 360), Vector2(1280, 720), false, dir, 0.005)
	# Move (10, 10): dot((10,10), normalized(1,1)) = 20/sqrt(2) ≈ 14.14
	t.feed_raw_delta(Vector2(10, 10), false)
	var expected := Vector2(10, 10).dot(dir)
	assert_float(t.get_delta()).is_equal_approx(expected, 0.01)


func test_linear_delta_negative() -> void:
	var t := _make()
	t.begin(Vector2(640, 360), Vector2(1280, 720), false, Vector2(1, 0), 0.005)
	# Move left: dot = -100
	t.feed_raw_delta(Vector2(-100, 0), false)
	assert_float(t.get_delta()).is_less(0.0)


# ---------------------------------------------------------------------------
# Raw offset from anchor
# ---------------------------------------------------------------------------

func test_raw_offset_accumulates() -> void:
	var t := _make()
	var anchor := Vector2(640, 360)
	t.begin(anchor, Vector2(1280, 720), true, Vector2(1, 0), 0.005)
	t.feed_raw_delta(Vector2(10, 20), false)
	t.feed_raw_delta(Vector2(5, 15), false)
	assert_vector(t.get_raw_offset_from_anchor()).is_equal(Vector2(15, 35))


# ---------------------------------------------------------------------------
# Precision handling — offset-folding
# ---------------------------------------------------------------------------

func test_precision_offset_folded_on_shift_toggle() -> void:
	var t := _make()
	t.begin(Vector2(640, 360), Vector2(1280, 720), false, Vector2(1, 0), 0.005)
	# Move 200 px at normal speed
	t.feed_raw_delta(Vector2(200, 0), false)
	assert_float(t.get_delta()).is_equal_approx(200.0, 0.001)
	# Now Shift activates: the 200 at full speed gets folded into offset
	t.feed_raw_delta(Vector2(10, 0), true)
	# Precision multiplier is 0.1, so the new delta contribution is 10 * 0.1 = 1.
	# But the offset absorbs the difference: was 200*1.0, now needs 200*0.1 = 20.
	# Offset += 200 * 0.005 * (1.0 - 0.1) = 200 * 0.005 * 0.9 = 0.9
	# The offset_folding ensures position continuity.
	assert_bool(not is_zero_approx(t.get_precision_offset())).is_true()


func test_precision_multiplier_is_1_by_default() -> void:
	var t := _make()
	t.begin(Vector2(640, 360), Vector2(1280, 720), true, Vector2(1, 0), 0.005)
	assert_float(t.get_precision_multiplier()).is_equal_approx(1.0, 0.001)


func test_end_resets_state() -> void:
	var t := _make()
	t.begin(Vector2(640, 360), Vector2(1280, 720), true, Vector2(1, 0), 0.005)
	t.feed_raw_delta(Vector2(100, 0), false)
	t.end()
	assert_bool(t.is_active()).is_false()
	assert_float(t.get_delta()).is_equal_approx(0.0, 0.001)
	assert_float(t.get_precision_offset()).is_equal_approx(0.0, 0.001)
	assert_float(t.get_precision_multiplier()).is_equal_approx(1.0, 0.001)


# ---------------------------------------------------------------------------
# Filter count — initial large deltas are skipped
# ---------------------------------------------------------------------------

func test_large_initial_delta_filtered_via_feed() -> void:
	var t := _make()
	t.begin(Vector2(640, 360), Vector2(1280, 720), true, Vector2(1, 0), 0.005)
	var evt := InputEventMouseMotion.new()
	evt.relative = Vector2(60, 0)
	evt.position = Vector2(640, 360)
	t.feed(evt)
	assert_float(t.get_delta()).is_equal_approx(0.0, 0.001)


func test_small_delta_passes_filter() -> void:
	var t := _make()
	t.begin(Vector2(640, 360), Vector2(1280, 720), true, Vector2(1, 0), 0.005)
	t.feed_raw_delta(Vector2(1, 0), false)
	assert_float(t.get_delta()).is_equal_approx(1.0, 0.001)


# ---------------------------------------------------------------------------
# fold_clamp_excess — bounce-back at clamp bounds
# ---------------------------------------------------------------------------

func test_fold_clamp_excess_linear_reduces_delta() -> void:
	var t := _make()
	t.begin(Vector2(640, 360), Vector2(1280, 720), false, Vector2(1, 0), 0.005)
	# Move 200 px right: delta = 200
	t.feed_raw_delta(Vector2(200, 0), false)
	assert_float(t.get_delta()).is_equal_approx(200.0, 0.001)
	# Only 100 of that 200 was consumed by the param strategy
	t.fold_clamp_excess(100.0)
	# Delta should now report 100, and virtual_pos adjusted by 100 along direction
	assert_float(t.get_delta()).is_equal_approx(100.0, 0.001)
	assert_vector(t.get_raw_offset_from_anchor()).is_equal(Vector2(100, 0))


func test_fold_clamp_excess_linear_preserves_position() -> void:
	var t := _make()
	t.begin(Vector2(640, 360), Vector2(1280, 720), false, Vector2(1, 0), 0.005)
	t.feed_raw_delta(Vector2(300, 50), false)
	var original_y: float = t.get_virtual_pos().y
	# Only 100 consumed; excess is 200 along x-axis
	t.fold_clamp_excess(100.0)
	# Y component should be preserved (perpendicular to direction)
	assert_float(t.get_virtual_pos().y).is_equal_approx(original_y, 0.001)
	# X component should reflect only consumed portion
	assert_float(t.get_virtual_pos().x).is_equal_approx(640.0 + 100.0, 0.001)


func test_fold_clamp_excess_radial_skips_position_adjustment() -> void:
	var t := _make()
	t.begin(Vector2(640, 360), Vector2(1280, 720), true, Vector2(1, 0), 0.005)
	t.feed_raw_delta(Vector2(200, 200), false)
	var orig_pos := t.get_virtual_pos()
	# Radial mode: fold_clamp_excess adjusts delta only, not position
	t.fold_clamp_excess(50.0)
	assert_float(t.get_delta()).is_equal_approx(50.0, 0.001)
	# Position unchanged in radial mode
	assert_vector(t.get_virtual_pos()).is_equal(orig_pos)


func test_fold_clamp_excess_no_op_when_consumed_equals_actual() -> void:
	var t := _make()
	t.begin(Vector2(640, 360), Vector2(1280, 720), false, Vector2(1, 0), 0.005)
	t.feed_raw_delta(Vector2(100, 0), false)
	var delta_before: float = t.get_delta()
	var pos_before := t.get_virtual_pos()
	# Consumed matches actual — no folding needed
	t.fold_clamp_excess(100.0)
	assert_float(t.get_delta()).is_equal_approx(delta_before, 0.001)
	assert_vector(t.get_virtual_pos()).is_equal(pos_before)


func test_fold_clamp_excess_reverse_after_clamp() -> void:
	var t := _make()
	t.begin(Vector2(640, 360), Vector2(1280, 720), false, Vector2(1, 0), 0.005)
	# Move 200 px right
	t.feed_raw_delta(Vector2(200, 0), false)
	assert_float(t.get_delta()).is_equal_approx(200.0, 0.001)
	# Clamp eats 100; fold excess
	t.fold_clamp_excess(100.0)
	# Now reverse: move 50 px left — delta should go to 50
	t.feed_raw_delta(Vector2(-50, 0), false)
	assert_float(t.get_delta()).is_equal_approx(50.0, 0.001)


# ---------------------------------------------------------------------------
# Indicator position — precision-scaled screen cursor
# ---------------------------------------------------------------------------

func test_indicator_pos_linear_no_precision() -> void:
	var t := _make()
	t.begin(Vector2(640, 360), Vector2(1280, 720), false, Vector2(1, 0), 0.005)
	t.feed_raw_delta(Vector2(200, 0), false)
	# No precision: indicator should match virtual_pos offset
	var expected := Vector2(640 + 200, 360)
	assert_vector(t.get_indicator_pos()).is_equal_approx(expected, Vector2(0.01, 0.01))


func test_indicator_pos_linear_precision_shrinks() -> void:
	var t := _make()
	t.begin(Vector2(640, 360), Vector2(1280, 720), false, Vector2(1, 0), 0.005)
	t.feed_raw_delta(Vector2(200, 0), false)
	# Enter precision mode (0.1)
	t.feed_raw_delta(Vector2(10, 0), true)
	# Indicator should be much closer to anchor than raw virtual_pos
	var indicator := t.get_indicator_pos()
	var raw := t.get_virtual_pos()
	# Raw offset from anchor: (210, 0)
	# Precision factor: the delta at precision is small, so indicator is near anchor
	assert_float(indicator.x - 640.0).is_less(raw.x - 640.0)


func test_indicator_pos_radial_no_precision() -> void:
	var t := _make()
	t.begin(Vector2(640, 360), Vector2(1280, 720), true, Vector2(1, 0), 0.005)
	t.feed_raw_delta(Vector2(30, 40), false)
	# Radial, no precision: indicator delta = distance from anchor = 50
	# Position should be anchor + direction * 50
	var expected := Vector2(640, 360) + Vector2(30, 40).normalized() * 50.0
	assert_vector(t.get_indicator_pos()).is_equal_approx(expected, Vector2(0.1, 0.1))


func test_indicator_pos_starts_at_anchor() -> void:
	var t := _make()
	var anchor := Vector2(500, 400)
	t.begin(anchor, Vector2(1280, 720), false, Vector2(1, 0), 0.005)
	# Before any movement, indicator should be at anchor
	assert_vector(t.get_indicator_pos()).is_equal_approx(anchor, Vector2(0.01, 0.01))