## GoBuildCube5 — the session's standard user mesh, verbatim from the
## in-editor Print Selection dump (2026-09-06).  All knife repro tests run
## against this fixture: 2.863×1.877×1 prism, +Z face = face 2.
## NOTE: not class_name'd — loaded via preload in tests.
class_name GoBuildCube5Fixture
extends RefCounted

const _MESH := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _FACE := preload("res://addons/go_build/mesh/go_build_face.gd")


static func make() -> GoBuildMesh:
	var m: GoBuildMesh = _MESH.new()
	m.vertices = [
		Vector3(-2.362876, 1.377355, 0.5),   # 0
		Vector3(0.5, 1.377355, 0.5),         # 1
		Vector3(-2.362876, 1.377355, -0.5),  # 2
		Vector3(0.5, 1.377355, -0.5),        # 3
		Vector3(-2.362876, -0.5, -0.5),      # 4
		Vector3(0.5, -0.5, -0.5),            # 5
		Vector3(-2.362876, -0.5, 0.5),       # 6
		Vector3(0.5, -0.5, 0.5),             # 7
	]
	var quads := [
		[0, 1, 3, 2],   # face 0: +Y
		[4, 5, 7, 6],   # face 1: -Y
		[6, 7, 1, 0],   # face 2: +Z
		[5, 4, 2, 3],   # face 3: -Z
		[7, 5, 3, 1],   # face 4: +X
		[4, 6, 0, 2],   # face 5: -X
	]
	for q: Array in quads:
		var f: GoBuildFace = _FACE.new()
		var r: Array[int] = []
		r.assign(q)
		f.vertex_indices = r
		m.faces.append(f)
	m.rebuild_edges()
	return m


## The user's exact closed-quad stroke (all picks recorded on face 2,
## close-click duplicate appended — the 2026-09-06 session repro).
static func closed_quad_stroke() -> Array:
	var raw := [
		Vector3(-0.836043, -0.068909, 0.5),
		Vector3(0.067063, -0.10663, 0.5),
		Vector3(-0.694604, 0.813599, 0.5),
		Vector3(-0.777948, 0.299069, 0.5),
	]
	var pts: Array = []
	for p: Vector3 in raw:
		pts.append({"face_index": 2, "position": p})
	pts.append({"face_index": 2, "position": raw[0]})
	return pts