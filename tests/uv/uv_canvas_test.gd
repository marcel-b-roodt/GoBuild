## GoBuildUvCanvas unit tests — GdUnit4
##
## Tests coordinate transforms and canvas-level integration.
## Pure-math hit-testing functions are tested in UvPicker tests.
extends GdUnitTestSuite

const _CANVAS_SCRIPT := preload("res://addons/go_build/uv/go_build_uv_canvas.gd")
const _MESH_INSTANCE_SCRIPT := preload("res://addons/go_build/core/go_build_mesh_instance.gd")


func test_uv_to_canvas_round_trip() -> void:
	var canvas := GoBuildUvCanvas.new()
	add_child(canvas)
	await await_frame
	canvas.size = Vector2(400, 400)
	canvas._zoom = 100.0
	canvas._pan = Vector2.ZERO

	var uv_pos := Vector2(0.5, 0.5)
	var canvas_pos: Vector2 = canvas._uv_to_canvas(uv_pos)
	var round_trip: Vector2 = canvas._canvas_to_uv(canvas_pos)
	assert_vector(round_trip).is_equal_approx(uv_pos, 0.001)

	canvas.queue_free()


func test_uv_to_canvas_with_pan() -> void:
	var canvas := GoBuildUvCanvas.new()
	add_child(canvas)
	canvas.size = Vector2(400, 400)
	canvas._zoom = 100.0
	canvas._pan = Vector2(50.0, -30.0)

	var uv_pos := Vector2(0.0, 0.0)
	var canvas_pos := canvas._uv_to_canvas(uv_pos)
	assert_float(canvas_pos.x).is_equal(250.0)
	assert_float(canvas_pos.y).is_equal(170.0)

	canvas.queue_free()