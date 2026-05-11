## Unit tests for [GoBuildDragOperation].
##
## Pure-logic tests — no scene tree required.
## Run via the GdUnit4 panel in the Godot editor.
@tool
extends GdUnitTestSuite


func _make() -> GoBuildDragOperation:
	return GoBuildDragOperation.new()


# ---------------------------------------------------------------------------
# Construction / defaults
# ---------------------------------------------------------------------------

func test_default_delta_mode_is_param_radial() -> void:
	var op := _make()
	assert_int(op.delta_mode).is_equal(GoBuildDragOperation.DeltaMode.PARAM_RADIAL)


func test_default_param_is_zero() -> void:
	var op := _make()
	assert_float(op.param).is_equal_approx(0.0, 0.001)


func test_default_param_start_is_zero() -> void:
	var op := _make()
	assert_float(op.param_start).is_equal_approx(0.0, 0.001)


func test_default_param_min_is_zero() -> void:
	var op := _make()
	assert_float(op.param_min).is_equal_approx(0.0, 0.001)


func test_default_param_max_is_inf() -> void:
	var op := _make()
	assert_bool(op.param_max == INF).is_true()


func test_default_units_per_pixel() -> void:
	var op := _make()
	assert_float(op.units_per_pixel).is_equal_approx(0.005, 0.0001)


func test_default_scale_by_gizmo_is_true() -> void:
	var op := _make()
	assert_bool(op.scale_by_gizmo).is_true()


func test_default_snap_to_grid_is_false() -> void:
	var op := _make()
	assert_bool(op.snap_to_grid).is_false()


func test_default_snap_to_start_is_false() -> void:
	var op := _make()
	assert_bool(op.snap_to_start).is_false()


func test_default_screen_direction_is_horizontal() -> void:
	var op := _make()
	assert_vector(op.screen_direction).is_equal(Vector2(1.0, 0.0))


func test_default_radial_mode_via_delta_mode() -> void:
	var op := _make()
	assert_int(op.delta_mode).is_equal(GoBuildDragOperation.DeltaMode.PARAM_RADIAL)


func test_default_preview_mode_is_false() -> void:
	var op := _make()
	assert_bool(op.preview_mode).is_false()


func test_default_vertex_update_mode_is_false() -> void:
	var op := _make()
	assert_bool(op.vertex_update_mode).is_false()


func test_default_handle_id_is_negative() -> void:
	var op := _make()
	assert_int(op.handle_id).is_less(0)


# ---------------------------------------------------------------------------
# DeltaMode enum values
# ---------------------------------------------------------------------------

func test_delta_mode_enum_values() -> void:
	assert_int(GoBuildDragOperation.DeltaMode.AXIS_PROJECT).is_equal(0)
	assert_int(GoBuildDragOperation.DeltaMode.PLANE_PROJECT).is_equal(1)
	assert_int(GoBuildDragOperation.DeltaMode.VIEWPORT_PLANE_PROJECT).is_equal(2)
	assert_int(GoBuildDragOperation.DeltaMode.ROTATE).is_equal(3)
	assert_int(GoBuildDragOperation.DeltaMode.SCALE_AXIS).is_equal(4)
	assert_int(GoBuildDragOperation.DeltaMode.SCALE_UNIFORM).is_equal(5)
	assert_int(GoBuildDragOperation.DeltaMode.INSET).is_equal(6)
	assert_int(GoBuildDragOperation.DeltaMode.PARAM_RADIAL).is_equal(7)
	assert_int(GoBuildDragOperation.DeltaMode.PARAM_LINEAR).is_equal(8)


# ---------------------------------------------------------------------------
# Mutation
# ---------------------------------------------------------------------------

func test_param_can_be_set() -> void:
	var op := _make()
	op.param = 5.0
	assert_float(op.param).is_equal_approx(5.0, 0.001)


func test_delta_mode_can_be_changed() -> void:
	var op := _make()
	op.delta_mode = GoBuildDragOperation.DeltaMode.ROTATE
	assert_int(op.delta_mode).is_equal(GoBuildDragOperation.DeltaMode.ROTATE)


func test_vertex_indices_can_be_set() -> void:
	var op := _make()
	op.vertex_indices = [0, 1, 2]
	assert_array(op.vertex_indices).has_size(3)


func test_initial_vertex_positions_can_be_set() -> void:
	var op := _make()
	op.initial_vertex_positions = {0: Vector3.ZERO, 1: Vector3.ONE}
	assert_int(op.initial_vertex_positions.size()).is_equal(2)