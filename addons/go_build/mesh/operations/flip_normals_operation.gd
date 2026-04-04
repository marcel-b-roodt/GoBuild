## Flip Normals operation for [GoBuildMesh].
##
## Reverses the winding order of each selected face, flipping its outward normal.
## The reversal is applied by calling [code]Array.reverse()[/code] on
## [member GoBuildFace.vertex_indices] and the matching per-vertex UV channels so
## that each vertex retains its original UV coordinates after the flip.
##
## Because [method GoBuildMesh.compute_face_normal] derives the outward normal
## from the winding order (Newell's method), no separate normal storage is needed —
## reversing the winding is sufficient.
##
## Call [method GoBuildMesh.rebuild_edges] after the operation to keep edge
## topology in sync — this class calls it automatically inside [method apply].
@tool
class_name FlipNormalsOperation
extends RefCounted

# Self-preloads — dependency order.
# GoBuildFace / GoBuildMesh live in mesh/ which is scanned before
# operations/ alphabetically, but explicit preloads are required per
# the self-preload rule whenever a class name is used as a compile-time type.
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")


## Reverse the outward normal of each face at [param face_indices] on [param mesh].
##
## Invalid (out-of-range) indices are silently skipped.
## Degenerate faces (fewer than 3 vertices) are silently skipped.
## [method GoBuildMesh.rebuild_edges] is called automatically on completion
## if at least one face was flipped.
static func apply(mesh: GoBuildMesh, face_indices: Array[int]) -> void:
	if mesh == null or face_indices.is_empty():
		return

	var flipped: bool = false
	for fi: int in face_indices:
		if fi < 0 or fi >= mesh.faces.size():
			continue
		var face: GoBuildFace = mesh.faces[fi]
		if face.vertex_indices.size() < 3:
			continue
		_flip_single_face(face)
		flipped = true

	if flipped:
		mesh.rebuild_edges()


## Reverse the winding of [param face] in place.
##
## Reverses [member GoBuildFace.vertex_indices], [member GoBuildFace.uvs], and
## [member GoBuildFace.uv2s] (if present and the same length) so that each
## vertex keeps its original UV assignment after the winding is reversed.
static func _flip_single_face(face: GoBuildFace) -> void:
	face.vertex_indices.reverse()
	face.uvs.reverse()
	# uv2s is optional; only reverse if it is fully populated for this face.
	if face.uv2s.size() == face.vertex_indices.size():
		face.uv2s.reverse()

