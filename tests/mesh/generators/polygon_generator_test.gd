## PolygonGenerator unit tests — n-gon cap emission (one face per cap).
extends GdUnitTestSuite

const _GEN := preload("res://addons/go_build/mesh/generators/polygon_generator.gd")
const _MESH := preload("res://addons/go_build/mesh/go_build_mesh.gd")


## Concave pentagon outline (the "house" shape) in XZ.  Ring walks -z→+z on
## the right edge; with the right-hand rule (x×z = -Y) the ring normal
## (Newell) points +Y — the extrusion direction, caps ±Y as asserted.
func _concave_points() -> Array[Vector3]:
	return [
		Vector3(-1.0, 0.0,  1.0),
		Vector3( 1.0, 0.0,  1.0),
		Vector3( 1.0, 0.0, -1.0),
		Vector3( 0.0, 0.0, -0.5),
		Vector3(-1.0, 0.0, -1.0),
	]


func test_prism_two_cap_ngons() -> void:
	# 5-gon prism: 2 cap n-gons + 5 sides = 7 faces, 10 verts.
	var m: GoBuildMesh = _GEN.generate(_concave_points(), 1.0)
	assert_int(m.faces.size()).is_equal(7)
	assert_int(m.vertices.size()).is_equal(10)
	var cap_sizes: Array = []
	for f: GoBuildFace in m.faces:
		if f.vertex_indices.size() != 4:
			cap_sizes.append(f.vertex_indices.size())
	assert_array(cap_sizes).is_equal([5, 5])


func test_concave_cap_bakes_correct_triangle_count() -> void:
	# Concave 5-gon ear-clips into 3 triangles (not 5 — no fan shatter).
	# Sides are quads (2 tris each ×5), caps 3+3; baked vertices are
	# non-indexed (3 per triangle).
	var m: GoBuildMesh = _GEN.generate(_concave_points(), 1.0)
	var am := ArrayMesh.new()
	m.bake_into(am)
	var total: int = 0
	for s: int in am.get_surface_count():
		total += (am.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	assert_int(total / 3).is_equal(5 * 2 + 3 + 3)


func test_cap_winding_outward() -> void:
	# Both caps' normals must point along ±extrusion normal (+Y here).
	var pts := _concave_points()
	var m: GoBuildMesh = _GEN.generate(pts, 1.0)
	var cap_normals: Array = []
	for f: GoBuildFace in m.faces:
		if f.vertex_indices.size() == 5:
			cap_normals.append(m.compute_face_normal(f))
	assert_vector(cap_normals[0]).is_equal_approx(Vector3.DOWN, Vector3.ONE * 0.001)
	assert_vector(cap_normals[1]).is_equal_approx(Vector3.UP, Vector3.ONE * 0.001)


func test_no_caps() -> void:
	# cap_bottom=false, cap_top=false → sides only.
	var m: GoBuildMesh = _GEN.generate(_concave_points(), 1.0, false, false)
	assert_int(m.faces.size()).is_equal(5)