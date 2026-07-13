## Converts Godot's built-in drag-and-drop material overrides into GoBuild's
## face-level material system.
##
## Godot's 3D viewport editor intercepts drag-and-drop before any GDScript
## overlay can, setting [material_override] (default drag) or
## [surface_override_material] (Ctrl+drag) on the MeshInstance3D as a preview.
##
## Strategy:
##   - During drag: suppress Godot's full-object tint, cache the material, and
##     show a per-face/per-slot preview by temporarily modifying the GoBuildMesh.
##   - On drop: restore the snapshot and apply the material permanently via
##     GoBuild's face-level system with undo/redo.
##   - On cancel: restore the snapshot and bake.
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
## Finds any GoBuildMeshInstance that Godot set an override on, extracts and
## caches the material, clears the override to suppress the full-object tint,
## and shows a per-face preview by temporarily modifying the mesh.
##
## Returns the target node that has the override, or [param prev_target] if
## no new override was found this frame.
static func cache_and_suppress(
		node: GoBuildMeshInstance,
		prev_cache: Material,
		camera: Camera3D,
		screen_pos: Vector2,
		ctrl_held: bool,
		snapshot: Dictionary,
) -> Dictionary:
	var result := {
		"material": prev_cache,
		"snapshot": snapshot,
		"target_faces": [] as Array[int],
	}
	if node == null or node.go_build_mesh == null:
		return result

	# Extract any editor-set override material.
	var mat: Material = extract_override_material(node)
	if mat != null:
		# First frame with override: take a snapshot before we modify anything.
		if result["snapshot"] == null or result["snapshot"].is_empty():
			result["snapshot"] = node.go_build_mesh.take_snapshot()
		# Clear the override so Godot's preview doesn't show.
		_clear_overrides_no_bake(node)
		result["material"] = mat

	# If we have a cached material and a snapshot, show the preview.
	var cached_mat: Material = result["material"]
	if cached_mat == null or result["snapshot"] == null or camera == null:
		return result

	# Restore from snapshot before applying the preview so we don't accumulate
	# changes across frames.
	node.go_build_mesh.restore_snapshot(result["snapshot"])

	# Raycast to find the face under the cursor.
	var target_faces: Array[int] = _resolve_target_faces(
			node, node.go_build_mesh, camera, screen_pos, ctrl_held)
	result["target_faces"] = target_faces

	if target_faces.is_empty():
		# Fallback: apply to all faces for the preview.
		target_faces = _all_face_indices(node.go_build_mesh)

	var target_slot: int = 0
	if not target_faces.is_empty():
		target_slot = node.go_build_mesh.faces[target_faces[0]].material_index

	MaterialAssignOperation.apply_to_selected_faces(
			node.go_build_mesh, target_faces, target_slot, cached_mat)
	node.bake_in_place()
	return result


## Convert the cached material into GoBuild's face-level system, using
## [param ur] for undo/redo.  Called when the drag ends (drop).
##
## Restores the mesh from the snapshot first, then applies the material
## permanently and registers an undo/redo action.
static func convert_with_material(
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

	var gbm: GoBuildMesh = node.go_build_mesh

	# Restore from snapshot to get a clean state before permanent apply.
	if snapshot != null and not snapshot.is_empty():
		gbm.restore_snapshot(snapshot)

	# Determine which faces to target.
	var target_faces: Array[int] = _resolve_target_faces(
			node, gbm, camera, screen_pos, ctrl_held)

	if target_faces.is_empty():
		# Fallback: apply to all faces.
		target_faces = _all_face_indices(gbm)

	var target_slot: int = 0
	if not target_faces.is_empty():
		target_slot = gbm.faces[target_faces[0]].material_index

	# Take the undo snapshot from the restored (pre-preview) state.
	var undo_snapshot := gbm.take_snapshot()

	# Apply permanently.
	MaterialAssignOperation.apply_to_selected_faces(gbm, target_faces, target_slot, mat)
	_clear_overrides(node)
	node.bake_in_place()

	ur.create_action("Apply Material to %d Face%s" % [
			target_faces.size(), "s" if target_faces.size() != 1 else ""])
	ur.add_do_method(node, "restore_and_bake", gbm.take_snapshot())
	ur.add_undo_method(node, "restore_and_bake", undo_snapshot)
	ur.commit_action()
	return true


## Cancel a drag: restore from snapshot and clear overrides.
static func cancel_drag(node: GoBuildMeshInstance, snapshot: Dictionary) -> void:
	if node == null:
		return
	if node.go_build_mesh != null and snapshot != null and not snapshot.is_empty():
		node.go_build_mesh.restore_snapshot(snapshot)
		node.bake_in_place()
	_clear_overrides(node)


## Clear all editor-set material overrides on [param node] and rebake.
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


## Clear overrides and rebake.
static func _clear_overrides(node: GoBuildMeshInstance) -> void:
	_clear_overrides_no_bake(node)
	if node != null:
		node.bake_in_place()


## Clear overrides without rebaking.  Used during drag suppression where
## we rebake after applying the preview instead.
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


## Scan the scene tree for any GoBuildMeshInstance that has an editor-set
## material override (material_override or surface_override_material).
## Returns the first one found, or null.
static func find_node_with_override(scene_root: Node) -> GoBuildMeshInstance:
	if scene_root == null:
		return null
	var candidates: Array[Node] = scene_root.find_children(
			"*", "GoBuildMeshInstance", true, false)
	for child: Node in candidates:
		var gbi: GoBuildMeshInstance = child as GoBuildMeshInstance
		if gbi == null or gbi.go_build_mesh == null:
			continue
		if gbi.material_override != null:
			return gbi
		if gbi._edit_cull_override:
			continue
		if gbi.mesh != null:
			var am := gbi.mesh as ArrayMesh
			if am != null:
				for si: int in am.get_surface_count():
					if gbi.get_surface_override_material(si) != null:
						return gbi
	return null