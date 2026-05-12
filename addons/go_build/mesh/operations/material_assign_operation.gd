## Assigns a material slot index to a set of faces.
##
## Sets [member GoBuildFace.material_index] on every face in [param face_indices]
## to [param material_index].  If [param material] is provided, it is also written
## into [member GoBuildMesh.material_slots] at that index; the slots array is
## grown with [code]null[/code] entries as needed.
##
## Use [method apply_to_selected_faces] when you want to apply a material to
## only the selected faces — it automatically preserves the original material
## for any unselected faces that share the same slot.
##
## The operation is pure data — it does not bake or trigger any side-effects.
## Wrap it in [method GoBuildMeshInstance.apply_operation] to get undo/redo.
class_name MaterialAssignOperation
extends RefCounted

# Self-preloads — dependency order:
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")


## Assign [param material_index] to [param face_indices] on [param mesh].
##
## If [param material] is non-null it is written into
## [member GoBuildMesh.material_slots] at [param material_index].
## [member GoBuildMesh.material_slots] is grown with [code]null[/code] entries
## until it is large enough to hold the index.
##
## [b]Warning:[/b] This changes the material object in the slot, which affects
## ALL faces referencing that slot — not just the faces in [param face_indices].
## Use [method apply_to_selected_faces] for face-selection-safe assignment.
static func apply(
		mesh: GoBuildMesh,
		face_indices: Array[int],
		material_index: int,
		material: Material = null,
) -> void:
	if mesh == null or material_index < 0:
		return

	while mesh.material_slots.size() <= material_index:
		mesh.material_slots.append(null)

	if material != null:
		mesh.material_slots[material_index] = material

	for fi: int in face_indices:
		if fi < 0 or fi >= mesh.faces.size():
			continue
		mesh.faces[fi].material_index = material_index


## Assign [param material] to only the selected faces on [param mesh].
##
## If unselected faces currently share the same slot, they are migrated to a
## new slot that retains the original material.  This prevents the common
## issue where all faces default to [code]material_index 0[/code] and changing
## slot 0's material accidentally affects the entire mesh.
##
## If no unselected faces share the slot, this behaves identically to
## [method apply].
static func apply_to_selected_faces(
		mesh: GoBuildMesh,
		selected_face_indices: Array[int],
		target_slot: int,
		material: Material,
) -> void:
	if mesh == null or material == null:
		return

	var selected_set: Dictionary = {}
	for fi: int in selected_face_indices:
		selected_set[fi] = true

	var needs_split: bool = false
	var original_material: Material = null
	if target_slot < mesh.material_slots.size():
		original_material = mesh.material_slots[target_slot]
		for fi: int in mesh.faces.size():
			if fi in selected_set:
				continue
			if mesh.faces[fi].material_index == target_slot:
				needs_split = true
				break

	if needs_split and original_material != material:
		var new_slot: int = mesh.material_slots.size()
		mesh.material_slots.append(original_material)
		for fi: int in mesh.faces.size():
			if fi in selected_set:
				continue
			if mesh.faces[fi].material_index == target_slot:
				mesh.faces[fi].material_index = new_slot

	while mesh.material_slots.size() <= target_slot:
		mesh.material_slots.append(null)
	mesh.material_slots[target_slot] = material

	for fi: int in selected_face_indices:
		if fi < 0 or fi >= mesh.faces.size():
			continue
		mesh.faces[fi].material_index = target_slot