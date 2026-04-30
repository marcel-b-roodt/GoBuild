## Unit tests for [OverlayHintHelper].
##
## All tests are pure-logic: no scene tree required.
## Run via the GdUnit4 panel in the Godot editor.
@tool
extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Convenience aliases for transform mode ints.
# ---------------------------------------------------------------------------

const T := OverlayHintHelper.TRANSLATE
const R := OverlayHintHelper.ROTATE
const S := OverlayHintHelper.SCALE


# ---------------------------------------------------------------------------
# build_hint — OBJECT mode
# ---------------------------------------------------------------------------

func test_hint_object_mode_returns_empty() -> void:
	assert_str(OverlayHintHelper.build_hint(
			SelectionManager.Mode.OBJECT, T, false, false)).is_equal("")


func test_hint_object_mode_with_modifiers_still_empty() -> void:
	assert_str(OverlayHintHelper.build_hint(
			SelectionManager.Mode.OBJECT, T, true, true)).is_equal("")


# ---------------------------------------------------------------------------
# build_hint — mode labels
# ---------------------------------------------------------------------------

func test_hint_vertex_mode_label() -> void:
	var h := OverlayHintHelper.build_hint(SelectionManager.Mode.VERTEX, T, false, false)
	assert_str(h).contains("Vertex")


func test_hint_edge_mode_label() -> void:
	var h := OverlayHintHelper.build_hint(SelectionManager.Mode.EDGE, T, false, false)
	assert_str(h).contains("Edge")


func test_hint_face_mode_label() -> void:
	var h := OverlayHintHelper.build_hint(SelectionManager.Mode.FACE, T, false, false)
	assert_str(h).contains("Face")


# ---------------------------------------------------------------------------
# build_hint — translate mode (default, no modifiers)
# ---------------------------------------------------------------------------

func test_hint_translate_no_modifiers_shows_move() -> void:
	var h := OverlayHintHelper.build_hint(SelectionManager.Mode.VERTEX, T, false, false)
	assert_str(h).contains("Move")


func test_hint_translate_no_modifiers_shows_ctrl_snap_hint() -> void:
	var h := OverlayHintHelper.build_hint(SelectionManager.Mode.VERTEX, T, false, false)
	assert_str(h).contains("Ctrl: Snap")


func test_hint_translate_no_modifiers_face_shows_extrude_hint() -> void:
	var h := OverlayHintHelper.build_hint(SelectionManager.Mode.FACE, T, false, false)
	assert_str(h).contains("Shift: Extrude")


func test_hint_translate_no_modifiers_edge_shows_extrude_edge_hint() -> void:
	var h := OverlayHintHelper.build_hint(SelectionManager.Mode.EDGE, T, false, false)
	assert_str(h).contains("Shift: Extrude Edge")


# ---------------------------------------------------------------------------
# build_hint — translate with modifiers
# ---------------------------------------------------------------------------

func test_hint_translate_shift_face_shows_extrude_op() -> void:
	var h := OverlayHintHelper.build_hint(SelectionManager.Mode.FACE, T, true, false)
	assert_str(h).contains("EXTRUDE")


func test_hint_translate_shift_edge_shows_extrude_edge_op() -> void:
	var h := OverlayHintHelper.build_hint(SelectionManager.Mode.EDGE, T, true, false)
	assert_str(h).contains("EXTRUDE EDGE")


func test_hint_translate_shift_vertex_shows_move() -> void:
	var h := OverlayHintHelper.build_hint(SelectionManager.Mode.VERTEX, T, true, false)
	assert_str(h).contains("Move")


func test_hint_translate_ctrl_shows_snap_op() -> void:
	var h := OverlayHintHelper.build_hint(SelectionManager.Mode.VERTEX, T, false, true)
	assert_str(h).contains("SNAP")


func test_hint_translate_ctrl_hides_shortcut_hints() -> void:
	# When ctrl is active, no "Shift: Extrude" hint should appear.
	var h := OverlayHintHelper.build_hint(SelectionManager.Mode.FACE, T, false, true)
	assert_str(h).not_contains("Shift: Extrude")


func test_hint_translate_shift_shows_ctrl_snap_hint() -> void:
	var h := OverlayHintHelper.build_hint(SelectionManager.Mode.FACE, T, true, false)
	assert_str(h).contains("+Ctrl: Snap")


# ---------------------------------------------------------------------------
# build_hint — rotate mode
# ---------------------------------------------------------------------------

func test_hint_rotate_no_modifiers_shows_rotate() -> void:
	var h := OverlayHintHelper.build_hint(SelectionManager.Mode.VERTEX, R, false, false)
	assert_str(h).contains("Rotate")


func test_hint_rotate_no_hints_when_no_modifiers() -> void:
	# Rotate mode has no shortcut-hint row in the default state.
	var h := OverlayHintHelper.build_hint(SelectionManager.Mode.VERTEX, R, false, false)
	assert_bool(h.ends_with("Rotate")).is_true()


# ---------------------------------------------------------------------------
# build_hint — scale mode
# ---------------------------------------------------------------------------

func test_hint_scale_no_modifiers_shows_scale() -> void:
	var h := OverlayHintHelper.build_hint(SelectionManager.Mode.VERTEX, S, false, false)
	assert_str(h).contains("Scale")


func test_hint_scale_no_modifiers_face_shows_inset_hint() -> void:
	var h := OverlayHintHelper.build_hint(SelectionManager.Mode.FACE, S, false, false)
	assert_str(h).contains("Shift: Inset")


func test_hint_scale_shift_face_shows_inset_op() -> void:
	var h := OverlayHintHelper.build_hint(SelectionManager.Mode.FACE, S, true, false)
	assert_str(h).contains("INSET")


func test_hint_scale_ctrl_shows_snap_op() -> void:
	var h := OverlayHintHelper.build_hint(SelectionManager.Mode.FACE, S, false, true)
	assert_str(h).contains("SNAP")


# ---------------------------------------------------------------------------
# build_panel_context — OBJECT mode
# ---------------------------------------------------------------------------

func test_context_object_mode_returns_empty() -> void:
	assert_str(OverlayHintHelper.build_panel_context(
			SelectionManager.Mode.OBJECT, T, false, false, false)).is_equal("")


# ---------------------------------------------------------------------------
# build_panel_context — translate mode
# ---------------------------------------------------------------------------

func test_context_translate_no_modifiers_returns_move() -> void:
	assert_str(OverlayHintHelper.build_panel_context(
			SelectionManager.Mode.VERTEX, T, false, false, false)).is_equal("Move")


func test_context_translate_shift_face_returns_extrude() -> void:
	assert_str(OverlayHintHelper.build_panel_context(
			SelectionManager.Mode.FACE, T, true, false, false)).is_equal("■ Extrude")


func test_context_translate_shift_edge_returns_extrude_edge() -> void:
	assert_str(OverlayHintHelper.build_panel_context(
			SelectionManager.Mode.EDGE, T, true, false, false)).is_equal("■ Extrude Edge")


func test_context_translate_ctrl_returns_snap() -> void:
	assert_str(OverlayHintHelper.build_panel_context(
			SelectionManager.Mode.VERTEX, T, false, true, false)).is_equal("■ Snap")


func test_context_translate_alt_returns_alt_vertex_snap() -> void:
	assert_str(OverlayHintHelper.build_panel_context(
			SelectionManager.Mode.VERTEX, T, false, false, true)).is_equal("■ Alt Vertex Snap")


# ---------------------------------------------------------------------------
# build_panel_context — rotate mode
# ---------------------------------------------------------------------------

func test_context_rotate_no_modifiers_returns_rotate() -> void:
	assert_str(OverlayHintHelper.build_panel_context(
			SelectionManager.Mode.VERTEX, R, false, false, false)).is_equal("Rotate")


func test_context_rotate_ctrl_returns_snap() -> void:
	assert_str(OverlayHintHelper.build_panel_context(
			SelectionManager.Mode.VERTEX, R, false, true, false)).is_equal("■ Snap")


# ---------------------------------------------------------------------------
# build_panel_context — scale mode
# ---------------------------------------------------------------------------

func test_context_scale_no_modifiers_returns_scale() -> void:
	assert_str(OverlayHintHelper.build_panel_context(
			SelectionManager.Mode.VERTEX, S, false, false, false)).is_equal("Scale")


func test_context_scale_shift_face_returns_inset() -> void:
	assert_str(OverlayHintHelper.build_panel_context(
			SelectionManager.Mode.FACE, S, true, false, false)).is_equal("■ Inset")


func test_context_scale_ctrl_returns_snap() -> void:
	assert_str(OverlayHintHelper.build_panel_context(
			SelectionManager.Mode.FACE, S, false, true, false)).is_equal("■ Snap")
