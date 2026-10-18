extends SceneTree
var game: Node
var failed := false
func _initialize() -> void: call_deferred("run")
func capture(name: String) -> void:
	for index in range(4): await process_frame
	await RenderingServer.frame_post_draw
	var path := "res://.test-results/ui-clarity-" + name + ".png"
	var error := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	if error != OK:
		failed = true
		push_error("Could not save " + path)
	print("CAPTURE: " + path)
func soldiers(kind: String, center: Vector2, count: int) -> Array:
	var spec: Dictionary = game.card_catalog[kind].base_stats()
	spec.merge({"team":2,"unit_type":kind,"lane":1,"spawn_positions":[]},true)
	for index in range(count): spec.spawn_positions.append(center+Vector2((index%6)*180,(index/6)*180))
	game.spawn_deployment(spec)
	for unit in game.units: unit.set_physics_process(false)
	return spec.squad.members.duplicate()
func run() -> void:
	game = load("res://main.tscn").instantiate()
	game.tuning = game.tuning.duplicate()
	game.tuning.enemy_enabled = false
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	game.set_process(false)
	game.planning.set_process(false)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size = Vector2i(1280,800)
	await process_frame
	game.show_overview()
	game.economies[2].current_command = 10
	game.hand.cards.assign([game.card_catalog.rifle_squad,game.card_catalog.commander_mojo,game.card_catalog.assault_squad,game.card_catalog.conscript_wave,game.card_catalog.forced_march])
	game.hand._toggle_card(0)
	game.hand._toggle_card(2)
	await capture("package-1280")
	game.command_ui.set_blueprint_size(1900,620)
	game.command_ui.open_blueprint(Vector2(3200,3500))
	game.planning.advance(1)
	await capture("blueprint-valid")
	game.command_ui.set_blueprint_size(100,100)
	await capture("blueprint-invalid")
	game.command_ui.set_blueprint_size(1900,620)
	game.command_ui.confirm_blueprint()
	game.command_ui.begin_gesture(game.command_ui.knob_position())
	game.command_ui.stroke = PackedVector2Array([game.command_ui.knob_position(),game.command_ui.knob_position()+Vector2.ONE])
	game.command_ui.finish_gesture()
	await capture("recovery")
	game.command_ui.cancel_current()
	game.hand.cancel_selection()
	var rifle := soldiers("rifle_squad",Vector2(2500,4200),24)
	var assault := soldiers("assault_squad",Vector2(3200,4800),12)
	game.squad_commands.issue_group([rifle[0].squad,assault[0].squad],"DEFEND",Vector2(3200,3500))
	for unit in game.units:
		unit.position = unit.squad.defense_positions[unit.squad_member_index]
		unit.defense_established = true
	game.squad_commands.points.update(0,true)
	game.squad_commands.select_point(rifle[0].squad.order_id)
	await capture("point-1280")
	for resolution in [Vector2i(960,700),Vector2i(1920,1080)]:
		root.size = resolution
		await capture("point-%d" % resolution.x)
	root.size = Vector2i(1280,800)
	game.hud.controls_help.visible = true
	await capture("controls")
	print("UI VISUAL CAPTURE " + ("FAILED" if failed else "PASSED"))
	quit(1 if failed else 0)
