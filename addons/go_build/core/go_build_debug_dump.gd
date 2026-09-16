## Debug utilities: geometry dumps and selection printing.
@tool
class_name GoBuildDebugDump
extends RefCounted


## Full mesh dump: every vertex (index + position), edge (index + endpoints),
## and face (index + vertex ring) of [param gbm].
static func print_mesh_geometry(gbm: GoBuildMesh) -> void:
	print("[Geometry] %s: %d verts, %d edges, %d faces" % [
			gbm.resource_name if gbm.resource_name != "" else "mesh",
			gbm.vertices.size(), gbm.edges.size(), gbm.faces.size()])
	for vi: int in gbm.vertices.size():
		print("  v%d %s" % [vi, gbm.vertices[vi]])
	for ei: int in gbm.edges.size():
		var e: GoBuildEdge = gbm.edges[ei]
		print("  e%d %d→%d" % [ei, e.vertex_a, e.vertex_b])
	for fi: int in gbm.faces.size():
		print("  f%d ring=%s" % [fi, gbm.faces[fi].vertex_indices])