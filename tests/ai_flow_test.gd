extends SceneTree
var game: Node
var checks := 0
var failed := false
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error("FAILED: "+label)
func soldier(kind: String, team: int, position: Vector2) -> Unit:
	var spec: Dictionary = game.card_catalog[kind].base_stats()
	spec.merge({"team":team,"lane":1,"unit_type":kind,"spawn_positions":[position]},true)
	game.spawn_deployment(spec)
	var unit: Unit = game.units[-1]
	unit.set_physics_process(false)
	return unit
func clear() -> void:
	game.formation_manager.clear()
	for unit in game.units.duplicate(): unit.die()
	game.squad_commands.prune()
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
	for team in [1,2]:
		for kind in ["rifle_squad","conscript_wave","assault_squad"]:
			var blocker := soldier("rifle_squad",team,Vector2(3200,3200))
			var direction := Vector2.DOWN if team == 1 else Vector2.UP
			var mover := soldier(kind,team,blocker.position-direction*150)
			var start := mover.position
			var crossed := false
			var kept_clear := true
			for tick in range(300):
				await physics_frame
				mover._physics_process(1.0/60)
				kept_clear = kept_clear and mover.position.distance_to(blocker.position) >= game.tuning.unit_radius*2+1.9
				if (mover.position-blocker.position).dot(direction) > 160:
					crossed = true
					break
			check(crossed,"Default Advance detours past a friendly blocker: %s team %d" % [kind,team])
			check(kept_clear,"Detour respects body clearance")
			check(blocker.position == Vector2(3200,3200),"Advance does not displace a stationary defender")
			check(mover.squad.intent == "ADVANCE" and mover.position.distance_to(start) > 300,"Movement stays Advance rather than silently holding")
			clear()
			for tick in range(3): await physics_frame
	var ai = game.enemy_controller
	ai.doctrine = "LINE"
	game.player_deployment_confirmed = true
	game.economies[1].current_command = 10
	ai.planned_package = [game.card_catalog.conscript_wave]
	ai.deployment_cooldown = 0
	ai.decide()
	var first = game.formation_manager.pending[0].specification.squad
	check(first.intent == "DEFEND" and first.order_id >= 0,"AI assigns defense while squad is still queued")
	check(ai.uncommitted.is_empty(),"Accepted squad is not left marching unassigned")
	check(ai.defender_count("left",true) == 12,"Queued bodies reserve defensive target")
	ai.planned_package = [game.card_catalog.conscript_wave]
	ai.deployment_cooldown = 0
	ai.decide()
	check(ai.defender_count("right",true) == 12,"Next package fills other outer target")
	check(ai.priority() == "WAIT","Preserve doctrine's establishment phase")
	var queued: int = game.formation_manager.pending.size()
	var command: float = game.economies[1].current_command
	ai.deployment_cooldown = 0
	ai.decide()
	check(game.formation_manager.pending.size() == queued and game.economies[1].current_command == command,"WAIT pauses new deployments instead of accumulating unassigned troops")
	# Policy fixture: model arrival metadata independently of movement scenario above.
	for key in ["left","right"]:
		var point: Dictionary = game.squad_commands.orders[ai.doctrine_points[key]]
		point.established = 12
		point.inbound = 0
	check(ai.priority() == "center","Center follows established outer positions")
	clear()
	print("AI FLOW: %d assertions, %s" % [checks,"FAILED" if failed else "PASSED"])
	quit(1 if failed else 0)
