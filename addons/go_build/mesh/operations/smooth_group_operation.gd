## Assigns a smooth group ID to every face in [param face_indices].
##
## Faces with [code]smooth_group == 0[/code] are flat-shaded (each face uses
## its own face normal at all vertices).  Faces with the same non-zero ID share
## averaged normals at shared vertices, producing a smooth silhouette across the
## seam.  IDs only need to be unique within a mesh — two meshes may reuse the
## same IDs without conflict.
##
## Usage:
## [codeblock]
## SmoothGroupOperation.apply(go_build_mesh, selected_face_indices, 1)
## # Flat-shade the same selection:
## SmoothGroupOperation.apply(go_build_mesh, selected_face_indices, 0)
## [/codeblock]
class_name SmoothGroupOperation
extends RefCounted

# Self-preloads — compile-time type references.
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")


## Set [member GoBuildFace.smooth_group] to [param group_id] for every face
## listed in [param face_indices].
##
## Out-of-range face indices are silently skipped.  An empty [param face_indices]
## array or a [code]null[/code] [param mesh] is a safe no-op.
static func apply(
		mesh: GoBuildMesh,
		face_indices: Array[int],
		group_id: int,
) -> void:
	if mesh == null:
		return
	for fi: int in face_indices:
		if fi < 0 or fi >= mesh.faces.size():
			continue
		mesh.faces[fi].smooth_group = group_id
