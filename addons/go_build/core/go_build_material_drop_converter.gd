## Converts Godot's built-in drag-and-drop material overrides into GoBuild's
## face-level material system.
##
## Godot's 3D viewport editor intercepts drag-and-drop before any GDScript
## overlay can, setting [material_override] (default drag) or
## [surface_override_material] (Ctrl+drag) on the MeshInstance3D.  This helper
## detects those overrides after the drop completes and migrates them into
## [GoBuildMesh.material_slots] + per-face [GoBuildFace.material_index].
##
## Conversion strategy:
##   - [material_override] (default drag): apply the material to ALL faces.
##   - [surface_override_material] (Ctrl drag): apply to faces that currently
##     use that surface index as their material slot.
##   - Drag cancel (no override): nothing to convert, so we clean up.
##
## After conversion, the override is cleared and the mesh is rebaked with the
## GoBuild material system.  Each conversion creates an undo/redo action.
@tool
class_name GoBuildMaterialDropConverter
extends RefCounted

# Self-preloads — dependency order:
const _FACE_SCRIPT             := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MESH_SCRIPT             := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _MATERIAL_ASSIGN_SCRIPT  := preload(
		"res://addons/go_build/mesh/operations/material_assign_operation.gd")
const _SELECTION_MGR_SCRIPT   := preload(
		"res://addons/go_build/core/selection_manager.gd")
const _MESH_INSTANCE_SCRIPT    := preload(
		"res://addons/go_build/core/go_build_mesh_instance.gd")


## Check whether [param node] has any material overrides that were likely
## set by Godot's editor drag-and-drop.  Returns [code]true[/code] if:
##   - [material_override] is non-null, OR
##   - Any [surface_override_material] is set while cull overrides are NOT active
static func has_editor_override(node: GoBuildMeshInstance) -> bool:
	if node == null or node.go_build_mesh == null:
		return false
	if node.material_override != null:
		return true
	if node._edit_cull_override:
		return false
	if node.mesh == null:
		return false
	var am := node.mesh as ArrayMesh
	if am == null:
		return false
	for si: int in am.get_surface_count():
		if node.get_surface_override_material(si) != null:
			return true
	return false


## Convert any editor-set material overrides on [param node] into GoBuild's
## face-level material system, using [param ur] for undo/redo.
##
## Call this from the plugin when a [signal NOTIFICATION_DRAG_END] is received
## or whenever [method has_editor_override] returns [code]true[/code].
##
## Returns [code]true[/code] if a conversion was made, [code]false[/code] if
## nothing needed converting.
static func convert(node: GoBuildMeshInstance, ur: EditorUndoRedoManager) -> bool:
	if node == null or node.go_build_mesh == null:
		return false
	if not has_editor_override(node):
		# Drag was cancelled or no override was set — just clean up.
		_clear_overrides(node)
		return false

	var gbm: GoBuildMesh = node.go_build_mesh

	# 1. Convert material_override (default drag — applies to all faces).
	var mat_override: Material = node.material_override
	if mat_override != null:
		var snapshot := gbm.take_snapshot()
		var all_faces: Array[int] = []
		all_faces.resize(gbm.faces.size())
		for i: int in gbm.faces.size():
			all_faces[i] = i
		MaterialAssignOperation.apply_to_selected_faces(gbm, all_faces, 0, mat_override)
		node.material_override = null
		node.bake_in_place()
		ur.create_action("Apply Dropped Material to All Faces")
		ur.add_do_method(node, "restore_and_bake", gbm.take_snapshot())
		ur.add_undo_method(node, "restore_and_bake", snapshot)
		ur.commit_action()
		return true

	# 2. Convert surface_override_material entries (Ctrl drag — per-surface).
	if node._edit_cull_override:
		return false
	if node.mesh == null:
		return false
	var am := node.mesh as ArrayMesh
	if am == null:
		return false
	for si: int in am.get_surface_count():
		var override_mat: Material = node.get_surface_override_material(si)
		if override_mat == null:
			continue
		var snapshot := gbm.take_snapshot()
		var face_indices: Array[int] = []
		for fi: int in gbm.faces.size():
			if gbm.faces[fi].material_index == si:
				face_indices.append(fi)
		if face_indices.is_empty():
			node.set_surface_override_material(si, null)
			continue
		MaterialAssignOperation.apply_to_selected_faces(
				gbm, face_indices, si, override_mat)
		node.set_surface_override_material(si, null)
		node.bake_in_place()
		ur.create_action("Apply Dropped Material to Slot %d Faces" % si)
		ur.add_do_method(node, "restore_and_bake", gbm.take_snapshot())
		ur.add_undo_method(node, "restore_and_bake", snapshot)
		ur.commit_action()
		return true

	return false


## Clear all editor-set material overrides on [param node] without converting
## them.  Used when a drag was cancelled (no drop) or when the override was
## already stale.
static func _clear_overrides(node: GoBuildMeshInstance) -> void:
	if node == null:
		return
	if node.material_override != null:
		node.material_override = null
	if not node._edit_cull_override and node.mesh != null:
		var am := node.mesh as ArrayMesh
		if am != null:
			for si: int in am.get_surface_count():
				node.set_surface_override_material(si, null)
	node.bake_in_place()