## Per-face auto transparency remap for the metre blockout material.
##
## When a paint commit leaves a face's vertices with alpha < 1.0, faces whose
## slot holds the shared [code]go_build_material.tres[/code] are remapped to the
## shared [code]go_build_material_alpha.tres[/code] — one pre-shipped material,
## never a duplicate — so the opaque resource itself stays untouched and
## transparency becomes per-face, never global.  Painted alpha back to 1.0
## remaps faces to the original opaque material (symmetric revert).
##
## Matching is by [code]resource_name[/code] only — custom materials are never
## touched and no material metadata is read or written.
class_name AlphaRemapOperation
extends RefCounted

# Self-preloads — dependency order.
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")

## The only opaque material the automatic remap touches (matched by
## resource_name — matches survive .tres moves and the un-filed duplicates
## tests create).
const METRE_MATERIAL_NAME := "go_build_metre"

## The shared transparent twin the remap assigns (matched by resource_name).
const ALPHA_MATERIAL_NAME := "go_build_metre_alpha"

## Canonical path of the shared transparent metre material.
const _ALPHA_MATERIAL_PATH := "res://addons/go_build/go_build_material_alpha.tres"

## Canonical path of the shared opaque metre material (revert fallback when
## no opaque metre sits in the mesh's slots).
const _METRE_MATERIAL_PATH := "res://addons/go_build/go_build_material.tres"


## Remap [param face_indices] on [param mesh] after an alpha paint:
## faces whose vertices now have alpha < 1.0 are assigned the shared metre
## alpha material; faces at alpha >= 1.0 get the original opaque metre
## material back.  Faces with custom materials are left untouched.
static func apply(
		mesh: GoBuildMesh,
		face_indices: Array[int],
		channel: int = 0,
) -> void:
	if mesh == null or face_indices.is_empty():
		return
	var alpha_ref: Material = _find_material(mesh, ALPHA_MATERIAL_NAME)
	for fi: int in face_indices:
		if fi < 0 or fi >= mesh.faces.size():
			continue
		var face: GoBuildFace = mesh.faces[fi]
		if face.material_index < 0 \
				or face.material_index >= mesh.material_slots.size():
			continue
		var slot_mat: Material = mesh.material_slots[face.material_index]
		if slot_mat == null or not _is_managed_material(slot_mat):
			continue
		var wants_alpha: bool = _face_has_alpha(mesh, face, channel)
		var is_alpha: bool = slot_mat.resource_name == ALPHA_MATERIAL_NAME
		if wants_alpha == is_alpha:
			continue
		if wants_alpha:
			if alpha_ref == null:
				alpha_ref = alpha_material()
				if alpha_ref == null:
					continue
			# Split the slot: opaque faces keep the metre material; this
			# face moves to the shared alpha slot.
			face.material_index = _slot_of(mesh, alpha_ref)
		else:
			# Symmetric revert: painted alpha returned to 1.0.
			var original: Material = _find_material(mesh, METRE_MATERIAL_NAME)
			if original == null:
				original = _load_opaque_metre()
			if original == null:
				continue
			face.material_index = _slot_of(mesh, original)


## The shared transparent twin this remap assigns:
## [code]go_build_material_alpha.tres[/code], or [code]null[/code] when the
## file is missing.  The ResourceCache returns the same instance project-wide.
static func alpha_material() -> Material:
	return _load_material(_ALPHA_MATERIAL_PATH)


static func _find_material(mesh: GoBuildMesh, mat_name: String) -> Material:
	for mat: Material in mesh.material_slots:
		if mat != null and mat.resource_name == mat_name:
			return mat
	return null


static func _load_opaque_metre() -> Material:
	return _load_material(_METRE_MATERIAL_PATH)


static func _load_material(path: String) -> Material:
	if not ResourceLoader.exists(path):
		return null
	return load(path)


## First slot index holding [param mat], appending a new slot when absent.
static func _slot_of(mesh: GoBuildMesh, mat: Material) -> int:
	var slot: int = mesh.material_slots.find(mat)
	if slot < 0:
		slot = mesh.material_slots.size()
		mesh.material_slots.append(mat)
	return slot


static func _face_has_alpha(mesh: GoBuildMesh, face: GoBuildFace, channel: int) -> bool:
	var arr: Array[Color] = []
	if channel == 0:
		arr = mesh.vertex_colors
	else:
		arr = mesh["custom_channel_%d" % (channel - 1)]
	if arr.size() < mesh.vertices.size():
		return false
	for vi: int in face.vertex_indices:
		if vi < arr.size() and arr[vi].a < 0.999:
			return true
	return false


static func _is_managed_material(mat: Material) -> bool:
	var mat_name: String = mat.resource_name
	return mat_name == METRE_MATERIAL_NAME or mat_name == ALPHA_MATERIAL_NAME