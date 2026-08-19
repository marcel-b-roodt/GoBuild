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

## Emitted after every [method bake] (including undo/redo restores).
## The panel subscribes to this to keep the stats label in sync.
signal mesh_changed

enum CollisionType { CONCAVE, CONVEX }

# Self-preload: Godot's startup script scan processes core/ files alphabetically,
# reaching this file before selection_manager.gd.  The explicit preload forces
# SelectionManager to be registered before this script is compiled.
const _SEL_MGR_SCRIPT          := preload("res://addons/go_build/core/selection_manager.gd")
const _PLANAR_UV_SCRIPT        := preload("res://addons/go_build/uv/planar_projection.gd")
const _BOX_UV_SCRIPT           := preload("res://addons/go_build/uv/box_projection.gd")
const _CYLINDRICAL_UV_SCRIPT   := preload("res://addons/go_build/uv/cylindrical_projection.gd")
const _SPHERICAL_UV_SCRIPT     := preload("res://addons/go_build/uv/spherical_projection.gd")
const _MESH_SCRIPT             := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _FACE_SCRIPT             := preload("res://addons/go_build/mesh/go_build_face.gd")

# ---------------------------------------------------------------------------
# Mesh (ungrouped)
# ---------------------------------------------------------------------------

## The editable mesh resource. Assigning a new resource immediately bakes it.
@export var go_build_mesh: GoBuildMesh:
	set(value):
		go_build_mesh = value
		if auto_uv_mode != GoBuildFace.UvMode.NONE and go_build_mesh != null:
			_apply_auto_uv()
		bake()

# ---------------------------------------------------------------------------
# Collision
# ---------------------------------------------------------------------------

@export_group("Collision")

@export var use_collision: bool = false:
	set(value):
		use_collision = value
		_update_collision()

@export var collision_type: GoBuildMeshInstance.CollisionType = CollisionType.CONCAVE:
	set(value):
		collision_type = value
		_update_collision()

@export var collision_layer: int = 1:
	set(value):
		collision_layer = value
		if _collision_body != null and is_instance_valid(_collision_body):
			_collision_body.collision_layer = value

@export var collision_mask: int = 1:
	set(value):
		collision_mask = value
		if _collision_body != null and is_instance_valid(_collision_body):
			_collision_body.collision_mask = value

@export var collision_disable_mode: StaticBody3D.DisableMode = StaticBody3D.DISABLE_MODE_REMOVE:
	set(value):
		collision_disable_mode = value
		if _collision_body != null and is_instance_valid(_collision_body):
			_collision_body.disable_mode = value

@export var collision_input_ray_pickable: bool = false:
	set(value):
		collision_input_ray_pickable = value
		if _collision_body != null and is_instance_valid(_collision_body):
			_collision_body.input_ray_pickable = value

# ---------------------------------------------------------------------------
# Auto UV
# ---------------------------------------------------------------------------

@export_group("Auto UV")

## Global auto-UV mode applied after every modelling operation.
##
## [constant GoBuildFace.UvMode.NONE] disables automatic re-projection.
## Any other value projects all faces whose [member GoBuildFace.uv_projection_mode]
## is [constant GoBuildFace.UvMode.NONE] (i.e. not explicitly set by the user)
## using the chosen algorithm.  Faces with an explicit per-face mode are left
## unchanged; they keep the projection that was last manually applied.
@export var auto_uv_mode: GoBuildFace.UvMode = GoBuildFace.UvMode.PLANAR

## Scale multiplier for auto-UV projection.  Higher values tile the UVs smaller.
@export var auto_uv_scale: float = 1.0

## UV offset applied during auto-UV projection.
@export var auto_uv_offset: Vector2 = Vector2.ZERO

## Seam rotation in radians for cylindrical / spherical auto-UV projection.
@export var auto_uv_seam_rotation: float = 0.0

## Per-instance selection state: which mode is active and which elements are
## selected. The gizmo and panel both hold a reference to this object.
var selection: SelectionManager = SelectionManager.new()

var _collision_body: StaticBody3D = null
var _collision_shape: CollisionShape3D = null
var _collision_debug_mesh: MeshInstance3D = null

## When true, [method bake] applies double-sided (cull-disabled) surface
## override materials so back-faces are visible in the editor viewport.
## Enabled by the plugin while this node is being edited; never exported.
var _edit_cull_override: bool = false

## Persistent ArrayMesh used during parameter-preview so [member mesh] is never
## reassigned (which would trigger Godot's inspector property notification).
## Null when no preview is active.
var _preview_mesh: ArrayMesh = null


func _ready() -> void:
	# After a scene reload the mesh data (vertices, faces, material_slots) is
	# restored by Godot's serialiser, but the derived caches (edges,
	# coincident_groups) are never stored — they are plain vars with no @export.
	# Rebuild them so the gizmo and drag system have consistent data on the
	# very first frame.
	if go_build_mesh != null:
		go_build_mesh.rebuild_edges()
	bake()
	if use_collision:
		_ensure_collision_nodes()
		_update_collision_shape()
		_update_collision_debug_overlay()


func _exit_tree() -> void:
	_remove_collision_nodes()


func _validate_property(property: Dictionary) -> void:
	if not use_collision:
		var hidden := ["collision_type", "collision_layer", "collision_mask",
				"collision_disable_mode", "collision_input_ray_pickable"]
		if property.name in hidden:
			property.usage = property.usage & ~PROPERTY_USAGE_EDITOR
	if property.name == "collision_layer" or property.name == "collision_mask":
		property.hint = PROPERTY_HINT_LAYERS_3D_PHYSICS


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Rebuild the [ArrayMesh] from [member go_build_mesh] and apply it to this node.
## Call this after any mutation to the GoBuildMesh data.
func bake() -> void:
	_bake_internal(true)
	_update_collision_shape()


## Same as [method bake] but does not emit [signal mesh_changed].
## Use when the caller needs to modify the mesh and then do additional work
## before external observers should react — avoids disconnect/reconnect dances.
func bake_silently() -> void:
	_bake_internal(false)
	_update_collision_shape()


func _bake_internal(emit_changed: bool) -> void:
	if go_build_mesh == null:
		mesh = null
		if emit_changed:
			mesh_changed.emit()
		return
	mesh = go_build_mesh.bake()
	_ensure_vertex_alpha_materials()
	if _edit_cull_override:
		_apply_cull_overrides()
	if emit_changed:
		mesh_changed.emit()


## Rebuild the mesh in-place when possible, avoiding [member mesh] reassignment.
##
## This is ideal for high-frequency editor updates (e.g. object-mode world-space
## UV refresh) because it reuses the same [ArrayMesh] object reference.
func bake_in_place() -> void:
	if go_build_mesh == null:
		mesh = null
		return
	var target: ArrayMesh = mesh as ArrayMesh
	if target == null:
		target = ArrayMesh.new()
		mesh = target
	go_build_mesh.bake_into(target)
	if _edit_cull_override:
		_apply_cull_overrides()
	mesh_changed.emit()
	_update_collision_shape()


## Begin preview mode: allocate a persistent [ArrayMesh] and assign it to
## [member mesh] once.  Subsequent [method bake_preview] calls repopulate it
## in-place without reassigning [member mesh], so no inspector notification fires.
## Call [method end_preview] on commit or cancel to restore normal operation.
func begin_preview() -> void:
	if _preview_mesh != null:
		return  # Already in preview mode.
	_preview_mesh = ArrayMesh.new()
	mesh = _preview_mesh


## End preview mode: clear the persistent preview mesh reference.
## The caller must follow with [method bake] or [method restore_and_bake] to
## reassign [member mesh] properly (with cull overrides and [signal mesh_changed]).
func end_preview() -> void:
	_preview_mesh = null


## Preview-only bake: repopulates [member _preview_mesh] in-place without
## reassigning [member mesh], emitting [signal mesh_changed], or applying
## cull overrides.  The inspector does not see a property change.
##
## Requires [method begin_preview] to have been called first.
## Falls back to a regular [method bake] if preview mode is not active.
func bake_preview() -> void:
	if go_build_mesh == null:
		mesh = null
		return
	if _preview_mesh == null:
		# Preview mode not initialised — fall back gracefully.
		bake()
		return
	go_build_mesh.bake_into(_preview_mesh)


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
	mesh_changed.emit()


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
	if auto_uv_mode != GoBuildFace.UvMode.NONE:
		_apply_auto_uv()
	bake()
	update_gizmos()


## Apply the global auto-UV mode to every face that has not been explicitly
## projected.  Faces whose [member GoBuildFace.uv_projection_mode] is not
## [constant GoBuildFace.UvMode.NONE] are re-projected individually using their
## stored per-face params ([member GoBuildFace.uv_scale], [member GoBuildFace.uv_offset],
## [member GoBuildFace.uv_seam_rotation]).
##
## Called automatically after operations when [member auto_uv_mode] is not NONE.
func _apply_auto_uv() -> void:
	if go_build_mesh == null:
		return
	var projection_xform: Transform3D = _get_uv_projection_transform()
	var mode: GoBuildFace.UvMode = auto_uv_mode
	var scale: float = auto_uv_scale
	var offset: Vector2 = auto_uv_offset
	var seam_rot: float = auto_uv_seam_rotation
	var auto_faces: Array[int] = []
	for i: int in go_build_mesh.faces.size():
		var face: GoBuildFace = go_build_mesh.faces[i]
		if face.uv_projection_mode == GoBuildFace.UvMode.NONE:
			auto_faces.append(i)
		else:
			_apply_face_projection(i, face, projection_xform)
	if auto_faces.is_empty() or mode == GoBuildFace.UvMode.NONE:
		return
	match mode:
		GoBuildFace.UvMode.PLANAR:
			PlanarProjection.apply(go_build_mesh, auto_faces, scale, offset)
		GoBuildFace.UvMode.BOX:
			BoxProjection.apply(go_build_mesh, auto_faces, scale, projection_xform, offset)
		GoBuildFace.UvMode.CYLINDRICAL:
			CylindricalProjection.apply(go_build_mesh, auto_faces, scale, projection_xform, offset, seam_rot)
		GoBuildFace.UvMode.SPHERICAL:
			SphericalProjection.apply(go_build_mesh, auto_faces, scale, projection_xform, offset, seam_rot)


## Re-project a single face using its stored per-face projection params.
## Only call this when [member GoBuildFace.uv_projection_mode] is not NONE.
func _apply_face_projection(
		face_idx: int,
		face: GoBuildFace,
		projection_xform: Transform3D = Transform3D.IDENTITY,
) -> void:
	var indices: Array[int] = [face_idx]
	match face.uv_projection_mode:
		GoBuildFace.UvMode.PLANAR:
			PlanarProjection.apply(go_build_mesh, indices, face.uv_scale, face.uv_offset)
		GoBuildFace.UvMode.BOX:
			BoxProjection.apply(go_build_mesh, indices, face.uv_scale, projection_xform, face.uv_offset)
		GoBuildFace.UvMode.CYLINDRICAL:
			CylindricalProjection.apply(
				go_build_mesh, indices,
				face.uv_scale, projection_xform,
				face.uv_offset, face.uv_seam_rotation,
			)
		GoBuildFace.UvMode.SPHERICAL:
			SphericalProjection.apply(
				go_build_mesh, indices,
				face.uv_scale, projection_xform,
				face.uv_offset, face.uv_seam_rotation,
			)


func _get_uv_projection_transform() -> Transform3D:
	# Node3D.global_transform warns when the node is not inside the scene tree.
	# In that case use the local transform, which matches world transform while detached.
	return global_transform if is_inside_tree() else transform


## Returns [code]true[/code] when the current UV setup depends on world-space
## projection and therefore must be refreshed as the node transform changes.
func needs_world_space_uv_refresh() -> bool:
	if go_build_mesh == null:
		return false
	if auto_uv_mode == GoBuildFace.UvMode.NONE:
		return false
	if auto_uv_mode == GoBuildFace.UvMode.BOX \
			or auto_uv_mode == GoBuildFace.UvMode.CYLINDRICAL \
			or auto_uv_mode == GoBuildFace.UvMode.SPHERICAL:
		return true
	# Global mode is planar: still refresh if any face has a world-space manual override.
	for face: GoBuildFace in go_build_mesh.faces:
		if face.uv_projection_mode == GoBuildFace.UvMode.BOX \
				or face.uv_projection_mode == GoBuildFace.UvMode.CYLINDRICAL \
				or face.uv_projection_mode == GoBuildFace.UvMode.SPHERICAL:
			return true
	return false


## Restore the mesh from [param snapshot] and rebake.
## Called by the undo/redo system; also callable directly for programmatic revert.
##
## Calls [method Node3D.update_gizmos] so the selection-highlight gizmo overlay
## is refreshed to match the restored vertex positions.
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
	var has_alpha: bool = go_build_mesh != null \
		and go_build_mesh.vertex_colors.size() == go_build_mesh.vertices.size() \
		and go_build_mesh.has_alpha_below_one()
	for i: int in am.get_surface_count():
		var orig: Material = am.surface_get_material(i)
		if orig is BaseMaterial3D:
			var dup: BaseMaterial3D = (orig as BaseMaterial3D).duplicate()
			dup.cull_mode = BaseMaterial3D.CULL_DISABLED
			dup.vertex_color_use_as_albedo = true
			if has_alpha:
				dup.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			set_surface_override_material(i, dup)
		else:
			var mat := StandardMaterial3D.new()
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = Color(0.7, 0.85, 1.0, 0.6)
			mat.vertex_color_use_as_albedo = true
			set_surface_override_material(i, mat)


## Clear all surface override materials set by [method _apply_cull_overrides].
func _clear_cull_overrides() -> void:
	var am := mesh as ArrayMesh
	if am == null:
		return
	for i: int in am.get_surface_count():
		set_surface_override_material(i, null)


## Ensure material slots have vertex colour and transparency settings
## consistent with whether [member GoBuildMesh.vertex_colors] has any alpha < 1.0.
## When alpha is present, all [BaseMaterial3D] slots get transparency enabled.
func _ensure_vertex_alpha_materials() -> void:
	if go_build_mesh == null:
		return
	var has_colors: bool = go_build_mesh.vertex_colors.size() == go_build_mesh.vertices.size()
	if not has_colors:
		return
	var has_alpha: bool = go_build_mesh.has_alpha_below_one()
	for mat: Material in go_build_mesh.material_slots:
		if mat is BaseMaterial3D:
			var bmat: BaseMaterial3D = mat as BaseMaterial3D
			bmat.vertex_color_use_as_albedo = true
			if has_alpha:
				bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


# ---------------------------------------------------------------------------
# Collision
# ---------------------------------------------------------------------------

func _update_collision() -> void:
	if use_collision:
		if not is_inside_tree():
			call_deferred("_ensure_collision_nodes")
			call_deferred("_update_collision_shape")
			call_deferred("_update_collision_debug_overlay")
			return
		_ensure_collision_nodes()
		_update_collision_shape()
		_update_collision_debug_overlay()
		notify_property_list_changed()
	else:
		_remove_collision_nodes()
		notify_property_list_changed()


func _ensure_collision_nodes() -> void:
	if _collision_body != null and is_instance_valid(_collision_body):
		return
	if not is_inside_tree():
		return
	_collision_body = StaticBody3D.new()
	_collision_body.name = "StaticBody3D"
	_collision_body.collision_layer = collision_layer
	_collision_body.collision_mask = collision_mask
	_collision_body.disable_mode = collision_disable_mode
	_collision_body.input_ray_pickable = collision_input_ray_pickable
	_collision_shape = CollisionShape3D.new()
	_collision_shape.name = "CollisionShape3D"
	_collision_body.add_child(_collision_shape, true)
	# No owner — don't pollute scene saves.
	# Editor debug overlay (Visible Collision Shapes) renders the shape.
	add_child(_collision_body, true)


func _remove_collision_nodes() -> void:
	if _collision_body != null and is_instance_valid(_collision_body):
		var parent := _collision_body.get_parent()
		if parent != null:
			parent.remove_child(_collision_body)
		_collision_body.queue_free()
	_collision_body = null
	_collision_shape = null
	_remove_collision_debug_overlay()


func _update_collision_shape() -> void:
	if not use_collision:
		return
	if _collision_shape == null or not is_instance_valid(_collision_shape):
		return
	var baked_mesh: Mesh = mesh
	if baked_mesh == null:
		_collision_shape.shape = null
		return
	var new_shape: Shape3D = null
	if collision_type == CollisionType.CONCAVE:
		new_shape = baked_mesh.create_trimesh_shape()
	elif collision_type == CollisionType.CONVEX:
		new_shape = baked_mesh.create_convex_shape()
	_collision_shape.shape = new_shape
	_update_collision_debug_overlay()


func _update_collision_debug_overlay() -> void:
	if not Engine.is_editor_hint():
		_remove_collision_debug_overlay()
		return
	if not use_collision or mesh == null:
		_remove_collision_debug_overlay()
		return
	if not is_inside_tree():
		return
	if _collision_shape == null or not is_instance_valid(_collision_shape) \
			or _collision_shape.shape == null:
		_remove_collision_debug_overlay()
		return
	var debug_mesh: Mesh = _collision_shape.shape.get_debug_mesh()
	if _collision_debug_mesh != null and is_instance_valid(_collision_debug_mesh):
		_collision_debug_mesh.mesh = debug_mesh
		_collision_debug_mesh.global_transform = global_transform
		return
	_collision_debug_mesh = MeshInstance3D.new()
	_collision_debug_mesh.name = "CollisionDebugOverlay"
	_collision_debug_mesh.mesh = debug_mesh
	_collision_debug_mesh.global_transform = global_transform
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.0, 0.6, 0.7, 0.15)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_collision_debug_mesh.material_override = mat
	_collision_debug_mesh.owner = null
	add_child(_collision_debug_mesh, true)


func _remove_collision_debug_overlay() -> void:
	if _collision_debug_mesh != null and is_instance_valid(_collision_debug_mesh):
		var parent := _collision_debug_mesh.get_parent()
		if parent != null:
			parent.remove_child(_collision_debug_mesh)
		_collision_debug_mesh.queue_free()
	_collision_debug_mesh = null


func _property_can_revert(property: StringName) -> bool:
	match property:
		&"use_collision":
			return true
		&"collision_type":
			return true
		&"collision_layer":
			return true
		&"collision_mask":
			return true
		&"collision_disable_mode":
			return true
		&"collision_input_ray_pickable":
			return true
	return false


func _property_get_revert(property: StringName) -> Variant:
	match property:
		&"use_collision":
			return false
		&"collision_type":
			return CollisionType.CONCAVE
		&"collision_layer":
			return 1
		&"collision_mask":
			return 1
		&"collision_disable_mode":
			return StaticBody3D.DISABLE_MODE_REMOVE
		&"collision_input_ray_pickable":
			return false
	return false
