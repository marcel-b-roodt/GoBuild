## Transparent overlay on the 3D viewport that intercepts drag-and-drop of
## textures and materials from the FileSystem dock and routes them through
## GoBuild's face-level material system.
##
## Drop behaviour:
##   - Default drop: apply the material to the face under the cursor (or to all
##     selected faces if a face selection exists).
##   - Ctrl+drop: apply the material to ALL faces sharing the same material slot
##     as the hovered face.
##   - If no GoBuildMeshInstance is being edited, the drop falls through to
##     Godot's default handler.
##
## On drag cancel (mouse leaves viewport), any Godot-applied
## material_override or surface_override_material is reverted.
@tool
class_name GoBuildMaterialDropOverlay
extends Control

# Self-preloads — dependency order:
const _FACE_SCRIPT             := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MESH_SCRIPT             := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _MATERIAL_ASSIGN_SCRIPT  := preload(
		"res://addons/go_build/mesh/operations/material_assign_operation.gd")
const _SELECTION_MGR_SCRIPT   := preload(
		"res://addons/go_build/core/selection_manager.gd")
const _MESH_INSTANCE_SCRIPT    := preload(
		"res://addons/go_build/core/go_build_mesh_instance.gd")
const _PICKING_SCRIPT           := preload("res://addons/go_build/core/picking_helper.gd")

## The EditorPlugin reference — needed for undo/redo access and the 3D camera.
var _plugin: EditorPlugin = null

## The GoBuildMeshInstance currently being edited.  Only set while editing.
var _edited_node: GoBuildMeshInstance = null

## True while a Godot drag-and-drop operation is in progress.
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
		# If the drag was cancelled (no drop occurred) or Godot's built-in
		# handler set overrides, clean those up.
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


func _drop_data(at_position: Vector2, data: Variant) -> void:
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
	var faces: Array[int] = _resolve_target_faces(at_position)
	if faces.is_empty():
		# Fallback: apply to all faces if raycasting fails.
		faces = _all_face_indices()

	_commit_drop(path, faces)


# ---------------------------------------------------------------------------
# Resolve which faces the drop should target
# ---------------------------------------------------------------------------

## Determine the face indices that should receive the dropped material.
##   - Ctrl held: all faces sharing the same material slot as the hovered face.
##   - Default: the single face under the cursor (or existing face selection).
func _resolve_target_faces(position: Vector2) -> Array[int]:
	if _edited_node == null or _edited_node.go_build_mesh == null:
		return []
	var gbm: GoBuildMesh = _edited_node.go_build_mesh
	if gbm.faces.is_empty():
		return []

	# If the user has faces selected in Face mode, use that selection.
	if _edited_node.selection.get_mode() == SelectionManager.Mode.FACE:
		var sel: Array[int] = _edited_node.selection.get_selected_faces()
		if not sel.is_empty():
			return sel

	# No selection — raycast to find the face under the cursor.
	var camera: Camera3D = _get_viewport_camera()
	if camera == null:
		return _all_face_indices()

	var face_idx: int = PickingHelper.find_nearest_face(
			camera, position, _edited_node, gbm)
	if face_idx < 0:
		return _all_face_indices()

	# Ctrl held: apply to all faces with the same material slot.
	if Input.is_key_pressed(KEY_CTRL):
		var target_slot: int = gbm.faces[face_idx].material_index
		var result: Array[int] = []
		for fi: int in gbm.faces.size():
			if gbm.faces[fi].material_index == target_slot:
				result.append(fi)
		return result

	return [face_idx]


func _all_face_indices() -> Array[int]:
	var gbm: GoBuildMesh = _edited_node.go_build_mesh
	var faces: Array[int] = []
	faces.resize(gbm.faces.size())
	for i: int in gbm.faces.size():
		faces[i] = i
	return faces


func _get_viewport_camera() -> Camera3D:
	var vp: SubViewport = EditorInterface.get_editor_viewport_3d(0)
	if vp == null:
		return null
	return vp.get_camera_3d()


# ---------------------------------------------------------------------------
# Load a material from a file path
# ---------------------------------------------------------------------------

func _load_material(path: String) -> Dictionary:
	var gbm: GoBuildMesh = _edited_node.go_build_mesh
	var mat: Material = null
	var mat_slot_idx: int = -1

	if path.to_lower().ends_with(".tres") or path.to_lower().ends_with(".res"):
		var loaded: Resource = load(path)
		if loaded is Material:
			mat = loaded as Material
		else:
			push_warning("GoBuild: Dropped file is not a Material resource: %s" % path)
			return {}
	else:
		var tex: Texture2D = load(path) as Texture2D
		if tex == null:
			push_warning("GoBuild: Could not load texture: %s" % path)
			return {}

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

	return {"material": mat, "slot_index": mat_slot_idx}


# ---------------------------------------------------------------------------
# Commit: apply the material permanently with undo/redo
# ---------------------------------------------------------------------------

func _commit_drop(path: String, faces: Array[int]) -> void:
	if _edited_node == null or _edited_node.go_build_mesh == null:
		return
	if _plugin == null:
		return

	var gbm: GoBuildMesh = _edited_node.go_build_mesh
	var snapshot := gbm.take_snapshot()

	var result: Dictionary = _load_material(path)
	if result.is_empty():
		return
	var mat: Material = result["material"]
	var mat_slot_idx: int = result["slot_index"]

	MaterialAssignOperation.apply_to_selected_faces(gbm, faces, mat_slot_idx, mat)

	# Clear any Godot-applied material_override that may have been set as a
	# drag preview during the drag phase.
	_edited_node.material_override = null
	_edited_node.bake_in_place()

	var ur: EditorUndoRedoManager = _plugin.get_undo_redo()
	var ctrl_held: bool = Input.is_key_pressed(KEY_CTRL)
	ur.create_action("Apply Material to %s Face%s" % [
			str(faces.size()), "s" if faces.size() != 1 else ""])
	ur.add_do_method(_edited_node, "restore_and_bake", gbm.take_snapshot())
	ur.add_undo_method(_edited_node, "restore_and_bake", snapshot)
	ur.commit_action()


# ---------------------------------------------------------------------------
# Fallback: convert Godot's built-in material overrides
# ---------------------------------------------------------------------------

## Convert any material overrides that Godot's editor drag-and-drop applied.
## Called on [constant NOTIFICATION_DRAG_END].  If the drag was cancelled
## (no drop), this clears the preview overrides.  If Godot's built-in handler
## set overrides that our overlay didn't catch, this converts them.
func _convert_editor_material_overrides() -> void:
	if _edited_node == null or _edited_node.go_build_mesh == null:
		return
	if not is_instance_valid(_edited_node):
		return

	# Always clear material_override — it was set by Godot's drag preview and
	# is either stale (drag cancelled) or has already been converted by our
	# _drop_data handler.
	if _edited_node.material_override != null:
		_edited_node.material_override = null

	# Clear non-cull surface overrides (also drag preview leftovers).
	if not _edited_node._edit_cull_override:
		if _edited_node.mesh != null:
			var am := _edited_node.mesh as ArrayMesh
			if am != null:
				for si: int in am.get_surface_count():
					_edited_node.set_surface_override_material(si, null)

	_edited_node.bake_in_place()