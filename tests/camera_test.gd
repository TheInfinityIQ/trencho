extends SceneTree
var checks := 0
func _initialize() -> void:
	call_deferred("_run")
func check(condition: bool, message: String) -> void:
	assert(condition, message)
	checks += 1
func _run() -> void:
	root.size = Vector2i(1280, 900)
	var game = load("res://main.tscn").instantiate()
	game.tuning = game.tuning.duplicate()
	game.tuning.enemy_enabled = false
	root.add_child(game)
	current_scene = game
	game.set_process(false)
	await process_frame
	check(ProjectSettings.get_setting("display/window/size/mode") == 2, "Starts maximized")
	check(game.zoom_multiplier == 2, "Closer default camera")
	check(game.camera_center.y > game.field_size.y * 0.7, "Default view focuses player side")
	var deployment_point: Vector2 = game.get_canvas_transform() * game.zones[1].get_center()
	check(game.zone_at_screen(deployment_point) == 1, "Deployment remains clickable at initial zoom")
	game.show_overview()
	check(game.zoom_multiplier == 1 and game.camera_center.is_equal_approx(game.field_size * 0.5), "Overview restores the full map")
	var camera: Camera2D = game.get_node("Camera2D")
	check(is_equal_approx(camera.zoom.x, game.base_zoom), "Overview zoom")
	game.zoom_camera(4)
	var anchor: Vector2 = game.battlefield_view_rect().get_center() + Vector2(20, -20)
	var before: Vector2 = game.get_canvas_transform().affine_inverse() * anchor
	game.zoom_camera(1.2, anchor)
	var after: Vector2 = game.get_canvas_transform().affine_inverse() * anchor
	check(before.distance_to(after) < 0.1, "Mouse zoom preserves the world point under the cursor")
	game.zoom_camera(100)
	check(game.zoom_multiplier == 6, "Maximum zoom clamped")
	game.zoom_camera(0.001)
	check(game.zoom_multiplier == 1, "Minimum zoom clamped")
	game.show_deployment()
	check(game.zoom_multiplier >= 2, "Deploy shortcut zooms in")
	deployment_point = game.get_canvas_transform() * game.zones[2].get_center()
	check(game.zone_at_screen(deployment_point) == 2, "Deployment hit testing follows camera")
	var middle := InputEventMouseButton.new()
	middle.button_index = MOUSE_BUTTON_MIDDLE
	middle.pressed = true
	middle.position = game.battlefield_view_rect().get_center()
	game._input(middle)
	check(game.camera_panning, "Middle button starts panning")
	var old_center: Vector2 = game.camera_center
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(0, 60)
	game._input(motion)
	check(game.camera_center.y < old_center.y, "Middle drag pans camera")
	middle.pressed = false
	game._input(middle)
	check(not game.camera_panning, "Middle release stops panning")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = game.hand._card_rect(0).get_center()
	var old_zoom: float = game.zoom_multiplier
	game._input(wheel)
	check(game.zoom_multiplier == old_zoom, "Wheel over cards does not zoom the map")
	game.hud.debug_panel.visible = true
	wheel.position = game.hud.debug_panel.get_global_rect().get_center()
	game._input(wheel)
	check(game.zoom_multiplier == old_zoom, "Wheel over debug panel scrolls without zooming")
	game.hud.debug_panel.visible = false
	wheel.position = game.battlefield_view_rect().get_center()
	game._input(wheel)
	check(game.zoom_multiplier > old_zoom, "Wheel over battlefield zooms")
	game.camera_center = Vector2(-100000, 100000)
	game._apply_camera()
	check(game.camera_center.x >= 0 and game.camera_center.y <= game.field_size.y, "Panning is constrained to battlefield")
	root.size = Vector2i(1600, 1000)
	await process_frame
	check(camera.zoom.x > 0 and camera.position.is_finite(), "Resize updates camera")
	print("CAMERA CHECKS PASSED: %d assertions" % checks)
	quit()
