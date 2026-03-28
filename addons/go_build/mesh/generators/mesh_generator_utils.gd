## Static helpers shared across all [GoBuildMesh] shape generators.
##
## The primary helper is [method add_quad_grid], which builds a rectangular
## grid of quad faces spanning four corner vertices. All generators that
## produce planar or near-planar faces delegate to this method.
class_name MeshGeneratorUtils
extends RefCounted


## Add a subdivided quad grid to [param mesh] spanning four CCW corners.
##
## Corner convention (wound CCW when viewed from the outward normal side):
## [param v0] bottom-left  · [param v1] bottom-right
## [param v2] top-right    · [param v3] top-left
##
## [param steps_u] quad columns  (>= 1)
## [param steps_v] quad rows     (>= 1)
## [param material_index] material slot assigned to every face created.
##
## Vertices are added to [member GoBuildMesh.vertices] and faces to
## [member GoBuildMesh.faces]. The caller is responsible for calling
## [method GoBuildMesh.rebuild_edges] when all faces have been added.
static func add_quad_grid(
		mesh: GoBuildMesh,
		v0: Vector3,
		v1: Vector3,
		v2: Vector3,
		v3: Vector3,
		steps_u: int = 1,
		steps_v: int = 1,
		material_index: int = 0,
) -> void:
	assert(steps_u >= 1, "MeshGeneratorUtils.add_quad_grid: steps_u must be >= 1")
	assert(steps_v >= 1, "MeshGeneratorUtils.add_quad_grid: steps_v must be >= 1")

	var vert_start: int = mesh.vertices.size()

	# Build a (steps_u + 1) × (steps_v + 1) vertex grid via bilinear lerp.
	# Row 0 is the v0 → v1 edge; row steps_v is the v3 → v2 edge.
	for row in range(steps_v + 1):
		var tv: float = float(row) / float(steps_v)
		for col in range(steps_u + 1):
			var tu: float = float(col) / float(steps_u)
			mesh.vertices.append(v0.lerp(v1, tu).lerp(v3.lerp(v2, tu), tv))

	# Create one GoBuildFace per grid cell, wound CCW (inherits corner winding).
	for row in range(steps_v):
		for col in range(steps_u):
			var i00: int = vert_start +  row      * (steps_u + 1) + col
			var i10: int = vert_start +  row      * (steps_u + 1) + col + 1
			var i11: int = vert_start + (row + 1) * (steps_u + 1) + col + 1
			var i01: int = vert_start + (row + 1) * (steps_u + 1) + col

			var face := GoBuildFace.new()
			face.vertex_indices = [i00, i10, i11, i01]
			face.material_index = material_index
			face.uvs = [
				Vector2(float(col)     / float(steps_u), float(row)     / float(steps_v)),
				Vector2(float(col + 1) / float(steps_u), float(row)     / float(steps_v)),
				Vector2(float(col + 1) / float(steps_u), float(row + 1) / float(steps_v)),
				Vector2(float(col)     / float(steps_u), float(row + 1) / float(steps_v)),
			]
			mesh.faces.append(face)

