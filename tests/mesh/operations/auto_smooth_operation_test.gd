## Tests for AutoSmoothOperation.
##
## All tests operate on meshes with edges already built (CubeGenerator calls
## WeldOperation internally, which calls rebuild_edges).
extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Cube: all-flat below 90° threshold
# ---------------------------------------------------------------------------

## A unit cube has adjacent face normals at exactly 90°.
## With a 45° threshold (cos_thresh ≈ 0.707), 0 < 0.707 so no pair passes.
## Every face ends up in its own region of size 1 → smooth_group = 0.
func test_cube_all_flat_below_90_threshold() -> void:
	var m: GoBuildMesh = CubeGenerator.generate(1.0, 1.0, 1.0, 0)
	AutoSmoothOperation.apply(m, 45.0)
	for face: GoBuildFace in m.faces:
		assert_int(face.smooth_group).is_equal(0)


# ---------------------------------------------------------------------------
# Cube: all smooth above 90° threshold
# ---------------------------------------------------------------------------

## With a 91° threshold (cos_thresh ≈ −0.017), all cube face pairs
## satisfy dot(n1, n2) = 0 >= −0.017, so BFS groups all 6 faces together.
## Every face must be in a non-zero group, and all in the same group.
func test_cube_all_smooth_above_90_threshold() -> void:
	var m: GoBuildMesh = CubeGenerator.generate(1.0, 1.0, 1.0, 0)
	AutoSmoothOperation.apply(m, 91.0)

	for face: GoBuildFace in m.faces:
		assert_int(face.smooth_group).is_greater(0)

	# All faces share exactly one group ID.
	var first_group: int = m.faces[0].smooth_group
	for face: GoBuildFace in m.faces:
		assert_int(face.smooth_group).is_equal(first_group)


# ---------------------------------------------------------------------------
# Hard edges always force a seam
# ---------------------------------------------------------------------------

## Marking all edges hard means no BFS propagation can occur.
## Every face ends in its own region of size 1 → smooth_group = 0,
## even when the angle threshold allows smoothing (180°).
func test_hard_edges_always_seam() -> void:
	var m: GoBuildMesh = CubeGenerator.generate(1.0, 1.0, 1.0, 0)
	for edge: GoBuildEdge in m.edges:
		edge.is_hard = true
	AutoSmoothOperation.apply(m, 180.0)
	for face: GoBuildFace in m.faces:
		assert_int(face.smooth_group).is_equal(0)


# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

## Null mesh is a safe no-op — must not crash.
func test_null_mesh_noop() -> void:
	AutoSmoothOperation.apply(null, 30.0)
	assert_bool(true).is_true()


## Empty mesh is a safe no-op — must not crash.
func test_empty_mesh_noop() -> void:
	var m := GoBuildMesh.new()
	AutoSmoothOperation.apply(m, 30.0)
	assert_int(m.faces.size()).is_equal(0)


## Full 180° threshold makes all faces smooth regardless of angle.
## Cube → all 6 faces in one non-zero smooth group.
func test_180_degree_threshold_all_smooth() -> void:
	var m: GoBuildMesh = CubeGenerator.generate(1.0, 1.0, 1.0, 0)
	AutoSmoothOperation.apply(m, 180.0)
	var first_group: int = m.faces[0].smooth_group
	assert_int(first_group).is_greater(0)
	for face: GoBuildFace in m.faces:
		assert_int(face.smooth_group).is_equal(first_group)
