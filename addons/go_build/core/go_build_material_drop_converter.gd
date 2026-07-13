## Converts Godot's built-in drag-and-drop material overrides into GoBuild's
## face-level material system.
##
## Godot's 3D viewport editor intercepts drag-and-drop before any GDScript
## overlay can, setting [material_override] (default drag) or
## [surface_override_material] (Ctrl+drag) on the MeshInstance3D as a preview.
##
## Strategy:
##   - During drag: suppress Godot's full-object tint, take a snapshot of the
##     GoBuildMesh, then each frame: restore from snapshot, apply the material
##     to the hovered face(s), and rebake.  This gives a true per-face preview.
##   - On drop: restore from snapshot, apply permanently with undo/redo.
##   - On cancel: restore from snapshot and rebake (back to original state).
##   - Default drop: raycast to find the face under the cursor, apply the
##     material to that face (or all selected faces if a selection exists).
##   - Ctrl drop: apply to all faces sharing the same GoBuild material slot
##     as the hovered face.
##   - If raycasting fails: apply to all faces (last resort).
##
## Only operates on the plugin's [_edited_node].  If the user drops onto a
## GoBuildMeshInstance that is not being edited, Godot's native system handles
## it (setting [material_override] or [surface_override_material] as usual).
@tool
class_name GoBuildMaterialDropConverter
extends RefCounted

# Self-preloads — dependency order:
const _FACE_SCRIPT             := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MESH_SCRIPT             := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _MATERIAL_ASSIGN_SCRIPT := preload(
		"res://addons/go_build/mesh/operations/material_assign_operation.gd")
const _SELECTION_MGR_SCRIPT  := preload(
		"res://addons/go_build/core/selection_manager.gd")
const _MESH_INSTANCE_SCRIPT   := preload(
		"res://addons/go_build/core/go_build_mesh_instance.gd")
const _PICKING_SCRIPT          := preload("res://addons/go_build/core/picking_helper.gd")


## Called each [method _process] frame while a drag is active on the
## [_edited_node].  Extracts the material Godot set as an override, suppresses
## the full-object tint, and shows a per-face preview by modifying the
## GoBuildMesh data model and rebaking.
##
## [param snapshot] is the GoBuildMesh snapshot taken before the drag started.
## It is restored each frame before applying the preview so changes never
## accumulate.  If [param snapshot] is empty, a new one is taken.
##
## Returns a Dictionary with "material" (cached Material) and "snapshot"
## (the GoBuildMesh snapshot to pass back on the next frame or on drop/cancel).
static func update_preview(
		node: GoBuildMeshInstance,
		prev_cached_mat: Material,
		snapshot: Dictionary,
		camera: Camera3D,
		screen_pos: Vector2,
		ctrl_held: bool,
) -> Dictionary:
	var result := {
		"material": prev_cached_mat,
		"snapshot": snapshot,
	}
	if node == null or node.go_build_mesh == null:
		return result

	# Extract any material override Godot set this frame.
	var mat: Material = extract_override_material(node)
	if mat != null:
		prev_cached_mat = mat
		result["material"] = mat

	# Suppress Godot's full-object tint.
	if node.material_override != null:
		node.material_override = null

	# Also clear any surface overrides Godot may have set (Ctrl+drag).
	_clear_surface_overrides(node)

	if prev_cached_mat == null:
		return result

	# Take a snapshot on the first frame we have a material, if not already
	# taken.  This captures the state before any preview modifications.
	if snapshot.is_empty():
		snapshot = node.go_build_mesh.take_snapshot()
		result["snapshot"] = snapshot

	# Restore from snapshot so preview changes never accumulate.
	node.go_build_mesh.restore_snapshot(snapshot)

	# Determine which faces to preview.
	var gbm: GoBuildMesh = node.go_build_mesh
	var target_faces: Array[int] = _resolve_target_faces(
			node, gbm, camera, screen_pos, ctrl_held)
	if target_faces.is_empty():
		target_faces = _all_face_indices(gbm)

	var target_slot: int = 0
	if not target_faces.is_empty():
		target_slot = gbm.faces[target_faces[0]].material_index

	# Apply preview to the GoBuildMesh data model and rebake.
	MaterialAssignOperation.apply_to_selected_faces(
			gbm, target_faces, target_slot, prev_cached_mat)
	node.bake_in_place()

	return result


## Apply the cached material permanently when the drag ends with a drop.
## Restores from snapshot first to get a clean state, then applies via
## GoBuild's face-level system with undo/redo.
static func apply_drop(
		node: GoBuildMeshInstance,
		ur: EditorUndoRedoManager,
		camera: Camera3D,
		screen_pos: Vector2,
		ctrl_held: bool,
		mat: Material,
		snapshot: Dictionary,
) -> bool:
	if node == null or node.go_build_mesh == null or mat == null:
		return false

	# Clear all preview overrides.
	_clear_overrides_no_bake(node)

	var gbm: GoBuildMesh = node.go_build_mesh

	# Restore from snapshot to get a clean pre-preview state.
	if not snapshot.is_empty():
		gbm.restore_snapshot(snapshot)

	# Determine which faces to target permanently.
	var target_faces: Array[int] = _resolve_target_faces(
			node, gbm, camera, screen_pos, ctrl_held)

	if target_faces.is_empty():
		target_faces = _all_face_indices(gbm)

	var target_slot: int = 0
	if not target_faces.is_empty():
		target_slot = gbm.faces[target_faces[0]].material_index

	# Take undo snapshot from the clean state.
	var undo_snapshot := gbm.take_snapshot()

	# Apply permanently.
	MaterialAssignOperation.apply_to_selected_faces(gbm, target_faces, target_slot, mat)
	node.bake_in_place()

	ur.create_action("Apply Material to %d Face%s" % [
			target_faces.size(), "s" if target_faces.size() != 1 else ""])
	ur.add_do_method(node, "restore_and_bake", gbm.take_snapshot())
	ur.add_undo_method(node, "restore_and_bake", undo_snapshot)
	ur.commit_action()
	return true


## Cancel a drag: restore from snapshot and rebake to undo all preview changes.
static func cancel_preview(node: GoBuildMeshInstance, snapshot: Dictionary) -> void:
	if node == null:
		return
	if node.go_build_mesh != null and not snapshot.is_empty():
		node.go_build_mesh.restore_snapshot(snapshot)
		node.bake_in_place()
	_clear_overrides_no_bake(node)


## Clear all editor-set material overrides on [param node] and rebake.
static func clear_overrides(node: GoBuildMeshInstance) -> void:
	_clear_overrides(node)


## Resolve which faces the material should be applied to (for both preview
## and permanent application).
##   - Ctrl held: all faces sharing the same GoBuild material slot as the
##     hovered face.
##   - Default: the single face under the cursor, or existing face selection.
static func _resolve_target_faces(
		node: GoBuildMeshInstance,
		gbm: GoBuildMesh,
		camera: Camera3D,
		screen_pos: Vector2,
		ctrl_held: bool,
) -> Array[int]:
	# If the user has faces selected in Face mode, use that selection.
	if node.selection.get_mode() == SelectionManager.Mode.FACE:
		var sel: Array[int] = node.selection.get_selected_faces()
		if not sel.is_empty():
			return sel

	# Raycast to find the face under the cursor.
	if camera == null:
		return []
	var face_idx: int = PickingHelper.find_nearest_face(
			camera, screen_pos, node, gbm)
	if face_idx < 0:
		return []

	# Ctrl held: apply to all faces with the same material slot.
	if ctrl_held:
		var target_slot: int = gbm.faces[face_idx].material_index
		var result: Array[int] = []
		for fi: int in gbm.faces.size():
			if gbm.faces[fi].material_index == target_slot:
				result.append(fi)
		return result

	return [face_idx]


static func _all_face_indices(gbm: GoBuildMesh) -> Array[int]:
	var faces: Array[int] = []
	faces.resize(gbm.faces.size())
	for i: int in gbm.faces.size():
		faces[i] = i
	return faces


## Extract the material that Godot's editor set as an override.
## For material_override: returns it directly.
## For surface_override_material: returns the first non-null one.
## Public so the plugin can check whether a node has an override.
static func extract_override_material(node: GoBuildMeshInstance) -> Material:
	var mat_override: Material = node.material_override
	if mat_override != null:
		return mat_override
	if node.mesh == null:
		return null
	var am := node.mesh as ArrayMesh
	if am == null:
		return null
	for si: int in am.get_surface_count():
		var override_mat: Material = node.get_surface_override_material(si)
		if override_mat != null:
			return override_mat
	return null


## Clear surface overrides only (preview cleanup during drag).
static func _clear_surface_overrides(node: GoBuildMeshInstance) -> void:
	if node == null:
		return
	if node._edit_cull_override:
		return
	if node.mesh == null:
		return
	var am := node.mesh as ArrayMesh
	if am == null:
		return
	for si: int in am.get_surface_count():
		node.set_surface_override_material(si, null)


## Clear overrides without rebaking.  Used when we're about to rebake anyway.
static func _clear_overrides_no_bake(node: GoBuildMeshInstance) -> void:
	if node == null:
		return
	if node.material_override != null:
		node.material_override = null
	_clear_surface_overrides(node)


## Clear all editor-set material overrides on [param node] and rebake.
static func _clear_overrides(node: GoBuildMeshInstance) -> void:
	_clear_overrides_no_bake(node)
	if node != null:
		node.bake_in_place()