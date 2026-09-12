## Viewport-anchored panel for structural generator parameters.
##
## Two modes:
##  - **Draw mode** (default): floats over the viewport during the 3-click
##    shape draw; edits flow into the draw controller's extra params.
##  - **Re-edit mode**: bound to an untouched [GoBuildMeshInstance] whose mesh
##    still matches its generator-pristine state; edits regenerate the mesh
##    from the stored shape params.  The node's transform is preserved.
##
## Deliberately a plain [PanelContainer], not a [PopupPanel]: popups close on
## outside clicks, which would swallow the draw flow's anchor clicks.
## Shown/hidden by [GoBuildCreateDrawer] alongside the dock strip.
@tool
class_name GoBuildDrawParamPopup
extends PanelContainer

signal edit_applied

# Self-preloads — dependency order.
const _CATALOG_SCRIPT := \
		preload("res://addons/go_build/mesh/generators/shape_creation_catalog.gd")
const _DRAW_CTRL_SCRIPT := \
		preload("res://addons/go_build/core/go_build_shape_draw_controller.gd")

const _POPUP_WIDTH: float = 180.0
const _POPUP_MARGIN: float = 8.0

## Same treatment as the GoBuild toolbar panel — an explicit opaque
## background (this popup lives under EditorInterface.get_base_control()
## where the default panel theme can render without a visible background).
const _POPUP_BG: Color = Color("3a3f47eb")

var _draw_ctrl: GoBuildShapeDrawController = null

# Re-edit mode state.
var _edit_node: GoBuildMeshInstance = null
var _edit_shape_name: String = ""
var _edit_drawn: Vector3 = Vector3.ZERO
var _edit_params: Dictionary = {}
## Suppresses the mesh_changed watcher while the popup regenerates the
## bound node's own mesh (those bakes must not close re-edit mode).
var _suppress_close: bool = false


## Build one widget per structural param spec and anchor the panel to the
## top-right of [param vp_rect] (screen coords of the 3D viewport).
## Does nothing when the shape has no structural params.
func open(
		shape_name: String,
		draw_ctrl: GoBuildShapeDrawController,
		vp_rect: Rect2,
) -> void:
	_apply_popup_style()
	_draw_ctrl = draw_ctrl
	for child: Node in get_children():
		child.queue_free()
	var specs: Array[Dictionary] = _CATALOG_SCRIPT.non_drawable_param_specs(shape_name)
	if specs.is_empty() or _draw_ctrl == null:
		hide()
		return
	var vbox := VBoxContainer.new()
	var title := Label.new()
	title.text = shape_name
	title.add_theme_font_size_override("font_size", 11)
	vbox.add_child(title)
	for spec: Dictionary in specs:
		var t: String = str(spec.get("type", ""))
		var key: String = str(spec.get("key", ""))
		var label_text: String = str(spec.get("label", key))
		if t == "button":
			# Momentary action, not state: press → fire once, then unpress.
			var btn := Button.new()
			btn.text = label_text
			btn.add_theme_font_size_override("font_size", 10)
			btn.pressed.connect(_on_button_pressed.bind(key))
			vbox.add_child(btn)
		elif t == "bool":
			var chk := CheckBox.new()
			chk.text = label_text
			chk.add_theme_font_size_override("font_size", 10)
			chk.button_pressed = bool(_draw_ctrl.get_extra_params().get(key, false))
			chk.toggled.connect(_on_bool_changed.bind(key))
			vbox.add_child(chk)
		else:
			var row := HBoxContainer.new()
			var lbl := Label.new()
			lbl.text = label_text
			lbl.add_theme_font_size_override("font_size", 10)
			row.add_child(lbl)
			var spin := SpinBox.new()
			spin.min_value = float(spec.get("min", 0.0))
			spin.max_value = float(spec.get("max", 100.0))
			spin.step = float(spec.get("step", 1.0))
			spin.allow_greater = false
			spin.allow_lesser = false
			spin.rounded = t == "int"
			spin.value = float(_draw_ctrl.get_extra_params().get(key, 0))
			spin.custom_minimum_size.x = 80.0
			spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			spin.value_changed.connect(_on_spin_changed.bind(key, t == "int"))
			row.add_child(spin)
			vbox.add_child(row)
	add_child(vbox)
	size = Vector2(_POPUP_WIDTH, 0.0)
	position = Vector2(
			vp_rect.end.x - _POPUP_WIDTH - _POPUP_MARGIN,
			vp_rect.position.y + _POPUP_MARGIN)
	show()


## Explicit panel stylebox — matches the GoBuild toolbar panel so the
## popup always has an opaque background regardless of theme context.
func _apply_popup_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = _POPUP_BG
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8.0)
	add_theme_stylebox_override("panel", style)


func close() -> void:
	_disconnect_mesh_watcher()
	_draw_ctrl = null
	_edit_node = null
	_edit_shape_name = ""
	for child: Node in get_children():
		child.queue_free()
	hide()


## Watch the bound node for manual mesh edits (knife, drag, undo …).  Popup
## regenerations suppress the flag so they don't close themselves.
func _connect_mesh_watcher(node: GoBuildMeshInstance) -> void:
	_disconnect_mesh_watcher()
	if node != null and is_instance_valid(node):
		_suppress_close = true
		node.mesh_changed.connect(_on_edit_node_mesh_changed)
		_suppress_close = false


func _disconnect_mesh_watcher() -> void:
	if _edit_node != null and is_instance_valid(_edit_node) \
			and _edit_node.mesh_changed.is_connected(_on_edit_node_mesh_changed):
		_edit_node.mesh_changed.disconnect(_on_edit_node_mesh_changed)


## Manual mesh edit while re-editing → the params no longer describe the
## mesh; close re-edit mode (the "un-edited" contract).
func _on_edit_node_mesh_changed() -> void:
	if _suppress_close or _edit_node == null:
		return
	close()


## Open in re-edit mode for [param node]: infers the shape from the node name,
## stores draw params from the committed params meta, and rebuilds on edits
## while the mesh stays generator-generated (manual edits close the popup
## via the mesh_changed watcher).
func open_for_edit(node: GoBuildMeshInstance, shape_name: String, vp_rect: Rect2) -> void:
	_apply_popup_style()
	_draw_ctrl = null
	_disconnect_mesh_watcher()
	if node == null or node.go_build_mesh == null \
			or not node.is_pristine_state_valid():
		hide()
		return
	_edit_node = node
	_edit_shape_name = shape_name
	# Params meta is written on the NODE by the commit paths
	# (draw controller / insert_shape) — read it there.
	var committed: Dictionary = node.get_meta("go_build_params", {})
	_edit_params = committed.duplicate(true)
	_edit_drawn = _committed_drawn_size(shape_name, committed)
	for child: Node in get_children():
		child.queue_free()
	var specs: Array[Dictionary] = _CATALOG_SCRIPT.non_drawable_param_specs(shape_name)
	if specs.is_empty():
		hide()
		return
	var vbox := VBoxContainer.new()
	var title := Label.new()
	title.text = "%s (editable)" % shape_name
	title.add_theme_font_size_override("font_size", 11)
	vbox.add_child(title)
	for spec: Dictionary in specs:
		var t: String = str(spec.get("type", ""))
		var key: String = str(spec.get("key", ""))
		var label_text: String = str(spec.get("label", key))
		if t == "button":
			var btn := Button.new()
			btn.text = label_text
			btn.add_theme_font_size_override("font_size", 10)
			btn.pressed.connect(_on_edit_button_pressed.bind(key))
			vbox.add_child(btn)
		elif t == "bool":
			var chk := CheckBox.new()
			chk.text = label_text
			chk.add_theme_font_size_override("font_size", 10)
			chk.button_pressed = bool(_edit_params.get(key, false))
			chk.toggled.connect(_on_edit_bool_changed.bind(key))
			vbox.add_child(chk)
		else:
			var row := HBoxContainer.new()
			var lbl := Label.new()
			lbl.text = label_text
			lbl.add_theme_font_size_override("font_size", 10)
			row.add_child(lbl)
			var spin := SpinBox.new()
			spin.min_value = float(spec.get("min", 0.0))
			spin.max_value = float(spec.get("max", 100.0))
			spin.step = float(spec.get("step", 1.0))
			spin.allow_greater = false
			spin.allow_lesser = false
			spin.rounded = t == "int"
			spin.value = float(_edit_params.get(key, 0))
			spin.custom_minimum_size.x = 80.0
			spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			spin.value_changed.connect(_on_edit_spin_changed.bind(key, t == "int"))
			row.add_child(spin)
			vbox.add_child(row)
	add_child(vbox)
	size = Vector2(_POPUP_WIDTH, 0.0)
	position = Vector2(
			vp_rect.end.x - _POPUP_WIDTH - _POPUP_MARGIN,
			vp_rect.position.y + _POPUP_MARGIN)
	# "Un-edited" indicator: green title while the mesh still matches its
	# generator output — as long as this stays green, every popup edit
	# regenerates from the original insertion.
	title.add_theme_color_override("font_color", Color(0.55, 0.9, 0.55))
	_connect_mesh_watcher(node)
	show()


## Reconstruct the drawn AABB size (width/depth/height in metres) from the
## committed generator params.  Per-step params divide the drawn size by
## steps, so the drawn size must be recomputed rather than read from the
## mesh AABB (which is in base-centre pivot space).
func _committed_drawn_size(shape_name: String, committed: Dictionary) -> Vector3:
	match shape_name:
		"Staircase":
			var steps: int = maxi(int(committed.get("steps", 4)), 1)
			return Vector3(
					float(committed.get("step_width", 1.0)),
					float(committed.get("step_height", 0.25)) * float(steps),
					float(committed.get("step_depth", 0.3)) * float(steps))
		_:
			return Vector3(
					float(committed.get("width", 1.0)),
					float(committed.get("height", 1.0)),
					float(committed.get("depth", 1.0)))


## Regenerate the bound node's mesh from the stored shape + current params.
## Per-step shapes (Staircase) keep the drawn totals fixed: the per-step
## sizes are recomputed from [member _edit_drawn] so changing the step
## count reslices the same block instead of rescaling it.
##
## Regeneration is part of the popup's own editing loop — it re-baselines
## the pristine snapshot and the params meta afterwards, so the next edit
## also regenerates.  The mesh_changed watcher closes the popup only on
## edits made outside the popup (knife, gizmo drag, undo …).
func _regenerate_edit_mesh() -> void:
	if _edit_node == null or not is_instance_valid(_edit_node):
		return
	if not _edit_node.is_pristine_state_valid():
		# Mesh changed outside the popup — params no longer describe it.
		close()
		return
	var params: Dictionary = _edit_params.duplicate()
	params["width"] = _edit_drawn.x
	params["height"] = _edit_drawn.y
	params["depth"] = _edit_drawn.z
	if _edit_shape_name == "Staircase":
		var steps: int = maxi(int(params.get("steps", 4)), 1)
		params["step_height"] = _edit_drawn.y / float(steps)
		params["step_depth"] = _edit_drawn.z / float(steps)
	# Polygon re-edit: keep the stored outline + extrude direction from
	# the commit meta (size keys above don't apply to polygons).
	if _edit_shape_name == "Polygon":
		var committed: Dictionary = _edit_node.get_meta("go_build_params", {})
		for poly_key: String in ["polygon_points", "override_normal"]:
			if committed.has(poly_key):
				params[poly_key] = committed[poly_key]
		params.erase("width")
		params.erase("depth")
	var gbm := _edit_node.go_build_mesh
	var generated: GoBuildMesh = _CATALOG_SCRIPT.build_mesh(_edit_shape_name, params)
	if generated == null:
		return
	# Pivot convention: committed meshes sit base-centre at the local
	# origin — shift the regenerated mesh the same way so the node
	# transform stays valid.
	var aabb: AABB = generated.compute_aabb()
	var pivot := Vector3(
			aabb.position.x + aabb.size.x * 0.5,
			aabb.position.y,
			aabb.position.z + aabb.size.z * 0.5)
	var all_idx: Array[int] = []
	all_idx.resize(generated.vertices.size())
	for i: int in all_idx.size():
		all_idx[i] = i
	generated.translate_vertices(all_idx, -pivot)
	_suppress_close = true
	gbm.vertices = generated.vertices
	gbm.faces = generated.faces
	# Keep the committed material slots — the generator returns an
	# empty array and overwriting would wipe user-assigned materials.
	gbm.rebuild_edges()
	_edit_node.bake()
	# Re-baseline: the regenerated mesh is the new "generator-generated"
	# state, and the live params are the new commit params.
	_edit_node.capture_pristine_state()
	_edit_node.set_meta("go_build_params", params)
	_suppress_close = false
	edit_applied.emit()


func _on_spin_changed(value: float, key: String, is_int: bool) -> void:
	if _draw_ctrl != null:
		_draw_ctrl.set_extra_param(key, int(round(value)) if is_int else value)


func _on_bool_changed(pressed: bool, key: String) -> void:
	if _draw_ctrl != null:
		_draw_ctrl.set_extra_param(key, pressed)


func _on_button_pressed(key: String) -> void:
	# Momentary: invert the current value once, then restore the widget so
	# the Button never reads as a sticky toggle.
	if _draw_ctrl != null:
		_draw_ctrl.set_extra_param(key, not bool(_draw_ctrl.get_extra_params().get(key, false)))


func _on_edit_spin_changed(value: float, key: String, is_int: bool) -> void:
	if _edit_node == null:
		return
	_edit_params[key] = int(round(value)) if is_int else value
	_regenerate_edit_mesh()


func _on_edit_bool_changed(pressed: bool, key: String) -> void:
	if _edit_node == null:
		return
	_edit_params[key] = pressed
	_regenerate_edit_mesh()


func _on_edit_button_pressed(key: String) -> void:
	if _edit_node == null:
		return
	_edit_params[key] = not bool(_edit_params.get(key, false))
	_regenerate_edit_mesh()