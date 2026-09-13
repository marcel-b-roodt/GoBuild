## Knife tool input controller.
##
## Collects a closed polyline of clicks ON the mesh surface (like the
## polygon draw tool's POLYGON state), with hover snapping to vertices and
## edges.  On confirm the picked points are handed to [KnifeCutOperation] as
## one undoable op through [method GoBuildMeshInstance.apply_operation].
##
## State machine: IDLE → CUTTING (LMB adds points; click near the first
## point or Enter closes; right-click/Esc cancels).
@tool
class_name GoBuildKnifeController
extends RefCounted

enum State { IDLE, CUTTING }

# Self-preloads — dependency order.
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _MESH_INSTANCE_SCRIPT := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _KNIFE_OP_SCRIPT := preload(
		"res://addons/go_build/mesh/operations/knife_cut_operation.gd")
const _KNIFE_SCRIPT := preload("res://addons/go_build/mesh/knife.gd")
const _SELECTION_MGR_SCRIPT := preload("res://addons/go_build/core/selection_manager.gd")
const _PICKING_SCRIPT := preload("res://addons/go_build/core/picking_helper.gd")
const _DEBUG_SCRIPT := preload("res://addons/go_build/core/go_build_debug.gd")
const _CURSOR_OVERLAY := preload("res://addons/go_build/core/go_build_cursor_overlay.gd")
const _TRANSFORM_HELPERS_SCRIPT := preload(
		"res://addons/go_build/core/go_build_transform_helpers.gd")

const _RAY_LENGTH: float = 4000.0
const _CLOSE_THRESHOLD_PX: float = 14.0
const _VERTEX_SNAP_PX: float = 12.0
const _EDGE_SNAP_PX: float = 8.0
const _HOVER_EDGE_COLOR := Color(1.0, 0.85, 0.3, 0.95)
const _HOVER_DOT_COLOR := Color(1.0, 0.95, 0.5, 1.0)

var _state: int = State.IDLE
var _plugin: EditorPlugin = null
var _edited_node: GoBuildMeshInstance = null
## Picked points: each { face_index, position, snapped_vertex, snapped_edge }.
var _hit_points: Array = []
## Hover snap state from the last mouse motion:
## { face_index, position, snapped_vertex, edge_index, screen } — empty when
## the cursor is off-mesh.
var _hover: Dictionary = {}
var _last_screen_pos := Vector2.ZERO
var _has_screen_pos: bool = false
var _markers: Array[MeshInstance3D] = []
var _marker_mesh: ArrayMesh = null
var _marker_material: StandardMaterial3D = null
var _first_material: StandardMaterial3D = null
var _scene_root: Node = null
## On-screen stroke popup ("Undo Point" / "Close Loop") shown while cutting.
var _popup: PanelContainer = null


func is_active() -> bool:
	return _state != State.IDLE


func get_hit_points() -> Array:
	return _hit_points


## Drop the last recorded point (Backspace / popup "Undo Point") and
## refresh markers.  No-op with fewer than 1 point.
func undo_last_point() -> void:
	if _hit_points.is_empty():
		return
	_hit_points.pop_back()
	print("[Knife] undo point: %d left" % _hit_points.size())
	_update_markers()


## Show the stroke popup (Undo Point / Commit) while cutting.
##
## PanelContainer used as a plain container (shown via [code]visible[/code],
## never [code]popup()[/code]): stable content-driven size without
## registering as a transient popup — transient popups close on outside
## clicks, which swallows the tool's anchor clicks.  Same style/positioning
## contract as the Create Shape Parameters popup (top-right of the
## viewport, opaque stylebox): _plugin_popup_anchor shares the param
## popup's anchor and _popup_stack_offset pushes this panel below the
## param popup when both are visible (popup stack, no overlap).
## The panel exists only while the knife stroke is active; cancel/confirm
## hide it.
func _show_popup() -> void:
	_hide_popup()
	var vp: SubViewport = EditorInterface.get_editor_viewport_3d(0)
	var vp_parent := vp.get_parent() as Control
	if vp == null or vp_parent == null:
		return
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("3a3f47eb")
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8.0)
	panel.add_theme_stylebox_override("panel", style)
	panel.z_index = 100
	var vbox := VBoxContainer.new()
	var title := Label.new()
	title.text = "Knife"
	title.add_theme_font_size_override("font_size", 11)
	vbox.add_child(title)
	var undo_btn := Button.new()
	undo_btn.text = "Undo Point (Backspace)"
	undo_btn.add_theme_font_size_override("font_size", 10)
	undo_btn.pressed.connect(undo_last_point)
	vbox.add_child(undo_btn)
	var close_btn := Button.new()
	close_btn.text = "Commit (Enter / Ctrl+Enter)"
	close_btn.add_theme_font_size_override("font_size", 10)
	close_btn.pressed.connect(_on_commit_button)
	vbox.add_child(close_btn)
	panel.add_child(vbox)
	vp_parent.get_parent().add_child(panel)
	# Top-right of the viewport, directly below the param popup when that
	# is also visible (the plugin's popup stack resolves the offset).
	panel.position = _plugin_popup_anchor() + _popup_stack_offset()
	panel.reset_size()
	panel.visible = true
	_popup = panel


## The popup stack's top-right anchor: vp top-right - margin (the Create
## Shape Parameters popup's anchor), so both popups share one layout rule.
func _plugin_popup_anchor() -> Vector2:
	var vp: SubViewport = EditorInterface.get_editor_viewport_3d(0)
	var vp_parent: Control = vp.get_parent() as Control if vp != null else null
	if vp == null or vp_parent == null:
		var container: Control = EditorInterface.get_base_control()
		return container.get_global_rect().position if container != null \
				else Vector2.ZERO
	var margin := 8.0
	return Vector2(
			vp_parent.get_global_rect().end.x - 180.0 - margin,
			vp_parent.get_global_rect().position.y + margin)


## Vertical offset below the param popup when it is visible (the knife
## popup must coexist, not overlap).  0 when no param popup is showing.
func _popup_stack_offset() -> Vector2:
	if _plugin == null:
		return Vector2.ZERO
	var panel_ref: Variant = _plugin.get("_panel")
	if panel_ref == null or not is_instance_valid(panel_ref as Object):
		return Vector2.ZERO
	var drawer: Variant = (panel_ref as Object).call("get_create_drawer")
	if drawer == null:
		return Vector2.ZERO
	var popup: Control = drawer.call("get_param_popup")
	if popup == null or not is_instance_valid(popup) or not popup.visible:
		return Vector2.ZERO
	return Vector2(0.0, popup.size.y + 8.0)


func _on_commit_button() -> void:
	# Buttons can't distinguish Enter vs Ctrl+Enter — commit with the
	# visual-closure heuristic (same as plain Enter).  Enabled from 2
	# points (seam) upward; the op rejects non-cuttable strokes cleanly.
	_confirm(false)


func _hide_popup() -> void:
	if _popup != null and is_instance_valid(_popup):
		_popup.queue_free()
	_popup = null


## Begin a knife stroke on [param edited_node].
func start(edited_node: GoBuildMeshInstance, plugin: EditorPlugin) -> void:
	# ponytail: raw prints while knife is in debug — route through
	# GoBuildDebug once the tool is stable
	print("[Knife] start called: node=%s mesh=%s dbg=%s" % [
			edited_node.name if edited_node != null else "null",
			str(edited_node != null and edited_node.go_build_mesh != null),
			GoBuildDebug.enabled])
	# Fresh data set — do NOT route through cancel(): that clears the node
	# reference and would look like a toggle-off in logs.
	_reset_data()
	_edited_node = edited_node
	_plugin = plugin
	if _edited_node == null or _edited_node.go_build_mesh == null:
		print("[Knife] start aborted: no edited node or mesh")
		return
	_state = State.CUTTING
	_scene_root = EditorInterface.get_edited_scene_root()
	_show_popup()
	print("[Knife] start: cutting on %s (scene_root=%s)" % [
			_edited_node.name, _scene_root.name if _scene_root != null else "null"])
	if plugin != null:
		plugin.update_overlays()


## Clear stroke data + markers without touching node/plugin refs.
func _reset_data() -> void:
	_clear_markers()
	_hide_popup()
	_hit_points.clear()
	_clear_hover()


func _clear_hover() -> void:
	_hover = {}
	_has_screen_pos = false


func cancel() -> void:
	_clear_markers()
	_hide_popup()
	_state = State.IDLE
	_hit_points.clear()
	_clear_hover()
	_edited_node = null
	_plugin = null
	_scene_root = null
	print("[Knife] cancelled")


## Handle viewport input while cutting.
## Returns 1 consumed, 0 unconsumed.
func handle_input(camera: Camera3D, event: InputEvent, edited_node: GoBuildMeshInstance) -> int:
	if _state != State.CUTTING:
		return 0
	if _edited_node == null or not is_instance_valid(_edited_node) \
			or not _edited_node.is_inside_tree():
		cancel()
		return 0
	if event is InputEventMouseMotion:
		_handle_hover(camera, (event as InputEventMouseMotion).position,
				(event as InputEventMouseMotion).ctrl_pressed)
		return 1
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			cancel()
			return 1
		if key.pressed and not key.echo and key.keycode == KEY_BACKSPACE \
				and not _hit_points.is_empty():
			undo_last_point()
			return 1
		if key.pressed and not key.echo and (key.keycode == KEY_ENTER \
				or key.keycode == KEY_KP_ENTER) and _hit_points.size() >= 2:
			# Enter confirms; Ctrl+Enter forces the closed form regardless of
			# where the cursor sits (the visual-closure heuristic only
			# applies to plain Enter).
			var closed := false
			if not key.ctrl_pressed:
				var first_world: Vector3 = _edited_node.global_transform \
						* (_hit_points[0]["position"] as Vector3)
				var sv: SubViewport = EditorInterface.get_editor_viewport_3d(0)
				if sv != null:
					var cam: Camera3D = sv.get_camera_3d()
					if cam != null and not cam.is_position_behind(first_world):
						closed = _last_screen_pos.distance_to(
								cam.unproject_position(first_world)) \
								< _CLOSE_THRESHOLD_PX
			else:
				closed = true
			return _confirm(closed)
		return 0
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			cancel()
			return 1
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			return _handle_click(camera, mb.position, edited_node,
					mb.ctrl_pressed)
	return 0


## LMB click: snap (vertex → edge → raw) and record the point.
## Blender semantics: vertices and edges SNAP the point (stroke continues);
## completion is only a close-click near the first point or Enter.
func _handle_click(camera: Camera3D, screen_pos: Vector2,
		edited_node: GoBuildMeshInstance, ctrl_held: bool) -> int:
	var node := edited_node if edited_node != null else _edited_node
	if node == null or node.go_build_mesh == null:
		return 0

	# Closing click: near the first point? (green marker in Create Polygon).
	# Guard: needs 3+ points (a 2-point stroke commits via Enter instead)
	# AND the click to be close on SCREEN.
	if not _hit_points.is_empty() and _hit_points.size() >= 3:
		var first_pos: Vector3 = _hit_points[0]["position"]
		var first_world: Vector3 = node.global_transform * first_pos
		if not camera.is_position_behind(first_world):
			var first_screen: Vector2 = camera.unproject_position(first_world)
			if first_screen.distance_to(screen_pos) < _CLOSE_THRESHOLD_PX:
				print("[Knife] close-click completion at first point")
				return _confirm(true)

	# Reuse the hover snap resolution (same pick → snap chain as this click).
	_handle_hover(camera, screen_pos, ctrl_held)
	if _hover.is_empty():
		return 0   # Missed the mesh — ignore click.
	var face_index: int = _hover["face_index"]
	var hit_point: Vector3 = _hover["position"]
	var snapped_vi: int = _hover["snapped_vertex"]
	var snapped_ei: int = _hover["edge_index"]

	# ── Record.
	# Dedupe: identical position to the previous point = double-click bounce.
	if not _hit_points.is_empty():
		var last_pos: Vector3 = _hit_points[_hit_points.size() - 1]["position"]
		if last_pos.distance_to(hit_point) < 1e-3:
			print("[Knife] duplicate point ignored (same as previous)")
			return 1
	# Debug: screen→world trace for the plotted point (pick misalignment
	# investigations — crosshair vs placed point).
	var placed_world: Vector3 = node.global_transform * hit_point
	var placed_screen: Vector2 = camera.unproject_position(placed_world)
	print("[Knife] added point %d: face=%d pos=%s snap=%s edge=%s" % [
			_hit_points.size(), face_index, hit_point, snapped_vi, snapped_ei])
	print("[Knife] pick trace: cursor=%s world=%s back_on_screen=%s (err=%.2fpx)" % [
			screen_pos, placed_world, placed_screen,
			placed_screen.distance_to(screen_pos)])
	_hit_points.append({
		"face_index": face_index,
		"position": hit_point,
		"snapped_vertex": snapped_vi,
		"snapped_edge": Vector2i(snapped_ei, -1) if snapped_ei >= 0 else Vector2i(-1, -1),
	})
	_update_markers()
	return 1


## Resolve the hover snap chain: vertex snap (any visible ring vertex) →
## edge snap (any visible edge) → face pick → raw surface hit.  Snapping
## does NOT require the cursor inside a face — Blender's knife snaps to
## vertices/edges slightly outside the silhouette too.
## Result stored in _hover; empty when the cursor misses the mesh.
func _handle_hover(camera: Camera3D, screen_pos: Vector2, ctrl_held: bool) -> void:
	_last_screen_pos = screen_pos
	_has_screen_pos = true
	var node := _edited_node
	if node == null or node.go_build_mesh == null:
		_clear_hover()
		return
	var gbm := node.go_build_mesh

	# Occlusion culling is ALWAYS on for the knife — even with X-ray ON the
	# knife only snaps what the camera sees (unlike selection, where X-ray
	# exposes hidden elements).  Cutting through the mesh surprised users
	# and produced geometry nobody drew.

	# Context face: the face under the cursor (empty when outside the
	# silhouette — snapping still works, Blender-style, but the run grouping
	# then falls back to a face of the snapped element).
	var ctx := _PICKING_SCRIPT.find_face_hit(camera, screen_pos, node, gbm, true)

	# ── 1. Vertex snap — nearest ring vertex of ANY face within the pixel
	# radius, front-facing only (occlusion via the behind test).
	var snapped_vi := _PICKING_SCRIPT.find_nearest_vertex(
			camera, screen_pos, node, gbm, _VERTEX_SNAP_PX, true)
	if snapped_vi >= 0:
		var fi: int = ctx.get("face_index", -1) if not ctx.is_empty() else -1
		if fi < 0 or not gbm.faces[fi].vertex_indices.has(snapped_vi):
			fi = _face_of_vertex(gbm, snapped_vi)
		_hover = {
			"face_index": fi,
			"position": gbm.vertices[snapped_vi],
			"snapped_vertex": snapped_vi, "edge_index": -1,
			"screen": screen_pos,
		}
		return

	# ── 2. Edge snap — nearest edge of ANY face, occlusion-checked; the point
	# lands ON the edge (Blender behaviour), not at the face ray-hit.
	var snapped_ei: int = _PICKING_SCRIPT.find_nearest_edge(
			camera, screen_pos, node, gbm, _EDGE_SNAP_PX, true)
	if snapped_ei >= 0:
		var e: GoBuildEdge = gbm.edges[snapped_ei]
		var wa: Vector3 = node.global_transform * gbm.vertices[e.vertex_a]
		var wb: Vector3 = node.global_transform * gbm.vertices[e.vertex_b]
		# Snap position, two steps: (1) the perpendicular foot of the
		# cursor on the edge's SCREEN segment (clamped — this is what the
		# snap radius measured), (2) the camera ray through the FOOT's
		# screen position intersected with the 3D edge line.  The previous
		# closest-approach-of-two-lines clamped to the wrong end when the
		# ray's line passed the edge segment (corner jumps, left-side
		# bias on oblique edges); the foot is already clamped in 2D and
		# its ray hits the edge line near the visible spot.
		var sa: Vector2 = camera.unproject_position(wa)
		var sb: Vector2 = camera.unproject_position(wb)
		var seg2 := sb - sa
		var len_sq: float = seg2.length_squared()
		var foot := sb if len_sq < 1e-9 else sa + seg2 * clampf(
				(screen_pos - sa).dot(seg2) / len_sq, 0.0, 1.0)
		var edge_point := _ray_line_hit(camera, foot, wa, wb)
		var fi: int = ctx.get("face_index", -1) if not ctx.is_empty() else -1
		if fi < 0 or not gbm.faces[fi].vertex_indices.has(e.vertex_a) \
				or not gbm.faces[fi].vertex_indices.has(e.vertex_b):
			fi = _face_of_vertex(gbm, e.vertex_a)
		_hover = {
			"face_index": fi,
			# Mesh-local (every other branch stores local — mixed spaces made
			# edge-snapped first points land off-mesh).
			"position": node.global_transform.affine_inverse() * edge_point,
			"snapped_vertex": -1, "edge_index": snapped_ei,
			"screen": screen_pos,
		}
		return

	# ── 3. Raw surface hit (needs the face hit) — Ctrl grid-snaps it
	# (world x/z, Create convention).
	if ctx.is_empty():
		_clear_hover()
		return
	var hit_point: Vector3 = ctx["position"]
	hit_point = _apply_grid_snap(camera, node, node.global_transform * hit_point,
			ctrl_held)
	_hover = {
		"face_index": ctx["face_index"], "position": node.global_transform.affine_inverse() * hit_point,
		"snapped_vertex": -1, "edge_index": -1,
		"screen": screen_pos,
	}


## A face containing [param vi] (the snap context face) — -1 when orphaned.
func _face_of_vertex(gbm: GoBuildMesh, vi: int) -> int:
	var faces: Array[int] = gbm.faces_of_vertex(vi)
	return faces[0] if not faces.is_empty() else -1


## Intersect the camera ray through [param ray_screen] with the 3D edge
## line wa—wb (parametric ray-vs-line solve, parameter clamped to the
## edge).  Falls back to the edge midpoint when parallel.
static func _ray_line_hit(
		camera: Camera3D,
		ray_screen: Vector2,
		wa: Vector3,
		wb: Vector3,
) -> Vector3:
	var hit := GoBuildKnife._ray_line_closest(
			camera.project_ray_origin(ray_screen),
			camera.project_ray_normal(ray_screen), wa, wb)
	if hit.is_empty():
		return wa.lerp(wb, 0.5)
	var t: float = clampf(hit["u"], 0.0, 1.0)
	return wa.lerp(wb, t)


## Grid-snap a raw surface hit when Ctrl is held (Create Shape/Polygon
## convention): x/z quantised to the editor grid step in WORLD space, y kept.
## Vertex/edge snaps stay exact.
func _apply_grid_snap(_camera: Camera3D, _node: GoBuildMeshInstance,
		world_pos: Vector3, ctrl_held: bool) -> Vector3:
	if not ctrl_held:
		return world_pos
	var snap: float = _TRANSFORM_HELPERS_SCRIPT.get_snap_step()
	return Vector3(
			snappedf(world_pos.x, snap),
			world_pos.y,
			snappedf(world_pos.z, snap))


## Confirm: run the op through undo/redo and reset.
func _confirm(closed: bool = false) -> int:
	if _edited_node == null or _plugin == null or _hit_points.size() < 2:
		print("[Knife] confirm aborted: node=%s pts=%d" % [
				str(_edited_node != null), _hit_points.size() if _edited_node != null else 0])
		cancel()
		return 1
	print("[Knife] confirm: running cut on %d points (closed=%s)" % [
			_hit_points.size(), closed])
	var node := _edited_node
	var points: Array = []
	for p: Dictionary in _hit_points:
		points.append(p)
	# Order matters: snapshot BEFORE the cut, apply, bake, then commit the
	# undo action, and only then tear the stroke down.  Cancelling first made
	# the commit look like it never ran when apply failed (no visible change,
	# markers vanish → looks like an undo).
	var gbm := node.go_build_mesh
	var snapshot := gbm.take_snapshot()
	# Screen-space edge crossings: project the stroke through the CURRENT
	# camera and record where it visibly crosses a mesh edge (Blender's knife
	# is a screen-space path — the projected stroke is authoritative).  A
	# straight 3D segment between picks on adjacent faces tunnels the shared
	# corner edge, but on screen it visibly crosses.
	var cam: Camera3D = EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	var edge_hits: Array = []
	if cam != null:
		edge_hits = _KNIFE_SCRIPT.screen_edge_hits(gbm, points, closed, cam,
				node.global_transform)
	var did := KnifeCutOperation.apply(gbm, points, closed, edge_hits)
	print("[Knife] apply result: %s" % did)
	if not did:
		cancel()
		return 1
	node.bake()
	var ur: EditorUndoRedoManager = _plugin.get_undo_redo()
	ur.create_action("Knife Cut")
	ur.add_do_method(node, "restore_and_bake", gbm.take_snapshot())
	ur.add_undo_method(node, "restore_and_bake", snapshot)
	ur.commit_action()
	print("[Knife] commit done — mesh updated, undo available")
	cancel()
	return 1


# ---------------------------------------------------------------------------
# Markers (mirrors Create Polygon: green first vertex, cyan others)
# ---------------------------------------------------------------------------

func _ensure_marker_resources() -> void:
	if _marker_mesh != null:
		return
	# Cyan marker (Create Polygon's _vertex_material).
	_marker_material = StandardMaterial3D.new()
	_marker_material.albedo_color = Color(0.55, 0.92, 1.0, 1.0)
	_marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_material.no_depth_test = true
	# Green marker (Create Polygon's _first_vertex_material).
	_first_material = StandardMaterial3D.new()
	_first_material.albedo_color = Color(0.2, 1.0, 0.4, 1.0)
	_first_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_first_material.no_depth_test = true
	var s := 0.04
	var positions := PackedVector3Array([
		Vector3(-s, -s, -s), Vector3(s, -s, -s), Vector3(s, s, -s), Vector3(-s, s, -s),
		Vector3(-s, -s, s), Vector3(s, -s, s), Vector3(s, s, s), Vector3(-s, s, s),
	])
	var indices := PackedInt32Array([
		0, 2, 1, 0, 3, 2, 4, 5, 6, 4, 6, 7,
		0, 1, 5, 0, 5, 4, 1, 2, 6, 1, 6, 5,
		2, 3, 7, 2, 7, 6, 3, 0, 4, 3, 4, 7,
	])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_INDEX] = indices
	_marker_mesh = ArrayMesh.new()
	_marker_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func _update_markers() -> void:
	_ensure_marker_resources()
	if _scene_root == null or _edited_node == null:
		return
	while _markers.size() < _hit_points.size():
		var mi := MeshInstance3D.new()
		mi.mesh = _marker_mesh
		mi.material_override = _marker_material
		mi.owner = null
		_scene_root.add_child(mi, true)
		_markers.append(mi)
	for i: int in _markers.size():
		if i < _hit_points.size():
			# Positions are node-local; markers live in the scene → world them.
			var wp: Vector3 = _edited_node.global_transform * (_hit_points[i]["position"] as Vector3)
			_markers[i].global_position = wp
			_markers[i].material_override = _first_material if i == 0 else _marker_material
			_markers[i].visible = true
		else:
			_markers[i].visible = false


func _clear_markers() -> void:
	for marker: MeshInstance3D in _markers:
		if is_instance_valid(marker):
			marker.get_parent().remove_child(marker)
			marker.queue_free()
	_markers.clear()


## Draw the active cut path on the viewport overlay: preview polyline between
## recorded points and the state hint.  Called from the plugin's overlay pass.
## The overlay Control is parented to the viewport CONTAINER (not the
## SubViewport), so overlay.get_viewport() is the root window whose
## get_camera_3d() is null — the camera must be passed in instead.
func draw_overlay(overlay: Control, camera: Camera3D) -> void:
	if _state != State.CUTTING or _edited_node == null:
		return
	if not is_instance_valid(_edited_node) or not _edited_node.is_inside_tree():
		cancel()
		return
	if camera == null:
		return
	var font: Font = ThemeDB.fallback_font

	# Polyline through recorded points (world space) — cyan, as Create Polygon.
	var inv: Transform3D = _edited_node.global_transform
	if not _hit_points.is_empty():
		var prev_screen: Vector2 = Vector2.ZERO
		for i: int in _hit_points.size():
			var wp: Vector3 = inv * (_hit_points[i]["position"] as Vector3)
			if camera.is_position_behind(wp):
				continue
			var sp: Vector2 = camera.unproject_position(wp)
			if i > 0:
				overlay.draw_line(prev_screen, sp, Color(0.55, 0.92, 1.0, 0.95), 2.0)
			prev_screen = sp

	_draw_crossing_preview(overlay, camera, inv)
	_draw_hover_highlight(overlay, camera, inv)
	_draw_rubber_band(overlay, camera, inv)
	_draw_crosshair(overlay)
	_draw_hint(overlay, font)


## Pierce preview: for every recorded segment, dots where it crosses an edge
## of the mesh — exactly the vertices the cut will generate (shared between
## neighbouring faces, like Blender's knife).  Drawn as small orange squares.
func _draw_crossing_preview(overlay: Control, camera: Camera3D, inv: Transform3D) -> void:
	if _hit_points.size() < 1 or _edited_node.go_build_mesh == null:
		return
	var gbm := _edited_node.go_build_mesh
	# Segments to preview: recorded (wrapping when closed) + the PENDING
	# segment (last recorded point → current snap position) so the
	# crossings light up while hovering, before the click (Blender's
	# knife preview).
	var segs: Array = []
	for s: int in _hit_points.size() - 1:
		segs.append([_hit_points[s]["position"],
				_hit_points[s + 1]["position"]])
	if _state == State.CUTTING and _hit_points.size() >= 3:
		segs.append([_hit_points[_hit_points.size() - 1]["position"],
				_hit_points[0]["position"]])
	if not _hover.is_empty() and not _hit_points.is_empty():
		segs.append([_hit_points[_hit_points.size() - 1]["position"],
				_hover["position"]])
	for seg_pair: Array in segs:
		var a: Vector3 = seg_pair[0]
		var b: Vector3 = seg_pair[1]
		var wa: Vector3 = _edited_node.global_transform * a
		var wb: Vector3 = _edited_node.global_transform * b
		for e: GoBuildEdge in gbm.edges:
			var ea: Vector3 = _edited_node.global_transform * gbm.vertices[e.vertex_a]
			var eb: Vector3 = _edited_node.global_transform * gbm.vertices[e.vertex_b]
			var hit := _KNIFE_SCRIPT.edge_hit(wa, wb, ea, eb)
			if hit.is_empty() or hit["u"] <= 0.001 or hit["u"] >= 1.0 - 0.001:
				continue
			var hp: Vector3 = inv * (hit["hit"] as Vector3)
			if camera.is_position_behind(hp):
				continue
			var sp: Vector2 = camera.unproject_position(hp)
			overlay.draw_circle(sp, 3.5, _HOVER_DOT_COLOR)
			overlay.draw_arc(sp, 5.0, 0.0, TAU, 12, _HOVER_EDGE_COLOR, 1.0)
	# TUNNELING crossings: segments between picks on adjacent faces pass
	# THROUGH the mesh in 3D but visibly cross the shared edge on screen
	# — the cut injects those (screen_edge_hits at confirm).  Preview
	# them the same way, or multi-face strokes show no crossing dots at
	# all (edge_hit above only finds coplanar 3D crossings).
	if camera != null:
		var preview_pts: Array = []
		for p: Dictionary in _hit_points:
			preview_pts.append(p)
		if not _hover.is_empty() and not _hit_points.is_empty():
			preview_pts.append({"face_index": _hover["face_index"],
					"position": _hover["position"]})
		var preview_closed: bool = _hit_points.size() >= 3
		var tunnel_hits := _KNIFE_SCRIPT.screen_edge_hits(gbm,
				preview_pts, preview_closed, camera, inv)
		for h: Dictionary in tunnel_hits:
			var hp2: Vector3 = inv * (h["point"] as Vector3)
			if camera.is_position_behind(hp2):
				continue
			var sp2: Vector2 = camera.unproject_position(hp2)
			overlay.draw_circle(sp2, 3.5, _HOVER_DOT_COLOR)
			overlay.draw_arc(sp2, 5.0, 0.0, TAU, 12, _HOVER_EDGE_COLOR, 1.0)


## Hover feedback: bright line along the snapped edge, dot on the snapped
## vertex, dot at the on-edge snap position.  Nothing drawn off-mesh.
func _draw_hover_highlight(overlay: Control, camera: Camera3D, inv: Transform3D) -> void:
	if _hover.is_empty():
		return
	var ei: int = _hover["edge_index"]
	if ei >= 0 and ei < _edited_node.go_build_mesh.edges.size():
		var e: GoBuildEdge = _edited_node.go_build_mesh.edges[ei]
		var wa: Vector3 = inv * _edited_node.go_build_mesh.vertices[e.vertex_a]
		var wb: Vector3 = inv * _edited_node.go_build_mesh.vertices[e.vertex_b]
		if not camera.is_position_behind(wa) and not camera.is_position_behind(wb):
			overlay.draw_line(camera.unproject_position(wa), camera.unproject_position(wb),
					_HOVER_EDGE_COLOR, 3.0)
		# Snap landing point: draw the RECORDED snap position directly —
		# the exact point the cut will use.  Re-deriving it by projecting
		# onto the edge's local line drifted (the snap foot is resolved in
		# world screen space; a rotated/scaled node made the local-space
		# re-projection land at a different edge parameter).
		var ep: Vector3 = _hover["position"] as Vector3
		var es: Vector2 = camera.unproject_position(inv * ep)
		overlay.draw_circle(es, 3.0, _HOVER_DOT_COLOR)
	var svi: int = _hover["snapped_vertex"]
	if svi >= 0:
		var wv: Vector3 = inv * _edited_node.go_build_mesh.vertices[svi]
		if not camera.is_position_behind(wv):
			overlay.draw_circle(camera.unproject_position(wv), 4.0, _HOVER_DOT_COLOR)


## Rubber band from the last recorded point to the current snap position
## (what the next click would record); when the cursor is near the first
## point, preview the closing segment instead.  With 3+ points a faint
## closing segment previews the loop polygon.
func _draw_rubber_band(overlay: Control, camera: Camera3D, inv: Transform3D) -> void:
	if _hit_points.is_empty() or not _has_screen_pos:
		return
	var last_wp: Vector3 = inv * (_hit_points[_hit_points.size() - 1]["position"] as Vector3)
	if camera.is_position_behind(last_wp):
		return
	var last_screen: Vector2 = camera.unproject_position(last_wp)

	var first_wp: Vector3 = inv * (_hit_points[0]["position"] as Vector3)
	var closing: bool = _hit_points.size() >= 3 \
			and not camera.is_position_behind(first_wp) \
			and camera.unproject_position(first_wp).distance_to(_last_screen_pos) \
					< _CLOSE_THRESHOLD_PX
	if closing:
		_CURSOR_OVERLAY.draw_rubber_band(overlay, last_screen,
				camera.unproject_position(first_wp))
		return
	if _hover.is_empty():
		return
	_CURSOR_OVERLAY.draw_rubber_band(overlay, last_screen, _last_screen_pos)
	# Faint preview of the loop's closing segment from the snap position.
	if _hit_points.size() >= 3 and not camera.is_position_behind(first_wp):
		var hover_sp: Vector2 = camera.unproject_position(
				inv * (_hover["position"] as Vector3))
		_CURSOR_OVERLAY.draw_closing_preview(overlay, hover_sp,
				camera.unproject_position(first_wp))


## 2D crosshair at the cursor; snap dot when a vertex or edge is snapped.
func _draw_crosshair(overlay: Control) -> void:
	if not _has_screen_pos:
		return
	var snapped: bool = not _hover.is_empty() \
			and ((_hover["snapped_vertex"] as int) >= 0
					or (_hover["edge_index"] as int) >= 0)
	_CURSOR_OVERLAY.draw_crosshair(overlay, _last_screen_pos, snapped)


func _draw_hint(overlay: Control, font: Font) -> void:
	# Hint text — always visible while cutting (matches Create Polygon's
	# state-label behaviour: you must always know the mode is on).
	var hint: String
	if _hit_points.is_empty():
		hint = "Knife — click on the surface to start (Ctrl: grid snap, Esc/right-click cancels)"
	elif _hit_points.size() == 1:
		hint = "Knife — pick the seam's other end, or another point (Esc cancels)"
	elif _hit_points.size() == 2:
		hint = "Knife — Enter commits the seam between these points (Esc cancels)"
	else:
		hint = "Knife — Enter: seam, Ctrl+Enter: closed loop (%d pts)" % _hit_points.size()
	var pos := Vector2(12, overlay.size.y - 12)
	overlay.draw_string(font, pos + Vector2(1, 1), hint,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0, 0, 0, 0.6))
	overlay.draw_string(font, pos, hint,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.6, 0.3))
