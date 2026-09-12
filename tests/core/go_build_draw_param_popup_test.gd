## Draw param popup tests — GdUnit4
##
## [GoBuildDrawParamPopup] mirrors the dock param strip over the viewport:
## one widget per structural spec, edits flow to the draw controller.
@tool
extends GdUnitTestSuite

const _POPUP_SCRIPT := preload("res://addons/go_build/core/go_build_draw_param_popup.gd")
const _CTRL_GD: GDScript = preload(
		"res://addons/go_build/core/go_build_shape_draw_controller.gd")
const _CATALOG_SCRIPT := \
		preload("res://addons/go_build/mesh/generators/shape_creation_catalog.gd")

var _draw_ctrl: GoBuildShapeDrawController = null


func before_test() -> void:
	_draw_ctrl = auto_free(GoBuildShapeDrawController.new())


func _make_popup():
	var p: PanelContainer = _POPUP_SCRIPT.new()
	add_child(p)
	auto_free(p)
	return p


func test_open_hidden_for_shape_without_structural_params() -> void:
	var p = _make_popup()
	p.open("QuadSphere", _draw_ctrl, Rect2(0, 0, 800, 600))
	assert_bool(p.visible).is_false()


func test_open_shows_widgets_for_structural_params() -> void:
	var p = _make_popup()
	p.show()
	p.open("Staircase", _draw_ctrl, Rect2(0, 0, 800, 600))
	assert_bool(p.visible).is_true()
	# Title + rows for specs (steps + flip button) = 1 child (the VBox).
	var specs := ShapeCreationCatalog.non_drawable_param_specs("Staircase")
	assert_int(specs.size()).is_equal(2)
	assert_int(p.get_child_count()).is_equal(1)


func test_open_positions_inside_viewport_rect() -> void:
	var p = _make_popup()
	var rect := Rect2(100, 50, 800, 600)
	p.open("Staircase", _draw_ctrl, rect)
	assert_bool(p.position.x >= rect.position.x).is_true()
	assert_bool(p.position.y >= rect.position.y).is_true()
	assert_bool(p.position.x + p.size.x <= rect.end.x).is_true()


func test_spin_edit_reaches_draw_controller() -> void:
	var p = _make_popup()
	p.open("Staircase", _draw_ctrl, Rect2(0, 0, 800, 600))
	var spin: SpinBox = _find_spin(p)
	assert_that(spin).is_not_null()
	spin.value = 7
	assert_int(int(_draw_ctrl.get_extra_params().get("steps", 0))).is_equal(7)


func test_bool_edit_reaches_draw_controller() -> void:
	var p = _make_popup()
	p.open("Cylinder", _draw_ctrl, Rect2(0, 0, 800, 600))
	var chk: CheckBox = _find_check(p)
	assert_that(chk).is_not_null()
	chk.button_pressed = true
	assert_bool(bool(_draw_ctrl.get_extra_params().get("cap_top", false))).is_true()


func test_close_hides_and_clears_controller_ref() -> void:
	var p = _make_popup()
	p.show()
	p.open("Staircase", _draw_ctrl, Rect2(0, 0, 800, 600))
	p.close()
	assert_bool(p.visible).is_false()
	p._on_spin_changed(3.0, "steps", true)
	assert_bool(_draw_ctrl.get_extra_params().has("steps")).is_false()


# ---------------------------------------------------------------------------
# Params persistence (re-edit contract)
# ---------------------------------------------------------------------------

func test_reedit_merges_polygon_keys_from_meta() -> void:
	# _regenerate_edit_mesh must carry polygon_points / override_normal
	# from the commit meta into the rebuilt params (size keys erased).
	var popup_gd: Variant = _POPUP_SCRIPT
	var src: String = (popup_gd as GDScript).source_code
	assert_bool(src.contains("for poly_key: String in "
			+ "[\"polygon_points\", \"override_normal\"]:")).is_true()
	assert_bool(src.contains("params.erase(\"width\")")).is_true()
	assert_bool(src.contains("params.erase(\"depth\")")).is_true()


func test_draw_controller_writes_params_meta() -> void:
	var src: String = _CTRL_GD.source_code
	assert_bool(src.contains('set_meta("go_build_params"')).is_true()
	assert_bool(src.contains('set_meta("go_build_shape"')).is_true()


func test_committed_drawn_size_staircase_reconstructs_totals() -> void:
	# Regression (user-reported): re-edit seeds drawn size from the mesh
	# AABB (pivot space) instead of the committed params, so editing
	# "steps" rescaled the whole staircase and moved it.  Drawn totals
	# must be reconstructed: w, h = step_height*steps, d = step_depth*steps.
	var p = _make_popup()
	var size: Vector3 = p._committed_drawn_size("Staircase", {
		"steps": 4, "step_width": 1.0, "step_height": 0.25, "step_depth": 0.3,
	})
	assert_float(size.x).is_equal_approx(1.0, 0.001)
	assert_float(size.y).is_equal_approx(1.0, 0.001)
	assert_float(size.z).is_equal_approx(1.2, 0.001)


func test_committed_drawn_size_cube_reads_width_height_depth() -> void:
	var p = _make_popup()
	var size: Vector3 = p._committed_drawn_size("Cube", {
		"width": 2.0, "height": 3.0, "depth": 4.0,
	})
	assert_float(size.x).is_equal_approx(2.0, 0.001)
	assert_float(size.y).is_equal_approx(3.0, 0.001)
	assert_float(size.z).is_equal_approx(4.0, 0.001)


func test_regenerate_keeps_material_slots_and_pivot() -> void:
	# Regression (user-reported): re-edit regenerate wiped committed
	# material_slots and skipped the base-centre pivot shift, so the
	# mesh moved on every edit.
	var p = _make_popup()
	var node: GoBuildMeshInstance = auto_free(GoBuildMeshInstance.new())
	var mesh: GoBuildMesh = _CATALOG_SCRIPT.build_mesh("Cube",
			{"width": 2.0, "height": 2.0, "depth": 2.0})
	var committed_mat := StandardMaterial3D.new()
	mesh.material_slots = [committed_mat]
	_seed_node(node, mesh, {"width": 2.0, "height": 2.0, "depth": 2.0})
	p.open_for_edit(node, "Cube", Rect2(0, 0, 800, 600))
	assert_bool(p.visible).is_true()
	p._edit_params["subdivisions"] = 0
	p._regenerate_edit_mesh()
	var regenerated: GoBuildMesh = node.go_build_mesh
	assert_int(regenerated.material_slots.size()).is_equal(1)
	assert_bool(regenerated.material_slots[0] == committed_mat).is_true()
	# Base-centre pivot: local AABB must be centred on X/Z and sit on y=0.
	var aabb: AABB = regenerated.compute_aabb()
	assert_float(aabb.position.x + aabb.size.x * 0.5).is_equal_approx(0.0, 0.001)
	assert_float(aabb.position.z + aabb.size.z * 0.5).is_equal_approx(0.0, 0.001)
	assert_float(aabb.position.y).is_equal_approx(0.0, 0.001)
	# Pristine state must still match (re-edit stays live after regenerate).
	assert_bool(node.is_pristine_state_valid()).is_true()


func test_regenerate_staircase_steps_preserves_total_size() -> void:
	# Regression (user-reported): changing "steps" on re-edit changed the
	# staircase's size/position instead of only the step count.
	var p = _make_popup()
	var node: GoBuildMeshInstance = auto_free(GoBuildMeshInstance.new())
	var params: Dictionary = {
		"steps": 4, "step_width": 1.0, "step_height": 0.25, "step_depth": 0.3,
	}
	var mesh: GoBuildMesh = _CATALOG_SCRIPT.build_mesh("Staircase", params)
	_seed_node(node, mesh, params)
	p.open_for_edit(node, "Staircase", Rect2(0, 0, 800, 600))
	assert_bool(p.visible).is_true()
	# Popup seeds drawn size from committed params, not the mesh AABB.
	var drawn: Vector3 = p._edit_drawn
	assert_float(drawn.y).is_equal_approx(1.0, 0.001)
	assert_float(drawn.z).is_equal_approx(1.2, 0.001)
	# Change only steps → same total size, different topology.
	p._edit_params["steps"] = 6
	p._regenerate_edit_mesh()
	var regenerated: GoBuildMesh = node.go_build_mesh
	var aabb: AABB = regenerated.compute_aabb()
	assert_float(aabb.size.x).is_equal_approx(1.0, 0.001)
	assert_float(aabb.size.y).is_equal_approx(1.0, 0.001)
	assert_float(aabb.size.z).is_equal_approx(1.2, 0.001)
	assert_int(regenerated.faces.size()).is_equal(2 * 6 + 4)


func test_regenerate_staircase_flip_button_inverts_param() -> void:
	# Flip Direction is a momentary button (not a sticky toggle): press
	# once → params inverted, mesh regenerated, popup stays open.
	var p = _make_popup()
	var node: GoBuildMeshInstance = auto_free(GoBuildMeshInstance.new())
	var params: Dictionary = {
		"steps": 4, "step_width": 1.0, "step_height": 0.25, "step_depth": 0.3,
	}
	var mesh: GoBuildMesh = _CATALOG_SCRIPT.build_mesh("Staircase", params)
	_seed_node(node, mesh, params)
	p.open_for_edit(node, "Staircase", Rect2(0, 0, 800, 600))
	assert_bool(p.visible).is_true()
	p._on_edit_button_pressed("flipped")
	assert_bool(bool(p._edit_params["flipped"])).is_true()
	assert_bool(p.visible).is_true()
	assert_bool(node.is_pristine_state_valid()).is_true()
	var regenerated: GoBuildMesh = node.go_build_mesh
	var riser_n: Vector3 = regenerated.compute_face_normal(regenerated.faces[1])
	assert_float(riser_n.dot(Vector3(0.0, 0.0, 1.0))).is_greater_equal(0.999)
	assert_int(regenerated.faces.size()).is_equal(2 * 4 + 4)
	# Meta updated so a later session re-opens with the flipped baseline.
	assert_bool(bool(node.get_meta("go_build_params").get("flipped", false))).is_true()


func test_popup_survives_repeated_regens() -> void:
	# Regression (user-reported): the second popup edit closed the popup —
	# the first regenerate left the mesh off-pristine, so the pristine
	# guard killed re-edit mode.  Regeneration must re-baseline.
	var p = _make_popup()
	var node: GoBuildMeshInstance = auto_free(GoBuildMeshInstance.new())
	var params: Dictionary = {
		"steps": 4, "step_width": 1.0, "step_height": 0.25, "step_depth": 0.3,
	}
	var mesh: GoBuildMesh = _CATALOG_SCRIPT.build_mesh("Staircase", params)
	_seed_node(node, mesh, params)
	p.open_for_edit(node, "Staircase", Rect2(0, 0, 800, 600))
	p._edit_params["steps"] = 6
	p._regenerate_edit_mesh()
	assert_bool(p.visible).is_true()
	p._on_edit_button_pressed("flipped")
	assert_bool(p.visible).is_true()
	p._edit_params["steps"] = 3
	p._regenerate_edit_mesh()
	assert_bool(p.visible).is_true()
	assert_bool(node.is_pristine_state_valid()).is_true()
	assert_int(node.go_build_mesh.faces.size()).is_equal(2 * 3 + 4)


func test_popup_closes_on_manual_mesh_edit() -> void:
	# The mesh_changed watcher: any edit outside the popup (drag, knife,
	# undo) ends re-edit mode — the params no longer describe the mesh.
	var p = _make_popup()
	var node: GoBuildMeshInstance = auto_free(GoBuildMeshInstance.new())
	var params: Dictionary = {"width": 2.0, "height": 2.0, "depth": 2.0}
	var mesh: GoBuildMesh = _CATALOG_SCRIPT.build_mesh("Cube", params)
	_seed_node(node, mesh, params)
	p.open_for_edit(node, "Cube", Rect2(0, 0, 800, 600))
	assert_bool(p.visible).is_true()
	var gbm: GoBuildMesh = node.go_build_mesh
	var all_idx: Array[int] = []
	all_idx.resize(gbm.vertices.size())
	for i: int in all_idx.size():
		all_idx[i] = i
	gbm.translate_vertices(all_idx, Vector3(0.5, 0, 0))
	gbm.rebuild_edges()
	node.bake()
	assert_bool(p.visible).is_false()


func _seed_node(
		node: GoBuildMeshInstance,
		mesh: GoBuildMesh,
		params: Dictionary,
) -> void:
	# Pivot convention: committed meshes sit base-centre at local origin
	# (the commit path shifts before capturing the pristine state).
	var aabb: AABB = mesh.compute_aabb()
	var pivot := Vector3(
			aabb.position.x + aabb.size.x * 0.5,
			aabb.position.y,
			aabb.position.z + aabb.size.z * 0.5)
	var idx: Array[int] = []
	idx.resize(mesh.vertices.size())
	for i: int in idx.size():
		idx[i] = i
	mesh.translate_vertices(idx, -pivot)
	node.go_build_mesh = mesh
	node.capture_pristine_state()
	node.set_meta("go_build_params", params)


func _find_spin(root: Node) -> SpinBox:
	for child: Node in root.get_children():
		if child is SpinBox:
			return child
		var inner := _find_spin(child)
		if inner != null:
			return inner
	return null


func _find_check(root: Node) -> CheckBox:
	for child: Node in root.get_children():
		if child is CheckBox:
			return child
		var inner := _find_check(child)
		if inner != null:
			return inner
	return null