## MeshImport tests — GdUnit4
##
## Tests for [MeshImport.from_array_mesh] covering:
##   - Null/empty input
##   - Single triangle surface (non-indexed, CCW from outside)
##   - Indexed quad surface (2 triangles)
##   - Multiple surfaces (material slots)
##   - Vertex colours preserved
##   - Winding convention: CCW input stays CCW, CW input reversed
##   - reverse_winding flag for re-importing GoBuild-baked meshes
extends GdUnitTestSuite

const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _IMPORT_SCRIPT := preload("res://addons/go_build/mesh/mesh_import.gd")


## Build a CCW triangle on XZ plane (standard Godot winding).
func _make_ccw_triangle_mesh() -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1),
	])
	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return arr_mesh


func _make_colored_triangle_mesh() -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1),
	])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([
		Color.RED, Color.GREEN, Color.BLUE,
	])
	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return arr_mesh


func _make_two_surface_mesh() -> ArrayMesh:
	var arr_mesh := ArrayMesh.new()

	var arrays0: Array = []
	arrays0.resize(Mesh.ARRAY_MAX)
	arrays0[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1),
	])
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays0)

	var arrays1: Array = []
	arrays1.resize(Mesh.ARRAY_MAX)
	arrays1[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(2, 0, 0), Vector3(3, 0, 0), Vector3(2, 0, 1),
	])
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays1)

	return arr_mesh


func _make_indexed_quad_mesh() -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0),
		Vector3(1, 0, 1), Vector3(0, 0, 1),
	])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([
		0, 1, 2,
		0, 2, 3,
	])
	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return arr_mesh


## Build a CW triangle (reversed from standard) to simulate GoBuild bake output.
func _make_cw_triangle_mesh() -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	# CW from outside: v0=(0,0,0), v1=(0,0,1), v2=(1,0,0)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 0),
	])
	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return arr_mesh


func _make_uv_triangle_mesh() -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1),
	])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
		Vector2(0, 1), Vector2(1, 1), Vector2(0, 0),
	])
	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return arr_mesh


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_import_null_mesh() -> void:
	var go_mesh: GoBuildMesh = MeshImport.from_array_mesh(null)
	assert_int(go_mesh.vertices.size()).is_equal(0)
	assert_int(go_mesh.faces.size()).is_equal(0)


func test_import_empty_mesh() -> void:
	var arr_mesh := ArrayMesh.new()
	var go_mesh: GoBuildMesh = MeshImport.from_array_mesh(arr_mesh)
	assert_int(go_mesh.vertices.size()).is_equal(0)
	assert_int(go_mesh.faces.size()).is_equal(0)


func test_import_single_triangle() -> void:
	var arr_mesh := _make_ccw_triangle_mesh()
	var go_mesh: GoBuildMesh = MeshImport.from_array_mesh(arr_mesh)
	assert_int(go_mesh.faces.size()).is_equal(1)
	assert_int(go_mesh.faces[0].vertex_indices.size()).is_equal(3)
	assert_int(go_mesh.vertices.size()).is_equal(3)


func test_import_preserves_vertex_positions() -> void:
	var arr_mesh := _make_ccw_triangle_mesh()
	var go_mesh: GoBuildMesh = MeshImport.from_array_mesh(arr_mesh)
	assert_bool(go_mesh.vertices.has(Vector3(0, 0, 0))).is_true()
	assert_bool(go_mesh.vertices.has(Vector3(1, 0, 0))).is_true()
	assert_bool(go_mesh.vertices.has(Vector3(0, 0, 1))).is_true()


func test_import_ccw_winding_preserved() -> void:
	# Standard Godot CCW triangle on XZ plane.
	# CCW from +Y: (0,0,0)→(1,0,0)→(0,0,1).
	# Newell normal should point +Y (outward).
	var arr_mesh := _make_ccw_triangle_mesh()
	var go_mesh: GoBuildMesh = MeshImport.from_array_mesh(arr_mesh)
	var face: GoBuildFace = go_mesh.faces[0]
	var normal := go_mesh.compute_face_normal(face)
	assert_float(normal.dot(Vector3.UP)).is_greater_than(0.9)


func test_import_cw_winding_reversed() -> void:
	# GoBuild-baked CW triangle.
	# CW from +Y: (0,0,0)→(0,0,1)→(1,0,0) — Newell would give -Y.
	# With reverse_winding=true, it should become CCW and normal should be +Y.
	var arr_mesh := _make_cw_triangle_mesh()
	var go_mesh: GoBuildMesh = MeshImport.from_array_mesh(arr_mesh, true)
	var face: GoBuildFace = go_mesh.faces[0]
	var normal := go_mesh.compute_face_normal(face)
	assert_float(normal.dot(Vector3.UP)).is_greater_than(0.9)


func test_import_cw_without_reverse_gives_inward_normal() -> void:
	# Same CW triangle imported without reverse — normal points -Y.
	var arr_mesh := _make_cw_triangle_mesh()
	var go_mesh: GoBuildMesh = MeshImport.from_array_mesh(arr_mesh, false)
	var face: GoBuildFace = go_mesh.faces[0]
	var normal := go_mesh.compute_face_normal(face)
	# Newell normal should point DOWN (-Y) for CW winding.
	assert_float(normal.dot(Vector3.DOWN)).is_greater_than(0.9)


func test_import_vertex_colors() -> void:
	var arr_mesh := _make_colored_triangle_mesh()
	var go_mesh: GoBuildMesh = MeshImport.from_array_mesh(arr_mesh)
	assert_int(go_mesh.vertex_colors.size()).is_equal(3)
	assert_color_equal(go_mesh.vertex_colors[0], Color.RED)
	assert_color_equal(go_mesh.vertex_colors[1], Color.GREEN)
	assert_color_equal(go_mesh.vertex_colors[2], Color.BLUE)


func test_import_no_colors_when_missing() -> void:
	var arr_mesh := _make_ccw_triangle_mesh()
	var go_mesh: GoBuildMesh = MeshImport.from_array_mesh(arr_mesh)
	assert_int(go_mesh.vertex_colors.size()).is_equal(0)


func test_import_two_surfaces_creates_two_material_slots() -> void:
	var arr_mesh := _make_two_surface_mesh()
	var go_mesh: GoBuildMesh = MeshImport.from_array_mesh(arr_mesh)
	assert_int(go_mesh.material_slots.size()).is_equal(2)
	assert_int(go_mesh.faces.size()).is_equal(2)
	assert_int(go_mesh.faces[0].material_index).is_equal(0)
	assert_int(go_mesh.faces[1].material_index).is_equal(1)


func test_import_indexed_mesh() -> void:
	var arr_mesh := _make_indexed_quad_mesh()
	var go_mesh: GoBuildMesh = MeshImport.from_array_mesh(arr_mesh)
	assert_int(go_mesh.faces.size()).is_equal(2)
	assert_int(go_mesh.vertices.size()).is_equal(4)


func test_import_edges_rebuilt() -> void:
	var arr_mesh := _make_ccw_triangle_mesh()
	var go_mesh: GoBuildMesh = MeshImport.from_array_mesh(arr_mesh)
	assert_int(go_mesh.edges.size()).is_equal(3)


func test_import_uvs_preserved() -> void:
	var arr_mesh := _make_uv_triangle_mesh()
	var go_mesh: GoBuildMesh = MeshImport.from_array_mesh(arr_mesh)
	assert_int(go_mesh.faces[0].uvs.size()).is_equal(3)
	# UVs should match input order (CCW, no reversal).
	assert_vector2(go_mesh.faces[0].uvs[0]).is_equal(Vector2(0, 1))
	assert_vector2(go_mesh.faces[0].uvs[1]).is_equal(Vector2(1, 1))
	assert_vector2(go_mesh.faces[0].uvs[2]).is_equal(Vector2(0, 0))


func test_import_uvs_reversed_with_cw() -> void:
	# CW input with reverse_winding=true — UVs should also be reversed.
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	# CW winding: (0,0,0)→(0,0,1)→(1,0,0)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 0),
	])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
		Vector2(0, 1), Vector2(0, 0), Vector2(1, 1),
	])
	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var go_mesh: GoBuildMesh = MeshImport.from_array_mesh(arr_mesh, true)
	assert_int(go_mesh.faces[0].uvs.size()).is_equal(3)
	# After reversal: index 2→0, index 1 stays, index 0→2
	assert_vector2(go_mesh.faces[0].uvs[0]).is_equal(Vector2(1, 1))
	assert_vector2(go_mesh.faces[0].uvs[1]).is_equal(Vector2(0, 0))
	assert_vector2(go_mesh.faces[0].uvs[2]).is_equal(Vector2(0, 1))


func test_import_smooth_group_is_zero() -> void:
	var arr_mesh := _make_ccw_triangle_mesh()
	var go_mesh: GoBuildMesh = MeshImport.from_array_mesh(arr_mesh)
	assert_int(go_mesh.faces[0].smooth_group).is_equal(0)


func assert_color_equal(actual: Color, expected: Color, delta: float = 0.001) -> void:
	assert_float(actual.r).is_equal_approx(expected.r, delta)
	assert_float(actual.g).is_equal_approx(expected.g, delta)
	assert_float(actual.b).is_equal_approx(expected.b, delta)
	assert_float(actual.a).is_equal_approx(expected.a, delta)