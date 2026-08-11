## Operations for setting per-vertex colour data on a [GoBuildMesh].
##
## Provides:
## - [method fill_faces]: paint every vertex of selected faces with a colour.
## - [method fill_all]: paint every vertex in the mesh with a colour.
## - [method set_vertices]: paint specific vertices with a colour.
##
## All operations respect a channel mask (R/G/B/A bitmask) and blend mode
## (Mix, Add, Subtract, Multiply).
class_name VertexColorOperation
extends RefCounted

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


## Ensure [member GoBuildMesh.vertex_colors] is initialised and parallel to
## [member GoBuildMesh.vertices].  Called internally before any write.
static func _ensure_colors(mesh: GoBuildMesh) -> void:
	if mesh.vertex_colors.size() != mesh.vertices.size():
		mesh.vertex_colors.resize(mesh.vertices.size())
		for i: int in mesh.vertices.size():
			if mesh.vertex_colors[i] == Color():
				mesh.vertex_colors[i] = Color.WHITE


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
## A [code]null[/code] or empty [param face_indices] is a safe no-op.
static func fill_faces(
		mesh: GoBuildMesh,
		face_indices: Array[int],
		color: Color,
		blend_mode: int = BlendMode.MIX,
		channel_mask: int = CHANNEL_ALL,
) -> void:
	if mesh == null or face_indices.is_empty():
		return
	_ensure_colors(mesh)
	var seen: Dictionary = {}
	for fi: int in face_indices:
		if fi < 0 or fi >= mesh.faces.size():
			continue
		for vi: int in mesh.faces[fi].vertex_indices:
			if seen.has(vi):
				continue
			seen[vi] = true
			mesh.vertex_colors[vi] = _blend(mesh.vertex_colors[vi], color, blend_mode, channel_mask)


## Paint every vertex in the mesh with [param color].
static func fill_all(
		mesh: GoBuildMesh,
		color: Color,
		blend_mode: int = BlendMode.MIX,
		channel_mask: int = CHANNEL_ALL,
) -> void:
	if mesh == null:
		return
	_ensure_colors(mesh)
	for i: int in mesh.vertices.size():
		mesh.vertex_colors[i] = _blend(mesh.vertex_colors[i], color, blend_mode, channel_mask)


## Paint specific vertices with [param color].
##
## [param vertex_indices] are the indices into [member GoBuildMesh.vertices].
static func set_vertices(
		mesh: GoBuildMesh,
		vertex_indices: Array[int],
		color: Color,
		blend_mode: int = BlendMode.MIX,
		channel_mask: int = CHANNEL_ALL,
) -> void:
	if mesh == null or vertex_indices.is_empty():
		return
	_ensure_colors(mesh)
	for vi: int in vertex_indices:
		if vi < 0 or vi >= mesh.vertices.size():
			continue
		mesh.vertex_colors[vi] = _blend(mesh.vertex_colors[vi], color, blend_mode, channel_mask)