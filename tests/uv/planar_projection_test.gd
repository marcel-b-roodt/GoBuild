## Planar UV projection tests — GdUnit4
extends GdUnitTestSuite

const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _PLANAR_SCRIPT := preload("res://addons/go_build/uv/planar_projection.gd")


func _make_plus_y_rect(width: float = 2.0, depth: float = 3.0) -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [
		Vector3(0.0, 0.0, 0.0),
		Vector3(0.0, 0.0, depth),
		Vector3(width, 0.0, depth),
		Vector3(width, 0.0, 0.0),
	]
	var face := GoBuildFace.new()
	face.vertex_indices = [0, 1, 2, 3]
	mesh.faces.append(face)
	return mesh


func _make_plus_x_rect(height: float = 2.0, depth: float = 3.0) -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [
		Vector3(0.0, 0.0, 0.0),
		Vector3(0.0, height, 0.0),
		Vector3(0.0, height, depth),
		Vector3(0.0, 0.0, depth),
	]
	var face := GoBuildFace.new()
	face.vertex_indices = [0, 1, 2, 3]
	mesh.faces.append(face)
	return mesh


func test_planar_projection_matches_face_size_for_plus_y_face() -> void:
	var mesh := _make_plus_y_rect(2.0, 3.0)
	PlanarProjection.apply(mesh, [0], 1.0)
	var face: GoBuildFace = mesh.faces[0]
	assert_int(face.uvs.size()).is_equal(4)
	var min_u: float = INF
	var max_u: float = -INF
	var min_v: float = INF
	var max_v: float = -INF
	for uv: Vector2 in face.uvs:
		min_u = minf(min_u, uv.x)
		max_u = maxf(max_u, uv.x)
		min_v = minf(min_v, uv.y)
		max_v = maxf(max_v, uv.y)
	assert_float(min_u).is_equal_approx(0.0, 0.001)
	assert_float(min_v).is_equal_approx(0.0, 0.001)
	assert_float(max_u - min_u).is_equal_approx(2.0, 0.001)
	assert_float(max_v - min_v).is_equal_approx(3.0, 0.001)


func test_planar_projection_matches_face_size_for_plus_x_face() -> void:
	var mesh := _make_plus_x_rect(2.0, 3.0)
	PlanarProjection.apply(mesh, [0], 1.0)
	var face: GoBuildFace = mesh.faces[0]
	var min_u: float = INF
	var max_u: float = -INF
	var min_v: float = INF
	var max_v: float = -INF
	for uv: Vector2 in face.uvs:
		min_u = minf(min_u, uv.x)
		max_u = maxf(max_u, uv.x)
		min_v = minf(min_v, uv.y)
		max_v = maxf(max_v, uv.y)
	assert_float(max_u - min_u).is_equal_approx(3.0, 0.001)
	assert_float(max_v - min_v).is_equal_approx(2.0, 0.001)


func test_planar_projection_respects_units_per_tile() -> void:
	var mesh := _make_plus_y_rect(2.0, 3.0)
	PlanarProjection.apply(mesh, [0], 0.5)
	var face: GoBuildFace = mesh.faces[0]
	var min_u: float = INF
	var max_u: float = -INF
	var min_v: float = INF
	var max_v: float = -INF
	for uv: Vector2 in face.uvs:
		min_u = minf(min_u, uv.x)
		max_u = maxf(max_u, uv.x)
		min_v = minf(min_v, uv.y)
		max_v = maxf(max_v, uv.y)
	assert_float(max_u - min_u).is_equal_approx(4.0, 0.001)
	assert_float(max_v - min_v).is_equal_approx(6.0, 0.001)


func test_planar_projection_only_changes_selected_faces() -> void:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [
		Vector3(0.0, 0.0, 0.0),
		Vector3(0.0, 0.0, 1.0),
		Vector3(1.0, 0.0, 1.0),
		Vector3(1.0, 0.0, 0.0),
		Vector3(2.0, 0.0, 0.0),
		Vector3(2.0, 0.0, 1.0),
	]
	var left := GoBuildFace.new()
	left.vertex_indices = [0, 1, 2, 3]
	left.uvs = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	var right := GoBuildFace.new()
	right.vertex_indices = [3, 2, 5, 4]
	right.uvs = [
		Vector2(7.0, 7.0),
		Vector2(8.0, 7.0),
		Vector2(8.0, 8.0),
		Vector2(7.0, 8.0),
	]
	mesh.faces = [left, right]
	PlanarProjection.apply(mesh, [0], 1.0)
	var min_u: float = INF
	var max_u: float = -INF
	var min_v: float = INF
	var max_v: float = -INF
	for uv: Vector2 in mesh.faces[0].uvs:
		min_u = minf(min_u, uv.x)
		max_u = maxf(max_u, uv.x)
		min_v = minf(min_v, uv.y)
		max_v = maxf(max_v, uv.y)
	assert_float(max_u - min_u).is_equal_approx(1.0, 0.001)
	assert_float(max_v - min_v).is_equal_approx(1.0, 0.001)
	assert_float(mesh.faces[1].uvs[0].x).is_equal_approx(7.0, 0.001)
	assert_float(mesh.faces[1].uvs[0].y).is_equal_approx(7.0, 0.001)


func test_planar_projection_empty_selection_is_noop() -> void:
	var mesh := _make_plus_y_rect(2.0, 3.0)
	PlanarProjection.apply(mesh, [], 1.0)
	assert_int(mesh.faces[0].uvs.size()).is_equal(0)


func test_planar_projection_offset_shifts_all_uvs() -> void:
	# Same geometry; projection with offset (0.5, 0.25) should produce UVs
	# shifted by exactly that amount relative to the unshifted result.
	var mesh := _make_plus_y_rect(2.0, 3.0)
	var mesh2 := _make_plus_y_rect(2.0, 3.0)
	PlanarProjection.apply(mesh,  [0], 1.0)
	PlanarProjection.apply(mesh2, [0], 1.0, Vector2(0.5, 0.25))
	for i: int in 4:
		assert_float(mesh2.faces[0].uvs[i].x).is_equal_approx(
				mesh.faces[0].uvs[i].x + 0.5, 0.001)
		assert_float(mesh2.faces[0].uvs[i].y).is_equal_approx(
				mesh.faces[0].uvs[i].y + 0.25, 0.001)

