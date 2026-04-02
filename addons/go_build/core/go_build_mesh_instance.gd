## A [MeshInstance3D] that owns a [GoBuildMesh] resource.
##
## Assign a [GoBuildMesh] to [member go_build_mesh] and the node automatically
## bakes it into a rendered [ArrayMesh]. All modelling operations should call
## [method bake] after mutating the resource to keep the visual mesh in sync.
##
## This is the scene-tree node the GoBuild EditorPlugin edits. Add one via
## [b]Add Node → GoBuildMeshInstance[/b].
@tool
class_name GoBuildMeshInstance
extends MeshInstance3D

# Self-preload: Godot's startup script scan processes core/ files alphabetically,
# reaching this file before selection_manager.gd.  The explicit preload forces
# SelectionManager to be registered before this script is compiled.
const _SEL_MGR_SCRIPT := preload("res://addons/go_build/core/selection_manager.gd")

## The editable mesh resource. Assigning a new resource immediately bakes it.
@export var go_build_mesh: GoBuildMesh:
	set(value):
		go_build_mesh = value
		bake()

## Per-instance selection state: which mode is active and which elements are
## selected. The gizmo and panel both hold a reference to this object.
var selection: SelectionManager = SelectionManager.new()


func _ready() -> void:
	bake()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Rebuild the [ArrayMesh] from [member go_build_mesh] and apply it to this node.
## Call this after any mutation to the GoBuildMesh data.
func bake() -> void:
	if go_build_mesh == null:
		mesh = null
		return
	mesh = go_build_mesh.bake()


## Fast alternative to [method bake] for use during a vertex-position-only drag.
##
## Calls [method GoBuildMesh.build_vertex_position_buffers] to rebuild only the
## packed vertex positions (same triangle-fan order as [method GoBuildMesh.bake])
## and applies each buffer to the existing [ArrayMesh] surface via
## [method ArrayMesh.surface_update_vertex_region].  Normals, UVs, and surface
## count are left unchanged — they remain from the last full [method bake] call.
##
## Falls back to a full [method bake] if [member mesh] is not an [ArrayMesh],
## or if the surface count has changed (topology mismatch).
##
## Always call [method bake] on drag commit to restore correct normals.
func bake_vertex_positions() -> void:
	if go_build_mesh == null:
		mesh = null
		return
	if not (mesh is ArrayMesh):
		bake()
		return
	var am := mesh as ArrayMesh
	var buffers: Array[PackedByteArray] = go_build_mesh.build_vertex_position_buffers()
	if buffers.size() != am.get_surface_count():
		# Surface count mismatch — topology must have changed; full rebuild needed.
		bake()
		return
	for si: int in buffers.size():
		am.surface_update_vertex_region(si, 0, buffers[si])


## Apply [param operation] (a [Callable] that mutates [member go_build_mesh]),
## push an undo/redo action via [param ur], and rebake.
##
## [b]Usage:[/b]
## [codeblock]
## node.apply_operation("Extrude Face",
##     func(): ExtrudeOperation.apply(node.go_build_mesh, faces, 0.5),
##     get_undo_redo())
## [/codeblock]
func apply_operation(
		action_name: String,
		operation: Callable,
		ur: EditorUndoRedoManager,
) -> void:
	var snapshot := go_build_mesh.take_snapshot()
	ur.create_action(action_name)
	ur.add_do_method(self, "_do_operation", operation)
	ur.add_undo_method(self, "restore_and_bake", snapshot)
	ur.commit_action()


## Execute [param operation] and rebake. Called by the undo/redo system.
func _do_operation(operation: Callable) -> void:
	operation.call()
	bake()


## Restore the mesh from [param snapshot] and rebake.
## Called by the undo/redo system; also callable directly for programmatic revert.
func restore_and_bake(snapshot: Dictionary) -> void:
	go_build_mesh.restore_snapshot(snapshot)
	bake()

