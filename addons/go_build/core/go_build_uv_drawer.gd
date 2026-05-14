## Face UV operations drawer for the GoBuild editor panel.
##
## Hosts the four UV-projection buttons (Planar, Box, Cylindrical, Spherical)
## and the param-box used for live previewing scale, offset, and seam rotation.
##
## Drop into any VBoxContainer with [method add_child].  After adding, call
## [method GoBuildDrawer.set_plugin] once and [method GoBuildDrawer.set_target]
## whenever the selected [GoBuildMeshInstance] changes.
##
## Call [method cancel_preview] before switching targets so the snapshot is
## restored cleanly.  The owning panel drives button-state updates by calling
## [method GoBuildDrawer.refresh_buttons] on selection-changed events.
@tool
class_name GoBuildUvDrawer
extends GoBuildDrawer

# Self-preloads — dependency order.
# GoBuildDrawer already preloads SelectionManager and GoBuildMeshInstance, but
# both are required here too since this file is compiled independently.
const _SEL_MGR_SCRIPT_U  := preload("res://addons/go_build/core/selection_manager.gd")
const _MESH_INST_SCRIPT_U := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _DRAWER_SCRIPT_U   := preload("res://addons/go_build/core/go_build_drawer.gd")
const _FACE_SCRIPT       := preload("res://addons/go_build/mesh/go_build_face.gd")
const _UV_PB_SCRIPT      := preload("res://addons/go_build/core/go_build_uv_param_box.gd")
const _PLANAR_SCRIPT     := preload("res://addons/go_build/uv/planar_projection.gd")
const _BOX_SCRIPT        := preload("res://addons/go_build/uv/box_projection.gd")
const _CYL_SCRIPT        := preload("res://addons/go_build/uv/cylindrical_projection.gd")
const _SPH_SCRIPT        := preload("res://addons/go_build/uv/spherical_projection.gd")

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

# UV param-box widget — shown during a live preview.
var _uv_param_box: GoBuildUvParamBox = null

# Active-preview state.
var _uv_preview_snapshot:  Dictionary          = {}
var _uv_preview_faces:     Array[int]          = []
var _uv_preview_mode:      GoBuildFace.UvMode  = GoBuildFace.UvMode.NONE
var _uv_preview_transform: Transform3D         = Transform3D.IDENTITY
var _uv_preview_active:    bool                = false

# UV buttons — kept for enable/disable via refresh_buttons().
var _planar_uv_btn:      Button = null
var _box_uv_btn:         Button = null
var _cylindrical_uv_btn: Button = null
var _spherical_uv_btn:   Button = null

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Cancel any active UV param preview and restore the mesh snapshot.
## Must be called before [method set_target] when switching to a different node.
func cancel_preview() -> void:
	if not _uv_preview_active:
		return
	_uv_preview_active = false
	if _uv_param_box != null:
		_uv_param_box.hide_box()
	if _target != null and not _uv_preview_snapshot.is_empty():
		_target.end_preview()
		_target.go_build_mesh.restore_snapshot(_uv_preview_snapshot)
		_target.bake()
	_uv_preview_snapshot = {}
	_uv_preview_faces    = []


# ---------------------------------------------------------------------------
# External trigger entry points
# ---------------------------------------------------------------------------

## Equivalent to pressing the Planar UV button.
func trigger_planar_uv() -> void:
	_on_planar_uv_pressed()


## Equivalent to pressing the Box UV button.
func trigger_box_uv() -> void:
	_on_box_uv_pressed()


## Equivalent to pressing the Cyl UV button.
func trigger_cylindrical_uv() -> void:
	_on_cylindrical_uv_pressed()


## Equivalent to pressing the Sphere UV button.
func trigger_spherical_uv() -> void:
	_on_spherical_uv_pressed()


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _ready() -> void:
	_setup_drawer("Face UV")

	var grid := GridContainer.new()
	grid.columns = 2
	_content.add_child(grid)

	const _TILE: float = 1.0

	_planar_uv_btn = _op_button("Planar UV",
		"Project selected face(s) onto their dominant axis using %.1f unit tiles.\n"
		% _TILE
		+ "Useful for checker or metre textures during blockout.\n"
		+ "Requires Face mode with \u22651 face selected.")
	_planar_uv_btn.pressed.connect(_on_planar_uv_pressed)
	grid.add_child(_planar_uv_btn)
	_register_op(_planar_uv_btn, _cond_face_any)

	_box_uv_btn = _op_button("Box UV",
		"Project selected face(s) using world-space box mapping (%.1f unit tiles).\n"
		% _TILE
		+ "Adjacent same-axis faces share UV coordinates \u2014 no seam at shared edges.\n"
		+ "Requires Face mode with \u22651 face selected.")
	_box_uv_btn.pressed.connect(_on_box_uv_pressed)
	grid.add_child(_box_uv_btn)
	_register_op(_box_uv_btn, _cond_face_any)

	_cylindrical_uv_btn = _op_button("Cyl UV",
		"Project selected face(s) using cylindrical mapping around the Y axis (%.1f unit tiles).\n"
		% _TILE
		+ "U wraps 0-1 around the Y axis; V scales with height.\n"
		+ "Requires Face mode with \u22651 face selected.")
	_cylindrical_uv_btn.pressed.connect(_on_cylindrical_uv_pressed)
	grid.add_child(_cylindrical_uv_btn)
	_register_op(_cylindrical_uv_btn, _cond_face_any)

	_spherical_uv_btn = _op_button("Sphere UV",
		"Project selected face(s) using spherical (equirectangular) mapping (%.1f unit tiles).\n"
		% _TILE
		+ "U = longitude (0-1 around Y axis); V = latitude (0 = north / +Y, 1 = south / -Y).\n"
		+ "Requires Face mode with \u22651 face selected.")
	_spherical_uv_btn.pressed.connect(_on_spherical_uv_pressed)
	grid.add_child(_spherical_uv_btn)
	_register_op(_spherical_uv_btn, _cond_face_any)

	# UV parameter box — lives below the buttons; shown during a live param preview.
	_uv_param_box = GoBuildUvParamBox.new()
	_uv_param_box.params_changed.connect(_on_uv_params_preview)
	_uv_param_box.apply_requested.connect(_on_uv_params_apply)
	_uv_param_box.cancelled.connect(_on_uv_params_cancelled)
	_content.add_child(_uv_param_box)


# ---------------------------------------------------------------------------
# Condition
# ---------------------------------------------------------------------------

## [code]true[/code] when Face mode is active and \u22651 face is selected.
func _cond_face_any() -> bool:
	return _target != null \
			and _target.selection.get_mode() == SelectionManager.Mode.FACE \
			and not _target.selection.get_selected_faces().is_empty()


# ---------------------------------------------------------------------------
# UV button handlers
# ---------------------------------------------------------------------------

func _on_planar_uv_pressed() -> void:
	_uv_start_preview(GoBuildFace.UvMode.PLANAR, "Planar UV", false)


func _on_box_uv_pressed() -> void:
	_uv_start_preview(GoBuildFace.UvMode.BOX, "Box UV", false)


func _on_cylindrical_uv_pressed() -> void:
	_uv_start_preview(GoBuildFace.UvMode.CYLINDRICAL, "Cyl UV", true)


func _on_spherical_uv_pressed() -> void:
	_uv_start_preview(GoBuildFace.UvMode.SPHERICAL, "Sphere UV", true)


## Begin a UV param-preview for [param mode].
## Takes a mesh snapshot, seeds the param box with the first selected face's
## existing params (when it already uses the same mode), and shows the param box.
func _uv_start_preview(
		mode: GoBuildFace.UvMode,
		action_name: String,
		has_seam: bool,
) -> void:
	if _target == null or _plugin == null:
		return
	if _target.selection.get_mode() != SelectionManager.Mode.FACE:
		return
	var sel_faces: Array[int] = _target.selection.get_selected_faces()
	if sel_faces.is_empty():
		return
	# Cancel any previous preview cleanly before starting a new one.
	if _uv_preview_active:
		cancel_preview()
	# Capture the pre-preview state.
	_uv_preview_snapshot  = _target.go_build_mesh.take_snapshot()
	_uv_preview_faces.assign(sel_faces)
	_uv_preview_mode      = mode
	_uv_preview_transform = _target.global_transform
	_uv_preview_active    = true
	# Enter preview mode so bake_preview reuses the same ArrayMesh.
	_target.begin_preview()
	# Seed the param box from the first face's existing params if applicable.
	var first: GoBuildFace = _target.go_build_mesh.faces[sel_faces[0]]
	var initial_scale:    float   = 1.0
	var initial_offset:   Vector2 = Vector2.ZERO
	var initial_seam_rot: float   = 0.0
	if first.uv_projection_mode == mode:
		initial_scale    = first.uv_scale
		initial_offset   = first.uv_offset
		initial_seam_rot = first.uv_seam_rotation
	_uv_param_box.setup(action_name, has_seam, initial_scale, initial_offset, initial_seam_rot)
	# Apply the initial projection so the user sees the result immediately
	# without needing to nudge a spinbox first.
	_on_uv_params_preview(_uv_param_box.get_params())


## Live-preview handler — restore snapshot, re-project, bake without mesh reassignment.
func _on_uv_params_preview(params: Dictionary) -> void:
	if not _uv_preview_active or _target == null:
		return
	_target.go_build_mesh.restore_snapshot(_uv_preview_snapshot)
	_uv_project_batch(
		_uv_preview_mode,
		_uv_preview_faces,
		params.get("scale", 1.0),
		Vector2(params.get("u_offset", 0.0), params.get("v_offset", 0.0)),
		params.get("seam_rotation", 0.0),
		_uv_preview_transform,
	)
	_target.bake_preview()


## Commit handler — restore/undo baseline then run the operation via undo/redo.
func _on_uv_params_apply(params: Dictionary) -> void:
	if not _uv_preview_active or _target == null or _plugin == null:
		return
	_uv_preview_active = false
	_target.end_preview()
	# Restore to the pre-preview state so the undo snapshot is clean.
	_target.go_build_mesh.restore_snapshot(_uv_preview_snapshot)
	var faces: Array[int]         = _uv_preview_faces.duplicate()
	var mode:  GoBuildFace.UvMode = _uv_preview_mode
	var xform: Transform3D        = _uv_preview_transform
	var scale:    float   = float(params.get("scale", 1.0))
	var offset:   Vector2 = Vector2(
			float(params.get("u_offset", 0.0)),
			float(params.get("v_offset", 0.0)))
	var seam_rot: float = float(params.get("seam_rotation", 0.0))
	_uv_preview_snapshot = {}
	_uv_preview_faces    = []
	_run_op(
		uv_action_name(mode),
		func():
			for fi: int in faces:
				var face: GoBuildFace = _target.go_build_mesh.faces[fi]
				face.uv_projection_mode = mode
				face.uv_scale           = scale
				face.uv_offset          = offset
				face.uv_seam_rotation   = seam_rot
			_uv_project_batch(mode, faces, scale, offset, seam_rot, xform),
		false,
	)


## Cancel handler — restore preview snapshot and bake.
func _on_uv_params_cancelled() -> void:
	if not _uv_preview_active or _target == null:
		return
	_uv_preview_active = false
	if not _uv_preview_snapshot.is_empty():
		_target.end_preview()
		_target.go_build_mesh.restore_snapshot(_uv_preview_snapshot)
		_target.bake()
	_uv_preview_snapshot = {}
	_uv_preview_faces    = []


## Dispatch a UV projection batch without creating an undo entry.
func _uv_project_batch(
		mode: GoBuildFace.UvMode,
		faces: Array[int],
		scale: float,
		offset: Vector2,
		seam_rot: float,
		xform: Transform3D,
) -> void:
	match mode:
		GoBuildFace.UvMode.PLANAR:
			PlanarProjection.apply(_target.go_build_mesh, faces, scale, offset)
		GoBuildFace.UvMode.BOX:
			BoxProjection.apply(_target.go_build_mesh, faces, scale, xform, offset)
		GoBuildFace.UvMode.CYLINDRICAL:
			CylindricalProjection.apply(
				_target.go_build_mesh, faces, scale, xform, offset, seam_rot)
		GoBuildFace.UvMode.SPHERICAL:
			SphericalProjection.apply(
				_target.go_build_mesh, faces, scale, xform, offset, seam_rot)


## Return the undo/redo action name for [param mode].
## Exposed as a static so tests can verify the mapping without a full instance.
static func uv_action_name(mode: GoBuildFace.UvMode) -> String:
	match mode:
		GoBuildFace.UvMode.PLANAR:      return "Planar UV"
		GoBuildFace.UvMode.BOX:         return "Box UV"
		GoBuildFace.UvMode.CYLINDRICAL: return "Cylindrical UV"
		GoBuildFace.UvMode.SPHERICAL:   return "Spherical UV"
	return "UV"
