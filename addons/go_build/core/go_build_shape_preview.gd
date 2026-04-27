## Parameter-preview UI for primitive shape creation.
##
## Owns the collapsible VBoxContainer shown below the shape buttons while a
## parameterisable shape (Cylinder, Sphere, etc.) is being configured. Emits
## [signal accepted] with the final key and params when the user clicks Accept,
## or [signal cancelled] when the user clicks Cancel or starts a different shape.
##
## Usage (panel side):
##   _shape_preview = GoBuildShapePreview.new()
##   _shape_preview.accepted.connect(_on_shape_preview_accepted)
##   _shape_preview.cancelled.connect(_on_shape_preview_cancelled)
##   add_child(_shape_preview)
##   _shape_preview.start("Cylinder", scene_root)
@tool
class_name GoBuildShapePreview
extends VBoxContainer

## Emitted when the user confirms the shape parameters.
## [param shape_key]  — the shape name string (e.g. "Cylinder")
## [param params]     — the final parameter Dictionary (already normalised)
signal accepted(shape_key: String, params: Dictionary)

## Emitted when the user cancels or the preview is dismissed.
signal cancelled

# Self-preloads — dependency order.
const _MESH_INSTANCE_SCRIPT := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _SHAPE_CATALOG_SCRIPT := \
		preload("res://addons/go_build/mesh/generators/shape_creation_catalog.gd")

var _title_label: Label = null
var _grid: GridContainer = null
var _accept_btn: Button = null
var _cancel_btn: Button = null

var _shape_key: String = ""
var _params: Dictionary = {}
var _preview_node: GoBuildMeshInstance = null
var _scene_root: Node = null


func _ready() -> void:
	visible = false

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 11)
	_title_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	add_child(_title_label)

	_grid = GridContainer.new()
	_grid.columns = 2
	add_child(_grid)

	var actions := HBoxContainer.new()
	add_child(actions)

	_accept_btn = Button.new()
	_accept_btn.text = "Accept"
	_accept_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_accept_btn.pressed.connect(_on_accept_pressed)
	actions.add_child(_accept_btn)

	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel"
	_cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cancel_btn.pressed.connect(_on_cancel_pressed)
	actions.add_child(_cancel_btn)


## Begin a preview for [param shape_name] under [param scene_root].
## If a preview is already active it is cancelled first.
func start(shape_name: String, scene_root: Node) -> void:
	if not Engine.is_editor_hint():
		return
	_cancel_preview_node()
	_shape_key = shape_name
	_params = ShapeCreationCatalog.default_params(shape_name)
	_scene_root = scene_root
	_title_label.text = "%s Parameters" % shape_name
	_rebuild_controls()
	_spawn_preview_node()
	visible = true


## Cancel and hide the preview without emitting [signal accepted].
func cancel() -> void:
	_cancel_preview_node()
	_shape_key = ""
	_params = {}
	_scene_root = null
	visible = false
	cancelled.emit()


## Returns true when a preview is currently active.
func is_active() -> bool:
	return not _shape_key.is_empty()


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _rebuild_controls() -> void:
	for child: Node in _grid.get_children():
		child.queue_free()

	for spec: Dictionary in ShapeCreationCatalog.preview_param_specs(_shape_key):
		var t: String = str(spec.get("type", ""))
		if t == "bool":
			_add_check(str(spec["key"]), str(spec["label"]))
		else:
			_add_spin(
				str(spec["key"]),
				str(spec["label"]),
				float(spec.get("min", 0.0)),
				float(spec.get("max", 1.0)),
				float(spec.get("step", 1.0)),
				t == "int",
			)


func _add_spin(
		key: String,
		label: String,
		min_value: float,
		max_value: float,
		step: float,
		integer: bool,
) -> void:
	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_font_size_override("font_size", 11)
	_grid.add_child(lbl)

	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.allow_greater = false
	spin.allow_lesser = false
	spin.rounded = integer
	spin.value = float(_params.get(key, min_value))
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(_on_spin_changed.bind(key, integer))
	_grid.add_child(spin)


func _add_check(key: String, label: String) -> void:
	var chk := CheckBox.new()
	chk.text = label
	chk.button_pressed = bool(_params.get(key, false))
	chk.toggled.connect(_on_check_toggled.bind(key))
	_grid.add_child(chk)
	_grid.add_child(Control.new())  # keep 2-column layout aligned


func _spawn_preview_node() -> void:
	if _scene_root == null or _shape_key.is_empty():
		return
	_preview_node = GoBuildMeshInstance.new()
	_preview_node.name = ShapeCreationCatalog.node_name(_shape_key) + "Preview"
	_preview_node.go_build_mesh = ShapeCreationCatalog.build_mesh(_shape_key, _params)
	_scene_root.add_child(_preview_node, true)
	_preview_node.owner = null


func _refresh_preview_node() -> void:
	if _shape_key.is_empty() or _preview_node == null:
		return
	if not is_instance_valid(_preview_node):
		_preview_node = null
		return
	var normalized: Dictionary = ShapeCreationCatalog.normalise_params(_shape_key, _params)
	if normalized != _params:
		_params = normalized
		_rebuild_controls()
	_preview_node.go_build_mesh = ShapeCreationCatalog.build_mesh(_shape_key, _params)


func _cancel_preview_node() -> void:
	if _preview_node != null and is_instance_valid(_preview_node):
		var parent := _preview_node.get_parent()
		if parent != null:
			parent.remove_child(_preview_node)
		_preview_node.queue_free()
	_preview_node = null


func _on_spin_changed(value: float, key: String, integer: bool) -> void:
	_params[key] = int(round(value)) if integer else value
	_refresh_preview_node()


func _on_check_toggled(pressed: bool, key: String) -> void:
	_params[key] = pressed
	_refresh_preview_node()


func _on_accept_pressed() -> void:
	if _shape_key.is_empty():
		return
	var key := _shape_key
	var params: Dictionary = _params.duplicate(true)
	_cancel_preview_node()
	_shape_key = ""
	_params = {}
	_scene_root = null
	visible = false
	accepted.emit(key, params)


func _on_cancel_pressed() -> void:
	cancel()
