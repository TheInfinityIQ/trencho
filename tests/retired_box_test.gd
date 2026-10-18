extends SceneTree
var game: Node
var failed := false
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error("FAILED: "+label)
func button(point: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.pressed = pressed
	return event
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://main.tscn").instantiate()
	game.tuning = game.tuning.duplicate()
	game.tuning.enemy_enabled = false
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	await process_frame
	game.hand.cards.assign([game.card_catalog.rifle_squad,game.card_catalog.commander_mojo])
	game.hand._toggle_card(0)
	game.economies[2].current_command = 10
	var ui = game.command_ui
	ui.open_blueprint(Vector2(3000,5500))
	ui.confirm_blueprint()
	var before: float = game.economies[2].current_command
	# A poor line fails, then the next press misses the command knob near home.
	ui.begin_gesture(ui.knob_position())
	ui.stroke = PackedVector2Array([ui.knob_position(),ui.knob_position()+Vector2.ONE])
	check(not ui.finish_gesture().success,"poor line is rejected")
	var start: Vector2 = game.get_canvas_transform()*Vector2(2200,5500)
	Input.parse_input_event(button(start,true))
	Input.flush_buffered_events()
	await process_frame
	check(not game.hand.has_footprint and not game.hand.drawing_footprint,"retry press never enters legacy drawing mode")
	var motion := InputEventMouseMotion.new()
	motion.position = start+Vector2(80,15)
	Input.parse_input_event(motion)
	Input.parse_input_event(button(motion.position,false))
	Input.flush_buffered_events()
	await process_frame
	game.hand._process(0.2)
	check(game.footprint_preview.is_empty() and game.preview.get_child_count()==0,"no legacy rectangle or ghosts after rejected retry")
	check(game.economies[2].current_command==before and game.formation_manager.pending.is_empty() and game.hand.selected_indices==[0],"failed retry preserves cards, resources and queue")
	check(not game.planning.active and ui.pending_ready,"failed command exits planning and keeps setup available")
	ui.cancel_current()
	game.planning.advance(1)
	print("RETIRED BOX: %d assertions, %s" % [checks,"FAILED" if failed else "PASSED"])
	quit(1 if failed else 0)
