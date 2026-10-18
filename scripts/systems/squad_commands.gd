extends RefCounted

signal selection_changed
signal command_resolved(result)

const SQUAD = preload("res://scripts/systems/squad.gd")
var battle: Node
var squads: Dictionary = {}
var selected_ids: Array[int] = []
var orders: Dictionary = {}
var next_squad_id := 1
var next_order_id := 1

func _init(owner_battle: Node) -> void:
	battle = owner_battle

func create_squad(specification: Dictionary) -> BattleSquad:
	var squad := SQUAD.new()
	squad.squad_id = next_squad_id
	next_squad_id += 1
	squad.team = specification.team
	squad.unit_type = specification.unit_type
	squad.source_cards = specification.get("source_cards", []).duplicate()
	squads[squad.squad_id] = squad
	specification["squad"] = squad
	return squad

func count_members(squad: BattleSquad) -> int:
	var count := squad.living_members().size()
	for slot in battle.formation_manager.pending:
		if slot.specification.get("squad") == squad: count += 1
	return count

func selected_squads() -> Array:
	var result: Array = []
	for id in selected_ids:
		if squads.has(id) and count_members(squads[id]) > 0: result.append(squads[id])
	return result

func clear_selection() -> void:
	for id in selected_ids:
		if squads.has(id): squads[id].selected = false
	selected_ids.clear()
	selection_changed.emit()

func select_unit(unit: Unit, additive: bool = false) -> void:
	if not is_instance_valid(unit) or not unit.is_alive() or unit.team_id != 2 or unit.squad == null: return
	var squad: BattleSquad = unit.squad
	if selected_ids.has(squad.squad_id):
		selected_ids.erase(squad.squad_id)
		squad.selected = false
	else:
		if not additive: clear_selection()
		selected_ids.append(squad.squad_id)
		squad.selected = true
	selection_changed.emit()

func centroid() -> Vector2:
	var position := Vector2.ZERO
	var count := 0
	for squad in selected_squads():
		for unit in squad.living_members():
			position += unit.global_position
			count += 1
	return position / count if count > 0 else battle.field_size * Vector2(0.5, 0.85)

func unit_at(world: Vector2, tolerance: float) -> Unit:
	var closest: Unit = null
	var distance := tolerance * tolerance
	for unit in battle.units:
		if unit.team_id == 2 and unit.is_alive():
			var candidate: float = world.distance_squared_to(unit.global_position)
			if candidate < distance:
				distance = candidate
				closest = unit
	return closest

func member_removed(unit: Unit) -> void:
	if unit.squad == null: return
	unit.squad.members.erase(unit)
	if orders.has(unit.squad.order_id): orders[unit.squad.order_id].dirty = true
	prune()

func prune() -> void:
	var changed := false
	for id in squads.keys():
		var squad: BattleSquad = squads[id]
		if count_members(squad) == 0:
			if selected_ids.has(id):
				selected_ids.erase(id)
				changed = true
			squads.erase(id)
	if changed: selection_changed.emit()
	for id in orders.keys():
		var remaining: Array = orders[id].squads.filter(func(squad_id): return squads.has(squad_id) and squads[squad_id].order_id == id)
		orders[id].squads = remaining
		if remaining.is_empty(): orders.erase(id)

func result(success: bool, kind: String, reason: String = "") -> Dictionary:
	return {"success": success, "command_type": kind, "affected_squad_ids": [], "failure_reason": reason, "defense_center": Vector2.ZERO, "defense_radius": 0.0, "expanded": false}

func defense_plan(team: int, count: int, center: Vector2, requested_radius: float) -> Dictionary:
	var plan := result(false, "DEFEND", "INVALID_DEFEND_AREA")
	if count < 1 or not center.is_finite() or not is_finite(requested_radius) or requested_radius < 0: return plan
	var radius: float = maxf(requested_radius, battle.tuning.minimum_defense_radius)
	var maximum: float = battle.tuning.maximum_defense_radius
	# Leave traversable corridors between settled defenders; a body-tight grid can trap late arrivals.
	var spacing: float = maxf(battle.tuning.defense_spacing, battle.tuning.unit_radius * 4 + 16)
	while radius <= maximum + 0.01:
		var points: Array[Vector2] = []
		var ranks := floori((radius - battle.tuning.unit_radius) / spacing)
		for row in range(-ranks, ranks + 1):
			for column in range(-ranks, ranks + 1):
				var offset := Vector2(column, row) * spacing
				if offset.length() + battle.tuning.unit_radius <= radius + 0.01:
					points.append(center + offset)
		if points.size() >= count:
			var inside: bool = center.x - radius >= 0 and center.x + radius <= battle.field_size.x and center.y - radius >= 0 and center.y + radius <= battle.field_size.y
			var outside_no_hold: bool = center.y - radius >= battle.tuning.no_hold_depth if team == 2 else center.y + radius <= battle.field_size.y - battle.tuning.no_hold_depth
			if not inside or not outside_no_hold: return plan
			points = points.filter(func(point): return not battle.formation_manager.terrain_blocks(point))
			if points.size() >= count:
				# Adjacent positions are allocated in squad-sized chunks to keep ownership coherent.
				plan.success = true
				plan.failure_reason = ""
				plan.defense_center = center
				plan.defense_radius = radius
				plan.expanded = radius > requested_radius + 0.01
				points.sort_custom(func(a, b): return a.distance_squared_to(center) < b.distance_squared_to(center))
				var packed: Array = points.slice(0, count)
				packed.sort_custom(func(a, b): return a.x < b.x if is_equal_approx(a.y, b.y) else a.y < b.y)
				plan["positions"] = packed
				return plan
		radius += spacing * 0.25
	plan.failure_reason = "POSITION_UNREACHABLE"
	return plan

func apply_validated(group: Array, kind: String, plan: Dictionary = {}) -> Dictionary:
	var response := result(true, kind)
	var shared_id := -1
	if kind == "DEFEND":
		shared_id = next_order_id
		next_order_id += 1
		orders[shared_id] = {"squads": [], "center": plan.defense_center, "radius": plan.defense_radius, "dirty": false, "enemies": [], "enemy_cache_valid": false}
		response.defense_center = plan.defense_center
		response.defense_radius = plan.defense_radius
		response.expanded = plan.expanded
	var position_index := 0
	for squad in group:
		if orders.has(squad.order_id): orders[squad.order_id].dirty = true
		squad.intent = kind
		squad.order_id = shared_id
		squad.defense_positions.clear()
		response.affected_squad_ids.append(squad.squad_id)
		if kind == "DEFEND":
			squad.defense_center = plan.defense_center
			squad.defense_radius = plan.defense_radius
			orders[shared_id].squads.append(squad.squad_id)
			position_index = _assign_positions(squad, plan.positions, position_index)
		else:
			squad.defense_radius = 0
		for unit in squad.living_members():
			unit.defense_established = false
			unit.defense_avoid_side = 1.0 if unit.squad_member_index % 2 == 0 else -1.0
			unit.target = null
			unit.state = Unit.State.MOVING_TO_DEFEND if kind == "DEFEND" else (Unit.State.ADVANCING if unit.has_entered_battlefield else Unit.State.ENTERING_BATTLEFIELD)
	command_resolved.emit(response)
	return response

func issue_selected(kind: String, center: Vector2 = Vector2.ZERO, radius: float = 0) -> Dictionary:
	prune()
	var group := selected_squads()
	var response := result(false, kind, "NO_SELECTED_UNITS")
	if not battle.battle_active: response.failure_reason = "BATTLE_ENDED"
	elif not group.is_empty():
		if kind == "ADVANCE": return apply_validated(group, kind)
		if kind == "DEFEND":
			var count := 0
			for squad in group: count += count_members(squad)
			var plan := defense_plan(2, count, center, radius)
			if plan.success: return apply_validated(group, kind, plan)
			response = plan
		else: response.failure_reason = "UNRECOGNIZED_GESTURE"
	command_resolved.emit(response)
	return response

func tick() -> void:
	prune()
	for id in orders.keys():
		var order: Dictionary = orders[id]
		_refresh_enemies(order)
		if not order.dirty: continue
		var group: Array = []
		var count := 0
		var pressure := false
		for squad_id in order.squads:
			var squad: BattleSquad = squads[squad_id]
			group.append(squad)
			count += count_members(squad)
			for unit in squad.living_members():
				if is_instance_valid(unit.target) and unit.target.is_alive(): pressure = true
		if not order.enemies.is_empty(): pressure = true
		if pressure: continue
		var plan := defense_plan(group[0].team, count, order.center, order.radius)
		if not plan.success: continue
		order.radius = plan.defense_radius
		var index := 0
		for squad in group:
			squad.defense_radius = plan.defense_radius
			index = _assign_positions(squad, plan.positions, index)
			for unit in squad.living_members(): unit.state = Unit.State.RETURNING_TO_DEFENSE
		order.dirty = false

func _assign_positions(squad: BattleSquad, positions: Array, offset: int) -> int:
	var members: Array = []
	for unit in squad.living_members(): members.append({"index": unit.squad_member_index, "position": unit.global_position})
	for slot in battle.formation_manager.pending:
		if slot.specification.get("squad") == squad: members.append({"index": slot.member_index, "position": slot.entry_position})
	# Match horizontal ordering once per command/reformation. This avoids
	# crossing the entire formation and costs no per-soldier path search.
	members.sort_custom(func(a,b): return a.position.x < b.position.x if not is_equal_approx(a.position.x,b.position.x) else (a.position.y < b.position.y if squad.team == 2 else a.position.y > b.position.y))
	var homes: Array = positions.slice(offset,offset+members.size())
	homes.sort_custom(func(a,b): return a.x < b.x if not is_equal_approx(a.x,b.x) else (a.y < b.y if squad.team == 2 else a.y > b.y))
	squad.defense_positions.clear()
	for index in range(members.size()): squad.defense_positions[members[index].index] = homes[index]
	return offset+members.size()

func invalidate_enemy_cache() -> void:
	for order in orders.values(): order.enemy_cache_valid = false

func _refresh_enemies(order: Dictionary) -> void:
	order.enemies.clear()
	if order.squads.is_empty(): return
	var team: int = squads[order.squads[0]].team
	var radius_squared: float = order.radius * order.radius
	for unit in battle.units:
		if unit.team_id != team and unit.is_alive() and unit.global_position.distance_squared_to(order.center) <= radius_squared: order.enemies.append(unit)
	order.enemy_cache_valid = true

func defense_enemies(squad: BattleSquad) -> Array:
	if not orders.has(squad.order_id): return []
	var order: Dictionary = orders[squad.order_id]
	if not order.enemy_cache_valid: _refresh_enemies(order)
	return order.enemies
