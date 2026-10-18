extends SceneTree
var failed := false
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	if not condition:
		push_error("FAILED: " + description)
		failed = true
	checks += 1

func physics_frames(count: int) -> void:
	for index in range(count):
		await physics_frame

func _run() -> void:
	root.size = Vector2i(1280, 800)
	var game = load("res://main.tscn").instantiate()
	game.tuning = game.tuning.duplicate()
	game.tuning.enemy_enabled = false
	root.add_child(game)
	current_scene = game
	game.set_process(false)
	game.set_physics_process(false)
	await process_frame
	var hand = game.hand
	var rifle: Resource = game.card_catalog.rifle_squad
	var mojo: Resource = game.card_catalog.commander_mojo
	hand.cards.assign([rifle, mojo, game.card_catalog.forced_march, game.card_catalog.defensive_officer, rifle])
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	var motion := InputEventMouseMotion.new()
	press.position = hand._card_rect(0).get_center()
	release.position = press.position
	hand._unhandled_input(press)
	hand._unhandled_input(release)
	check(hand.selected_indices == [0] and hand.dragged_index == -1, "Click selects a unit without dragging")
	await create_timer(0.22).timeout
	check(is_equal_approx(hand.card_lifts[0], 22), "Selected-card tween completes")
	press.position = hand._card_rect(1).get_center()
	release.position = press.position
	hand._unhandled_input(press)
	hand._unhandled_input(release)
	check(hand.selected_indices == [0, 1], "Click attaches Mojo")
	game.economies[2].current_command = 6
	var rectangle := Rect2(2400, 5500, 1000, 500)
	press.position = game.get_canvas_transform() * rectangle.position
	hand._start_footprint(press.position)
	motion.position = game.get_canvas_transform() * rectangle.end
	hand._unhandled_input(motion)
	check(game.footprint_preview.is_valid and game.preview.get_child_count() == 12, "Selected package previews a drawn formation")
	release.position = motion.position
	hand._unhandled_input(release)
	check(game.formation_manager.pending.size() == 12 and hand.selected_indices.is_empty(), "Release confirms and reserves formation")
	game.formation_manager.clear()
	for unit in game.units.duplicate():
		unit.die()
	# Rejected release must remove the box and ghosts, even when released over UI.
	for release_over_hud in [false, true]:
		hand.cards.assign([rifle, mojo, rifle, rifle, rifle])
		hand.cancel_selection()
		hand._toggle_card(0)
		game.economies[2].current_command = 0 if release_over_hud else 10
		var command_before: float = game.economies[2].current_command
		var selected_before: Array = hand.selected_indices.duplicate()
		var cards_before: Array = hand.cards.duplicate()
		var invalid_rect := Rect2(2400, 5500, 100, 100)
		press.position = game.get_canvas_transform() * invalid_rect.position
		hand._start_footprint(press.position)
		motion.position = game.get_canvas_transform() * invalid_rect.end
		hand._input(motion)
		check(hand.drawing_footprint and not game.footprint_preview.is_valid, "Invalid box is red while drawing")
		release.position = Vector2(500, root.size.y - 100) if release_over_hud else motion.position
		hand._input(release)
		check(not hand.has_footprint and not hand.drawing_footprint and game.footprint_preview.is_empty() and game.preview.get_child_count() == 0, "Invalid release clears rectangle and ghosts, including over HUD")
		hand._process(0.2)
		check(game.footprint_preview.is_empty(), "Periodic refresh cannot revive a rejected box")
		check(hand.selected_indices == selected_before and hand.cards == cards_before and game.economies[2].current_command == command_before and game.formation_manager.pending.is_empty(), "Invalid release preserves cards, selection and Command without queueing")
		check(hand.message.contains("No cards or Command spent"), "Rejection remains explained after box clears")
	# The next draw can still confirm normally after an invalid release.
	hand.cancel_selection()
	hand.cards.assign([rifle, mojo, rifle, rifle, rifle])
	hand._toggle_card(0)
	game.economies[2].current_command = 3
	press.position = game.get_canvas_transform() * rectangle.position
	hand._start_footprint(press.position)
	motion.position = game.get_canvas_transform() * rectangle.end
	hand._input(motion)
	release.position = motion.position
	hand._input(release)
	check(game.formation_manager.pending.size() == 6 and hand.selected_indices.is_empty() and not hand.has_footprint, "Valid draw works immediately after rejected release")
	game.formation_manager.clear()
	# Drag remains available, including modifier-only discard and cancellation.
	hand.cancel_selection()
	hand.cards.assign([rifle, mojo, rifle, rifle, rifle])
	press.position = hand._card_rect(1).get_center()
	hand._unhandled_input(press)
	motion.position = hand._discard_rect().get_center()
	hand._unhandled_input(motion)
	check(hand.dragged_index == 1 and hand.discard_hovered, "Drag modifier to discard")
	release.position = motion.position
	hand._unhandled_input(release)
	check(hand.cards.size() == 5 and hand.selected_indices.is_empty(), "Discard refills and clears selection")
	# Actual detection, nearest targeting, ranged damage, death and resumed advance.
	var spec: Dictionary = rifle.base_stats()
	spec.quantity = 1
	spec.unit_type = "rifle_squad"
	spec.lane = 1
	spec.team = 2
	spec.spawn_positions = [Vector2(3200, 3500)]
	game.spawn_deployment(spec)
	var player: Unit = game.units.back()
	player.set_physics_process(false)
	spec.team = 1
	spec.spawn_positions = [Vector2(3200, 3000)]
	game.spawn_deployment(spec)
	var near: Unit = game.units.back()
	near.set_physics_process(false)
	spec.spawn_positions = [Vector2(3300, 2950)]
	game.spawn_deployment(spec)
	var far: Unit = game.units.back()
	far.set_physics_process(false)
	await physics_frames(4)
	check(player.nearest_enemy() == near, "Acquire nearest valid enemy")
	player._physics_process(0.016)
	check(near.current_health == 55 and player.state == Unit.State.ENGAGING, "Ranged attack applies damage and stops movement")
	player._physics_process(0.016)
	check(near.current_health == 55, "Attack interval prevents damage every frame")
	near.die()
	await physics_frames(3)
	check(player.nearest_enemy() == far, "Retarget after enemy death")
	far.die()
	await physics_frames(3)
	var before_y := player.position.y
	player._physics_process(0.016)
	check(player.state == Unit.State.ADVANCING and player.velocity.y < 0 and player.position.y < before_y, "Resume advancing after all targets die")
	player.die()
	await physics_frames(2)
	# Exercise the real goal Area2D, rather than calling scoring directly.
	spec.team = 2
	spec.spawn_positions = [Vector2(3200, 200)]
	game.spawn_deployment(spec)
	var scorer: Unit = game.units.back()
	scorer.set_physics_process(false)
	await physics_frames(4)
	check(game.scores[2] == 0, "Unit is not scored before crossing the boundary")
	scorer.position.y = 80
	await physics_frames(4)
	check(game.scores[2] == 1 and game.units.is_empty(), "Goal collision awards own team and removes unit")
	# Both event handlers and game rules reset through the real Restart button.
	game.finish_battle(2, "Restart test")
	game.hud.restart_button.pressed.emit()
	await process_frame
	await process_frame
	var restarted = current_scene
	check(is_instance_valid(restarted) and restarted != game, "Restart loads a fresh scene")
	check(restarted.battle_active and restarted.scores[2] == 0 and restarted.scores[1] == 0, "Restart resets battle and scores")
	check(restarted.hand.cards.size() == 5 and restarted.units.is_empty(), "Restart deals new hand and clears units")
	check(restarted.economies[2].current_command >= 3 and restarted.economies[2].current_command < 3.2, "Restart resets Command")
	print("COMBAT / INPUT CHECKS: %d assertions, %s" % [checks, "FAILED" if failed else "PASSED"])
	quit(1 if failed else 0)

