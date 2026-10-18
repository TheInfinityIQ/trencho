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
func freeze() -> void:
	for unit in game.units: unit.set_physics_process(false)
func clear_units() -> void:
	game.formation_manager.clear()
	for unit in game.units.duplicate(): unit.die()
func body(point: Vector2, team: int) -> Unit:
	var spec: Dictionary = game.card_catalog.rifle_squad.base_stats()
	spec.team = team
	spec.unit_type = "rifle_squad"
	spec.lane = 1
	spec.spawn_positions = [point]
	game.spawn_deployment(spec)
	var unit: Unit = game.units.back()
	unit.set_physics_process(false)
	return unit
func frames(count: int = 3) -> void:
	for i in range(count): await physics_frame
func reservation_occupancy_scenarios() -> void:
	var fm = game.formation_manager
	var manager = game.deployment_manager
	var rifle: BattleCard = game.card_catalog.rifle_squad
	for team in [1, 2]:
		var rectangle := Rect2(1200, 600 if team == 1 else 5300, 940, 140)
		# A reservation describes entry geometry, not a destination to revalidate.
		game.economies[team].current_command = 10
		var accepted: Dictionary = manager.request_formation(team, [rifle], rectangle)
		check(accepted.is_valid, "accept order before its drawn space becomes occupied")
		var occupied_slot: Vector2 = fm.pending[0].position
		var later_occupant := body(Vector2(3500, 3500), 3 - team)
		later_occupant.position = occupied_slot
		fm.tick(0.2)
		freeze()
		var actual_spawned := 0
		for unit in game.units:
			if unit.reservation_id >= 0: actual_spawned += 1
		check(actual_spawned == 6 and fm.pending.is_empty(), "later occupancy of drawn slots does not cancel purchased troops")
		check(game.economies[team].current_command == 7, "drawn-slot occupancy does not charge again")
		clear_units()
		await frames()
		for blocker_team in [team, 3 - team]:
			# Physically occupying an entry point after acceptance should retain,
			# retry and eventually spawn that exact queued soldier once clear.
			game.economies[team].current_command = 10
			accepted = manager.request_formation(team, [rifle], rectangle)
			check(accepted.is_valid, "accept order before physical entry becomes occupied")
			var delayed_id: int = fm.pending[0].id
			var delayed_point: Vector2 = fm.pending[0].entry_position
			later_occupant = body(Vector2(3500, 3500), blocker_team)
			later_occupant.position = delayed_point
			for step in range(180):
				fm.tick(1.0 / 60)
				freeze()
			check(fm.pending.size() == 1 and fm.pending[0].id == delayed_id and fm.reservations.has(delayed_id), "blocked entry retains the paid soldier and reservation across retries")
			check(game.units.size() == 6, "one blocked file does not hold up five clear files")
			later_occupant.position += Vector2(2000, 0)
			fm.tick(0.2)
			freeze()
			var identifiers: Dictionary = {}
			for unit in game.units:
				if unit.reservation_id >= 0: identifiers[unit.reservation_id] = true
			check(fm.pending.is_empty() and identifiers.size() == 6 and identifiers.has(delayed_id), "entry clearing spawns every paid soldier exactly once")
			check(game.economies[team].current_command == 7, "entry retries never spend extra Command")
			for step in range(60): fm.tick(1.0 / 60)
			check(game.units.size() == 7, "completed queue never duplicates soldiers")
			clear_units()
			await frames()
		# Separate legal drawn rectangles can translate to the same entry files.
		# Let real movement clear those files, rather than deleting blockers.
		game.economies[team].current_command = 10
		var first: Dictionary = manager.request_formation(team, [rifle], rectangle)
		var shifted := Rect2(1200, 1100 if team == 1 else 4800, 940, 140)
		var second: Dictionary = manager.request_formation(team, [rifle], shifted)
		check(first.is_valid and second.is_valid and fm.pending.size() == 12, "two drawn formations can share translated entry geometry")
		for step in range(360):
			fm.tick(1.0 / 60)
			freeze()
			for unit in game.units.duplicate(): unit._physics_process(1.0 / 60)
		var flow: Dictionary = fm.flow_counts(team)
		check(fm.pending.is_empty() and flow.active == 12 and flow.incoming == 0, "shared entry files eventually deliver both complete formations")
		check(fm.reservations.is_empty(), "all shared-entry reservations release after crossing")
		check(game.economies[team].current_command == 4, "both complete formations cost exactly two orders")
		clear_units()
		await frames()
		# Terrain introduced at an accepted entry is retained/retried too.
		game.economies[team].current_command = 10
		accepted = manager.request_formation(team, [rifle], rectangle)
		check(accepted.is_valid, "accept order before terrain blocks entry")
		var terrain_id: int = fm.pending[0].id
		var terrain := StaticBody2D.new()
		terrain.collision_layer = 1
		terrain.collision_mask = 0
		terrain.position = fm.pending[0].entry_position
		var collision := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 1
		collision.shape = shape
		terrain.add_child(collision)
		game.add_child(terrain)
		await frames()
		fm.tick(0.2)
		freeze()
		check(fm.pending.size() == 1 and fm.pending[0].id == terrain_id and game.units.size() == 5, "new terrain queues its file without losing the reservation or blocking clear files")
		terrain.queue_free()
		await frames()
		fm.tick(0.2)
		freeze()
		check(fm.pending.is_empty() and game.units.size() == 6, "terrain removal releases the last paid soldier")
		clear_units()
		await frames()
		# A deep Mojo wave must drain completely as front ranks clear the route.
		game.economies[team].current_command = 10
		var deep := Rect2(2600, 600 if team == 1 else 4800, 620, 940)
		accepted = manager.request_formation(team, [game.card_catalog.conscript_wave, game.card_catalog.commander_mojo], deep)
		check(accepted.is_valid and fm.pending.size() == 24, "queue a deep 24-soldier formation")
		for step in range(720):
			fm.tick(1.0 / 60)
			freeze()
			for unit in game.units.duplicate(): unit._physics_process(1.0 / 60)
		flow = fm.flow_counts(team)
		check(fm.pending.is_empty() and flow.active == 24 and flow.incoming == 0, "deep formation eventually delivers all 24 soldiers")
		check(fm.reservations.is_empty() and game.economies[team].current_command == 5, "deep wave releases every reservation at its original cost")
		clear_units()
		await frames()
func run() -> void:
	game = load("res://main.tscn").instantiate()
	game.tuning = game.tuning.duplicate()
	game.tuning.enemy_enabled = false
	root.add_child(game)
	current_scene = game
	game.set_process(false)
	game.set_physics_process(false)
	await process_frame
	var fm = game.formation_manager
	var manager = game.deployment_manager
	var rifle: BattleCard = game.card_catalog.rifle_squad
	var conscript: BattleCard = game.card_catalog.conscript_wave
	var mojo: BattleCard = game.card_catalog.commander_mojo
	var wide := Rect2(1200,5300,940,300)
	game.economies[1].tick(100)
	for i in range(30): game.enemy_controller.tick(1.0)
	game.enemy_controller.decide()
	check(fm.pending.is_empty() and game.economies[1].current_command == 10,"enemy waits despite a full economy")
	check(not game.player_deployment_confirmed,"clock does not unlock enemy")
	game.hand._toggle_card(0)
	game.hand._discard_selected()
	check(not game.player_deployment_confirmed,"discard does not unlock enemy")
	manager.request_formation(2,[rifle],Rect2(1200,5300,100,100))
	check(not game.player_deployment_confirmed,"invalid order does not unlock enemy")
	game.economies[2].current_command = 0
	manager.request_formation(2,[rifle],wide)
	check(not game.player_deployment_confirmed,"unaffordable order does not unlock enemy")
	game.economies[2].current_command = 10
	manager.request_formation(2,[rifle],wide)
	check(game.player_deployment_confirmed,"accepted player order unlocks enemy")
	game.enemy_controller.tick(1.0)
	var enemy_orders := 0
	for slot in fm.pending:
		if slot.team == 1: enemy_orders += 1
	check(enemy_orders > 0 and game.economies[1].current_command < 10,"enemy starts a legal paid package after gate")
	clear_units()
	game.economies[1].current_command = 10
	game.enemy_controller.tick(1.0)
	check(fm.pending.size() > 0,"gate stays open after all player troops are gone and deployment cooldown elapses")
	clear_units()
	var points: Array = fm.evaluate(2,wide,12).chosen_slots
	var shifted: Array = fm.evaluate(2,Rect2(1200,4800,940,300),12).chosen_slots
	check(fm.entry_positions(2,points) == fm.entry_positions(2,shifted),"moving rectangle vertically does not change entry distance")
	var entries: Array = fm.entry_positions(2,points)
	for i in range(points.size()):
		check(entries[i].x == points[i].x and entries[i].y > game.field_size.y,"entry preserves frontage behind friendly edge")
		for j in range(i):
			check((entries[i]-entries[j]).is_equal_approx(points[i]-points[j]),"relative formation geometry survives translation")
	var enemy_points: Array = fm.evaluate(1,Rect2(1200,600,940,300),12).chosen_slots
	var enemy_entries: Array = fm.entry_positions(1,enemy_points)
	check(enemy_entries[0].y == -game.tuning.offscreen_spawn_margin,"enemy front rank faces down from top edge")
	for point in enemy_entries: check(point.y < 0,"enemy ranks stay behind top edge")
	# One physical enemy denies its local slot while the rest of the same rectangle stays available.
	var candidate: Vector2 = points[0]
	var enemy := body(candidate,1)
	var evaluation: Dictionary = fm.evaluate(2,wide,6)
	check(evaluation.is_valid and evaluation.capacity == 11,"one enemy removes one nearby slot, leaving same rectangle usable")
	check(fm.block_reason(2,candidate) == "ENEMY_TOO_CLOSE","cannot reserve a slot on an enemy")
	check(game.tuning.enemy_exclusion_radius == 144,"local denial radius fits unit diameter")
	for i in range(1,points.size()): body(points[i],1)
	check(not fm.evaluate(2,wide,6).is_valid,"physically occupied rectangle can still be denied")
	clear_units()
	await frames()
	await reservation_occupancy_scenarios()
	# Full 24-body order: two broad ranks, no distant-slot travel stage.
	game.economies[2].current_command = 10
	var mass := Rect2(1000,5000,1900,300)
	var accepted: Dictionary = manager.request_formation(2,[conscript,mojo],mass)
	check(accepted.is_valid and accepted.resolved_deployment.quantity == 24,"Mojo Conscript baseline unchanged")
	check(game.economies[2].current_command == 5,"original combined Command cost retained")
	var flow: Dictionary = fm.flow_counts(2)
	check(flow.queued == 24 and flow.entering == 0 and flow.active == 0,"purchased wave begins queued")
	fm.tick(.2)
	freeze()
	flow = fm.flow_counts(2)
	check(flow.queued == 12 and flow.entering == 12 and flow.incoming == 24,"first broad rank enters together")
	fm.tick(.2)
	freeze()
	flow = fm.flow_counts(2)
	check(flow.queued == 0 and flow.entering == 24,"second broad rank spawns without per-soldier bottleneck")
	check(flow.oldest_incoming > 0,"incoming age is inspectable")
	for step in range(240):
		for unit in game.units: unit._physics_process(1.0/60)
	flow = fm.flow_counts(2)
	check(flow.incoming == 0 and flow.active == 24 and flow.advancing == 24,"wave activates at edge within four seconds")
	check(fm.reservations.is_empty(),"entry frees requested layout reservations")
	for unit in game.units:
		check(unit.entry_elapsed > 0 and unit.position.y > mass.end.y,"active unit never waited to reach drawn rectangle")
	clear_units()
	await frames()
	# Emergency Assault can fire before fully entering and resume straight forward afterward.
	game.economies[2].current_command = 10
	manager.request_formation(2,[game.card_catalog.assault_squad],Rect2(2400,5100,620,140))
	fm.tick(.2)
	freeze()
	var assault: Unit = game.units[0]
	enemy = body(assault.position + Vector2(0,-390),1)
	await frames()
	assault._physics_process(.016)
	check(assault.state == Unit.State.ENGAGING and enemy.current_health < 100,"emergency assault fights before finishing entry")
	check(assault.velocity == Vector2.ZERO and not assault.has_entered_battlefield,"incoming fire stops movement without pretending to be active")
	flow = fm.flow_counts(2)
	check(flow.entering == 4 and flow.engaging == 1,"debug separates physical entry from combat state")
	enemy.die()
	await frames()
	var old_position := assault.position
	assault._physics_process(.016)
	check(assault.state == Unit.State.ENTERING_BATTLEFIELD and assault.position.y < old_position.y,"threat resolved resumes straight forward entry")
	check(assault.position.x == old_position.x,"entry never steers to a destination")
	check(assault.debug_description().contains("Queue wait") and assault.debug_description().contains("Entry total"),"unit inspection exposes logistics delay")
	clear_units()
	# The actual Restart button resets the first-deployment gate.
	game.hud.restart_button.pressed.emit()
	await process_frame
	await process_frame
	var restarted = current_scene
	restarted.set_process(false)
	restarted.set_physics_process(false)
	check(not restarted.player_deployment_confirmed and restarted.formation_manager.pending.is_empty(),"restart resets startup gate and queue")
	print("REINFORCEMENT FLOW: %d assertions, %s" % [checks,"FAILED" if failed else "PASSED"])
	quit(1 if failed else 0)
