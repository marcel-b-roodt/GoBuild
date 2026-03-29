## Unit tests for [SelectionManager].
##
## Pure-logic tests — no scene tree required.
## Run via the GdUnit4 panel in the Godot editor.
@tool
extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make() -> SelectionManager:
	return SelectionManager.new()


# ---------------------------------------------------------------------------
# Mode
# ---------------------------------------------------------------------------

func test_default_mode_is_object() -> void:
	var sm := _make()
	assert_int(sm.get_mode()).is_equal(SelectionManager.Mode.OBJECT)


func test_set_mode_changes_mode() -> void:
	var sm := _make()
	sm.set_mode(SelectionManager.Mode.VERTEX)
	assert_int(sm.get_mode()).is_equal(SelectionManager.Mode.VERTEX)


func test_set_mode_noop_when_same() -> void:
	var sm := _make()
	# Capture signal emission count via a flag.
	var emitted := false
	sm.mode_changed.connect(func(_m): emitted = true)
	sm.set_mode(SelectionManager.Mode.OBJECT)   # already OBJECT
	assert_bool(emitted).is_false()


func test_set_mode_clears_selection() -> void:
	var sm := _make()
	sm.set_mode(SelectionManager.Mode.VERTEX)
	sm.select_vertex(0)
	sm.select_vertex(1)
	sm.set_mode(SelectionManager.Mode.FACE)     # switch clears verts
	assert_array(sm.get_selected_vertices()).is_empty()


func test_set_mode_emits_mode_changed() -> void:
	var sm := _make()
	var received: Array[SelectionManager.Mode] = []
	sm.mode_changed.connect(func(m): received.append(m))
	sm.set_mode(SelectionManager.Mode.EDGE)
	assert_array(received).has_size(1)
	assert_int(received[0]).is_equal(SelectionManager.Mode.EDGE)


# ---------------------------------------------------------------------------
# Vertex selection
# ---------------------------------------------------------------------------

func test_select_vertex() -> void:
	var sm := _make()
	sm.set_mode(SelectionManager.Mode.VERTEX)
	sm.select_vertex(3)
	assert_bool(sm.is_vertex_selected(3)).is_true()


func test_select_vertex_idempotent() -> void:
	var sm := _make()
	sm.set_mode(SelectionManager.Mode.VERTEX)
	sm.select_vertex(3)
	sm.select_vertex(3)
	assert_int(sm.get_selected_vertices().size()).is_equal(1)


func test_deselect_vertex() -> void:
	var sm := _make()
	sm.set_mode(SelectionManager.Mode.VERTEX)
	sm.select_vertex(5)
	sm.deselect_vertex(5)
	assert_bool(sm.is_vertex_selected(5)).is_false()


func test_deselect_vertex_noop_when_not_selected() -> void:
	var sm := _make()
	sm.set_mode(SelectionManager.Mode.VERTEX)
	# Should not crash.
	sm.deselect_vertex(99)
	assert_array(sm.get_selected_vertices()).is_empty()


func test_toggle_vertex_on() -> void:
	var sm := _make()
	sm.set_mode(SelectionManager.Mode.VERTEX)
	sm.toggle_vertex(2)
	assert_bool(sm.is_vertex_selected(2)).is_true()


func test_toggle_vertex_off() -> void:
	var sm := _make()
	sm.set_mode(SelectionManager.Mode.VERTEX)
	sm.select_vertex(2)
	sm.toggle_vertex(2)
	assert_bool(sm.is_vertex_selected(2)).is_false()


func test_get_selected_vertices_returns_copy() -> void:
	var sm := _make()
	sm.set_mode(SelectionManager.Mode.VERTEX)
	sm.select_vertex(1)
	var copy := sm.get_selected_vertices()
	copy.append(999)                    # mutate the copy
	assert_int(sm.get_selected_vertices().size()).is_equal(1)   # original unchanged


func test_set_selected_vertices_bulk() -> void:
	var sm := _make()
	sm.set_mode(SelectionManager.Mode.VERTEX)
	var indices: Array[int] = [0, 1, 4]
	sm.set_selected_vertices(indices)
	assert_array(sm.get_selected_vertices()).contains_exactly_in_any_order([0, 1, 4])


# ---------------------------------------------------------------------------
# Edge selection
# ---------------------------------------------------------------------------

func test_select_edge() -> void:
	var sm := _make()
	sm.set_mode(SelectionManager.Mode.EDGE)
	sm.select_edge(7)
	assert_bool(sm.is_edge_selected(7)).is_true()


func test_deselect_edge() -> void:
	var sm := _make()
	sm.set_mode(SelectionManager.Mode.EDGE)
	sm.select_edge(7)
	sm.deselect_edge(7)
	assert_bool(sm.is_edge_selected(7)).is_false()


func test_toggle_edge() -> void:
	var sm := _make()
	sm.set_mode(SelectionManager.Mode.EDGE)
	sm.toggle_edge(2)
	assert_bool(sm.is_edge_selected(2)).is_true()
	sm.toggle_edge(2)
	assert_bool(sm.is_edge_selected(2)).is_false()


# ---------------------------------------------------------------------------
# Face selection
# ---------------------------------------------------------------------------

func test_select_face() -> void:
	var sm := _make()
	sm.set_mode(SelectionManager.Mode.FACE)
	sm.select_face(0)
	assert_bool(sm.is_face_selected(0)).is_true()


func test_deselect_face() -> void:
	var sm := _make()
	sm.set_mode(SelectionManager.Mode.FACE)
	sm.select_face(0)
	sm.deselect_face(0)
	assert_bool(sm.is_face_selected(0)).is_false()


func test_toggle_face() -> void:
	var sm := _make()
	sm.set_mode(SelectionManager.Mode.FACE)
	sm.toggle_face(3)
	assert_bool(sm.is_face_selected(3)).is_true()
	sm.toggle_face(3)
	assert_bool(sm.is_face_selected(3)).is_false()


func test_set_selected_faces_bulk() -> void:
	var sm := _make()
	sm.set_mode(SelectionManager.Mode.FACE)
	var indices: Array[int] = [0, 2, 5]
	sm.set_selected_faces(indices)
	assert_array(sm.get_selected_faces()).contains_exactly_in_any_order([0, 2, 5])


# ---------------------------------------------------------------------------
# Clear
# ---------------------------------------------------------------------------

func test_clear_removes_all_elements() -> void:
	var sm := _make()
	sm.set_mode(SelectionManager.Mode.VERTEX)
	sm.select_vertex(0)
	sm.set_mode(SelectionManager.Mode.EDGE)
	sm.select_edge(0)
	sm.set_mode(SelectionManager.Mode.FACE)
	sm.select_face(0)
	sm.clear()
	assert_bool(sm.is_empty()).is_true()


func test_is_empty_true_by_default() -> void:
	var sm := _make()
	assert_bool(sm.is_empty()).is_true()


func test_is_empty_false_when_vertex_selected() -> void:
	var sm := _make()
	sm.set_mode(SelectionManager.Mode.VERTEX)
	sm.select_vertex(0)
	assert_bool(sm.is_empty()).is_false()


# ---------------------------------------------------------------------------
# selection_changed signal
# ---------------------------------------------------------------------------

func test_selection_changed_emitted_on_select_vertex() -> void:
	var sm := _make()
	var count := 0
	sm.selection_changed.connect(func(): count += 1)
	sm.select_vertex(1)
	assert_int(count).is_greater_equal(1)


func test_selection_changed_emitted_on_clear() -> void:
	var sm := _make()
	sm.select_vertex(0)
	var count := 0
	sm.selection_changed.connect(func(): count += 1)
	sm.clear()
	assert_int(count).is_greater_equal(1)

