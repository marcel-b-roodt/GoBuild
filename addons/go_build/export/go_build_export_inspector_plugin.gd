## Inspector plugin that adds an "Export GLB" button to [GoBuildMeshInstance] nodes.
##
## Appears in the Inspector when a [GoBuildMeshInstance] is selected.
## Clicking it opens a file dialog to choose the export path.
@tool
class_name GoBuildExportInspectorPlugin
extends EditorInspectorPlugin

const _MESH_INSTANCE_SCRIPT := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _GLB_EXPORTER_SCRIPT := preload("res://addons/go_build/export/glb_exporter.gd")

var _file_dialog: FileDialog = null


func _can_handle(object: Object) -> bool:
	return object is GoBuildMeshInstance


func _parse_begin(object: Object) -> void:
	var mi: GoBuildMeshInstance = object as GoBuildMeshInstance
	if mi == null:
		return
	var btn := Button.new()
	btn.text = "Export GLB…"
	btn.tooltip_text = "Export this mesh as a binary glTF 2.0 file (.glb)"
	btn.pressed.connect(_on_export_pressed.bind(mi))
	add_custom_control(btn)


func _on_export_pressed(mi: GoBuildMeshInstance) -> void:
	if mi == null or mi.mesh == null:
		push_warning("GoBuildExport: no mesh to export")
		return
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.filters = PackedStringArray(["*.glb ; GLB File"])
		_file_dialog.title = "Export GLB"
		EditorInterface.get_base_control().add_child(_file_dialog)
		_file_dialog.file_selected.connect(_on_file_selected)
	var default_name: String = mi.name + ".glb"
	_file_dialog.current_file = default_name
	_file_dialog.popup_centered_ratio(0.6)


func _on_file_selected(path: String) -> void:
	if not path.to_lower().ends_with(".glb"):
		path += ".glb"
	# ponytail: find the target from the dialog metadata — re-query selection
	var selection: EditorSelection = EditorInterface.get_selection()
	var nodes: Array[Node] = selection.get_selected_nodes()
	var mi: GoBuildMeshInstance = null
	for node: Node in nodes:
		if node is GoBuildMeshInstance:
			mi = node
			break
	if mi == null:
		push_warning("GoBuildExport: no GoBuildMeshInstance selected")
		return
	var err: Error = GlbExporter.export_file(mi, path)
	if err == OK:
		EditorInterface.get_resource_filesystem().scan()
		push_warning("GoBuildExport: exported to %s" % path)
	else:
		push_warning("GoBuildExport: export failed (error %d)" % err)