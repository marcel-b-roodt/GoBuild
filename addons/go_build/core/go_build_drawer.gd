## Base class for all GoBuild collapsible drawer subcomponents.
##
## Provides:
##   - A standard collapsible header (▶ / ▼ toggle button).
##   - [member _content] [VBoxContainer] — subclasses add their UI children here.
##   - Shared [method _op_button], [method _register_op] helpers.
##   - Shared [method _run_op] that wraps [method GoBuildMeshInstance.apply_operation].
##   - [method set_plugin] / [method set_target] virtual entry points.
##   - [method refresh_buttons] that iterates the [member _op_entries] registry.
##   - [method set_open] / [method is_open] for programmatic open/close.
##
## Subclasses should:
##   1. Call [method _setup_drawer] from their own [method Node._ready], passing
##      the drawer title and whether it starts open.
##   2. Add all widget children to [member _content] after calling [code]_setup_drawer[/code].
##   3. Override [method set_plugin] and [method set_target] calling [code]super[/code].
##   4. Add conditions and buttons via [method _register_op].
##   5. Override [method refresh] for extra refresh logic (e.g. slot list rebuilds);
##      default implementation just calls [method refresh_buttons].
@tool
class_name GoBuildDrawer
extends VBoxContainer

# Self-preloads — SelectionManager and GoBuildMeshInstance are referenced at
# compile time in type annotations and must be pre-registered.
const _SEL_MGR_SCRIPT       := preload("res://addons/go_build/core/selection_manager.gd")
const _MESH_INSTANCE_SCRIPT := preload("res://addons/go_build/core/go_build_mesh_instance.gd")

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _plugin: EditorPlugin          = null
var _target: GoBuildMeshInstance   = null

## All [Button] → [Callable] condition pairs registered via [method _register_op].
## Iterated by [method refresh_buttons] to update [member Button.disabled].
var _op_entries: Array = []

## Interior content container. All subclass UI children go here.
var _content: VBoxContainer = null

# Internal — header toggle button for set_open / is_open.
var _header_btn: Button = null

# Title stored so the header text can be reconstructed on toggle.
var _drawer_title: String = ""


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Provide the owning [EditorPlugin] so operations can call
## [method EditorPlugin.get_undo_redo].
## Subclasses that need the plugin reference for their own logic should
## override this and call [code]super.set_plugin(plugin)[/code] first.
func set_plugin(plugin: EditorPlugin) -> void:
	_plugin = plugin


## Point the drawer at a new mesh instance (or [code]null[/code] to clear).
## Subclasses that cache target-derived state should override this and call
## [code]super.set_target(target)[/code] first.
func set_target(target: GoBuildMeshInstance) -> void:
	_target = target


## Full refresh: update button states and any dynamic UI.
## The default implementation calls [method refresh_buttons].
## Override in subclasses that also need to rebuild dynamic children.
func refresh() -> void:
	refresh_buttons()


## Update [member Button.disabled] for every registered operation button
## based on each button's condition callable.
## Call this on selection-changed events.
func refresh_buttons() -> void:
	for entry in _op_entries:
		entry.button.disabled = not entry.condition.call()


## Expand the drawer (show its content container).
## No-op when already open.
func set_open(value: bool) -> void:
	if _content == null or _header_btn == null:
		return
	if _content.visible == value:
		return
	_content.visible = value
	_header_btn.set_pressed_no_signal(value)
	_header_btn.text = ("\u25bc  " if value else "\u25b6  ") + _drawer_title


## Return [code]true[/code] when the content container is currently visible.
func is_open() -> bool:
	return _content != null and _content.visible


# ---------------------------------------------------------------------------
# Protected UI construction helpers
# ---------------------------------------------------------------------------

## Build the collapsible header and content pair.
## Subclasses must call this from their own [method Node._ready] before
## adding any children to [member _content].
## [param title] is the human-readable section name (e.g. "Vertex").
## [param open] sets the initial visible state.
func _setup_drawer(title: String, open: bool = false) -> void:
	_drawer_title = title

	_header_btn = Button.new()
	_header_btn.text = ("\u25bc  " if open else "\u25b6  ") + title
	_header_btn.toggle_mode = true
	_header_btn.button_pressed = open
	_header_btn.flat = true
	_header_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_header_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_btn.add_theme_font_size_override("font_size", 11)
	add_child(_header_btn)

	_content = VBoxContainer.new()
	_content.visible = open
	add_child(_content)

	_header_btn.toggled.connect(func(pressed: bool) -> void:
		_content.visible = pressed
		_header_btn.text = ("\u25bc  " if pressed else "\u25b6  ") + _drawer_title
	)


## Create a standard disabled operation [Button] with full-width sizing.
func _op_button(text: String, tooltip: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 11)
	btn.tooltip_text = tooltip
	btn.disabled = true
	return btn


## Register [param btn] so [method refresh_buttons] will enable it when
## [param condition].call() returns [code]true[/code] and disable it otherwise.
## Call once per button inside [method Node._ready], after each button is added
## to its parent container.
func _register_op(btn: Button, condition: Callable) -> void:
	_op_entries.append({"button": btn, "condition": condition})


## Apply [param op_callable] as a single undo/redo [param action_name] on the
## active target, then optionally clear the selection and refresh gizmos.
##
## Panel-level stats and button refresh are driven by the
## [signal GoBuildMeshInstance.mesh_changed] signal emitted by
## [method GoBuildMeshInstance.bake] — no explicit call needed here.
## Set [param clear_selection] to [code]false[/code] for operations that should
## preserve the selection (e.g. Flip Normals, material assignment).
func _run_op(
		action_name: String,
		op_callable: Callable,
		clear_selection: bool = true,
) -> void:
	if _target == null or _plugin == null:
		return
	_target.apply_operation(action_name, op_callable, _plugin.get_undo_redo())
	if clear_selection:
		_target.selection.clear()
	_target.update_gizmos()


# ---------------------------------------------------------------------------
# Post-commit selection helpers
# ---------------------------------------------------------------------------

## Returns a [Callable] that sets [param node]'s edge selection to
## [param edge_indices] and refreshes gizmos. Intended to be used as
## [member GoBuildParamPreview.post_commit_fn] or
## [member GoBuildDragOperation.post_commit_fn].
##
## Example:
##   [codeblock]
##   preview.post_commit_fn = _make_select_edges_fn(_target, new_edges)
##   [/codeblock]
static func _make_select_edges_fn(
		node: GoBuildMeshInstance,
		edge_indices: Array[int],
) -> Callable:
	return func() -> void:
		if node == null or not is_instance_valid(node):
			return
		if edge_indices.is_empty():
			return
		node.selection.set_mode(SelectionManager.Mode.EDGE)
		node.selection.set_selected_edges(edge_indices)
		node.update_gizmos()


## Returns a [Callable] that sets [param node]'s face selection to
## [param face_indices] and refreshes gizmos.
static func _make_select_faces_fn(
		node: GoBuildMeshInstance,
		face_indices: Array[int],
) -> Callable:
	return func() -> void:
		if node == null or not is_instance_valid(node):
			return
		if face_indices.is_empty():
			return
		node.selection.set_mode(SelectionManager.Mode.FACE)
		node.selection.set_selected_faces(face_indices)
		node.update_gizmos()


## Returns a [Callable] that sets [param node]'s vertex selection to
## [param vertex_indices] and refreshes gizmos.
static func _make_select_vertices_fn(
		node: GoBuildMeshInstance,
		vertex_indices: Array[int],
) -> Callable:
	return func() -> void:
		if node == null or not is_instance_valid(node):
			return
		if vertex_indices.is_empty():
			return
		node.selection.set_mode(SelectionManager.Mode.VERTEX)
		node.selection.set_selected_vertices(vertex_indices)
		node.update_gizmos()
