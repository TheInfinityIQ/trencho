extends RefCounted

var battle: Node
var team := 1
var advance_only := false
var planned_package: Array = []
var package_bag: Array = []
var remaining := 1.0
var rng := RandomNumberGenerator.new()
var last_decision := "Waiting for Command"
var chosen_lane := -1
var chosen_deployment := "None"
var last_strengths: Array[int] = [0, 0, 0]
var last_open: Array[int] = []
var doctrine := "LINE"
var deployment_cooldown := 0.0
var uncommitted: Array[int] = []
var doctrine_points: Dictionary = {}
var reinforcement_priority := "None"

func _init(owner_battle: Node, side: int = 1, chosen_doctrine: String = "") -> void:
	battle = owner_battle
	team = side
	rng.seed = battle.tuning.random_seed + 1
	doctrine = battle.tuning.enemy_doctrine if chosen_doctrine.is_empty() else chosen_doctrine
	if doctrine == "RANDOM": doctrine = "LINE" if rng.randf() < 0.5 else "TRIANGLE"
	remaining = battle.tuning.enemy_decision_interval

func tick(delta: float) -> void:
	deployment_cooldown = maxf(0,deployment_cooldown-delta)
	_assign_available()
	if not battle.player_deployment_confirmed:
		last_decision = "Waiting for player’s first deployment"
		return
	remaining -= delta
	if remaining <= 0:
		remaining += maxf(0.1, battle.tuning.enemy_decision_interval)
		decide()

func decide() -> void:
	if deployment_cooldown > 0: return
	if not battle.battle_active or not battle.player_deployment_confirmed:
		last_decision = "Waiting for player’s first deployment"
		return
	_assign_available()
	if not advance_only and (priority() == "WAIT" or not uncommitted.is_empty()):
		last_decision = "Waiting for committed defenders to establish"
		return
	battle.refresh_occupancy()
	if planned_package.is_empty(): planned_package = next_package()
	var planned: Dictionary = battle.deployment_manager.resolve_package(planned_package)
	if not battle.economies[team].can_spend(planned.total_cost):
		last_decision = "Wait: insufficient Command; saving for planned package"
		return
	last_open.clear()
	for lane in range(3):
		var formation: Dictionary = battle.deployment_manager.validate_squad(team, planned_package, battle.preset_footprint(team, lane), "ADVANCE")
		if formation.is_valid:
			last_open.append(lane)
		last_strengths[lane] = battle.lane_strength(3-team, lane)
	if last_open.is_empty():
		last_decision = "Wait: no usable entry frontage"
		return

	var lane: int = last_open[rng.randi_range(0, last_open.size() - 1)]
	if rng.randf() < battle.tuning.enemy_weak_lane_weight:
		var minimum := 2147483647
		var weakest: Array[int] = []
		for candidate in last_open:
			if last_strengths[candidate] < minimum:
				minimum = last_strengths[candidate]
				weakest.clear()
			if last_strengths[candidate] == minimum:
				weakest.append(candidate)
		lane = weakest[rng.randi_range(0, weakest.size() - 1)]
		last_decision = "Weakest legal lane (%.0f%% policy)" % (battle.tuning.enemy_weak_lane_weight * 100)
	else:
		last_decision = "Random legal lane (%.0f%% policy)" % ((1 - battle.tuning.enemy_weak_lane_weight) * 100)
	var package: Array = planned_package.duplicate()
	var rectangle: Rect2 = battle.preset_footprint(team,lane)
	var resolved: Dictionary = battle.deployment_manager.resolve_package(package)
	while battle.formation_manager.generate_slots(rectangle,team).size() < resolved.resolved_deployment.quantity:
		rectangle.size.y += battle.tuning.spawn_spacing
	var result: Dictionary = battle.deployment_manager.request_squad(team, package, rectangle, "ADVANCE")
	if result.is_valid:
		battle.telemetry.event("AI_DEPLOYMENT_DECISION",{"team":team,"available_command":battle.economies[team].current_command+result.total_cost,"cards_chosen":result.resolved_deployment.squad.source_cards.map(func(card): return card.card_id),"package_cost":result.total_cost,"reason":last_decision,"squad_id":result.resolved_deployment.squad.squad_id})
		deployment_cooldown = maxf(1.0,battle.tuning.enemy_decision_interval)
		uncommitted.append(result.resolved_deployment.squad.squad_id)
		_assign_available()
		chosen_lane = lane
		chosen_deployment = " + ".join(package.map(func(card): return card.display_name))
		planned_package.clear()
	else:
		last_decision = "Rejected: " + result.failure_reason

func anchor(key: String) -> Vector2:
	var fraction: float = {"left":0.25,"center":0.5,"right":0.75}[key]
	var depth: float = battle.tuning.enemy_defense_depth
	if doctrine == "TRIANGLE" and key == "center": depth += battle.tuning.enemy_apex_extra_depth
	return Vector2(battle.field_size.x*fraction,depth if team == 1 else battle.field_size.y-depth)

func defender_count(key: String, include_inbound: bool = false) -> int:
	var id: int = doctrine_points.get(key,-1)
	if not battle.squad_commands.orders.has(id): return 0
	var point: Dictionary = battle.squad_commands.orders[id]
	return point.established+(point.inbound if include_inbound else 0)

func priority() -> String:
	# Inbound commitments reserve the deficit, but do not increase territory.
	if doctrine == "TRIANGLE" and defender_count("center") < 20:
		return "center" if defender_count("center",true) < 20 else "WAIT"
	var left := defender_count("left",true)
	var right := defender_count("right",true)
	if left < 10 or right < 10: return "left" if left <= right else "right"
	if defender_count("left") < 10 or defender_count("right") < 10: return "WAIT"
	if defender_count("center") < 10: return "center" if defender_count("center",true) < 10 else "WAIT"
	return ""

func _assign_available() -> void:
	for id in uncommitted.duplicate():
		if not battle.squad_commands.squads.has(id):
			uncommitted.erase(id)
			continue
		var squad: BattleSquad = battle.squad_commands.squads[id]
		if battle.squad_commands.count_members(squad) == 0: continue
		var key := "" if advance_only else priority()
		if key == "WAIT":
			reinforcement_priority = "Waiting for committed defenders to establish"
			continue
		reinforcement_priority = key if not key.is_empty() else "Advance"
		if key.is_empty():
			uncommitted.erase(id)
			battle.telemetry.event("AI_ASSIGNMENT",{"team":team,"squad_id":id,"reason":"ADVANCE_EXCESS"})
			continue
		var target_id: int = doctrine_points.get(key,-1)
		var response: Dictionary = battle.squad_commands.issue_group([squad],"DEFEND",anchor(key),0,PackedVector2Array(),target_id)
		if response.success:
			uncommitted.erase(id)
			battle.telemetry.event("AI_ASSIGNMENT",{"team":team,"squad_id":id,"reason":("REINFORCE_" if target_id >= 0 else "ESTABLISH_")+key.to_upper(),"point_id":response.defensive_point_id})
			doctrine_points[key] = response.defensive_point_id
			battle.squad_commands.points.update(0,true)

func next_package() -> Array:
	# Shared shuffled template bag prevents the cheapest affordable Rifle from
	# consuming each regeneration tick before mixed packages can be afforded.
	if package_bag.is_empty():
		package_bag = [["rifle_squad"],["conscript_wave"],["assault_squad"],
			["rifle_squad","conscript_wave"],["rifle_squad","assault_squad"],["conscript_wave","assault_squad"]]
		for index in range(package_bag.size()-1,0,-1):
			var other := rng.randi_range(0,index)
			var swap = package_bag[index]
			package_bag[index] = package_bag[other]
			package_bag[other] = swap
	var cards: Array = []
	for id in package_bag.pop_back(): cards.append(battle.card_catalog[id])
	if rng.randf() < 0.25:
		var modifiers := ["commander_mojo","forced_march","defensive_officer"]
		var modifier = battle.card_catalog[modifiers[rng.randi_range(0,modifiers.size()-1)]]
		var modified: Dictionary = battle.deployment_manager.resolve_package(cards+[modifier])
		if modified.is_valid and modified.total_cost <= battle.economies[team].maximum_command: cards.append(modifier)
	var resolved: Dictionary = battle.deployment_manager.resolve_package(cards)
	if not resolved.is_valid or resolved.total_cost > battle.economies[team].maximum_command:
		return [battle.card_catalog.conscript_wave]
	return cards
