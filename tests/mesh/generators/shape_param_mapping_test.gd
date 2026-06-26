## ShapeParamMapping unit tests.
##
## Verifies that build_params produces correct generator parameters and
## ellipsoid_scale values for each shape, especially the arch which uses
## _scale_x and _scale_y (but not _scale_z since depth maps directly).
extends GdUnitTestSuite

const _MAPPING_SCRIPT := preload("res://addons/go_build/mesh/generators/shape_param_mapping.gd")


# ---------------------------------------------------------------------------
# Cube
# ---------------------------------------------------------------------------

func test_cube_params_uniform() -> void:
	var p := ShapeParamMapping.build_params("Cube", 2.0, 3.0, 4.0)
	assert_float(p["width"]).is_equal(2.0)
	assert_float(p["height"]).is_equal(4.0)
	assert_float(p["depth"]).is_equal(3.0)


func test_cube_needs_no_ellipsoid_scale() -> void:
	assert_bool(ShapeParamMapping.needs_ellipsoid_scale("Cube")).is_false()


func test_cube_is_not_radial() -> void:
	assert_bool(ShapeParamMapping.is_radial("Cube")).is_false()


# ---------------------------------------------------------------------------
# Plane
# ---------------------------------------------------------------------------

func test_plane_params() -> void:
	var p := ShapeParamMapping.build_params("Plane", 5.0, 3.0, 0.0)
	assert_float(p["width"]).is_equal(5.0)
	assert_float(p["depth"]).is_equal(3.0)


func test_plane_needs_no_height() -> void:
	assert_bool(ShapeParamMapping.needs_height_step("Plane")).is_false()


# ---------------------------------------------------------------------------
# Cylinder
# ---------------------------------------------------------------------------

func test_cylinder_params_uniform() -> void:
	var p := ShapeParamMapping.build_params("Cylinder", 2.0, 2.0, 3.0)
	assert_float(p["radius"]).is_equal(1.0)
	assert_float(p["height"]).is_equal(3.0)
	assert_bool(p.has("_scale_x")).is_false()
	assert_bool(p.has("_scale_z")).is_false()


func test_cylinder_params_nonuniform() -> void:
	var p := ShapeParamMapping.build_params("Cylinder", 4.0, 2.0, 3.0)
	assert_float(p["radius"]).is_equal(2.0)
	assert_float(p["_scale_x"]).is_equal(4.0 / 4.0)
	assert_float(p["_scale_z"]).is_equal(2.0 / 4.0)


func test_cylinder_ellipsoid_scale_uniform() -> void:
	var p := ShapeParamMapping.build_params("Cylinder", 2.0, 2.0, 3.0)
	var es := ShapeParamMapping.ellipsoid_scale(p)
	assert_float(es.x).is_equal_approx(1.0, 0.001)
	assert_float(es.y).is_equal_approx(1.0, 0.001)
	assert_float(es.z).is_equal_approx(1.0, 0.001)


func test_cylinder_ellipsoid_scale_nonuniform() -> void:
	var p := ShapeParamMapping.build_params("Cylinder", 4.0, 2.0, 3.0)
	var es := ShapeParamMapping.ellipsoid_scale(p)
	assert_float(es.x).is_equal_approx(1.0, 0.001)
	assert_float(es.z).is_equal_approx(0.5, 0.001)


func test_cylinder_clean_params_removes_scale() -> void:
	var p := ShapeParamMapping.build_params("Cylinder", 4.0, 2.0, 3.0)
	var clean := ShapeParamMapping.clean_drawn_params(p)
	assert_bool(clean.has("_scale_x")).is_false()
	assert_bool(clean.has("_scale_z")).is_false()
	assert_float(clean["radius"]).is_equal(2.0)


func test_cylinder_is_radial() -> void:
	assert_bool(ShapeParamMapping.is_radial("Cylinder")).is_true()


# ---------------------------------------------------------------------------
# Sphere
# ---------------------------------------------------------------------------

func test_sphere_params() -> void:
	var p := ShapeParamMapping.build_params("Sphere", 2.0, 3.0, 4.0)
	var max_dim := maxf(2.0, maxf(3.0, 4.0))
	assert_float(p["radius"]).is_equal(max_dim / 2.0)
	assert_float(p["_scale_x"]).is_equal_approx(2.0 / max_dim, 0.001)
	assert_float(p["_scale_y"]).is_equal_approx(4.0 / max_dim, 0.001)
	assert_float(p["_scale_z"]).is_equal_approx(3.0 / max_dim, 0.001)


# ---------------------------------------------------------------------------
# Arch
# ---------------------------------------------------------------------------

func test_arch_params_depth_maps_to_drawn_depth() -> void:
	var p := ShapeParamMapping.build_params("Arch", 2.0, 1.5, 1.0)
	assert_float(p["depth"]).is_equal(1.5)


func test_arch_params_uniform() -> void:
	var p := ShapeParamMapping.build_params("Arch", 2.0, 1.0, 2.0)
	var max_wh := maxf(2.0, 2.0)
	assert_float(p["outer_radius"]).is_equal(max_wh / 2.0)
	assert_float(p["_scale_x"]).is_equal_approx(2.0 / max_wh, 0.001)
	assert_float(p["_scale_y"]).is_equal_approx(2.0 * 2.0 / max_wh, 0.001)


func test_arch_params_nonuniform() -> void:
	var p := ShapeParamMapping.build_params("Arch", 3.0, 1.0, 2.0)
	var max_wh := maxf(3.0, 2.0)
	assert_float(p["outer_radius"]).is_equal(max_wh / 2.0)
	assert_float(p["_scale_x"]).is_equal_approx(3.0 / max_wh, 0.001)
	assert_float(p["_scale_y"]).is_equal_approx(2.0 * 2.0 / max_wh, 0.001)
	assert_bool(p.has("_scale_z")).is_false()


func test_arch_params_wider_than_tall() -> void:
	var p := ShapeParamMapping.build_params("Arch", 4.0, 1.0, 2.0)
	assert_float(p["outer_radius"]).is_equal(2.0)
	assert_float(p["_scale_x"]).is_equal_approx(4.0 / 4.0, 0.001)
	assert_float(p["_scale_y"]).is_equal_approx(2.0 * 2.0 / 4.0, 0.001)


func test_arch_ellipsoid_scale_has_y() -> void:
	var p := ShapeParamMapping.build_params("Arch", 3.0, 1.0, 2.0)
	var es := ShapeParamMapping.ellipsoid_scale(p)
	assert_float(es.x).is_equal_approx(3.0 / 3.0, 0.001)
	assert_float(es.y).is_equal_approx(2.0 * 2.0 / 3.0, 0.001)
	assert_float(es.z).is_equal_approx(1.0, 0.001)


func test_arch_is_not_radial() -> void:
	assert_bool(ShapeParamMapping.is_radial("Arch")).is_false()


func test_arch_needs_ellipsoid_scale() -> void:
	assert_bool(ShapeParamMapping.needs_ellipsoid_scale("Arch")).is_true()


func test_arch_clean_params_removes_scales() -> void:
	var p := ShapeParamMapping.build_params("Arch", 3.0, 1.0, 2.0)
	var clean := ShapeParamMapping.clean_drawn_params(p)
	assert_bool(clean.has("_scale_x")).is_false()
	assert_bool(clean.has("_scale_y")).is_false()
	assert_bool(clean.has("_scale_z")).is_false()
	assert_float(clean["outer_radius"]).is_equal(1.5)
	assert_float(clean["depth"]).is_equal(1.0)


# ---------------------------------------------------------------------------
# Staircase
# ---------------------------------------------------------------------------

func test_staircase_params() -> void:
	var p := ShapeParamMapping.build_params("Staircase", 2.0, 3.0, 4.0, {"steps": 4})
	assert_int(p["steps"]).is_equal(4)
	assert_float(p["step_width"]).is_equal(2.0)
	assert_float(p["step_height"]).is_equal(1.0)
	assert_float(p["step_depth"]).is_equal(0.75)


func test_staircase_needs_no_ellipsoid_scale() -> void:
	assert_bool(ShapeParamMapping.needs_ellipsoid_scale("Staircase")).is_false()


# ---------------------------------------------------------------------------
# constrain_uniform
# ---------------------------------------------------------------------------

func test_constrain_uniform_arch() -> void:
	var r := ShapeParamMapping.constrain_uniform("Arch", 3.0, 2.0, 4.0)
	var m := maxf(3.0, maxf(2.0, 4.0))
	assert_float(r["width"]).is_equal(m)
	assert_float(r["depth"]).is_equal(m)
	assert_float(r["height"]).is_equal(m)


# ---------------------------------------------------------------------------
# ellipsoid_scale with missing keys
# ---------------------------------------------------------------------------

func test_ellipsoid_scale_defaults_to_one() -> void:
	var es := ShapeParamMapping.ellipsoid_scale({"radius": 1.0})
	assert_float(es.x).is_equal_approx(1.0, 0.001)
	assert_float(es.y).is_equal_approx(1.0, 0.001)
	assert_float(es.z).is_equal_approx(1.0, 0.001)