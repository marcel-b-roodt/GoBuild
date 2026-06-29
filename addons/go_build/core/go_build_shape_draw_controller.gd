## Interactive shape draw controller — 3-click primitive insertion.
##
## Manages the [DrawState] finite state machine (IDLE → POSITION → BASE → HEIGHT
## → commit), raycasts against the scene to find placement surfaces, spawns a
## wireframe ghost that updates in real-time, applies grid snap, and finally
## commits the shape via the canonical [code]insert_shape()[/code] path on
## [GoBuildCreateDrawer].
##
## Owned by [GoBuildPlugin]; activated when the user clicks a shape button or
## uses the "Add Shape" context menu.
@tool
class_name GoBuildShapeDrawController
extends RefCounted

enum DrawState { IDLE, POSITION, BASE, HEIGHT }

enum ParentMode { CHILD, SIBLING, ROOT }

# Self-preloads — dependency order.
const _MESH_SCRIPT := \
		preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _MESH_INSTANCE_SCRIPT := \
		preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _SHAPE_PLACEMENT_SCRIPT := \
		preload("res://addons/go_build/core/shape_placement.gd")
const _CATALOG_SCRIPT := \
		preload("res://addons/go_build/mesh/generators/shape_creation_catalog.gd")
const _MAPPING_SCRIPT := \
		preload("res://addons/go_build/mesh/generators/shape_param_mapping.gd")
const _OVERLAY_SCRIPT := \
		preload("res://addons/go_build/core/go_build_shape_draw_overlay.gd")
const _TRANSFORM_HELPERS_SCRIPT := \
		preload("res://addons/go_build/core/go_build_transform_helpers.gd")

const _RAY_LENGTH: float = 4000.0
const _MIN_DIM: float = 0.01
const _CROSSHAIR_SIZE: float = 0.15
const _DIM_SNAP: float = 0.02

var _state: int = DrawState.IDLE
var _shape_name: String = ""
var _extra_params: Dictionary = {}
var _align_to_surface: bool = true
var _parent_mode: int = ParentMode.CHILD
var _plugin: EditorPlugin = null
var _scene_root: Node = null
var _edited_node: GoBuildMeshInstance = null

var _ghost: GoBuildMeshInstance = null
var _ghost_edges: MeshInstance3D = null
var _ghost_aabb: MeshInstance3D = null
var _crosshair: MeshInstance3D = null
var _ghost_material: StandardMaterial3D = null
var _ghost_edge_material: StandardMaterial3D = null
var _crosshair_material: StandardMaterial3D = null
var _ghost_aabb_material: StandardMaterial3D = null

var _ghost_dirty: bool = false
var _last_drawn_key: String = ""
var _last_topology_key: String = ""
var _last_edge_count: int = -1
var _ghost_base_mesh: GoBuildMesh = null

var _anchor_world: Vector3 = Vector3.ZERO
var _hit_normal: Vector3 = Vector3.UP
var _hit_parent: GoBuildMeshInstance = null
var _hit_did_hit: bool = false
var _surface_basis: Basis = Basis.IDENTITY

var _drawn_width: float = 0.0
var _drawn_depth: float = 0.0
var _drawn_height: float = 0.0
var _drag_dir_x: float = 1.0
var _drag_dir_z: float = 1.0

var _snap_step: float = -1.0
var _last_camera: Camera3D = null
var _last_screen_pos: Vector2 = Vector2.ZERO

var _mouse_captured: bool = false
var _prev_mouse_pos: Vector2 = Vector2.ZERO
var _saved_mouse_mode: int = Input.MOUSE_MODE_VISIBLE
var _capture_filter_count: int = 0


func is_active() -> bool:
	return _state != DrawState.IDLE


func is_mouse_captured() -> bool:
	return _mouse_captured


func get_state() -> int:
	return _state


func get_shape_name() -> String:
	return _shape_name


func get_drawn_width() -> float:
	return _drawn_width


func get_drawn_depth() -> float:
	return _drawn_depth


func get_drawn_height() -> float:
	return _drawn_height


func get_extra_params() -> Dictionary:
	return _extra_params


func set_extra_param(key: String, value: Variant) -> void:
	_extra_params[key] = value
	if is_active():
		_ghost_dirty = true


func set_snap_step(step: float) -> void:
	_snap_step = step


func set_align_to_surface(value: bool) -> void:
	if _align_to_surface == value:
		return
	_align_to_surface = value
	if is_active() and _last_camera != null:
		_update_placement(_last_camera, _last_screen_pos)
		_ghost_dirty = true


func set_parent_mode(mode: int) -> void:
	_parent_mode = mode


func start(
		shape_name: String,
		plugin: EditorPlugin,
		align_to_surface: bool,
		_camera: Camera3D = null,
		_screen_pos: Vector2 = Vector2.ZERO,
		edited_node: GoBuildMeshInstance = null,
) -> void:
	cancel()
	_shape_name = shape_name
	_plugin = plugin
	_align_to_surface = align_to_surface
	_scene_root = EditorInterface.get_edited_scene_root()
	_edited_node = edited_node
	_extra_params = _CATALOG_SCRIPT.default_non_drawable_params(shape_name)
	_drawn_width = 0.0
	_drawn_depth = 0.0
	_drawn_height = 0.0
	_drag_dir_x = 1.0
	_drag_dir_z = 1.0
	_snap_step = _TRANSFORM_HELPERS_SCRIPT.get_snap_step(-1.0)
	_state = DrawState.POSITION
	_last_drawn_key = ""
	_last_topology_key = ""
	_last_edge_count = -1
	_ghost_base_mesh = null
	_ensure_ghost_material()


func start_at_position(
		shape_name: String,
		plugin: EditorPlugin,
		align_to_surface: bool,
		camera: Camera3D,
		screen_pos: Vector2,
		edited_node: GoBuildMeshInstance = null,
) -> void:
	cancel()
	_shape_name = shape_name
	_plugin = plugin
	_align_to_surface = align_to_surface
	_scene_root = EditorInterface.get_edited_scene_root()
	_edited_node = edited_node
	_extra_params = _CATALOG_SCRIPT.default_non_drawable_params(shape_name)
	_drawn_width = 0.0
	_drawn_depth = 0.0
	_drawn_height = 0.0
	_drag_dir_x = 1.0
	_drag_dir_z = 1.0
	_snap_step = _TRANSFORM_HELPERS_SCRIPT.get_snap_step(-1.0)
	_state = DrawState.POSITION
	_last_drawn_key = ""
	_last_topology_key = ""
	_last_edge_count = -1
	_ghost_base_mesh = null
	_ensure_ghost_material()
	_last_camera = camera
	_last_screen_pos = screen_pos
	_update_placement(camera, screen_pos)
	_ghost_dirty = true


func cancel() -> void:
	_release_mouse_capture()
	_remove_ghost()
	_state = DrawState.IDLE
	_shape_name = ""
	_extra_params = {}
	_drawn_width = 0.0
	_drawn_depth = 0.0
	_drawn_height = 0.0
	_drag_dir_x = 1.0
	_drag_dir_z = 1.0
	_anchor_world = Vector3.ZERO
	_hit_normal = Vector3.UP
	_hit_parent = null
	_hit_did_hit = false
	_surface_basis = Basis.IDENTITY
	_last_camera = null
	_last_screen_pos = Vector2.ZERO
	_last_drawn_key = ""
	_last_topology_key = ""
	_last_edge_count = -1
	_ghost_base_mesh = null


func handle_input(camera: Camera3D, event: InputEvent) -> int:
	if _state == DrawState.IDLE:
		return 0
	_last_camera = camera
	if event is InputEventMouseMotion:
		_handle_mouse_motion(camera, event as InputEventMouseMotion)
		return 1
	if event is InputEventMouseButton:
		var result := _handle_mouse_button(camera, event as InputEventMouseButton)
		if result:
			return 1
		return 0
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.keycode == KEY_ESCAPE and key.pressed and not key.echo:
			cancel()
			return 1
	return 0


func build_state_label(shift_held: bool, ctrl_held: bool) -> String:
	return _OVERLAY_SCRIPT.state_label(_shape_name, _state, shift_held, ctrl_held)


func build_dims_label() -> String:
	return _OVERLAY_SCRIPT.dims_label(
		_shape_name, _state, _drawn_width, _drawn_depth, _drawn_height)


# ---------------------------------------------------------------------------
# Input handlers
# ---------------------------------------------------------------------------

func _handle_mouse_motion(camera: Camera3D, event: InputEventMouseMotion) -> void:
	var screen_pos: Vector2
	if _mouse_captured:
		if _capture_filter_count > 0:
			if event.relative.length_squared() > 50.0 * 50.0:
				_capture_filter_count -= 1
				return
			_capture_filter_count = 0
		_prev_mouse_pos += event.relative
		screen_pos = _prev_mouse_pos
	else:
		screen_pos = event.position
	_last_screen_pos = screen_pos
	_last_camera = camera
	match _state:
		DrawState.POSITION:
			_update_placement(camera, screen_pos)
			_update_crosshair()
			_ghost_dirty = true
		DrawState.BASE:
			_update_base(camera, screen_pos, Input.is_key_pressed(KEY_SHIFT),
					Input.is_key_pressed(KEY_CTRL))
			_ghost_dirty = true
		DrawState.HEIGHT:
			_update_height(camera, screen_pos, Input.is_key_pressed(KEY_SHIFT),
					Input.is_key_pressed(KEY_CTRL))
			_ghost_dirty = true


func _handle_mouse_button(camera: Camera3D, event: InputEventMouseButton) -> bool:
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		cancel()
		return true
	if event.button_index != MOUSE_BUTTON_LEFT:
		return false
	match _state:
		DrawState.POSITION:
			if event.pressed:
				_anchor_world = _current_hit_pos(camera, event.position)
				_update_placement(camera, event.position)
				_state = DrawState.BASE
				_drawn_width = 0.0
				_drawn_depth = 0.0
				_drawn_height = 0.0
				_drag_dir_x = 1.0
				_drag_dir_z = 1.0
				_hide_ghost()
				_capture_mouse(event.position)
				return true
		DrawState.BASE:
			if not event.pressed:
				if not _MAPPING_SCRIPT.needs_height_step(_shape_name):
					_commit_shape()
					return true
				_state = DrawState.HEIGHT
				_drawn_height = 0.0
				_last_drawn_key = ""
				_last_topology_key = ""
				_last_edge_count = -1
				return true
		DrawState.HEIGHT:
			if event.pressed:
				_commit_shape()
				return true
	return false


func _capture_mouse(initial_pos: Vector2 = Vector2.ZERO) -> void:
	if _mouse_captured:
		return
	_saved_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_mouse_captured = true
	_prev_mouse_pos = initial_pos
	_capture_filter_count = 2


func _release_mouse_capture() -> void:
	if not _mouse_captured:
		return
	Input.mouse_mode = _saved_mouse_mode
	_mouse_captured = false
	_capture_filter_count = 0


# ---------------------------------------------------------------------------
# Placement / raycast
# ---------------------------------------------------------------------------

func _update_placement(camera: Camera3D, screen_pos: Vector2) -> void:
	var edited: GoBuildMeshInstance = _edited_node
	var placement := _SHAPE_PLACEMENT_SCRIPT.find_placement(
			camera, screen_pos, edited, _ghost)
	if placement != null and placement.did_hit:
		_hit_did_hit = true
		_hit_parent = placement.parent
		_hit_normal = placement.hit_normal
	else:
		_hit_did_hit = false
		_hit_parent = null
		_hit_normal = Vector3.UP
	if _align_to_surface:
		_surface_basis = _SHAPE_PLACEMENT_SCRIPT._align_y_to_normal(_hit_normal)
	else:
		_surface_basis = Basis.IDENTITY


func _current_hit_pos(camera: Camera3D, screen_pos: Vector2) -> Vector3:
	var edited: GoBuildMeshInstance = _edited_node
	var placement := _SHAPE_PLACEMENT_SCRIPT.find_placement(
			camera, screen_pos, edited, _ghost)
	if placement != null:
		if _align_to_surface:
			var snap: float = _TRANSFORM_HELPERS_SCRIPT.get_snap_step(_snap_step)
			if snap > 0.0 and Input.is_key_pressed(KEY_CTRL):
				var snapped: Vector3 = Vector3(
					snappedf(placement.world_pos.x, snap),
					placement.world_pos.y,
					snappedf(placement.world_pos.z, snap))
				return snapped
		return placement.world_pos
	return Vector3.ZERO


func _project_to_surface_plane(camera: Camera3D, screen_pos: Vector2) -> Vector3:
	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)
	var plane := Plane(_hit_normal, _anchor_world)
	var hit := plane.intersects_ray(ray_origin, ray_dir)
	if hit != null:
		return hit
	return _anchor_world


func _project_height(camera: Camera3D, screen_pos: Vector2) -> float:
	var normal_dir: Vector3 = _surface_basis.y if _align_to_surface else Vector3.UP
	var cam_forward: Vector3 = -camera.global_basis.z.normalized()
	var plane_normal: Vector3 = cam_forward
	if absf(plane_normal.dot(normal_dir)) > 0.999:
		plane_normal = camera.global_basis.x.normalized()
	var plane := Plane(plane_normal, _anchor_world)
	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)
	var hit := plane.intersects_ray(ray_origin, ray_dir)
	if hit == null:
		return _drawn_height
	var diff: Vector3 = (hit as Vector3) - _anchor_world
	var h: float = diff.dot(normal_dir)
	if h < _MIN_DIM:
		h = _MIN_DIM
	return h


# ---------------------------------------------------------------------------
# Base and height computation
# ---------------------------------------------------------------------------

func _update_base(
		camera: Camera3D,
		screen_pos: Vector2,
		shift_held: bool,
		ctrl_held: bool,
) -> void:
	var target: Vector3 = _project_to_surface_plane(camera, screen_pos)
	var diff: Vector3 = target - _anchor_world
	if diff.is_zero_approx():
		return
	var right: Vector3 = _surface_basis.x if _align_to_surface else Vector3.RIGHT
	var fwd: Vector3 = -_surface_basis.z if _align_to_surface else Vector3.FORWARD
	var signed_w: float = diff.dot(right)
	var signed_d: float = diff.dot(fwd)
	var w: float = absf(signed_w)
	var d: float = absf(signed_d)
	if w < _MIN_DIM and d < _MIN_DIM:
		return
	if shift_held:
		var m: float = maxf(w, d)
		w = m
		d = m
	if ctrl_held:
		var step: float = _TRANSFORM_HELPERS_SCRIPT.get_snap_step(_snap_step)
		if step > 0.0:
			w = snappedf(w, step)
			d = snappedf(d, step)
	_drawn_width = maxf(w, _MIN_DIM)
	_drawn_depth = maxf(d, _MIN_DIM)
	_drag_dir_x = signf(signed_w) if not is_zero_approx(signed_w) else 1.0
	_drag_dir_z = signf(signed_d) if not is_zero_approx(signed_d) else 1.0


func _update_height(
		camera: Camera3D,
		screen_pos: Vector2,
		shift_held: bool,
		ctrl_held: bool,
) -> void:
	var h: float = _project_height(camera, screen_pos)
	if shift_held:
		var m: float = maxf(_drawn_width, _drawn_depth)
		h = m
	if ctrl_held:
		var step: float = _TRANSFORM_HELPERS_SCRIPT.get_snap_step(_snap_step)
		if step > 0.0:
			h = snappedf(h, step)
	var old_h: float = _drawn_height
	_drawn_height = maxf(h, _MIN_DIM)


# ---------------------------------------------------------------------------
# Flush offset — positions shape so it sits on the surface
# ---------------------------------------------------------------------------

## Compute the offset from the anchor point to the shape origin so the
## shape sits flush on the surface (bottom face touching the surface).
##
## In our convention, [member _surface_basis].y points outward from the surface.
## The shape's local -Y face should touch the surface, so we push the origin
## along the outward normal by the distance from origin to the -Y face.
func _compute_draw_offset(aabb: AABB) -> Vector3:
	var bottom_dist: float = maxf(0.0, -aabb.position.y)
	if _align_to_surface:
		return _surface_basis.y * bottom_dist
	return Vector3.UP * bottom_dist


## Compute the offset that positions the mesh so the AABB edge on the anchor
## side aligns with the anchor point.  This accounts for shapes whose local
## origin is not at the AABB center (e.g. arch, which is centered horizontally
## but offset vertically).
##
## Uses the ghost's basis to transform local AABB offsets to world space.
## The drag direction determines which edge of the AABB aligns with the anchor:
## positive drag → the min edge aligns (shape extends in the positive direction).
## For Z, the drag direction uses "fwd" (toward camera = -Z), so a positive
## _drag_dir_z means the user dragged toward the camera (-Z world), and the
## shape should extend in that direction. Since local +Z maps to world +Z
## (opposite to fwd on flat ground), the Z condition is inverted relative
## to X.
func _compute_center_offset(aabb: AABB) -> Vector3:
	var basis: Basis = _surface_basis if _align_to_surface else Basis.IDENTITY
	var neg_x_local: float
	if _drag_dir_x >= 0.0:
		neg_x_local = -aabb.position.x
	else:
		neg_x_local = -(aabb.position.x + aabb.size.x)
	var neg_z_local: float
	if _drag_dir_z < 0.0:
		neg_z_local = -aabb.position.z
	else:
		neg_z_local = -(aabb.position.z + aabb.size.z)
	return basis * Vector3(neg_x_local, 0.0, neg_z_local)


# ---------------------------------------------------------------------------
# Ghost management
# ---------------------------------------------------------------------------

func _ensure_ghost_material() -> void:
	if _ghost_material != null:
		return
	_ghost_material = StandardMaterial3D.new()
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.albedo_color = Color(0.4, 0.85, 1.0, 0.15)
	_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_material.no_depth_test = true
	_ghost_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ghost_edge_material = StandardMaterial3D.new()
	_ghost_edge_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_edge_material.albedo_color = Color(0.55, 0.92, 1.0, 0.85)
	_ghost_edge_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_edge_material.no_depth_test = true
	_crosshair_material = StandardMaterial3D.new()
	_crosshair_material.albedo_color = Color(1.0, 1.0, 1.0, 0.9)
	_crosshair_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_crosshair_material.no_depth_test = true
	_ghost_aabb_material = StandardMaterial3D.new()
	_ghost_aabb_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_aabb_material.albedo_color = Color(1.0, 0.84, 0.0, 0.6)
	_ghost_aabb_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_aabb_material.no_depth_test = true


## Call from the plugin's _process to flush pending ghost updates.
## Coalesces multiple mouse-motion events per frame into a single rebuild.
func tick() -> void:
	if not _ghost_dirty:
		return
	_ghost_dirty = false
	_refresh_ghost()
	_update_crosshair()


func _update_crosshair() -> void:
	if _crosshair == null or not is_instance_valid(_crosshair):
		if _state == DrawState.POSITION:
			_ensure_crosshair()
		else:
			return
	if _state != DrawState.POSITION:
		_crosshair.visible = false
		return
	var pos: Vector3 = _get_current_ghost_pos()
	_crosshair.global_position = pos
	if _align_to_surface and not _surface_basis.is_equal_approx(Basis.IDENTITY):
		_crosshair.global_basis = _surface_basis
	else:
		_crosshair.global_basis = Basis.IDENTITY
	_crosshair.visible = true


func _ensure_crosshair() -> void:
	if _crosshair != null and is_instance_valid(_crosshair):
		return
	if _scene_root == null:
		return
	_ensure_ghost_material()
	var s: float = _CROSSHAIR_SIZE
	var positions := PackedVector3Array([
		Vector3(-s, 0.0, 0.0), Vector3(s, 0.0, 0.0),
		Vector3(0.0, -s, 0.0), Vector3(0.0, s, 0.0),
		Vector3(0.0, 0.0, -s), Vector3(0.0, 0.0, s),
	])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	var line_mesh := ArrayMesh.new()
	line_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	_crosshair = MeshInstance3D.new()
	_crosshair.name = "DrawCrosshair"
	_crosshair.mesh = line_mesh
	_crosshair.material_override = _crosshair_material
	_crosshair.owner = null
	_crosshair.visible = false
	_scene_root.add_child(_crosshair, true)


func _refresh_ghost() -> void:
	if _shape_name.is_empty():
		return
	if _state == DrawState.POSITION:
		_update_crosshair()
		return
	if _state == DrawState.BASE and _drawn_width < _MIN_DIM and _drawn_depth < _MIN_DIM:
		_hide_ghost()
		return
	var params: Dictionary = _MAPPING_SCRIPT.build_params(
		_shape_name, _drawn_width, _drawn_depth, _drawn_height, _extra_params)
	var ellipsoid_scale: Vector3 = Vector3.ONE
	if _MAPPING_SCRIPT.needs_ellipsoid_scale(_shape_name):
		ellipsoid_scale = _MAPPING_SCRIPT.ellipsoid_scale(params)
		params = _MAPPING_SCRIPT.clean_drawn_params(params)
	var full_key: String = _shape_name + "|" + str(_extra_params.hash()) + "|" \
			+ str(snappedf(_drawn_width, _DIM_SNAP)) + "|" \
			+ str(snappedf(_drawn_depth, _DIM_SNAP)) + "|" \
			+ str(snappedf(_drawn_height, _DIM_SNAP)) + "|" \
			+ str(ellipsoid_scale)
	var topology_key: String = _shape_name + "|" + str(_extra_params.hash())
	var scale: Vector3 = _compute_ghost_scale(ellipsoid_scale)
	var scaled_aabb: AABB = _compute_scaled_aabb(scale)
	if full_key == _last_drawn_key and _ghost != null and is_instance_valid(_ghost):
		if _ghost_base_mesh != null:
			_position_ghost_from_aabb(scaled_aabb)
			_ghost.scale = scale
			if _ghost_edges != null and is_instance_valid(_ghost_edges):
				_ghost_edges.global_transform = _ghost.global_transform
			_show_ghost_aabb()
		else:
			_position_ghost(ellipsoid_scale)
		return
	_last_drawn_key = full_key
	var mesh: GoBuildMesh = _CATALOG_SCRIPT.build_mesh(_shape_name, params)
	if mesh == null:
		return
	_ghost_base_mesh = mesh
	_ensure_ghost()
	_ghost.go_build_mesh = mesh
	_ghost.bake_in_place()
	var topology_changed: bool = (topology_key != _last_topology_key)
	if topology_changed:
		_refresh_ghost_edges(mesh)
		_last_topology_key = topology_key
	else:
		_refresh_ghost_edge_positions(mesh)
	_position_ghost(ellipsoid_scale)


func _compute_ghost_scale(ellipsoid_scale: Vector3) -> Vector3:
	if _MAPPING_SCRIPT.needs_ellipsoid_scale(_shape_name):
		return ellipsoid_scale
	if _ghost_base_mesh == null:
		return Vector3.ONE
	var base_aabb: AABB = _ghost_base_mesh.compute_aabb()
	var sx: float = _drawn_width / maxf(base_aabb.size.x, _MIN_DIM)
	var sy: float = _drawn_height / maxf(base_aabb.size.y, _MIN_DIM)
	var sz: float = _drawn_depth / maxf(base_aabb.size.z, _MIN_DIM)
	if _MAPPING_SCRIPT.is_radial(_shape_name):
		var m: float = maxf(sx, sz)
		sx = m
		sz = m
	return Vector3(sx, sy, sz)


func _compute_scaled_aabb(scale: Vector3) -> AABB:
	if _ghost_base_mesh == null:
		return AABB()
	var base_aabb: AABB = _ghost_base_mesh.compute_aabb()
	return AABB(base_aabb.position * scale, base_aabb.size * scale)


func _show_ghost_aabb() -> void:
	if _ghost == null or not is_instance_valid(_ghost):
		return
	if _ghost_aabb == null or not is_instance_valid(_ghost_aabb):
		return
	_ghost_aabb.global_position = _ghost.global_position
	_ghost_aabb.global_basis = _ghost.global_basis.orthonormalized()
	_ghost_aabb.visible = true


func _ensure_ghost() -> void:
	if _ghost != null and is_instance_valid(_ghost):
		return
	if _scene_root == null:
		return
	_ghost = GoBuildMeshInstance.new()
	_ghost.name = _CATALOG_SCRIPT.node_name(_shape_name) + "DrawGhost"
	_ghost.material_override = _ghost_material
	_ghost.owner = null
	_ghost.visible = false
	_scene_root.add_child(_ghost, true)
	_ghost_edges = MeshInstance3D.new()
	_ghost_edges.name = "DrawGhostEdges"
	_ghost_edges.material_override = _ghost_edge_material
	_ghost_edges.owner = null
	_ghost_edges.visible = false
	_scene_root.add_child(_ghost_edges, true)
	_ghost_aabb = MeshInstance3D.new()
	_ghost_aabb.name = "DrawGhostAABB"
	_ghost_aabb.material_override = _ghost_aabb_material
	_ghost_aabb.owner = null
	_ghost_aabb.visible = false
	_scene_root.add_child(_ghost_aabb, true)


func _refresh_ghost_aabb(scaled_aabb: AABB) -> void:
	if _ghost_aabb == null or not is_instance_valid(_ghost_aabb):
		return
	var p: Vector3 = scaled_aabb.position
	var s: Vector3 = scaled_aabb.size
	var positions := PackedVector3Array([
		p, Vector3(p.x + s.x, p.y, p.z),
		Vector3(p.x + s.x, p.y, p.z), Vector3(p.x + s.x, p.y, p.z + s.z),
		Vector3(p.x + s.x, p.y, p.z + s.z), Vector3(p.x, p.y, p.z + s.z),
		Vector3(p.x, p.y, p.z + s.z), p,
		p, Vector3(p.x, p.y + s.y, p.z),
		Vector3(p.x, p.y + s.y, p.z), Vector3(p.x + s.x, p.y + s.y, p.z),
		Vector3(p.x + s.x, p.y + s.y, p.z), Vector3(p.x + s.x, p.y, p.z),
		Vector3(p.x, p.y + s.y, p.z), Vector3(p.x, p.y + s.y, p.z + s.z),
		Vector3(p.x, p.y + s.y, p.z + s.z), Vector3(p.x, p.y, p.z + s.z),
		Vector3(p.x, p.y + s.y, p.z + s.z), Vector3(p.x + s.x, p.y + s.y, p.z + s.z),
		Vector3(p.x + s.x, p.y + s.y, p.z + s.z), Vector3(p.x + s.x, p.y + s.y, p.z),
		Vector3(p.x + s.x, p.y + s.y, p.z), Vector3(p.x + s.x, p.y, p.z),
		Vector3(p.x, p.y, p.z + s.z), Vector3(p.x, p.y + s.y, p.z + s.z),
		Vector3(p.x + s.x, p.y, p.z + s.z), Vector3(p.x + s.x, p.y + s.y, p.z + s.z),
	])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	var aabb_mesh := ArrayMesh.new()
	aabb_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	_ghost_aabb.mesh = aabb_mesh
	_ghost_aabb.scale = Vector3.ONE


func _refresh_ghost_edges(mesh: GoBuildMesh) -> void:
	if _ghost_edges == null or not is_instance_valid(_ghost_edges):
		return
	var positions: PackedVector3Array = []
	var count: int = mesh.edges.size()
	positions.resize(count * 2)
	var i: int = 0
	for edge: GoBuildEdge in mesh.edges:
		positions[i] = mesh.vertices[edge.vertex_a]
		positions[i + 1] = mesh.vertices[edge.vertex_b]
		i += 2
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	var edge_mesh := ArrayMesh.new()
	edge_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	_ghost_edges.mesh = edge_mesh
	_last_edge_count = count


func _refresh_ghost_edge_positions(mesh: GoBuildMesh) -> void:
	if _ghost_edges == null or not is_instance_valid(_ghost_edges):
		return
	var am := _ghost_edges.mesh as ArrayMesh
	if am == null or am.get_surface_count() == 0:
		_refresh_ghost_edges(mesh)
		return
	var count: int = mesh.edges.size()
	if count != _last_edge_count:
		_refresh_ghost_edges(mesh)
		return
	var positions: PackedVector3Array = []
	positions.resize(count * 2)
	var i: int = 0
	for edge: GoBuildEdge in mesh.edges:
		positions[i] = mesh.vertices[edge.vertex_a]
		positions[i + 1] = mesh.vertices[edge.vertex_b]
		i += 2
	am.surface_update_vertex_region(0, 0, positions.to_byte_array())


func _position_ghost(ellipsoid_scale: Vector3) -> void:
	if _ghost == null or not is_instance_valid(_ghost):
		return
	if not _ghost.is_inside_tree():
		return
	var aabb: AABB = _ghost.go_build_mesh.compute_aabb() if _ghost.go_build_mesh != null \
			else AABB()
	var scaled_aabb: AABB = AABB(
		aabb.position * ellipsoid_scale,
		aabb.size * ellipsoid_scale)
	_position_ghost_from_aabb(scaled_aabb)
	_ghost.scale = ellipsoid_scale
	_ghost.visible = true
	if _ghost_edges != null and is_instance_valid(_ghost_edges):
		_ghost_edges.global_transform = _ghost.global_transform
		_ghost_edges.visible = true
	_refresh_ghost_aabb(scaled_aabb)
	_ghost_aabb.global_position = _ghost.global_position
	_ghost_aabb.global_basis = _ghost.global_basis.orthonormalized()
	_ghost_aabb.visible = true


func _position_ghost_from_aabb(scaled_aabb: AABB) -> void:
	var draw_offset: Vector3 = _compute_draw_offset(scaled_aabb)
	var anchor: Vector3 = _anchor_world
	var center_offset: Vector3 = _compute_center_offset(scaled_aabb)
	_ghost.global_position = anchor + draw_offset + center_offset
	if not _surface_basis.is_equal_approx(Basis.IDENTITY):
		_ghost.global_basis = _surface_basis
	else:
		_ghost.global_basis = Basis.IDENTITY


func _get_current_ghost_pos() -> Vector3:
	if _last_camera == null:
		return Vector3.ZERO
	var placement := _SHAPE_PLACEMENT_SCRIPT.find_placement(
		_last_camera, _last_screen_pos, _edited_node, _ghost)
	if placement != null:
		if _align_to_surface:
			var snap: float = _TRANSFORM_HELPERS_SCRIPT.get_snap_step(_snap_step)
			if snap > 0.0 and Input.is_key_pressed(KEY_CTRL):
				return Vector3(
					snappedf(placement.world_pos.x, snap),
					placement.world_pos.y,
					snappedf(placement.world_pos.z, snap))
		return placement.world_pos
	return Vector3.ZERO


func _remove_ghost() -> void:
	if _ghost != null and is_instance_valid(_ghost):
		var parent := _ghost.get_parent()
		if parent != null:
			parent.remove_child(_ghost)
		_ghost.queue_free()
	_ghost = null
	if _ghost_edges != null and is_instance_valid(_ghost_edges):
		var parent := _ghost_edges.get_parent()
		if parent != null:
			parent.remove_child(_ghost_edges)
		_ghost_edges.queue_free()
	_ghost_edges = null
	_last_edge_count = -1
	if _ghost_aabb != null and is_instance_valid(_ghost_aabb):
		var parent := _ghost_aabb.get_parent()
		if parent != null:
			parent.remove_child(_ghost_aabb)
		_ghost_aabb.queue_free()
	_ghost_aabb = null
	if _crosshair != null and is_instance_valid(_crosshair):
		var parent := _crosshair.get_parent()
		if parent != null:
			parent.remove_child(_crosshair)
		_crosshair.queue_free()
	_crosshair = null


func _hide_ghost() -> void:
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.visible = false
	if _ghost_edges != null and is_instance_valid(_ghost_edges):
		_ghost_edges.visible = false
	if _ghost_aabb != null and is_instance_valid(_ghost_aabb):
		_ghost_aabb.visible = false
	if _crosshair != null and is_instance_valid(_crosshair):
		_crosshair.visible = false


# ---------------------------------------------------------------------------
# Commit
# ---------------------------------------------------------------------------

func _commit_shape() -> void:
	if _shape_name.is_empty() or _plugin == null:
		cancel()
		return
	if _drawn_width < _MIN_DIM and _drawn_depth < _MIN_DIM \
			and _drawn_height < _MIN_DIM and _MAPPING_SCRIPT.needs_height_step(_shape_name):
		cancel()
		return
	_release_mouse_capture()
	var params: Dictionary = _MAPPING_SCRIPT.build_params(
		_shape_name, _drawn_width, _drawn_depth, _drawn_height, _extra_params)
	var ellipsoid_scale: Vector3 = Vector3.ONE
	if _MAPPING_SCRIPT.needs_ellipsoid_scale(_shape_name):
		ellipsoid_scale = _MAPPING_SCRIPT.ellipsoid_scale(params)
		params = _MAPPING_SCRIPT.clean_drawn_params(params)
	var node_name: String = _CATALOG_SCRIPT.node_name(_shape_name)
	var node := GoBuildMeshInstance.new()
	node.name = node_name
	node.go_build_mesh = _CATALOG_SCRIPT.build_mesh(_shape_name, params)
	var scene_root: Node = EditorInterface.get_edited_scene_root()
	if scene_root == null:
		cancel()
		return
	var aabb: AABB = node.go_build_mesh.compute_aabb()
	var scaled_aabb: AABB = AABB(
		aabb.position * ellipsoid_scale,
		aabb.size * ellipsoid_scale)
	var draw_offset: Vector3 = _compute_draw_offset(scaled_aabb)
	var anchor: Vector3 = _anchor_world
	var center_offset: Vector3 = _compute_center_offset(scaled_aabb)
	var world_pos: Vector3 = anchor + draw_offset + center_offset
	var world_basis: Basis = _surface_basis
	var parent: Node = scene_root
	var local_pos: Vector3 = world_pos
	var local_basis: Basis = world_basis
	match _parent_mode:
		ParentMode.CHILD:
			if _hit_did_hit and _hit_parent != null and is_instance_valid(_hit_parent):
				parent = _hit_parent
				var inv: Transform3D = _hit_parent.global_transform.affine_inverse()
				local_pos = inv * world_pos
				local_basis = inv.basis * world_basis
		ParentMode.SIBLING:
			if _hit_did_hit and _hit_parent != null and is_instance_valid(_hit_parent):
				var sibling_parent: Node = _hit_parent.get_parent()
				if sibling_parent != null:
					parent = sibling_parent
					var inv: Transform3D = sibling_parent.global_transform.affine_inverse()
					local_pos = inv * world_pos
					local_basis = inv.basis * world_basis
		ParentMode.ROOT:
			pass
	if not ellipsoid_scale.is_equal_approx(Vector3.ONE):
		local_basis = local_basis * Basis.from_scale(ellipsoid_scale)
	var default_mat: Material = load("res://addons/go_build/go_build_material.tres")
	if default_mat != null and node.go_build_mesh != null:
		node.go_build_mesh.material_slots = [default_mat]
	if parent == scene_root:
		node.global_position = local_pos
	else:
		node.position = local_pos
	if not local_basis.is_equal_approx(Basis.IDENTITY):
		node.basis = local_basis
	var ur: EditorUndoRedoManager = _plugin.get_undo_redo()
	ur.create_action("Insert " + node_name)
	ur.add_do_method(parent, "add_child", node, true)
	ur.add_do_method(node, "set_owner", scene_root)
	ur.add_undo_method(parent, "remove_child", node)
	ur.add_undo_reference(node)
	ur.commit_action()
	var es: EditorSelection = EditorInterface.get_selection()
	es.clear()
	es.add_node(node)
	cancel()