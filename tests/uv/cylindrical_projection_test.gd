## Cylindrical UV projection tests — GdUnit4
extends GdUnitTestSuite

const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _CYL_SCRIPT  := preload("res://addons/go_build/uv/cylindrical_projection.gd")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## A ring of four vertices at height y=0, radius r, at the cardinal angles.
## Vertices are placed at +Z, +X, -Z, -X (i.e. 0°, 90°, 180°, 270°).
func _make_ring_face(radius: float = 1.0) -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [
		Vector3(0.0,        0.0, radius),   # 0: +Z  → atan2(0, r) = 0   → U = 0.5
		Vector3(radius,     0.0, 0.0),      # 1: +X  → atan2(r, 0) = π/2 → U = 0.75
		Vector3(0.0,        0.0, -radius),  # 2: -Z  → atan2(0,-r) = ±π  → U = 0 or 1
		Vector3(-radius,    0.0, 0.0),      # 3: -X  → atan2(-r,0)= -π/2 → U = 0.25
	]
	var face := GoBuildFace.new()
	face.vertex_indices = [0, 1, 2, 3]
	mesh.faces.append(face)
	return mesh


## A tall quad at +X side (x=radius, varying y).
func _make_vertical_strip(radius: float = 1.0, height: float = 2.0) -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [
		Vector3(radius, 0.0,    0.0),
		Vector3(radius, height, 0.0),
		Vector3(radius, height, 0.01),
		Vector3(radius, 0.0,    0.01),
	]
	var face := GoBuildFace.new()
	face.vertex_indices = [0, 1, 2, 3]
	mesh.faces.append(face)
	return mesh


# ---------------------------------------------------------------------------
# U coordinate tests
# ---------------------------------------------------------------------------

func test_plus_z_vertex_u_is_half() -> void:
	# +Z maps to atan2(0, r) = 0 → U = 0.5
	var mesh := _make_ring_face()
	CylindricalProjection.apply(mesh, [0], 1.0)
	assert_float(mesh.faces[0].uvs[0].x).is_equal_approx(0.5, 0.001)


func test_plus_x_vertex_u_is_three_quarters() -> void:
	# +X maps to atan2(r, 0) = π/2 → U = 0.75
	var mesh := _make_ring_face()
	CylindricalProjection.apply(mesh, [0], 1.0)
	assert_float(mesh.faces[0].uvs[1].x).is_equal_approx(0.75, 0.001)


func test_minus_x_vertex_u_is_quarter() -> void:
	# -X maps to atan2(-r, 0) = -π/2 → U = 0.25
	var mesh := _make_ring_face()
	CylindricalProjection.apply(mesh, [0], 1.0)
	assert_float(mesh.faces[0].uvs[3].x).is_equal_approx(0.25, 0.001)


func test_u_is_in_zero_to_one_range_for_all_ring_verts() -> void:
	var mesh := _make_ring_face()
	CylindricalProjection.apply(mesh, [0], 1.0)
	for uv: Vector2 in mesh.faces[0].uvs:
		assert_float(uv.x).is_greater_equal(0.0 - 0.001)
		assert_float(uv.x).is_less_equal(1.0 + 0.001)


# ---------------------------------------------------------------------------
# V coordinate (height) tests
# ---------------------------------------------------------------------------

func test_v_at_y_zero_is_zero() -> void:
	var mesh := _make_vertical_strip(1.0, 2.0)
	CylindricalProjection.apply(mesh, [0], 1.0)
	# Both bottom vertices have y=0 → V=0
	assert_float(mesh.faces[0].uvs[0].y).is_equal_approx(0.0, 0.001)
	assert_float(mesh.faces[0].uvs[3].y).is_equal_approx(0.0, 0.001)


func test_v_at_height_equals_height_over_units_per_tile() -> void:
	# height=2.0, units_per_tile=1.0 → V = 2.0
	var mesh := _make_vertical_strip(1.0, 2.0)
	CylindricalProjection.apply(mesh, [0], 1.0)
	assert_float(mesh.faces[0].uvs[1].y).is_equal_approx(2.0, 0.001)
	assert_float(mesh.faces[0].uvs[2].y).is_equal_approx(2.0, 0.001)


func test_v_scales_with_units_per_tile() -> void:
	# height=2.0, units_per_tile=2.0 → V = 1.0
	var mesh := _make_vertical_strip(1.0, 2.0)
	CylindricalProjection.apply(mesh, [0], 2.0)
	assert_float(mesh.faces[0].uvs[1].y).is_equal_approx(1.0, 0.001)


# ---------------------------------------------------------------------------
# UV count
# ---------------------------------------------------------------------------

func test_uv_count_matches_vertex_count() -> void:
	var mesh := _make_ring_face()
	CylindricalProjection.apply(mesh, [0], 1.0)
	assert_int(mesh.faces[0].uvs.size()).is_equal(4)


# ---------------------------------------------------------------------------
# Seam correction
# ---------------------------------------------------------------------------

func test_seam_correction_keeps_face_u_span_below_half() -> void:
	# A face straddling the +Z seam (U ≈ 0 / 1) should have adjacent U values
	# corrected so they are within 0.5 of vertex 0, not smeared across the whole
	# texture.  After correction the max U spread for any face must be < 0.5.
	var mesh := _make_ring_face()
	CylindricalProjection.apply(mesh, [0], 1.0)
	var face := mesh.faces[0]
	var u0: float = face.uvs[0].x
	for uv: Vector2 in face.uvs:
		assert_float(absf(uv.x - u0)).is_less_equal(0.5 + 0.001)


# ---------------------------------------------------------------------------
# World-space transform
# ---------------------------------------------------------------------------

func test_world_space_transform_shifts_v_by_translation_y() -> void:
	# Translate node 3 units up → all V values offset by 3 / units_per_tile
	var mesh := _make_vertical_strip(1.0, 2.0)
	var t := Transform3D(Basis.IDENTITY, Vector3(0.0, 3.0, 0.0))
	CylindricalProjection.apply(mesh, [0], 1.0, t)
	# Bottom vertex (local y=0 → world y=3) → V = 3.0
	assert_float(mesh.faces[0].uvs[0].y).is_equal_approx(3.0, 0.001)
	# Top vertex (local y=2 → world y=5) → V = 5.0
	assert_float(mesh.faces[0].uvs[1].y).is_equal_approx(5.0, 0.001)


func test_invalid_units_per_tile_noops() -> void:
	# units_per_tile <= 0 must not modify UVs.
	var mesh := _make_ring_face()
	var face := mesh.faces[0]
	face.uvs.resize(4)
	face.uvs[0] = Vector2(0.5, 0.5)
	CylindricalProjection.apply(mesh, [0], 0.0)
	CylindricalProjection.apply(mesh, [0], -1.0)
	assert_float(face.uvs[0].x).is_equal_approx(0.5, 0.001)
	assert_float(face.uvs[0].y).is_equal_approx(0.5, 0.001)


func test_degenerate_face_not_modified() -> void:
	# A face with fewer than 3 vertices should be skipped silently.
	var mesh := GoBuildMesh.new()
	mesh.vertices = [Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0)]
	var face := GoBuildFace.new()
	face.vertex_indices = [0, 1]
	face.uvs = [Vector2(0.1, 0.2), Vector2(0.3, 0.4)]
	mesh.faces.append(face)
	CylindricalProjection.apply(mesh, [0], 1.0)
	# UVs unchanged.
	assert_float(face.uvs[0].x).is_equal_approx(0.1, 0.001)
	assert_float(face.uvs[0].y).is_equal_approx(0.2, 0.001)
