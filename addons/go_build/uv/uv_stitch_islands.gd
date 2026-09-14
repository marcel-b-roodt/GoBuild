## Merges UV islands along shared topology edges.
##
## For each pair of selected UV islands that share a topology edge (same vertex
## indices in 3D space) but have different UV coordinates, this operation
## snaps the UVs of one island to match the other along the shared boundary.
##
## The "target" island is chosen as the one containing the face with the
## lowest index in the selected set; all others snap to it.
@tool
class_name UvStitchIslands
extends RefCounted

const _FACE_SCRIPT := preload("res://addons/go_build/mesh/go_build_face.gd")
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _EDGE_SCRIPT := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _ISLAND_SELECT := preload("res://addons/go_build/uv/uv_island_select.gd")


## Stitch UV islands in [param mesh] for faces in [param selected_faces].
## Returns the number of stitch operations performed (pairs of islands merged).
static func apply(mesh: GoBuildMesh, selected_faces: Array[int]) -> int:
	if selected_faces.size() < 2:
		return 0

	if mesh.edges.is_empty():
		mesh.rebuild_edges()

	var islands := _build_islands_from_selection(mesh, selected_faces)
	if islands.size() < 2:
		return 0

	var face_to_island: Dictionary = {}
	for i: int in islands.size():
		for fi: int in islands[i]:
			face_to_island[fi] = i

	var stitched_count: int = 0
	var visited_pairs: Dictionary = {}

	for edge: GoBuildEdge in mesh.edges:
		if edge.face_indices.size() != 2:
			continue
		var fa: int = edge.face_indices[0]
		var fb: int = edge.face_indices[1]
		if not face_to_island.has(fa) or not face_to_island.has(fb):
			continue
		var ia: int = face_to_island[fa]
		var ib: int = face_to_island[fb]
		if ia == ib:
			continue

		var pair_key: int = mini(ia, ib) * 100000 + maxi(ia, ib)
		if visited_pairs.has(pair_key):
			continue
		visited_pairs[pair_key] = true

		_stitch_along_edge(mesh, edge, islands[ia], islands[ib])
		_merge_islands(islands, ia, ib, face_to_island)
		stitched_count += 1

	return stitched_count


# ---------------------------------------------------------------------------
# Island detection (from selected faces only)
# ---------------------------------------------------------------------------

static func _build_islands_from_selection(
		mesh: GoBuildMesh, selected_faces: Array[int]) -> Array[Array]:
	return UvIslandSelect.build_all_islands(mesh, selected_faces)


# ---------------------------------------------------------------------------
# Stitching logic
# ---------------------------------------------------------------------------

## Snap UVs on shared topology vertices of [param edge] between two islands.
## Island A's UVs are the "target"; island B's UVs on the shared verts are
## snapped to match.
static func _stitch_along_edge(
		mesh: GoBuildMesh, edge: GoBuildEdge,
		island_a: Array[int], island_b: Array[int]) -> void:
	var a_set: Dictionary = {}
	for fi: int in island_a:
		a_set[fi] = true

	var b_set: Dictionary = {}
	for fi: int in island_b:
		b_set[fi] = true

	var shared_verts: Array[int] = [edge.vertex_a, edge.vertex_b]

	var target_uvs: Dictionary = {}
	for fi: int in island_a:
		var face: GoBuildFace = mesh.faces[fi]
		for vi: int in face.vertex_indices.size():
			var vert_idx: int = face.vertex_indices[vi]
			if shared_verts.has(vert_idx):
				if not target_uvs.has(vert_idx):
					target_uvs[vert_idx] = face.uvs[vi]

	for fi: int in island_b:
		var face: GoBuildFace = mesh.faces[fi]
		for vi: int in face.vertex_indices.size():
			var vert_idx: int = face.vertex_indices[vi]
			if target_uvs.has(vert_idx):
				face.uvs[vi] = target_uvs[vert_idx]


## Merge island B into island A and update the face_to_island map.
static func _merge_islands(
		islands: Array[Array], ia: int, ib: int,
		face_to_island: Dictionary) -> void:
	for fi: int in islands[ib]:
		islands[ia].append(fi)
		face_to_island[fi] = ia
	islands[ib].clear()