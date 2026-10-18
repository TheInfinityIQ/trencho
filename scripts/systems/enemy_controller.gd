extends RefCounted

var battle: Node
var remaining := 1.0
var rng := RandomNumberGenerator.new()
var last_decision := "Waiting for Command"
var chosen_lane := -1
var chosen_deployment := "None"
var last_strengths: Array[int] = [0, 0, 0]
var last_open: Array[int] = []

func _init(owner_battle: Node) -> void:
	battle = owner_battle
	rng.seed = battle.tuning.random_seed + 1
	remaining = battle.tuning.enemy_decision_interval

func tick(delta: float) -> void:
	if not battle.player_deployment_confirmed:
		last_decision = "Waiting for player’s first deployment"
		return
	remaining -= delta
	if remaining <= 0:
		remaining += maxf(0.1, battle.tuning.enemy_decision_interval)
		decide()

func decide() -> void:
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
	var result: Dictionary = battle.deployment_manager.request_squad(1, [rifle], battle.preset_footprint(1, lane), "ADVANCE")
	if result.is_valid:
		chosen_lane = lane
		chosen_deployment = rifle.display_name
	else:
		last_decision = "Rejected: " + result.failure_reason
