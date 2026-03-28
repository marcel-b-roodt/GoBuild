## GoBuild mesh tests — GdUnit4
## Install GdUnit4 from AssetLib before running.
extends GdUnitTestSuite


# ── GoBuildMesh construction ─────────────────────────────────────────────

func test_placeholder_always_passes() -> void:
	# TODO: replace once GoBuildMesh is implemented.
	# var mesh := GoBuildMesh.new()
	# assert_int(mesh.vertices.size()).is_equal(0)
	assert_bool(true).is_true()

