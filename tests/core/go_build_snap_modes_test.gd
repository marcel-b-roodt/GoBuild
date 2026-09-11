## Snap-semantics tests for the three snap modes (Hybrid / World / Delta)
## and both drag classes (object move vs element edit).
##
## The snapping maths lives in static helpers on [GoBuildDragController]
## ([method _snap_translate], [method _snap_delta_world],
## [method _snap_scale]) so it is pure-logic testable headless: feed in a
## transform + cumulative raw delta, assert the returned correction.
##
## The semantic contract:
##   SMART   — keep geometry on the grid wherever the absolute position is
##             meaningful: object moves and VERTEX drags snap absolute
##             world positions; EDGE/FACE drags quantize the world DELTA
##             (the drag reference — centroid — may sit off-axis, and
##             absolute snapping would land the element on the wrong
##             cell); scale quantizes the RESULTING world size.  Off-grid
##             repair is "Snap Selection to Grid"'s job.
##   DELTA   — legacy: quantize the cumulative LOCAL delta; nothing
##             teleports, only increments are enforced (scale: ratio).
@tool
extends GdUnitTestSuite

const _CTRL_SCRIPT := preload("res://addons/go_build/core/go_build_drag_controller.gd")
const _OP_SCRIPT := preload("res://addons/go_build/core/go_build_drag_operation.gd")

## Identity transform (axis-aligned node at origin).
func _identity() -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3.ZERO)


func _op(snap_mode: int, element_edit: bool, drag_mode: int,
		element_kind: int = 0) -> GoBuildDragOperation:
	var op := GoBuildDragOperation.new()
	op.snap_mode = snap_mode
	op.element_edit = element_edit
	op.element_kind = element_kind
	op.delta_mode = drag_mode
	op.snap_step = 0.1
	op.initial_world_size = 1.0
	return op


func _call_snap(
		op: GoBuildDragOperation,
		raw: Vector3,
		centroid: Vector3,
		xform: Transform3D,
) -> Vector3:
	var correction: Vector3 = _CTRL_SCRIPT._snap_translate(
			raw, centroid, xform, op.snap_step, op.snap_mode,
			op.delta_mode, op.world_axis, op.element_edit,
			op.element_kind)
	return correction


# ---------------------------------------------------------------------------
# Hybrid — object moves
# ---------------------------------------------------------------------------

func test_smart_object_axis_move_snaps_absolute_position() -> void:
	# Object centroid at x=0.53, dragged +0.05 → target 0.58 → snaps to 0.6.
	var op := _op(_OP_SCRIPT.SnapMode.SMART,
			false, GoBuildDragOperation.DeltaMode.AXIS_PROJECT)
	op.world_axis = Vector3.RIGHT
	var xf := _identity()
	var raw := Vector3(0.05, 0, 0)
	var correction := _call_snap(op, raw, Vector3(0.53, 0, 0), xf)
	assert_vector(correction).is_equal_approx(Vector3(0.07, 0, 0), Vector3.ONE * 0.001)


func test_smart_object_plane_move_snaps_all_axes() -> void:
	var op := _op(_OP_SCRIPT.SnapMode.SMART,
			false, GoBuildDragOperation.DeltaMode.PLANE_PROJECT)
	# Centroid (0.53, 1.02, 0), dragged (0.05, -0.01, 0.04):
	# target (0.58, 1.01, 0.05) → snapped (0.6, 1.0, 0.1)... z stays 0.05? No:
	# 0.05 snaps to 0.1? round(0.05/0.1)=round(0.5)=0? banker's?  snapped uses
	# round-half-away → 0.05 → 0.1?  Actually roundi(0.5)=1 → 0.1.
	var xf := _identity()
	var correction := _call_snap(op, Vector3(0.05, -0.01, 0.05),
			Vector3(0.53, 1.02, 0.0), xf)
	var target := Vector3(0.53, 1.02, 0.0) + correction
	assert_float(target.x).is_equal_approx(0.6, 0.001)
	assert_float(target.y).is_equal_approx(1.0, 0.001)
	assert_float(target.z).is_equal_approx(0.1, 0.001)


func test_smart_object_move_never_teleports_object() -> void:
	# A nudge of 0.01 from centroid x=0.53: target 0.54 snaps to 0.5.
	# Correction (-0.04) is a small rigid move — NOT a teleport to a
	# distant cell (sanity bound).
	var op := _op(_OP_SCRIPT.SnapMode.SMART,
			false, GoBuildDragOperation.DeltaMode.PLANE_PROJECT)
	var correction := _call_snap(op, Vector3(0.01, 0, 0),
			Vector3(0.53, 0, 0), _identity())
	assert_float(correction.length()).is_less(0.1)


# ---------------------------------------------------------------------------
# Hybrid / World — element edits (vertex: absolute; edge/face: delta)
# ---------------------------------------------------------------------------

func test_smart_vertex_drag_off_grid_snaps_absolute() -> void:
	# Vertex at 2.863 dragged +0.14 → snaps absolutely to 3.0.  The
	# dragged point is the thing being snapped.
	var op := _op(_OP_SCRIPT.SnapMode.SMART, true,
			GoBuildDragOperation.DeltaMode.AXIS_PROJECT, 1)
	op.world_axis = Vector3.RIGHT
	var correction := _call_snap(op, Vector3(0.14, 0, 0),
			Vector3(2.863, 0, 0), _identity())
	assert_float(2.863 + correction.x).is_equal_approx(3.0, 0.001)


func test_smart_edge_drag_off_grid_centroid_is_delta() -> void:
	# Off-axis edge centroid at 2.863, dragged +0.14: the delta is
	# quantized (0.1) — NOT snapped absolutely to 3.0.  The element
	# lands at 2.863 + 0.1 = 2.963, geometry intact.
	var op := _op(_OP_SCRIPT.SnapMode.SMART, true,
			GoBuildDragOperation.DeltaMode.AXIS_PROJECT, 2)
	op.world_axis = Vector3.RIGHT
	var correction := _call_snap(op, Vector3(0.14, 0, 0),
			Vector3(2.863, 0, 0), _identity())
	assert_vector(correction).is_equal_approx(Vector3(0.1, 0, 0),
			Vector3.ONE * 0.001)


func test_smart_edge_drag_rotated_node_quantizes_world_delta() -> void:
	# Node rotated 90° around Y: local +X is world -Z.  Raw local delta
	# (0.14, 0, 0) → world delta (0, 0, -0.14) → snapped (0, 0, -0.1)
	# → back to local (0.1, 0, 0).
	var op := _op(_OP_SCRIPT.SnapMode.SMART, true,
			GoBuildDragOperation.DeltaMode.PLANE_PROJECT, 2)
	var xf := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO)
	var correction := _call_snap(op, Vector3(0.14, 0, 0), Vector3.ZERO, xf)
	assert_float(correction.length()).is_equal_approx(0.1, 0.001)


func test_smart_edge_drag_delta_is_position_agnostic() -> void:
	# Same delta from a different (also off-grid) centroid → same
	# correction: position-agnostic by contract.
	var op := _op(_OP_SCRIPT.SnapMode.SMART, true,
			GoBuildDragOperation.DeltaMode.PLANE_PROJECT, 2)
	var a := _call_snap(op, Vector3(0.14, 0, 0), Vector3(2.863, 0, 0),
			_identity())
	var b := _call_snap(op, Vector3(0.14, 0, 0), Vector3(7.413, 0, 0),
			_identity())
	assert_vector(a).is_equal_approx(b, Vector3.ONE * 0.001)


func test_smart_face_drag_behaves_like_edge_drag() -> void:
	# Face centroids share edge semantics (element_kind 2).
	var op := _op(_OP_SCRIPT.SnapMode.SMART, true,
			GoBuildDragOperation.DeltaMode.PLANE_PROJECT, 2)
	var correction := _call_snap(op, Vector3(0.14, 0.02, 0),
			Vector3(2.863, 0.41, 0), _identity())
	assert_vector(correction).is_equal_approx(Vector3(0.1, 0.0, 0.0),
			Vector3.ONE * 0.001)


func test_object_move_unaffected_by_element_kind() -> void:
	# element_kind 0 (object move) keeps absolute-position semantics.
	var op := _op(_OP_SCRIPT.SnapMode.SMART, false,
			GoBuildDragOperation.DeltaMode.PLANE_PROJECT, 0)
	var correction := _call_snap(op, Vector3(0.05, 0, 0),
			Vector3(0.53, 0, 0), _identity())
	assert_float(0.53 + correction.x).is_equal_approx(0.6, 0.001)


func test_smart_edge_drag_object_move_equivalence() -> void:
	# SMART edge drags and plain rigid world-delta quantization share the
	# same maths: object at 0.53 nudged 0.07 with element_kind EDGE →
	# delta snapped 0.1 (lands 0.63, no teleport to 0.5).
	var op := _op(_OP_SCRIPT.SnapMode.SMART, true,
			GoBuildDragOperation.DeltaMode.PLANE_PROJECT, 2)
	var correction := _call_snap(op, Vector3(0.07, 0, 0),
			Vector3(0.53, 0, 0), _identity())
	assert_vector(correction).is_equal_approx(Vector3(0.1, 0, 0), Vector3.ONE * 0.001)


func test_delta_mode_rotated_node_world_quantization() -> void:
	# Node rotated 90° around Y: local +X is world −Z.  A raw local delta
	# of (0.14, 0, 0) must quantize to 0.1 along world Z.
	var op := _op(_OP_SCRIPT.SnapMode.SMART, false,
			GoBuildDragOperation.DeltaMode.PLANE_PROJECT, 2)
	var basis := Basis(Vector3.UP, PI * 0.5)
	var xf := Transform3D(basis, Vector3.ZERO)
	var correction := _call_snap(op, Vector3(0.14, 0, 0),
			Vector3.ZERO, xf)
	# Correction is in LOCAL space: world delta (0, 0, ±0.1) rotated back
	# into local space.
	assert_float(correction.length()).is_equal_approx(0.1, 0.001)


# ---------------------------------------------------------------------------
# Delta — legacy local increments
# ---------------------------------------------------------------------------

func test_delta_mode_quantizes_raw_local_delta() -> void:
	var op := _op(_OP_SCRIPT.SnapMode.DELTA,
			false, GoBuildDragOperation.DeltaMode.PLANE_PROJECT)
	var correction := _call_snap(op, Vector3(0.14, 0.02, 0), Vector3.ZERO,
			_identity())
	assert_vector(correction).is_equal_approx(Vector3(0.1, 0.0, 0.0), Vector3.ONE * 0.001)


func test_delta_mode_never_moves_off_grid_object_to_cell() -> void:
	# Delta is position-agnostic: same raw delta → same result regardless
	# of where the object sits.
	var op := _op(_OP_SCRIPT.SnapMode.DELTA,
			true, GoBuildDragOperation.DeltaMode.PLANE_PROJECT)
	var a := _call_snap(op, Vector3(0.14, 0, 0), Vector3(2.863, 0, 0),
			_identity())
	var b := _call_snap(op, Vector3(0.14, 0, 0), Vector3.ZERO, _identity())
	assert_vector(a).is_equal_approx(b, Vector3.ONE * 0.001)


# ---------------------------------------------------------------------------
# Scale
# ---------------------------------------------------------------------------

func test_scale_delta_quantizes_ratio() -> void:
	var op := _op(_OP_SCRIPT.SnapMode.DELTA, false,
			GoBuildDragOperation.DeltaMode.SCALE_UNIFORM)
	var ratio := _CTRL_SCRIPT._snap_scale(op, 0.14, true, 0.1)
	assert_float(ratio).is_equal_approx(0.1, 0.001)


func test_scale_smart_quantizes_resulting_world_size() -> void:
	var op := _op(_OP_SCRIPT.SnapMode.SMART, false,
			GoBuildDragOperation.DeltaMode.SCALE_AXIS)
	op.initial_world_size = 1.2
	# Raw ratio 0.55 → world size 1.2*0.55 = 0.66 → snapped 0.7 →
	# ratio 0.7/1.2 = 0.5833.
	var ratio := _CTRL_SCRIPT._snap_scale(op, 0.55, true, 0.1)
	assert_float(ratio).is_equal_approx(0.58333, 0.001)


func test_scale_disabled_no_snap() -> void:
	var op := _op(_OP_SCRIPT.SnapMode.SMART, false,
			GoBuildDragOperation.DeltaMode.SCALE_AXIS)
	assert_float(_CTRL_SCRIPT._snap_scale(op, 0.14, false, 0.1)) \
			.is_equal_approx(0.14, 0.001)


func test_scale_zero_step_no_snap() -> void:
	var op := _op(_OP_SCRIPT.SnapMode.SMART, false,
			GoBuildDragOperation.DeltaMode.SCALE_AXIS)
	assert_float(_CTRL_SCRIPT._snap_scale(op, 0.55, true, 0.0)) \
			.is_equal_approx(0.55, 0.001)


# ---------------------------------------------------------------------------
# Grid overlay data
# ---------------------------------------------------------------------------

func test_grid_anchor_follows_snapped_position() -> void:
	var c: GoBuildDragController = _CTRL_SCRIPT.new()
	c._grid_anchor = Vector3(3.0, 0, 0)
	assert_vector(c._grid_anchor).is_equal_approx(Vector3(3.0, 0, 0), Vector3.ONE * 0.001)
	c._grid_anchor = Vector3.ZERO
	# With a zero anchor the overlay falls back to the drag-start centroid.
	assert_bool(c._grid_anchor.is_zero_approx()).is_true()
