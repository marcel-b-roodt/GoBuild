## Knife cut operation — editor entry point for [GoBuildKnife].
##
## Splits every face along a closed polyline of surface points (see
## docs/knife-cut-design.md).  Thin wrapper: the geometry lives in the pure
## [GoBuildKnife] helpers; this class adds the mesh guard.  Edge topology is
## maintained incrementally inside [GoBuildKnife] (split_edge +
## register/unregister + compact/refresh — no rebuild).
##
## The caller (knife controller) is responsible for undo/redo — normally via
## [method GoBuildMeshInstance.apply_operation] wrapping a single snapshot.
class_name KnifeCutOperation
extends RefCounted

# Self-preloads — dependency order.
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _KNIFE_SCRIPT := preload("res://addons/go_build/mesh/knife.gd")


## Run the knife over [param points] (each { "face_index": int,
## "position": Vector3 } in local space).  [param edge_hits] carries
## screen-space edge crossings (see [method GoBuildKnife.screen_edge_hits])
## — the camera-visible pierces the caller computed; empty when headless.
## Returns true when any face was split.  Edge topology is reconciled
## incrementally (no rebuild).
static func apply(mesh: GoBuildMesh, points: Array, closed: bool = false,
		edge_hits: Array = []) -> bool:
	if mesh == null or points.is_empty():
		return false
	return GoBuildKnife.apply(mesh, points, closed, edge_hits)