## One-click UV preparation: applies Box projection to all faces, then packs islands.
##
## Applies Box UV projection to every face in the mesh, then packs all
## UV islands into the 0-1 tile.  This gives a good starting point for
## manual texturing in an external paint program.
##
## The projection uses the mesh's world-space transform (if the node is
## in the scene tree) so that rotated objects get correctly oriented UVs.
@tool
class_name UvPrepareForTexturing
extends RefCounted

const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _BOX_SCRIPT := preload("res://addons/go_build/uv/box_projection.gd")
const _PACK_SCRIPT := preload("res://addons/go_build/uv/uv_pack_islands.gd")


## Apply Box UV projection to all faces and pack islands.
## [param mesh] is the [GoBuildMesh] to modify.
## [param transform] is the world-space transform for Box projection.
## [param scale] is the UV scale (units per tile).  Default 1.0.
## [param margin] is the packing margin between islands.  Default 0.02.
## Returns the number of UV islands packed.
static func apply(
		mesh: GoBuildMesh,
		transform: Transform3D = Transform3D.IDENTITY,
		scale: float = 1.0,
		margin: float = 0.02,
) -> int:
	if mesh.faces.is_empty():
		return 0

	# Collect all face indices.
	var all_faces: Array[int] = []
	all_faces.resize(mesh.faces.size())
	for i: int in mesh.faces.size():
		all_faces[i] = i

	# Set all faces to NONE uv_projection_mode so Box projection
	# covers every face uniformly.
	for face: GoBuildFace in mesh.faces:
		face.uv_projection_mode = GoBuildFace.UvMode.NONE

	# Apply Box UV projection.
	BoxProjection.apply(mesh, all_faces, scale, transform)

	# Pack islands into 0-1 tile.
	return UvPackIslands.apply(mesh, margin)