extends SceneTree

# Deterministic CPU workload. Timings are measurements of this fixture, not FPS.
var game: Node
func _initialize() -> void: call_deferred("run")
func stats(label: String, samples: Array[int]) -> void:
	var total := 0
	for sample in samples: total += sample
	samples.sort()
	print("PROFILE %s samples=%d mean_us=%.1f p95_us=%d max_us=%d" % [label,samples.size(),float(total)/samples.size(),samples[floori(samples.size()*0.95)],samples[-1]])
func run() -> void:
	game = load("res://main.tscn").instantiate()
	game.tuning = game.tuning.duplicate()
	game.tuning.enemy_enabled = false
	game.tuning.move_speed_variance = 0
	root.add_child(game)
	current_scene = game
	game.set_process(false)
	game.set_physics_process(false)
	game.planning.set_process(false)
	await process_frame
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
			var response: Dictionary = game.squad_commands.issue_group([spec.squad],"DEFEND",center)
			if not response.success:
				push_error("Profile fixture rejected")
				quit(1)
				return
			for unit in spec.squad.members:
				unit.position = spec.squad.defense_positions[unit.squad_member_index]
				unit.defense_established = true
	game.squad_commands.points.update(0,true)
	var commands: Array[int] = []
	var units: Array[int] = []
	for tick in range(180):
		var start := Time.get_ticks_usec()
		game.squad_commands.tick(1.0/60)
		commands.append(Time.get_ticks_usec()-start)
		start = Time.get_ticks_usec()
		for unit in game.units: unit._physics_process(1.0/60)
		units.append(Time.get_ticks_usec()-start)
	stats("commands_144_units_6_points",commands)
	stats("soldiers_144_units_6_points",units)
	var solves: Array[int] = []
	for iteration in range(12):
		var start := Time.get_ticks_usec()
		game.squad_commands.points.update(0,true)
		solves.append(Time.get_ticks_usec()-start)
	stats("forced_territory_solve",solves)
	print("PERFORMANCE PROFILE COMPLETED")
	quit()
