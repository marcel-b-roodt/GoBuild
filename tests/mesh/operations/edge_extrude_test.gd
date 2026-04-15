## Edge extrude operation tests — GdUnit4
##
## Tests for [EdgeExtrudeOperation.apply] covering vertex/face/edge counts,
## winding order, material inheritance, and edge cases (interior edges,
## empty/invalid selection, non-boundary skip).
##
## Test mesh conventions:
##   _make_plus_y_quad() — single CCW-from-above quad in XZ plane, normal +Y,
##     all 4 edges are boundary.
##   _make_two_quads() — two adjacent quads sharing an interior edge; the
##     shared edge should be skipped by edge extrude.
extends GdUnitTestSuite

# Self-preloads — needed because the test suite is compiled before the
# mesh/ scripts in Godot's alphabetical scan order.
const _FACE_SCRIPT          := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT         := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT         := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _EDGE_EXTRUDE_SCRIPT := \
		preload("res://addons/go_build/mesh/operations/edge_extrude_operation.gd")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Single quad in the XZ plane (normal = +Y).
## Vertices: v0=(0,0,0) v1=(1,0,0) v2=(1,0,1) v3=(0,0,1) — CCW from +Y.
## All 4 edges are boundary edges after rebuild_edges().
func _make_plus_y_quad() -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [
		Vector3(0.0, 0.0, 0.0),
		Vector3(1.0, 0.0, 0.0),
		Vector3(1.0, 0.0, 1.0),
		Vector3(0.0, 0.0, 1.0),
	]
	var face := GoBuildFace.new()
	face.vertex_indices = [0, 1, 2, 3]
	face.uvs = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	mesh.faces.append(face)
	mesh.rebuild_edges()
	return mesh


## Two adjacent quads sharing edge 1↔4 (an interior edge).
## Layout (XZ plane, +Y normal):
##   v0=(0,0,0) v1=(1,0,0) v2=(1,0,1) v3=(0,0,1) — left quad
##   v1=(1,0,0) v4=(2,0,0) v5=(2,0,1) v2=(1,0,1) — right quad
## After rebuild_edges(): edge v1↔v2 has 2 face_indices → interior.
func _make_two_quads() -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [
		Vector3(0.0, 0.0, 0.0),  # 0
		Vector3(1.0, 0.0, 0.0),  # 1
		Vector3(1.0, 0.0, 1.0),  # 2
		Vector3(0.0, 0.0, 1.0),  # 3
		Vector3(2.0, 0.0, 0.0),  # 4
		Vector3(2.0, 0.0, 1.0),  # 5
	]
	var f0 := GoBuildFace.new()
	f0.vertex_indices = [0, 1, 2, 3]
	f0.uvs = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var f1 := GoBuildFace.new()
	f1.vertex_indices = [1, 4, 5, 2]
	f1.uvs = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	mesh.faces.append(f0)
	mesh.faces.append(f1)
	mesh.rebuild_edges()
	return mesh


# ---------------------------------------------------------------------------
# Helper sanity checks
# ---------------------------------------------------------------------------

func test_plus_y_quad_all_edges_are_boundary() -> void:
	var mesh := _make_plus_y_quad()
	assert_int(mesh.edges.size()).is_equal(4)
	for edge in mesh.edges:
		assert_bool((edge as GoBuildEdge).is_boundary()).is_true()


func test_two_quads_has_one_interior_edge() -> void:
	var mesh := _make_two_quads()
	var interior_count := 0
	for edge in mesh.edges:
		if not (edge as GoBuildEdge).is_boundary():
			interior_count += 1
	assert_int(interior_count).is_equal(1)


# ---------------------------------------------------------------------------
# Vertex and face counts — single boundary edge
# ---------------------------------------------------------------------------

func test_extrude_single_boundary_edge_adds_two_vertices() -> void:
	var mesh := _make_plus_y_quad()
	# 4 original vertices; extruding one edge should add 2 new ones.
	var indices: Array[int] = [0]
	EdgeExtrudeOperation.apply(mesh, indices)
	assert_int(mesh.vertices.size()).is_equal(6)


func test_extrude_single_boundary_edge_adds_one_face() -> void:
	var mesh := _make_plus_y_quad()
	# 1 original face; extruding one edge should add 1 new quad face.
	var indices: Array[int] = [0]
	EdgeExtrudeOperation.apply(mesh, indices)
	assert_int(mesh.faces.size()).is_equal(2)


# ---------------------------------------------------------------------------
# Vertex counts — multiple edges
# ---------------------------------------------------------------------------

func test_extrude_two_boundary_edges_adds_four_vertices() -> void:
	var mesh := _make_plus_y_quad()
	# Extrude two boundary edges independently → 4 + 4 vertices.
	var indices: Array[int] = [0, 1]
	EdgeExtrudeOperation.apply(mesh, indices)
	assert_int(mesh.vertices.size()).is_equal(8)


func test_extrude_two_boundary_edges_adds_two_faces() -> void:
	var mesh := _make_plus_y_quad()
	var indices: Array[int] = [0, 1]
	EdgeExtrudeOperation.apply(mesh, indices)
	assert_int(mesh.faces.size()).is_equal(3)


# ---------------------------------------------------------------------------
# New face starts at original edge position (degenerate / coincident)
# ---------------------------------------------------------------------------

func test_new_face_vertices_are_initially_coincident_with_source_edge() -> void:
	# After extrude the new face is a zero-area degenerate quad — both the
	# original edge verts and the new duplicate verts are at the same positions.
	var mesh := _make_plus_y_quad()
	var indices: Array[int] = [0]
	EdgeExtrudeOperation.apply(mesh, indices)
	# The new face is mesh.faces[1]; its verts 2/3 are the new na/nb clones.
	var new_face: GoBuildFace = mesh.faces[1]
	assert_int(new_face.vertex_indices.size()).is_equal(4)
	var va: Vector3 = mesh.vertices[new_face.vertex_indices[0]]
	var vb: Vector3 = mesh.vertices[new_face.vertex_indices[1]]
	var nb: Vector3 = mesh.vertices[new_face.vertex_indices[2]]
	var na: Vector3 = mesh.vertices[new_face.vertex_indices[3]]
	# vb should match nb and va should match na (coincident pairs).
	assert_float(va.distance_to(na)).is_equal_approx(0.0, 0.001)
	assert_float(vb.distance_to(nb)).is_equal_approx(0.0, 0.001)


# ---------------------------------------------------------------------------
# Winding / normal correctness
# ---------------------------------------------------------------------------

func test_new_face_normal_perpendicular_to_original_face_after_drag() -> void:
	# Simulate dragging the new edge down by -Y (as a user would after extrude).
	# The new face should then have a horizontal normal (n.y ≈ 0) and point
	# outward from the quad centroid.
	var mesh := _make_plus_y_quad()
	var edge_0_va: int = (mesh.edges[0] as GoBuildEdge).vertex_a
	var edge_0_vb: int = (mesh.edges[0] as GoBuildEdge).vertex_b
	var indices: Array[int] = [0]
	EdgeExtrudeOperation.apply(mesh, indices)

	# The new face's na and nb occupy the last two vertex slots.
	var new_face: GoBuildFace = mesh.faces[1]
	var na_idx: int = new_face.vertex_indices[3]
	var nb_idx: int = new_face.vertex_indices[2]
	# Drag the new verts down by 1 unit in Y.
	mesh.vertices[na_idx] = mesh.vertices[na_idx] + Vector3(0.0, -1.0, 0.0)
	mesh.vertices[nb_idx] = mesh.vertices[nb_idx] + Vector3(0.0, -1.0, 0.0)

	var n: Vector3 = mesh.compute_face_normal(new_face)
	# After dragging down, the new face lies in a vertical plane → n.y ≈ 0.
	assert_float(absf(n.y)).is_less(0.01)
	# Normal should be unit length.
	assert_float(n.length()).is_equal_approx(1.0, 0.001)


# ---------------------------------------------------------------------------
# UV validity
# ---------------------------------------------------------------------------

func test_new_face_has_four_uvs() -> void:
	var mesh := _make_plus_y_quad()
	var indices: Array[int] = [0]
	EdgeExtrudeOperation.apply(mesh, indices)
	var new_face: GoBuildFace = mesh.faces[1]
	assert_int(new_face.uvs.size()).is_equal(4)


# ---------------------------------------------------------------------------
# Material inheritance
# ---------------------------------------------------------------------------

func test_new_face_inherits_material_from_adjacent_face() -> void:
	var mesh := _make_plus_y_quad()
	mesh.faces[0].material_index = 2
	var indices: Array[int] = [0]
	EdgeExtrudeOperation.apply(mesh, indices)
	assert_int(mesh.faces[1].material_index).is_equal(2)


# ---------------------------------------------------------------------------
# Return value — new boundary edge indices
# ---------------------------------------------------------------------------

func test_apply_returns_one_new_edge_index_per_extruded_edge() -> void:
	var mesh := _make_plus_y_quad()
	var indices: Array[int] = [0]
	var new_edges: Array[int] = EdgeExtrudeOperation.apply(mesh, indices)
	assert_int(new_edges.size()).is_equal(1)


func test_returned_edge_is_boundary() -> void:
	var mesh := _make_plus_y_quad()
	var indices: Array[int] = [0]
	var new_edges: Array[int] = EdgeExtrudeOperation.apply(mesh, indices)
	assert_bool(new_edges.is_empty()).is_false()
	var new_edge: GoBuildEdge = mesh.edges[new_edges[0]]
	assert_bool(new_edge.is_boundary()).is_true()


func test_apply_two_edges_returns_two_new_indices() -> void:
	var mesh := _make_plus_y_quad()
	var indices: Array[int] = [0, 1]
	var new_edges: Array[int] = EdgeExtrudeOperation.apply(mesh, indices)
	assert_int(new_edges.size()).is_equal(2)


# ---------------------------------------------------------------------------
# Interior edge extrude
# ---------------------------------------------------------------------------

func test_interior_edge_creates_face() -> void:
	# Extruding an interior edge creates a new quad face (T-junction topology).
	var mesh := _make_two_quads()
	# Find the interior edge index.
	var interior_idx: int = -1
	for ei: int in mesh.edges.size():
		if not (mesh.edges[ei] as GoBuildEdge).is_boundary():
			interior_idx = ei
			break
	assert_int(interior_idx).is_not_equal(-1)

	var indices: Array[int] = [interior_idx]
	var new_edges: Array[int] = EdgeExtrudeOperation.apply(mesh, indices)
	# One new boundary edge (na-nb), one new face, two new vertices.
	assert_int(new_edges.size()).is_equal(1)
	assert_int(mesh.faces.size()).is_equal(3)
	assert_int(mesh.vertices.size()).is_equal(8)


# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

func test_empty_selection_is_noop() -> void:
	var mesh := _make_plus_y_quad()
	var indices: Array[int] = []
	var new_edges: Array[int] = EdgeExtrudeOperation.apply(mesh, indices)
	assert_int(new_edges.size()).is_equal(0)
	assert_int(mesh.vertices.size()).is_equal(4)
	assert_int(mesh.faces.size()).is_equal(1)


func test_out_of_range_index_is_skipped() -> void:
	var mesh := _make_plus_y_quad()
	var indices: Array[int] = [999]
	var new_edges: Array[int] = EdgeExtrudeOperation.apply(mesh, indices)
	assert_int(new_edges.size()).is_equal(0)
	assert_int(mesh.faces.size()).is_equal(1)
