## MaterialAssignOperation tests — GdUnit4
extends GdUnitTestSuite

const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _OP_SCRIPT   := preload("res://addons/go_build/mesh/operations/material_assign_operation.gd")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Build a simple mesh with [param face_count] quads sharing no vertices.
func _make_mesh(face_count: int) -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	for fi: int in face_count:
		var base: int = fi * 4
		mesh.vertices.append_array([
			Vector3(float(fi), 0.0, 0.0),
			Vector3(float(fi), 1.0, 0.0),
			Vector3(float(fi), 1.0, 1.0),
			Vector3(float(fi), 0.0, 1.0),
		])
		var face := GoBuildFace.new()
		face.vertex_indices = [base, base + 1, base + 2, base + 3]
		face.uvs = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
		face.material_index = 0
		mesh.faces.append(face)
	return mesh


# ---------------------------------------------------------------------------
# Basic assignment
# ---------------------------------------------------------------------------

func test_assign_sets_material_index_on_selected_faces() -> void:
	var mesh := _make_mesh(3)
	var indices: Array[int] = [0, 2]
	MaterialAssignOperation.apply(mesh, indices, 1)
	assert_int(mesh.faces[0].material_index).is_equal(1)
	assert_int(mesh.faces[1].material_index).is_equal(0)  # untouched
	assert_int(mesh.faces[2].material_index).is_equal(1)


func test_assign_to_slot_zero_keeps_existing_zero_index() -> void:
	var mesh := _make_mesh(1)
	mesh.faces[0].material_index = 2
	var indices: Array[int] = [0]
	MaterialAssignOperation.apply(mesh, indices, 0)
	assert_int(mesh.faces[0].material_index).is_equal(0)


func test_assign_does_not_touch_unselected_faces() -> void:
	var mesh := _make_mesh(4)
	# Give each face a distinct starting index.
	for i: int in 4:
		mesh.faces[i].material_index = i
	var indices: Array[int] = [1]
	MaterialAssignOperation.apply(mesh, indices, 7)
	assert_int(mesh.faces[0].material_index).is_equal(0)
	assert_int(mesh.faces[1].material_index).is_equal(7)
	assert_int(mesh.faces[2].material_index).is_equal(2)
	assert_int(mesh.faces[3].material_index).is_equal(3)


# ---------------------------------------------------------------------------
# material_slots growth
# ---------------------------------------------------------------------------

func test_material_slots_grown_when_index_exceeds_current_size() -> void:
	var mesh := _make_mesh(1)
	assert_int(mesh.material_slots.size()).is_equal(0)
	var indices: Array[int] = [0]
	MaterialAssignOperation.apply(mesh, indices, 2)
	# Slots must be at least index + 1 = 3.
	assert_int(mesh.material_slots.size()).is_greater_equal(3)


func test_material_object_written_to_slot_when_provided() -> void:
	var mesh := _make_mesh(1)
	var mat := StandardMaterial3D.new()
	var indices: Array[int] = [0]
	MaterialAssignOperation.apply(mesh, indices, 0, mat)
	assert_object(mesh.material_slots[0]).is_equal(mat)


func test_material_object_not_overwritten_when_null() -> void:
	var mesh := _make_mesh(1)
	var mat := StandardMaterial3D.new()
	mesh.material_slots.append(mat)
	var indices: Array[int] = [0]
	# Passing null should leave the existing slot material alone.
	MaterialAssignOperation.apply(mesh, indices, 0, null)
	assert_object(mesh.material_slots[0]).is_equal(mat)


# ---------------------------------------------------------------------------
# Guard conditions
# ---------------------------------------------------------------------------

func test_noop_for_empty_face_indices() -> void:
	var mesh := _make_mesh(2)
	mesh.faces[0].material_index = 3
	var empty: Array[int] = []
	MaterialAssignOperation.apply(mesh, empty, 1)
	assert_int(mesh.faces[0].material_index).is_equal(3)


func test_noop_for_null_mesh() -> void:
	# Should not crash.
	var empty: Array[int] = []
	MaterialAssignOperation.apply(null, empty, 0)


func test_noop_for_negative_material_index() -> void:
	var mesh := _make_mesh(1)
	mesh.faces[0].material_index = 5
	var indices: Array[int] = [0]
	MaterialAssignOperation.apply(mesh, indices, -1)
	assert_int(mesh.faces[0].material_index).is_equal(5)


func test_out_of_range_face_index_skipped() -> void:
	var mesh := _make_mesh(2)
	var indices: Array[int] = [0, 99]
	MaterialAssignOperation.apply(mesh, indices, 1)
	assert_int(mesh.faces[0].material_index).is_equal(1)


# ---------------------------------------------------------------------------
# apply_to_selected_faces — slot splitting
# ---------------------------------------------------------------------------

func test_apply_to_selected_faces_basic() -> void:
	var mesh := _make_mesh(3)
	var old_mat := StandardMaterial3D.new()
	old_mat.albedo_color = Color.WHITE
	mesh.material_slots.append(old_mat)
	var new_mat := StandardMaterial3D.new()
	new_mat.albedo_color = Color.RED
	var selected: Array[int] = [0]
	MaterialAssignOperation.apply_to_selected_faces(mesh, selected, 0, new_mat)
	assert_int(mesh.faces[0].material_index).is_equal(0)
	assert_object(mesh.material_slots[0]).is_equal(new_mat)
	assert_int(mesh.faces[1].material_index).is_equal(1)
	assert_int(mesh.faces[2].material_index).is_equal(1)
	assert_object(mesh.material_slots[1]).is_equal(old_mat)


func test_apply_to_selected_faces_no_split_when_only_selected_use_slot() -> void:
	var mesh := _make_mesh(2)
	mesh.faces[0].material_index = 0
	mesh.faces[1].material_index = 1
	mesh.material_slots.append(StandardMaterial3D.new())
	mesh.material_slots.append(StandardMaterial3D.new())
	var new_mat := StandardMaterial3D.new()
	new_mat.albedo_color = Color.RED
	var selected: Array[int] = [0]
	MaterialAssignOperation.apply_to_selected_faces(mesh, selected, 0, new_mat)
	assert_int(mesh.faces[0].material_index).is_equal(0)
	assert_int(mesh.faces[1].material_index).is_equal(1)
	assert_object(mesh.material_slots[0]).is_equal(new_mat)
	assert_int(mesh.material_slots.size()).is_equal(2)


func test_apply_to_selected_faces_noop_when_same_material() -> void:
	var mesh := _make_mesh(3)
	var mat := StandardMaterial3D.new()
	mesh.material_slots.append(mat)
	var selected: Array[int] = [0]
	MaterialAssignOperation.apply_to_selected_faces(mesh, selected, 0, mat)
	assert_int(mesh.faces[0].material_index).is_equal(0)
	assert_int(mesh.faces[1].material_index).is_equal(0)
	assert_int(mesh.faces[2].material_index).is_equal(0)
	assert_int(mesh.material_slots.size()).is_equal(1)


func test_apply_to_selected_faces_noop_null_mesh() -> void:
	var new_mat := StandardMaterial3D.new()
	var selected: Array[int] = [0]
	MaterialAssignOperation.apply_to_selected_faces(null, selected, 0, new_mat)


func test_apply_to_selected_faces_noop_null_material() -> void:
	var mesh := _make_mesh(1)
	mesh.material_slots.append(StandardMaterial3D.new())
	var selected: Array[int] = [0]
	MaterialAssignOperation.apply_to_selected_faces(mesh, selected, 0, null)
	assert_int(mesh.faces[0].material_index).is_equal(0)
	assert_int(mesh.material_slots.size()).is_equal(1)
