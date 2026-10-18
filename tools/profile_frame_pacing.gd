extends SceneTree

# Rendered, static established-defense fixture: measures periodic rule updates
# plus actual rendering/UI work without changing the combat population.
var game: Node
func _initialize() -> void: call_deferred("run")
func report(label: String, samples: Array[float]) -> void:
	var sum := 0.0
	for sample in samples: sum += sample
	samples.sort()
	print("FRAME PROFILE %s mean_ms=%.3f p95_ms=%.3f max_ms=%.3f" % [label,sum/samples.size(),samples[floori(samples.size()*0.95)],samples[-1]])
func run() -> void:
	game = load("res://main.tscn").instantiate()
	game.tuning = game.tuning.duplicate()
	game.tuning.enemy_enabled = false
	root.add_child(game)
	current_scene = game
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size = Vector2i(1280,900)
	await process_frame
	game.show_overview()
	for team in [1,2]:
		for lane in range(3):
			var center := Vector2(game.field_size.x*(0.25+0.25*lane),2200 if team==1 else 4400)
			var spec: Dictionary = game.card_catalog.conscript_wave.base_stats()
			spec.team = team
			spec.unit_type = "conscript_wave"
			spec.lane = lane
			spec.spawn_positions = []
			for index in range(24): spec.spawn_positions.append(center+Vector2(index%6,index/6)*160)
			game.spawn_deployment(spec)
			for unit in spec.squad.members: unit.set_physics_process(false)
			game.squad_commands.issue_group([spec.squad],"DEFEND",center)
			for unit in spec.squad.members:
				unit.position = spec.squad.defense_positions[unit.squad_member_index]
				unit.defense_established = true
	game.squad_commands.points.update(0,true)
	game.command_ui.feedback.clear()
	var warm_until := Time.get_ticks_usec()+2000000
	while Time.get_ticks_usec() < warm_until: await process_frame
	var frame_times: Array[float] = []
	var process_times: Array[float] = []
	var draw_calls: Array[float] = []
	var previous := Time.get_ticks_usec()
	var sample_until := Time.get_ticks_usec()+3000000
	while frame_times.size() < 240 or Time.get_ticks_usec() < sample_until:
		await process_frame
		var now := Time.get_ticks_usec()
		frame_times.append(float(now-previous)/1000)
		process_times.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000)
		draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		previous = now
	report("wall_144_units_6_points",frame_times)
	report("engine_process",process_times)
	draw_calls.sort()
	print("FRAME PROFILE draw_calls_p95=%.0f samples=%d" % [draw_calls[floori(draw_calls.size()*0.95)],frame_times.size()])
	print("FRAME PROFILE COMPLETED")
	quit()
