extends SceneTree
var game: Node
func _initialize() -> void: call_deferred("run")
func soldiers(kind: String, team: int, center: Vector2, count: int) -> Array:
	var spec: Dictionary = game.card_catalog[kind].base_stats()
	spec.team = team
	spec.unit_type = kind
	spec.lane = 1
	spec.spawn_positions = []
	for index in range(count): spec.spawn_positions.append(center+Vector2(index*180,0))
	game.spawn_deployment(spec)
	for unit in game.units: unit.set_physics_process(false)
	return spec.squad.members.duplicate()
func capture(name: String) -> void:
	for index in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var output: String = ProjectSettings.globalize_path("res://.test-results/"+name+".png")
	var error: int = root.get_texture().get_image().save_png(output)
	if error != OK:
		push_error("Screenshot failed: "+str(error))
		quit(1)
	print("CAPTURE: "+output)
func run() -> void:
	game = load("res://main.tscn").instantiate()
	game.tuning = game.tuning.duplicate()
	game.tuning.enemy_enabled = false
	root.add_child(game)
	current_scene = game
	game.set_process(false)
	game.set_physics_process(false)
	game.planning.set_process(false)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size = Vector2i(1280,900)
	await process_frame
	game.show_overview()
	var friendly := soldiers("rifle_squad",2,Vector2(2700,4200),6)
	var assault := soldiers("assault_squad",2,Vector2(3000,4800),4)
	soldiers("rifle_squad",1,Vector2(2700,1900),6)
	game.hand.cards.assign([game.card_catalog.rifle_squad,game.card_catalog.commander_mojo,game.card_catalog.assault_squad,game.card_catalog.conscript_wave,game.card_catalog.forced_march])
	game.hand._toggle_card(0)
	game.hand._toggle_card(2)
	game.command_ui.blueprint_width = 1900
	game.command_ui.blueprint_depth = 620
	game.economies[2].current_command = 10
	game.command_ui.open_blueprint(Vector2(3200,3500))
	game.planning.advance(1)
	await capture("squad-blueprint")
	game.command_ui.cancel_current()
	game.hand.cancel_selection()
	game.squad_commands.select_unit(friendly[0])
	game.squad_commands.select_unit(assault[0],true)
	game.command_ui.gesture_origin = game.squad_commands.centroid()
	game.planning.begin()
	game.planning.advance(1)
	game.squad_commands.issue_selected("DEFEND",Vector2(3200,3500),800)
	for squad in game.squad_commands.selected_squads():
		for unit in squad.living_members():
			unit.position = squad.defense_positions[unit.squad_member_index]
			unit.defense_established = true
	game.squad_commands.points.update(0,true)
	game.command_ui.set_process(false)
	game.command_ui.queue_redraw()
	await capture("squad-planning")
	game.planning.end()
	game.planning.advance(1)
	print("COMMAND VISUAL SMOKE PASSED")
	quit()
