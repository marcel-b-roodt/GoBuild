## Subdivide operation tests — GdUnit4
##
## Tests for [SubdivideOperation.apply] covering:
##   - Vertex / face / edge counts after subdividing a single quad.
##   - Midpoint is shared between two co-selected adjacent quads.
##   - Sub-quad winding (normal direction consistent with original face).
##   - Material and smooth-group inheritance.
##   - Edge-case guards: empty selection, duplicate indices, out-of-range.
##
## Mesh conventions:
##   _make_plus_y_quad() — single unit quad, [0,1,2,3] in XZ plane.
##   _make_two_quads()   — two adjacent unit quads sharing edge v1↔v2.
extends GdUnitTestSuite

const _FACE_SCRIPT       := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT       := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT       := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _SUBDIVIDE_SCRIPT  := preload("res://addons/go_build/mesh/operations/subdivide_operation.gd")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

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
# Helper sanity
# ---------------------------------------------------------------------------

func test_plus_y_quad_starts_with_four_verts() -> void:
	var mesh := _make_plus_y_quad()
	assert_int(mesh.vertices.size()).is_equal(4)


func test_plus_y_quad_starts_with_one_face() -> void:
	var mesh := _make_plus_y_quad()
	assert_int(mesh.faces.size()).is_equal(1)


# ---------------------------------------------------------------------------
# Single-quad subdivision — vertex count
# ---------------------------------------------------------------------------

func test_subdivide_single_quad_adds_five_vertices() -> void:
	# 4 original + 4 edge midpoints + 1 centroid = 9.
	var mesh := _make_plus_y_quad()
	SubdivideOperation.apply(mesh, [0])
	assert_int(mesh.vertices.size()).is_equal(9)


# ---------------------------------------------------------------------------
# Single-quad subdivision — face count
# ---------------------------------------------------------------------------

func test_subdivide_single_quad_produces_four_faces() -> void:
	# Original face is replaced by 4 sub-quads.
	var mesh := _make_plus_y_quad()
	SubdivideOperation.apply(mesh, [0])
	assert_int(mesh.faces.size()).is_equal(4)


# ---------------------------------------------------------------------------
# Sub-face vertex count
# ---------------------------------------------------------------------------

func test_each_sub_face_has_four_vertices() -> void:
	var mesh := _make_plus_y_quad()
	SubdivideOperation.apply(mesh, [0])
	for face in mesh.faces:
		assert_int((face as GoBuildFace).vertex_indices.size()).is_equal(4)


# ---------------------------------------------------------------------------
# Centroid position
# ---------------------------------------------------------------------------

func test_centroid_vertex_is_at_mesh_centre() -> void:
	# For a unit quad (0,0,0)→(1,0,1) the centroid should be at (0.5,0,0.5).
	# The centroid is the last vertex added: index 8.
	var mesh := _make_plus_y_quad()
	SubdivideOperation.apply(mesh, [0])
	# The centroid is at index 8 (4 original + 4 midpoints).
	var c: Vector3 = mesh.vertices[8]
	assert_float(c.x).is_equal_approx(0.5, 0.001)
	assert_float(c.y).is_equal_approx(0.0, 0.001)
	assert_float(c.z).is_equal_approx(0.5, 0.001)


# ---------------------------------------------------------------------------
# Shared midpoint between two co-selected adjacent faces
# ---------------------------------------------------------------------------

func test_two_adjacent_selected_faces_share_midpoint_on_common_edge() -> void:
	# When both quads are subdivided the shared edge v1↔v2 should produce
	# exactly ONE midpoint vertex, not two.
	# New verts added: 7 edge midpoints (4 for face0 + 3 unique for face1)
	# + 2 centroids = 9 new verts.  Total = 6 + 9 = 15.
	var mesh := _make_two_quads()
	SubdivideOperation.apply(mesh, [0, 1])
	assert_int(mesh.vertices.size()).is_equal(15)


func test_two_adjacent_selected_faces_produce_eight_sub_faces() -> void:
	var mesh := _make_two_quads()
	SubdivideOperation.apply(mesh, [0, 1])
	assert_int(mesh.faces.size()).is_equal(8)


# ---------------------------------------------------------------------------
# Normal direction — consistent with original face
# ---------------------------------------------------------------------------

func test_sub_faces_have_consistent_normal_direction() -> void:
	var mesh := _make_plus_y_quad()
	# Capture original face normal sign before subdivision.
	var orig_ny: float = mesh.compute_face_normal(mesh.faces[0]).y
	SubdivideOperation.apply(mesh, [0])
	for face in mesh.faces:
		var n: Vector3 = mesh.compute_face_normal(face as GoBuildFace)
		# Each sub-face normal should have the same Y sign as the original.
		assert_bool(signf(n.y) == signf(orig_ny)).is_true()


# ---------------------------------------------------------------------------
# Material and smooth-group inheritance
# ---------------------------------------------------------------------------

func test_sub_faces_inherit_material_index() -> void:
	var mesh := _make_plus_y_quad()
	mesh.faces[0].material_index = 5
	SubdivideOperation.apply(mesh, [0])
	for face in mesh.faces:
		assert_int((face as GoBuildFace).material_index).is_equal(5)


func test_sub_faces_inherit_smooth_group() -> void:
	var mesh := _make_plus_y_quad()
	mesh.faces[0].smooth_group = 2
	SubdivideOperation.apply(mesh, [0])
	for face in mesh.faces:
		assert_int((face as GoBuildFace).smooth_group).is_equal(2)


# ---------------------------------------------------------------------------
# Sub-faces have UVs
# ---------------------------------------------------------------------------

func test_each_sub_face_has_four_uvs() -> void:
	var mesh := _make_plus_y_quad()
	SubdivideOperation.apply(mesh, [0])
	for face in mesh.faces:
		assert_int((face as GoBuildFace).uvs.size()).is_equal(4)


# ---------------------------------------------------------------------------
# Only selected faces are subdivided
# ---------------------------------------------------------------------------

func test_unselected_face_is_unchanged() -> void:
	# Subdivide only face 0; face 1 should remain a single quad with 4 verts.
	var mesh := _make_two_quads()
	SubdivideOperation.apply(mesh, [0])
	# Face at original index 1 is now at index 4 (face 0 was replaced + 3 appended).
	# Actually original face 1 is at index 1 since we only replaced face 0 → 1 face
	# + 3 appended = indices 0,1,2,3 where 0 is first sub-quad, 1..3 are the next
	# three, and the original face 1 is pushed to index... wait.
	# Phase 3: valid=[0], faces[0]=quads[0][0], append quads[0][1..3].
	# So face 1 (the unselected one) stays at index 1.
	# But after appending 3 more quads it's still at index 1.
	# Indices: 0=sub0, 1=original_face1(unchanged), 2=sub1, 3=sub2, 4=sub3.
	# Actually: faces[0] replaced with sub-quad, then sub-quads 1,2,3 appended.
	# mesh.faces = [sub0, original_face1, sub1, sub2, sub3].
	# original_face1 is now at index 1.
	assert_int(mesh.faces.size()).is_equal(5)
	var unchanged: GoBuildFace = mesh.faces[1]
	# Phase 4 stitching inserts the midpoint of the shared edge v1↔v2 (index 7)
	# into face 1 to avoid a T-junction, growing it from 4 to 5 vertices.
	assert_int(unchanged.vertex_indices.size()).is_equal(5)
	assert_int(unchanged.vertex_indices[0]).is_equal(1)
	assert_int(unchanged.vertex_indices[1]).is_equal(4)
	assert_int(unchanged.vertex_indices[2]).is_equal(5)
	assert_int(unchanged.vertex_indices[3]).is_equal(2)


# ---------------------------------------------------------------------------
# Edge-case guards
# ---------------------------------------------------------------------------

func test_empty_selection_is_noop() -> void:
	var mesh := _make_plus_y_quad()
	SubdivideOperation.apply(mesh, [])
	assert_int(mesh.vertices.size()).is_equal(4)
	assert_int(mesh.faces.size()).is_equal(1)


func test_out_of_range_index_is_skipped() -> void:
	var mesh := _make_plus_y_quad()
	SubdivideOperation.apply(mesh, [999])
	assert_int(mesh.vertices.size()).is_equal(4)
	assert_int(mesh.faces.size()).is_equal(1)


func test_duplicate_index_is_processed_once() -> void:
	# Passing the same face index twice should produce the same result as once.
	var mesh := _make_plus_y_quad()
	SubdivideOperation.apply(mesh, [0, 0])
	assert_int(mesh.vertices.size()).is_equal(9)
	assert_int(mesh.faces.size()).is_equal(4)
