## Unit tests for [GoBuildDeltaStrategy] static functions.
##
## These are pure functions that take explicit parameters and return
## [StrategyResult] — no scene tree, no mesh mutation.
## Run via the GdUnit4 panel in the Godot editor.
@tool
extends GdUnitTestSuite

# Self-preloads — dependency order.
const _DELTA_STRATEGY_SCRIPT := preload("res://addons/go_build/core/go_build_delta_strategy.gd")


# ---------------------------------------------------------------------------
# Helper: make a StrategyResult for comparison
# ---------------------------------------------------------------------------

func _result_float(v: float) -> GoBuildDeltaStrategy.StrategyResult:
	var r := GoBuildDeltaStrategy.StrategyResult.new()
	r.float_value = v
	return r


func _result_vec(v: Vector3) -> GoBuildDeltaStrategy.StrategyResult:
	var r := GoBuildDeltaStrategy.StrategyResult.new()
	r.vec_value = v
	return r


# ---------------------------------------------------------------------------
# param_radial
# ---------------------------------------------------------------------------

func test_param_radial_basic() -> void:
	var result := GoBuildDeltaStrategy.param_radial(
		50.0,   # tracker_delta: 50px from anchor
		0.0,    # param_start
		0.0,    # precision_offset
		0.005,  # sensitivity (units_per_pixel)
		1.0,    # precision_multiplier (no shift)
		0.0,    # param_min
		INF,    # param_max
		false,  # snap_to_start
		0.04    # snap_threshold
	)
	assert_float(result.float_value).is_equal_approx(0.25, 0.001)


func test_param_radial_with_start() -> void:
	var result := GoBuildDeltaStrategy.param_radial(
		50.0,   # tracker_delta
		0.5,    # param_start: 0.5
		0.0,    # precision_offset
		0.005,  # sensitivity
		1.0,    # precision_multiplier
		0.0,    # param_min
		INF,    # param_max
		false,  # snap_to_start
		0.04
	)
	# 0.5 + 50 * 0.005 * 1.0 = 0.5 + 0.25 = 0.75
	assert_float(result.float_value).is_equal_approx(0.75, 0.001)


func test_param_radial_clamped() -> void:
	var result := GoBuildDeltaStrategy.param_radial(
		1000.0, # tracker_delta: huge
		0.0,    # param_start
		0.0,    # precision_offset
		0.005,  # sensitivity
		1.0,    # precision_multiplier
		0.0,    # param_min
		1.0,    # param_max (clamp to 1.0)
		false,  # snap_to_start
		0.04
	)
	assert_float(result.float_value).is_equal_approx(1.0, 0.001)


func test_param_radial_precision_multiplier() -> void:
	var result := GoBuildDeltaStrategy.param_radial(
		100.0,   # tracker_delta
		0.0,     # param_start
		0.0,     # precision_offset
		0.005,   # sensitivity
		0.1,     # precision_multiplier (shift held)
		0.0,     # param_min
		INF,     # param_max
		false,   # snap_to_start
		0.04
	)
	# 0.0 + 0.0 + 100 * 0.005 * 0.1 = 0.05
	assert_float(result.float_value).is_equal_approx(0.05, 0.001)


func test_param_radial_with_precision_offset() -> void:
	var result := GoBuildDeltaStrategy.param_radial(
		100.0,   # tracker_delta
		0.0,     # param_start
		0.3,     # precision_offset (folded from previous precision segment)
		0.005,   # sensitivity
		0.1,     # precision_multiplier
		0.0,     # param_min
		INF,     # param_max
		false,   # snap_to_start
		0.04
	)
	# 0.0 + 0.3 + 100 * 0.005 * 0.1 = 0.3 + 0.05 = 0.35
	assert_float(result.float_value).is_equal_approx(0.35, 0.001)


func test_param_radial_snap_to_start() -> void:
	var result := GoBuildDeltaStrategy.param_radial(
		5.0,    # tracker_delta: small (5 * 0.005 = 0.025, within threshold 0.04)
		0.5,    # param_start
		0.0,    # precision_offset
		0.005,  # sensitivity
		1.0,    # precision_multiplier
		0.0,    # param_min
		INF,    # param_max
		true,   # snap_to_start
		0.04    # snap_threshold
	)
	# 0.5 + 0.025 = 0.525, but |0.525 - 0.5| = 0.025 < 0.04, so snap to 0.5
	assert_float(result.float_value).is_equal_approx(0.5, 0.001)


func test_param_radial_no_snap_when_past_threshold() -> void:
	var result := GoBuildDeltaStrategy.param_radial(
		100.0,  # tracker_delta: large (100 * 0.005 = 0.5, well past threshold)
		0.5,    # param_start
		0.0,    # precision_offset
		0.005,  # sensitivity
		1.0,    # precision_multiplier
		0.0,    # param_min
		INF,    # param_max
		true,   # snap_to_start
		0.04    # snap_threshold
	)
	# |1.0 - 0.5| = 0.5 > 0.04, no snap
	assert_float(result.float_value).is_equal_approx(1.0, 0.001)


# ---------------------------------------------------------------------------
# param_linear
# ---------------------------------------------------------------------------

func test_param_linear_positive() -> void:
	var result := GoBuildDeltaStrategy.param_linear(
		100.0,  # tracker_delta: 100px along screen_direction
		0.0,    # param_start
		0.0,    # precision_offset
		0.005,  # sensitivity
		1.0,    # precision_multiplier
		0.0,    # param_min
		INF,    # param_max
		false,  # snap_to_start
		0.04
	)
	# 0.0 + 0.0 + 100 * 0.005 * 1.0 = 0.5
	assert_float(result.float_value).is_equal_approx(0.5, 0.001)


func test_param_linear_negative() -> void:
	var result := GoBuildDeltaStrategy.param_linear(
		-100.0, # tracker_delta: negative direction
		0.5,    # param_start
		0.0,    # precision_offset
		0.005,  # sensitivity
		1.0,    # precision_multiplier
		-INF,   # param_min (allow negative)
		INF,    # param_max
		false,  # snap_to_start
		0.04
	)
	# 0.5 + 0.0 + (-100) * 0.005 * 1.0 = 0.5 - 0.5 = 0.0
	assert_float(result.float_value).is_equal_approx(0.0, 0.001)


func test_param_linear_clamped_min() -> void:
	var result := GoBuildDeltaStrategy.param_linear(
		-200.0, # tracker_delta
		0.0,    # param_start
		0.0,    # precision_offset
		0.005,  # sensitivity
		1.0,    # precision_multiplier
		0.0,    # param_min (clamp at 0)
		INF,    # param_max
		false,  # snap_to_start
		0.04
	)
	# Would be -1.0, clamped to 0.0
	assert_float(result.float_value).is_equal_approx(0.0, 0.001)


# ---------------------------------------------------------------------------
# inset
# ---------------------------------------------------------------------------

func test_inset_basic() -> void:
	var result := GoBuildDeltaStrategy.inset(
		Vector2(200, 300),   # screen_pos
		0.1,                  # snap_step (unused when snap_enabled=false)
		false,               # snap_enabled
		1.0,                  # precision_multiplier (no shift)
		Vector2(100, 300),    # initial_screen
		0.0                   # inset_offset
	)
	# offset = (200-100)*1.0 = 100, amount = 100*0.005 = 0.5
	assert_float(result.float_value).is_equal_approx(0.5, 0.001)


func test_inset_clamped_to_zero_one() -> void:
	var result := GoBuildDeltaStrategy.inset(
		Vector2(50, 300),    # screen_pos (move left = negative offset)
		0.1,                  # snap_step
		false,               # snap_enabled
		1.0,                  # precision_multiplier
		Vector2(100, 300),    # initial_screen
		0.0                   # inset_offset
	)
	# offset = (50-100)*1.0 = -50, amount = -50*0.005 = -0.25, clamped to 0.0
	assert_float(result.float_value).is_equal_approx(0.0, 0.001)


func test_inset_with_offset() -> void:
	var result := GoBuildDeltaStrategy.inset(
		Vector2(120, 300),    # screen_pos (20px from initial)
		0.1,                   # snap_step
		false,                # snap_enabled
		1.0,                   # precision_multiplier
		Vector2(100, 300),     # initial_screen
		0.3                    # inset_offset (previously accumulated)
	)
	# offset = 20, amount = 20*0.005 + 0.3 = 0.1 + 0.3 = 0.4
	assert_float(result.float_value).is_equal_approx(0.4, 0.001)


func test_inset_with_precision() -> void:
	var result := GoBuildDeltaStrategy.inset(
		Vector2(200, 300),   # screen_pos
		0.1,                  # snap_step
		false,               # snap_enabled
		0.1,                  # precision_multiplier (shift held)
		Vector2(100, 300),    # initial_screen
		0.0                   # inset_offset
	)
	# offset = 100, amount = 100*0.005*0.1 = 0.05
	assert_float(result.float_value).is_equal_approx(0.05, 0.001)


func test_inset_with_snap() -> void:
	var result := GoBuildDeltaStrategy.inset(
		Vector2(230, 300),   # screen_pos
		0.1,                  # snap_step (0.1)
		true,                # snap_enabled
		1.0,                  # precision_multiplier
		Vector2(100, 300),    # initial_screen
		0.0                   # inset_offset
	)
	# offset = 130, amount_raw = 130*0.005 = 0.65, snapped to 0.1 increments → 0.7
	# Actually: amount = 130*0.005 = 0.65, snappedf(0.65, 0.1) = 0.7
	assert_float(result.float_value).is_equal_approx(0.7, 0.001)


# ---------------------------------------------------------------------------
# StrategyResult helpers
# ---------------------------------------------------------------------------

func test_make_result_float() -> void:
	var r := GoBuildDeltaStrategy.make_result_float(3.14)
	assert_bool(r.needs_initialise).is_false()
	assert_float(r.float_value).is_equal_approx(3.14, 0.001)


func test_make_result_vec() -> void:
	var r := GoBuildDeltaStrategy.make_result_vec(Vector3(1, 2, 3))
	assert_bool(r.needs_initialise).is_false()
	assert_vector(r.vec_value).is_equal(Vector3(1, 2, 3))


func test_make_result_init_float() -> void:
	var r := GoBuildDeltaStrategy.make_result_init_float(5.0)
	assert_bool(r.needs_initialise).is_true()
	assert_float(r.float_value).is_equal_approx(5.0, 0.001)


func test_make_result_init_vec() -> void:
	var r := GoBuildDeltaStrategy.make_result_init_vec(Vector3(10, 20, 30))
	assert_bool(r.needs_initialise).is_true()
	assert_vector(r.vec_value).is_equal(Vector3(10, 20, 30))


func test_make_result_init_default_float() -> void:
	var r := GoBuildDeltaStrategy.make_result_init_float()
	assert_bool(r.needs_initialise).is_true()
	assert_float(r.float_value).is_equal_approx(0.0, 0.001)


func test_make_result_init_default_vec() -> void:
	var r := GoBuildDeltaStrategy.make_result_init_vec()
	assert_bool(r.needs_initialise).is_true()
	assert_vector(r.vec_value).is_equal(Vector3.ZERO)


# ---------------------------------------------------------------------------
# Per-frame delta strategies
#
# Camera-dependent strategies (axis_project_frame, plane_project_frame,
# viewport_plane_project_frame, rotate_frame, scale_axis_frame,
# scale_uniform_frame) require a Camera3D in the scene tree and are tested
# via integration tests in the editor.
#
# The following tests verify structural properties that can be asserted headless.
# ---------------------------------------------------------------------------


## Verify the per-frame strategy functions exist on the class.
func test_per_frame_strategy_functions_exist() -> void:
	var script: GDScript = _DELTA_STRATEGY_SCRIPT
	assert_object(script).is_not_null()
	assert_bool(script.has_method("axis_project_frame")).is_true()
	assert_bool(script.has_method("plane_project_frame")).is_true()
	assert_bool(script.has_method("viewport_plane_project_frame")).is_true()
	assert_bool(script.has_method("rotate_frame")).is_true()
	assert_bool(script.has_method("scale_axis_frame")).is_true()
	assert_bool(script.has_method("scale_uniform_frame")).is_true()
	assert_bool(script.has_method("inset_frame")).is_true()
	assert_bool(script.has_method("compute_units_per_pixel")).is_true()
	assert_bool(script.has_method("world_axis_to_screen")).is_true()


## Per-frame inset strategy is pure-math (no Camera3D needed) and can be
## tested headless.
func test_inset_frame_basic() -> void:
	var result := GoBuildDeltaStrategy.inset_frame(
			Vector2(10.0, 0.0),
			1.0
	)
	assert_float(result.float_value).is_equal_approx(0.05, 0.001)


func test_inset_frame_negative_direction() -> void:
	var result := GoBuildDeltaStrategy.inset_frame(
			Vector2(-10.0, 0.0),
			1.0
	)
	assert_float(result.float_value).is_equal_approx(-0.05, 0.001)


func test_inset_frame_precision() -> void:
	var result := GoBuildDeltaStrategy.inset_frame(
			Vector2(10.0, 0.0),
			0.1
	)
	assert_float(result.float_value).is_equal_approx(0.005, 0.001)