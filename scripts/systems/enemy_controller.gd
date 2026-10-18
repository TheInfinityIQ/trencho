extends RefCounted

var battle: Node
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

func _init(owner_battle: Node) -> void:
	battle = owner_battle
	rng.seed = battle.tuning.random_seed + 1
	doctrine = battle.tuning.enemy_doctrine
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
	battle.refresh_occupancy()
	var rifle: Resource = battle.card_catalog["rifle_squad"]
	if not battle.economies[1].can_spend(rifle.command_cost):
		last_decision = "Wait: insufficient Command"
		return
	last_open.clear()
	for lane in range(3):
		var formation: Dictionary = battle.deployment_manager.validate_squad(1, [battle.card_catalog.rifle_squad], battle.preset_footprint(1, lane), "ADVANCE")
		if formation.is_valid:
			last_open.append(lane)
		last_strengths[lane] = battle.lane_strength(2, lane)
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
	var package: Array = [rifle]
	# Simple affordable packages, not a separate AI combat model or combo search.
	for id in ["assault_squad","conscript_wave"]:
		var mixed: Array = package+[battle.card_catalog[id]]
		var resolved: Dictionary = battle.deployment_manager.resolve_package(mixed)
		if rng.randf() < 0.35 and resolved.is_valid and battle.economies[1].can_spend(resolved.total_cost):
			package = mixed
			break
	for id in ["commander_mojo","forced_march","defensive_officer"]:
		var modified: Array = package+[battle.card_catalog[id]]
		var resolved: Dictionary = battle.deployment_manager.resolve_package(modified)
		if rng.randf() < 0.25 and resolved.is_valid and battle.economies[1].can_spend(resolved.total_cost):
			package = modified
			break
	var rectangle: Rect2 = battle.preset_footprint(1,lane)
	var resolved: Dictionary = battle.deployment_manager.resolve_package(package)
	while battle.formation_manager.generate_slots(rectangle,1).size() < resolved.resolved_deployment.quantity:
		rectangle.size.y += battle.tuning.spawn_spacing
	var result: Dictionary = battle.deployment_manager.request_squad(1, package, rectangle, "ADVANCE")
	if result.is_valid:
		deployment_cooldown = maxf(1.0,battle.tuning.enemy_decision_interval)
		uncommitted.append(result.resolved_deployment.squad.squad_id)
		chosen_lane = lane
		chosen_deployment = rifle.display_name
	else:
		last_decision = "Rejected: " + result.failure_reason

func anchor(key: String) -> Vector2:
	var fraction: float = {"left":0.25,"center":0.5,"right":0.75}[key]
	var depth: float = battle.tuning.enemy_defense_depth
	if doctrine == "TRIANGLE" and key == "center": depth += battle.tuning.enemy_apex_extra_depth
	return Vector2(battle.field_size.x*fraction,depth)

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
		if squad.living_members().is_empty() or squad.combat_center.y < battle.tuning.enemy_defense_depth: continue
		var key := priority()
		if key == "WAIT":
			reinforcement_priority = "Waiting for committed defenders to establish"
			continue
		uncommitted.erase(id)
		reinforcement_priority = key if not key.is_empty() else "Advance"
		if key.is_empty(): continue
		var target_id: int = doctrine_points.get(key,-1)
		var response: Dictionary = battle.squad_commands.issue_group([squad],"DEFEND",anchor(key),0,PackedVector2Array(),target_id)
		if response.success:
			doctrine_points[key] = response.defensive_point_id
			battle.squad_commands.points.update(0,true)
