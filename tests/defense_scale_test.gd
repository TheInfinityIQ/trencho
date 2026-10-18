extends SceneTree
var game: Node
var checks := 0
var failed := false
func _initialize() -> void: call_deferred("run")
func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error("FAILED: "+label)
func run() -> void:
	game = load("res://main.tscn").instantiate()
	game.tuning = game.tuning.duplicate()
	game.tuning.enemy_enabled = false
	game.tuning.move_speed_variance = 0
	root.add_child(game)
	current_scene = game
	for group in range(6):
		var spec: Dictionary = game.card_catalog.conscript_wave.base_stats()
		spec.team = 2
		spec.unit_type = "conscript_wave"
		spec.lane = 1
		spec.spawn_positions = []
		for index in range(12): spec.spawn_positions.append(Vector2(2320+index*160,5000+group*160))
		game.spawn_deployment(spec)
		game.squad_commands.select_unit(spec.squad.members[0],true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261017
	var queries: Array[Vector2] = []
	for unit in game.units:
		queries.append(unit.position)
		queries.append(unit.position+Vector2(game.tuning.unit_radius*2+2,0))
	for index in range(100): queries.append(Vector2(rng.randf_range(1800,4800),rng.randf_range(4200,6200)))
	var minimum: float = game.tuning.unit_radius*2+2
	for point in queries:
		var allowed: bool = not game.formation_manager.terrain_blocks(point)
		for unit in game.units:
			if unit.is_alive() and unit.position.distance_squared_to(point)<minimum*minimum: allowed=false
		check(game.formation_manager.can_move_to(point,null)==allowed,"local collision lookup agrees with independent all-body reference")
	var order: Dictionary = game.squad_commands.issue_selected("DEFEND",Vector2(3200,3500),600)
	check(order.success and order.affected_squad_ids.size()==6,"large selection receives one shared order")
	if not order.success:
		print("DEFENSE SCALE: %d assertions, FAILED" % checks)
		quit(1)
		return
	var arrived := false
	for tick in range(3600):
		await physics_frame
		arrived = game.units.all(func(unit): return unit.state==Unit.State.DEFENDING)
		if arrived: break
	check(arrived and game.units.size()==72,"all 72 soldiers reach defense using local steering")
	check(game.squad_commands.selected_ids.size()==6,"large command preserves six squad identities")
	for unit in game.units:
		check(unit.position.distance_to(unit.squad.defense_center)+game.tuning.unit_radius<=unit.squad.defense_radius+1,"large formation stays inside defense circle")
	game.formation_manager.clear()
	for unit in game.units.duplicate(): unit.die()
	var spec: Dictionary = game.card_catalog.rifle_squad.base_stats()
	spec.team = 2
	spec.unit_type = "rifle_squad"
	spec.lane = 1
	spec.spawn_positions = [Vector2(1000,1000)]
	game.spawn_deployment(spec)
	var mover: Unit = game.units[0]
	mover.set_physics_process(false)
	check(not game.formation_manager.can_move_to(mover.position,null),"spawn registers collision occupancy immediately")
	mover.position = Vector2(4000,4000)
	check(game.formation_manager.can_move_to(Vector2(1000,1000),null) and not game.formation_manager.can_move_to(mover.position,null),"cross-cell position changes update occupancy synchronously")
	mover.die()
	check(game.formation_manager.can_move_to(Vector2(4000,4000),null),"death releases collision occupancy without waiting for a frame")
	spec.erase("squad")
	spec.team=2
	spec.spawn_positions=[Vector2(3200,3500)]
	game.spawn_deployment(spec)
	var defender: Unit = game.units[0]
	defender.set_physics_process(false)
	game.squad_commands.select_unit(defender)
	game.squad_commands.issue_selected("DEFEND",Vector2(3200,3500),600)
	spec.erase("squad")
	spec.team=1
	spec.spawn_positions=[Vector2(3200,3600)]
	game.spawn_deployment(spec)
	var enemy: Unit = game.units[1]
	enemy.set_physics_process(false)
	check(game.squad_commands.defense_enemies(defender.squad).has(enemy),"shared threat scan includes a new enemy in the area")
	enemy.die()
	await physics_frame
	await physics_frame
	check(game.squad_commands.defense_enemies(defender.squad).is_empty(),"shared threat cache releases dead or freed enemies")
	print("DEFENSE SCALE: %d assertions, %s" % [checks,"FAILED" if failed else "PASSED"])
	quit(1 if failed else 0)
