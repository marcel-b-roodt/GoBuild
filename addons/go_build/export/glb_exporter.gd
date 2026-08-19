## Export [GoBuildMesh] geometry to GLB (binary GLTF 2.0).
##
## Uses Godot's built-in [GLTFDocument] for full fidelity: vertex positions,
## normals, UVs, vertex colours, and materials are preserved.
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

	# GLTFDocument requires the node to be in the scene tree to traverse it.
	# mesh_instance is already in the tree — we can pass it directly.
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err: Error = doc.append_from_scene(mesh_instance, state)
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