## Unit tests for [GoBuildDragController].
##
## Tests the lifecycle (begin/update/commit/cancel), state queries, and
## deferred-bake interaction.  Gizmo-mode strategies require a Camera3D which
## cannot be instantiated headless, so those are integration-tested in the editor.
## Param-mode drags are pure-logic testable here.
@tool
extends GdUnitTestSuite

const _DRAG_OP_SCRIPT := preload("res://addons/go_build/core/go_build_drag_operation.gd")
const _CTRL_SCRIPT    := preload("res://addons/go_build/core/go_build_drag_controller.gd")


func _make_op() -> GoBuildDragOperation:
	return GoBuildDragOperation.new()


func _make_ctrl() -> GoBuildDragController:
	return GoBuildDragController.new()


# ---------------------------------------------------------------------------
# Construction / defaults
# ---------------------------------------------------------------------------

func test_new_controller_is_not_active() -> void:
	var c := _make_ctrl()
	assert_bool(c.is_active()).is_false()


func test_new_controller_has_no_operation() -> void:
	var c := _make_ctrl()
	assert_object(c.get_operation()).is_null()


func test_new_controller_is_not_param_mode() -> void:
	var c := _make_ctrl()
	assert_bool(c.is_param_mode()).is_false()


func test_new_controller_overlay_data_is_empty() -> void:
	var c := _make_ctrl()
	assert_dict(c.get_overlay_data()).is_empty()


func test_new_controller_overlay_text_is_empty() -> void:
	var c := _make_ctrl()
	assert_str(c.get_overlay_text()).is_empty()


# ---------------------------------------------------------------------------
# Begin — param mode
# ---------------------------------------------------------------------------

func test_begin_param_mode_sets_active() -> void:
	var c := _make_ctrl()
	var op := _make_op()
	op.delta_mode = GoBuildDragOperation.DeltaMode.PARAM_RADIAL
	op.node = null
	c.begin(op)
	assert_bool(c.is_active()).is_true()


func test_begin_param_mode_is_param_mode() -> void:
	var c := _make_ctrl()
	var op := _make_op()
	op.delta_mode = GoBuildDragOperation.DeltaMode.PARAM_RADIAL
	c.begin(op)
	assert_bool(c.is_param_mode()).is_true()


func test_begin_param_operation_is_stored() -> void:
	var c := _make_ctrl()
	var op := _make_op()
	op.delta_mode = GoBuildDragOperation.DeltaMode.PARAM_RADIAL
	c.begin(op)
	assert_object(c.get_operation()).is_equal(op)


func test_begin_param_linear_is_param_mode() -> void:
	var c := _make_ctrl()
	var op := _make_op()
	op.delta_mode = GoBuildDragOperation.DeltaMode.PARAM_LINEAR
	c.begin(op)
	assert_bool(c.is_param_mode()).is_true()


# ---------------------------------------------------------------------------
# Begin — gizmo mode
# ---------------------------------------------------------------------------

func test_begin_gizmo_mode_sets_active() -> void:
	var c := _make_ctrl()
	var op := _make_op()
	op.delta_mode = GoBuildDragOperation.DeltaMode.AXIS_PROJECT
	c.begin(op)
	assert_bool(c.is_active()).is_true()


func test_begin_gizmo_mode_is_not_param_mode() -> void:
	var c := _make_ctrl()
	var op := _make_op()
	op.delta_mode = GoBuildDragOperation.DeltaMode.AXIS_PROJECT
	c.begin(op)
	assert_bool(c.is_param_mode()).is_false()


func test_begin_rotate_is_not_param_mode() -> void:
	var c := _make_ctrl()
	var op := _make_op()
	op.delta_mode = GoBuildDragOperation.DeltaMode.ROTATE
	c.begin(op)
	assert_bool(c.is_param_mode()).is_false()


func test_begin_scale_axis_is_not_param_mode() -> void:
	var c := _make_ctrl()
	var op := _make_op()
	op.delta_mode = GoBuildDragOperation.DeltaMode.SCALE_AXIS
	c.begin(op)
	assert_bool(c.is_param_mode()).is_false()


func test_begin_scale_uniform_is_not_param_mode() -> void:
	var c := _make_ctrl()
	var op := _make_op()
	op.delta_mode = GoBuildDragOperation.DeltaMode.SCALE_UNIFORM
	c.begin(op)
	assert_bool(c.is_param_mode()).is_false()


func test_begin_plane_project_is_not_param_mode() -> void:
	var c := _make_ctrl()
	var op := _make_op()
	op.delta_mode = GoBuildDragOperation.DeltaMode.PLANE_PROJECT
	c.begin(op)
	assert_bool(c.is_param_mode()).is_false()


func test_begin_viewport_plane_is_not_param_mode() -> void:
	var c := _make_ctrl()
	var op := _make_op()
	op.delta_mode = GoBuildDragOperation.DeltaMode.VIEWPORT_PLANE_PROJECT
	c.begin(op)
	assert_bool(c.is_param_mode()).is_false()


func test_begin_inset_is_not_param_mode() -> void:
	var c := _make_ctrl()
	var op := _make_op()
	op.delta_mode = GoBuildDragOperation.DeltaMode.INSET
	c.begin(op)
	assert_bool(c.is_param_mode()).is_false()


# ---------------------------------------------------------------------------
# Cancel — clears state
# ---------------------------------------------------------------------------

func test_cancel_clears_active() -> void:
	var c := _make_ctrl()
	var op := _make_op()
	op.delta_mode = GoBuildDragOperation.DeltaMode.PARAM_RADIAL
	c.begin(op)
	c.cancel()
	assert_bool(c.is_active()).is_false()


func test_cancel_clears_operation() -> void:
	var c := _make_ctrl()
	var op := _make_op()
	op.delta_mode = GoBuildDragOperation.DeltaMode.PARAM_RADIAL
	c.begin(op)
	c.cancel()
	assert_object(c.get_operation()).is_null()


func test_cancel_clears_param_mode() -> void:
	var c := _make_ctrl()
	var op := _make_op()
	op.delta_mode = GoBuildDragOperation.DeltaMode.PARAM_RADIAL
	c.begin(op)
	c.cancel()
	assert_bool(c.is_param_mode()).is_false()


func test_cancel_when_not_active_is_safe() -> void:
	var c := _make_ctrl()
	c.cancel()
	assert_bool(c.is_active()).is_false()


# ---------------------------------------------------------------------------
# Commit — clears state (without node, no undo wiring)
# ---------------------------------------------------------------------------

func test_commit_clears_active() -> void:
	var c := _make_ctrl()
	var op := _make_op()
	op.delta_mode = GoBuildDragOperation.DeltaMode.PARAM_RADIAL
	op.node = null
	op.snapshot = {}
	c.begin(op)
	c.commit()
	assert_bool(c.is_active()).is_false()


func test_commit_clears_operation() -> void:
	var c := _make_ctrl()
	var op := _make_op()
	op.delta_mode = GoBuildDragOperation.DeltaMode.PARAM_RADIAL
	op.node = null
	op.snapshot = {}
	c.begin(op)
	c.commit()
	assert_object(c.get_operation()).is_null()


func test_commit_when_not_active_is_safe() -> void:
	var c := _make_ctrl()
	c.commit()
	assert_bool(c.is_active()).is_false()


# ---------------------------------------------------------------------------
# Overlay data — param mode
# ---------------------------------------------------------------------------

func test_overlay_data_param_mode_keys() -> void:
	var c := _make_ctrl()
	var op := _make_op()
	op.delta_mode = GoBuildDragOperation.DeltaMode.PARAM_RADIAL
	op.overlay_label = "Distance"
	c.begin(op)
	var data: Dictionary = c.get_overlay_data()
	assert_bool(data.has("anchor")).is_true()
	assert_bool(data.has("vp_size")).is_true()
	assert_bool(data.has("virtual_pos")).is_true()
	assert_bool(data.has("delta")).is_true()
	assert_bool(data.has("param")).is_true()
	assert_bool(data.has("label")).is_true()
	assert_bool(data.has("param_label")).is_true()
	assert_bool(data.has("is_gizmo")).is_false()


func test_overlay_data_gizmo_mode_keys() -> void:
	var c := _make_ctrl()
	var op := _make_op()
	op.delta_mode = GoBuildDragOperation.DeltaMode.AXIS_PROJECT
	c.begin(op)
	var data: Dictionary = c.get_overlay_data()
	assert_bool(data.has("is_gizmo")).is_true()
	assert_bool(data["is_gizmo"]).is_true()
	assert_bool(data.has("cumulative_translate")).is_true()
	assert_bool(data.has("cumulative_angle")).is_true()
	assert_bool(data.has("cumulative_scale")).is_true()


# ---------------------------------------------------------------------------
# Overlay text — gizmo mode
# ---------------------------------------------------------------------------

func test_overlay_text_inset() -> void:
	var c := _make_ctrl()
	var op := _make_op()
	op.delta_mode = GoBuildDragOperation.DeltaMode.INSET
	op._gizmo_cumulative_scale = 0.5
	c.begin(op)
	assert_str(c.get_overlay_text()).contains("inset")


func test_overlay_text_rotate() -> void:
	var c := _make_ctrl()
	var op := _make_op()
	op.delta_mode = GoBuildDragOperation.DeltaMode.ROTATE
	op._gizmo_cumulative_angle = 1.5708
	c.begin(op)
	assert_str(c.get_overlay_text()).contains("°")


func test_overlay_text_scale() -> void:
	var c := _make_ctrl()
	var op := _make_op()
	op.delta_mode = GoBuildDragOperation.DeltaMode.SCALE_AXIS
	op._gizmo_cumulative_scale = 2.0
	c.begin(op)
	assert_str(c.get_overlay_text()).contains("x")


func test_overlay_text_translate() -> void:
	var c := _make_ctrl()
	var op := _make_op()
	op.delta_mode = GoBuildDragOperation.DeltaMode.AXIS_PROJECT
	c.begin(op)
	assert_str(c.get_overlay_text()).contains("Δ")


# ---------------------------------------------------------------------------
# Tracker access
# ---------------------------------------------------------------------------

func test_tracker_accessible() -> void:
	var c := _make_ctrl()
	assert_object(c.get_tracker()).is_not_null()


func test_tracker_begins_with_op() -> void:
	var c := _make_ctrl()
	var op := _make_op()
	op.delta_mode = GoBuildDragOperation.DeltaMode.PARAM_RADIAL
	c.begin(op)
	assert_bool(c.get_tracker().is_active()).is_true()


func test_tracker_ends_with_cancel() -> void:
	var c := _make_ctrl()
	var op := _make_op()
	op.delta_mode = GoBuildDragOperation.DeltaMode.PARAM_RADIAL
	c.begin(op)
	c.cancel()
	assert_bool(c.get_tracker().is_active()).is_false()


# ---------------------------------------------------------------------------
# Gizmo operations — accumulator fields on DragOperation
# ---------------------------------------------------------------------------

func test_drag_op_default_cumulative_translate() -> void:
	var op := _make_op()
	assert_vector(op._gizmo_cumulative_translate).is_equal(Vector3.ZERO)


func test_drag_op_default_cumulative_angle() -> void:
	var op := _make_op()
	assert_float(op._gizmo_cumulative_angle).is_equal_approx(0.0, 0.001)


func test_drag_op_default_cumulative_scale() -> void:
	var op := _make_op()
	assert_float(op._gizmo_cumulative_scale).is_equal_approx(1.0, 0.001)


func test_drag_op_default_inset_offset() -> void:
	var op := _make_op()
	assert_float(op._gizmo_inset_offset).is_equal_approx(0.0, 0.001)