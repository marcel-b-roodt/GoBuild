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
## Negative [param amount] switches to depth mode: the inner ring keeps the
## outer ring's shape but is pushed along -face-normal by [code]-amount[/code]
## units (local space), producing a sunken floor with vertical side walls.
##
## When [param inner_centroids]/[param inner_normals] are provided, they are
## populated with mappings from each new inner vertex index to its face
## centroid / face normal (local space).  Used by the interactive drag path to
## animate the inset in real-time.
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
## [param amount] ≥ 0 is a blend factor: 0.0 = no inset, 1.0 = fully collapsed.
## [param amount] < 0 is a normal-offset depth in units (sunken floor).
## [param inner_centroids] / [param inner_normals] are optionally populated:
## inner_vert_idx → local centroid / local face normal.
## Invalid or degenerate face indices are silently skipped.
## [method GoBuildMesh.rebuild_edges] is called automatically on completion.
static func apply(
		mesh: GoBuildMesh,
		face_indices: Array[int],
		amount: float,
		inner_centroids: Dictionary = {},
		inner_normals: Dictionary = {},
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
		_inset_single_face(mesh, fi, amount, inner_centroids, inner_normals)
	mesh.rebuild_edges()


## Inset a single face by blending each vertex toward the face centroid
## (amount ≥ 0) or pushing it along -face-normal (amount < 0).
static func _inset_single_face(
		mesh: GoBuildMesh,
		face_index: int,
		amount: float,
		inner_centroids: Dictionary,
		inner_normals: Dictionary,
) -> void:
	var face: GoBuildFace = mesh.faces[face_index]
	var vc: int = face.vertex_indices.size()
	if vc < 3:
		return   # Degenerate face — skip silently.

	# ── 1. Compute face centroid + normal ────────────────────────────────────
	var centroid := Vector3.ZERO
	for vi: int in face.vertex_indices:
		centroid += mesh.vertices[vi]
	centroid /= float(vc)
	var normal := mesh.compute_face_normal(face)

	# ── 2. Create inner vertices ─────────────────────────────────────────────
	var inner_indices: Array[int] = []
	inner_indices.resize(vc)
	for k: int in vc:
		var outer_pos: Vector3 = mesh.vertices[face.vertex_indices[k]]
		var inner_pos: Vector3
		if amount >= 0.0:
			inner_pos = lerp(outer_pos, centroid, amount)
		else:
			inner_pos = outer_pos - normal * (-amount)
		inner_indices[k] = mesh.append_vertex_from(face.vertex_indices[k], inner_pos)
		inner_centroids[inner_indices[k]] = centroid
		inner_normals[inner_indices[k]] = normal

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

