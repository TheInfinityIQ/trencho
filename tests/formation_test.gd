extends SceneTree
var checks := 0
var game: Node2D
func _initialize() -> void:
	call_deferred("_run")
func check(value: bool, label: String) -> void:
	if not value:
		push_error("FAILED: " + label)
		quit(1)
		assert(value, label)
	checks += 1
func clear_units() -> void:
	game.formation_manager.clear()
	for unit in game.units.duplicate():
		unit.die()
	game.refresh_occupancy()
func body(point: Vector2, team: int = 2) -> Unit:
	var stats: Dictionary = game.card_catalog.rifle_squad.base_stats()
	stats.team = team
	stats.lane = game.lane_for_x(point.x)
	stats.unit_type = "rifle_squad"
	stats.spawn_positions = [point]
	game.spawn_deployment(stats)
	var unit: Unit = game.units.back()
	unit.set_physics_process(false)
	return unit
func mouse_button(point: Vector2, pressed: bool, button: int = MOUSE_BUTTON_LEFT) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = button
	event.pressed = pressed
	return event
func _run() -> void:
	root.size = Vector2i(1280, 900)
	game = load("res://main.tscn").instantiate()
	game.tuning = game.tuning.duplicate()
	game.tuning.enemy_enabled = false
	root.add_child(game)
	current_scene = game
	game.set_process(false)
	game.hand.set_process(false)
	await process_frame
	var fm = game.formation_manager
	var manager = game.deployment_manager
	var hand = game.hand
	var player = game.economies[2]
	var rifle: Resource = game.card_catalog.rifle_squad
	var mojo: Resource = game.card_catalog.commander_mojo
	var march: Resource = game.card_catalog.forced_march
	var officer: Resource = game.card_catalog.defensive_officer
	check(game.card_catalog.size() == 6 and hand.cards.size() == 5, "Six cards and five-card initial hand")
	for card in game.card_catalog.values():
		check(card.art != null, "Artwork loaded")
	player.tick(2)
	game.economies[1].tick(2)
	check(player.current_command == 5 and game.economies[1].current_command == 5, "Both economies regenerate")
	player.tick(100)
	check(player.current_command == 10, "Command capped")
	check(manager.resolve_package([mojo]).failure_reason == "NO_UNIT_CARD", "Modifiers alone cannot deploy")
	check(manager.resolve_package([rifle, rifle]).failure_reason == "MULTIPLE_UNIT_CARDS", "Exactly one Unit")
	check(manager.resolve_package([rifle, mojo, march, officer]).failure_reason == "TOO_MANY_MODIFIERS", "Two modifier maximum")
	check(manager.resolve_package([rifle, mojo]).resolved_deployment.quantity == 12, "Mojo resolves before formation evaluation")
	var vehicle: Resource = rifle.duplicate()
	vehicle.tags = PackedStringArray(["Vehicle"])
	check(manager.resolve_package([vehicle, mojo]).failure_reason == "INCOMPATIBLE_MODIFIER", "Tag compatibility retained")
	hand.cards.assign([rifle, mojo, march, officer, vehicle])
	hand._toggle_card(1)
	hand._toggle_card(2)
	check(hand.selected_indices == [1, 2], "Two modifiers can be selected first")
	hand._toggle_card(3)
	check(hand.selected_indices == [1, 2], "Modifier-first limit enforced")
	hand._toggle_card(4)
	check(hand.selected_indices == [1, 2], "Incompatible Unit rejected without dropping modifiers")
	hand._toggle_card(0)
	check(hand.selected_indices == [0, 1, 2], "Unit selected after modifiers preserves package")
	hand._toggle_card(0)
	check(hand.selected_indices == [1, 2], "Unit can be deselected independently")
	hand._toggle_card(0)
	var right := mouse_button(hand._card_rect(0).get_center(), true, MOUSE_BUTTON_RIGHT)
	game._input(right)
	check(hand.selected_indices.is_empty(), "Right-click anywhere clears selection")
	var wide := Rect2(1200, 5300, 940, 300)
	var deep := Rect2(1200, 4800, 460, 620)
	var evaluated: Dictionary = fm.evaluate(2, wide, 12)
	check(evaluated.is_valid and evaluated.capacity == 12, "Wide shallow formation has 6 by 2 slots")
	check(fm.evaluate(2, deep, 12).is_valid, "Narrow deep formation has 3 by 4 slots")
	var balanced: Dictionary = fm.evaluate(2, Rect2(1200, 5300, 1000, 500), 9)
	var chosen_bounds := Rect2(balanced.chosen_slots[0], Vector2.ZERO)
	for point in balanced.chosen_slots:
		chosen_bounds = chosen_bounds.expand(point)
	check(chosen_bounds.size.x >= 700 and chosen_bounds.size.y >= 300, "Partial formations use the requested width and depth")
	for a in evaluated.valid_slots:
		check(wide.grow(-70).encloses(Rect2(a, Vector2.ZERO)), "Whole unit footprint stays inside rectangle")
		for b in evaluated.valid_slots:
			if a != b:
				check(a.distance_to(b) >= game.tuning.spawn_spacing - 0.01, "Minimum slot spacing")
	var tiny := Rect2(1200, 5300, 100, 100)
	check(not fm.evaluate(2, tiny, 6).is_valid, "Too-small footprint rejected")
	check(fm.evaluate(2, tiny, 6).rectangle == tiny, "Rectangle never auto-expands")
	var outside := Rect2(100, 5300, 1000, 300)
	check(fm.evaluate(2, outside, 6).failure_reason == "OUTSIDE_DEPLOYMENT_AREA", "Entire rectangle must stay inside region")
	var occupied: Vector2 = evaluated.valid_slots[0]
	var friend = body(occupied)
	check(fm.evaluate(2, wide, 12).capacity == 11, "Friendly body blocks only its own space")
	check(fm.evaluate(2, Rect2(1200, 5300, 1100, 300), 12).is_valid, "A larger footprint remains legal near a friend")
	friend.die()
	check(fm.evaluate(2, wide, 12).is_valid, "Death frees physical slots")
	var enemy = body(occupied, 1)
	check(fm.evaluate(2, wide, 12).failure_reason == "ENEMY_TOO_CLOSE", "Enemy exclusion removes nearby slots")
	check(fm.evaluate(2, Rect2(4000, 5300, 940, 300), 12).is_valid, "Enemy does not disable the whole deployment area")
	enemy.die()
	# Actual terrain collision is excluded from the generated slots.
	var terrain := StaticBody2D.new()
	terrain.collision_layer = 1
	terrain.collision_mask = 0
	terrain.position = occupied
	var collider := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 40
	collider.shape = circle
	terrain.add_child(collider)
	game.add_child(terrain)
	for frame in range(3):
		await physics_frame
	check(fm.evaluate(2, wide, 12).failure_reason == "BLOCKED_BY_TERRAIN", "Terrain blocks slots")
	terrain.queue_free()
	for frame in range(3):
		await physics_frame
	# Invalid draw/release remains exact and red; no side effects.
	hand.cancel_selection()
	hand.cards.assign([rifle, mojo, march, officer, rifle])
	hand.draw_pile.assign([rifle, rifle, rifle, rifle, rifle])
	hand.discard_pile.clear()
	hand._toggle_card(1)
	hand._toggle_card(0)
	var start: Vector2 = game.get_canvas_transform() * tiny.position
	var finish: Vector2 = game.get_canvas_transform() * tiny.end
	hand._unhandled_input(mouse_button(start, true))
	var motion := InputEventMouseMotion.new()
	motion.position = finish
	hand._unhandled_input(motion)
	hand._unhandled_input(mouse_button(finish, false))
	check(hand.has_footprint and not hand.drawing_footprint, "Invalid rectangle persists after release")
	check(hand.footprint.position.distance_to(tiny.position) < 0.1 and hand.footprint.size.distance_to(tiny.size) < 0.1, "Dragged footprint remains exactly drawn")
	check(not game.footprint_preview.is_valid and hand.cards.size() == 5 and fm.pending.is_empty() and player.current_command == 10, "Invalid footprint is red and atomic")
	# Corner drag resizes, interior drag moves, and release is captured over HUD.
	var corner_point: Vector2 = game.get_canvas_transform() * hand.footprint.end
	check(hand._start_footprint(corner_point) and hand.footprint_mode == "resize", "Invalid rectangle has resize handles")
	hand._drag_footprint(game.get_canvas_transform() * (tiny.end + Vector2(20, 20)))
	check(hand.footprint.size.distance_to(Vector2(120, 120)) < 0.1, "Corner resizing remains exact")
	hand.drawing_footprint = false
	var interior_point: Vector2 = game.get_canvas_transform() * hand.footprint.get_center()
	check(hand._start_footprint(interior_point) and hand.footprint_mode == "move", "Invalid rectangle can be moved")
	hand._drag_footprint(interior_point + Vector2(20, 0))
	check(hand.footprint.position.x > tiny.position.x, "Move gesture changes position")
	var hud_release := mouse_button(Vector2(500, root.size.y - 100), false)
	hand._input(hud_release)
	check(not hand.drawing_footprint and hand.has_footprint and fm.pending.is_empty(), "Release over HUD ends invalid gesture without deployment")
	game._input(right)
	check(not hand.has_footprint and game.footprint_preview.is_empty() and hand.selected_indices.is_empty(), "Right-click clears rectangle and ghosts without spending")
	# Confirmation spends once, consumes the package and reserves before entry.
	hand._toggle_card(1)
	hand._toggle_card(0)
	hand.has_footprint = true
	hand.footprint = wide
	player.current_command = 5
	check(not hand._confirm_footprint(), "Insufficient Command cannot confirm")
	check(hand.selected_indices.size() == 2 and hand.discard_pile.is_empty() and player.current_command == 5 and fm.pending.is_empty(), "Resource rejection preserves cards, selection and resource")
	player.current_command = 6
	check(hand._confirm_footprint(), "Valid footprint accepted")
	check(player.current_command == 0 and hand.cards.size() == 5 and hand.discard_pile.size() == 2, "Exact package cost and consumption")
	check(fm.reservations.size() == 12 and fm.pending.size() == 12 and game.units.is_empty(), "Reserve all slots and queue instead of instant spawn")
	player.current_command = 10
	check(not manager.request_formation(2, [rifle, mojo], wide).is_valid and player.current_command == 10, "Reservations prevent double-booking without charging")
	check(manager.request_formation(2, [rifle], Rect2(4000, 5300, 940, 300)).is_valid, "Disjoint formation can deploy during entry")
	clear_units()
	# Entry geometry is translated behind the edge, never a destination march.
	player.current_command = 10
	check(manager.request_formation(2, [rifle], Rect2(1200, 5300, 940, 140)).is_valid, "Queue a reinforcement squad")
	fm.tick(0.2)
	for unit in game.units:
		unit.set_physics_process(false)
	check(game.units.size() == 6 and fm.pending.is_empty(), "Whole wide rank releases together")
	for unit in game.units:
		check(unit.state == Unit.State.ENTERING_BATTLEFIELD and unit.position.y > game.field_size.y, "Units originate behind the battlefield")
		check(unit.assigned_formation_slot == unit.position, "Assigned geometry records entry origin, not drawn destination")
		for other in game.units:
			if other != unit:
				check(unit.position.distance_to(other.position) >= game.tuning.unit_radius * 2, "No initial reinforcement overlap")
	for step in range(180):
		for unit in game.units:
			unit._physics_process(1.0 / 60)
	for unit in game.units:
		check(unit.state == Unit.State.ADVANCING and unit.has_entered_battlefield and unit.position.y > wide.end.y, "Normal advance begins at field edge before drawn rectangle")
	check(fm.reservations.is_empty(), "Crossing the edge releases reservations")
	clear_units()
	# Actual entry congestion holds only the blocked file, without relocation.
	player.current_command = 10
	manager.request_formation(2, [rifle], Rect2(1200, 5300, 940, 140))
	var first_entry: Vector2 = fm.pending[0].entry_position
	var blocker := body(first_entry)
	fm.tick(0.2)
	for unit in game.units:
		unit.set_physics_process(false)
	check(fm.pending.size() == 1 and game.units.size() == 6, "Blocked file queues while five safe files spawn")
	check(fm.pending[0].entry_position == first_entry, "Entry blockage never moves requested geometry")
	blocker.die()
	fm.tick(0.2)
	check(fm.pending.is_empty(), "Blocked file resumes when entry clears")
	var dead_id: int = game.units.back().reservation_id
	game.units.back().die()
	check(not fm.reservations.has(dead_id), "Death releases incoming reservation")
	clear_units()
	# A narrow/deep formation translates into separated ranks behind the edge.
	player.current_command = 10
	var column := Rect2(2600, 4800, 140, 940)
	manager.request_formation(2, [rifle], column)
	fm.tick(0.2)
	fm.tick(0.2)
	for unit in game.units:
		unit.set_physics_process(false)
	check(game.units.size() == 2 and fm.pending.size() == 4, "Narrow formation releases one separated rank per interval")
	check(is_equal_approx(game.units[1].position.y - game.units[0].position.y, game.tuning.spawn_spacing), "Depth produces physical rank spacing")
	clear_units()
	# Enemy requests use the same region/slot/reservation path.
	game.economies[1].current_command = 3
	game.enemy_controller.decide()
	check(game.economies[1].current_command == 0 and fm.pending.size() == 6, "Bot pays and reserves through shared formation validation")
	fm.tick(1)
	check(game.units[0].team_id == 1 and game.units[0].position.y < 0, "Enemy reinforces from behind its own boundary")
	clear_units()
	# Automatic reshuffle and score victory remain available.
	var total: int = hand.cards.size() + hand.draw_pile.size() + hand.discard_pile.size()
	for index in range(12):
		hand.cancel_selection()
		hand._toggle_card(0)
		hand._discard_selected()
		check(hand.cards.size() == 5 and hand.cards.size() + hand.draw_pile.size() + hand.discard_pile.size() == total, "Deck conservation during automatic reshuffle")
	check(hand.shuffle_count > 0, "Discard reshuffles automatically")
	game.scores[2] = game.tuning.victory_score - 1
	game.score_unit(body(Vector2(3200, 100)))
	check(not game.battle_active and game.winner == 2, "Score victory still resolves")
	check(fm.pending.is_empty() and fm.reservations.is_empty(), "Battle end clears pending reinforcements")
	print("FORMATION CHECKS PASSED: %d assertions" % checks)
	quit()
