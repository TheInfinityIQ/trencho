extends RefCounted

var battle: Node
func _init(owner_battle: Node) -> void:
	battle = owner_battle

func rejected(reason: String, cost: float = 0.0) -> Dictionary:
	return {"is_valid": false, "failure_reason": reason, "total_cost": cost, "resolved_deployment": {}}

func resolve_package(selected_cards: Array) -> Dictionary:
	var unit_cards: Array = []
	var modifiers: Array = []
	var cost := 0.0
	for card in selected_cards:
		if card == null or not card is BattleCard or card.command_cost < 0: return rejected("INVALID_CARD")
		cost += card.command_cost
		if card.card_type == BattleCard.Type.UNIT: unit_cards.append(card)
		else: modifiers.append(card)
	if unit_cards.is_empty(): return rejected("NO_UNIT_CARD",cost)
	if unit_cards.size() > 2: return rejected("TOO_MANY_UNIT_CARDS",cost)
	if selected_cards.size() > 3: return rejected("TOO_MANY_CARDS",cost)
	if modifiers.size() > battle.tuning.maximum_modifiers: return rejected("TOO_MANY_MODIFIERS",cost)
	# Card IDs impose deterministic override precedence; modifier selection order is irrelevant.
	modifiers.sort_custom(func(a,b): return a.card_id < b.card_id)
	var components: Array = []
	var total := 0
	var base_total := 0
	for base in unit_cards:
		for modifier in modifiers:
			if not modifier.compatible_with(base): return rejected("INCOMPATIBLE_MODIFIER",cost)
		var stats: Dictionary = base.base_stats()
		for key in stats:
			for modifier in modifiers: stats[key] += float(modifier.additive.get(key,0.0))
			for modifier in modifiers: stats[key] *= float(modifier.multiplicative.get(key,1.0))
			for modifier in modifiers:
				if modifier.overrides.has(key): stats[key] = modifier.overrides[key]
		stats.quantity = maxi(1,floori(stats.quantity))
		stats.score_value = maxi(1,floori(stats.score_value))
		for key in ["health","damage","melee_damage","move_speed","attack_range","melee_range"]: stats[key] = maxf(1,stats[key])
		for key in ["attack_interval","melee_interval"]: stats[key] = maxf(0.1,stats[key])
		stats.unit_type = base.card_id
		components.append(stats)
		total += stats.quantity
		base_total += base.quantity
	var resolved: Dictionary = components[0].duplicate()
	resolved.quantity = total
	resolved.base_quantity = base_total
	resolved.source_cards = selected_cards.duplicate()
	resolved.components = components
	return {"is_valid":true,"failure_reason":"","total_cost":cost,"resolved_deployment":resolved}

func assign_components(specification: Dictionary) -> void:
	var components: Array = specification.get("components",[specification])
	var positions: Array = specification.spawn_positions
	var distribution: Array = []
	if components.size() == 1:
		for index in range(positions.size()): distribution.append(0)
	else:
		# Slots are front-to-rear. Weighted interleaving within ranks spreads
		# scarce front-priority soldiers across file heads, never in a left block.
		var remaining: Array[int] = [int(components[0].quantity),int(components[1].quantity)]
		var cursor := 0
		var remainder_first := 0
		var remainder_second := 0
		var remainder_index := 0
		while cursor < positions.size():
			var end := cursor+1
			while end < positions.size() and is_equal_approx(positions[end].y,positions[cursor].y): end += 1
			var width := end-cursor
			var front := mini(width,remaining[0])
			for column in range(width):
				var component := 0 if floori(float(column+1)*front/width) > floori(float(column)*front/width) else 1
				if cursor > 0:
					# Carry the weighted remainder across ranks. Rounding each
					# one-file rank independently would create two large blocks.
					var total := remainder_first+remainder_second
					component = 1 if floori(float(remainder_index+1)*remainder_second/total) > floori(float(remainder_index)*remainder_second/total) else 0
					remainder_index += 1
				distribution.append(component)
				remaining[component] -= 1
			if cursor == 0:
				remainder_first = remaining[0]
				remainder_second = remaining[1]
			cursor = end
	specification.member_components = distribution

func validate_formation(team: int, selected_cards: Array, rectangle: Rect2) -> Dictionary:
	var result := resolve_package(selected_cards)
	if not result.is_valid:
		return result
	if not battle.battle_active:
		return rejected("BATTLE_ENDED", result.total_cost)
	if not battle.formation_manager.regions.has(team):
		return rejected("INVALID_ZONE", result.total_cost)
	var formation: Dictionary = battle.formation_manager.evaluate(team, rectangle, result.resolved_deployment.quantity)
	result["formation"] = formation
	if not formation.is_valid:
		result.is_valid = false
		result.failure_reason = formation.failure_reason
		return result
	if not battle.economies[team].can_spend(result.total_cost):
		result.is_valid = false
		result.failure_reason = "INSUFFICIENT_COMMAND"
		return result
	result.resolved_deployment["spawn_positions"] = formation.chosen_slots
	result.resolved_deployment["requested_rectangle"] = rectangle
	result.resolved_deployment["team"] = team
	result.resolved_deployment["lane"] = battle.lane_for_x(rectangle.get_center().x)
	result.resolved_deployment["reinforcements"] = true
	return result

func request_formation(team: int, cards: Array, rectangle: Rect2) -> Dictionary:
	battle.deployment_requested.emit(team, cards, rectangle)
	var result := validate_formation(team, cards, rectangle)
	if not result.is_valid:
		battle.last_rejection = result.failure_reason
		battle.deployment_rejected.emit(team, result.failure_reason)
		return result
	# Reserve and queue only after every spatial, package and economy check succeeds.
	battle.economies[team].spend(result.total_cost)
	battle.squad_commands.create_squad(result.resolved_deployment)
	battle.formation_manager.reserve(result.resolved_deployment)
	if team == 2:
		battle.player_deployment_confirmed = true
	battle.last_rejection = ""
	battle.deployment_accepted.emit(team, result.resolved_deployment)
	return result

# Lane presets are retained for the bot and developer tests, not as player locks.
func validate_deployment(team: int, cards: Array, lane: int) -> Dictionary:
	if team not in [1, 2] or lane < 0 or lane > 3:
		return rejected("INVALID_ZONE")
	return validate_formation(team, cards, battle.preset_footprint(team, lane))

func request_deployment(team: int, cards: Array, lane: int) -> Dictionary:
	if team not in [1, 2] or lane < 0 or lane > 3:
		return rejected("INVALID_ZONE")
	return request_formation(team, cards, battle.preset_footprint(team, lane))

# New player/bot order path: geometry sets entry shape, never battlefield legality.
func validate_squad(team: int, cards: Array, rectangle: Rect2, kind: String, center: Vector2 = Vector2.ZERO, radius: float = 0, route: PackedVector2Array = PackedVector2Array()) -> Dictionary:
	var response := resolve_package(cards)
	if not response.is_valid: return response
	if team not in [1, 2]: return rejected("INVALID_ZONE", response.total_cost)
	if not battle.battle_active: return rejected("BATTLE_ENDED", response.total_cost)
	if kind not in ["ADVANCE", "DEFEND"]: return rejected("UNRECOGNIZED_GESTURE", response.total_cost)
	if not rectangle.position.is_finite() or not rectangle.size.is_finite() or rectangle.size.x <= 0 or rectangle.size.y <= 0 or rectangle.position.x < 0 or rectangle.end.x > battle.field_size.x:
		return rejected("INVALID_FORMATION", response.total_cost)
	var candidates: Array = battle.formation_manager.generate_slots(rectangle, team)
	if candidates.size() < response.resolved_deployment.quantity: return rejected("NOT_ENOUGH_SPACE", response.total_cost)
	var plan: Dictionary = {}
	if kind == "DEFEND":
		plan = battle.squad_commands.points.plan(team, response.resolved_deployment.quantity, center)
		if not plan.success: return rejected(plan.failure_reason, response.total_cost)
	if not battle.economies[team].can_spend(response.total_cost): return rejected("INSUFFICIENT_COMMAND", response.total_cost)
	for waypoint in route:
		if not waypoint.is_finite() or not Rect2(Vector2.ZERO,battle.field_size).has_point(waypoint): return rejected("POSITION_UNREACHABLE",response.total_cost)
	response["defense_plan"] = plan
	response.resolved_deployment["spawn_positions"] = battle.formation_manager.choose_slots(team, rectangle, response.resolved_deployment.quantity, candidates)
	response.resolved_deployment["team"] = team
	response.resolved_deployment["requested_rectangle"] = rectangle
	response.resolved_deployment["lane"] = battle.lane_for_x(rectangle.get_center().x)
	response.resolved_deployment["reinforcements"] = true
	response.resolved_deployment["intent_order"] = true
	return response

func request_squad(team: int, cards: Array, rectangle: Rect2, kind: String, center: Vector2 = Vector2.ZERO, radius: float = 0, route: PackedVector2Array = PackedVector2Array()) -> Dictionary:
	battle.deployment_requested.emit(team, cards, rectangle)
	var response := validate_squad(team, cards, rectangle, kind, center, radius, route)
	if not response.is_valid:
		battle.last_rejection = response.failure_reason
		battle.deployment_rejected.emit(team, response.failure_reason)
		return response
	battle.economies[team].spend(response.total_cost)
	var squad: BattleSquad = battle.squad_commands.create_squad(response.resolved_deployment)
	battle.formation_manager.reserve(response.resolved_deployment)
	var target_id: int = battle.squad_commands.points.point_at(team,route[-1]) if kind == "ADVANCE" and not route.is_empty() else -1
	response["command_result"] = battle.squad_commands.apply_validated([squad], "DEFEND" if target_id >= 0 else kind, response.defense_plan, route, target_id)
	if team == 2: battle.player_deployment_confirmed = true
	battle.last_rejection = ""
	battle.deployment_accepted.emit(team, response.resolved_deployment)
	return response
