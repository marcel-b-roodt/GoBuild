## Box UV projection tests — GdUnit4
extends GdUnitTestSuite

const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _BOX_SCRIPT := preload("res://addons/go_build/uv/box_projection.gd")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

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


func _make_plus_z_rect(width: float = 2.0, height: float = 3.0) -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [
		Vector3(0.0, 0.0, 0.0),
		Vector3(width, 0.0, 0.0),
		Vector3(width, height, 0.0),
		Vector3(0.0, height, 0.0),
	]
	var face := GoBuildFace.new()
	face.vertex_indices = [0, 1, 2, 3]
	mesh.faces.append(face)
	return mesh


# ---------------------------------------------------------------------------
# World-space UV coordinate tests
# ---------------------------------------------------------------------------

func test_box_y_face_uv_origin_vertex_is_world_zero() -> void:
	# v0 = (0,0,0) → box +Y projection → UV = (x, -z) = (0, 0)
	var mesh := _make_plus_y_rect(2.0, 3.0)
	BoxProjection.apply(mesh, [0], 1.0)
	var face: GoBuildFace = mesh.faces[0]
	assert_float(face.uvs[0].x).is_equal_approx(0.0, 0.001)
	assert_float(face.uvs[0].y).is_equal_approx(0.0, 0.001)


func test_box_y_face_uv_matches_world_xz() -> void:
	# v2 = (2, 0, 3) → +Y face → UV = (x, -z) = (2, -3)
	var mesh := _make_plus_y_rect(2.0, 3.0)
	BoxProjection.apply(mesh, [0], 1.0)
	var face: GoBuildFace = mesh.faces[0]
	assert_float(face.uvs[2].x).is_equal_approx(2.0, 0.001)
	assert_float(face.uvs[2].y).is_equal_approx(-3.0, 0.001)


func test_box_x_face_uv_matches_world_zy() -> void:
	# +X face at x=0 — dominant axis is X, UV = (z, y)
	# v2 = (0, height, depth) = (0, 2, 3) → UV = (z, y) = (3, 2)
	var mesh := _make_plus_x_rect(2.0, 3.0)
	BoxProjection.apply(mesh, [0], 1.0)
	var face: GoBuildFace = mesh.faces[0]
	assert_float(face.uvs[2].x).is_equal_approx(3.0, 0.001)
	assert_float(face.uvs[2].y).is_equal_approx(2.0, 0.001)


func test_box_z_face_uv_matches_world_xy() -> void:
	# +Z face at z=0 — dominant axis is Z, UV = (x, y)
	# v2 = (width, height, 0) = (2, 3, 0) → UV = (x, y) = (2, 3)
	var mesh := _make_plus_z_rect(2.0, 3.0)
	BoxProjection.apply(mesh, [0], 1.0)
	var face: GoBuildFace = mesh.faces[0]
	assert_float(face.uvs[2].x).is_equal_approx(2.0, 0.001)
	assert_float(face.uvs[2].y).is_equal_approx(3.0, 0.001)


# ---------------------------------------------------------------------------
# Span tests (dimensions still correct even without per-face origin reset)
# ---------------------------------------------------------------------------

func test_box_y_face_uv_span_matches_face_dimensions() -> void:
	var mesh := _make_plus_y_rect(2.0, 3.0)
	BoxProjection.apply(mesh, [0], 1.0)
	var face: GoBuildFace = mesh.faces[0]
	var min_u := INF; var max_u := -INF
	var min_v := INF; var max_v := -INF
	for uv: Vector2 in face.uvs:
		min_u = minf(min_u, uv.x); max_u = maxf(max_u, uv.x)
		min_v = minf(min_v, uv.y); max_v = maxf(max_v, uv.y)
	assert_float(max_u - min_u).is_equal_approx(2.0, 0.001)
	assert_float(max_v - min_v).is_equal_approx(3.0, 0.001)


func test_box_x_face_uv_span_matches_face_dimensions() -> void:
	var mesh := _make_plus_x_rect(2.0, 3.0)
	BoxProjection.apply(mesh, [0], 1.0)
	var face: GoBuildFace = mesh.faces[0]
	var min_u := INF; var max_u := -INF
	var min_v := INF; var max_v := -INF
	for uv: Vector2 in face.uvs:
		min_u = minf(min_u, uv.x); max_u = maxf(max_u, uv.x)
		min_v = minf(min_v, uv.y); max_v = maxf(max_v, uv.y)
	assert_float(max_u - min_u).is_equal_approx(3.0, 0.001)
	assert_float(max_v - min_v).is_equal_approx(2.0, 0.001)


# ---------------------------------------------------------------------------
# units_per_tile scaling
# ---------------------------------------------------------------------------

func test_box_projection_respects_units_per_tile() -> void:
	# 2×3 face at units_per_tile=0.5 → UV span 4×6
	var mesh := _make_plus_y_rect(2.0, 3.0)
	BoxProjection.apply(mesh, [0], 0.5)
	var face: GoBuildFace = mesh.faces[0]
	var min_u := INF; var max_u := -INF
	var min_v := INF; var max_v := -INF
	for uv: Vector2 in face.uvs:
		min_u = minf(min_u, uv.x); max_u = maxf(max_u, uv.x)
		min_v = minf(min_v, uv.y); max_v = maxf(max_v, uv.y)
	assert_float(max_u - min_u).is_equal_approx(4.0, 0.001)
	assert_float(max_v - min_v).is_equal_approx(6.0, 0.001)


# ---------------------------------------------------------------------------
# Seamless-seam test — the key difference from planar projection
# ---------------------------------------------------------------------------

func test_box_projection_adjacent_y_faces_share_uvs_at_seam() -> void:
	# Two unit quads side by side in the XZ plane, sharing edge at x=1.
	# Box projection should assign identical UVs to the shared vertices.
	var mesh := GoBuildMesh.new()
	mesh.vertices = [
		Vector3(0.0, 0.0, 0.0),  # 0
		Vector3(0.0, 0.0, 1.0),  # 1
		Vector3(1.0, 0.0, 1.0),  # 2  — shared
		Vector3(1.0, 0.0, 0.0),  # 3  — shared
		Vector3(2.0, 0.0, 0.0),  # 4
		Vector3(2.0, 0.0, 1.0),  # 5
	]
	var left := GoBuildFace.new()
	left.vertex_indices = [0, 1, 2, 3]
	var right := GoBuildFace.new()
	right.vertex_indices = [3, 2, 5, 4]
	mesh.faces = [left, right]

	BoxProjection.apply(mesh, [0, 1], 1.0)

	# Left face: v2=(1,0,1) → UV=(1,-1);  v3=(1,0,0) → UV=(1,0)
	# Right face: v0=(1,0,0) → UV=(1,0);  v1=(1,0,1) → UV=(1,-1)
	var left_shared_a: Vector2 = mesh.faces[0].uvs[2]  # vertex 2 = (1,0,1)
	var left_shared_b: Vector2 = mesh.faces[0].uvs[3]  # vertex 3 = (1,0,0)
	var right_shared_a: Vector2 = mesh.faces[1].uvs[0] # vertex 3 = (1,0,0)
	var right_shared_b: Vector2 = mesh.faces[1].uvs[1] # vertex 2 = (1,0,1)

	assert_float(left_shared_b.x).is_equal_approx(right_shared_a.x, 0.001)
	assert_float(left_shared_b.y).is_equal_approx(right_shared_a.y, 0.001)
	assert_float(left_shared_a.x).is_equal_approx(right_shared_b.x, 0.001)
	assert_float(left_shared_a.y).is_equal_approx(right_shared_b.y, 0.001)


# ---------------------------------------------------------------------------
# Selection scoping
# ---------------------------------------------------------------------------

func test_box_projection_only_changes_selected_faces() -> void:
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
	BoxProjection.apply(mesh, [0], 1.0)

	# Left face UVs changed.
	var min_u := INF; var max_u := -INF
	for uv: Vector2 in mesh.faces[0].uvs:
		min_u = minf(min_u, uv.x); max_u = maxf(max_u, uv.x)
	assert_float(max_u - min_u).is_equal_approx(1.0, 0.001)

	# Right face UVs unchanged.
	assert_float(mesh.faces[1].uvs[0].x).is_equal_approx(7.0, 0.001)
	assert_float(mesh.faces[1].uvs[0].y).is_equal_approx(7.0, 0.001)


# ---------------------------------------------------------------------------
# Guard / no-op tests
# ---------------------------------------------------------------------------

func test_box_projection_empty_selection_is_noop() -> void:
	var mesh := _make_plus_y_rect(2.0, 3.0)
	BoxProjection.apply(mesh, [], 1.0)
	assert_int(mesh.faces[0].uvs.size()).is_equal(0)


func test_box_projection_null_mesh_is_noop() -> void:
	# Must not crash.
	BoxProjection.apply(null, [0], 1.0)


func test_box_projection_non_positive_units_per_tile_is_noop() -> void:
	var mesh := _make_plus_y_rect(2.0, 3.0)
	BoxProjection.apply(mesh, [0], 0.0)
	assert_int(mesh.faces[0].uvs.size()).is_equal(0)
	BoxProjection.apply(mesh, [0], -1.0)
	assert_int(mesh.faces[0].uvs.size()).is_equal(0)


func test_box_projection_out_of_range_face_index_is_skipped() -> void:
	var mesh := _make_plus_y_rect(2.0, 3.0)
	BoxProjection.apply(mesh, [99], 1.0)
	assert_int(mesh.faces[0].uvs.size()).is_equal(0)


func test_box_projection_degenerate_face_under_3_verts_is_noop() -> void:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [Vector3(0.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0)]
	var face := GoBuildFace.new()
	face.vertex_indices = [0, 1]
	mesh.faces.append(face)
	BoxProjection.apply(mesh, [0], 1.0)
	assert_int(mesh.faces[0].uvs.size()).is_equal(0)


# ---------------------------------------------------------------------------
# Transform-aware projection tests
# ---------------------------------------------------------------------------

func test_box_projection_identity_transform_matches_default_apply() -> void:
	var mesh_a := _make_plus_y_rect(2.0, 3.0)
	var mesh_b := _make_plus_y_rect(2.0, 3.0)

	BoxProjection.apply(mesh_a, [0], 1.0)
	BoxProjection.apply(mesh_b, [0], 1.0, Transform3D.IDENTITY)

	for i: int in 4:
		assert_float(mesh_a.faces[0].uvs[i].x).is_equal_approx(mesh_b.faces[0].uvs[i].x, 0.001)
		assert_float(mesh_a.faces[0].uvs[i].y).is_equal_approx(mesh_b.faces[0].uvs[i].y, 0.001)


func test_box_projection_translation_transform_offsets_uvs_in_projection_space() -> void:
	# +Y face maps as UV=(x,-z). Translating by (+5,+0,+7) should shift UV by (+5,-7).
	var mesh := _make_plus_y_rect(2.0, 3.0)
	var t := Transform3D(Basis.IDENTITY, Vector3(5.0, 0.0, 7.0))

	BoxProjection.apply(mesh, [0], 1.0, t)

	var face: GoBuildFace = mesh.faces[0]
	# v0 local=(0,0,0) -> world=(5,0,7) -> uv=(5,-7)
	assert_float(face.uvs[0].x).is_equal_approx(5.0, 0.001)
	assert_float(face.uvs[0].y).is_equal_approx(-7.0, 0.001)
	# v2 local=(2,0,3) -> world=(7,0,10) -> uv=(7,-10)
	assert_float(face.uvs[2].x).is_equal_approx(7.0, 0.001)
	assert_float(face.uvs[2].y).is_equal_approx(-10.0, 0.001)


func test_box_projection_translation_respects_units_per_tile() -> void:
	# Same as above, but 0.5 units_per_tile doubles UV coordinates.
	var mesh := _make_plus_y_rect(2.0, 3.0)
	var t := Transform3D(Basis.IDENTITY, Vector3(5.0, 0.0, 7.0))

	BoxProjection.apply(mesh, [0], 0.5, t)

	var face: GoBuildFace = mesh.faces[0]
	assert_float(face.uvs[0].x).is_equal_approx(10.0, 0.001)
	assert_float(face.uvs[0].y).is_equal_approx(-14.0, 0.001)
	assert_float(face.uvs[2].x).is_equal_approx(14.0, 0.001)
	assert_float(face.uvs[2].y).is_equal_approx(-20.0, 0.001)


func test_box_projection_rotation_transform_changes_axes_as_expected() -> void:
	# Rotate +Y face by +90 deg around Y:
	# local point (2,0,3) -> world (3,0,-2), so UV=(x,-z)=(3,2)
	var mesh := _make_plus_y_rect(2.0, 3.0)
	var basis := Basis(Vector3.UP, deg_to_rad(90.0))
	var t := Transform3D(basis, Vector3.ZERO)

	BoxProjection.apply(mesh, [0], 1.0, t)

	var uv: Vector2 = mesh.faces[0].uvs[2]
	assert_float(uv.x).is_equal_approx(3.0, 0.001)
	assert_float(uv.y).is_equal_approx(2.0, 0.001)


func test_box_projection_non_uniform_scale_transform_scales_uv_span() -> void:
	# +Y face with width=2, depth=3. Applying scale (2,1,0.5) should produce
	# world-space span U=4 (x scaled by 2) and V=1.5 (z scaled by 0.5).
	var mesh := _make_plus_y_rect(2.0, 3.0)
	var basis := Basis.from_scale(Vector3(2.0, 1.0, 0.5))
	var t := Transform3D(basis, Vector3.ZERO)

	BoxProjection.apply(mesh, [0], 1.0, t)

	var face: GoBuildFace = mesh.faces[0]
	var min_u := INF; var max_u := -INF
	var min_v := INF; var max_v := -INF
	for uv: Vector2 in face.uvs:
		min_u = minf(min_u, uv.x); max_u = maxf(max_u, uv.x)
		min_v = minf(min_v, uv.y); max_v = maxf(max_v, uv.y)
	assert_float(max_u - min_u).is_equal_approx(4.0, 0.001)
	assert_float(max_v - min_v).is_equal_approx(1.5, 0.001)


func test_box_projection_offset_shifts_all_uvs() -> void:
	# A +Y rect with offset (0.1, -0.2): all UVs must be shifted by exactly that.
	var mesh := _make_plus_y_rect(2.0, 3.0)
	var mesh2 := _make_plus_y_rect(2.0, 3.0)
	BoxProjection.apply(mesh,  [0], 1.0)
	BoxProjection.apply(mesh2, [0], 1.0, Transform3D.IDENTITY, Vector2(0.1, -0.2))
	for i: int in 4:
		assert_float(mesh2.faces[0].uvs[i].x).is_equal_approx(
				mesh.faces[0].uvs[i].x + 0.1, 0.001)
		assert_float(mesh2.faces[0].uvs[i].y).is_equal_approx(
				mesh.faces[0].uvs[i].y - 0.2, 0.001)
