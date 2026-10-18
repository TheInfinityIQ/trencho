extends SceneTree
var game: Node
func _initialize() -> void: call_deferred("run")
func run() -> void:
	game = load("res://main.tscn").instantiate()
	game.tuning = game.tuning.duplicate()
	game.tuning.enemy_enabled = false
	game.tuning.move_speed_variance = 0
	game.tuning.maximum_defense_radius = 2600
	root.add_child(game)
	current_scene = game
	game.set_process(false)
	game.set_physics_process(false)
	game.planning.set_process(false)
	await process_frame
	for quantity in [24,72]:
		var spec: Dictionary = game.card_catalog.conscript_wave.base_stats()
		spec.team = 2
		spec.unit_type = "conscript_wave"
		spec.lane = 1
		spec.spawn_positions = []
		for index in range(quantity):
			spec.spawn_positions.append(Vector2(2600+(index%8)*160,4200+floori(float(index)/8)*160))
		game.spawn_deployment(spec)
		for unit in game.units: unit.set_physics_process(false)
		game.squad_commands.select_unit(spec.squad.members[0])
		var response: Dictionary = game.squad_commands.issue_selected("DEFEND",Vector2(3200,3500),600)
		if not response.success:
			push_error("Profile setup rejected")
			quit(1)
			return
		var samples: Array[int] = []
		for frame in range(180):
			var start := Time.get_ticks_usec()
			game._physics_process(1.0/60)
			for unit in game.units: unit._physics_process(1.0/60)
			samples.append(Time.get_ticks_usec()-start)
		var total := 0
		for value in samples: total += value
		samples.sort()
		print("DEFENSE PROFILE units=%d ticks=%d mean_us=%.1f p95_us=%d max_us=%d" % [quantity,samples.size(),float(total)/samples.size(),samples[floori(samples.size()*0.95)],samples[-1]])
		game.formation_manager.clear()
		for unit in game.units.duplicate(): unit.die()
		await physics_frame
		await physics_frame
	print("DEFENSE PROFILE COMPLETED")
	quit()
