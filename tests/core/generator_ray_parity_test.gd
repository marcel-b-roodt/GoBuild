## Generator ray-parity tests — every catalog shape.
##
## Invariant (issues/2026-09-06-generator-zfighting-parity.md): for every
## face of a generated mesh, a ray from the face centre along its Newell
## normal must cross an even number of OTHER faces (0 for hull faces).
## Odd parity = inverted winding or buried coplanar geometry — the
## z-fighting bug class.
@tool
extends GdUnitTestSuite

const _CATALOG := preload(
		"res://addons/go_build/mesh/generators/shape_creation_catalog.gd")


func _ray_tri(orig: Vector3, dir: Vector3, a: Vector3, b: Vector3,
		c: Vector3) -> float:
	var e1: Vector3 = b - a
	var e2: Vector3 = c - a
	var p: Vector3 = dir.cross(e2)
	var det: float = e1.dot(p)
	if absf(det) < 1e-10:
		return -1.0
	var inv: float = 1.0 / det
	var t: Vector3 = orig - a
	var u: float = t.dot(p) * inv
	if u < -1e-6 or u > 1.0 + 1e-6:
		return -1.0
	var q: Vector3 = t.cross(e1)
	var v: float = dir.dot(q) * inv
	if v < -1e-6 or u + v > 1.0 + 1e-6:
		return -1.0
	var dist: float = e2.dot(q) * inv
	if dist < 1e-6:
		return -1.0
	return dist


func _parity_fails(mesh: GoBuildMesh) -> Array[int]:
	var bad: Array[int] = []
	for fi: int in mesh.faces.size():
		var face: GoBuildFace = mesh.faces[fi]
		var n: Vector3 = mesh.compute_face_normal(face)
		var fc := Vector3.ZERO
		for vi: int in face.vertex_indices:
			fc += mesh.vertices[vi]
		fc /= float(face.vertex_indices.size())
		var orig: Vector3 = fc + n * 1e-4
		var hits := 0
		for fj: int in mesh.faces.size():
			if fj == fi:
				continue
			var other: GoBuildFace = mesh.faces[fj]
			var idx: Array = other.vertex_indices
			for k: int in range(1, idx.size() - 1):
				if _ray_tri(orig, n, mesh.vertices[idx[0]],
						mesh.vertices[idx[k]], mesh.vertices[idx[k + 1]]) > 0.0:
					hits += 1
					break
		if hits % 2 == 1:
			bad.append(fi)
	return bad


func test_all_shapes_have_even_ray_parity() -> void:
	for shape_name: String in _CATALOG.all_shapes():
		var params: Dictionary = _CATALOG.default_params(shape_name)
		if shape_name == "Polygon":
			# Polygon needs an explicit loop; default params have none.
			var points: Array[Vector3] = [
				Vector3(-1, 0, -1), Vector3(1, 0, -1),
				Vector3(1, 0, 1), Vector3(-1, 0, 1),
			]
			params["polygon_points"] = points
		var mesh: GoBuildMesh = _CATALOG.build_mesh(shape_name, params)
		assert_that(mesh).is_not_null()
		var bad: Array[int] = _parity_fails(mesh)
		assert_array(bad).is_empty()
