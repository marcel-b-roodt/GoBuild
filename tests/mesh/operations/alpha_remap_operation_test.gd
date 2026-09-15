## AlphaRemapOperation + shared metre alpha material tests — GdUnit4
extends GdUnitTestSuite

const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _VC_OP_SCRIPT := preload("res://addons/go_build/mesh/operations/vertex_color_operation.gd")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Build [param face_count] independent quads, all on slot 0 holding
## [param slot_mat].  Vertex colours are initialised to opaque white.
func _make_mesh(face_count: int, slot_mat: Material) -> GoBuildMesh:
	var mesh := GoBuildMesh.new()
	mesh.material_slots.append(slot_mat)
	for fi: int in face_count:
		var base: int = fi * 4
		mesh.vertices.append_array([
			Vector3(float(fi), 0.0, 0.0),
			Vector3(float(fi), 1.0, 0.0),
			Vector3(float(fi), 1.0, 1.0),
			Vector3(float(fi), 0.0, 1.0),
		])
		var face := GoBuildFace.new()
		face.vertex_indices = [base, base + 1, base + 2, base + 3]
		face.uvs = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
		face.material_index = 0
		mesh.faces.append(face)
	mesh.vertex_colors.resize(mesh.vertices.size())
	for i: int in mesh.vertex_colors.size():
		mesh.vertex_colors[i] = Color.WHITE
	return mesh


## A stand-in for the metre material: opaque, correct resource_name.
func _metre_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = AlphaRemapOperation.METRE_MATERIAL_NAME
	return mat


## A stand-in for the shared alpha material: correct resource_name.  The
## remap matches by resource_name, so this is interchangeable with the
## loaded .tres for slot-assignment tests.
func _alpha_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = AlphaRemapOperation.ALPHA_MATERIAL_NAME
	return mat


# ---------------------------------------------------------------------------
# alpha_material loader
# ---------------------------------------------------------------------------

func test_alpha_material_loads_shipped_tres() -> void:
	var mat: Material = AlphaRemapOperation.alpha_material()
	assert_object(mat).is_not_null()
	assert_str(mat.resource_name).is_equal(
			AlphaRemapOperation.ALPHA_MATERIAL_NAME)


# ---------------------------------------------------------------------------
# Paint alpha < 1 remaps to the shared transparent metre material
# ---------------------------------------------------------------------------

func test_paint_alpha_remaps_face_to_shared_alpha_material() -> void:
	var metre := _metre_material()
	var mesh := _make_mesh(2, metre)
	mesh.material_slots.append(_alpha_material())
	# Paint alpha 0.5 on face 0's vertices.
	VertexColorOperation.fill_faces(mesh, [0], Color(1, 1, 1, 0.5),
			VertexColorOperation.BlendMode.MIX, VertexColorOperation.CHANNEL_A)
	AlphaRemapOperation.apply(mesh, [0, 1])
	assert_int(mesh.faces[0].material_index) \
			.is_not_equal(mesh.faces[1].material_index)
	var alpha_mat: Material = mesh.material_slots[mesh.faces[0].material_index]
	assert_str(alpha_mat.resource_name) \
			.is_equal(AlphaRemapOperation.ALPHA_MATERIAL_NAME)
	# Shared opaque metre untouched.
	assert_int(metre.transparency) \
			.is_equal(BaseMaterial3D.TRANSPARENCY_DISABLED)
	# Untouched face still on the opaque metre slot.
	assert_object(mesh.material_slots[mesh.faces[1].material_index]) \
			.is_equal(metre)


func test_alpha_material_loaded_when_absent_from_slots() -> void:
	var metre := _metre_material()
	var mesh := _make_mesh(2, metre)
	VertexColorOperation.fill_faces(mesh, [0], Color(1, 1, 1, 0.5),
			VertexColorOperation.BlendMode.MIX, VertexColorOperation.CHANNEL_A)
	AlphaRemapOperation.apply(mesh, [0, 1])
	assert_int(mesh.material_slots.size()).is_equal(2)
	var alpha_mat: Material = mesh.material_slots[mesh.faces[0].material_index]
	assert_str(alpha_mat.resource_name) \
			.is_equal(AlphaRemapOperation.ALPHA_MATERIAL_NAME)


func test_painting_three_faces_yields_one_alpha_slot() -> void:
	# Regression: three alpha-painted faces must share ONE alpha material —
	# no per-face duplicates appended to material_slots.
	var metre := _metre_material()
	var mesh := _make_mesh(3, metre)
	VertexColorOperation.fill_faces(mesh, [0, 1, 2], Color(1, 1, 1, 0.5),
			VertexColorOperation.BlendMode.MIX, VertexColorOperation.CHANNEL_A)
	AlphaRemapOperation.apply(mesh, [0, 1, 2])
	assert_int(mesh.material_slots.size()).is_equal(2)
	for fi: int in 3:
		assert_str(mesh.material_slots[
				mesh.faces[fi].material_index].resource_name) \
				.is_equal(AlphaRemapOperation.ALPHA_MATERIAL_NAME)


func test_alpha_appended_once_across_separate_applies() -> void:
	var metre := _metre_material()
	var mesh := _make_mesh(2, metre)
	VertexColorOperation.fill_faces(mesh, [0], Color(1, 1, 1, 0.5),
			VertexColorOperation.BlendMode.MIX, VertexColorOperation.CHANNEL_A)
	AlphaRemapOperation.apply(mesh, [0, 1])
	VertexColorOperation.fill_faces(mesh, [1], Color(1, 1, 1, 0.5),
			VertexColorOperation.BlendMode.MIX, VertexColorOperation.CHANNEL_A)
	AlphaRemapOperation.apply(mesh, [0, 1])
	assert_int(mesh.material_slots.size()).is_equal(2)


func test_revert_alpha_remaps_back_to_opaque_original() -> void:
	var metre := _metre_material()
	var mesh := _make_mesh(2, metre)
	var opaque_slot: int = mesh.faces[0].material_index
	VertexColorOperation.fill_faces(mesh, [0], Color(1, 1, 1, 0.5),
			VertexColorOperation.BlendMode.MIX, VertexColorOperation.CHANNEL_A)
	AlphaRemapOperation.apply(mesh, [0, 1])
	# Paint alpha back to 1.0 on face 0.
	VertexColorOperation.fill_faces(mesh, [0], Color(1, 1, 1, 1.0),
			VertexColorOperation.BlendMode.MIX, VertexColorOperation.CHANNEL_A)
	AlphaRemapOperation.apply(mesh, [0, 1])
	assert_int(mesh.faces[0].material_index).is_equal(opaque_slot)
	assert_object(mesh.material_slots[opaque_slot]).is_equal(metre)


func test_revert_works_when_all_faces_started_alpha() -> void:
	# No opaque metre in any candidate face — revert falls back to loading
	# the shipped opaque metre material by path.
	var alpha := _alpha_material()
	var mesh := _make_mesh(2, alpha)
	VertexColorOperation.fill_faces(mesh, [0, 1], Color(1, 1, 1, 1.0),
			VertexColorOperation.BlendMode.MIX, VertexColorOperation.CHANNEL_A)
	AlphaRemapOperation.apply(mesh, [0, 1])
	for fi: int in 2:
		var mat: Material = mesh.material_slots[mesh.faces[fi].material_index]
		assert_str(mat.resource_name) \
				.is_equal(AlphaRemapOperation.METRE_MATERIAL_NAME)


func test_revert_without_metre_in_slots_uses_loaded_tres() -> void:
	# Same fallback, exercised with the real resource cache paths.
	var alpha: Material = AlphaRemapOperation.alpha_material()
	var mesh := _make_mesh(1, alpha)
	VertexColorOperation.fill_faces(mesh, [0], Color(1, 1, 1, 1.0),
			VertexColorOperation.BlendMode.MIX, VertexColorOperation.CHANNEL_A)
	AlphaRemapOperation.apply(mesh, [0])
	var mat: Material = mesh.material_slots[mesh.faces[0].material_index]
	assert_str(mat.resource_name) \
			.is_equal(AlphaRemapOperation.METRE_MATERIAL_NAME)


func test_custom_material_never_remapped() -> void:
	var custom := StandardMaterial3D.new()
	var mesh := _make_mesh(1, custom)
	VertexColorOperation.fill_faces(mesh, [0], Color(1, 1, 1, 0.5),
			VertexColorOperation.BlendMode.MIX, VertexColorOperation.CHANNEL_A)
	AlphaRemapOperation.apply(mesh, [0])
	assert_int(mesh.faces[0].material_index).is_equal(0)
	assert_object(mesh.material_slots[0]).is_equal(custom)
	assert_int(custom.transparency) \
			.is_equal(BaseMaterial3D.TRANSPARENCY_DISABLED)


func test_custom_material_remap_never_touches_meta() -> void:
	# No metadata is read or written by the remap — custom materials with or
	# without any meta keys are skipped purely by resource_name.
	var custom := StandardMaterial3D.new()
	custom.resource_name = "my_wood_floor"
	var mesh := _make_mesh(1, custom)
	VertexColorOperation.fill_faces(mesh, [0], Color(1, 1, 1, 0.5),
			VertexColorOperation.BlendMode.MIX, VertexColorOperation.CHANNEL_A)
	AlphaRemapOperation.apply(mesh, [0])
	assert_bool(custom.has_meta("go_build_alpha_variant_of")).is_false()


func test_no_remap_when_all_alpha_opaque() -> void:
	var metre := _metre_material()
	var mesh := _make_mesh(2, metre)
	var faces: Array[int] = [0, 1]
	AlphaRemapOperation.apply(mesh, faces)
	assert_int(mesh.faces[0].material_index).is_equal(0)
	assert_int(mesh.faces[1].material_index).is_equal(0)
	assert_int(mesh.material_slots.size()).is_equal(1)


func test_alpha_face_shared_with_opaque_face_splits_slot() -> void:
	var metre := _metre_material()
	var alpha := _alpha_material()
	# Two faces sharing all 4 vertices (as on a box corner) — the slot
	# remap must not steal the still-opaque face's slot.
	var mesh := GoBuildMesh.new()
	mesh.material_slots.append(metre)
	mesh.material_slots.append(alpha)
	mesh.vertices.append_array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0),
	])
	var f0 := GoBuildFace.new()
	f0.vertex_indices = [0, 1, 2, 3]
	f0.material_index = 0
	mesh.faces.append(f0)
	var f1 := GoBuildFace.new()
	f1.vertex_indices = [0, 1, 2, 3]
	f1.material_index = 0
	mesh.faces.append(f1)
	mesh.vertex_colors.resize(4)
	for i: int in 4:
		mesh.vertex_colors[i] = Color.WHITE
	# Paint alpha on vertices of face 0 only... but they share every vertex,
	# so both faces go transparent — the slot split moves both to the shared
	# alpha slot while the opaque metre stays in the slots chain.
	VertexColorOperation.fill_faces(mesh, [0], Color(1, 1, 1, 0.5),
			VertexColorOperation.BlendMode.MIX, VertexColorOperation.CHANNEL_A)
	AlphaRemapOperation.apply(mesh, [0, 1])
	assert_int(mesh.faces[0].material_index).is_equal(mesh.faces[1].material_index)
	var alpha_mat: Material = mesh.material_slots[mesh.faces[0].material_index]
	assert_object(alpha_mat).is_equal(alpha)
	# The opaque metre must survive somewhere in the slots chain.
	assert_object(mesh.material_slots[0]).is_equal(metre)


func test_noop_for_null_mesh_and_empty_faces() -> void:
	var empty: Array[int] = []
	AlphaRemapOperation.apply(null, empty)
	var metre := _metre_material()
	var mesh := _make_mesh(1, metre)
	AlphaRemapOperation.apply(mesh, empty)
	assert_int(mesh.faces[0].material_index).is_equal(0)


func test_noop_for_out_of_range_face_index() -> void:
	var metre := _metre_material()
	var mesh := _make_mesh(1, metre)
	AlphaRemapOperation.apply(mesh, [99])
	assert_int(mesh.faces[0].material_index).is_equal(0)


# ---------------------------------------------------------------------------
# Custom-channel paint (target channel != COLOR)
# ---------------------------------------------------------------------------

func test_custom_channel_alpha_remaps_too() -> void:
	var metre := _metre_material()
	var mesh := _make_mesh(1, metre)
	VertexColorOperation.fill_faces(mesh, [0], Color(1, 1, 1, 0.5),
			VertexColorOperation.BlendMode.MIX, VertexColorOperation.CHANNEL_A,
			VertexColorOperation.TargetChannel.CUSTOM0)
	AlphaRemapOperation.apply(mesh, [0],
			VertexColorOperation.TargetChannel.CUSTOM0)
	var alpha_mat: Material = mesh.material_slots[mesh.faces[0].material_index]
	assert_str(alpha_mat.resource_name) \
			.is_equal(AlphaRemapOperation.ALPHA_MATERIAL_NAME)