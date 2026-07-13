## Converts Godot's built-in drag-and-drop material overrides into GoBuild's
## face-level material system.
##
## Godot's 3D viewport editor intercepts drag-and-drop before any GDScript
## overlay can, setting [material_override] (default drag) or
## [surface_override_material] (Ctrl+drag) on the MeshInstance3D as a preview.
##
## Strategy:
##   - During drag: [method cache_and_suppress] extracts and caches the material
##     Godot set, then clears the override so the preview doesn't show.
##   - On drop: [method convert_with_material] uses the cached material plus
##     a raycast to determine the target face and applies via GoBuild's system.
##   - Default drop: raycast to find the face under the cursor, apply the
##     material to that face (or all selected faces if a selection exists).
##   - Ctrl drop: apply to all faces sharing the same GoBuild material slot
##     as the hovered face.
##   - If raycasting fails: apply to all faces (last resort).
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


## Called each [method _process] frame while a drag is active.
## Extracts any material override Godot set, caches it (or keeps the previous
## cache if nothing new was set), and clears the override to suppress the
## full-object preview tint.
##
## Returns the cached material (which may be [param prev_cache] if Godot
## didn't set a new override this frame, or a newly extracted one).
static func cache_and_suppress(
		node: GoBuildMeshInstance,
		prev_cache: Material,
) -> Material:
	if node == null or node.go_build_mesh == null:
		return prev_cache
	# Check for editor-set overrides and extract the material.
	var mat: Material = _extract_override_material(node)
	if mat != null:
		_clear_overrides_no_bake(node)
		return mat
	# No new override this frame — keep the previous cache.
	return prev_cache


## Convert the cached material into GoBuild's face-level system, using
## [param ur] for undo/redo.  Called when the drag ends.
##
## [param camera] is used to raycast and find the face under the cursor.
## [param screen_pos] is the last known mouse position during the drag.
## [param ctrl_held] determines whether to apply to the hovered face only
## (default) or to all faces sharing the same material slot (Ctrl).
## [param mat] is the cached material from [method cache_and_suppress].
##
## Returns [code]true[/code] if a conversion was made.
static func convert_with_material(
		node: GoBuildMeshInstance,
		ur: EditorUndoRedoManager,
		camera: Camera3D,
		screen_pos: Vector2,
		ctrl_held: bool,
		mat: Material,
) -> bool:
	if node == null or node.go_build_mesh == null or mat == null:
		return false

	var gbm: GoBuildMesh = node.go_build_mesh

	# Determine which faces to target.
	var target_faces: Array[int] = _resolve_target_faces(
			node, gbm, camera, screen_pos, ctrl_held)

	print("GoBuildMaterialDropConverter: ctrl=%s screen_pos=%s target_faces=%d" % [
			ctrl_held, str(screen_pos), target_faces.size()])

	if target_faces.is_empty():
		# Fallback: apply to all faces.
		target_faces = _all_face_indices(gbm)

	# Determine the target slot.  For a single face, use its existing slot
	# so we only change the material without moving the face to a different slot.
	# For multiple faces (slot assignment), the hovered face's slot is used.
	var target_slot: int = 0
	if not target_faces.is_empty():
		target_slot = gbm.faces[target_faces[0]].material_index

	# Apply to GoBuild's face-level system.
	var snapshot := gbm.take_snapshot()
	MaterialAssignOperation.apply_to_selected_faces(gbm, target_faces, target_slot, mat)
	_clear_overrides(node)
	node.bake_in_place()

	ur.create_action("Apply Material to %d Face%s" % [
			target_faces.size(), "s" if target_faces.size() != 1 else ""])
	ur.add_do_method(node, "restore_and_bake", gbm.take_snapshot())
	ur.add_undo_method(node, "restore_and_bake", snapshot)
	ur.commit_action()
	return true


## Clear all editor-set material overrides on [param node].
## Called after conversion or when a drag ends without a cached material.
static func clear_overrides(node: GoBuildMeshInstance) -> void:
	_clear_overrides(node)


## Resolve which faces the material should be applied to.
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
		push_warning("GoBuildMaterialDropConverter: camera is null, cannot raycast")
		return []
	var face_idx: int = PickingHelper.find_nearest_face(
			camera, screen_pos, node, gbm)
	if face_idx < 0:
		push_warning("GoBuildMaterialDropConverter: raycast miss at screen_pos=%s" % str(screen_pos))
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
static func _extract_override_material(node: GoBuildMeshInstance) -> Material:
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


## Clear all editor-set material overrides on [param node].
static func _clear_overrides(node: GoBuildMeshInstance) -> void:
	_clear_overrides_no_bake(node)
	node.bake_in_place()


## Clear overrides without rebaking.  Used during drag suppression where
## we only need to remove the visual preview, not rebuild the mesh.
static func _clear_overrides_no_bake(node: GoBuildMeshInstance) -> void:
	if node == null:
		return
	if node.material_override != null:
		node.material_override = null
	if not node._edit_cull_override and node.mesh != null:
		var am := node.mesh as ArrayMesh
		if am != null:
			for si: int in am.get_surface_count():
				node.set_surface_override_material(si, null)