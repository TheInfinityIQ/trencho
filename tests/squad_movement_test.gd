extends SceneTree
var game: Node
var checks := 0
var failed := false
func _initialize() -> void: call_deferred("run")
func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error("FAILED: " + label)
func run() -> void:
	game = load("res://main.tscn").instantiate()
	game.tuning = game.tuning.duplicate()
	game.tuning.enemy_enabled = false
	game.tuning.move_speed_variance = 0
	root.add_child(game)
	current_scene = game
	for quantity in [6,24]:
		game.economies[2].current_command = 10
		var cards: Array = [game.card_catalog.rifle_squad] if quantity == 6 else [game.card_catalog.conscript_wave,game.card_catalog.commander_mojo]
		var response: Dictionary = game.deployment_manager.request_squad(2,cards,Rect2(2200,0,1900,300),"DEFEND",Vector2(3200,5000),600)
		check(response.is_valid,"moving defense order accepted")
		var arrived := 0
		for tick in range(1800):
			await physics_frame
			arrived = 0
			for unit in game.units:
				if unit.state == Unit.State.DEFENDING: arrived += 1
			if arrived == quantity: break
		if arrived != quantity:
			for unit in game.units: print("SLOT ",unit.squad_member_index," position ",unit.position," home ",unit.squad.defense_positions[unit.squad_member_index]," state ",unit.state)
		print("DEFENSE ARRIVAL %d/%d queued=%d" % [arrived,quantity,game.formation_manager.pending.size()])
		check(arrived == quantity,"all defenders reach allocated positions without manual teleportation")
		for unit in game.units:
			check(unit.global_position.distance_to(unit.squad.defense_center)+game.tuning.unit_radius <= unit.squad.defense_radius+1,"arrived body remains inside defense area")
		game.formation_manager.clear()
		for unit in game.units.duplicate(): unit.die()
		await physics_frame
		await physics_frame
		# Two independently owned squads converge on one shared area and re-form
	# through normal physics after casualties.
	game.economies[2].current_command = 10
	var rifle: Dictionary = game.deployment_manager.request_squad(2,[game.card_catalog.rifle_squad],Rect2(2000,0,940,300),"ADVANCE")
	var assault: Dictionary = game.deployment_manager.request_squad(2,[game.card_catalog.assault_squad],Rect2(3400,0,620,300),"ADVANCE")
	for tick in range(90): await physics_frame
	game.squad_commands.select_unit(rifle.resolved_deployment.squad.members[0])
	game.squad_commands.select_unit(assault.resolved_deployment.squad.members[0],true)
	var shared: Dictionary = game.squad_commands.issue_selected("DEFEND",Vector2(3200,4800),850)
	check(shared.success and shared.affected_squad_ids.size()==2,"mixed squads receive one shared defense area")
	var settled := false
	for tick in range(1800):
		await physics_frame
		settled = game.units.all(func(unit): return unit.state == Unit.State.DEFENDING)
		if settled: break
	check(settled and game.units.size()==10,"both mixed squads reach their shared area through physics")
	var kept_ids: Array = game.squad_commands.selected_ids.duplicate()
	rifle.resolved_deployment.squad.members[0].die()
	assault.resolved_deployment.squad.members[0].die()
	for tick in range(1200):
		await physics_frame
		settled = game.units.all(func(unit): return unit.state == Unit.State.DEFENDING and unit.position.distance_to(unit.squad.defense_positions[unit.squad_member_index]) <= 10)
		if settled: break
	if not settled:
		for unit in game.units: print("REFORM ",unit.position," home ",unit.squad.defense_positions.get(unit.squad_member_index)," established ",unit.defense_established," state ",unit.state," in ",game.squad_commands.inside_defense(unit.squad,unit.position))
	check(settled and game.units.size()==8,"mixed survivors return to recalculated positions after casualties")
	check(game.squad_commands.selected_ids==kept_ids,"casualties preserve separate selected squad identities")
	game.finish_battle(2,"movement test completed")
	game.planning.advance(1)
	print("SQUAD MOVEMENT: %d assertions, %s" % [checks,"FAILED" if failed else "PASSED"])
	quit(1 if failed else 0)
