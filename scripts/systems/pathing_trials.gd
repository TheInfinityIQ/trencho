extends Node
## Repeatable order/physics trials. No teleporting, collision bypass or forced deaths.
const IO = preload("res://scripts/systems/mirror_io.gd")
const CASES = ["open_advance", "queued_direct", "queued_route_loop", "stationary_rank", "whole_point_release", "whole_point_relocate", "reinforce", "crossing_orders", "mid_entry_reorder", "edge_route", "terrain_detour", "mass_route", "sealed_destination"]
var game: Node
var seed_value := 0
var team := 2
var shift := 0.0
var results: Array = []
var stage_results: Array = []
var failures: Array[String] = []
var history: Array = []
var previous: Dictionary = {}
var stationary: Dictionary = {}
var elapsed_ticks := 0
var overlaps := 0
var overlap_events: Array = []
var invalid_motion := 0
var destination := ""
var started := 0

func _ready() -> void:
	if IO.arguments().has("pathing-worker"): call_deferred("_worker")

func _worker() -> void:
	var options := IO.arguments()
	destination = str(options.get("result","user://pathing_trials.json"))
	var report: Dictionary = await run(int(options.get("seed",16102026)),clampi(int(options.get("repetitions",3)),1,20),str(options.get("case","")))
	print("PATHING TRIALS: %d trials, %s; %s" % [report.results.size(),"PASSED" if report.passed else "FAILED",ProjectSettings.globalize_path(destination)])
	get_tree().quit(0 if report.passed else 1)

func run(base_seed: int, repetitions: int = 2, only_case: String = "") -> Dictionary:
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0
	started = Time.get_ticks_msec()
	results.clear()
	var cases: Array = CASES if only_case.is_empty() else [only_case]
	if not only_case.is_empty() and only_case not in CASES:
		results.append({"case":only_case,"passed":false,"reason":"UNKNOWN_CASE"})
	else:
		for repetition in range(repetitions):
			for case_name in cases:
				await _trial(case_name,base_seed+repetition)
	var report := _report(true)
	if not destination.is_empty() and not IO.write_json(destination,report):
		report.passed = false
		report.write_error = "Could not save trial report"
	return report

func _report(completed: bool) -> Dictionary:
	return {"schema_version":1,"completed":completed,"passed":not results.is_empty() and results.all(func(result): return result.passed),"engine":Engine.get_version_info().string,"physics_hz":Engine.physics_ticks_per_second,"real_seconds":(Time.get_ticks_msec()-started)/1000.0,"results":results,"current_case":name,"note":"Arrival requires all expected soldiers. Queued, missing, dead or unspawned members cannot make a trial pass. Blocked-destination trials explicitly expect non-arrival. Combat is disabled to isolate movement."}

func _setup(seed_number: int) -> void:
	seed_value = seed_number
	team = 2 if seed_number%2 == 0 else 1
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_number
	shift = rng.randf_range(-60,60)
	stage_results = []
	failures.clear()
	history = []
	previous.clear()
	stationary.clear()
	elapsed_ticks = 0
	overlaps = 0
	overlap_events = []
	invalid_motion = 0
	game = load("res://main.tscn").instantiate()
	game.tuning = game.tuning.duplicate()
	game.tuning.enemy_enabled = false
	game.tuning.move_speed_variance = 0
	game.tuning.telemetry_enabled = false
	game.tuning.score_victory_enabled = false
	game.match_options = {"presentation":false,"seed":seed_number}
	add_child(game)

func point(x: float, y: float) -> Vector2:
	return Vector2(x+shift,y if team == 2 else game.field_size.y-y)

func route(points: Array) -> PackedVector2Array:
	var path := PackedVector2Array()
	for p in points: path.append(point(p.x,p.y))
	return path

func spawn(count: int, x: float, y: float, columns: int = 6, frozen: bool = false) -> BattleSquad:
	var positions: Array = []
	for index in range(count): positions.append(point(x+(index%columns)*160,y+floori(float(index)/columns)*160))
	return spawn_positions(positions,frozen)

func spawn_positions(positions: Array, frozen: bool = false) -> BattleSquad:
	var spec: Dictionary = game.card_catalog.conscript_wave.base_stats()
	spec.merge({"team":team,"unit_type":"conscript_wave","lane":1,"spawn_positions":positions},true)
	game.spawn_deployment(spec)
	if frozen:
		for unit in spec.squad.members:
			unit.set_physics_process(false)
			stationary[unit.simulation_id] = unit.position
	return spec.squad

func order(group: Array, kind: String, center: Vector2, path: PackedVector2Array = PackedVector2Array()) -> bool:
	var result: Dictionary = game.squad_commands.issue_group(group,kind,center,0,path)
	if not result.success: failures.append("ORDER_REJECTED: "+result.failure_reason)
	return result.success

func _sample() -> void:
	var clearance: float = game.tuning.unit_radius*2+2
	for unit in game.units:
		if previous.has(unit.simulation_id):
			var maximum: float = unit.move_speed*maxf(game.tuning.capture_speed_multiplier,game.tuning.rout_speed_multiplier)/60.0+0.2
			if unit.position.distance_to(previous[unit.simulation_id]) > maximum: invalid_motion += 1
		previous[unit.simulation_id] = unit.position
		if not unit.position.is_finite() or unit.position.x < game.tuning.unit_radius-0.2 or unit.position.x > game.field_size.x-game.tuning.unit_radius+0.2: invalid_motion += 1
		if stationary.has(unit.simulation_id) and unit.position.distance_to(stationary[unit.simulation_id]) > 0.01: invalid_motion += 1
		if unit.has_entered_battlefield and unit.squad.intent == "DEFEND" and (unit.position.y < game.tuning.unit_radius-0.2 or unit.position.y > game.field_size.y-game.tuning.unit_radius+0.2): invalid_motion += 1
		if elapsed_ticks%6 == 0:
			if unit.has_entered_battlefield and game.formation_manager.terrain_blocks(unit.position): invalid_motion += 1
			for other in game.formation_manager.near_units(unit.position,clearance-0.2):
				if other.simulation_id > unit.simulation_id:
					overlaps += 1
					if overlap_events.size() < 8: overlap_events.append({"time":elapsed_ticks/60.0,"units":[unit.simulation_id,other.simulation_id],"states":[Unit.State.keys()[unit.state],Unit.State.keys()[other.state]],"distance":unit.position.distance_to(other.position)})
	if elapsed_ticks%60 == 0:
		var snapshot: Array = []
		for unit in game.units:
			var home: Vector2 = unit.squad.defense_positions.get(unit.squad_member_index,Vector2.INF)
			# Do not call route_target here: observing must not advance waypoints.
			snapshot.append({"id":unit.simulation_id,"squad":unit.squad.squad_id,"position":[unit.position.x,unit.position.y],"route_index":unit.squad.route_indices.get(unit.squad_member_index,0),"route_size":unit.squad.route_waypoints.size(),"target":_current_target(unit),"stalled":unit.steering_stalled,"detour_seconds":unit.detour_remaining,"passing_side":unit.defense_avoid_side,"side_locked":unit.detour_locked,"state":Unit.State.keys()[unit.state],"home":[home.x,home.y] if home.is_finite() else null})
		history.append({"time":elapsed_ticks/60.0,"units":snapshot})
		if history.size() > 8: history.pop_front()

func _current_target(unit: Unit) -> Variant:
	var index: int = unit.squad.route_indices.get(unit.squad_member_index,0)
	if index >= unit.squad.route_waypoints.size(): return null
	var target: Vector2 = unit.squad._bounded_waypoint(unit.squad.route_waypoints[index]+unit.squad.route_offsets.get(unit.squad_member_index,Vector2.ZERO))
	return [target.x,target.y]
func wait_for(group: Array, expected: int, defending: bool, stage: String, ticks: int = 3600) -> bool:
	var completed: Dictionary = {}
	var arrived := 0
	for tick in range(ticks):
		await get_tree().physics_frame
		elapsed_ticks += 1
		_sample()
		arrived = 0
		for squad in group:
			for unit in squad.living_members():
				if defending:
					if unit.state == Unit.State.DEFENDING and unit.defense_established and unit.position.distance_to(squad.defense_positions.get(unit.squad_member_index,Vector2.INF)) <= 10: arrived += 1
				elif unit.has_entered_battlefield and squad.route_indices.get(unit.squad_member_index,0) >= squad.route_waypoints.size(): completed[unit.simulation_id] = true
		if not defending: arrived = completed.size()
		if arrived == expected:
			stage_results.append({"stage":stage,"arrived":arrived,"expected":expected,"ticks":tick+1,"passed":true})
			return true
	stage_results.append({"stage":stage,"arrived":arrived,"expected":expected,"ticks":ticks,"passed":false})
	return false

func _trial(case_name: String, seed_number: int) -> void:
	name = case_name
	_setup(seed_number)
	if not destination.is_empty(): IO.write_json(destination,_report(false))
	var group: Array = []
	var passed := false
	var expected := 0
	match case_name:
		"open_advance":
			group = [spawn(12,2200,4500,12)]
			expected = 12
			var origins: Dictionary = {}
			for unit in group[0].members: origins[unit.simulation_id] = unit.position
			passed = true
			for tick in range(180):
				await get_tree().physics_frame
				elapsed_ticks += 1
				_sample()
				for unit in group[0].members:
					if unit.detour_remaining > 0 or unit.steering_stalled: passed = false
			var arrived := 0
			for unit in group[0].members:
				var progress: float = (origins[unit.simulation_id].y-unit.position.y)*(1 if team == 2 else -1)
				if progress >= unit.move_speed*2.9: arrived += 1
			passed = passed and arrived == expected
			stage_results.append({"stage":"unobstructed_advance","arrived":arrived,"expected":expected,"ticks":180,"passed":passed})
		"queued_direct", "queued_route_loop":
			game.economies[team].current_command = 10
			var path := route([Vector2(3200,5500),Vector2(3200,4700)]) if case_name == "queued_route_loop" else PackedVector2Array()
			var response: Dictionary = game.deployment_manager.request_squad(team,[game.card_catalog.conscript_wave,game.card_catalog.conscript_wave,game.card_catalog.commander_mojo],Rect2(2200+shift,0,1900,800),"DEFEND",point(3200,4000),0,path)
			if response.is_valid:
				group = [response.resolved_deployment.squad]
				expected = 48
				passed = await wait_for(group,expected,true,"queued_arrival")
			else: failures.append("DEPLOYMENT_REJECTED: "+response.failure_reason)
		"stationary_rank", "terrain_detour":
			if case_name == "stationary_rank": spawn(8,2600,3800,8,true)
			else:
				var body := StaticBody2D.new()
				body.position = point(3200,3800)
				body.collision_layer = 1
				body.collision_mask = 0
				var shape := CollisionShape2D.new()
				var rectangle := RectangleShape2D.new()
				rectangle.size = Vector2(1100,160)
				shape.shape = rectangle
				body.add_child(shape)
				game.add_child(body)
				await get_tree().physics_frame
				game.squad_commands.points.invalidate_terrain()
			group = [spawn(12,2800,4800)]
			expected = 12
			if order(group,"DEFEND",point(3200,2500),route([Vector2(3200,3800),Vector2(3200,3000)])):
				passed = await wait_for(group,expected,true,"pass_obstruction")
		"whole_point_release", "whole_point_relocate", "reinforce":
			group = [spawn(24,2200,4500),spawn(24,3500,4500)] if case_name != "reinforce" else [spawn(12,2800,4500)]
			expected = 48 if case_name != "reinforce" else 12
			if order(group,"DEFEND",point(3200,4000)) and await wait_for(group,expected,true,"establish_origin"):
				if case_name == "whole_point_release":
					if order(group,"ADVANCE",Vector2.ZERO,route([Vector2(4500,4300),Vector2(4500,2400),Vector2(3200,2000)])): passed = await wait_for(group,expected,false,"release_curved_route")
				elif case_name == "whole_point_relocate":
					if order(group,"DEFEND",point(4500,2800),route([Vector2(4400,4100),Vector2(4500,3300)])): passed = await wait_for(group,expected,true,"relocate_route_loop")
				else:
					game.squad_commands.points.update(0,true)
					var old_homes: Dictionary = group[0].defense_positions.duplicate()
					var inbound := spawn(24,2200,5300)
					if order([inbound],"ADVANCE",Vector2.ZERO,route([Vector2(3000,4700),Vector2(3200,4000)])):
						if inbound.order_id != group[0].order_id: failures.append("REINFORCEMENT_NOT_JOINED")
						if group[0].defense_positions != old_homes: failures.append("SETTLED_HOMES_CHANGED")
						group.append(inbound)
						expected = 36
						passed = await wait_for(group,expected,true,"reinforce_arrival")
		"crossing_orders":
			var left := spawn(24,1400,4500)
			var right := spawn(24,4300,4500)
			group = [left,right]
			expected = 48
			if order([left],"DEFEND",point(4500,2800),route([Vector2(3400,4100),Vector2(4500,3400)])) and order([right],"DEFEND",point(1800,2800),route([Vector2(3000,3800),Vector2(1800,3400)])):
				passed = await wait_for(group,expected,true,"crossing_arrival")
		"mid_entry_reorder":
			game.economies[team].current_command = 10
			var response: Dictionary = game.deployment_manager.request_squad(team,[game.card_catalog.conscript_wave,game.card_catalog.conscript_wave,game.card_catalog.commander_mojo],Rect2(2200+shift,0,1900,800),"ADVANCE")
			if response.is_valid:
				group = [response.resolved_deployment.squad]
				expected = 48
				for tick in range(90):
					await get_tree().physics_frame
					elapsed_ticks += 1
					_sample()
				if order(group,"DEFEND",point(4500,4000),route([Vector2(4400,5000),Vector2(4500,4500)])): passed = await wait_for(group,expected,true,"mid_entry_redirect")
			else: failures.append("DEPLOYMENT_REJECTED: "+response.failure_reason)
		"edge_route":
			group = [spawn(12,4800,4600)]
			expected = 12
			if order(group,"DEFEND",point(5500,3200),PackedVector2Array([Vector2(game.field_size.x-1,point(0,4200).y),point(5500,3500)])): passed = await wait_for(group,expected,true,"bounded_edge_route")
		"mass_route":
			for index in range(6): group.append(spawn(12,2300,4400+index*160,12))
			expected = 72
			if order(group,"DEFEND",point(3200,3500)) and await wait_for(group,expected,true,"mass_establish"):
				if order(group,"DEFEND",point(4200,3000),route([Vector2(3800,4600),Vector2(4200,3600)])): passed = await wait_for(group,expected,true,"mass_route_loop")
		"sealed_destination":
			group = [spawn(1,3200,4700)]
			expected = 1
			if order(group,"DEFEND",point(3200,3500)):
				var home: Vector2 = group[0].defense_positions[0]
				var ring: Array = []
				for index in range(8): ring.append(home+Vector2.from_angle(index*TAU/8)*210)
				spawn_positions(ring,true)
				passed = not await wait_for(group,expected,true,"expected_blocked",720)
				passed = passed and group[0].living_members().size() == expected
				if passed: stage_results[-1].passed = true
				stage_results[-1]["expected_blocked"] = true
	if not passed and failures.is_empty(): failures.append("ARRIVAL_TIMEOUT_OR_UNEXPECTED_STALL")
	if overlaps > 0: failures.append("BODY_OVERLAP: %d samples" % overlaps)
	if invalid_motion > 0: failures.append("INVALID_MOTION: %d samples" % invalid_motion)
	passed = passed and failures.is_empty()
	var result := {"case":case_name,"seed":seed_number,"team":team,"passed":passed,"expected_members":expected,"simulation_seconds":elapsed_ticks/60.0,"overlap_samples":overlaps,"overlap_events":overlap_events.duplicate(true),"invalid_motion_samples":invalid_motion,"stages":stage_results.duplicate(true),"recovery":game.formation_manager.recovery.metrics.duplicate(),"failures":failures.duplicate(),"last_snapshots":history.duplicate(true) if not passed else []}
	results.append(result)
	print("PATHING CASE %s seed=%d team=%d %s stages=%s" % [case_name,seed_number,team,"PASS" if passed else "FAIL",JSON.stringify(stage_results)])
	game.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame
	if not destination.is_empty(): IO.write_json(destination,_report(false))

func _exit_tree() -> void:
	if is_instance_valid(game): game.queue_free()
