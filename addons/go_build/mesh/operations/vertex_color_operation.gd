## Operations for setting per-vertex colour data on a [GoBuildMesh].
##
## Provides:
## - [method fill_faces]: paint every vertex of selected faces with a colour.
## - [method fill_all]: paint every vertex in the mesh with a colour.
## - [method set_vertices]: paint specific vertices with a colour.
##
## All operations respect a channel mask (R/G/B/A bitmask) and blend mode
## (Mix, Add, Subtract, Multiply).
##
## Use [member TargetChannel] to select which per-vertex channel to paint on.
class_name VertexColorOperation
extends RefCounted

## Which per-vertex data channel to paint on.
enum TargetChannel {
	COLOR,     ## vertex_colors (ARRAY_COLOR)
	CUSTOM0,   ## custom_channel_0 (ARRAY_CUSTOM0)
	CUSTOM1,   ## custom_channel_1 (ARRAY_CUSTOM1)
	CUSTOM2,   ## custom_channel_2 (ARRAY_CUSTOM2)
	CUSTOM3,   ## custom_channel_3 (ARRAY_CUSTOM3)
}

## Blend modes for colour application.
enum BlendMode {
	MIX,       ## Replace masked channels with the new colour.
	ADD,       ## Add masked channels.
	SUBTRACT,  ## Subtract masked channels.
	MULTIPLY,  ## Multiply masked channels.
}

# Self-preloads — compile-time type references.
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")

const CHANNEL_R := 0b0001
const CHANNEL_G := 0b0010
const CHANNEL_B := 0b0100
const CHANNEL_A := 0b1000
const CHANNEL_ALL := CHANNEL_R | CHANNEL_G | CHANNEL_B | CHANNEL_A
const CHANNEL_RGB := CHANNEL_R | CHANNEL_G | CHANNEL_B

## Property names on GoBuildMesh corresponding to each [TargetChannel].
const _CHANNEL_PROPERTY: Dictionary = {
	TargetChannel.COLOR: "vertex_colors",
	TargetChannel.CUSTOM0: "custom_channel_0",
	TargetChannel.CUSTOM1: "custom_channel_1",
	TargetChannel.CUSTOM2: "custom_channel_2",
	TargetChannel.CUSTOM3: "custom_channel_3",
}


## Get the per-vertex data array for [param target] on [param mesh].
static func _get_channel(mesh: GoBuildMesh, target: TargetChannel) -> Array[Color]:
	return mesh[_CHANNEL_PROPERTY[target]]


## Ensure the target channel is initialised and parallel to
## [member GoBuildMesh.vertices].  [param default_val] is used for padding
## (white for colour, transparent black for custom channels).
static func _ensure_channel(mesh: GoBuildMesh, target: TargetChannel) -> void:
	var prop_name: String = _CHANNEL_PROPERTY[target]
	var arr: Array[Color] = mesh[prop_name]
	if arr.size() != mesh.vertices.size():
		arr.resize(mesh.vertices.size())
		var default: Color = Color.WHITE if target == TargetChannel.COLOR else Color(0.0, 0.0, 0.0, 0.0)
		for i: int in mesh.vertices.size():
			if arr[i] == Color():
				arr[i] = default


## Blend [param new_color] into [param existing] using [param blend_mode],
## respecting [param channel_mask].
##
## Only channels whose mask bit is set are modified; others pass through.
static func _blend(
		existing: Color,
		new_color: Color,
		blend_mode: int,
		channel_mask: int,
) -> Color:
	var result := existing
	if channel_mask & CHANNEL_R:
		result.r = _blend_channel(existing.r, new_color.r, blend_mode)
	if channel_mask & CHANNEL_G:
		result.g = _blend_channel(existing.g, new_color.g, blend_mode)
	if channel_mask & CHANNEL_B:
		result.b = _blend_channel(existing.b, new_color.b, blend_mode)
	if channel_mask & CHANNEL_A:
		result.a = _blend_channel(existing.a, new_color.a, blend_mode)
	return result


## Blend a single channel value.
static func _blend_channel(existing: float, new_val: float, blend_mode: int) -> float:
	match blend_mode:
		BlendMode.MIX:
			return new_val
		BlendMode.ADD:
			return clampf(existing + new_val, 0.0, 1.0)
		BlendMode.SUBTRACT:
			return clampf(existing - new_val, 0.0, 1.0)
		BlendMode.MULTIPLY:
			return clampf(existing * new_val, 0.0, 1.0)
	return new_val


## Paint every vertex of the selected faces with [param color].
##
## [param blend_mode] controls how the colour is combined with existing values.
## [param channel_mask] controls which channels (R/G/B/A) are affected.
## [param target] selects which per-vertex data channel to paint on.
## A [code]null[/code] or empty [param face_indices] is a safe no-op.
static func fill_faces(
		mesh: GoBuildMesh,
		face_indices: Array[int],
		color: Color,
		blend_mode: int = BlendMode.MIX,
		channel_mask: int = CHANNEL_ALL,
		target: TargetChannel = TargetChannel.COLOR,
) -> void:
	if mesh == null or face_indices.is_empty():
		return
	_ensure_channel(mesh, target)
	var arr: Array[Color] = _get_channel(mesh, target)
	var seen: Dictionary = {}
	for fi: int in face_indices:
		if fi < 0 or fi >= mesh.faces.size():
			continue
		for vi: int in mesh.faces[fi].vertex_indices:
			if seen.has(vi):
				continue
			seen[vi] = true
			arr[vi] = _blend(arr[vi], color, blend_mode, channel_mask)


## Paint every vertex in the mesh with [param color].
static func fill_all(
		mesh: GoBuildMesh,
		color: Color,
		blend_mode: int = BlendMode.MIX,
		channel_mask: int = CHANNEL_ALL,
		target: TargetChannel = TargetChannel.COLOR,
) -> void:
	if mesh == null:
		return
	_ensure_channel(mesh, target)
	var arr: Array[Color] = _get_channel(mesh, target)
	for i: int in mesh.vertices.size():
		arr[i] = _blend(arr[i], color, blend_mode, channel_mask)


## Paint specific vertices with [param color].
##
## [param vertex_indices] are the indices into [member GoBuildMesh.vertices].
static func set_vertices(
		mesh: GoBuildMesh,
		vertex_indices: Array[int],
		color: Color,
		blend_mode: int = BlendMode.MIX,
		channel_mask: int = CHANNEL_ALL,
		target: TargetChannel = TargetChannel.COLOR,
) -> void:
	if mesh == null or vertex_indices.is_empty():
		return
	_ensure_channel(mesh, target)
	var arr: Array[Color] = _get_channel(mesh, target)
	for vi: int in vertex_indices:
		if vi < 0 or vi >= mesh.vertices.size():
			continue
		arr[vi] = _blend(arr[vi], color, blend_mode, channel_mask)