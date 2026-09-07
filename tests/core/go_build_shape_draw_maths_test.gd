## Pure draw-flow maths tests — [ShapeDrawMaths].
##
## The snap semantics under test:
##  - WORLD_GRID: cursor POSITION snaps to the 3D world grid (grid-aligned
##    footprints); height snaps the TOP face's absolute coordinate.
##  - DELTA_GRID: dimension VALUES snap.
@tool
extends GdUnitTestSuite

const _MATHS := preload("res://addons/go_build/core/go_build_shape_draw_maths.gd")

const _STEP: float = 1.0


# ---------------------------------------------------------------------------
# basis_from_width_dir
# ---------------------------------------------------------------------------

func test_basis_x_along_width_dir() -> void:
	var b: Basis = _MATHS.basis_from_width_dir(Vector3(2, 0, 0), Vector3.UP)
	assert_vector(b.x).is_equal_approx(Vector3.RIGHT, Vector3.ONE * 0.001)
	assert_vector(b.y).is_equal_approx(Vector3.UP, Vector3.ONE * 0.001)


func test_basis_is_right_handed_with_z_perpendicular() -> void:
	var b: Basis = _MATHS.basis_from_width_dir(Vector3(1, 0, 0), Vector3.UP)
	# x = RIGHT, y = UP → z = x × y = BACK... right-handed: z = x.cross(y)
	assert_vector(b.z).is_equal_approx(Vector3.RIGHT.cross(Vector3.UP),
			Vector3.ONE * 0.001)


func test_basis_diagonal_width_dir_normalized() -> void:
	var b: Basis = _MATHS.basis_from_width_dir(
			Vector3(1, 0, 1), Vector3.UP)
	assert_vector(b.x).is_equal_approx(Vector3(1, 0, 1).normalized(),
			Vector3.ONE * 0.001)


func test_basis_width_parallel_to_normal_gets_fallback_up() -> void:
	# Width dir along +X, normal also +X — degenerate; falls back.
	var b: Basis = _MATHS.basis_from_width_dir(Vector3(1, 0, 0), Vector3.RIGHT)
	assert_vector(b.x).is_equal_approx(Vector3.RIGHT, Vector3.ONE * 0.001)


# ---------------------------------------------------------------------------
# width_result
# ---------------------------------------------------------------------------

func test_width_plain_measures_distance() -> void:
	var r := _MATHS.width_result(Vector3.ZERO, Vector3(3, 0, 4),
			Vector3.UP, _STEP, false, _MATHS.SnapMode.WORLD_GRID)
	assert_float(r["width"]).is_equal_approx(5.0, 0.001)


func test_width_world_snap_snaps_cursor_position() -> void:
	# Cursor at x=2.7 → snapped to 3 → width 3 (not 2.7).
	var r := _MATHS.width_result(Vector3.ZERO, Vector3(2.7, 0, 0),
			Vector3.UP, _STEP, true, _MATHS.SnapMode.WORLD_GRID)
	assert_float(r["width"]).is_equal_approx(3.0, 0.001)


func test_width_delta_snap_snaps_value_not_position() -> void:
	# Cursor at 2.7: value snaps to 3 — same here; at 2.4 → 2.
	var r := _MATHS.width_result(Vector3.ZERO, Vector3(2.4, 0, 0),
			Vector3.UP, _STEP, true, _MATHS.SnapMode.DELTA_GRID)
	assert_float(r["width"]).is_equal_approx(2.0, 0.001)


func test_width_world_snap_offgrid_anchor_measures_from_anchor() -> void:
	# Anchor off-grid (0.37): snapped cursor (3,0,0) → width = 2.63.
	var r := _MATHS.width_result(Vector3(0.37, 0, 0), Vector3(2.7, 0, 0),
			Vector3.UP, _STEP, true, _MATHS.SnapMode.WORLD_GRID)
	assert_float(r["width"]).is_equal_approx(2.63, 0.001)


func test_width_degenerate_returns_empty() -> void:
	var r := _MATHS.width_result(Vector3.ZERO, Vector3(0.001, 0, 0),
			Vector3.UP, _STEP, false, _MATHS.SnapMode.WORLD_GRID)
	assert_bool(r.is_empty()).is_true()


func test_width_basis_orientation_follows_cursor() -> void:
	# Cursor at -Z: local +X points toward -Z (orientation from stroke).
	var r := _MATHS.width_result(Vector3.ZERO, Vector3(0, 0, -2),
			Vector3.UP, _STEP, false, _MATHS.SnapMode.WORLD_GRID)
	var b: Basis = r["basis"]
	assert_vector(b.x).is_equal_approx(Vector3(0, 0, -1), Vector3.ONE * 0.001)


func test_width_no_ctrl_never_snaps() -> void:
	var r := _MATHS.width_result(Vector3.ZERO, Vector3(2.4, 0, 0),
			Vector3.UP, _STEP, false, _MATHS.SnapMode.WORLD_GRID)
	assert_float(r["width"]).is_equal_approx(2.4, 0.001)


# ---------------------------------------------------------------------------
# length_result
# ---------------------------------------------------------------------------

func test_length_plain_measures_perpendicular_distance() -> void:
	var basis := Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK)
	var r := _MATHS.length_result(Vector3.ZERO, Vector3(0, 0, 2.5),
			basis, 2.0, false, false, _STEP, _MATHS.SnapMode.WORLD_GRID)
	assert_float(r["depth"]).is_equal_approx(2.5, 0.001)
	assert_float(r["drag_dir_z"]).is_equal_approx(1.0, 0.001)


func test_length_world_snap_snaps_cursor_position() -> void:
	var basis := Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK)
	# Cursor z=1.6 → snapped 2 → depth 2.
	var r := _MATHS.length_result(Vector3.ZERO, Vector3(0, 0, 1.6),
			basis, 2.0, false, true, _STEP, _MATHS.SnapMode.WORLD_GRID)
	assert_float(r["depth"]).is_equal_approx(2.0, 0.001)


func test_length_delta_snap_snaps_value() -> void:
	var basis := Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK)
	var r := _MATHS.length_result(Vector3.ZERO, Vector3(0, 0, 1.4),
			basis, 2.0, false, true, _STEP, _MATHS.SnapMode.DELTA_GRID)
	assert_float(r["depth"]).is_equal_approx(1.0, 0.001)


func test_length_negative_side_gives_negative_dir() -> void:
	var basis := Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK)
	var r := _MATHS.length_result(Vector3.ZERO, Vector3(0, 0, -2),
			basis, 2.0, false, false, _STEP, _MATHS.SnapMode.WORLD_GRID)
	assert_float(r["depth"]).is_equal_approx(2.0, 0.001)
	assert_float(r["drag_dir_z"]).is_equal_approx(-1.0, 0.001)


func test_length_shift_square_uses_width() -> void:
	var basis := Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK)
	# Cursor depth 3.0 + Shift → depth = width (2.0).
	var r := _MATHS.length_result(Vector3.ZERO, Vector3(0, 0, 3.0),
			basis, 2.0, true, false, _STEP, _MATHS.SnapMode.WORLD_GRID)
	assert_float(r["depth"]).is_equal_approx(2.0, 0.001)


func test_length_shift_square_keeps_side_sign() -> void:
	var basis := Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK)
	var r := _MATHS.length_result(Vector3.ZERO, Vector3(0, 0, -3.0),
			basis, 2.0, true, false, _STEP, _MATHS.SnapMode.WORLD_GRID)
	assert_float(r["depth"]).is_equal_approx(2.0, 0.001)
	assert_float(r["drag_dir_z"]).is_equal_approx(-1.0, 0.001)


func test_length_degenerate_returns_empty() -> void:
	var basis := Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK)
	var r := _MATHS.length_result(Vector3.ZERO, Vector3(2, 0, 0),
			basis, 2.0, false, false, _STEP, _MATHS.SnapMode.WORLD_GRID)
	assert_bool(r.is_empty()).is_true()


# ---------------------------------------------------------------------------
# height_result
# ---------------------------------------------------------------------------

func test_height_plain_measures_normal_component() -> void:
	var r := _MATHS.height_result(Vector3.ZERO, Vector3(0, 2.5, 0),
			Vector3.UP, false, _STEP, _MATHS.SnapMode.WORLD_GRID)
	assert_float(r["height"]).is_equal_approx(2.5, 0.001)


func test_height_world_snap_lands_top_on_grid_from_ground() -> void:
	# Anchor on ground (y=0): raw 2.3 → top at grid 2.0.
	var r := _MATHS.height_result(Vector3.ZERO, Vector3(0, 2.3, 0),
			Vector3.UP, true, _STEP, _MATHS.SnapMode.WORLD_GRID)
	assert_float(r["height"]).is_equal_approx(2.0, 0.001)


func test_height_world_snap_offgrid_surface_top_on_grid() -> void:
	# Anchor at y=0.37, raw h 1.93 → hit at 2.3 → snapped top 2.0
	# → h = 1.63 (top face exactly on the grid plane).
	var r := _MATHS.height_result(Vector3(0, 0.37, 0), Vector3(0, 2.3, 0),
			Vector3.UP, true, _STEP, _MATHS.SnapMode.WORLD_GRID)
	assert_float(r["height"]).is_equal_approx(1.63, 0.001)


func test_height_delta_snap_snaps_value_not_top() -> void:
	# Anchor 0.37 + snapped h 2.0 → top at 2.37 (off-grid, delta semantics).
	var r := _MATHS.height_result(Vector3(0, 0.37, 0), Vector3(0, 2.3, 0),
			Vector3.UP, true, _STEP, _MATHS.SnapMode.DELTA_GRID)
	assert_float(r["height"]).is_equal_approx(2.0, 0.001)


func test_height_no_ctrl_never_snaps() -> void:
	var r := _MATHS.height_result(Vector3.ZERO, Vector3(0, 2.3, 0),
			Vector3.UP, false, _STEP, _MATHS.SnapMode.WORLD_GRID)
	assert_float(r["height"]).is_equal_approx(2.3, 0.001)


func test_height_clamped_to_minimum() -> void:
	# Cursor below the anchor → clamped to minimum dimension.
	var r := _MATHS.height_result(Vector3.ZERO, Vector3(0, -5, 0),
			Vector3.UP, false, _STEP, _MATHS.SnapMode.WORLD_GRID)
	assert_float(r["height"]).is_equal_approx(0.01, 0.0001)


# ---------------------------------------------------------------------------
# world_snap
# ---------------------------------------------------------------------------

func test_world_snap_all_axes() -> void:
	var p: Vector3 = _MATHS.world_snap(Vector3(0.6, 1.4, -0.9), _STEP)
	assert_vector(p).is_equal_approx(Vector3(1, 1, -1),
			Vector3.ONE * 0.001)


func test_world_snap_zero_step_is_identity() -> void:
	var p: Vector3 = _MATHS.world_snap(Vector3(0.37, 2.3, 1.9), 0.0)
	assert_vector(p).is_equal_approx(Vector3(0.37, 2.3, 1.9),
			Vector3.ONE * 0.001)