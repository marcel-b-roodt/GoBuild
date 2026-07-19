## Consolidates duplicate material slots in a [GoBuildMesh].
##
## Merges material slots that reference the same [Material] resource (or are both
## [code]null[/code]) into a single slot, reindexing all faces to point at the
## consolidated slot.  Empty slots (no faces referencing them) are also removed.
##
## This is a pure data operation — it does not bake or trigger any side-effects.
## Wrap it in [method GoBuildMeshInstance.apply_operation] to get undo/redo.
class_name ConsolidateSlotsOperation
extends RefCounted

# Self-preloads — dependency order:
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")


## Merge duplicate material slots and remove empty slots.
##
## After this operation:
## - Each unique [Material] (or [code]null[/code]) appears in exactly one slot.
## - All faces' [member GoBuildFace.material_index] values are remapped.
## - [member GoBuildMesh.material_slots] has no duplicate entries and no empty
##   slots (slots with zero face references).
## - [method GoBuildMesh.rebuild_edges] is called at the end.
static func apply(mesh: GoBuildMesh) -> void:
	if mesh == null or mesh.faces.is_empty():
		return

	# Step 1: Build old→new slot mapping by deduplicating materials.
	# Two slots are "duplicates" if they hold the same Material resource
	# (or both are null).
	var old_to_new: Array[int] = []
	old_to_new.resize(mesh.material_slots.size())
	var seen: Dictionary = {}  # Material (or null) → new slot index
	var new_slots: Array[Material] = []
	var next_new: int = 0

	for old_idx: int in mesh.material_slots.size():
		var mat: Material = mesh.material_slots[old_idx]
		if seen.has(mat):
			old_to_new[old_idx] = seen[mat]
		else:
			seen[mat] = next_new
			old_to_new[old_idx] = next_new
			new_slots.append(mat)
			next_new += 1

	# Step 2: Remap all face material_index values.
	for fi: int in mesh.faces.size():
		var old_mi: int = mesh.faces[fi].material_index
		if old_mi >= 0 and old_mi < old_to_new.size():
			mesh.faces[fi].material_index = old_to_new[old_mi]

	# Step 3: Remove slots that no faces reference (empty slots).
	# Count face references per new slot index.
	var ref_count: Dictionary = {}
	for fi: int in mesh.faces.size():
		var mi: int = mesh.faces[fi].material_index
		ref_count[mi] = ref_count.get(mi, 0) + 1

	# Build the final compact slot array, remapping again to skip empty slots.
	var final_slots: Array[Material] = []
	var compact_map: Dictionary = {}  # new_slot_idx → final_idx
	var final_idx: int = 0
	for ni: int in new_slots.size():
		if ref_count.get(ni, 0) > 0:
			compact_map[ni] = final_idx
			final_slots.append(new_slots[ni])
			final_idx += 1

	# Remap face material_index to the final compact indices.
	for fi: int in mesh.faces.size():
		var mi: int = mesh.faces[fi].material_index
		if compact_map.has(mi):
			mesh.faces[fi].material_index = compact_map[mi]
		else:
			mesh.faces[fi].material_index = 0

	# Step 4: Replace material_slots with the consolidated array.
	mesh.material_slots.clear()
	for mat: Material in final_slots:
		mesh.material_slots.append(mat)

	mesh.rebuild_edges()