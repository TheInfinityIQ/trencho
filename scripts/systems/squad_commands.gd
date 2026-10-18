extends RefCounted

signal selection_changed
signal command_resolved(result)

const SQUAD = preload("res://scripts/systems/squad.gd")
var battle: Node
var squads: Dictionary = {}
var selected_ids: Array[int] = []
var selected_point_id := -1
var orders: Dictionary = {}
var next_squad_id := 1
var next_order_id := 1
var points: RefCounted
var fronts: RefCounted
var simulation_time := 0.0

func _init(owner_battle: Node) -> void:
	battle = owner_battle
	points = preload("res://scripts/systems/defensive_points.gd").new(self)
	fronts = preload("res://scripts/systems/defensive_fronts.gd").new(self)

func create_squad(specification: Dictionary) -> BattleSquad:
	var squad := SQUAD.new()
	squad.squad_id = next_squad_id
	next_squad_id += 1
	squad.team = specification.team
	squad.route_bounds = Rect2(Vector2.ONE*battle.tuning.unit_radius,battle.field_size-Vector2.ONE*battle.tuning.unit_radius*2)
	# A drawn waypoint can be occupied by a friendly body. Accept passage
	# within body clearance rather than demanding an impossible exact hit.
	# Include the steering probe plus clearance on both sides of a blocked guide.
	squad.waypoint_clearance = maxf(45,(battle.tuning.unit_radius*2+2)*3)
	squad.unit_type = specification.unit_type
	squad.source_cards = specification.get("source_cards", []).duplicate()
	if specification.has("components") and specification.has("spawn_positions"): battle.deployment_manager.assign_components(specification)
	fronts.remember(squad,specification)
	squads[squad.squad_id] = squad
	specification["squad"] = squad
	if battle.telemetry != null: battle.telemetry.squad_created(specification)
	return squad

func count_members(squad: BattleSquad) -> int:
	var count := squad.living_members().size()
	count += int(battle.formation_manager.pending_counts.get(squad.squad_id,0))
	return count

func selected_squads() -> Array:
	var result: Array = []
	for id in selected_ids:
		if squads.has(id) and count_members(squads[id]) > 0: result.append(squads[id])
	return result

func clear_selection() -> void:
	selected_point_id = -1
	for id in selected_ids:
		if squads.has(id): squads[id].selected = false
	selected_ids.clear()
	selection_changed.emit()

func select_unit(unit: Unit, additive: bool = false) -> void:
	if not is_instance_valid(unit) or not unit.is_alive() or unit.team_id != 2 or unit.squad == null: return
	if selected_point_id >= 0 and not additive: clear_selection()
	selected_point_id = -1
	var squad: BattleSquad = unit.squad
	if selected_ids.has(squad.squad_id):
		selected_ids.erase(squad.squad_id)
		squad.selected = false
	else:
		if not additive: clear_selection()
		selected_ids.append(squad.squad_id)
		squad.selected = true
	selection_changed.emit()

func point_anchor_at(world: Vector2, tolerance: float) -> int:
	var nearest := -1
	var distance := tolerance*tolerance
	for id in orders:
		if orders[id].team != 2: continue
		var candidate: float = world.distance_squared_to(orders[id].center)
		if candidate <= distance:
			nearest = id
			distance = candidate
	return nearest

func select_point(id: int) -> void:
	clear_selection()
	if not orders.has(id) or orders[id].team != 2: return
	for squad_id in orders[id].squads:
		if not squads.has(squad_id): continue
		var established := false
		for member in squads[squad_id].living_members():
			if member.defense_established: established = true
		if established:
			selected_ids.append(squad_id)
			squads[squad_id].selected = true
	if not selected_ids.is_empty(): selected_point_id = id
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
	unit.squad.refresh_travel()
	if orders.has(unit.squad.order_id):
		var point: Dictionary = orders[unit.squad.order_id]
		point.dirty = true
		points.clock = 0
		# Reward only destruction, never a voluntary order change or departure.
		var remaining := 0
		for squad_id in point.squads:
			if squads.has(squad_id): remaining += count_members(squads[squad_id])
		if remaining == 0: break_point(unit.squad.order_id,true,"ALL_DEFENDERS_KILLED")
	prune()

func prune() -> void:
	var changed := false
	for id in squads.keys():
		var squad: BattleSquad = squads[id]
		if count_members(squad) == 0:
			if selected_ids.has(id):
				selected_ids.erase(id)
				changed = true
			if battle.telemetry != null: battle.telemetry.squad_ended(id)
			squads.erase(id)
	if changed: selection_changed.emit()
	for id in orders.keys():
		var remaining: Array = orders[id].squads.filter(func(squad_id): return squads.has(squad_id) and squads[squad_id].order_id == id)
		orders[id].squads = remaining
		if remaining.is_empty():
			battle.telemetry.point_deleted(id,orders[id].get("pending_delete_reason","NO_DEFENDERS_OR_INBOUND"))
			orders.erase(id)

func result(success: bool, kind: String, reason: String = "") -> Dictionary:
	return {"success": success, "command_type": kind, "affected_squad_ids": [], "failure_reason": reason, "defense_center": Vector2.ZERO, "defense_radius": 0.0, "expanded": false, "route": PackedVector2Array(), "defensive_point_id": -1}

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

func apply_validated(group: Array, kind: String, plan: Dictionary = {}, route: PackedVector2Array = PackedVector2Array(), target_id: int = -1) -> Dictionary:
	if kind == "DEFEND" and not plan.has("front_blocks"):
		plan = fronts.plan(group,plan.get("defense_center",orders[target_id].center if orders.has(target_id) else Vector2.ZERO),route,target_id)
		if not plan.success: return plan
	if selected_point_id >= 0: selected_point_id = -1
	var response := result(true,kind)
	response.team = group[0].team
	var shared_id := target_id
	if kind == "DEFEND":
		if not orders.has(shared_id):
			shared_id = next_order_id
			next_order_id += 1
			orders[shared_id] = {"id":shared_id,"squads":[],"team":group[0].team,"center":plan.defense_center,"anchors":[plan.defense_center],"radius":plan.defense_radius,"dirty":false,"enemies":[],"enemy_cache_valid":false,"cells":{},"preview_cells":plan.get("preview_cells",{}),"established":0,"inbound":0,"lifecycle":"PENDING","desired_cells":0,"desired_area":0.0,"actual_area":0.0,"pressure":0.0,"capacity":0,"capacity_state":"STABLE","neighbors":[],"contributors":{}}

		response.defense_center = plan.defense_center
		response.defense_radius = plan.defense_radius
		response.expanded = plan.expanded
		response.defensive_point_id = shared_id
	if kind == "DEFEND" and battle.telemetry != null: battle.telemetry.point_changed(shared_id)
	response.route = route.duplicate()
	var direction := Vector2.UP if group[0].team == 2 else Vector2.DOWN
	if route.size() >= 2: direction = route[0].direction_to(route[1])
	var lateral := Vector2(-direction.y,direction.x)
	var ordered := group.duplicate()
	ordered.sort_custom(func(a,b): return a.combat_center.dot(lateral) < b.combat_center.dot(lateral))
	for squad in group:
		if orders.has(squad.order_id):
			battle.telemetry.event("DEFENSIVE_POINT_LEFT",{"point_id":squad.order_id,"squad_id":squad.squad_id})
			orders[squad.order_id].pending_delete_reason = "REPLACED"
			orders[squad.order_id].dirty = true
			fronts.release(squad)
			orders[squad.order_id].squads.erase(squad.squad_id)
		squad.intent = kind
		squad.order_id = shared_id
		squad.defense_positions.clear()
		squad.corridor_offset = lateral*(ordered.find(squad)-(group.size()-1)*0.5)*battle.tuning.route_lane_spacing
		squad.route_waypoints = PackedVector2Array()
		for waypoint in route:
			var shifted: Vector2 = waypoint+squad.corridor_offset
			squad.route_waypoints.append(shifted.clamp(Vector2.ONE*battle.tuning.unit_radius,battle.field_size-Vector2.ONE*battle.tuning.unit_radius))
		squad.combat_target = null
		squad.route_indices.clear()
		squad.route_offsets.clear()
		squad.refresh_travel()
		var front := Vector2.ZERO
		var travelers: Array = []
		for unit in squad.living_members(): travelers.append({"index":unit.squad_member_index,"position":unit.position})
		for slot in battle.formation_manager.pending:
			if slot.specification.get("squad") == squad: travelers.append({"index":slot.member_index,"position":slot.entry_position})
		for member in travelers: front += member.position
		if not travelers.is_empty(): front /= travelers.size()
		for member in travelers:
			# Queue members need offsets too; a newly purchased large squad must
			# not funnel every soldier through the exact same drawn waypoint.
			squad.route_offsets[member.index] = (member.position-front).limit_length(battle.tuning.cohesion_leash*0.6)
		response.affected_squad_ids.append(squad.squad_id)
		if kind == "DEFEND":
			battle.telemetry.event("DEFENSIVE_POINT_JOINED",{"point_id":shared_id,"squad_id":squad.squad_id})
			squad.defense_center = plan.defense_center
			squad.defense_radius = plan.defense_radius
			orders[shared_id].squads.append(squad.squad_id)
		else: squad.defense_radius = 0
		for unit in squad.living_members():
			unit.reset_steering()
			unit.defense_established = false
			unit.target = null
			unit.state = Unit.State.MOVING_TO_DEFEND if kind == "DEFEND" else (Unit.State.ADVANCING if unit.has_entered_battlefield else Unit.State.ENTERING_BATTLEFIELD)
	if battle.telemetry != null:
		for squad in group: battle.telemetry.order(squad,kind,squad.route_waypoints)
	# Release vacated points before projecting homes for the replacement order.
	prune()
	if kind == "DEFEND":
		fronts.install(orders[shared_id],plan)
	points.clock = 0
	command_resolved.emit(response)
	return response

func _point_count(id: int) -> int:
	var count := 0
	for squad_id in orders[id].squads:
		if squads.has(squad_id): count += count_members(squads[squad_id])
	return count

func _group_count(group: Array, excluding: int = -1) -> int:
	var count := 0
	for squad in group:
		if squad.order_id != excluding or excluding == -1: count += count_members(squad)
	return count

func _repack(id: int) -> void:
	if not orders.has(id): return
	var order: Dictionary = orders[id]
	if order.has("blocks"):
		fronts.sync(order)
		return
	var count := _point_count(id)
	var cells: Dictionary = points.isolated(order.team,order.anchors,count)
	if count <= order.established and not order.cells.is_empty(): cells = order.cells.duplicate()
	# The home projection is not active territory, and cannot steal another
	# point's established cells. Arrivals increase actual area on the next solve.
	for cell in cells.keys():
		if points.owners.has(cell) and points.owners[cell] != id and orders.has(points.owners[cell]): cells.erase(cell)
	var positions: Array = points.homes(cells,count,order.center)
	if positions.size() < count: positions = points.homes(cells,count,order.center,true)
	if positions.size() < count:
		order.capacity_state = "CRITICAL"
		return
	order.preview_cells = cells
	order.radius = points.bounds_radius(cells,order.center)
	positions.sort_custom(func(a,b): return a.x < b.x if is_equal_approx(a.y,b.y) else (a.y < b.y if order.team == 2 else a.y > b.y))
	var inbound := false
	var established := false
	for squad_id in order.squads:
		if squads.has(squad_id):
			inbound = inbound or battle.formation_manager.pending_counts.get(squad_id,0) > 0
			for unit in squads[squad_id].living_members():
				inbound = inbound or not unit.defense_established
				established = established or unit.defense_established
	if inbound and established:
		_assign_arrival_sectors(order,positions)
		order.dirty = false
		return
	var offset := 0
	for squad_id in order.squads:
		if not squads.has(squad_id): continue
		var squad: BattleSquad = squads[squad_id]
		squad.defense_center = order.center
		squad.defense_radius = order.radius
		offset = _assign_positions(squad,positions,offset)
		for unit in squad.living_members():
			if unit.defense_established: unit.state = Unit.State.RETURNING_TO_DEFENSE
	order.dirty = false

func _assign_arrival_sectors(order: Dictionary, positions: Array) -> void:
	var available := positions.duplicate()
	var inbound: Array = []
	# Reserve settled bodies first, preserving their existing homes under pressure.
	for id in order.squads:
		if not squads.has(id): continue
		var squad: BattleSquad = squads[id]
		for unit in squad.living_members():
			if unit.defense_established:
				var home: Vector2 = squad.defense_positions.get(unit.squad_member_index,unit.position)
				var nearest := _nearest_home(available,home)
				if nearest >= 0: available.remove_at(nearest)
			else: inbound.append({"squad":squad,"index":unit.squad_member_index,"position":unit.position})
		for slot in battle.formation_manager.pending:
			if slot.specification.get("squad") == squad: inbound.append({"squad":squad,"index":slot.member_index,"position":slot.entry_position})
	var groups := {}
	for member in inbound:
		var id: int = member.squad.squad_id
		if not groups.has(id): groups[id] = []
		groups[id].append(member)
	for members in groups.values():
		var origin := Vector2.ZERO
		for member in members: origin += member.position
		origin /= members.size()
		var homes: Array = []
		for member in members:
			var nearest := _nearest_home(available,origin)
			if nearest < 0: break
			homes.append(available[nearest])
			available.remove_at(nearest)
		var team: int = members[0].squad.team
		# Preserve lateral files and send front arrivals into deeper homes first;
		# nearest-per-soldier assignment can settle a blocking front rank.
		members.sort_custom(func(a,b): return a.position.x < b.position.x if not is_equal_approx(a.position.x,b.position.x) else (a.position.y < b.position.y if team == 2 else a.position.y > b.position.y))
		homes.sort_custom(func(a,b): return a.x < b.x if not is_equal_approx(a.x,b.x) else (a.y < b.y if team == 2 else a.y > b.y))
		for index in range(homes.size()): members[index].squad.defense_positions[members[index].index] = homes[index]

func _nearest_home(positions: Array, origin: Vector2) -> int:
	var nearest := -1
	var distance := INF
	for index in range(positions.size()):
		var candidate: float = origin.distance_squared_to(positions[index])
		if candidate < distance:
			distance = candidate
			nearest = index
	return nearest

func issue_selected(kind: String, center: Vector2 = Vector2.ZERO, radius: float = 0, route: PackedVector2Array = PackedVector2Array()) -> Dictionary:
	prune()
	return issue_group(selected_squads(),kind,center,radius,route)

func issue_group(group: Array, kind: String, center: Vector2 = Vector2.ZERO, _radius: float = 0, route: PackedVector2Array = PackedVector2Array(), target_id: int = -1, facing: Vector2 = Vector2.ZERO) -> Dictionary:
	var response := result(false,kind,"NO_SELECTED_UNITS")
	response.team = group[0].team if not group.is_empty() else 2
	if not battle.battle_active: response.failure_reason = "BATTLE_ENDED"
	elif not group.is_empty():
		for squad in group:
			if squad.retreating:
				response.failure_reason = "SQUAD_RETREATING"
				command_resolved.emit(response)
				return response
		for waypoint in route:
			if not waypoint.is_finite() or not Rect2(Vector2.ZERO,battle.field_size).has_point(waypoint):
				response.failure_reason = "POSITION_UNREACHABLE"
				command_resolved.emit(response)
				return response
		if not route.is_empty() and kind == "ADVANCE": target_id = points.point_at(group[0].team,route[-1])
		if target_id >= 0 and orders.has(target_id):
			if orders[target_id].team != group[0].team:
				response.failure_reason = "INVALID_DEFEND_LOCATION"
			else:
				var reinforcement: Dictionary = fronts.plan(group,center,route,target_id,facing)
				if reinforcement.success: return apply_validated(group,"DEFEND",reinforcement,route,target_id)
				response.failure_reason = reinforcement.failure_reason
		elif kind == "ADVANCE": return apply_validated(group,kind,{},route)
		elif kind == "DEFEND":
			var plan: Dictionary = fronts.plan(group,center,route,-1,facing)
			if plan.success: return apply_validated(group,kind,plan,route)
			response = plan
			response.team = group[0].team
		else: response.failure_reason = "UNRECOGNIZED_GESTURE"
	command_resolved.emit(response)
	return response

func tick(delta: float = 1.0/60.0) -> void:
	simulation_time += delta
	prune()
	for squad in squads.values():
		squad.refresh_travel()
		squad.combat_candidates.clear()
		var reach: float = battle.tuning.cohesion_leash
		for member in squad.living_members(): reach = maxf(reach,member.attack_range)
		for enemy in battle.formation_manager.near_units(squad.combat_center,reach):
			if enemy.team_id != squad.team: squad.combat_candidates.append(enemy)
		squad.combat_target = null
		for member in squad.living_members():
			if is_instance_valid(member.target) and member.target.is_alive() and member.is_attacking:
				squad.combat_target = member.target
				break
		squad.breakthrough_remaining = maxf(0,squad.breakthrough_remaining-delta)
	fronts.tick(delta)
	points.update(delta)
	for id in orders.keys():
		var order: Dictionary = orders[id]
		_refresh_enemies(order)
		var contested := false
		for neighbor in order.neighbors:
			if orders.has(neighbor) and orders[neighbor].team != order.team: contested = true
		if order.dirty and order.enemies.is_empty() and not contested: _repack(id)

func record_damage(attacker: Unit, defender: Unit) -> void:
	if attacker.squad == null or defender.squad == null or not orders.has(defender.squad.order_id): return
	orders[defender.squad.order_id].contributors[attacker.squad.squad_id] = simulation_time

func award_breakthrough(squad: BattleSquad, broken_point_id: int = -1) -> void:
	var was_buffed := squad.breakthrough_remaining > 0
	var heal_budget := 0.0
	var unused := 0.0
	for unit in squad.living_members():
		var heal: float = unit.total_health*battle.tuning.breakthrough_heal_fraction
		var actual := minf(heal,unit.total_health-unit.current_health)
		unit.current_health += actual
		battle.telemetry.add(unit,"healing_received",actual)
		unit.update_health_bar()
		heal_budget += heal
		unused += heal-actual
	var duration: float = battle.tuning.breakthrough_duration*(1.0+unused/maxf(0.001,heal_budget))
	var cap: float = battle.tuning.breakthrough_duration*battle.tuning.breakthrough_duration_cap
	squad.breakthrough_remaining = minf(cap,maxf(squad.breakthrough_remaining,duration))
	battle.telemetry.event("BREAKTHROUGH_REFRESHED" if was_buffed else "BREAKTHROUGH_GRANTED",{"defensive_point_broken":broken_point_id,"eligible_squad_id":squad.squad_id,"living_members_buffed":squad.living_members().size(),"heal_budget":heal_budget,"actual_healing":heal_budget-unused,"unused_healing":unused,"base_duration":battle.tuning.breakthrough_duration,"bonus_duration_from_unused_heal":duration-battle.tuning.breakthrough_duration,"final_duration":squad.breakthrough_remaining,"damage_bonus":battle.tuning.breakthrough_damage_multiplier-1.0,"fire_rate_bonus":0.0})

func break_point(id: int, combat: bool = true, break_cause: String = "SCRIPTED") -> void:
	if not orders.has(id): return
	var point: Dictionary = orders[id]
	if battle.telemetry != null: battle.telemetry.point_broken(id,combat,break_cause)
	if combat:
		for squad_id in point.contributors:
			if squads.has(squad_id) and simulation_time-point.contributors[squad_id] <= battle.tuning.breakthrough_contribution_window: award_breakthrough(squads[squad_id],id)
	for squad_id in point.squads:
		if not squads.has(squad_id): continue
		var squad: BattleSquad = squads[squad_id]
		squad.intent = "ADVANCE"
		squad.order_id = -1
		squad.route_waypoints.clear()
		squad.defense_positions.clear()
		squad.defense_radius = 0
		squad.retreating = combat and not squad.living_members().is_empty()
		if squad.retreating: battle.telemetry.rout_started(squad,id)
		for unit in squad.living_members():
			unit.reset_steering()
			unit.defense_established = false
			unit.target = null
			unit.state = Unit.State.RETREATING if squad.retreating else Unit.State.ADVANCING
	orders.erase(id)
	points.clock = 0

func inside_defense(squad: BattleSquad, position: Vector2) -> bool:
	return orders.has(squad.order_id) and points.contains(orders[squad.order_id],position)

func intercepted_enemy(unit: Unit, destination: Vector2) -> Unit:
	var heading := unit.global_position.direction_to(destination)
	for sample in [unit.global_position,unit.global_position+heading*points.cell_size()]:
		var id: int = points.owners.get(points.cell_at(sample),-1)
		if not orders.has(id) or orders[id].team == unit.team_id or orders[id].lifecycle != "ACTIVE": continue
		var closest: Unit = null
		var distance := INF
		for squad_id in orders[id].squads:
			if not squads.has(squad_id): continue
			for defender in squads[squad_id].living_members():
				if not defender.defense_established: continue
				var candidate: float = defender.position.distance_squared_to(unit.position)
				if candidate < distance:
					distance = candidate
					closest = defender
		if closest != null: return closest
	return null

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
	for unit in battle.units:
		if unit.team_id != order.team and unit.is_alive() and points.contains(order,unit.global_position): order.enemies.append(unit)
	order.enemy_cache_valid = true

func defense_enemies(squad: BattleSquad) -> Array:
	if not orders.has(squad.order_id): return []
	var order: Dictionary = orders[squad.order_id]
	if not order.enemy_cache_valid: _refresh_enemies(order)
	return order.enemies
