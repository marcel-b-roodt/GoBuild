## Gizmo plugin — creates [GoBuildGizmo] instances and owns shared materials.
##
## Register with [method EditorPlugin.add_node_3d_gizmo_plugin] in [code]plugin.gd[/code].
## Materials are created once in [method setup] and reused by every gizmo instance.
@tool
class_name GoBuildGizmoPlugin
extends EditorNode3DGizmoPlugin

# Preload the gizmo script explicitly so its class name is registered before
# _create_gizmo is called, regardless of the editor's script-scan order.
const _GIZMO_SCRIPT := preload("res://addons/go_build/core/go_build_gizmo.gd")

# ── Colour palette ────────────────────────────────────────────────────────
const COLOR_UNSELECTED  := Color(0.85, 0.85, 0.85, 1.0)   ## Unselected verts / edges.
const COLOR_SELECTED    := Color(1.0,  0.55, 0.0,  1.0)   ## Selected elements (Blender orange).
const COLOR_FACE_HINT   := Color(0.4,  0.8,  1.0,  1.0)   ## Unselected face-centre dots.
const COLOR_CONTEXT     := Color(0.55, 0.55, 0.55, 0.5)   ## Faint edge context in vert/face mode.

# ── Shared materials ──────────────────────────────────────────────────────
## Unselected edge lines.
var mat_edge_normal:     StandardMaterial3D
## Selected edge lines.
var mat_edge_selected:   StandardMaterial3D
## Faint context edges shown behind vertex / face overlays.
var mat_edge_context:    StandardMaterial3D
## Unselected vertex handles.
var mat_vertex_normal:   StandardMaterial3D
## Selected vertex handles.
var mat_vertex_selected: StandardMaterial3D
## Unselected face-centre handles.
var mat_face_normal:     StandardMaterial3D
## Selected face-centre handles.
var mat_face_selected:   StandardMaterial3D

var _editor_plugin: EditorPlugin = null


## Call immediately after [code]GoBuildGizmoPlugin.new()[/code] to wire the
## back-reference to the [EditorPlugin] and initialise all shared materials.
func setup(plugin: EditorPlugin) -> void:
	_editor_plugin      = plugin
	mat_edge_normal     = _line_mat(COLOR_UNSELECTED)
	mat_edge_selected   = _line_mat(COLOR_SELECTED)
	mat_edge_context    = _line_mat(COLOR_CONTEXT)
	mat_vertex_normal   = _point_mat(COLOR_UNSELECTED)
	mat_vertex_selected = _point_mat(COLOR_SELECTED)
	mat_face_normal     = _point_mat(COLOR_FACE_HINT)
	mat_face_selected   = _point_mat(COLOR_SELECTED)


func _get_name() -> String:
	return "GoBuildMeshInstance"


func _get_priority() -> int:
	return 1


func _has_gizmo(for_node_3d: Node3D) -> bool:
	return for_node_3d is GoBuildMeshInstance


func _create_gizmo(for_node_3d: Node3D) -> EditorNode3DGizmo:
	if not for_node_3d is GoBuildMeshInstance:
		return null
	return _GIZMO_SCRIPT.new()


## Request the 3D viewport to redraw all active gizmos.
## Called by [GoBuildGizmo] instances when the selection state changes.
func request_redraw() -> void:
	if _editor_plugin:
		_editor_plugin.update_overlays()


# ---------------------------------------------------------------------------
# Material helpers
# ---------------------------------------------------------------------------

## Create an unshaded line material with depth testing enabled.
## [param color] is the albedo colour.
func _line_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color    = color
	mat.render_priority = 1
	return mat


## Create an unshaded point/handle material rendered on top of all geometry.
## [param color] is the albedo colour.
func _point_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color    = color
	mat.no_depth_test   = true
	mat.render_priority = 2
	return mat
