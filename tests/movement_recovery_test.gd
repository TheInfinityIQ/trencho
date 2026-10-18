extends SceneTree
var checks := 0
var failed := false
var game: Node
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error("FAILED: "+message)
func frames(count: int) -> void:
	for tick in range(count): await physics_frame
func spawn(points: Array) -> BattleSquad:
	var spec: Dictionary = game.card_catalog.conscript_wave.base_stats()
	spec.merge({"team":2,"unit_type":"conscript_wave","lane":1,"spawn_positions":points},true)
	game.spawn_deployment(spec)
	return spec.squad
func run() -> void:
	game = load("res://main.tscn").instantiate()
	game.tuning = game.tuning.duplicate()
	game.tuning.enemy_enabled = false
	game.tuning.move_speed_variance = 0
	game.match_options = {"presentation":false}
	root.add_child(game)
	current_scene = game
	var points: Array = []
	for index in range(8): points.append(Vector2(2600+index*160,3800))
	var wall := spawn(points)
	for body in wall.members: body.set_physics_process(false)
	var squad := spawn([Vector2(3200,4500)])
	var mover: Unit = squad.members[0]
	var response: Dictionary = game.squad_commands.issue_group([squad],"DEFEND",Vector2(3200,2600))
	check(response.success,"recovery fixture order accepted")
	var goal: Vector2 = squad.defense_positions[0]
	mover.steering_goal = goal
	game.formation_manager.recovery.request(mover,goal)
	var arrived := false
	for tick in range(2400):
		await physics_frame
		if mover.state == Unit.State.DEFENDING:
			arrived = true
			break
	var service = game.formation_manager.recovery
	check(arrived,"local recovery routes around a stationary rank without teleportation")
	check(service.metrics.paths > 0,"recovery installs an actual path")
	check(game.telemetry.data.orders.any(func(order): return order.repath_count > 0),"installed recovery paths are counted in combat telemetry")
	check(service.metrics.max_cells_per_tick <= 128 and service.metrics.max_cells_per_tick > 0,"shared scan work respects its hard per-tick cell cap")
	game.squad_commands.issue_group([squad],"DEFEND",Vector2(4200,3500))
	goal = squad.defense_positions[0]
	mover.steering_goal = goal
	service.request(mover,goal)
	await frames(2)
	var cancelled: int = service.metrics.cancelled
	game.squad_commands.issue_group([squad],"ADVANCE",Vector2.ZERO,0,PackedVector2Array([Vector2(1800,2500)]))
	await frames(3)
	check(service.metrics.cancelled > cancelled and mover.recovery_path.is_empty(),"a replaced order cancels an in-flight job before a stale path is installed")
	mover.steering_goal = Vector2(1800,2500)
	service.request(mover,mover.steering_goal)
	mover.die()
	await frames(3)
	check(service.requested.is_empty() and service.job.is_empty(),"dead/freed units release recovery requests safely")
	service.terrain[Vector2i.ZERO] = true
	game.squad_commands.points.invalidate_terrain()
	check(service.terrain.is_empty(),"runtime terrain invalidation also clears the recovery cache")
	print("MOVEMENT RECOVERY: %d assertions, %s; max_slice_us=%d" % [checks,"FAILED" if failed else "PASSED",service.metrics.max_slice_us])
	quit(1 if failed else 0)
