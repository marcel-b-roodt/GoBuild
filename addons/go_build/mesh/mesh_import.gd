## Import an existing Godot [ArrayMesh] into a [GoBuildMesh].
##
## Reads vertex positions, UVs, UV2s, and vertex colours from each surface of
## an [ArrayMesh] and reconstructs a [GoBuildMesh] with per-triangle faces.
## Indexed meshes are expanded so every face is self-contained.
##
## Each surface becomes a separate material slot.  Smooth groups are set to 0
## (flat shading) — the importer does not reconstruct smooth groups from split
## normals.  UV projection mode defaults to [constant GoBuildFace.UvMode.NONE]
## so the global auto-UV setting applies.
##
## [param reverse_winding]: Standard Godot meshes (GLTF imports, SurfaceTool
## output) store triangles CCW from outside, which matches GoBuildMesh's
## convention.  Leave [code]false[/code] (default).  Set to [code]true[/code]
## only when re-importing a mesh that was originally baked by GoBuild (which
## emits CW triangles to compensate for Vulkan's Y-flip).
##
## Usage:
## [codeblock]
## var source_mesh: ArrayMesh = mesh_instance.get_mesh()
## var go_mesh: GoBuildMesh = MeshImport.from_array_mesh(source_mesh)
## [/codeblock]
class_name MeshImport
extends RefCounted

# Self-preloads — compile-time type references.
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")


## Import all surfaces from [param array_mesh] into a new [GoBuildMesh].
##
## Each surface becomes one material slot.  Triangles are imported as 3-vertex
## faces.  If [param array_mesh] is [code]null[/code], returns an empty mesh.
## Set [param reverse_winding] to [code]true[/code] only when re-importing a
## GoBuild-baked mesh (which emits CW triangles).
static func from_array_mesh(
		array_mesh: ArrayMesh,
		reverse_winding: bool = false,
) -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	if array_mesh == null:
		return mesh

	var vertex_offset: int = 0

	for surf_idx: int in array_mesh.get_surface_count():
		var arrays: Array = array_mesh.surface_get_arrays(surf_idx)
		if arrays.is_empty():
			continue

		var mat: Material = array_mesh.surface_get_material(surf_idx)

		# Assign material slot.
		var mat_idx: int = mesh.material_slots.size()
		mesh.material_slots.append(mat)

		# Expand indexed or non-indexed geometry into flat vertex/face lists.
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if verts.is_empty():
			continue

		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array
		var uv2s: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2] as PackedVector2Array
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] as PackedColorArray
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array

		var has_uvs: bool = uvs.size() == verts.size()
		var has_uv2s: bool = uv2s.size() == verts.size()
		var has_colors: bool = colors.size() == verts.size()

		# ponytail: import each triangle as a 3-vertex face.
		# Users can dissolve/merge into n-gons later.  Full n-gon
		# reconstruction from triangulated data is lossy and fragile.
		var tri_count: int = 0
		if indices.size() > 0:
			tri_count = indices.size() / 3
		else:
			tri_count = verts.size() / 3

		for tri: int in tri_count:
			var face := GoBuildFace.new()
			face.material_index = mat_idx
			face.smooth_group = 0

			for corner: int in 3:
				var vi: int
				if indices.size() > 0:
					vi = indices[tri * 3 + corner]
				else:
					vi = tri * 3 + corner

				face.vertex_indices.append(vertex_offset + vi)
				if has_uvs:
					face.uvs.append(uvs[vi])
				else:
					face.uvs.append(Vector2.ZERO)
				if has_uv2s:
					face.uv2s.append(uv2s[vi])
				else:
					face.uv2s.append(Vector2.ZERO)

			# Standard Godot meshes are CCW (matching GoBuildMesh convention).
			# GoBuild-baked meshes are CW (Vulkan Y-flip compensation).
			if reverse_winding:
				face.vertex_indices.reverse()
				face.uvs.reverse()
				face.uv2s.reverse()

			mesh.faces.append(face)

		# Copy vertices and colours.
		for i: int in verts.size():
			mesh.vertices.append(verts[i])
			if has_colors:
				mesh.vertex_colors.append(colors[i])
			elif not mesh.vertex_colors.is_empty():
				mesh.vertex_colors.append(Color.WHITE)

		vertex_offset = mesh.vertices.size()

	# If any surface had colours, ensure all vertices have colours.
	_if_any_colors_fill_white(mesh)
	mesh.rebuild_edges()
	return mesh


## If at least one surface had vertex colours, fill the rest with white
## so [member GoBuildMesh.vertex_colors] stays parallel to [member GoBuildMesh.vertices].
static func _if_any_colors_fill_white(mesh: GoBuildMesh) -> void:
	if mesh.vertex_colors.is_empty():
		return
	if mesh.vertex_colors.size() < mesh.vertices.size():
		var diff: int = mesh.vertices.size() - mesh.vertex_colors.size()
		for _i: int in diff:
			mesh.vertex_colors.append(Color.WHITE)