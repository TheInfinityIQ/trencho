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

func frames() -> void:
	for index in range(4): await physics_frame

func soldier(kind: String, team: int, position: Vector2) -> Unit:
	var spec: Dictionary = game.card_catalog[kind].base_stats()
	spec.merge({"unit_type":kind,"team":team,"lane":1,"spawn_positions":[position]},true)
	game.spawn_deployment(spec)
	var unit: Unit = spec.squad.members[0]
	unit.set_physics_process(false)
	return unit

func run() -> void:
	game = load("res://main.tscn").instantiate()
	game.tuning = game.tuning.duplicate()
	game.tuning.enemy_enabled = false
	game.tuning.attack_interval_variance = 0
	game.tuning.move_speed_variance = 0
	root.add_child(game)
	current_scene = game
	game.set_process(false)
	game.set_physics_process(false)
	game.planning.set_process(false)
	for team in [1,2]:
		for kind in ["rifle_squad","assault_squad","conscript_wave"]:
			var defender := soldier(kind,team,Vector2(3200,3200))
			var response: Dictionary = game.squad_commands.issue_group([defender.squad],"DEFEND",defender.position)
			check(response.success,"Defense fixture accepted")
			defender.defense_established = true
			game.squad_commands.points.update(0,true)
			var point: Dictionary = game.squad_commands.orders[response.defensive_point_id]
			var edge := Vector2.ZERO
			for cell in point.cells:
				var center: Vector2 = game.squad_commands.points.position(cell)
				if center.x > edge.x: edge = center
			defender.position = edge
			var enemy := soldier("rifle_squad",3-team,edge+Vector2(200,0))
			await frames()
			check(game.squad_commands.inside_defense(defender.squad,defender.position),"Defender is within real territory")
			check(not game.squad_commands.inside_defense(defender.squad,enemy.position),"Shooter is outside territory")
			check(enemy.nearest_enemy() == defender,"Outside shooter can acquire defender")
			var hp := defender.current_health
			enemy._physics_process(1.0/60)
			check(defender.current_health < hp,"Outside shooter actually damages defender")
			check(defender.nearest_enemy() == enemy,"Established defender acquires in-range shooter outside territory")
			var enemy_hp := enemy.current_health
			var position := defender.position
			defender.attack_remaining = 0
			defender._physics_process(1.0/60)
			check(enemy.current_health < enemy_hp,"Defender returns fire across territorial boundary")
			check(defender.position == position and defender.velocity == Vector2.ZERO,"Return fire does not chase")
			check(defender.squad.intent == "DEFEND" and defender.defense_established,"Return fire preserves defense assignment")
			# A boundary is not a weapon-range extension or a reason to leave the point.
			enemy.position = edge+Vector2(defender.attack_range+game.tuning.unit_radius+200,0)
			await frames()
			check(defender.nearest_enemy() == null,"Defender cannot shoot beyond weapon range")
			enemy_hp = enemy.current_health
			for tick in range(30): defender._physics_process(1.0/60)
			check(enemy.current_health == enemy_hp,"No out-of-range damage")
			check(game.squad_commands.inside_defense(defender.squad,defender.position),"Defender does not pursue outside territory")
			check(not defender.is_attacking,"Out-of-range shooter does not produce false firing uptime")
			for unit in game.units.duplicate(): unit.die()
			game.squad_commands.prune()
			await frames()
	print("DEFENSIVE COMBAT: %d assertions, %s" % [checks,"FAILED" if failed else "PASSED"])
	quit(1 if failed else 0)
