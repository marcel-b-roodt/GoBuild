## Spherical UV projection tests — GdUnit4
extends GdUnitTestSuite

const _FACE_SCRIPT   := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MESH_SCRIPT   := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _SPHER_SCRIPT  := preload("res://addons/go_build/uv/spherical_projection.gd")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Build a mesh whose single face is a quad at the four provided positions.
func _make_face(v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3) -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [v0, v1, v2, v3]
	var face := GoBuildFace.new()
	face.vertex_indices = [0, 1, 2, 3]
	mesh.faces.append(face)
	return mesh


## Build a mesh with a triangle at three unit-sphere positions.
func _make_tri(v0: Vector3, v1: Vector3, v2: Vector3) -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	mesh.vertices = [v0, v1, v2]
	var face := GoBuildFace.new()
	face.vertex_indices = [0, 1, 2]
	mesh.faces.append(face)
	return mesh


# ---------------------------------------------------------------------------
# U coordinate — cardinal longitudes
# ---------------------------------------------------------------------------

func test_plus_z_vertex_u_is_half() -> void:
	# +Z: atan2(0, 1) = 0 → U = (0/TAU + 0.5) = 0.5
	var mesh := _make_tri(
		Vector3(0.0, 0.0,  1.0),
		Vector3(1.0, 0.0,  0.0),
		Vector3(0.0, 1.0,  0.0),
	)
	SphericalProjection.apply(mesh, [0], 1.0)
	assert_float(mesh.faces[0].uvs[0].x).is_equal_approx(0.5, 0.001)


func test_plus_x_vertex_u_is_three_quarters() -> void:
	# +X: atan2(1, 0) = PI/2 → U = (0.25 + 0.5) = 0.75
	var mesh := _make_tri(
		Vector3(1.0, 0.0,  0.0),
		Vector3(0.0, 0.0,  1.0),
		Vector3(0.0, 1.0,  0.0),
	)
	SphericalProjection.apply(mesh, [0], 1.0)
	assert_float(mesh.faces[0].uvs[0].x).is_equal_approx(0.75, 0.001)


func test_minus_x_vertex_u_is_quarter() -> void:
	# -X: atan2(-1, 0) = -PI/2 → U = (-0.25 + 0.5) = 0.25
	var mesh := _make_tri(
		Vector3(-1.0, 0.0,  0.0),
		Vector3( 0.0, 0.0,  1.0),
		Vector3( 0.0, 1.0,  0.0),
	)
	SphericalProjection.apply(mesh, [0], 1.0)
	assert_float(mesh.faces[0].uvs[0].x).is_equal_approx(0.25, 0.001)


# ---------------------------------------------------------------------------
# V coordinate — poles and equator
# ---------------------------------------------------------------------------

func test_north_pole_vertex_v_is_zero() -> void:
	# +Y (north pole): acos(1) = 0 → V = 0
	var mesh := _make_tri(
		Vector3(0.0,  1.0, 0.0),
		Vector3(1.0,  0.0, 0.0),
		Vector3(0.0,  0.0, 1.0),
	)
	SphericalProjection.apply(mesh, [0], 1.0)
	assert_float(mesh.faces[0].uvs[0].y).is_equal_approx(0.0, 0.001)


func test_south_pole_vertex_v_is_one() -> void:
	# -Y (south pole): acos(-1) = PI → V = 1
	var mesh := _make_tri(
		Vector3( 0.0, -1.0, 0.0),
		Vector3( 1.0,  0.0, 0.0),
		Vector3( 0.0,  0.0, 1.0),
	)
	SphericalProjection.apply(mesh, [0], 1.0)
	assert_float(mesh.faces[0].uvs[0].y).is_equal_approx(1.0, 0.001)


func test_equator_vertex_v_is_half() -> void:
	# Any equatorial vertex (y=0, r=1): acos(0) = PI/2 → V = 0.5
	var mesh := _make_tri(
		Vector3(0.0, 0.0,  1.0),
		Vector3(1.0, 0.0,  0.0),
		Vector3(0.0, 0.0, -1.0),
	)
	SphericalProjection.apply(mesh, [0], 1.0)
	assert_float(mesh.faces[0].uvs[0].y).is_equal_approx(0.5, 0.001)
	assert_float(mesh.faces[0].uvs[1].y).is_equal_approx(0.5, 0.001)


# ---------------------------------------------------------------------------
# units_per_tile scaling
# ---------------------------------------------------------------------------

func test_units_per_tile_scales_both_uv_components() -> void:
	# With units_per_tile=2: U and V should both be halved.
	var mesh := _make_tri(
		Vector3(0.0, 0.0,  1.0),
		Vector3(1.0, 0.0,  0.0),
		Vector3(0.0, 1.0,  0.0),
	)
	SphericalProjection.apply(mesh, [0], 2.0)
	# +Z equatorial: raw U=0.5, V=0.5 → scaled: 0.25, 0.25
	assert_float(mesh.faces[0].uvs[0].x).is_equal_approx(0.25, 0.001)
	assert_float(mesh.faces[0].uvs[0].y).is_equal_approx(0.25, 0.001)


# ---------------------------------------------------------------------------
# Seam correction
# ---------------------------------------------------------------------------

func test_seam_correction_keeps_face_u_span_below_half() -> void:
	# A face that straddles +Z (U≈0.5) and -Z (U≈0 or 1) should be corrected
	# so all vertices stay within 0.5 of vertex 0.
	var mesh := _make_face(
		Vector3( 0.01, 0.0,  1.0),   # near +Z, U ≈ 0.5
		Vector3( 0.01, 0.0, -1.0),   # near -Z, U ≈ 0 (or 1 before correction)
		Vector3(-0.01, 0.0, -1.0),
		Vector3(-0.01, 0.0,  1.0),
	)
	SphericalProjection.apply(mesh, [0], 1.0)
	var face := mesh.faces[0]
	var u0: float = face.uvs[0].x
	for uv: Vector2 in face.uvs:
		assert_float(absf(uv.x - u0)).is_less_equal(0.5 + 0.001)


# ---------------------------------------------------------------------------
# World-space transform
# ---------------------------------------------------------------------------

func test_world_space_rotation_shifts_u() -> void:
	# Rotating 90° around Y brings +X (+Z after rotation) → U should be 0.5.
	var mesh := _make_tri(
		Vector3(1.0, 0.0, 0.0),   # +X in local space
		Vector3(0.0, 0.0, 1.0),
		Vector3(0.0, 1.0, 0.0),
	)
	# Rotate 90° around Y: +X local → +Z world, so atan2(0,1)=0 → U=0.5
	var t := Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3.ZERO)
	SphericalProjection.apply(mesh, [0], 1.0, t)
	assert_float(mesh.faces[0].uvs[0].x).is_equal_approx(0.5, 0.001)


# ---------------------------------------------------------------------------
# Pole guard (degenerate vertex)
# ---------------------------------------------------------------------------

func test_origin_vertex_returns_centre_uv() -> void:
	# A vertex at the origin (r ≈ 0) should fall back to U=0.5, V=0.5.
	var mesh := _make_tri(
		Vector3.ZERO,
		Vector3(1.0, 0.0, 0.0),
		Vector3(0.0, 0.0, 1.0),
	)
	SphericalProjection.apply(mesh, [0], 1.0)
	assert_float(mesh.faces[0].uvs[0].x).is_equal_approx(0.5, 0.001)
	assert_float(mesh.faces[0].uvs[0].y).is_equal_approx(0.5, 0.001)


# ---------------------------------------------------------------------------
# Guard: invalid inputs
# ---------------------------------------------------------------------------

func test_invalid_units_per_tile_noops() -> void:
	var mesh := _make_tri(
		Vector3(0.0, 0.0, 1.0),
		Vector3(1.0, 0.0, 0.0),
		Vector3(0.0, 1.0, 0.0),
	)
	var face := mesh.faces[0]
	face.uvs.resize(3)
	face.uvs[0] = Vector2(0.9, 0.9)
	SphericalProjection.apply(mesh, [0], 0.0)
	SphericalProjection.apply(mesh, [0], -1.0)
	assert_float(face.uvs[0].x).is_equal_approx(0.9, 0.001)


# ---------------------------------------------------------------------------
# UV offset
# ---------------------------------------------------------------------------

func test_offset_shifts_all_uvs() -> void:
	# Apply projection, then apply again with offset (0.1, 0.2).
	# All UVs should be shifted by exactly that amount.
	var mesh := _make_tri(
		Vector3(0.0, 0.0,  1.0),
		Vector3(1.0, 0.0,  0.0),
		Vector3(0.0, 1.0,  0.0),
	)
	var mesh2 := _make_tri(
		Vector3(0.0, 0.0,  1.0),
		Vector3(1.0, 0.0,  0.0),
		Vector3(0.0, 1.0,  0.0),
	)
	SphericalProjection.apply(mesh,  [0], 1.0)
	SphericalProjection.apply(mesh2, [0], 1.0, Transform3D.IDENTITY,
			Vector2(0.1, 0.2))
	for i: int in 3:
		assert_float(mesh2.faces[0].uvs[i].x).is_equal_approx(
				mesh.faces[0].uvs[i].x + 0.1, 0.001)
		assert_float(mesh2.faces[0].uvs[i].y).is_equal_approx(
				mesh.faces[0].uvs[i].y + 0.2, 0.001)


# ---------------------------------------------------------------------------
# Seam rotation
# ---------------------------------------------------------------------------

func test_seam_rotation_180_moves_plus_z_to_u0() -> void:
	# +Z normally maps to U=0.5. With seam_rotation=180, it should map to U=0.
	# seam_rotation/360=0.5 → fposmod(0.5+0.5, 1.0)=0
	var mesh := _make_tri(
		Vector3(0.0, 0.0,  1.0),
		Vector3(1.0, 0.0,  0.0),
		Vector3(0.0, 1.0,  0.0),
	)
	SphericalProjection.apply(mesh, [0], 1.0, Transform3D.IDENTITY,
			Vector2.ZERO, 180.0)
	assert_float(mesh.faces[0].uvs[0].x).is_equal_approx(0.0, 0.001)
