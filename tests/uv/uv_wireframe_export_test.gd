## UvWireframeExport unit tests.
extends GdUnitTestSuite


func test_render_image_empty_mesh() -> void:
	var mesh := GoBuildMesh.new()
	var img := UvWireframeExport.render_image(mesh, 64)
	assert_int(img.get_width()).is_equal(64)
	assert_int(img.get_height()).is_equal(64)


func test_render_image_cube() -> void:
	var mesh := CubeGenerator.generate(1.0, 1.0, 1.0, 0)
	var img := UvWireframeExport.render_image(mesh, 64)
	assert_int(img.get_width()).is_equal(64)
	assert_int(img.get_height()).is_equal(64)


func test_render_image_default_size() -> void:
	var mesh := CubeGenerator.generate(1.0, 1.0, 1.0, 0)
	var img := UvWireframeExport.render_image(mesh)
	assert_int(img.get_width()).is_equal(1024)
	assert_int(img.get_height()).is_equal(1024)


func test_render_image_custom_color() -> void:
	var mesh := CubeGenerator.generate(1.0, 1.0, 1.0, 0)
	var wire_color := Color(1.0, 0.0, 0.0, 1.0)
	var bg_color := Color(0.0, 0.0, 0.0, 1.0)
	var img := UvWireframeExport.render_image(mesh, 64, wire_color, bg_color)
	assert_int(img.get_width()).is_equal(64)
	assert_int(img.get_height()).is_equal(64)


func test_render_image_has_wireframe_pixels() -> void:
	var mesh := CubeGenerator.generate(1.0, 1.0, 1.0, 0)
	var img := UvWireframeExport.render_image(mesh, 64, Color.WHITE, Color(0, 0, 0, 0))
	# A cube with default UVs should have at least some white pixels
	# (wireframe edges) and some transparent pixels (background).
	var has_white := false
	var has_transparent := false
	for x: int in range(0, 64, 4):
		for y: int in range(0, 64, 4):
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				has_white = true
			else:
				has_transparent = true
	assert_that(has_white).is_true()
	assert_that(has_transparent).is_true()


func test_save_png() -> void:
	var mesh := CubeGenerator.generate(1.0, 1.0, 1.0, 0)
	var path := "user://test_uv_wireframe.png"
	var ok := UvWireframeExport.save_png(path, mesh, 64)
	assert_that(ok).is_true()