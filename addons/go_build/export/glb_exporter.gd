## Export [GoBuildMesh] geometry to GLB (binary glTF 2.0).
##
## Uses Godot's built-in [GLTFDocument] for full fidelity: vertex positions,
## normals, UVs, vertex colours, and materials are preserved.
##
## The exported mesh is centered at the world origin with no transform,
## regardless of the source node's position in the scene.
##
## Usage:
##   [codeblock]
##   var err := GlbExporter.export_file(mesh_instance, "res://output.glb")
##   [/codeblock]
@tool
class_name GlbExporter
extends RefCounted


const _MESH_INSTANCE_SCRIPT := preload("res://addons/go_build/core/go_build_mesh_instance.gd")

## Export the baked mesh from [param mesh_instance] as a GLB file to [param path].
##
## [param path] should be a [code]res://[/code] or absolute path with a [code].glb[/code]
## extension. The file is written to disk immediately.
##
## Returns [code]OK[/code] on success, or an error code.
static func export_file(mesh_instance: GoBuildMeshInstance, path: String) -> Error:
	if mesh_instance == null:
		push_warning("GlbExporter: mesh_instance is null")
		return ERR_INVALID_PARAMETER
	if not mesh_instance.is_inside_tree():
		push_warning("GlbExporter: mesh_instance must be in the scene tree to export")
		return ERR_INVALID_PARAMETER
	var baked_mesh: Mesh = mesh_instance.mesh
	if baked_mesh == null:
		push_warning("GlbExporter: mesh_instance has no baked mesh")
		return ERR_INVALID_PARAMETER
	if path.is_empty():
		push_warning("GlbExporter: path is empty")
		return ERR_INVALID_PARAMETER
	if not path.to_lower().ends_with(".glb"):
		push_warning("GlbExporter: path must end with .glb, got %s" % path)
		return ERR_INVALID_PARAMETER

	# Rebuild mesh with full-precision floats to avoid "Byte/Half formats
	# not supported" errors in GLTFDocument.
	var full_prec_mesh: ArrayMesh = _rebake_full_precision(baked_mesh)

	# Create a temporary MeshInstance3D at the world origin.
	# GLTFDocument requires the node to be in the scene tree.
	var export_node := MeshInstance3D.new()
	export_node.name = "__GoBuildExport_" + mesh_instance.name
	export_node.mesh = full_prec_mesh
	for i in full_prec_mesh.get_surface_count():
		var mat: Material = full_prec_mesh.surface_get_material(i)
		if mat != null:
			export_node.set_surface_override_material(i, mat)
	export_node.owner = null  # don't pollute scene saves

	var scene_root: Node = mesh_instance.get_tree().current_scene
	if scene_root == null:
		scene_root = mesh_instance.get_parent()
	if scene_root == null:
		push_warning("GlbExporter: cannot find a scene root to attach export node")
		return ERR_INVALID_PARAMETER
	scene_root.add_child(export_node, true)

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err: Error = doc.append_from_scene(export_node, state)

	# Clean up immediately — remove from tree and free memory.
	scene_root.remove_child(export_node)
	export_node.free()

	if err != OK:
		push_warning("GlbExporter: GLTFDocument.append_from_scene failed with error %d" % err)
		return err

	var dir_path: String = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		var da := DirAccess.open("res://")
		if da != null:
			da.make_dir_recursive(dir_path.replace("res://", ""))

	err = doc.write_to_filesystem(state, path)
	if err != OK:
		push_warning("GlbExporter: write_to_filesystem failed with error %d" % err)
	return err


## Rebuild the mesh with full-precision normals and tangents.
## Godot's ArrayMesh compresses normals to half-float and tangents to bytes
## by default, which GLTFDocument cannot export ("Byte/Half formats not supported").
## We rebuild surface-by-surface using add_surface_from_arrays with the
## ARRAY_FLAG_USES_FULL_NORMAL_AND_TANGENT flag to force Float32.
static func _rebake_full_precision(src_mesh: Mesh) -> ArrayMesh:
	var result := ArrayMesh.new()
	for surf_idx in src_mesh.get_surface_count():
		var arrays: Array = src_mesh.surface_get_arrays(surf_idx)
		if arrays.is_empty():
			continue
		var format: int = src_mesh.surface_get_format(surf_idx)
		format |= Mesh.ARRAY_FLAG_USES_FULL_NORMAL_AND_TANGENT
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, format)
		var mat: Material = src_mesh.surface_get_material(surf_idx)
		if mat != null:
			result.surface_set_material(result.get_surface_count() - 1, mat)
	return result