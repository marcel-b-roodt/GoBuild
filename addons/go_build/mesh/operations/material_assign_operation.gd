## Assigns a material slot index to a set of faces.
##
## Sets [member GoBuildFace.material_index] on every face in [param face_indices]
## to [param material_index].  If [param material] is provided, it is also written
## into [member GoBuildMesh.material_slots] at that index; the slots array is
## grown with [code]null[/code] entries as needed.
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
static func apply(
		mesh: GoBuildMesh,
		face_indices: Array[int],
		material_index: int,
		material: Material = null,
) -> void:
	if mesh == null or material_index < 0:
		return

	# Ensure material_slots is large enough.
	while mesh.material_slots.size() <= material_index:
		mesh.material_slots.append(null)

	# Optionally set the material object on the slot.
	if material != null:
		mesh.material_slots[material_index] = material

	for fi: int in face_indices:
		if fi < 0 or fi >= mesh.faces.size():
			continue
		mesh.faces[fi].material_index = material_index
