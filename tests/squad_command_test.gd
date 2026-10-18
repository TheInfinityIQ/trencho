extends SceneTree
const RECOGNIZER = preload("res://scripts/systems/gesture_recognizer.gd")
var game: Node
var checks := 0
var failed := false

func _initialize() -> void: call_deferred("run")
func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error("FAILED: " + label)
func frames(count: int = 3) -> void:
	for index in range(count): await physics_frame
func freeze() -> void:
	for unit in game.units: unit.set_physics_process(false)
func clear() -> void:
	game.command_ui.close_all()
	game.formation_manager.clear()
	for unit in game.units.duplicate(): unit.die()
	game.squad_commands.prune()
	game.planning.end()
	game.planning.advance(1)
func squad(kind: String, team: int, center: Vector2, count: int = 1) -> Array:
	var spec: Dictionary = game.card_catalog[kind].base_stats()
	spec.unit_type = kind
	spec.team = team
	spec.lane = 1
	spec.spawn_positions = []
	for index in range(count): spec.spawn_positions.append(center + Vector2(index * 180, 0))
	game.spawn_deployment(spec)
	freeze()
	return spec.squad.members.duplicate()
func loop(center: Vector2, radius: float, start_angle: float = 0) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(33): points.append(center + Vector2.from_angle(start_angle + TAU * index / 32) * radius)
	return points
func click(point: Vector2, shift: bool = false) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = point
	event.shift_pressed = shift
	return event
func run() -> void:
	root.size = Vector2i(1280, 900)
	game = load("res://main.tscn").instantiate()
	game.tuning = game.tuning.duplicate()
	game.tuning.enemy_enabled = false
	game.tuning.attack_interval_variance = 0
	game.tuning.move_speed_variance = 0
	root.add_child(game)
	current_scene = game
	game.set_process(false)
	game.set_physics_process(false)
	game.planning.set_process(false)
	await process_frame
	var commands = game.squad_commands
	var ui = game.command_ui
	var line := PackedVector2Array([Vector2(100,100), Vector2(140,108), Vector2(200,120)])
	check(RECOGNIZER.classify(line).command_type == "ADVANCE", "forgiving line recognizes Advance")
	check(RECOGNIZER.classify(loop(Vector2(350,350),80)).command_type == "DEFEND", "loop recognizes Defend")
	var stem := PackedVector2Array([Vector2(80,350),Vector2(140,350),Vector2(220,350)])
	stem.append_array(loop(Vector2(350,350),80,PI))
	var stem_result: Dictionary = RECOGNIZER.classify(stem)
	check(stem_result.command_type == "DEFEND" and stem_result.center.distance_to(Vector2(350,350)) < 5, "knob-to-loop stem preserves defense center")
	for bad in [PackedVector2Array(), PackedVector2Array([Vector2.ZERO,Vector2.ONE]), PackedVector2Array([Vector2(0,0),Vector2(80,0),Vector2(0,0),Vector2(80,0),Vector2(0,0)])]:
		check(not RECOGNIZER.classify(bad).success, "tiny or ambiguous strokes fail rather than guess")
	var first: Array = squad("rifle_squad",2,Vector2(2800,3500),3)
	var second: Array = squad("assault_squad",2,Vector2(3500,3500),2)
	check(first[0].squad == first[2].squad and first[0].squad != second[0].squad, "deployment owns a persistent distinct squad")
	ui._input(click(game.get_canvas_transform()*first[0].position))
	check(commands.selected_ids == [first[0].squad.squad_id] and first[2].squad.selected, "clicking a soldier selects the entire squad")
	check(not game.planning.active and Engine.time_scale == 1, "selection alone never slows the game")
	ui._input(click(game.get_canvas_transform()*second[0].position,true))
	check(commands.selected_ids.size() == 2, "Shift click adds a distinct squad")
	ui._input(InputEventKey.new())
	check(commands.selected_ids.size() == 2, "releasing Shift does not clear selection")
	var expected_centroid: Vector2 = (first[0].position+first[1].position+first[2].position+second[0].position+second[1].position)/5
	check(commands.centroid().is_equal_approx(expected_centroid), "centroid averages all selected living soldiers")
	commands.select_unit(second[0],true)
	check(commands.selected_ids.size() == 1, "Shift click toggles an existing squad off")
	commands.select_unit(first[0])
	check(commands.selected_ids.is_empty(), "click selected squad toggles it off")
	commands.select_unit(first[0])
	commands.select_unit(second[0],true)
	var defense: Dictionary = commands.issue_selected("DEFEND",Vector2(3200,3300),10)
	check(defense.success and defense.expanded and defense.defense_radius > 10, "small circle expands to fit all survivors")
	check(first[0].squad.order_id == second[0].squad.order_id and first[0].squad.intent == "DEFEND", "separate squads share one defense order")
	check(first[0].squad.squad_id != second[0].squad.squad_id, "shared defense does not merge identities")
	var all_positions: Array = first[0].squad.defense_positions.values()+second[0].squad.defense_positions.values()
	var separated := true
	for i in range(all_positions.size()):
		check(all_positions[i].distance_to(defense.defense_center)+game.tuning.unit_radius <= defense.defense_radius+0.01, "every defense body fits inside final circle")
		for j in range(i):
			if all_positions[i].distance_to(all_positions[j]) < game.tuning.unit_radius*2: separated = false
	check(separated, "shared defense positions do not overlap")
	var previous_order: int = first[0].squad.order_id
	var rejected: Dictionary = commands.issue_selected("DEFEND", Vector2(3200,500),500)
	check(not rejected.success and rejected.failure_reason == "INVALID_DEFEND_LOCATION", "circle overlapping enemy No-Hold Zone fails")
	check(first[0].squad.order_id == previous_order and commands.selected_ids.size() == 2, "failed order preserves previous intent and selection")
	check(not commands.defense_plan(2,5,Vector2(30,3500),500).success, "circle crossing map boundary fails")
	check(not commands.defense_plan(2,50000,Vector2(3200,3500),500).success, "impossible packing fails within bounded maximum radius")
	ui.begin_gesture(ui.knob_position())
	ui.cancel_current()
	check(first[0].squad.intent=="DEFEND" and first[0].squad.order_id==previous_order and commands.selected_ids.size()==2,"gesture cancellation preserves existing shared Defend order")
	ui.cancel_current()
	check(first[0].squad.intent=="DEFEND" and commands.selected_ids.is_empty(),"selection cancellation does not silently switch defenders to Advance")
	commands.select_unit(first[0])
	commands.select_unit(second[0],true)
	check(not commands.defense_plan(1,1,Vector2(3200,game.field_size.y-100),300).success,"enemy Defend obeys the mirrored No-Hold rule")
	var advanced: Dictionary = commands.issue_selected("ADVANCE")
	check(advanced.success and first[0].squad.intent == "ADVANCE" and first[0].squad.defense_radius == 0, "Advance clears defense data for every selected squad")
	var no_reform: Vector2 = first[0].position
	first[1].die()
	commands.tick()
	check(first[0].position == no_reform and first[0].squad.defense_positions.is_empty(), "Advance does not re-form after casualties")
	check(commands.selected_ids.size() == 2, "partial casualties preserve selection")
	ui.begin_gesture(ui.knob_position())
	game.planning.advance(0.125)
	check(Engine.time_scale > 0.4 and Engine.time_scale < 1 and game.planning.effect.visible, "planning interpolates rather than snaps")
	game.planning.advance(1)
	check(is_equal_approx(Engine.time_scale,0.4), "planning reaches configured speed")
	ui.stroke = PackedVector2Array([Vector2(200,200),Vector2(201,201)])
	var bad: Dictionary = ui.finish_gesture()
	check(not bad.success and bad.failure_reason == "UNRECOGNIZED_GESTURE" and first[0].squad.intent == "ADVANCE", "ambiguous input preserves previous intent")
	check(commands.selected_ids.size() == 2, "failed gesture keeps selection for retry")
	ui.begin_gesture(ui.knob_position())
	ui.cancel_current()
	check(not ui.gesture_active and commands.selected_ids.size() == 2 and not game.planning.active, "right-click during gesture cancels only the gesture")
	game.planning.advance(1)
	check(Engine.time_scale == 1 and not game.planning.effect.visible, "cancel restores speed and saturation")
	ui.cancel_current()
	check(commands.selected_ids.is_empty() and first[0].squad.intent == "ADVANCE", "right-click at selection level only clears selection")
	commands.select_unit(first[0])
	commands.select_unit(second[0],true)
	ui.begin_gesture(ui.knob_position())
	for unit in first.duplicate():
		if is_instance_valid(unit) and unit.is_alive(): unit.die()
	check(commands.selected_ids.size() == 1, "destroyed squad is removed while other selected squad survives")
	for unit in second.duplicate(): unit.die()
	ui._process(0.1)
	check(commands.selected_ids.is_empty() and not ui.gesture_active and not game.planning.active and ui.failure_reason == "SQUAD_DESTROYED", "all selected casualties terminate command safely")
	clear()
	await frames()
	# A defender fights en route and returns fire across the territory boundary,
	# repositions only inside the circle and returns after combat/casualties.
	var defenders: Array = squad("rifle_squad",2,Vector2(3000,4300),3)
	commands.select_unit(defenders[0])
	defense = commands.issue_selected("DEFEND",Vector2(3200,3200),650)
	var enemy: Unit = squad("rifle_squad",1,Vector2(3000,3900))[0]
	await frames()
	defenders[0]._physics_process(1.0/60)
	check(defenders[0].state == Unit.State.ENGAGING and enemy.current_health < 100, "soldier can fight immediate threats while moving to Defend")
	enemy.die()
	await frames()
	for unit in defenders:
		unit.position = unit.squad.defense_positions[unit.squad_member_index]
		unit._physics_process(1.0/60)
	check(defenders[0].state == Unit.State.DEFENDING and defenders[0].defense_established, "arrived soldier establishes defense")
	var home: Vector2 = defenders[0].squad.defense_positions[defenders[0].squad_member_index]
	enemy = squad("rifle_squad",1,Vector2(3200,2500))[0]
	defenders[0].position = Vector2(3200,2700)
	await frames()
	check(defenders[0].nearest_enemy() == enemy, "established defense targets in-range enemies outside its territory")
	var firing_position: Vector2 = defenders[0].position
	defenders[0]._physics_process(1.0/60)
	check(defenders[0].state == Unit.State.ENGAGING and defenders[0].position == firing_position, "defender fires outside its territory without pursuing")
	enemy.die()
	await frames()
	defenders[0].position = home
	var distant_enemy: Unit = squad("rifle_squad",1,Vector2(3200,3700))[0]
	await frames()
	var before: Vector2 = defenders[0].position
	defenders[0]._physics_process(1.0/60)
	check(defenders[0].position.distance_to(defense.defense_center)+game.tuning.unit_radius <= defense.defense_radius+0.1, "defensive reposition remains within leash")
	distant_enemy.die()
	defenders[1].die()
	commands.tick()
	check(defenders[0].state == Unit.State.RETURNING_TO_DEFENSE, "survivors re-form after pressure ends")
	await frames()
	var return_home: Vector2 = defenders[0].squad.defense_positions[defenders[0].squad_member_index]
	defenders[0].position = return_home + Vector2(40,0)
	before = defenders[0].position
	defenders[0]._physics_process(1.0/60)
	check(defenders[0].position.distance_to(return_home)<before.distance_to(return_home), "defender returns toward assigned home")
	commands.issue_selected("ADVANCE")
	check(defenders[0].state == Unit.State.ADVANCING and not defenders[0].defense_established, "re-commanding clears the shield/move-to-defend state")
	clear()
	await frames()
	# Blueprint and final order commit must be one atomic purchase.
	var rifle: BattleCard = game.card_catalog.rifle_squad
	game.hand.cards.assign([rifle, game.card_catalog.commander_mojo, rifle, rifle, rifle])
	game.hand._toggle_card(0)
	game.economies[2].current_command = 10
	var initial_cards: Array = game.hand.cards.duplicate()
	ui.open_blueprint(Vector2(3000,3500))
	check(ui.blueprint.visible and game.planning.active and game.economies[2].current_command == 10, "blueprint begins planning without spending")
	var initial_width: float = ui.blueprint_width
	var corner: Vector2 = ui.blueprint_preview.global_position+ui.blueprint_box.end
	ui._input(click(corner))
	var resize_motion := InputEventMouseMotion.new()
	resize_motion.position = corner+Vector2(30,20)
	ui._input(resize_motion)
	var resize_release := click(resize_motion.position)
	resize_release.pressed = false
	ui._input(resize_release)
	check(ui.blueprint_width>initial_width and not ui.blueprint_resizing,"blueprint corner handle resizes and releases cleanly")
	ui.blueprint_width = 140
	ui.blueprint_depth = 140
	ui.set_blueprint_size(ui.blueprint_width,ui.blueprint_depth)
	ui.confirm_blueprint()
	check(ui.blueprint.visible and not ui.pending_ready and game.hand.cards == initial_cards, "undersized blueprint cannot progress or consume cards")
	ui.blueprint_width = 940
	ui.blueprint_depth = 460
	ui.set_blueprint_size(ui.blueprint_width,ui.blueprint_depth)
	ui.confirm_blueprint()
	check(not ui.blueprint.visible and ui.pending_ready and game.formation_manager.pending.is_empty(), "blueprint confirmation waits for initial command")
	ui.begin_gesture(ui.knob_position())
	ui.stroke = PackedVector2Array([Vector2.ZERO,Vector2.ONE])
	ui.finish_gesture()
	check(game.hand.cards == initial_cards and game.economies[2].current_command == 10, "failed initial gesture spends nothing")
	ui.cancel_current()
	check(not ui.pending_ready and game.hand.cards == initial_cards and game.economies[2].current_command == 10, "cancel before final order spends nothing")
	ui.open_blueprint(Vector2(3000,3500))
	ui.confirm_blueprint()
	ui.begin_gesture(ui.knob_position())
	ui.stroke = line.duplicate()
	var committed: Dictionary = ui.finish_gesture()
	check(committed.success and game.economies[2].current_command == 7 and game.hand.selected_indices.is_empty(), "valid initial Advance commits once")
	check(game.formation_manager.pending.size() == 6 and game.formation_manager.pending[0].specification.squad.intent == "ADVANCE", "new squad receives intent before spawning")
	check(not game.planning.active and ui.feedback.size()>0, "success produces feedback and exits planning")
	clear()
	await frames()
		# Initial Defend validates before spending and includes queued members.
	game.hand.cards.assign([rifle, game.card_catalog.commander_mojo, rifle, rifle, rifle])
	game.hand._toggle_card(0)
	game.economies[2].current_command = 10
	ui.open_blueprint(Vector2(3200,3500))
	ui.confirm_blueprint()
	ui.begin_gesture(ui.knob_position())
	var invalid_screen: Vector2 = game.get_canvas_transform()*Vector2(3200,300)
	ui.stroke = loop(invalid_screen,60)
	var invalid_initial: Dictionary = ui.finish_gesture()
	check(not invalid_initial.success and game.economies[2].current_command == 10 and game.formation_manager.pending.is_empty() and ui.pending_ready, "invalid initial Defend keeps setup and resources for retry")
	ui.begin_gesture(ui.knob_position())
	var defense_screen: Vector2 = game.get_canvas_transform()*Vector2(3200,3500)
	ui.stroke = loop(defense_screen,45)
	var initial_defense: Dictionary = ui.finish_gesture()
	check(initial_defense.success and initial_defense.command_type == "DEFEND" and game.economies[2].current_command == 7, "initial Defend commits only after full area validation")
	var queued_squad: BattleSquad = game.formation_manager.pending[0].specification.squad
	check(queued_squad.intent == "DEFEND" and queued_squad.defense_positions.size() == 6, "queued soldiers already have a defense intent and home positions")
	game.formation_manager.tick(0.2)
	freeze()
	check(game.units.size()>0 and game.units[0].squad == queued_squad, "spawning retains initial Defend squad identity")
	var first_defender: Unit = game.units[0]
	first_defender._physics_process(1.0/60)
	check(first_defender.state == Unit.State.MOVING_TO_DEFEND and not first_defender.has_entered_battlefield, "new defender starts its trip directly from off-screen")
	clear()
	await frames()
	# Genuine mouse event routing must open setup and accept a knob gesture.
	game.hand.cards.assign([rifle, rifle, rifle, rifle, rifle])
	game.hand._toggle_card(0)
	game.economies[2].current_command = 10
	var setup_click := click(game.battlefield_view_rect().get_center()+Vector2(180,100))
	Input.parse_input_event(setup_click)
	Input.flush_buffered_events()
	await process_frame
	check(ui.blueprint.visible and not game.hand.drawing_footprint, "live mouse routing opens blueprint instead of the retired deployment rectangle")
	ui.confirm_blueprint()
	var knob: Vector2 = ui.knob_position()
	Input.parse_input_event(click(knob))
	Input.flush_buffered_events()
	await process_frame
	check(ui.gesture_active and game.planning.active, "live knob press starts command planning")
	var motion := InputEventMouseMotion.new()
	motion.position = knob+Vector2(110,-15)
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	var release := click(motion.position)
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	await process_frame
	check(not ui.gesture_active and not ui.pending_ready and game.formation_manager.pending.size() == 6, "live gesture release commits and clears the command tool")
	clear()
	await frames()
	# Interrupted setup cannot strand slow motion or accidentally commit.
	game.hand.cards.assign([rifle, rifle, rifle, rifle, rifle])
	game.hand._toggle_card(0)
	game.economies[2].current_command = 10
	ui.open_blueprint(Vector2(3200,3500))
	ui.cancel_current()
	check(not ui.blueprint.visible and not game.planning.active and game.economies[2].current_command == 10 and game.hand.selected_indices == [0], "blueprint cancel preserves cards and leaves planning")
	ui.open_blueprint(Vector2(3200,3500))
	ui.confirm_blueprint()
	game.economies[2].current_command = 0
	ui.begin_gesture(ui.knob_position())
	ui.stroke = line.duplicate()
	var late_funds: Dictionary = ui.finish_gesture()
	check(not late_funds.success and late_funds.failure_reason == "INSUFFICIENT_COMMAND" and game.formation_manager.pending.is_empty(), "resources are revalidated at final commit")
	clear()
	await frames()
	# New Advance never uses old area occupancy/exclusion as a veto.
	game.economies[2].current_command = 10
	var blocker: Unit = squad("rifle_squad",1,Vector2(2000,2200))[0]
	var deployed: Dictionary = game.deployment_manager.request_squad(2,[rifle],Rect2(1800,2000,940,140),"ADVANCE")
	check(deployed.is_valid, "new deployment is not restricted to old deployment zones or enemy exclusion")
	check(game.player_deployment_confirmed, "valid intent-first deployment opens enemy startup gate")
	game.economies[1].current_command = 0
	game.enemy_controller.decide()
	check(game.enemy_controller.last_decision.contains("insufficient Command"),"enemy debug distinguishes resource shortage from entry-space failure")
	clear()
	game.planning.advance(1)
	print("SQUAD COMMANDS: %d assertions, %s" % [checks,"FAILED" if failed else "PASSED"])
	quit(1 if failed else 0)
