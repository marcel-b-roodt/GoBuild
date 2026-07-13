## Converts Godot's built-in drag-and-drop material overrides into GoBuild's
## face-level material system.
##
## Godot's 3D viewport editor intercepts drag-and-drop before any GDScript
## overlay can, setting [material_override] (default drag) or
## [surface_override_material] (Ctrl+drag) on the MeshInstance3D as a preview.
##
## Strategy:
##   - During drag: suppress Godot's full-object tint by clearing
##     [material_override], then show a per-surface preview by setting
##     [surface_override_material] on only the surface(s) under the cursor.
##     This is lightweight — no GoBuildMesh data model changes, no mesh rebuilds.
##   - On drop: clear all overrides, raycast to find the target face, and apply
##     the material permanently via GoBuild's face-level system with undo/redo.
##   - On cancel: clear all overrides, no changes to the mesh.
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
## the full-object tint, and shows a lightweight per-surface preview via
## [surface_override_material].
##
## Returns the cached material (null if no override found this frame or ever).
static func update_preview(
		node: GoBuildMeshInstance,
		prev_cached_mat: Material,
		camera: Camera3D,
		screen_pos: Vector2,
		ctrl_held: bool,
) -> Material:
	if node == null or node.go_build_mesh == null:
		return prev_cached_mat

	# Step 1: Extract any material override Godot set this frame.
	var mat: Material = extract_override_material(node)
	if mat != null:
		# New override found — cache it.
		prev_cached_mat = mat

	# Step 2: Always clear material_override (suppress full-object tint).
	# We'll set surface_override_material selectively for the preview instead.
	if node.material_override != null:
		node.material_override = null

	# Step 3: If we have a cached material, show per-surface preview.
	if prev_cached_mat == null:
		return prev_cached_mat

	# Clear any previous surface overrides from our preview.
	_clear_surface_overrides(node)

	# Raycast to find the face(s) under the cursor.
	var gbm: GoBuildMesh = node.go_build_mesh
	var target_slots: Array[int] = _resolve_target_slots(
			node, gbm, camera, screen_pos, ctrl_held)

	# Set the material on just those surfaces for a lightweight preview.
	var am: ArrayMesh = node.mesh as ArrayMesh
	if am == null:
		return prev_cached_mat
	for slot: int in target_slots:
		if slot < am.get_surface_count():
			node.set_surface_override_material(slot, prev_cached_mat)

	return prev_cached_mat


## Apply the cached material permanently when the drag ends with a drop.
## Clears all preview overrides first, then applies via GoBuild's face-level
## system with undo/redo.
static func apply_drop(
		node: GoBuildMeshInstance,
		ur: EditorUndoRedoManager,
		camera: Camera3D,
		screen_pos: Vector2,
		ctrl_held: bool,
		mat: Material,
) -> bool:
	if node == null or node.go_build_mesh == null or mat == null:
		return false

	# Clear all preview overrides.
	_clear_overrides(node)

	var gbm: GoBuildMesh = node.go_build_mesh

	# Determine which faces to target.
	var target_faces: Array[int] = _resolve_target_faces(
			node, gbm, camera, screen_pos, ctrl_held)

	if target_faces.is_empty():
		target_faces = _all_face_indices(gbm)

	var target_slot: int = 0
	if not target_faces.is_empty():
		target_slot = gbm.faces[target_faces[0]].material_index

	# Apply permanently via GoBuild's face-level system.
	var snapshot := gbm.take_snapshot()
	MaterialAssignOperation.apply_to_selected_faces(gbm, target_faces, target_slot, mat)
	node.bake_in_place()

	ur.create_action("Apply Material to %d Face%s" % [
			target_faces.size(), "s" if target_faces.size() != 1 else ""])
	ur.add_do_method(node, "restore_and_bake", gbm.take_snapshot())
	ur.add_undo_method(node, "restore_and_bake", snapshot)
	ur.commit_action()
	return true


## Cancel a drag: just clear all preview overrides. No data model changes
## were made during the drag, so nothing to restore.
static func cancel_preview(node: GoBuildMeshInstance) -> void:
	_clear_overrides(node)


## Clear all editor-set material overrides on [param node] and rebake.
static func clear_overrides(node: GoBuildMeshInstance) -> void:
	_clear_overrides(node)


## Determine which GoBuild material slots (and thus which baked surfaces)
## should show the preview material.
##   - Ctrl held: the slot of the hovered face.
##   - Default: the slot of the hovered face (single face preview).
##   - Face selection: the slots of all selected faces.
##   - Fallback: all slots (if raycast misses).
static func _resolve_target_slots(
		node: GoBuildMeshInstance,
		gbm: GoBuildMesh,
		camera: Camera3D,
		screen_pos: Vector2,
		_ctrl_held: bool,
) -> Array[int]:
	# If the user has faces selected in Face mode, collect their slots.
	if node.selection.get_mode() == SelectionManager.Mode.FACE:
		var sel: Array[int] = node.selection.get_selected_faces()
		if not sel.is_empty():
			var slots: Array[int] = []
			var seen: Dictionary = {}
			for fi: int in sel:
				var slot: int = gbm.faces[fi].material_index
				if not seen.has(slot):
					seen[slot] = true
					slots.append(slot)
			return slots

	# Raycast to find the face under the cursor.
	if camera == null:
		return _all_slots(gbm)
	var face_idx: int = PickingHelper.find_nearest_face(
			camera, screen_pos, node, gbm)
	if face_idx < 0:
		return _all_slots(gbm)

	var target_slot: int = gbm.faces[face_idx].material_index

	# Ctrl held: same slot — no extra work, just that one slot.
	# Default: same — just that one slot.
	return [target_slot]


## Resolve which faces the material should be *permanently* applied to on drop.
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


static func _all_slots(gbm: GoBuildMesh) -> Array[int]:
	var slots: Array[int] = []
	for i: int in gbm.material_slots.size():
		slots.append(i)
	return slots


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


## Clear all surface overrides (used to clear our own preview).
## Does NOT touch material_override — call sites handle that separately.
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


## Clear all editor-set material overrides on [param node] and rebake.
static func _clear_overrides(node: GoBuildMeshInstance) -> void:
	if node == null:
		return
	if node.material_override != null:
		node.material_override = null
	_clear_surface_overrides(node)
	node.bake_in_place()