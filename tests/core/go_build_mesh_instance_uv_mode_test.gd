## Smoke tests for GoBuildMeshInstance auto UV mode routing.
@tool
extends GdUnitTestSuite

# Self-preloads — dependency order.
const _FACE_SCRIPT          := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MESH_SCRIPT          := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _SEL_MGR_SCRIPT       := preload("res://addons/go_build/core/selection_manager.gd")
const _MESH_INSTANCE_SCRIPT := preload("res://addons/go_build/core/go_build_mesh_instance.gd")


func _make_single_quad_mesh() -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [
		Vector3(0.0, 0.0, 0.0),
		Vector3(0.0, 0.0, 1.0),
		Vector3(1.0, 0.0, 1.0),
		Vector3(1.0, 0.0, 0.0),
	]
	var face := GoBuildFace.new()
	face.vertex_indices = [0, 1, 2, 3]
	mesh.faces = [face]
	return mesh


func _make_two_quad_mesh() -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [
		# left quad (x in [0..1])
		Vector3(0.0, 0.0, 0.0),
		Vector3(0.0, 0.0, 1.0),
		Vector3(1.0, 0.0, 1.0),
		Vector3(1.0, 0.0, 0.0),
		# right quad (x in [10..11])
		Vector3(10.0, 0.0, 0.0),
		Vector3(10.0, 0.0, 1.0),
		Vector3(11.0, 0.0, 1.0),
		Vector3(11.0, 0.0, 0.0),
	]
	var left := GoBuildFace.new()
	left.vertex_indices = [0, 1, 2, 3]
	var right := GoBuildFace.new()
	right.vertex_indices = [4, 5, 6, 7]
	mesh.faces = [left, right]
	return mesh


func test_needs_world_space_uv_refresh_false_when_global_mode_none() -> void:
	var node := GoBuildMeshInstance.new()
	auto_free(node)
	node.auto_uv_mode = GoBuildFace.UvMode.NONE
	node.go_build_mesh = _make_single_quad_mesh()
	assert_bool(node.needs_world_space_uv_refresh()).is_false()


func test_needs_world_space_uv_refresh_true_when_global_mode_box() -> void:
	var node := GoBuildMeshInstance.new()
	auto_free(node)
	node.auto_uv_mode = GoBuildFace.UvMode.BOX
	node.go_build_mesh = _make_single_quad_mesh()
	assert_bool(node.needs_world_space_uv_refresh()).is_true()


func test_needs_world_space_uv_refresh_false_when_global_planar_and_no_box_override() -> void:
	var node := GoBuildMeshInstance.new()
	auto_free(node)
	node.auto_uv_mode = GoBuildFace.UvMode.PLANAR
	node.go_build_mesh = _make_single_quad_mesh()
	node.go_build_mesh.faces[0].uv_projection_mode = GoBuildFace.UvMode.NONE
	assert_bool(node.needs_world_space_uv_refresh()).is_false()


func test_needs_world_space_uv_refresh_true_when_planar_global_has_box_override() -> void:
	var node := GoBuildMeshInstance.new()
	auto_free(node)
	node.auto_uv_mode = GoBuildFace.UvMode.PLANAR
	node.go_build_mesh = _make_single_quad_mesh()
	node.go_build_mesh.faces[0].uv_projection_mode = GoBuildFace.UvMode.BOX
	assert_bool(node.needs_world_space_uv_refresh()).is_true()


func test_apply_auto_uv_respects_face_override_vs_global_mode() -> void:
	var node := GoBuildMeshInstance.new()
	auto_free(node)
	node.auto_uv_mode = GoBuildFace.UvMode.NONE
	node.go_build_mesh = _make_two_quad_mesh()
	node.global_transform = Transform3D(Basis.IDENTITY, Vector3(5.0, 0.0, 7.0))

	# Global mode is BOX, but second face is explicitly PLANAR override.
	node.auto_uv_mode = GoBuildFace.UvMode.BOX
	node.go_build_mesh.faces[0].uv_projection_mode = GoBuildFace.UvMode.NONE
	node.go_build_mesh.faces[1].uv_projection_mode = GoBuildFace.UvMode.PLANAR
	node._apply_auto_uv()

	var box_uv0: Vector2 = node.go_build_mesh.faces[0].uvs[0]
	var planar_uv0: Vector2 = node.go_build_mesh.faces[1].uvs[0]

	# Face 0 (box/global) uses world-space transform: local (0,0,0) -> world (5,0,7) -> UV (5,-7)
	assert_float(box_uv0.x).is_equal_approx(5.0, 0.001)
	assert_float(box_uv0.y).is_equal_approx(-7.0, 0.001)

	# Face 1 (manual planar override) stays locally projected and rebased to (0,0).
	assert_float(planar_uv0.x).is_equal_approx(0.0, 0.001)
	assert_float(planar_uv0.y).is_equal_approx(0.0, 0.001)
