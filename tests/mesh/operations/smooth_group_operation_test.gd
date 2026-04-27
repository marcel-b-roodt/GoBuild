## SmoothGroupOperation tests — GdUnit4
extends GdUnitTestSuite

const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _OP_SCRIPT   := preload("res://addons/go_build/mesh/operations/smooth_group_operation.gd")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Build a simple mesh with [param face_count] triangles.
func _make_mesh(face_count: int) -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	for fi: int in face_count:
		var base: int = fi * 3
		mesh.vertices.append_array([
			Vector3(float(fi), 0.0, 0.0),
			Vector3(float(fi), 1.0, 0.0),
			Vector3(float(fi), 0.0, 1.0),
		])
		var face := GoBuildFace.new()
		face.vertex_indices = [base, base + 1, base + 2]
		face.uvs = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
		face.smooth_group = 0
		mesh.faces.append(face)
	return mesh


# ---------------------------------------------------------------------------
# Basic assignment
# ---------------------------------------------------------------------------

func test_apply_sets_smooth_group_on_selected_faces() -> void:
	var mesh := _make_mesh(3)
	var indices: Array[int] = [0, 2]
	SmoothGroupOperation.apply(mesh, indices, 1)
	assert_int(mesh.faces[0].smooth_group).is_equal(1)
	assert_int(mesh.faces[1].smooth_group).is_equal(0)  # untouched
	assert_int(mesh.faces[2].smooth_group).is_equal(1)


func test_apply_flat_shading_sets_group_to_zero() -> void:
	var mesh := _make_mesh(2)
	mesh.faces[0].smooth_group = 3
	mesh.faces[1].smooth_group = 3
	var indices: Array[int] = [0, 1]
	SmoothGroupOperation.apply(mesh, indices, 0)
	assert_int(mesh.faces[0].smooth_group).is_equal(0)
	assert_int(mesh.faces[1].smooth_group).is_equal(0)


func test_apply_does_not_modify_unselected_faces() -> void:
	var mesh := _make_mesh(4)
	for i: int in 4:
		mesh.faces[i].smooth_group = i + 10
	SmoothGroupOperation.apply(mesh, [1], 99)
	assert_int(mesh.faces[0].smooth_group).is_equal(10)
	assert_int(mesh.faces[1].smooth_group).is_equal(99)
	assert_int(mesh.faces[2].smooth_group).is_equal(12)
	assert_int(mesh.faces[3].smooth_group).is_equal(13)


func test_apply_noop_for_empty_face_indices() -> void:
	var mesh := _make_mesh(2)
	mesh.faces[0].smooth_group = 5
	mesh.faces[1].smooth_group = 5
	var indices: Array[int] = []
	SmoothGroupOperation.apply(mesh, indices, 99)
	assert_int(mesh.faces[0].smooth_group).is_equal(5)
	assert_int(mesh.faces[1].smooth_group).is_equal(5)


func test_apply_noop_for_null_mesh() -> void:
	# Must not crash.
	var indices: Array[int] = [0]
	SmoothGroupOperation.apply(null, indices, 1)


func test_apply_skips_negative_face_index() -> void:
	var mesh := _make_mesh(2)
	mesh.faces[0].smooth_group = 0
	mesh.faces[1].smooth_group = 0
	var indices: Array[int] = [-1, 1]
	SmoothGroupOperation.apply(mesh, indices, 7)
	# Only face 1 should be changed; face 0 and the negative index are skipped.
	assert_int(mesh.faces[0].smooth_group).is_equal(0)
	assert_int(mesh.faces[1].smooth_group).is_equal(7)


func test_apply_skips_out_of_range_face_index() -> void:
	var mesh := _make_mesh(1)
	mesh.faces[0].smooth_group = 0
	var indices: Array[int] = [0, 999]
	SmoothGroupOperation.apply(mesh, indices, 2)
	assert_int(mesh.faces[0].smooth_group).is_equal(2)
	# No crash — 999 was silently skipped.


func test_apply_multiple_distinct_groups_on_same_mesh() -> void:
	var mesh := _make_mesh(4)
	SmoothGroupOperation.apply(mesh, [0, 1], 1)
	SmoothGroupOperation.apply(mesh, [2, 3], 2)
	assert_int(mesh.faces[0].smooth_group).is_equal(1)
	assert_int(mesh.faces[1].smooth_group).is_equal(1)
	assert_int(mesh.faces[2].smooth_group).is_equal(2)
	assert_int(mesh.faces[3].smooth_group).is_equal(2)


func test_apply_overwrites_existing_non_zero_group() -> void:
	var mesh := _make_mesh(1)
	mesh.faces[0].smooth_group = 5
	var indices: Array[int] = [0]
	SmoothGroupOperation.apply(mesh, indices, 3)
	assert_int(mesh.faces[0].smooth_group).is_equal(3)
