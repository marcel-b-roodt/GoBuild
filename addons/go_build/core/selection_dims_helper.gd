## Pure helpers for building human-readable dimension strings from a
## GoBuildMesh selection.
##
## All methods are static so this helper can be called from plugin.gd,
## panel scripts, tests, and any future tooling without instantiation.
@tool
class_name SelectionDimsHelper
extends RefCounted

# ---------------------------------------------------------------------------
# Self-preloads — dependency order matters.
#
# selection_dims_helper.gd ('se_d') is compiled before selection_manager.gd
# ('se_m') and before anything in mesh/ (core/ is scanned before mesh/).
# Explicit preloads here ensure all referenced class names are registered
# before this script is compiled, regardless of scan order.
# ---------------------------------------------------------------------------
const _FACE_SCRIPT    := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT    := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT    := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _SEL_MGR_SCRIPT := preload("res://addons/go_build/core/selection_manager.gd")

## Axis-aligned extent below this threshold (metres) is considered flat.
const FLAT_THRESHOLD: float = 0.0001


# ---------------------------------------------------------------------------
# Formatting
# ---------------------------------------------------------------------------

## Format [param v] as a compact metre string with up to 3 significant decimal
## places, trailing zeros stripped.
## Examples: 1.0 → "1m", 1.5 → "1.5m", 1.234 → "1.234m", -0.5 → "-0.5m".
static func fmt_m(v: float) -> String:
	if not is_finite(v):
		return "?m"
	var s := "%.3f" % absf(v)
	var parts := s.split(".")
	if parts.size() < 2:
		return str(absf(v)) + "m"
	var frac: String = parts[1].rstrip("0")
	var r: String = ("-" if v < 0.0 else "") + parts[0]
	if frac.length() > 0:
		r += "." + frac
	return r + "m"


# ---------------------------------------------------------------------------
# Bounding box
# ---------------------------------------------------------------------------

## Return the world-space AABB size vector for [param vert_indices].
static func bbox_extents(
		gbm: GoBuildMesh,
		vert_indices: Array[int],
		xform: Transform3D) -> Vector3:
	if vert_indices.is_empty():
		return Vector3.ZERO
	var mn := Vector3( INF,  INF,  INF)
	var mx := Vector3(-INF, -INF, -INF)
	for vi: int in vert_indices:
		if vi < 0 or vi >= gbm.vertices.size():
			continue
		var p: Vector3 = xform * gbm.vertices[vi]
		mn = mn.min(p)
		mx = mx.max(p)
	if mn.x == INF:
		return Vector3.ZERO
	return mx - mn


## Compute the world-space AABB of [param vert_indices] and return a
## formatted "W: Xm  H: Ym  D: Zm" string.
static func bbox_text(
		gbm: GoBuildMesh,
		vert_indices: Array[int],
		xform: Transform3D) -> String:
	var s: Vector3 = bbox_extents(gbm, vert_indices, xform)
	return "W: %s  H: %s  D: %s" % [fmt_m(s.x), fmt_m(s.y), fmt_m(s.z)]


## Compute W/H for a single face.
##
## Drops the near-zero axis-aligned extent (the flat axis) and shows the two
## in-plane extents as W (larger) and H (smaller).
## Falls back to W/H/D if all three extents are significant (diagonal face).
static func single_face_dims_text(
		gbm: GoBuildMesh,
		face_idx: int,
		xform: Transform3D) -> String:
	var vert_idxs: Array[int] = []
	vert_idxs.assign(gbm.faces[face_idx].vertex_indices)
	var s: Vector3 = bbox_extents(gbm, vert_idxs, xform)
	var sig: Array[float] = []
	if s.x > FLAT_THRESHOLD:
		sig.append(s.x)
	if s.y > FLAT_THRESHOLD:
		sig.append(s.y)
	if s.z > FLAT_THRESHOLD:
		sig.append(s.z)
	sig.sort()
	sig.reverse()
	if sig.size() == 2:
		return "W: %s  H: %s" % [fmt_m(sig[0]), fmt_m(sig[1])]
	return "W: %s  H: %s  D: %s" % [fmt_m(s.x), fmt_m(s.y), fmt_m(s.z)]


# ---------------------------------------------------------------------------
# Selection builder
# ---------------------------------------------------------------------------

## Build a human-readable dimension string for the current selection.
## Returns an empty string when nothing is selected or the mode is OBJECT.
## Safe to call with stale selection indices — out-of-bounds accesses are
## silently skipped and an empty string is returned.
static func build(
		gbm: GoBuildMesh,
		sel: SelectionManager,
		xform: Transform3D) -> String:
	if gbm == null or sel == null:
		return ""
	var result := ""

	match sel.get_mode():

		SelectionManager.Mode.VERTEX:
			var idxs: Array[int] = sel.get_selected_vertices()
			if not idxs.is_empty():
				if idxs.size() == 1:
					if idxs[0] >= gbm.vertices.size():
						return ""
					var p: Vector3 = xform * gbm.vertices[idxs[0]]
					result = "X: %s  Y: %s  Z: %s" % [fmt_m(p.x), fmt_m(p.y), fmt_m(p.z)]
				elif idxs.size() == 2:
					if idxs[0] >= gbm.vertices.size() or idxs[1] >= gbm.vertices.size():
						return ""
					var a: Vector3 = xform * gbm.vertices[idxs[0]]
					var b: Vector3 = xform * gbm.vertices[idxs[1]]
					var d: Vector3 = (b - a).abs()
					result = "X: %s  Y: %s  Z: %s  (%s)" % \
							[fmt_m(d.x), fmt_m(d.y), fmt_m(d.z), fmt_m(a.distance_to(b))]
				else:
					result = bbox_text(gbm, idxs, xform)

		SelectionManager.Mode.EDGE:
			var idxs: Array[int] = sel.get_selected_edges()
			if not idxs.is_empty():
				if idxs.size() == 1:
					if idxs[0] >= gbm.edges.size():
						return ""
					var e: GoBuildEdge = gbm.edges[idxs[0]]
					if e.vertex_a >= gbm.vertices.size() or e.vertex_b >= gbm.vertices.size():
						return ""
					var a: Vector3 = xform * gbm.vertices[e.vertex_a]
					var b: Vector3 = xform * gbm.vertices[e.vertex_b]
					result = "L: %s" % fmt_m(a.distance_to(b))
				else:
					var vert_set: Dictionary = {}
					for ei: int in idxs:
						vert_set[gbm.edges[ei].vertex_a] = true
						vert_set[gbm.edges[ei].vertex_b] = true
					var verts: Array[int] = []
					verts.assign(vert_set.keys())
					result = bbox_text(gbm, verts, xform)

		SelectionManager.Mode.FACE:
			var idxs: Array[int] = sel.get_selected_faces()
			if not idxs.is_empty():
				if idxs.size() == 1:
					if idxs[0] >= gbm.faces.size():
						return ""
					result = single_face_dims_text(gbm, idxs[0], xform)
				else:
					var vert_set: Dictionary = {}
					for fi: int in idxs:
						for vi: int in gbm.faces[fi].vertex_indices:
							vert_set[vi] = true
					var verts: Array[int] = []
					verts.assign(vert_set.keys())
					result = bbox_text(gbm, verts, xform)

	return result
