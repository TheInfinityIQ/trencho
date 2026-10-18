extends SceneTree
var game: Node
var checks := 0
var failed := false
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error("FAILED: " + label)
func spawn(team: int, points: Array) -> BattleSquad:
	var spec: Dictionary = game.card_catalog.conscript_wave.base_stats()
	spec.merge({"team":team,"unit_type":"conscript_wave","lane":1,"spawn_positions":points},true)
	game.spawn_deployment(spec)
	return spec.squad
func settle(label: String) -> void:
	var arrived := false
	for tick in range(3600):
		await physics_frame
		arrived = game.units.all(func(unit): return unit.state == Unit.State.DEFENDING)
		if arrived: break
	var remaining: Array = game.units.filter(func(unit): return unit.state != Unit.State.DEFENDING)
	print(label," remaining=",remaining.size())
	for unit in remaining.slice(0,4): print("STUCK ",unit.position," home ",unit.squad.defense_positions.get(unit.squad_member_index))
	check(arrived,label)
func run() -> void:
	game = load("res://main.tscn").instantiate()
	game.tuning = game.tuning.duplicate()
	game.tuning.enemy_enabled = false
	game.tuning.move_speed_variance = 0
	root.add_child(game)
	current_scene = game
	# Enemy orders must not become arrows from the player's last gesture.
	var friendly := spawn(2,[Vector2(3000,5500)])
	game.squad_commands.select_unit(friendly.members[0])
	var ui = game.command_ui
	ui.feedback.clear()
	ui.failure_reason = "PLAYER_NOTICE"
	game.hand.message = "PLAYER_MESSAGE"
	ui.gesture_origin = Vector2(3000,5500)
	ui.stroke = PackedVector2Array([Vector2(300,400),Vector2(350,350)])
	var enemy := spawn(1,[Vector2(3000,1000)])
	var result: Dictionary = game.squad_commands.issue_group([enemy],"DEFEND",Vector2(3000,2000))
	check(result.success,"enemy defense accepted")
	check(ui.feedback.is_empty(),"enemy order creates no player command feedback even during a player gesture")
	check(ui.failure_reason == "PLAYER_NOTICE" and game.hand.message == "PLAYER_MESSAGE","enemy success preserves player failure and hand message")
	result = game.squad_commands.issue_group([enemy],"DEFEND",Vector2(-1,-1))
	check(not result.success and result.team == 1 and ui.feedback.is_empty(),"enemy rejection also creates no player feedback")
	check(ui.failure_reason == "PLAYER_NOTICE","enemy rejection preserves player failure notice")
	check(friendly.intent == "ADVANCE" and game.squad_commands.selected_ids == [friendly.squad_id],"enemy orders preserve player intent and selection")
	result = game.squad_commands.issue_selected("DEFEND",Vector2(3200,4500))
	check(result.success and ui.feedback.size() == 1,"friendly defense still produces feedback")
	result = game.squad_commands.issue_selected("DEFEND",Vector2(-1,-1))
	check(not result.success and ui.feedback.size() == 2 and ui.failure_reason == result.failure_reason,"friendly rejection still produces error feedback")
	check(friendly.intent == "DEFEND" and game.squad_commands.selected_ids == [friendly.squad_id],"enemy order preserves player selection")

	ui.stroke.clear()
	game.formation_manager.clear()
	for unit in game.units.duplicate(): unit.die()
	await physics_frame
	for team in [2,1]:
		for group in range(12):
			var points: Array = []
			for index in range(12):
				points.append(Vector2(2300+index*160, (4400+group*160) if team == 2 else (2000-group*160)))
			var squad := spawn(team,points)
			if team == 2: game.squad_commands.select_unit(squad.members[0],true)
		var group: Array = game.squad_commands.squads.values().filter(func(squad): return squad.team == team)
		result = game.squad_commands.issue_group(group,"DEFEND",Vector2(3200,3500))
		check(result.success,"dense defense accepted team %d" % team)
		await settle("144 dense defenders arrive team %d" % team)
		var previous_id: int = group[0].order_id
		result = game.squad_commands.issue_group(group,"DEFEND",Vector2(3200,3500))
		check(result.success and not game.squad_commands.orders.has(previous_id),"same-center replacement releases vacated point team %d" % team)
		check(game.units.all(func(unit): return unit.squad.defense_positions.has(unit.squad_member_index)),"same-center replacement gives every soldier a home team %d" % team)
		await settle("144 defenders re-establish at the same center team %d" % team)
		previous_id = group[0].order_id
		result = game.squad_commands.issue_group(group,"DEFEND",Vector2(4400,3500))
		check(result.success,"lateral redirect accepted team %d" % team)
		check(not game.squad_commands.orders.has(previous_id),"lateral replacement releases vacated point team %d" % team)
		var clear_homes := true
		var homes: Array = []
		for unit in game.units:
			var home: Vector2 = unit.squad.defense_positions[unit.squad_member_index]
			for other in homes:
				if home.distance_to(other) < game.tuning.defense_spacing-0.01: clear_homes = false
			homes.append(home)
		check(clear_homes,"relocation preserves traversable spacing team %d" % team)
		await settle("144 defenders arrive after lateral redirect team %d" % team)
		game.formation_manager.clear()
		for unit in game.units.duplicate(): unit.die()
		await physics_frame
	print("DEFENSE REGRESSION: %d assertions, %s" % [checks,"FAILED" if failed else "PASSED"])
	quit(1 if failed else 0)
