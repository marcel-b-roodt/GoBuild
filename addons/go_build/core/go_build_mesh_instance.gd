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

## When true, [method bake] applies double-sided (cull-disabled) surface
## override materials so back-faces are visible in the editor viewport.
## Enabled by the plugin while this node is being edited; never exported.
var _edit_cull_override: bool = false


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
	if _edit_cull_override:
		_apply_cull_overrides()


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
	update_gizmos()


## Restore the mesh from [param snapshot] and rebake.
## Called by the undo/redo system; also callable directly for programmatic revert.
##
## Calls [method Node3D.update_gizmos] so the selection-highlight gizmo overlay
## is refreshed to match the restored vertex positions.  Without this call, the
## gizmo retains the pre-restore (pre-undo/redo) element positions, making
## selected vertices / edges / faces appear at the wrong location or invisible.
func restore_and_bake(snapshot: Dictionary) -> void:
	go_build_mesh.restore_snapshot(snapshot)
	bake()
	update_gizmos()


# ---------------------------------------------------------------------------
# In-editor double-sided override
# ---------------------------------------------------------------------------

## Enable or disable the in-editor back-face-visible material override.
##
## When [param enabled] is [code]true[/code], [method bake] applies a surface
## override material with [constant BaseMaterial3D.CULL_DISABLED] for each
## mesh surface so both sides of every face are visible in the editor viewport.
## Clears the overrides immediately when set to [code]false[/code].
##
## Has no effect at runtime — only the plugin calls this during _edit / _make_visible.
func set_edit_cull_override(enabled: bool) -> void:
	_edit_cull_override = enabled
	if enabled:
		_apply_cull_overrides()
	else:
		_clear_cull_overrides()


## Apply [constant BaseMaterial3D.CULL_DISABLED] surface override materials.
##
## For each surface:
##   - If the surface has a [BaseMaterial3D], duplicate it and set cull_mode.
##   - If the surface has no material, create a plain [StandardMaterial3D] with
##     cull_mode disabled so back-faces are visible with the default look.
##   - [ShaderMaterial] surfaces are left untouched (cull mode is shader-defined).
func _apply_cull_overrides() -> void:
	var am := mesh as ArrayMesh
	if am == null:
		return
	for i: int in am.get_surface_count():
		var orig: Material = am.surface_get_material(i)
		if orig is BaseMaterial3D:
			var dup: BaseMaterial3D = (orig as BaseMaterial3D).duplicate()
			dup.cull_mode = BaseMaterial3D.CULL_DISABLED
			set_surface_override_material(i, dup)
		elif orig == null:
			var mat := StandardMaterial3D.new()
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			set_surface_override_material(i, mat)
		# ShaderMaterial: leave override empty — cull is shader-controlled.


## Clear all surface override materials set by [method _apply_cull_overrides].
func _clear_cull_overrides() -> void:
	var am := mesh as ArrayMesh
	if am == null:
		return
	for i: int in am.get_surface_count():
		set_surface_override_material(i, null)

