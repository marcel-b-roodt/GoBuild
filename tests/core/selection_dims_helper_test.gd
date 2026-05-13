## Unit tests for [SelectionDimsHelper].
##
## All tests are pure-logic: no scene tree required.
## Run via the GdUnit4 panel in the Godot editor.
@tool
extends GdUnitTestSuite

# Self-preloads — dependency order.
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _SEL_MGR_SCRIPT := preload("res://addons/go_build/core/selection_manager.gd")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_mesh_with_verts(verts: Array[Vector3]) -> GoBuildMesh:
	var m := GoBuildMesh.new()
	m.vertices = verts
	return m


## Build a mesh with one quad face on the XZ plane (Y = 0, width × depth).
func _make_xz_quad(w: float, d: float) -> GoBuildMesh:
	var m := GoBuildMesh.new()
	m.vertices = [
		Vector3(0, 0, 0),
		Vector3(w, 0, 0),
		Vector3(w, 0, d),
		Vector3(0, 0, d),
	]
	var f := GoBuildFace.new()
	f.vertex_indices = [0, 1, 2, 3]
	f.uvs = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	m.faces.append(f)
	return m


## Build a mesh with one quad face on the XY plane (Z = 0).
func _make_xy_quad(w: float, h: float) -> GoBuildMesh:
	var m := GoBuildMesh.new()
	m.vertices = [
		Vector3(0, 0, 0),
		Vector3(w, 0, 0),
		Vector3(w, h, 0),
		Vector3(0, h, 0),
	]
	var f := GoBuildFace.new()
	f.vertex_indices = [0, 1, 2, 3]
	f.uvs = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	m.faces.append(f)
	return m


## Build a GoBuildEdge connecting two vertex indices.
func _make_edge(a: int, b: int) -> GoBuildEdge:
	var e := GoBuildEdge.new()
	e.vertex_a = a
	e.vertex_b = b
	return e


# ---------------------------------------------------------------------------
# fmt_m
# ---------------------------------------------------------------------------

func test_fmt_m_whole_number() -> void:
	assert_str(SelectionDimsHelper.fmt_m(1.0)).is_equal("1m")


func test_fmt_m_one_decimal() -> void:
	assert_str(SelectionDimsHelper.fmt_m(1.5)).is_equal("1.5m")


func test_fmt_m_two_decimals() -> void:
	assert_str(SelectionDimsHelper.fmt_m(1.25)).is_equal("1.25m")


func test_fmt_m_three_decimals() -> void:
	assert_str(SelectionDimsHelper.fmt_m(1.234)).is_equal("1.234m")


func test_fmt_m_strips_trailing_zeros() -> void:
	assert_str(SelectionDimsHelper.fmt_m(2.100)).is_equal("2.1m")


func test_fmt_m_zero() -> void:
	assert_str(SelectionDimsHelper.fmt_m(0.0)).is_equal("0m")


func test_fmt_m_negative() -> void:
	assert_str(SelectionDimsHelper.fmt_m(-0.5)).is_equal("-0.5m")


func test_fmt_m_negative_whole() -> void:
	assert_str(SelectionDimsHelper.fmt_m(-2.0)).is_equal("-2m")


# ---------------------------------------------------------------------------
# bbox_extents
# ---------------------------------------------------------------------------

func test_bbox_extents_unit_cube_verts() -> void:
	var m := _make_mesh_with_verts([
		Vector3(0, 0, 0), Vector3(1, 0, 0),
		Vector3(1, 1, 0), Vector3(0, 1, 0),
		Vector3(0, 0, 1), Vector3(1, 0, 1),
		Vector3(1, 1, 1), Vector3(0, 1, 1),
	])
	var idxs: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]
	var s: Vector3 = SelectionDimsHelper.bbox_extents(m, idxs, Transform3D.IDENTITY)
	assert_float(s.x).is_equal_approx(1.0, 0.0001)
	assert_float(s.y).is_equal_approx(1.0, 0.0001)
	assert_float(s.z).is_equal_approx(1.0, 0.0001)


func test_bbox_extents_identity_transform_does_not_scale() -> void:
	var m := _make_mesh_with_verts([Vector3(0, 0, 0), Vector3(3, 2, 1)])
	var idxs: Array[int] = [0, 1]
	var s: Vector3 = SelectionDimsHelper.bbox_extents(m, idxs, Transform3D.IDENTITY)
	assert_float(s.x).is_equal_approx(3.0, 0.0001)
	assert_float(s.y).is_equal_approx(2.0, 0.0001)
	assert_float(s.z).is_equal_approx(1.0, 0.0001)


func test_bbox_extents_applies_translation() -> void:
	# Translate by (10,0,0) — extents should be unchanged, but the computed
	# AABB shifts. bbox_extents returns size, not position, so result stays (3,2,1).
	var m := _make_mesh_with_verts([Vector3(0, 0, 0), Vector3(3, 2, 1)])
	var idxs: Array[int] = [0, 1]
	var xform := Transform3D(Basis.IDENTITY, Vector3(10, 0, 0))
	var s: Vector3 = SelectionDimsHelper.bbox_extents(m, idxs, xform)
	assert_float(s.x).is_equal_approx(3.0, 0.0001)


# ---------------------------------------------------------------------------
# bbox_text
# ---------------------------------------------------------------------------

func test_bbox_text_format() -> void:
	var m := _make_mesh_with_verts([Vector3(0, 0, 0), Vector3(2, 1, 0.5)])
	var idxs: Array[int] = [0, 1]
	var t: String = SelectionDimsHelper.bbox_text(m, idxs, Transform3D.IDENTITY)
	assert_str(t).is_equal("W: 2m  H: 1m  D: 0.5m")


func test_bbox_text_unit_cube() -> void:
	var m := _make_mesh_with_verts([
		Vector3(0, 0, 0), Vector3(1, 0, 0),
		Vector3(1, 1, 0), Vector3(0, 1, 0),
		Vector3(0, 0, 1), Vector3(1, 0, 1),
		Vector3(1, 1, 1), Vector3(0, 1, 1),
	])
	var idxs: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]
	var t: String = SelectionDimsHelper.bbox_text(m, idxs, Transform3D.IDENTITY)
	assert_str(t).is_equal("W: 1m  H: 1m  D: 1m")


# ---------------------------------------------------------------------------
# single_face_dims_text
# ---------------------------------------------------------------------------

func test_single_face_xz_plane_shows_only_w_h() -> void:
	# XZ quad (Y is flat) — expect W and H, no depth axis.
	var m := _make_xz_quad(2.0, 1.5)
	var t: String = SelectionDimsHelper.single_face_dims_text(m, 0, Transform3D.IDENTITY)
	assert_str(t).is_equal("W: 2m  H: 1.5m")


func test_single_face_xy_plane_shows_only_w_h() -> void:
	# XY quad (Z is flat) — expect W and H, no depth axis.
	var m := _make_xy_quad(3.0, 1.0)
	var t: String = SelectionDimsHelper.single_face_dims_text(m, 0, Transform3D.IDENTITY)
	assert_str(t).is_equal("W: 3m  H: 1m")


func test_single_face_w_is_always_larger_than_h() -> void:
	# Tall portrait XZ quad: depth > width. W should still be the larger extent.
	var m := _make_xz_quad(1.0, 4.0)
	var t: String = SelectionDimsHelper.single_face_dims_text(m, 0, Transform3D.IDENTITY)
	assert_str(t).is_equal("W: 4m  H: 1m")


func test_single_face_square_quad() -> void:
	var m := _make_xy_quad(2.0, 2.0)
	var t: String = SelectionDimsHelper.single_face_dims_text(m, 0, Transform3D.IDENTITY)
	assert_str(t).is_equal("W: 2m  H: 2m")


# ---------------------------------------------------------------------------
# build — vertex mode
# ---------------------------------------------------------------------------

func test_build_vertex_empty_selection_returns_empty() -> void:
	var m := _make_mesh_with_verts([Vector3(0, 0, 0)])
	var sel := SelectionManager.new()
	sel.set_mode(SelectionManager.Mode.VERTEX)
	assert_str(SelectionDimsHelper.build(m, sel, Transform3D.IDENTITY)).is_equal("")


func test_build_single_vertex_shows_position() -> void:
	var m := _make_mesh_with_verts([Vector3(1.0, 2.0, 3.0)])
	var sel := SelectionManager.new()
	sel.set_mode(SelectionManager.Mode.VERTEX)
	sel.select_vertex(0)
	var t: String = SelectionDimsHelper.build(m, sel, Transform3D.IDENTITY)
	assert_str(t).is_equal("X: 1m  Y: 2m  Z: 3m")


func test_build_two_vertices_shows_deltas_and_distance() -> void:
	var m := _make_mesh_with_verts([Vector3(0, 0, 0), Vector3(3, 4, 0)])
	var sel := SelectionManager.new()
	sel.set_mode(SelectionManager.Mode.VERTEX)
	sel.select_vertex(0)
	sel.select_vertex(1)
	var t: String = SelectionDimsHelper.build(m, sel, Transform3D.IDENTITY)
	# Distance = 5 (3-4-5 triangle).
	assert_str(t).is_equal("X: 3m  Y: 4m  Z: 0m  (5m)")


func test_build_three_plus_vertices_shows_bbox() -> void:
	var m := _make_mesh_with_verts([
		Vector3(0, 0, 0), Vector3(2, 0, 0),
		Vector3(2, 1, 0), Vector3(0, 1, 0),
	])
	var sel := SelectionManager.new()
	sel.set_mode(SelectionManager.Mode.VERTEX)
	for i: int in range(4):
		sel.select_vertex(i)
	var t: String = SelectionDimsHelper.build(m, sel, Transform3D.IDENTITY)
	assert_str(t).is_equal("W: 2m  H: 1m  D: 0m")


func test_build_object_mode_returns_empty() -> void:
	var m := _make_mesh_with_verts([Vector3(0, 0, 0)])
	var sel := SelectionManager.new()
	# Default mode is OBJECT.
	assert_str(SelectionDimsHelper.build(m, sel, Transform3D.IDENTITY)).is_equal("")


# ---------------------------------------------------------------------------
# build — edge mode
# ---------------------------------------------------------------------------

func test_build_single_edge_shows_length() -> void:
	var m := _make_mesh_with_verts([Vector3(0, 0, 0), Vector3(3, 4, 0)])
	m.edges.append(_make_edge(0, 1))
	var sel := SelectionManager.new()
	sel.set_mode(SelectionManager.Mode.EDGE)
	sel.select_edge(0)
	var t: String = SelectionDimsHelper.build(m, sel, Transform3D.IDENTITY)
	assert_str(t).is_equal("L: 5m")


func test_build_multiple_edges_shows_bbox() -> void:
	# Two axis-aligned edges forming an L: (0,0,0)→(1,0,0) and (0,0,0)→(0,1,0).
	var m := _make_mesh_with_verts([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0),
	])
	m.edges.append(_make_edge(0, 1))
	m.edges.append(_make_edge(0, 2))
	var sel := SelectionManager.new()
	sel.set_mode(SelectionManager.Mode.EDGE)
	sel.select_edge(0)
	sel.select_edge(1)
	var t: String = SelectionDimsHelper.build(m, sel, Transform3D.IDENTITY)
	assert_str(t).is_equal("W: 1m  H: 1m  D: 0m")


# ---------------------------------------------------------------------------
# build — face mode
# ---------------------------------------------------------------------------

func test_build_single_face_shows_wh_only() -> void:
	var m := _make_xy_quad(2.0, 1.0)
	var sel := SelectionManager.new()
	sel.set_mode(SelectionManager.Mode.FACE)
	sel.select_face(0)
	var t: String = SelectionDimsHelper.build(m, sel, Transform3D.IDENTITY)
	assert_str(t).is_equal("W: 2m  H: 1m")


func test_build_multiple_faces_shows_bbox() -> void:
	# Two side-by-side 1×1 XY quads giving a 2×1 combined AABB.
	var m := GoBuildMesh.new()
	m.vertices = [
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0),
		Vector3(1, 0, 0), Vector3(2, 0, 0), Vector3(2, 1, 0), Vector3(1, 1, 0),
	]
	var f0 := GoBuildFace.new()
	f0.vertex_indices = [0, 1, 2, 3]
	f0.uvs = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var f1 := GoBuildFace.new()
	f1.vertex_indices = [4, 5, 6, 7]
	f1.uvs = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	m.faces.append(f0)
	m.faces.append(f1)
	var sel := SelectionManager.new()
	sel.set_mode(SelectionManager.Mode.FACE)
	sel.select_face(0)
	sel.select_face(1)
	var t: String = SelectionDimsHelper.build(m, sel, Transform3D.IDENTITY)
	assert_str(t).is_equal("W: 2m  H: 1m  D: 0m")
