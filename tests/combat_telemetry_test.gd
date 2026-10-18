extends SceneTree
var checks := 0
var failed := false
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error("FAILED: "+label)

func spawn(game: Node, team: int, kind: String, position: Vector2) -> Unit:
	var spec: Dictionary = game.card_catalog[kind].base_stats()
	spec.merge({"team":team,"lane":1,"unit_type":kind,"spawn_positions":[position],"quantity":1,"source_cards":[game.card_catalog[kind]]},true)
	game.spawn_deployment(spec)
	var unit: Unit = spec.squad.members[0]
	unit.set_physics_process(false)
	return unit

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	game.tuning = game.tuning.duplicate()
	game.tuning.enemy_enabled = false
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	game.set_process(false)
	var logger = game.telemetry
	check(logger.data.economy["2"].cards_drawn == game.hand.cards.size(),"Opening hand draws counted")
	check(logger.data.economy["1"].cards_drawn == null,"AI deck is explicitly not applicable")
	for card in game.card_catalog.values():
		var category: String = "units" if card.card_type == BattleCard.Type.UNIT else "modifiers"
		check(logger.data.stat_snapshot[category][card.card_id].card_cost == card.command_cost,"Snapshot actual card cost")
		if card.card_type == BattleCard.Type.UNIT:
			check(logger.data.stat_snapshot.units[card.card_id].health == card.health,"Snapshot actual HP")
		else:
			check(logger.data.stat_snapshot.modifiers[card.card_id].effects.multiplicative == card.multiplicative,"Snapshot modifier effects")
	var attacker := spawn(game,2,"assault_squad",Vector2(2200,3000))
	var victim := spawn(game,1,"rifle_squad",Vector2(2200,3200))
	check(attacker.telemetry_id != victim.telemetry_id,"Stable unique soldier IDs")
	var victim_id := victim.telemetry_id
	var attacker_id := attacker.telemetry_id
	var victim_hp := victim.current_health
	victim.apply_damage(20,attacker,"test")
	check(victim.current_health == victim_hp-20,"Telemetry preserves damage behavior")
	victim.apply_damage(victim_hp+30,attacker,"test")
	check(logger.soldiers[attacker_id].record.damage_dealt == victim_hp,"Applied damage excludes overkill")
	check(logger.soldiers[attacker_id].record.overkill_damage == 50,"Exact overkill")
	check(logger.soldiers[victim_id].record.damage_received == victim_hp,"Damage received reconciles")
	check(logger.soldiers[attacker_id].record.kills == 1 and logger.soldiers[victim_id].record.deaths == 1,"Kill and death counted once")
	var kills: Array = logger.data.events.filter(func(entry): return entry.type == "UNIT_KILLED")
	check(kills.size() == 1 and kills[0].killer_unit_type == "assault_squad" and kills[0].victim_unit_type == "rifle_squad","Kill provenance")
	attacker.position += Vector2(30,40)
	logger.observe_unit(attacker,0.5)
	check(logger.soldiers[attacker_id].record.distance_travelled == 50,"Measured actual displacement")
	check(logger.soldiers[attacker_id].record.time_with_no_target_in_range == 0.5,"No target uptime")
	var target := spawn(game,1,"conscript_wave",Vector2(2300,3100))
	attacker.target = target
	attacker.is_attacking = true
	attacker.attack_remaining = 0.2
	logger.observe_unit(attacker,0.25)
	check(logger.soldiers[attacker_id].record.time_actively_attacking == 0.25,"Active attacking measured")
	attacker.is_attacking = false
	game.squad_commands.issue_group([attacker.squad],"ADVANCE",Vector2.ZERO,0,PackedVector2Array([Vector2(2500,2600)]))
	check(logger.data.orders.size() == 1,"Movement order record")
	logger.tick(1.0)
	logger.tick(1.0)
	logger.tick(1.0)
	check(logger.data.orders[0].stuck_time > 0,"Tunable stuck detection")
	attacker.position += Vector2(100,0)
	logger.tick(1.0)
	check(not logger.data.orders[0].stuck,"Stuck ends when movement resumes")
	attacker.squad.route_indices[attacker.squad_member_index] = 1
	logger.tick(1.0)
	check(logger.data.orders[0].destination_reached,"Arrival closes path record")
	game.squad_commands.issue_group([attacker.squad],"ADVANCE",Vector2.ZERO,0,PackedVector2Array([Vector2(2600,2500)]))
	game.squad_commands.issue_group([attacker.squad],"ADVANCE",Vector2.ZERO,0,PackedVector2Array([Vector2(2700,2500)]))
	check(logger.data.orders[1].end_reason == "superseded","Superseded route closes")
	var defense: Dictionary = game.squad_commands.issue_group([attacker.squad],"DEFEND",Vector2(2200,3200))
	check(defense.success and logger.point_records.has(defense.defensive_point_id),"Point creation recorded immediately")
	var point_id: int = defense.defensive_point_id
	game.squad_commands.award_breakthrough(attacker.squad,point_id)
	var first_buff: float = attacker.squad.breakthrough_remaining
	game.squad_commands.award_breakthrough(attacker.squad,point_id)
	check(attacker.squad.breakthrough_remaining == first_buff,"Breakthrough refresh preserves magnitude")
	var buffs: Array = logger.data.events.filter(func(entry): return entry.type.begins_with("BREAKTHROUGH_"))
	check(buffs.size() == 2 and buffs[1].type == "BREAKTHROUGH_REFRESHED","Refresh identified separately")
	check(buffs[0].heal_budget == buffs[0].actual_healing+buffs[0].unused_healing,"Healing budget reconciles")
	check(buffs[0].defensive_point_broken == point_id,"Breakthrough origin linked")
	game.squad_commands.break_point(point_id,true)
	check(logger.point_records[point_id].was_broken,"Point break recorded")
	check(logger.data.routs.size() == 1 and logger.data.routs[0].rout_origin_point_id == point_id,"Rout origin linked")
	logger.rout_ended(attacker.squad)
	check(logger.data.routs[0].soldiers_reaching_deployment == 1,"Rout recovery recorded")
	attacker.squad.retreating = false
	game.economies[2].current_command = game.economies[2].maximum_command
	var package: Array = [game.card_catalog.rifle_squad,game.card_catalog.conscript_wave,game.card_catalog.forced_march]
	var deployed: Dictionary = game.deployment_manager.request_squad(2,package,game.preset_footprint(2,0),"ADVANCE")
	check(deployed.is_valid,"Mixed package accepted")
	var mixed: Dictionary = logger.squad_records[deployed.resolved_deployment.squad.squad_id]
	check(mixed.unit_card_order == ["rifle_squad","conscript_wave"] and mixed.modifier_cards == ["forced_march"],"Ordered components and modifiers preserved")
	check(mixed.command_cost == deployed.total_cost,"Mixed package full cost")
	check(mixed.initial_composition.rifle_squad == game.card_catalog.rifle_squad.quantity,"Mixed resolved quantity")
	check(logger.data.economy["2"].cards_played == 3,"Committed cards count")
	var spend_before: float = logger.data.economy["2"].command_spent
	game.economies[2].current_command = game.economies[2].maximum_command-0.5
	var rate: float = game.economies[2].command_regeneration_rate
	game.economies[2].tick(2.0)
	check(is_equal_approx(logger.data.economy["2"].command_wasted_at_cap,maxf(0,rate*2.0-0.5)),"Partial cap overflow measured exactly")
	game.economies[2].spend(2)
	check(logger.data.economy["2"].command_spent == spend_before+2,"Successful spend counted")
	game.economies[2].spend(999)
	check(logger.data.economy["2"].command_spent == spend_before+2,"Failed spend not counted")
	game.scores[2] = 7
	var duration: float = logger.clock
	game.finish_battle(2,"telemetry fixture")
	check(logger.closed and not logger.export_path.is_empty(),"Completed match autoexports")
	var path: String = logger.export_path
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(parsed != null and parsed.schema_version == "0.2","JSON roundtrip")
	check(parsed.match.final_score_player == 7 and parsed.match.winner == 2,"Final scores and winner")
	check(is_equal_approx(parsed.match.duration_seconds,duration),"Simulation duration")
	check(logger.save() and logger.export_path == path,"Repeated save creates no duplicate")
	var last := -1.0
	for entry in parsed.events:
		check(entry.timestamp >= last,"Monotonic simulation event timestamps")
		last = entry.timestamp
	var damage_dealt := 0.0
	var damage_received := 0.0
	for record in parsed.unit_type_aggregates.values():
		damage_dealt += record.damage_dealt
		damage_received += record.damage_received
	check(damage_dealt == damage_received,"Aggregate damage reconciles across teams")
	check(parsed.target_pairs["2:assault_squad->rifle_squad"].damage_dealt == victim_hp,"Target pair matrix")
	print("Telemetry test log: "+ProjectSettings.globalize_path(path))
	print("COMBAT TELEMETRY: %d assertions, %s" % [checks,"FAILED" if failed else "PASSED"])
	quit(1 if failed else 0)
