## UV topology helpers for island detection and shared-vertex queries.
##
## Centralises the UV vertex map builder and quantised key function that
## were previously duplicated between [UvIslandSelect] and [UvPackIslands].
class_name UvTopology
extends RefCounted

const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")

const UV_EPSILON: float = 0.0001


## Build a dictionary mapping quantised UV positions to face indices.
##
## Each key is a [StringName] of the form [code]"ix|iy"[/code] where
## [code]ix = round(uv.x / UV_EPSILON)[/code] and similarly for [code]iy[/code].
## Each value is an [Array[int]] of face indices that reference that UV position.
##
## Used by [UvIslandSelect] and [UvPackIslands] for flood-fill island detection.
static func build_uv_vertex_map(mesh: GoBuildMesh) -> Dictionary:
	var m: Dictionary = {}
	for fi: int in mesh.faces.size():
		var face: GoBuildFace = mesh.faces[fi]
		for uv: Vector2 in face.uvs:
			var key := uv_key(uv)
			if not m.has(key):
				m[key] = []
			m[key].append(fi)
	return m


## Quantise a UV position to a [StringName] key for dictionary lookup.
##
## Two UVs within [constant UV_EPSILON] of each other produce the same key,
## enabling epsilon-based grouping without floating-point drift.
static func uv_key(uv: Vector2) -> StringName:
	var ix: int = roundi(uv.x / UV_EPSILON)
	var iy: int = roundi(uv.y / UV_EPSILON)
	return StringName("%d|%d" % [ix, iy])