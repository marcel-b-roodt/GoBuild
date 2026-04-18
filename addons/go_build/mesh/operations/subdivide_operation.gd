## Subdivide face(s) operation for [GoBuildMesh].
##
## Splits each selected face into N quads (one per original vertex) by
## inserting a centroid vertex and edge-midpoint vertices.  The result is
## a fully quad mesh with no triangles.
##
## Algorithm for each selected face with [code]N[/code] vertices:
##   1. For each edge of the face, compute the edge midpoint.  Midpoints are
##      shared between adjacent selected faces so no T-junctions are created
##      at the boundary between two co-selected faces.
##   2. Compute the face centroid (added once per face).
##   3. Replace the original face with [code]N[/code] new quads.  For vertex
##      [code]k[/code] the replacement quad is:
##      [code][v_k, mid(v_k → v_{k+1}), centroid, mid(v_{k-1} → v_k)][/code]
##
## Edges on the boundary between a selected face and an unselected face share
## only one midpoint (from the selected side) producing a T-junction at the
## unselected face's edge.  This matches Blender's simple-subdivide behaviour
## for partial face selections and is acceptable for the v1 implementation.
##
## [method GoBuildMesh.rebuild_edges] is called automatically inside
## [method apply].
@tool
class_name SubdivideOperation
extends RefCounted

# Self-preloads — dependency order.
const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE_SCRIPT := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")


## Subdivide the faces at [param face_indices] on [param mesh].
##
## Invalid or out-of-range indices are silently skipped.
## [method GoBuildMesh.rebuild_edges] is called automatically on completion.
static func apply(mesh: GoBuildMesh, face_indices: Array[int]) -> void:
	if mesh == null or face_indices.is_empty():
		return

	var valid: Array[int] = []
	var seen: Dictionary = {}
	for fi: int in face_indices:
		if fi >= 0 and fi < mesh.faces.size() and not seen.has(fi):
			seen[fi] = true
			valid.append(fi)
	if valid.is_empty():
		return

	# ── Phase 1: compute shared edge midpoints for all selected faces ───────
	#
	# Key: "%d_%d" % [min(va, vb), max(va, vb)] → new vertex index.
	# Using the canonical min/max key ensures two adjacent selected faces share
	# the same midpoint on their common edge.
	var edge_mids: Dictionary = {}
	for fi: int in valid:
		var face: GoBuildFace = mesh.faces[fi]
		var vc: int = face.vertex_indices.size()
		for k: int in vc:
			var va: int = face.vertex_indices[k]
			var vb: int = face.vertex_indices[(k + 1) % vc]
			var key: String = "%d_%d" % [mini(va, vb), maxi(va, vb)]
			if not edge_mids.has(key):
				var mid: Vector3 = (mesh.vertices[va] + mesh.vertices[vb]) * 0.5
				edge_mids[key] = mesh.vertices.size()
				mesh.vertices.append(mid)

	# ── Phase 2: build replacement quad sets for each selected face ──────────
	#
	# Collect all replacements before modifying mesh.faces so that face indices
	# in `valid` remain stable during this loop.
	var replacements: Array = []   # Array of Array[GoBuildFace]
	for fi: int in valid:
		var face: GoBuildFace = mesh.faces[fi]
		var vc: int = face.vertex_indices.size()

		# Centroid — one per face.
		var centroid := Vector3.ZERO
		for vi: int in face.vertex_indices:
			centroid += mesh.vertices[vi]
		centroid /= float(vc)
		var c_idx: int = mesh.vertices.size()
		mesh.vertices.append(centroid)

		var new_quads: Array[GoBuildFace] = []
		for k: int in vc:
			var va: int = face.vertex_indices[k]
			var vb: int = face.vertex_indices[(k + 1) % vc]
			var vc_prev: int = face.vertex_indices[(k - 1 + vc) % vc]

			var key_next: String = "%d_%d" % [mini(va, vb), maxi(va, vb)]
			var key_prev: String = "%d_%d" % [mini(vc_prev, va), maxi(vc_prev, va)]

			var mid_next: int = edge_mids[key_next]
			var mid_prev: int = edge_mids[key_prev]

			# Winding [va, mid_next, centroid, mid_prev] is consistent with the
			# CCW-from-outside convention used throughout GoBuildMesh operations.
			var q := GoBuildFace.new()
			q.vertex_indices = [va, mid_next, c_idx, mid_prev]
			q.uvs = [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]
			q.material_index = face.material_index
			q.smooth_group   = face.smooth_group
			new_quads.append(q)

		replacements.append(new_quads)

	# ── Phase 3: apply replacements ─────────────────────────────────────────
	#
	# Replace each original selected face with the first new quad; append the
	# rest.  Processing in ascending index order keeps `valid[i]` accurate.
	# Capture the original face count before appending new quads so Phase 4
	# can limit its scan to pre-existing faces only.
	var original_face_count: int = mesh.faces.size()
	for i: int in valid.size():
		var fi: int = valid[i]
		var quads: Array[GoBuildFace] = replacements[i]
		mesh.faces[fi] = quads[0]
		for j: int in range(1, quads.size()):
			mesh.faces.append(quads[j])

	# ── Phase 4: stitch adjacent unselected faces ────────────────────────────
	#
	# Each edge midpoint in edge_mids was only wired into the new sub-quads of
	# the selected faces.  Any original unselected face that shares an edge with
	# a selected face now has a T-junction — the midpoint vertex exists in the
	# mesh but is absent from the unselected face's ring.  Insert it between the
	# two original endpoints so the face grows from an N-gon to an (N+1)-gon.
	#
	# We iterate the ring backwards so that each insert(k+1, …) never shifts
	# the positions still to be visited (they all have index ≤ k).
	var valid_set: Dictionary = {}
	for fi: int in valid:
		valid_set[fi] = true

	for fi: int in original_face_count:
		if valid_set.has(fi):
			continue
		var face: GoBuildFace = mesh.faces[fi]
		var vc: int = face.vertex_indices.size()
		var has_uvs: bool = face.uvs.size() == vc
		for k: int in range(vc - 1, -1, -1):
			var va: int = face.vertex_indices[k]
			var vb: int = face.vertex_indices[(k + 1) % vc]
			var key: String = "%d_%d" % [mini(va, vb), maxi(va, vb)]
			if edge_mids.has(key):
				var mid_idx: int = edge_mids[key]
				# Capture UVs before mutating the array.
				var uv_mid: Vector2
				if has_uvs:
					uv_mid = (face.uvs[k] + face.uvs[(k + 1) % vc]) * 0.5
				face.vertex_indices.insert(k + 1, mid_idx)
				if has_uvs:
					face.uvs.insert(k + 1, uv_mid)

	mesh.rebuild_edges()
