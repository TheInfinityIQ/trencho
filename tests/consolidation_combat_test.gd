extends SceneTree
var game: Node
var failed := false
var checks := 0
var evidence: Array = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error("FAILED: "+label)
func setup() -> void:
	game = load("res://main.tscn").instantiate()
	game.tuning = game.tuning.duplicate()
	game.tuning.enemy_enabled = false
	game.tuning.move_speed_variance = 0
	game.tuning.score_victory_enabled = false
	game.match_options = {"presentation":false}
	root.add_child(game)
	current_scene = game
func spawn(team: int, columns: int, rows: int, center: Vector2, kind: String = "rifle_squad") -> BattleSquad:
	var spec: Dictionary = game.card_catalog[kind].base_stats()
	spec.merge({"team":team,"unit_type":kind,"lane":1,"spawn_positions":[]},true)
	for row in range(rows):
		for column in range(columns): spec.spawn_positions.append(center+Vector2(column*160,row*160 if team==2 else -row*160))
	game.spawn_deployment(spec)
	return spec.squad
func clear() -> void:
	game.queue_free()
	await process_frame
	await physics_frame
func run() -> void:
	for fixture in [{"team":1,"kind":"rifle_squad"},{"team":2,"kind":"rifle_squad"},{"team":1,"kind":"conscript_wave"},{"team":2,"kind":"conscript_wave"},{"team":1,"kind":"assault_squad"},{"team":2,"kind":"assault_squad"}]:
		var team: int = fixture.team
		setup()
		game.set_physics_process(false)
		var defenders := spawn(team,1,2,Vector2(3200,3500),fixture.kind)
		var response: Dictionary = game.squad_commands.issue_group([defenders],"DEFEND",Vector2(3200,3500))
		check(response.success,"contact defender setup accepted")
		for unit in defenders.members:
			unit.position = defenders.defense_positions[unit.squad_member_index]
			unit.defense_established = true
			unit.set_physics_process(false)
		var enemy: Unit = spawn(3-team,1,1,Vector2(3200,2000)).members[0]
		enemy.set_physics_process(false)
		enemy.current_health = 100000
		enemy.total_health = 100000
		for defender in defenders.members:
			for distance in [300,600,690,740,900]:
				enemy.position = defender.position+Vector2(0,distance if team==1 else -distance)
				await physics_frame
				await physics_frame
				defender.attack_remaining = 0
				var health_before: float = enemy.current_health
				var damage_events: int = game.telemetry.data.events.filter(func(event): return event.type=="DAMAGE_DEALT").size()
				defender._physics_process(1.0/60)
				var snapshot: Dictionary = game.telemetry.inspect_engagement(defender)
				snapshot["test_distance"] = distance
				snapshot["unit_type"] = fixture.kind
				evidence.append(snapshot)
				var in_detection: bool = snapshot.detection_target != 0
				if distance==300: check(in_detection,"fixture proves positive detection for every unit type and role")
				if distance==900: check(not in_detection,"distant visual neighbor is outside actual detection")
				check(game.telemetry.data.events.filter(func(event): return event.type=="DAMAGE_DEALT").size()==damage_events+(1 if in_detection else 0),"damage telemetry matches detection and shot")
				check(snapshot.fired == in_detection,"ready defender fires exactly when detection has living enemy, team %d distance %d" % [team,distance])
				check((enemy.current_health<health_before) == in_detection,"damage accompanies each detected ready shot")
				if in_detection:
					defender._physics_process(1.0/60)
					var cooling: Dictionary = game.telemetry.inspect_engagement(defender)
					check(not cooling.fired and cooling.reason=="COOLDOWN","engaging cooldown explains intervals without fire")
		await clear()
	# Live combat creates the loss; all replacements use normal autonomous physics.
	setup()
	var defenders := spawn(2,8,2,Vector2(2200,4000))
	game.squad_commands.issue_group([defenders],"DEFEND",Vector2(3328,3500))
	for unit in defenders.members:
		unit.position = defenders.defense_positions[unit.squad_member_index]
		unit.defense_established = true
		unit.state = Unit.State.DEFENDING
	var point_id := defenders.order_id
	var victim: Unit = defenders.members[0]
	var home: Vector2 = victim.position
	victim.current_health = 1
	var attacker: Unit = spawn(1,1,1,home+Vector2(0,-500)).members[0]
	attacker.current_health = 100000
	attacker.total_health = 100000
	for tick in range(120):
		await physics_frame
		if not is_instance_valid(victim) or not victim.is_alive(): break
	check(not is_instance_valid(victim) or not victim.is_alive(),"live front contact produces actual casualty")
	attacker.die()
	var casualty_time: float = game.simulation_time
	var assigned_time := -1.0
	var arrived := false
	var snapshots: Array = []
	for tick in range(600):
		await physics_frame
		var order: Dictionary = game.squad_commands.orders[point_id]
		var vacancies: int = game.squad_commands.fronts.vacant_front(order).size()
		if tick%15==0: snapshots.append({"time":game.simulation_time,"vacancies":vacancies,"timer":order.wave_remaining,"reserves":game.squad_commands.fronts.reserves(order).size()})
		if vacancies==0 and assigned_time<0: assigned_time=game.simulation_time
		for unit in defenders.living_members():
			if unit.position.distance_to(home)<=10:
				arrived = true
		if arrived: break
	check(assigned_time-casualty_time>=2.9,"live ordinary loss remains vacant for reserve delay")
	check(arrived,"assigned reserve physically reaches live combat vacancy")
	var events: Array = game.telemetry.data.events.filter(func(event): return event.type=="RESERVE_WAVE_ASSIGNED")
	check(events.size()==1 and events[0].assignments.size()==1 and events[0].unused_reserves==7,"wave logs exactly one reserve and leaves excess behind")
	evidence.append({"live_wave":snapshots,"assignments":events,"casualty_time":casualty_time,"assigned_time":assigned_time,"arrived":arrived})
	var file := FileAccess.open("user://consolidation_combat_evidence.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence))
	print("CONSOLIDATION COMBAT: %d assertions, %s; %s" % [checks,"FAILED" if failed else "PASSED",ProjectSettings.globalize_path("user://consolidation_combat_evidence.json")])
	quit(1 if failed else 0)
