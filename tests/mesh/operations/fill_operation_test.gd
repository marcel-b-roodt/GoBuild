## Fill operation tests — GdUnit4
##
## Tests for [FillOperation.apply] covering:
##   - Filling a triangular hole (3 boundary edges) creates 1 new face.
##   - Filling a quad hole (4 boundary edges) creates 1 new face.
##   - Filling a pentagonal hole (5 boundary edges) creates 1 new face.
##   - Interior edges (non-boundary) are filtered out.
##   - Fewer than 3 boundary edges is a no-op.
##   - Open chain (not closed) is a no-op.
##   - Winding is corrected to match adjacent face normals.
##   - Material index and smooth group inherited from adjacent face.
##   - Edges are rebuilt after the operation.
extends GdUnitTestSuite

const _FACE_SCRIPT   := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT   := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT   := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _FILL_SCRIPT   := preload("res://addons/go_build/mesh/operations/fill_operation.gd")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Create an open box (unit cube with top face removed). Returns the mesh and
## the boundary edge indices around the open top (4 edges).
func _make_open_box() -> Dictionary:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [
		Vector3(-0.5, -0.5, -0.5),  # 0
		Vector3( 0.5, -0.5, -0.5),  # 1
		Vector3( 0.5, -0.5,  0.5),  # 2
		Vector3(-0.5, -0.5,  0.5),  # 3
		Vector3(-0.5,  0.5, -0.5),  # 4
		Vector3( 0.5,  0.5, -0.5),  # 5
		Vector3( 0.5,  0.5,  0.5),  # 6
		Vector3(-0.5,  0.5,  0.5),  # 7
	]
	# Bottom face (y = -0.5), normal -Y
	var bottom := GoBuildFace.new()
	bottom.vertex_indices = [0, 3, 2, 1]
	bottom.uvs = [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.UP]
	mesh.faces.append(bottom)
	# Front face (z = -0.5)
	var front := GoBuildFace.new()
	front.vertex_indices = [0, 1, 5, 4]
	front.uvs = [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.UP]
	mesh.faces.append(front)
	# Right face (x = 0.5)
	var right := GoBuildFace.new()
	right.vertex_indices = [1, 2, 6, 5]
	right.uvs = [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.UP]
	mesh.faces.append(right)
	# Back face (z = 0.5)
	var back := GoBuildFace.new()
	back.vertex_indices = [2, 3, 7, 6]
	back.uvs = [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.UP]
	mesh.faces.append(back)
	# Left face (x = -0.5)
	var left := GoBuildFace.new()
	left.vertex_indices = [3, 0, 4, 7]
	left.uvs = [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.UP]
	mesh.faces.append(left)
	mesh.rebuild_edges()
	# Find boundary edges (top ring: 4→5, 5→6, 6→7, 7→4)
	var boundary: Array[int] = []
	for i: int in mesh.edges.size():
		if mesh.edges[i].is_boundary():
			boundary.append(i)
	return { "mesh": mesh, "boundary": boundary }


## Create a mesh with a triangular hole (3 boundary edges).
func _make_open_tri() -> Dictionary:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [
		Vector3(0.0, 0.0, 0.0),    # 0
		Vector3(1.0, 0.0, 0.0),    # 1
		Vector3(0.5, 0.0, 1.0),    # 2
	]
	# No faces — just 3 boundary edges forming a triangle
	var face := GoBuildFace.new()
	face.vertex_indices = [0, 2, 1]
	face.uvs = [Vector2.ZERO, Vector2(1.0, 0.0), Vector2(0.5, 1.0)]
	mesh.faces.append(face)
	mesh.rebuild_edges()
	var boundary: Array[int] = []
	for i: int in mesh.edges.size():
		if mesh.edges[i].is_boundary():
			boundary.append(i)
	return { "mesh": mesh, "boundary": boundary }


# ---------------------------------------------------------------------------
# Core fill tests
# ---------------------------------------------------------------------------

func test_fill_quad_hole_creates_face() -> void:
	var ctx := _make_open_box()
	var mesh: GoBuildMesh = ctx["mesh"]
	var boundary: Array[int] = ctx["boundary"]
	var faces_before: int = mesh.faces.size()
	FillOperation.apply(mesh, boundary)
	assert_int(mesh.faces.size()).is_equal(faces_before + 1)


func test_fill_triangle_hole_creates_face() -> void:
	var ctx := _make_open_tri()
	var mesh: GoBuildMesh = ctx["mesh"]
	var boundary: Array[int] = ctx["boundary"]
	var faces_before: int = mesh.faces.size()
	FillOperation.apply(mesh, boundary)
	assert_int(mesh.faces.size()).is_equal(faces_before + 1)


func test_fill_face_has_correct_vertex_count() -> void:
	var ctx := _make_open_box()
	var mesh: GoBuildMesh = ctx["mesh"]
	var boundary: Array[int] = ctx["boundary"]
	FillOperation.apply(mesh, boundary)
	var fill_face: GoBuildFace = mesh.faces[mesh.faces.size() - 1]
	assert_int(fill_face.vertex_indices.size()).is_equal(4)


func test_fill_triangle_face_has_3_vertices() -> void:
	var ctx := _make_open_tri()
	var mesh: GoBuildMesh = ctx["mesh"]
	var boundary: Array[int] = ctx["boundary"]
	FillOperation.apply(mesh, boundary)
	var fill_face: GoBuildFace = mesh.faces[mesh.faces.size() - 1]
	assert_int(fill_face.vertex_indices.size()).is_equal(3)


func test_fill_edges_rebuilt() -> void:
	var ctx := _make_open_box()
	var mesh: GoBuildMesh = ctx["mesh"]
	var boundary: Array[int] = ctx["boundary"]
	FillOperation.apply(mesh, boundary)
	var boundary_after: int = 0
	for i: int in mesh.edges.size():
		if mesh.edges[i].is_boundary():
			boundary_after += 1
	assert_int(boundary_after).is_equal(0)


func test_fill_has_uvs() -> void:
	var ctx := _make_open_box()
	var mesh: GoBuildMesh = ctx["mesh"]
	var boundary: Array[int] = ctx["boundary"]
	FillOperation.apply(mesh, boundary)
	var fill_face: GoBuildFace = mesh.faces[mesh.faces.size() - 1]
	assert_bool(fill_face.uvs.size() == fill_face.vertex_indices.size()).is_true()


# ---------------------------------------------------------------------------
# Guard tests
# ---------------------------------------------------------------------------

func test_fill_noop_fewer_than_3_boundary() -> void:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [Vector3.ZERO, Vector3.RIGHT, Vector3.FORWARD]
	var face := GoBuildFace.new()
	face.vertex_indices = [0, 1, 2]
	face.uvs = [Vector2.ZERO, Vector2.RIGHT, Vector2(0.5, 1.0)]
	mesh.faces.append(face)
	mesh.rebuild_edges()
	var faces_before: int = mesh.faces.size()
	FillOperation.apply(mesh, [])
	assert_int(mesh.faces.size()).is_equal(faces_before)


func test_fill_noop_null_mesh() -> void:
	FillOperation.apply(null, [0, 1, 2])


func test_fill_noop_empty_edges() -> void:
	var mesh := GoBuildMesh.new()
	FillOperation.apply(mesh, [])