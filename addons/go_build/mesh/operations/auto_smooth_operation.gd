## Auto-smooth all faces in a [GoBuildMesh] by dihedral angle threshold.
##
## For each pair of adjacent faces that share a non-hard edge:
## [codeblock]
## dihedral_angle = acos(normal_a · normal_b)
## [/codeblock]
## Faces whose dihedral angle is smaller than [param angle_deg] are placed
## in the same smooth group; their normals are averaged at shared vertices.
## Edges at or above the threshold (and all hard-flagged edges) act as creases.
##
## This replaces all [member GoBuildFace.smooth_group] values on the mesh.
## Faces with no smooth neighbours receive group [code]0[/code] (flat shading).
##
## Usage:
## [codeblock]
## # Auto-smooth with 30° threshold (Blender default).
## AutoSmoothOperation.apply(go_build_mesh, 30.0)
## [/codeblock]
class_name AutoSmoothOperation
extends RefCounted

# Self-preloads — compile-time type references.
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")


## Apply angle-threshold smooth groups to every face in [param mesh].
##
## [param angle_deg] — dihedral angle threshold in degrees (1–180).
## Adjacent faces whose dihedral angle is strictly less than this value share
## a smooth group. Hard edges ([member GoBuildEdge.is_hard]) always force a
## seam regardless of the angle.
##
## Safe to call on a null or empty mesh.
static func apply(mesh: GoBuildMesh, angle_deg: float = 30.0) -> void:
	if mesh == null or mesh.faces.is_empty() or mesh.edges.is_empty():
		return

	var cos_thresh: float = cos(deg_to_rad(clampf(angle_deg, 0.0, 180.0)))

	# Pre-compute one face normal per face.
	var fn: Array[Vector3] = []
	fn.resize(mesh.faces.size())
	for i: int in mesh.faces.size():
		fn[i] = mesh.compute_face_normal(mesh.faces[i])

	# Build face → adjacent-edge index list for fast BFS traversal.
	var face_edges: Array = []
	face_edges.resize(mesh.faces.size())
	for i: int in mesh.faces.size():
		face_edges[i] = []
	for ei: int in mesh.edges.size():
		for fi: int in mesh.edges[ei].face_indices:
			face_edges[fi].append(ei)

	# BFS: group faces into smooth regions by propagating through edges whose
	# two faces satisfy the angle threshold (and are not hard).
	var face_group: Array[int] = []
	face_group.resize(mesh.faces.size())
	face_group.fill(-1)
	var next_group: int = 1

	for start: int in mesh.faces.size():
		if face_group[start] != -1:
			continue
		var group: int = next_group
		next_group += 1
		face_group[start] = group
		var queue: Array[int] = [start]
		var qi: int = 0
		while qi < queue.size():
			var fi: int = queue[qi]
			qi += 1
			for ei: int in face_edges[fi]:
				var edge: GoBuildEdge = mesh.edges[ei]
				if edge.is_hard:
					continue
				for fi2: int in edge.face_indices:
					if fi2 == fi or face_group[fi2] != -1:
						continue
					# Propagate when the dihedral angle is below the threshold.
					if fn[fi].dot(fn[fi2]) >= cos_thresh:
						face_group[fi2] = group
						queue.append(fi2)

	# Count how many faces each group contains.
	# Isolated faces (regions of size 1) are flat-shaded (group 0).
	var group_sizes: Dictionary = {}
	for g: int in face_group:
		group_sizes[g] = group_sizes.get(g, 0) + 1

	for fi: int in mesh.faces.size():
		var g: int = face_group[fi]
		mesh.faces[fi].smooth_group = 0 if group_sizes.get(g, 0) <= 1 else g
