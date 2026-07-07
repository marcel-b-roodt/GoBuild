## Transparent overlay on the 3D viewport that intercepts drag-and-drop of
## textures and materials from the FileSystem dock.
##
## When a texture or material file is dragged onto the viewport while a
## GoBuildMeshInstance is being edited, this overlay:
## [br]
##   - Accepts the drop and converts it to a face-level material assignment
##     through GoBuild's [GoBuildMesh.material_slots] system.
##   - Clears any [material_override] or [surface_override_material] that Godot's
##     built-in editor handler may have set as a drag preview.
##   - Creates a proper undo/redo action so the user can revert the assignment.
## [br]
## If no GoBuildMeshInstance is being edited, the drop falls through to Godot's
## default behaviour (setting [material_override] or [surface_override_material]
## on the MeshInstance3D).
@tool
class_name GoBuildMaterialDropOverlay
extends Control

# Self-preloads
const _MESH_SCRIPT                 := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _FACE_SCRIPT                 := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MATERIAL_ASSIGN_SCRIPT := preload(
		"res://addons/go_build/mesh/operations/material_assign_operation.gd")
const _SELECTION_MGR_SCRIPT := preload(
		"res://addons/go_build/core/selection_manager.gd")
const _MESH_INSTANCE_SCRIPT := preload(
		"res://addons/go_build/core/go_build_mesh_instance.gd")

## The EditorPlugin reference — needed for undo/redo access.
var _plugin: EditorPlugin = null

## The GoBuildMeshInstance currently being edited.  Only set while editing.
var _edited_node: GoBuildMeshInstance = null

## True while a Godot drag-and-drop operation is in progress over this control.
var _drag_active: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS


func setup(plugin: EditorPlugin, edited_node: GoBuildMeshInstance) -> void:
	_plugin = plugin
	_edited_node = edited_node


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		_drag_active = true
	elif what == NOTIFICATION_DRAG_END:
		_drag_active = false
		if _edited_node != null and is_instance_valid(_edited_node) \
				and _edited_node.go_build_mesh != null:
			_convert_editor_material_overrides()


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if _edited_node == null or _edited_node.go_build_mesh == null:
		return false
	if data is Dictionary and data.has("type") and data["type"] == &"files":
		var files: Array = data.get("files", [])
		for f: String in files:
			var ext: String = f.to_lower()
			if ext.ends_with(".png") or ext.ends_with(".jpg") \
					or ext.ends_with(".jpeg") or ext.ends_with(".svg") \
					or ext.ends_with(".webp") or ext.ends_with(".bmp") \
					or ext.ends_with(".tres") or ext.ends_with(".res"):
				return true
	return false


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if _edited_node == null or _edited_node.go_build_mesh == null:
		return
	if not (data is Dictionary):
		return
	if not data.has("type") or data["type"] != &"files":
		return
	var files: Array = data.get("files", [])
	if files.is_empty():
		return

	var path: String = files[0]
	_apply_resource_to_selected_faces(path)


## Apply a texture or material resource to the selected faces (or all faces
## if no face selection exists).  This is the same logic used by the UV canvas
## drop handler and the material override converter.
func _apply_resource_to_selected_faces(path: String) -> void:
	if _edited_node == null or _edited_node.go_build_mesh == null:
		return
	if _plugin == null:
		return

	var gbm: GoBuildMesh = _edited_node.go_build_mesh
	var snapshot := gbm.take_snapshot()

	var sel_faces: Array[int] = []
	if _edited_node.selection.get_mode() == SelectionManager.Mode.FACE:
		sel_faces = _edited_node.selection.get_selected_faces()
	if sel_faces.is_empty():
		sel_faces.resize(gbm.faces.size())
		for i: int in gbm.faces.size():
			sel_faces[i] = i

	var mat: Material = null
	var mat_slot_idx: int = -1

	if path.to_lower().ends_with(".tres") or path.to_lower().ends_with(".res"):
		var loaded: Resource = load(path)
		if loaded is Material:
			mat = loaded as Material
		else:
			push_warning("GoBuild: Dropped file is not a Material resource: %s" % path)
			return
	else:
		var tex: Texture2D = load(path) as Texture2D
		if tex == null:
			push_warning("GoBuild: Could not load texture: %s" % path)
			return

		for i: int in gbm.material_slots.size():
			var slot_mat: Material = gbm.material_slots[i]
			if slot_mat is StandardMaterial3D:
				var smat: StandardMaterial3D = slot_mat as StandardMaterial3D
				if smat.albedo_texture != null \
						and smat.albedo_texture.resource_path == path:
					mat = smat
					mat_slot_idx = i
					break

		if mat == null:
			var new_mat := StandardMaterial3D.new()
			new_mat.albedo_texture = tex
			var tex_name: String = tex.resource_name
			if tex_name == "":
				tex_name = path.get_file().get_basename()
			new_mat.resource_name = tex_name
			mat = new_mat

	if mat_slot_idx < 0:
		mat_slot_idx = gbm.material_slots.size()
		gbm.material_slots.append(null)

	MaterialAssignOperation.apply_to_selected_faces(gbm, sel_faces, mat_slot_idx, mat)

	_edited_node.material_override = null
	_edited_node.bake_in_place()

	var ur: EditorUndoRedoManager = _plugin.get_undo_redo()
	ur.create_action("Apply Material to Faces (Drop)")
	ur.add_do_method(_edited_node, "restore_and_bake", gbm.take_snapshot())
	ur.add_undo_method(_edited_node, "restore_and_bake", snapshot)
	ur.commit_action()


## Convert any material overrides that Godot's editor drag-and-drop applied
## as a preview.  Called on [constant NOTIFICATION_DRAG_END] so the preview
## had time to render, and we now migrate it to GoBuild's face-level system.
##
## This also catches the case where Godot's built-in 3D viewport drop handler
## set [material_override] or [surface_override_material] instead of our
## [GoBuildMaterialDropOverlay._drop_data].
func _convert_editor_material_overrides() -> void:
	if _edited_node == null or _edited_node.go_build_mesh == null:
		return
	if not is_instance_valid(_edited_node):
		return

	var gbm: GoBuildMesh = _edited_node.go_build_mesh

	# 1. Convert material_override if set.
	var mat_override: Material = _edited_node.material_override
	if mat_override != null:
		var snapshot := gbm.take_snapshot()
		var all_faces: Array[int] = []
		all_faces.resize(gbm.faces.size())
		for i: int in gbm.faces.size():
			all_faces[i] = i
		MaterialAssignOperation.apply_to_selected_faces(gbm, all_faces, 0, mat_override)
		_edited_node.material_override = null
		_edited_node.bake_in_place()
		var ur: EditorUndoRedoManager = _plugin.get_undo_redo()
		ur.create_action("Apply Dropped Material to All Faces")
		ur.add_do_method(_edited_node, "restore_and_bake", gbm.take_snapshot())
		ur.add_undo_method(_edited_node, "restore_and_bake", snapshot)
		ur.commit_action()
		return

	# 2. Convert surface_override_material entries that are NOT cull overrides.
	if _edited_node._edit_cull_override:
		return
	if _edited_node.mesh == null:
		return
	var am := _edited_node.mesh as ArrayMesh
	if am == null:
		return
	for si: int in am.get_surface_count():
		var override_mat: Material = _edited_node.get_surface_override_material(si)
		if override_mat == null:
			continue
		var snapshot := gbm.take_snapshot()
		var face_indices: Array[int] = []
		for fi: int in gbm.faces.size():
			if gbm.faces[fi].material_index == si:
				face_indices.append(fi)
		if face_indices.is_empty():
			_edited_node.set_surface_override_material(si, null)
			continue
		MaterialAssignOperation.apply_to_selected_faces(gbm, face_indices, si, override_mat)
		_edited_node.set_surface_override_material(si, null)
		_edited_node.bake_in_place()
		var ur2: EditorUndoRedoManager = _plugin.get_undo_redo()
		ur2.create_action("Apply Dropped Material to Faces")
		ur2.add_do_method(_edited_node, "restore_and_bake", gbm.take_snapshot())
		ur2.add_undo_method(_edited_node, "restore_and_bake", snapshot)
		ur2.commit_action()
		return