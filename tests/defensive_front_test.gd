extends SceneTree
var game: Node
var checks := 0
var failed := false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error("FAILED: "+label)
func spawn(columns: int, rows: int, team: int = 2, type: String = "rifle_squad") -> BattleSquad:
	var spec: Dictionary = game.card_catalog[type].base_stats()
	spec.merge({"team":team,"unit_type":type,"lane":1,"spawn_positions":[]},true)
	for row in range(rows):
		for column in range(columns): spec.spawn_positions.append(Vector2(2200+column*160,5200+row*160) if team == 2 else Vector2(2200+column*160,1800-row*160))
	game.spawn_deployment(spec)
	for unit in spec.squad.members: unit.set_physics_process(false)
	return spec.squad
func settle(squad: BattleSquad) -> void:
	for unit in squad.living_members():
		unit.position = squad.defense_positions[unit.squad_member_index]
		unit.defense_established = true
		unit.state = Unit.State.DEFENDING
		unit.target = null
		unit.is_attacking = false
		if not squad.route_waypoints.is_empty(): squad.route_indices[unit.squad_member_index] = squad.route_waypoints.size()
func clear() -> void:
	game.formation_manager.clear()
	for unit in game.units.duplicate(): unit.die()
	game.squad_commands.prune()
	game.squad_commands.points.update(0,true)
func run() -> void:
	game = load("res://main.tscn").instantiate()
	game.tuning = game.tuning.duplicate()
	game.tuning.enemy_enabled = false
	game.match_options = {"presentation":false}
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	await physics_frame
	var commands = game.squad_commands
	var fronts = commands.fronts
	for team in [2,1]:
		var main := spawn(6,2,team)
		var response: Dictionary = commands.issue_group([main],"DEFEND",Vector2(3200,3500))
		check(response.success,"wide formation accepted team %d" % team)
		if not response.success: continue
		var order: Dictionary = commands.orders[main.order_id]
		check(order.blocks[0].rect.size == Vector2(1920,640),"six files and two ranks persist")
		check(order.facing == (Vector2.UP if team == 2 else Vector2.DOWN),"default faces opposing side")
		settle(main)
		commands.points.update(0,true)
		var homes: Dictionary = main.defense_positions.duplicate()
		var backup := spawn(4,2,team)
		response = commands.issue_group([backup],"DEFEND",order.center,0,PackedVector2Array(),main.order_id)
		check(response.success and order.blocks[-1].role == "RESERVE","center reinforcement adds reserve block")
		check(main.defense_positions == homes,"reinforcement never repacks established homes")
		settle(backup)
		var reserve_unit: Unit = backup.members[0]
		var enemy_squad := spawn(1,1,3-team)
		var enemy: Unit = enemy_squad.members[0]
		enemy.position=reserve_unit.position+order.facing*500
		await physics_frame
		await physics_frame
		var reserve_home: Vector2 = reserve_unit.position
		var enemy_health: float = enemy.current_health
		reserve_unit._physics_process(1.0/60)
		check(enemy.current_health<enemy_health and reserve_unit.position==reserve_home,"reserve fires normally without leaving its home")
		enemy.position=reserve_home+order.facing*900
		await physics_frame
		await physics_frame
		backup.combat_candidates=[enemy]
		reserve_unit._physics_process(1.0/60)
		check(reserve_unit.position==reserve_home,"reserve does not pursue out-of-range squad contacts")
		enemy.die()
		reserve_unit.target=null
		reserve_unit.is_attacking=false
		var edge := spawn(2,2,team)
		var left: float = order.blocks[0].rect.position.x
		var endpoint: Vector2 = fronts.world(order,Vector2(left,0))
		response = commands.issue_group([edge],"DEFEND",endpoint,0,PackedVector2Array(),main.order_id)
		check(response.success and order.blocks[-1].role == "FRONT","edge reinforcement extends frontage")
		settle(edge)
		check(main.defense_positions == homes,"edge extension keeps original block stable")
		var victim: Unit = main.members[0]
		var dead_home: Vector2 = main.defense_positions[victim.squad_member_index]
		victim.die()
		fronts.tick(0.01)
		check(fronts.vacant_front(order).size()==1,"casualty creates real frontline vacancy")
		var reserves_before: int = fronts.reserves(order).size()
		fronts.tick(2.8)
		check(fronts.vacant_front(order).size()==1,"ordinary casualty is not replaced before three seconds")
		fronts.tick(0.20)
		check(fronts.vacant_front(order).is_empty(),"reserve wave assigns exactly one replacement")
		check(fronts.reserves(order).size()==reserves_before-1,"wave moves only the required number of reserves")
		var advancing: Array = main.living_members()+backup.living_members()
		check(advancing.any(func(unit): return unit.squad.defense_positions[unit.squad_member_index]==dead_home),"replacement receives actual vacant home")
		var detached_id: int = edge.squad_id
		commands.issue_group([edge],"ADVANCE")
		check(edge.order_id==-1 and edge.defense_positions.is_empty() and commands.orders.has(main.order_id),"Advance detaches only ordered squad")
		check(fronts.vacant_front(order).size()==2,"detaching creates an opening")
		check(commands.squads.has(detached_id),"detachment preserves squad identity")
		clear()
	# A genuine multi-file opening accepts a block; previews are read-only.
	var opening := spawn(6,1)
	commands.issue_group([opening],"DEFEND",Vector2(3200,3500))
	settle(opening)
	var opening_id: int = opening.order_id
	var old: Dictionary = opening.defense_positions.duplicate()
	for unit in opening.members.duplicate():
		if unit.squad_member_index in [2,3]: unit.die()
	var arriving := spawn(2,1)
	var before_orders := var_to_str(commands.orders)
	var predicted: Dictionary = fronts.plan([arriving],Vector2(3200,3500),PackedVector2Array(),opening_id)
	check(predicted.success and predicted.proposed_blocks[0].role=="FRONT","intact small block fits meaningful casualty opening")
	check(var_to_str(commands.orders)==before_orders,"planning a gap does not mutate live slots or ownership")
	var joined: Dictionary = commands.issue_group([arriving],"DEFEND",Vector2(3200,3500),0,PackedVector2Array(),opening_id)
	check(joined.success and commands.orders[opening_id].blocks[-1].role=="FRONT","committed gap placement matches preview")
	check(opening.defense_positions==old,"gap filling preserves existing surviving homes")
	check(fronts.vacant_front(commands.orders[opening_id]).is_empty(),"new formation reserves gap without double-counting old empty slots")
	clear()
	# An illegal formation cannot spend Command or leave queued soldiers behind.
	game.economies[2].current_command=10
	var command_before: float = game.economies[2].current_command
	var rejected: Dictionary = game.deployment_manager.request_squad(2,[game.card_catalog.conscript_wave],Rect2(2200,0,940,460),"DEFEND",Vector2(80,3500))
	check(not rejected.is_valid and game.economies[2].current_command==command_before and game.formation_manager.pending.is_empty(),"invalid block placement is atomic and unspent")
	clear()
	# Raw formation homes can lie off-center within a legal territory cell.
	# Validate the whole physical body, not just the containing grid cell.
	var boundary := spawn(1,1)
	for at in [Vector2(40,3500),Vector2(game.field_size.x-40,3500),Vector2(3200,game.tuning.no_hold_depth+65)]:
		check(not commands.issue_group([boundary],"DEFEND",at).success,"body crossing map/No-Hold boundary rejects even in a legal grid cell")
	check(commands.issue_group([boundary],"DEFEND",Vector2(game.tuning.unit_radius,3500)).success,"body tangent to legal map edge is accepted")
	clear()
	# Facing derives from final meaningful segment, not first leg.
	var deep := spawn(2,6)
	var path := PackedVector2Array([Vector2(2000,4000),Vector2(2400,3500),Vector2(3200,3500)])
	var r: Dictionary = commands.issue_group([deep],"DEFEND",Vector2(3200,3500),0,path)
	check(r.success and commands.orders[deep.order_id].facing == Vector2.RIGHT,"route sets oriented front facing")
	check(commands.orders[deep.order_id].blocks[0].rect.size==Vector2(640,1920),"deep blueprint persists independently of rotation")
	clear()
	# Full block loss immediately promotes an intact reserve block.
	var line := spawn(4,2)
	commands.issue_group([line],"DEFEND",Vector2(3200,3500))
	settle(line)
	var point_id := line.order_id
	var reserve := spawn(4,2)
	commands.issue_group([reserve],"DEFEND",Vector2(3200,3500),0,PackedVector2Array(),point_id)
	settle(reserve)
	var former: Vector2 = line.defense_positions[0]
	commands.issue_group([line],"ADVANCE")
	fronts.tick(0.01)
	check(commands.orders[point_id].blocks.size()==1 and commands.orders[point_id].blocks[0].role=="FRONT","whole reserve block replaces detached frontline immediately")
	check(reserve.defense_positions[0]==former,"replacement block advances into vacated region")
	clear()
	# Heavy loss accelerates, but never instantly fills a casualty.
	line = spawn(4,2)
	commands.issue_group([line],"DEFEND",Vector2(3200,3500))
	settle(line)
	var order: Dictionary = commands.orders[line.order_id]
	line.members[0].die()
	fronts.tick(0.01)
	check(fronts.vacant_front(order).size()==1 and order.wave_remaining<=1,"quarter loss starts a visible accelerated delay")
	fronts.tick(1.0)
	check(fronts.vacant_front(order).is_empty(),"heavy-loss wave uses the same reserves")
	clear()
	# No reserves means no invented replacements.
	line = spawn(6,1)
	commands.issue_group([line],"DEFEND",Vector2(3200,3500))
	settle(line)
	order = commands.orders[line.order_id]
	line.members[0].die()
	fronts.tick(10)
	check(fronts.vacant_front(order).size()==1 and line.living_members().size()==5,"depleted line stays depleted")
	clear()
	# Physical compatible consolidation, with source identity retained during travel.
	line = spawn(6,1)
	commands.issue_group([line],"DEFEND",Vector2(3200,3500))
	settle(line)
	point_id = line.order_id
	var tiny := spawn(2,1)
	commands.issue_group([tiny],"DEFEND",Vector2(3200,3500),0,PackedVector2Array(),point_id)
	settle(tiny)
	line.members[0].die()
	line.members[0].die()
	tiny.selected = true
	fronts._find_transfers()
	check(fronts.transfers.is_empty(),"selected stragglers never consolidate")
	tiny.selected = false
	fronts._find_transfers()
	check(fronts.transfers.size()==2,"compatible slots reserve exactly available capacity")
	var source_id := tiny.squad_id
	var survivor: Unit = tiny.members[0]
	check(survivor.squad==tiny,"membership stays with source before physical arrival")
	fronts.tick(0.01)
	check(survivor.squad==tiny,"wave/tick cannot teleport membership")
	for unit in tiny.living_members():
		unit.set_physics_process(true)
		unit.attack_range=1
	for tick in range(1800):
		fronts.tick(1.0/60)
		await physics_frame
		if not commands.squads.has(source_id): break
	check(not commands.squads.has(source_id) and line.living_members().size()==6,"physical arrivals consolidate and delete empty source")
	check(game.telemetry.squad_records[source_id].end_reason=="consolidated","consolidated squad is not reported as killed")
	check(line.living_members().size()<=line.formation_capacity,"consolidation cannot exceed original capacity")
	clear()
	line = spawn(6,1)
	commands.issue_group([line],"DEFEND",Vector2(3200,3500))
	settle(line)
	point_id=line.order_id
	tiny=spawn(2,1,2,"assault_squad")
	commands.issue_group([tiny],"DEFEND",Vector2(3200,3500),0,PackedVector2Array(),point_id)
	settle(tiny)
	line.members[0].die()
	fronts._find_transfers()
	check(fronts.transfers.is_empty(),"incompatible unit type does not consolidate")
	commands.issue_group([tiny],"ADVANCE")
	fronts._find_transfers()
	check(fronts.transfers.is_empty(),"advancing stragglers never consolidate")
	clear()
	# Cancellation preserves source identity when the player issues Advance.
	line = spawn(6,1)
	commands.issue_group([line],"DEFEND",Vector2(3200,3500))
	settle(line)
	point_id=line.order_id
	tiny=spawn(2,1)
	commands.issue_group([tiny],"DEFEND",Vector2(3200,3500),0,PackedVector2Array(),point_id)
	settle(tiny)
	line.members[0].die()
	fronts._find_transfers()
	check(fronts.transfers.size()==1,"consolidation reserves only one casualty slot")
	var cancelling: Unit = tiny.members[0]
	commands.issue_group([tiny],"ADVANCE")
	fronts.tick(0.01)
	check(fronts.transfers.is_empty() and cancelling.squad==tiny and tiny.intent=="ADVANCE","player Advance cancels internal transfer without changing membership")
	clear()
	# A wave leaves a rear home vacant while its original member is now forward.
	# Consolidation must use a free identity index, not that home's old index.
	line = spawn(6,2)
	commands.issue_group([line],"DEFEND",Vector2(3200,3500))
	settle(line)
	point_id=line.order_id
	line.members[0].die()
	fronts.tick(3.1)
	settle(line)
	tiny=spawn(2,1)
	commands.issue_group([tiny],"DEFEND",Vector2(3200,3500),0,PackedVector2Array(),point_id)
	settle(tiny)
	fronts._find_transfers()
	check(fronts.transfers.size()==1,"post-wave rear vacancy remains eligible for consolidation")
	if not fronts.transfers.is_empty(): check(fronts.transfers[0].index==0,"free receiving identity remains independent of original physical slot")
	clear()
	# Mixed card order is captured once and preserved with formation member IDs.
	game.economies[2].current_command=10
	var cards: Array = [game.card_catalog.assault_squad,game.card_catalog.rifle_squad]
	var purchase: Dictionary = game.deployment_manager.request_squad(2,cards,Rect2(2200,0,940,620),"DEFEND",Vector2(3200,3500))
	check(purchase.is_valid,"mixed blueprint can establish front")
	if purchase.is_valid:
		var squad: BattleSquad = purchase.resolved_deployment.squad
		var block: Dictionary = commands.orders[squad.order_id].blocks[0]
		var first_row: Array = block.slots.filter(func(slot): return slot.front)
		check(first_row.filter(func(slot): return slot.type=="assault_squad").size()==4,"all four front-priority Assault soldiers remain in first rank")
		check(first_row.size()==5,"original five-file mixed formation persists")
		check(block.blueprint_size==Vector2(940,620),"original blueprint width and depth remain stored on the block")
		check(squad.formation_types.values().has("rifle_squad"),"mixed rear type stays in original squad")
	clear()
	# The largest two-card purchase fits a flank without changing doctrine anchors.
	var ai = game.enemy_controller
	ai.doctrine="LINE"
	ai.doctrine_points.clear()
	ai.uncommitted.clear()
	ai.deployment_cooldown=0
	ai.planned_package=[game.card_catalog.conscript_wave,game.card_catalog.conscript_wave,game.card_catalog.commander_mojo]
	game.player_deployment_confirmed=true
	game.economies[1].current_command=10
	ai.decide()
	check(ai.uncommitted.is_empty() and ai.defender_count("left",true)==48,"large AI package commits once to a legal flank front")
	if ai.doctrine_points.has("left"):
		var ai_point: Dictionary = commands.orders[ai.doctrine_points.left]
		check(ai_point.center==ai.anchor("left") and ai_point.facing==Vector2.DOWN,"AI retains doctrine anchor and explicit enemy-facing orientation")
	clear()
	game.queue_free()
	await process_frame
	# Real controller, economy, queue and physics: both doctrines establish,
	# then buy advancing excess. No metadata teleport or instant establishment.
	for doctrine in ["LINE","TRIANGLE"]:
		game = load("res://main.tscn").instantiate()
		game.tuning = game.tuning.duplicate()
		game.tuning.enemy_enabled = true
		game.tuning.enemy_doctrine = doctrine
		game.tuning.score_victory_enabled = false
		game.tuning.move_speed_variance = 0
		game.match_options = {"presentation":false}
		root.add_child(game)
		current_scene = game
		game.player_deployment_confirmed = true
		game.economies[1].current_command = 10
		var established := false
		var excess := false
		var assigned := true
		for tick in range(9000):
			await physics_frame
			var controller = game.enemy_controller
			assigned = assigned and controller.uncommitted.is_empty()
			if controller.defender_count("center") >= (20 if doctrine=="TRIANGLE" else 10) and controller.defender_count("left")>=10 and controller.defender_count("right")>=10: established = true
			if established and game.squad_commands.squads.values().any(func(squad): return squad.team==1 and squad.intent=="ADVANCE" and game.squad_commands.count_members(squad)>0):
				excess = true
				break
		check(established,doctrine+" physically establishes all doctrine minimums")
		check(assigned,doctrine+" never buys an unplaceable defensive block")
		check(excess,doctrine+" still deploys advancing excess forces")
		for key in ["left","center","right"]:
			var point: int = game.enemy_controller.doctrine_points.get(key,-1)
			check(game.squad_commands.orders.has(point) and game.squad_commands.orders[point].center==game.enemy_controller.anchor(key),doctrine+" preserves "+key+" anchor")
		game.queue_free()
		await process_frame
	print("DEFENSIVE FRONT: %d assertions, %s" % [checks,"FAILED" if failed else "PASSED"])
	quit(1 if failed else 0)
