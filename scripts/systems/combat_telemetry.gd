extends RefCounted
## Development instrument. Counters use simulation seconds; no gameplay RNG or searches.
var battle: Node
var enabled := true
var clock := 0.0
var sample_clock := 0.0
var closed := false
var export_path := ""
var export_error := ""
var started_ticks := Time.get_ticks_msec()
var data: Dictionary = {}
var soldiers: Dictionary = {}
var squad_records: Dictionary = {}
var active_paths: Dictionary = {}
var point_records: Dictionary = {}
const STATE_METRICS = {Unit.State.ADVANCING:"time_advancing",Unit.State.ENTERING_BATTLEFIELD:"time_advancing",Unit.State.CAPTURING:"time_advancing",Unit.State.DEFENDING:"time_defending",Unit.State.MOVING_TO_DEFEND:"time_moving_to_defend",Unit.State.RETURNING_TO_DEFENSE:"time_moving_to_defend",Unit.State.ENGAGING:"time_engaging",Unit.State.RETREATING:"time_retreating"}
var next_unit := 1
var next_order := 1
var routs: Dictionary = {}
var doctrine_summary: Dictionary = {}

func _init(owner_battle: Node) -> void:
	battle = owner_battle
	enabled = battle.tuning.telemetry_enabled
	var stamp := Time.get_datetime_string_from_system(true)
	data = {"schema_version":"0.1", "match":{
		"match_id":"%s_%s" % [stamp.replace(":", ""), Time.get_ticks_usec()],
		"build_version":ProjectSettings.get_setting("application/config/version", "development"),
		"timestamp_start":stamp, "timestamp_end":null, "duration_seconds":0.0,
		"random_seed":battle.tuning.random_seed, "map_id":battle.scene_file_path,
		"debug_build":OS.is_debug_build(), "platform":OS.get_name()},
		"stat_snapshot":{"units":{}, "modifiers":{}, "tuning":{}},
		"economy":{}, "squads":[], "unit_type_aggregates":{}, "target_pairs":{},
		"defensive_points":[], "orders":[], "soldiers":[], "cards":{}, "routs":[],
		"ai":{"decisions":[], "doctrine":battle.enemy_controller.doctrine,
			"deployment_delay":maxf(1.0,battle.tuning.enemy_decision_interval)},
		"events":[], "summary":{}, "measurement_notes":[
			"Time totals are soldier-seconds, summed across members; simulation time includes planning slowdown.",
			"Active attacking means an in-range engagement, including cooldown; attacks are instantaneous guaranteed hits.",
			"No-target-in-range includes travel and idle defense; it does not prove an enemy exists out of range.",
			"Stuck is a tunable centroid heuristic, excluding active combat, retreat and settled defense.",
			"Mixed package unit costs follow their card; modifier cost is apportioned by resolved quantity.",
			"AI draws no cards; its draw count is null. Repath count is zero: movement uses local steering, not a pathfinder."]}
	for property in battle.tuning.get_property_list():
		if property.usage & PROPERTY_USAGE_STORAGE and property.name not in ["script", "resource_path", "resource_name", "resource_local_to_scene"]:
			data.stat_snapshot.tuning[property.name] = plain(battle.tuning.get(property.name))
	for card in battle.card_catalog.values():
		var definition := {"display_name":card.display_name, "card_cost":card.command_cost, "special_flags":Array(card.tags)}
		if card.card_type == BattleCard.Type.UNIT:
			definition.merge(card.base_stats())
			definition.unit_id = card.card_id
			definition.base_quantity = card.quantity
			definition.projectile_speed = null
			data.stat_snapshot.units[card.card_id] = definition
		else:
			definition.modifier_id = card.card_id
			definition.effects = {"additive":card.additive.duplicate(true), "multiplicative":card.multiplicative.duplicate(true), "overrides":card.overrides.duplicate(true)}
			data.stat_snapshot.modifiers[card.card_id] = definition
	for team in [1,2]:
		var economy = battle.economies[team]
		data.economy[str(team)] = {"initial_command":economy.current_command, "max_command":economy.maximum_command,
			"command_generated":0.0, "command_spent":0.0, "command_wasted_at_cap":0.0,
			"command_lost_to_cap":0.0, "time_at_command_cap":0.0, "cards_drawn":0 if team == 2 else null,
			"cards_played":0,"unit_cards_played":0,"modifier_cards_played":0,"deployment_packages_created":0}
		# Install before hand startup so opening draws are included.
		economy.telemetry = self
		economy.telemetry_team = team
	for key in ["left","center","right"]:
		doctrine_summary[key] = {"time_first_point_established":null,"peak_defenders":0,"time_below_target":0.0}
	data.ai.defensive_doctrine = doctrine_summary

func plain(value):
	if value is Vector2 or value is Vector2i: return [value.x,value.y]
	if value is Dictionary:
		var result := {}
		for key in value:
			if value[key] is Object: continue
			result[str(key)] = plain(value[key])
		return result
	if value is Array or value is PackedVector2Array:
		var result := []
		for item in value: result.append(plain(item))
		return result
	return value

func event(kind: String, fields: Dictionary = {}) -> void:
	if not enabled or closed: return
	var entry := {"timestamp":clock, "type":kind}
	entry.merge(plain(fields))
	data.events.append(entry)
	if kind == "AI_DEPLOYMENT_DECISION": data.ai.decisions.append(entry)
	if kind == "DEFENSIVE_POINT_JOINED" and point_records.has(fields.point_id): point_records[fields.point_id].reinforcement_count += 1

func totals() -> Dictionary:
	return {"soldiers_deployed":0,"soldiers_killed":0,"soldiers_survived":0,"damage_dealt":0.0,
		"damage_received":0.0,"healing_received":0.0,"kills":0,"deaths":0,"attack_attempts":0,"hits":0,
		"overkill_damage":0.0,"time_alive":0.0,"time_actively_attacking":0.0,
		"time_with_valid_target":0.0,"time_with_no_target_in_range":0.0,"time_waiting_for_attack_cooldown":0.0,
		"time_closing_to_range":0.0,"distance_moved_during_engagement":0.0,
		"distance_travelled":0.0,"time_stuck":0.0,"score_contribution":0,"command_cost_attributed":0.0,
		"time_advancing":0.0,"time_defending":0.0,"time_moving_to_defend":0.0,"time_engaging":0.0,"time_retreating":0.0}

func squad_created(spec: Dictionary) -> void:
	if not enabled: return
	var squad: BattleSquad = spec.squad
	var record := totals()
	record.merge({"squad_id":squad.squad_id,"team":squad.team,"spawn_time":clock,"end_time":null,"end_reason":null,
		"cards_used":[],"modifier_cards":[],"command_cost":0.0,"initial_composition":{},"final_composition":{},
		"final_effective_stats":plain(spec.get("components",[spec])),"components":{},"samples":[],"unit_card_order":[]})
	for card in squad.source_cards:
		record.command_cost += card.command_cost
		record.cards_used.append(card.card_id)
		if card.card_type == BattleCard.Type.MODIFIER: record.modifier_cards.append(card.card_id)
		else: record.unit_card_order.append(card.card_id)
	for component in spec.get("components",[spec]):
		var kind: String = component.unit_type
		record.initial_composition[kind] = record.initial_composition.get(kind,0)+int(component.quantity)
	record.front_priority_unit = record.unit_card_order.front() if not record.unit_card_order.is_empty() else squad.unit_type
	record.rear_priority_unit = record.unit_card_order.back() if not record.unit_card_order.is_empty() else squad.unit_type
	record.formation_width = spec.requested_rectangle.size.x if spec.has("requested_rectangle") else null
	record.formation_depth = spec.requested_rectangle.size.y if spec.has("requested_rectangle") else null
	var origin := Vector2.ZERO
	var positions: Array = spec.get("spawn_positions",[])
	for position in positions: origin += position
	if not positions.is_empty(): origin /= positions.size()
	record.deployment_origin = plain(origin)
	squad_records[squad.squad_id] = record
	data.squads.append(record)
	event("SQUAD_SPAWNED", {"squad_id":squad.squad_id,"team":squad.team})

func committed(team: int, spec: Dictionary) -> void:
	if not enabled: return
	var record: Dictionary = squad_records[spec.squad.squad_id]
	var economy: Dictionary = data.economy[str(team)]
	economy.deployment_packages_created += 1
	for card in spec.source_cards:
		economy.cards_played += 1
		var key := "unit_cards_played" if card.card_type == BattleCard.Type.UNIT else "modifier_cards_played"
		economy[key] += 1
		var card_key := "%d:%s" % [team,card.card_id]
		if not data.cards.has(card_key): data.cards[card_key] = {"team":team,"card_id":card.card_id,"times_played":0,"command_spent":0.0}
		data.cards[card_key].times_played += 1
		data.cards[card_key].command_spent += card.command_cost
	event("PACKAGE_COMMITTED", {"squad_id":spec.squad.squad_id,"team":team,"cards":record.cards_used,"command_cost":record.command_cost})

func spawned(unit: Unit) -> void:
	if not enabled or unit.squad == null: return
	unit.telemetry_id = next_unit
	next_unit += 1
	var record := totals()
	record.merge({"unit_id":unit.telemetry_id,"squad_id":unit.squad.squad_id,"team":unit.team_id,"unit_type":unit.unit_type,
		"spawn_time":clock,"end_time":null,"end_reason":null,"spawned_stats":{"hp":unit.total_health,"damage":unit.attack_ranged_strength,
			"attack_interval":unit.attack_interval,"move_speed":unit.move_speed,"range":unit.attack_range}})
	var squad: Dictionary = squad_records[unit.squad.squad_id]
	if not squad.components.has(unit.unit_type): squad.components[unit.unit_type] = totals()
	var type_key := "%d:%s" % [unit.team_id,unit.unit_type]
	if not data.unit_type_aggregates.has(type_key):
		data.unit_type_aggregates[type_key] = totals()
		data.unit_type_aggregates[type_key].merge({"team":unit.team_id,"unit_type":unit.unit_type})
	soldiers[unit.telemetry_id] = {"record":record,"last_position":unit.position,"last_state":-1,"last_target":0,
		"targets":[record,squad,squad.components[unit.unit_type],data.unit_type_aggregates[type_key]]}
	data.soldiers.append(record)
	add(unit,"soldiers_deployed",1)
	var quantity: int = squad.initial_composition.get(unit.unit_type,1)
	var total_quantity := 0
	for count in squad.initial_composition.values(): total_quantity += count
	var cost := 0.0
	for card in unit.squad.source_cards:
		if card.card_type == BattleCard.Type.MODIFIER: cost += card.command_cost/maxi(1,total_quantity)
		elif card.card_id == unit.unit_type: cost += card.command_cost/maxi(1,quantity)
	add(unit,"command_cost_attributed",cost)
	event("UNIT_SPAWNED",identity(unit))

func identity(unit: Unit, prefix: String = "") -> Dictionary:
	return {prefix+"unit_id":unit.telemetry_id,prefix+"squad_id":unit.squad.squad_id if unit.squad != null else null,
		prefix+"unit_type":unit.unit_type,prefix+"intent":unit.squad.intent if unit.squad != null else null,
		prefix+"defensive_point_id":unit.squad.order_id if unit.squad != null and unit.squad.intent == "DEFEND" else null}

func add(unit: Unit, key: String, amount: float) -> void:
	if not enabled or not soldiers.has(unit.telemetry_id): return
	for target in soldiers[unit.telemetry_id].targets:
		target[key] = target.get(key,0.0)+amount

func observe_unit(unit: Unit, delta: float) -> void:
	if not enabled or closed or not soldiers.has(unit.telemetry_id): return
	var tracking: Dictionary = soldiers[unit.telemetry_id]
	var distance: float = unit.position.distance_to(tracking.last_position)
	tracking.last_position = unit.position
	add(unit,"time_alive",delta)
	add(unit,"distance_travelled",distance)
	if unit.squad != null and routs.has(unit.squad.squad_id): routs[unit.squad.squad_id].distance_retreating += distance
	var in_range: bool = unit.is_attacking and is_instance_valid(unit.target)
	add(unit,"time_actively_attacking" if in_range else "time_with_no_target_in_range",delta)
	if is_instance_valid(unit.target) and unit.target.is_alive():
		add(unit,"time_with_valid_target",delta)
		if in_range:
			if unit.attack_remaining > 0: add(unit,"time_waiting_for_attack_cooldown",delta)
		else:
			add(unit,"time_closing_to_range",delta)
		add(unit,"distance_moved_during_engagement",distance)
	var state_key: String = STATE_METRICS.get(unit.state,"")
	if not state_key.is_empty(): add(unit,state_key,delta)
	if tracking.last_state != unit.state:
		event("STATE_CHANGED",{"unit_id":unit.telemetry_id,"state":Unit.State.keys()[unit.state]})
		tracking.last_state = unit.state
	var target_id: int = unit.target.telemetry_id if is_instance_valid(unit.target) and unit.target.is_alive() else 0
	if target_id != tracking.last_target:
		if tracking.last_target != 0: event("TARGET_LOST",{"unit_id":unit.telemetry_id,"target_unit_id":tracking.last_target})
		if target_id != 0: event("TARGET_ACQUIRED",{"unit_id":unit.telemetry_id,"target_unit_id":target_id})
		tracking.last_target = target_id
	if active_paths.has(unit.squad.squad_id): active_paths[unit.squad.squad_id].soldier_distance_travelled += distance

func damage(attacker: Unit, victim: Unit, attempted: float, before: float, after: float, source: String) -> void:
	if not enabled or closed: return
	var applied := before-after
	add(victim,"damage_received",applied)
	if victim.squad != null and routs.has(victim.squad.squad_id):
		routs[victim.squad.squad_id].damage_received_while_routing += applied
		if after <= 0: routs[victim.squad.squad_id].soldiers_killed_while_routing += 1
	point_combat(victim,"damage_received_by_assigned_squads",applied)
	if after <= 0: point_combat(victim,"friendly_deaths",1)
	var fields := identity(victim,"target_")
	fields.merge({"damage_attempted":attempted,"damage_applied":applied,"overkill_damage":maxf(0,attempted-applied),"target_hp_before":before,"target_hp_after":after,"damage_source":source})
	if is_instance_valid(attacker):
		fields.merge(identity(attacker,"attacker_"))
		add(attacker,"damage_dealt",applied)
		add(attacker,"overkill_damage",maxf(0,attempted-applied))
		add(attacker,"attack_attempts",1)
		add(attacker,"hits",1)
		point_combat(attacker,"damage_dealt_by_assigned_squads",applied)
		if attacker.squad != null and attacker.squad.breakthrough_remaining > 0:
			add(attacker,"damage_dealt_while_buffed",applied)
			if after <= 0: add(attacker,"kills_while_buffed",1)
		var pair := "%d:%s->%s" % [attacker.team_id,attacker.unit_type,victim.unit_type]
		if not data.target_pairs.has(pair): data.target_pairs[pair] = {"damage_dealt":0.0,"kills":0,"attack_count":0,"hit_count":0}
		data.target_pairs[pair].damage_dealt += applied
		data.target_pairs[pair].attack_count += 1
		data.target_pairs[pair].hit_count += 1
		if after <= 0:
			add(attacker,"kills",1)
			point_combat(attacker,"enemy_kills",1)
			data.target_pairs[pair].kills += 1
		event("ATTACK_FIRED",fields)
	event("DAMAGE_DEALT",fields)
	if after <= 0:
		var kill := identity(victim,"victim_")
		kill.merge(identity(attacker,"killer_") if is_instance_valid(attacker) else {"killer_unit_id":null,"killer_squad_id":null,"killer_unit_type":null})
		kill.damage_source = source
		kill.victim_state = Unit.State.keys()[victim.state]
		event("UNIT_KILLED",kill)

func removed(unit: Unit, killed: bool) -> void:
	if not enabled or not soldiers.has(unit.telemetry_id): return
	var record: Dictionary = soldiers[unit.telemetry_id].record
	if record.end_time != null: return
	if killed:
		add(unit,"deaths",1)
		add(unit,"soldiers_killed",1)
		event("UNIT_DIED",identity(unit))
	else:
		add(unit,"score_contribution",unit.score_value)
		add(unit,"soldiers_survived",1)
	record.end_time = clock
	record.end_reason = "killed" if killed else "scored"
	if not killed:
		var fields := identity(unit,"source_")
		fields.merge({"team":unit.team_id,"score_delta":unit.score_value})
		event("SCORE_EVENT",fields)

func squad_ended(id: int) -> void:
	if not enabled or not squad_records.has(id): return
	var record: Dictionary = squad_records[id]
	if record.end_time != null: return
	record.end_time = clock
	record.end_reason = "destroyed" if record.deaths >= record.soldiers_deployed and record.soldiers_deployed > 0 else "departed"
	close_path(id,record.end_reason)
	event("SQUAD_DESTROYED" if record.end_reason == "destroyed" else "SQUAD_ENDED",{"squad_id":id})
	if routs.has(id):
		routs[id].rout_end_time = clock
		routs[id].end_reason = record.end_reason
		routs.erase(id)

func rout_started(squad: BattleSquad, point_id: int) -> void:
	if not enabled: return
	var record := {"squad_id":squad.squad_id,"rout_start_time":clock,"rout_end_time":null,"rout_origin_point_id":point_id,
		"soldiers_at_rout_start":squad.living_members().size(),"soldiers_reaching_deployment":0,
		"soldiers_killed_while_routing":0,"damage_received_while_routing":0.0,"distance_retreating":0.0}
	routs[squad.squad_id] = record
	data.routs.append(record)
	event("ROUT_STARTED",record)

func rout_ended(squad: BattleSquad) -> void:
	if not enabled or not routs.has(squad.squad_id): return
	var record: Dictionary = routs[squad.squad_id]
	record.rout_end_time = clock
	record.soldiers_reaching_deployment = squad.living_members().size()
	record.end_reason = "recovered"
	event("ROUT_ENDED",record)
	routs.erase(squad.squad_id)

func point_combat(unit: Unit, key: String, amount: float) -> void:
	if unit.squad == null or unit.squad.intent != "DEFEND": return
	var id: int = unit.squad.order_id
	if not point_records.has(id): point_changed(id)
	if point_records.has(id): point_records[id][key] += amount

func point_changed(id: int) -> void:
	if not enabled or not battle.squad_commands.orders.has(id): return
	var point: Dictionary = battle.squad_commands.orders[id]
	if not point_records.has(id):
		point_records[id] = {"point_id":id,"team":point.team,"created_time":clock,"deleted_time":null,"samples":[],
			"peak_established_soldiers":0,"established_soldier_seconds":0.0,"sampled_seconds":0.0,
			"damage_dealt_by_assigned_squads":0.0,"damage_received_by_assigned_squads":0.0,"enemy_kills":0,"friendly_deaths":0,
			"reinforcement_count":0,"times_entered_critical":0,"was_absorbed":false,"was_broken":false,"break_reason":null}
		data.defensive_points.append(point_records[id])
		event("DEFENSIVE_POINT_CREATED",{"point_id":id,"team":point.team})
	var record: Dictionary = point_records[id]
	var snapshot := {}
	for key in ["lifecycle","anchors","established","inbound","desired_area","actual_area","capacity_state","pressure","neighbors","squads"]: snapshot[key] = plain(point[key])
	if record.has("latest"):
		var old: Dictionary = record.latest
		if old.lifecycle != snapshot.lifecycle:
			event("DEFENSIVE_POINT_BECAME_PENDING" if snapshot.lifecycle == "PENDING" else "DEFENSIVE_POINT_ACTIVE",{"point_id":id})
		if old.capacity_state != snapshot.capacity_state:
			event("DEFENSIVE_POINT_CAPACITY_CHANGED",{"point_id":id,"capacity_state":snapshot.capacity_state})
			if snapshot.capacity_state == "CRITICAL": record.times_entered_critical += 1
	record.latest = snapshot
	record.peak_established_soldiers = maxi(record.peak_established_soldiers,point.established)

func point_broken(id: int, combat: bool) -> void:
	if not enabled: return
	point_changed(id)
	if point_records.has(id):
		point_records[id].was_broken = true
		point_records[id].break_reason = "combat" if combat else "capacity"
		point_records[id].deleted_time = clock
	event("DEFENSIVE_POINT_BROKEN",{"point_id":id,"combat":combat})

func point_absorbed(weak_id: int, strong_id: int) -> void:
	if not enabled: return
	point_changed(weak_id)
	point_changed(strong_id)
	point_records[weak_id].was_absorbed = true
	point_records[weak_id].deleted_time = clock
	event("DEFENSIVE_POINT_ABSORBED",{"point_id":weak_id,"absorbed_by_point_id":strong_id})

func order(squad: BattleSquad, kind: String, route: PackedVector2Array) -> void:
	if not enabled: return
	close_path(squad.squad_id,"superseded")
	var origin := squad.combat_center
	if squad.members.is_empty():
		var position: Array = squad_records[squad.squad_id].deployment_origin
		origin = Vector2(position[0],position[1])
	var length := 0.0
	var previous := origin
	for waypoint in route:
		length += previous.distance_to(waypoint)
		previous = waypoint
	if route.is_empty() and kind == "DEFEND": length = origin.distance_to(squad.defense_center)
	var record := {"order_id":next_order,"squad_id":squad.squad_id,"kind":kind,"issued_time":clock,
		"route_waypoints":plain(route),"destination":plain(previous if not route.is_empty() else squad.defense_center),
		"route_requested_length":length,"straight_line_distance":origin.distance_to(previous),"arrival_time":null,
		"destination_reached":false,"end_reason":null,"actual_distance_travelled":0.0,"soldier_distance_travelled":0.0,"repath_count":0,"stuck_time":0.0,
		"stationary_seconds":0.0,"stuck":false,"last_centroid":plain(origin)}
	next_order += 1
	data.orders.append(record)
	active_paths[squad.squad_id] = record
	event("ORDER_ISSUED",record)

func close_path(id: int, reason: String) -> void:
	if not active_paths.has(id): return
	var record: Dictionary = active_paths[id]
	if record.stuck: event("SQUAD_STUCK_ENDED",{"order_id":record.order_id,"squad_id":id,"reason":reason})
	record.end_reason = reason
	record.end_time = clock
	record.destination_reached = reason == "arrived"
	if reason == "arrived": record.arrival_time = clock
	event("DESTINATION_REACHED" if reason == "arrived" else "DESTINATION_FAILED",{"order_id":record.order_id,"squad_id":id,"reason":reason})
	active_paths.erase(id)

func tick(delta: float) -> void:
	if not enabled or closed: return
	clock += delta
	sample_clock += delta
	if sample_clock < maxf(0.1,battle.tuning.telemetry_sample_interval): return
	var interval := sample_clock
	sample_clock = 0
	for squad in battle.squad_commands.squads.values():
		if not squad_records.has(squad.squad_id): continue
		var members: Array = squad.living_members()
		if members.is_empty(): continue
		var center := Vector2.ZERO
		for unit in members: center += unit.position
		center /= members.size()
		var spread := 0.0
		var maximum := 0.0
		var fighting := false
		var arrived := true
		for unit in members:
			var distance: float = center.distance_to(unit.position)
			spread += distance
			maximum = maxf(maximum,distance)
			fighting = fighting or unit.is_attacking
			if squad.intent == "DEFEND": arrived = arrived and unit.defense_established
			else: arrived = arrived and squad.route_indices.get(unit.squad_member_index,0) >= squad.route_waypoints.size()
		squad_records[squad.squad_id].samples.append({"timestamp":clock,"centroid":plain(center),"average_member_distance_from_centroid":spread/members.size(),"max_member_distance_from_centroid":maximum,"living_member_count":members.size(),"intent":squad.intent})
		if not active_paths.has(squad.squad_id): continue
		var path: Dictionary = active_paths[squad.squad_id]
		if arrived and (squad.intent == "DEFEND" or not squad.route_waypoints.is_empty()):
			close_path(squad.squad_id,"arrived")
			continue
		var previous := Vector2(path.last_centroid[0],path.last_centroid[1])
		path.actual_distance_travelled += center.distance_to(previous)
		var stationary: bool = not fighting and not squad.retreating and center.distance_to(previous) < battle.tuning.stuck_distance_threshold
		path.stationary_seconds = path.stationary_seconds+interval if stationary else 0.0
		var stuck: bool = path.stationary_seconds >= battle.tuning.stuck_time_threshold
		if stuck != path.stuck:
			event("SQUAD_STUCK_STARTED" if stuck else "SQUAD_STUCK_ENDED",{"order_id":path.order_id,"squad_id":squad.squad_id})
		path.stuck = stuck
		if stuck:
			path.stuck_time += interval
			for unit in members: add(unit,"time_stuck",interval)
		path.last_centroid = plain(center)
	for id in battle.squad_commands.orders:
		var point: Dictionary = battle.squad_commands.orders[id]
		point_changed(id)
		point_records[id].sampled_seconds += interval
		point_records[id].established_soldier_seconds += point.established*interval
		var sample := {"timestamp":clock}
		for key in ["lifecycle","anchors","established","inbound","desired_area","actual_area","capacity_state","pressure","neighbors","squads"]: sample[key] = plain(point[key])
		point_records[id].samples.append(sample)
	for id in point_records:
		if not battle.squad_commands.orders.has(id) and point_records[id].deleted_time == null:
			point_records[id].deleted_time = clock
			event("DEFENSIVE_POINT_DELETED",{"point_id":id})
	for key in doctrine_summary:
		var count: int = battle.enemy_controller.defender_count(key)
		var summary: Dictionary = doctrine_summary[key]
		summary.peak_defenders = maxi(summary.peak_defenders,count)
		if count > 0 and summary.time_first_point_established == null: summary.time_first_point_established = clock
		var desired := 20 if key == "center" and battle.enemy_controller.doctrine == "TRIANGLE" else 10
		if count < desired: summary.time_below_target += interval

func economy_tick(team: int, generated: float, wasted: float, cap_seconds: float) -> void:
	if not enabled or closed: return
	var record: Dictionary = data.economy[str(team)]
	record.command_generated += generated
	record.command_wasted_at_cap += wasted
	record.command_lost_to_cap += wasted
	record.time_at_command_cap += cap_seconds

func finish(winner: int, reason: String) -> void:
	if not enabled or closed: return
	for id in active_paths.keys(): close_path(id,"match_ended")
	for record in squad_records.values():
		if record.end_time == null:
			record.end_time = clock
			record.end_reason = "match_ended"
		record.shots_or_attacks_attempted = record.attack_attempts
		record.shots_or_attacks_completed = record.hits
		record.misses = null
	for tracking in soldiers.values():
		var record: Dictionary = tracking.record
		if record.end_time == null:
			record.end_time = clock
			record.end_reason = "match_ended"
			record.soldiers_survived = 1
			var squad: Dictionary = squad_records[record.squad_id]
			squad.final_composition[record.unit_type] = squad.final_composition.get(record.unit_type,0)+1
			squad.soldiers_survived += 1
			squad.components[record.unit_type].soldiers_survived += 1
			data.unit_type_aggregates["%d:%s" % [record.team,record.unit_type]].soldiers_survived += 1
	data.match.merge({"timestamp_end":Time.get_datetime_string_from_system(true),"duration_seconds":clock,
		"real_duration_seconds":(Time.get_ticks_msec()-started_ticks)/1000.0,"winner":winner,"end_reason":reason,
		"final_score_player":battle.scores[2],"final_score_enemy":battle.scores[1]},true)
	for team in [2,1]:
		var summary := {"command_generated":data.economy[str(team)].command_generated,"command_spent":data.economy[str(team)].command_spent,
			"damage_dealt":0.0,"damage_received":0.0,"kills":0,"deaths":0,"score":battle.scores[team]}
		data.economy[str(team)].final_command = battle.economies[team].current_command
		for squad in squad_records.values():
			if squad.team == team:
				for key in ["damage_dealt","damage_received","kills","deaths"]: summary[key] += squad[key]
		data.summary["player" if team == 2 else "enemy"] = summary
	for point in point_records.values():
		point.lifetime = (point.deleted_time if point.deleted_time != null else clock)-point.created_time
		point.average_established_soldiers = point.established_soldier_seconds/point.sampled_seconds if point.sampled_seconds > 0 else 0.0
	for record in routs.values():
		record.rout_end_time = clock
		record.end_reason = "match_ended"
	# Modifier outcomes describe association, not a causal estimate of modifier value.
	for key in data.cards:
		var card: Dictionary = data.cards[key]
		var definition: Resource = battle.card_catalog[card.card_id]
		for metric in ["damage_dealt","damage_received","kills","deaths","score_contribution","soldiers_generated"]: card[metric] = 0.0
		for squad in squad_records.values():
			if squad.team != card.team or not squad.cards_used.has(card.card_id): continue
			var source: Dictionary = squad if definition.card_type == BattleCard.Type.MODIFIER else squad.components.get(card.card_id,{})
			for metric in ["damage_dealt","damage_received","kills","deaths","score_contribution"]: card[metric] += source.get(metric,0.0)
			card.soldiers_generated += source.get("soldiers_deployed",0)
	event("MATCH_ENDED",{"winner":winner,"reason":reason})
	closed = true
	save()

func save() -> bool:
	if not closed: return false
	if not export_path.is_empty(): return true
	var directory := "user://combat_logs"
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		export_error = "Could not create combat log folder (%s)" % error
		push_warning(export_error)
		return false
	var path: String = directory+"/trencho_match_"+data.match.match_id+".json"
	var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file == null:
		export_error = "Could not open combat log (%s)" % FileAccess.get_open_error()
		push_warning(export_error)
		return false
	file.store_string(JSON.stringify(data))
	file.flush()
	error = file.get_error()
	file.close()
	if error == OK: error = DirAccess.rename_absolute(path+".tmp",path)
	if error != OK:
		export_error = "Could not save combat log (%s)" % error
		push_warning(export_error)
		return false
	export_error = ""
	export_path = path
	return true

func summary_text() -> String:
	return "MATCH %s\nDuration %.2fs\nScore: Player %d / Enemy %d\n%s" % [data.match.match_id,clock,battle.scores[2],battle.scores[1],JSON.stringify(data.summary,"  ")]
