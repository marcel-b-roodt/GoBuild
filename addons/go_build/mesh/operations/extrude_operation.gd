## Extrude face(s) operation for [GoBuildMesh].
##
## Extrudes each selected face along its own face normal by a configurable
## distance.  For each face the operation:
##   1. Creates new vertices at the original ring positions offset by
##      [code]normal × distance[/code].
##   2. Adds side quads around the perimeter connecting the original (bottom)
##      ring to the new (top) ring.
##   3. Replaces the original face's vertex_indices with the new top-ring
##      indices so the face appears at the extruded position.
##
## Multiple selected faces are each extruded independently in this first
## implementation.  Shared-edge merging (needed to avoid internal gaps when
## two adjacent faces are co-selected) is deferred to a later pass.
##
## Call [method GoBuildMesh.rebuild_edges] after the operation to keep edge
## topology in sync — this class calls it automatically inside [method apply].
@tool
class_name ExtrudeOperation
extends RefCounted

# Self-preloads — dependency order.
# GoBuildFace / GoBuildEdge / GoBuildMesh live in mesh/ which is scanned
# before operations/ alphabetically, but explicit preloads are required per
# the self-preload rule whenever a class name is used as a compile-time type.
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")


## Extrude the faces at [param face_indices] on [param mesh] by [param distance]
## along each face's own outward normal.
##
## Invalid (out-of-range) indices are silently skipped.
## Degenerate faces (fewer than 3 vertices) are silently skipped.
## [method GoBuildMesh.rebuild_edges] is called automatically on completion.
static func apply(mesh: GoBuildMesh, face_indices: Array[int], distance: float) -> void:
	if mesh == null or face_indices.is_empty():
		return

	# Validate indices up-front so _extrude_single_face can assume they are in range.
	var valid_indices: Array[int] = []
	for fi: int in face_indices:
		if fi >= 0 and fi < mesh.faces.size():
			valid_indices.append(fi)

	if valid_indices.is_empty():
		return

	for fi: int in valid_indices:
		_extrude_single_face(mesh, fi, distance)

	mesh.rebuild_edges()


## Extrude a single face by [param distance] along its outward face normal.
##
## Algorithm:
##   1. Compute the face normal via [method GoBuildMesh.compute_face_normal].
##   2. For each vertex in the face create a new vertex at
##      [code]original_pos + normal × distance[/code].
##   3. For each edge of the face (ik → ik+1), add a side quad with winding
##      [code][ik, ik+1, jk+1, jk][/code] — CCW from outside, so
##      [method GoBuildMesh.compute_face_normal] returns the correct outward
##      normal for each side face (verified in the unit tests).
##   4. Replace the original face's vertex_indices with the new top-ring
##      indices.  The original UVs are preserved on the extruded top face.
##
## Side-face UV convention: simple planar (0,0)→(1,1) mapping per quad.
static func _extrude_single_face(mesh: GoBuildMesh, face_index: int, distance: float) -> void:
	var face: GoBuildFace = mesh.faces[face_index]
	var vc: int = face.vertex_indices.size()
	if vc < 3:
		return  # Degenerate face — skip silently.

	var normal: Vector3 = mesh.compute_face_normal(face)
	var offset: Vector3 = normal * distance

	# ── 1. Create new top-ring vertices ────────────────────────────────────
	var new_indices: Array[int] = []
	new_indices.resize(vc)
	for k: int in vc:
		var orig_pos: Vector3 = mesh.vertices[face.vertex_indices[k]]
		mesh.vertices.append(orig_pos + offset)
		new_indices[k] = mesh.vertices.size() - 1

	# ── 2. Create side faces ────────────────────────────────────────────────
	# Winding [bottom_a, bottom_b, top_b, top_a] is CCW from outside.
	# Verified by Newell's method in the unit tests (test_extrude_side_face_normals).
	for k: int in vc:
		var k_next: int = (k + 1) % vc
		var side := GoBuildFace.new()
		side.vertex_indices = [
			face.vertex_indices[k],
			face.vertex_indices[k_next],
			new_indices[k_next],
			new_indices[k],
		]
		side.material_index = face.material_index
		side.smooth_group   = face.smooth_group
		# Simple planar UV for the side quad: bottom-left → bottom-right → top-right → top-left.
		side.uvs = [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]
		mesh.faces.append(side)

	# ── 3. Update original face to use the new top-ring vertices ───────────
	# Original UVs are preserved (they map the extruded top face the same way).
	face.vertex_indices.assign(new_indices)

