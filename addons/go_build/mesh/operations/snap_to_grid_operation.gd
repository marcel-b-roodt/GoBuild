## Snap the selected vertices to the world grid (ProBuilder "Snap Selection
## to Grid").
##
## Deforming by design: each selected vertex independently snaps to its
## nearest grid cell in WORLD space (node transform applied), so malformed
## off-grid geometry (e.g. an edge 2.863 m long) is normalised — every
## endpoint lands on grid.  Faces whose verts all move may change shape;
## degenerate faces are NOT removed (indices are untouched, only positions
## change — topology is preserved).
##
## Rigid alternative (offset-preserving) is the Ctrl-drag snap; see
## [method GoBuildDragController._snap_translate].
@tool
class_name SnapToGridOperation
extends RefCounted

# Self-preloads — dependency order.
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")


## Snap [param vertex_indices] on [param mesh] to the world grid implied by
## [param node_xform] (each vertex's world position rounded to the nearest
## [param step] multiple per axis, converted back to mesh-local space).
## Invalid indices are silently skipped.  Returns the number of vertices
## moved.  Does NOT rebuild edges — no topology change, only positions.
static func apply(
		mesh: GoBuildMesh,
		vertex_indices: Array[int],
		node_xform: Transform3D,
		step: float,
) -> int:
	if mesh == null or step <= 0.0:
		return 0
	var inv_basis: Basis = node_xform.basis.inverse()
	var origin: Vector3 = node_xform.origin
	var moved: int = 0
	for idx: int in vertex_indices:
		if idx < 0 or idx >= mesh.vertices.size():
			continue
		var local: Vector3 = mesh.vertices[idx]
		var world: Vector3 = node_xform * local
		var snapped_world: Vector3 = world.snapped(Vector3.ONE * step)
		var local_new: Vector3 = inv_basis * (snapped_world - origin)
		if not local_new.is_equal_approx(local):
			mesh.vertices[idx] = local_new
			moved += 1
	return moved