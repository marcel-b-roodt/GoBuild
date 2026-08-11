## Triangulate face(s) operation for [GoBuildMesh].
##
## Converts each selected face with more than 3 vertices into triangle faces
## using ear-clipping triangulation.  Triangles (3-vertex faces) are left
## unchanged.
##
## Each n-gon is replaced by (N - 2) triangle faces that cover the same area.
## The new faces inherit the material index, smooth group, and UV projection
## mode of the original face.  Per-vertex UVs are interpolated from the
## original face's UV ring.
##
## [method GoBuildMesh.rebuild_edges] is called automatically on completion.
@tool
class_name TriangulateOperation
extends RefCounted

# Self-preloads — dependency order.
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _TRIANGULATE_SCRIPT := preload("res://addons/go_build/mesh/triangulate.gd")
const _DEBUG_SCRIPT := preload("res://addons/go_build/core/go_build_debug.gd")


## Triangulate the faces at [param face_indices] on [param mesh].
##
## Each face with more than 3 vertices is replaced by triangle faces.
## Faces with exactly 3 vertices are silently skipped.
## [method GoBuildMesh.rebuild_edges] is called automatically on completion.
static func apply(mesh: GoBuildMesh, face_indices: Array[int]) -> void:
	if mesh == null or face_indices.is_empty():
		return

	var valid: Array[int] = []
	var seen: Dictionary = {}
	for fi: int in face_indices:
		if fi >= 0 and fi < mesh.faces.size() and not seen.has(fi):
			seen[fi] = true
			if mesh.faces[fi].vertex_indices.size() > 3:
				valid.append(fi)

	if valid.is_empty():
		return

	# Process in reverse order so removals don't shift earlier indices.
	valid.sort()
	valid.reverse()

	for fi: int in valid:
		var face: GoBuildFace = mesh.faces[fi]
		var vc: int = face.vertex_indices.size()
		if vc <= 3:
			continue

		GoBuildDebug.log("[Triangulate] fi=%d vc=%d verts=%s" % [fi, vc, str(face.vertex_indices)])

		# Compute the face normal for ear-clipping projection.
		var normal: Vector3 = mesh.compute_face_normal(face)
		GoBuildDebug.log("[Triangulate] normal=%s" % str(normal))

		# Build 3D point array for ear_clip.
		var points: Array[Vector3] = []
		points.resize(vc)
		for k: int in vc:
			points[k] = mesh.vertices[face.vertex_indices[k]]

		# Ear-clip returns triangles as arrays of 3 local indices (CCW).
		var tris: Array = Triangulate.ear_clip(points, normal)
		GoBuildDebug.log("[Triangulate] ear_clip returned %d triangles" % tris.size())
		if tris.is_empty():
			# Ear-clip can fail on non-planar faces where the 2D projection
			# self-intersects. Fall back to fan triangulation.
			# Fan returns CW-from-outside indices ([0, tri+2, tri+1]), but
			# GoBuildFace stores CCW-from-outside. Swap the last two indices.
			GoBuildDebug.log(
					"[Triangulate] ear_clip failed for fi=%d, falling back to fan"
					% fi)
			var fan_tris: Array = Triangulate.fan(vc)
			tris = []
			for ft: Array in fan_tris:
				tris.append([ft[0], ft[2], ft[1]])

		# Build replacement triangle faces.
		var new_faces: Array[GoBuildFace] = []
		new_faces.resize(tris.size())
		for ti: int in tris.size():
			var tri: Array = tris[ti]
			var tface := GoBuildFace.new()
			var vis: Array[int] = []
			vis.resize(3)
			var uvs: Array[Vector2] = []
			uvs.resize(3)
			for li: int in 3:
				var orig_idx: int = tri[li]
				vis[li] = face.vertex_indices[orig_idx]
				if face.uvs.size() == vc:
					uvs[li] = face.uvs[orig_idx]
				else:
					uvs[li] = Vector2.ZERO
			tface.vertex_indices = vis
			tface.uvs = uvs
			tface.material_index = face.material_index
			tface.smooth_group = face.smooth_group
			tface.uv_projection_mode = face.uv_projection_mode
			tface.uv_scale = face.uv_scale
			tface.uv_offset = face.uv_offset
			tface.uv_seam_rotation = face.uv_seam_rotation
			new_faces[ti] = tface

		# Replace original face with first triangle, append the rest.
		mesh.faces[fi] = new_faces[0]
		for ti: int in range(1, new_faces.size()):
			mesh.faces.append(new_faces[ti])

	mesh.rebuild_edges()