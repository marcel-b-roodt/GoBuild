## Inset face(s) operation for [GoBuildMesh].
##
## Shrinks each selected face toward its own centroid by [param amount] (0 = no
## inset, 1 = fully collapsed to centroid).  For each face the operation:
##   1. Computes the face centroid as the average of its vertex positions.
##   2. Creates inner vertices at [code]lerp(vertex, centroid, amount)[/code].
##   3. Adds border quads around the perimeter connecting the outer ring to the
##      inner ring (same winding convention as ExtrudeOperation side faces).
##   4. Replaces the original face's vertex_indices with the inner ring.
##
## When [param inner_centroids] is provided, it is populated with a mapping from
## each new inner vertex index to its face centroid (local space).  This is used
## by the interactive drag path to animate the inset in real-time.
##
## Call [method GoBuildMesh.rebuild_edges] after the operation to keep edge
## topology in sync — this class calls it automatically inside [method apply].
@tool
class_name InsetOperation
extends RefCounted

# Self-preloads — dependency order.
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")


## Inset the faces at [param face_indices] on [param mesh] by [param amount].
## [param amount] is a blend factor: 0.0 = no inset, 1.0 = fully collapsed.
## [param inner_centroids] is optionally populated: inner_vert_idx → local centroid.
## Invalid or degenerate face indices are silently skipped.
## [method GoBuildMesh.rebuild_edges] is called automatically on completion.
static func apply(
		mesh: GoBuildMesh,
		face_indices: Array[int],
		amount: float,
		inner_centroids: Dictionary = {},
) -> void:
	if mesh == null or face_indices.is_empty():
		return
	var valid: Array[int] = []
	for fi: int in face_indices:
		if fi >= 0 and fi < mesh.faces.size():
			valid.append(fi)
	if valid.is_empty():
		return
	for fi: int in valid:
		_inset_single_face(mesh, fi, amount, inner_centroids)
	mesh.rebuild_edges()


## Inset a single face by blending each vertex toward the face centroid.
static func _inset_single_face(
		mesh: GoBuildMesh,
		face_index: int,
		amount: float,
		inner_centroids: Dictionary,
) -> void:
	var face: GoBuildFace = mesh.faces[face_index]
	var vc: int = face.vertex_indices.size()
	if vc < 3:
		return   # Degenerate face — skip silently.

	# ── 1. Compute face centroid ─────────────────────────────────────────────
	var centroid := Vector3.ZERO
	for vi: int in face.vertex_indices:
		centroid += mesh.vertices[vi]
	centroid /= float(vc)

	# ── 2. Create inner vertices ─────────────────────────────────────────────
	var inner_indices: Array[int] = []
	inner_indices.resize(vc)
	for k: int in vc:
		var outer_pos: Vector3 = mesh.vertices[face.vertex_indices[k]]
		mesh.vertices.append(lerp(outer_pos, centroid, amount))
		inner_indices[k]              = mesh.vertices.size() - 1
		inner_centroids[inner_indices[k]] = centroid   # for drag animation

	# ── 3. Create border faces ───────────────────────────────────────────────
	# Winding [outer_k, outer_k+1, inner_k+1, inner_k] is CCW from outside
	# (same convention as ExtrudeOperation side faces — verified by Newell's method).
	for k: int in vc:
		var k_next: int = (k + 1) % vc
		var border := GoBuildFace.new()
		border.vertex_indices = [
			face.vertex_indices[k],
			face.vertex_indices[k_next],
			inner_indices[k_next],
			inner_indices[k],
		]
		border.material_index = face.material_index
		border.smooth_group   = face.smooth_group
		border.uvs = [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]
		mesh.faces.append(border)

	# ── 4. Replace face with inner ring ─────────────────────────────────────
	face.vertex_indices.assign(inner_indices)

