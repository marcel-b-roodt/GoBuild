## Marks or clears the hard-edge flag on a set of edges.
##
## A hard edge acts as a normal seam: faces on either side will not average
## their per-vertex normals across it, even when they share the same smooth
## group.  This gives artists precise control over where sharp creases appear
## without changing geometry.
##
## The flag is stored in two places for persistence:
## - [member GoBuildEdge.is_hard] on the live edge object (fast bake lookup)
## - [member GoBuildMesh.hard_edge_pairs] as a serialised [Array][Vector2i]
##   that survives [method GoBuildMesh.rebuild_edges] calls.
##
## Usage:
## [codeblock]
## # Mark edge_index as hard:
## HardEdgeOperation.apply(go_build_mesh, [edge_index], true)
##
## # Clear it (make soft again):
## HardEdgeOperation.apply(go_build_mesh, [edge_index], false)
## [/codeblock]
class_name HardEdgeOperation
extends RefCounted

# Self-preloads — compile-time type references.
const _EDGE_SCRIPT := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")


## Apply the hard/soft flag to every edge in [param edge_indices].
##
## When [param hard] is [code]true[/code], each edge is added to
## [member GoBuildMesh.hard_edge_pairs] (without duplicating).
## When [code]false[/code], the edge is removed from that list.
## Out-of-range edge indices are silently skipped.
## A [code]null[/code] [param mesh] is a safe no-op.
static func apply(
		mesh: GoBuildMesh,
		edge_indices: Array[int],
		hard: bool,
) -> void:
	if mesh == null:
		return
	for ei: int in edge_indices:
		if ei < 0 or ei >= mesh.edges.size():
			continue
		var edge: GoBuildEdge = mesh.edges[ei]
		edge.is_hard = hard
		var pair := Vector2i(mini(edge.vertex_a, edge.vertex_b), maxi(edge.vertex_a, edge.vertex_b))
		if hard:
			if not mesh.hard_edge_pairs.has(pair):
				mesh.hard_edge_pairs.append(pair)
		else:
			mesh.hard_edge_pairs.erase(pair)
