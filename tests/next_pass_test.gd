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
func frames(count: int = 3) -> void:
	for index in range(count): await physics_frame
func soldier(kind: String, team: int, position: Vector2, shared: BattleSquad = null) -> Unit:
	var spec: Dictionary = game.card_catalog[kind].base_stats()
	spec.merge({"unit_type":kind,"team":team,"lane":1,"spawn_positions":[position]},true)
	if shared != null: spec.squad = shared
	game.spawn_deployment(spec)
	var unit: Unit = game.units[-1]
	unit.squad_member_index = unit.squad.members.size()-1
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
	game.tuning.attack_interval_variance = 0
	game.tuning.move_speed_variance = 0
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	game.set_process(false)
	game.planning.set_process(false)
	var commands = game.squad_commands
	var assault := soldier("assault_squad",2,Vector2(3000,3500))
	var rifle := soldier("rifle_squad",2,Vector2(3220,3400),assault.squad)
	var enemy := soldier("rifle_squad",1,Vector2(3000,2800))
	await frames()
	commands.tick()
	rifle._physics_process(1.0/60)
	commands.tick()
	check(assault.squad.combat_target == enemy,"Squad exposes an ally's live firing contact")
	var before := assault.position
	assault._physics_process(1.0/60)
	check(assault.target == enemy and assault.combat_closing,"Assault inherits an out-of-range squad target")
	check(is_equal_approx(before.distance_to(assault.position),assault.move_speed/60.0),"Closing uses native tactical speed")
	check(assault.squad.strategic_speed == rifle.move_speed,"Mixed strategic travel remains slowest-member speed")
	check(assault.position.distance_to(assault.squad.combat_center) <= game.tuning.cohesion_leash,"Closing respects moving cohesion body")
	var record: Dictionary = game.telemetry.soldiers[assault.telemetry_id].record
	check(record.time_closing_to_range > 0 and record.distance_moved_while_closing > 0,"Closing is measured rather than lost from telemetry")
	check(record.combat_close_started_count == 1,"Closing attempts counted once")
	for index in range(80):
		await frames(1)
		commands.tick()
		assault._physics_process(1.0/60)
		if assault.is_attacking: break
	check(assault.is_attacking and record.combat_close_completed_count == 1,"Closing transitions to actual fire")
	enemy.position = Vector2(3000,1000)
	await frames()
	commands.tick()
	assault.squad.combat_target = enemy
	assault._physics_process(1.0/60)
	check(not assault.combat_closing,"Unreachable contact does not bypass leash")
	clear()
	await frames()
	assault = soldier("assault_squad",2,Vector2(3000,3300))
	rifle = soldier("rifle_squad",2,Vector2(3220,3100),assault.squad)
	commands.issue_group([assault.squad],"DEFEND",Vector2(3200,3200))
	for unit in [assault,rifle]: unit.defense_established = true
	commands.points.update(0,true)
	enemy = soldier("rifle_squad",1,Vector2(3000,2600))
	await frames()
	rifle._physics_process(1.0/60)
	commands.tick()
	assault._physics_process(1.0/60)
	check(assault.combat_closing and assault.target == enemy,"Established Assault can close on shared firing contact")
	check(commands.inside_defense(assault.squad,assault.position),"Defensive closing stays in actual territory")
	clear()
	await frames()
	var first := soldier("rifle_squad",2,Vector2(2800,4100))
	var second := soldier("conscript_wave",2,Vector2(3500,4100))
	var inbound := soldier("assault_squad",2,Vector2(3200,5200))
	var response: Dictionary = commands.issue_group([first.squad,second.squad,inbound.squad],"DEFEND",Vector2(3200,3500))
	var point_id: int = response.defensive_point_id
	for unit in [first,second]:
		unit.position = unit.squad.defense_positions[unit.squad_member_index]
		unit.defense_established = true
	commands.points.update(0,true)
	var first_home: Dictionary = first.squad.defense_positions.duplicate()
	var second_home: Dictionary = second.squad.defense_positions.duplicate()
	var reinforcing := soldier("rifle_squad",2,Vector2(4500,5200))
	commands.issue_group([reinforcing.squad],"DEFEND",Vector2.ZERO,0,PackedVector2Array(),point_id)
	check(first.squad.defense_positions == first_home and second.squad.defense_positions == second_home,"Reinforcement preserves settled homes")
	check(reinforcing.squad.defense_positions[0] != inbound.squad.defense_positions[0],"Inbound squads receive distinct arrival slots")
	var expected: Array = []
	for unit in game.units:
		if unit.position.distance_to(Vector2(3200,4000)) <= 1800: expected.append(unit)
	check(game.formation_manager.near_units(Vector2(3200,4000),1800) == expected,"Spatial combat query equals exact full unit scan")
	commands.select_point(point_id)
	check(commands.selected_ids.size() == 2 and not commands.selected_ids.has(inbound.squad.squad_id),"Point selects established squads and excludes inbound")
	check(commands.selected_point_id == point_id,"Aggregate selection identity")
	commands.select_unit(first)
	check(commands.selected_ids == [first.squad.squad_id] and commands.selected_point_id == -1,"Soldier click returns to a single squad selection")
	commands.select_point(point_id)
	var route := PackedVector2Array([Vector2(3200,3000),Vector2(3200,2400)])
	var released: Dictionary = commands.issue_selected("ADVANCE",Vector2.ZERO,0,route)
	check(released.success and first.squad.intent == "ADVANCE" and second.squad.intent == "ADVANCE","Whole point releases as one force")
	check(inbound.squad.order_id == point_id and commands.orders.has(point_id),"Old point survives while inbound remains")
	check(first.squad.route_waypoints[0].distance_to(second.squad.route_waypoints[0]) == game.tuning.route_lane_spacing,"Mass route distributes squad lanes")
	check(first.squad.route_offsets[first.squad_member_index].length() <= game.tuning.cohesion_leash,"Local formation offsets remain bounded")
	response = commands.issue_group([first.squad,second.squad],"DEFEND",Vector2(2800,2500),0,route)
	check(response.success and first.squad.order_id == second.squad.order_id and first.squad.order_id != point_id,"Route plus Defend relocates selected mass")
	var new_id: int = response.defensive_point_id
	commands.break_point(new_id,true)
	var breaks: Array = game.telemetry.data.events.filter(func(entry): return entry.type == "DEFENSIVE_POINT_BROKEN" and entry.point_id == new_id)
	check(breaks.size() == 1 and breaks[0].surviving_defenders_at_break == 2,"Break snapshot records living survivors")
	check(breaks[0].living_assigned_squads_before_break.size() == 2 and breaks[0].break_cause == "SCRIPTED","Break diagnostic identifies squads and cause")
	check(game.telemetry.point_records[new_id].delete_reason == "COMBAT_BREAK","Point deletion has explicit reason")
	clear()
	await frames()
	var mover := soldier("rifle_squad",2,Vector2(2000,4000))
	commands.issue_group([mover.squad],"ADVANCE",Vector2.ZERO,0,PackedVector2Array([Vector2(2000,3000)]))
	var path: Dictionary = game.telemetry.active_paths[mover.squad.squad_id]
	for index in range(3):
		mover.position += Vector2(200,0)
		game.telemetry.tick(1.0)
	check(path.friction and path.pathing_friction_events == 1,"Moving away from route triggers friction")
	check(not path.stuck and path.stuck_time == 0,"Moving friction is distinct from stationary stuck")
	check(path.negative_progress_distance > 0 and path.net_route_progress < 0,"Backtracking is quantified")
	mover.position = mover.position.move_toward(Vector2(2000,3000),200)
	game.telemetry.tick(1.0)
	check(not path.friction and path.pathing_friction_time > 0,"Useful progress ends friction")
	game.telemetry.close_path(mover.squad.squad_id,"test_complete")
	check(path.has("mean_progress_efficiency") and path.has("median_progress_efficiency"),"Terminated orders preserve route metrics")
	clear()
	# Both sides use the same controller, mirrored anchors and equal economy.
	var bot = preload("res://scripts/systems/enemy_controller.gd").new(game,2,"TRIANGLE")
	game.enemy_controller.doctrine = "TRIANGLE"
	check(bot.anchor("center").y == game.field_size.y-game.enemy_controller.anchor("center").y,"AI anchors mirror between sides")
	var kinds := {}
	for index in range(6):
		var package: Array = bot.next_package()
		var units: Array = []
		for card in package:
			if card.card_type == BattleCard.Type.UNIT: units.append(card.card_id)
		kinds[str(units)] = true
	check(kinds.size() == 6,"Shuffled templates cover single and mixed packages")
	# Menu retains play/mirror entry points and exposes movement trials.
	var menu = load("res://scenes/menu.tscn").instantiate()
	root.add_child(menu)
	var buttons: Array = menu.find_children("*","Button",true,false)
	check(buttons.size() == 3 and buttons[0].text == "Play" and buttons[1].text == "Mirror test match" and buttons[2].text == "Pathing trials","Menu has Play, Mirror test match and Pathing trials")
	menu.free()
	print("NEXT PASS: %d assertions, %s" % [checks,"FAILED" if failed else "PASSED"])
	quit(1 if failed else 0)
