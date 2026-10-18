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
func soldier(center: Vector2, squad: BattleSquad = null) -> Unit:
	var spec: Dictionary = game.card_catalog.rifle_squad.base_stats()
	spec.merge({"team":2,"unit_type":"rifle_squad","lane":1,"spawn_positions":[center]},true)
	if squad != null: spec.squad = squad
	game.spawn_deployment(spec)
	var unit: Unit = game.units[-1]
	unit.squad_member_index = unit.squad.members.size()-1
	unit.set_physics_process(false)
	return unit
func recognition(kind: String, endpoint: Vector2) -> Dictionary:
	var transform: Transform2D = game.get_canvas_transform()
	return {"success":true,"command_type":kind,"route":PackedVector2Array([transform*Vector2(3200,5200),transform*endpoint]),"center":transform*endpoint}
func run() -> void:
	root.size = Vector2i(1280,800)
	game = load("res://main.tscn").instantiate()
	game.tuning = game.tuning.duplicate()
	game.tuning.enemy_enabled = false
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	game.set_process(false)
	game.planning.set_process(false)
	await process_frame
	var hand = game.hand
	var ui = game.command_ui
	var commands = game.squad_commands
	game.economies[2].current_command = 10
	hand.cards.assign([game.card_catalog.rifle_squad,game.card_catalog.assault_squad,game.card_catalog.commander_mojo])
	hand._toggle_card(0)
	hand._toggle_card(1)
	check(hand.package_description().contains("Cost 7") and not hand.package_description().contains("3 -> 7"),"two-Unit cost is the total, not the first Unit's cost")
	check(hand.package_description().contains("10 soldiers"),"mixed quantity matches resolver")
	hand._toggle_card(2)
	check(hand.package_description().contains("20 soldiers (10 base)") and hand.package_description().contains("Cost 10"),"modifier updates mixed quantity and total cost")
	check(hand.package_details().contains("Front priority: Rifle Squad ×12") and hand.package_details().contains("Rear priority: Assault Squad ×8"),"component priorities and modified quantities stay distinct")
	check(hand.package_details().contains("100 HP") and hand.package_details().contains("225 HP"),"mixed stats are shown per component")
	game.economies[2].current_command = 3
	check(hand.package_description().contains("Need 7.0 more"),"affordability is explicit without blocking selection")
	var stable_details: String = hand.package_details()
	game.economies[2].current_command = 3.1
	check(hand.package_details() == stable_details,"regeneration does not reset inspectable component tooltip content")
	hand.cards.append(game.card_catalog.conscript_wave)
	hand._toggle_card(3)
	check(ui.context_text().contains("Maximum three cards"),"card selection rejection remains visible in the new contextual strip")
	ui.open_blueprint(Vector2(3000,5500))
	check(ui.blueprint.visible and ui.confirm_button.disabled,"unaffordable setup remains inspectable")
	game.economies[2].current_command = 10
	ui.set_blueprint_size(40,40)
	check(ui.confirm_button.disabled and ui.capacity_label.text.contains("Needs 20 spaces"),"undersized blueprint explains capacity")
	var before: float = game.economies[2].current_command
	ui.confirm_blueprint()
	check(ui.blueprint.visible and not ui.pending_ready and game.economies[2].current_command == before,"Enter/direct confirm cannot bypass capacity or spend")
	ui.set_blueprint_size(1900,900)
	check(not ui.confirm_button.disabled and ui.capacity_label.text.contains("20 soldiers /"),"resizing recovers without automatic shape changes")
	ui.confirm_blueprint()
	check(ui.pending_ready and not ui.blueprint.visible and game.economies[2].current_command == before,"formation confirmation spends nothing")
	ui.begin_gesture(ui.knob_position())
	ui.stroke = PackedVector2Array([ui.knob_position(),ui.knob_position()+Vector2.ONE])
	check(not ui.finish_gesture().success,"incomplete gesture safely rejected")
	ui.feedback.clear()
	check(ui.context_text().contains("Retry") and ui.context_text().contains("unspent"),"actionable recovery survives floating cue removal")
	var previous_notice: String = ui.notice
	ui._on_result(commands.result(false,"ADVANCE","POSITION_UNREACHABLE"))
	check(ui.notice == previous_notice,"unrelated system orders cannot overwrite player recovery")
	check(ui.pending_ready and game.economies[2].current_command == before and hand.selected_indices.size() == 3,"failure preserves setup, cards and Command")
	ui.cancel_current()
	check(ui.feedback.is_empty(),"cancelling stale context removes old floating rejection cues")
	hand.cancel_selection()
	var first := soldier(Vector2(3000,4100))
	var partial := soldier(Vector2(3250,4100))
	var partial_arrival := soldier(Vector2(3250,5200),partial.squad)
	var inbound := soldier(Vector2(3500,5200))
	var accepted: Dictionary = commands.issue_group([first.squad,partial.squad,inbound.squad],"DEFEND",Vector2(3200,4000))
	check(accepted.success,"real point fixture accepts defense")
	first.defense_established = true
	partial.defense_established = true
	partial_arrival.defense_established = false
	inbound.defense_established = false
	commands.points.update(0,true)
	commands.select_point(first.squad.order_id)
	check(commands.selected_ids.size() == 2 and not commands.selected_ids.has(inbound.squad.squad_id),"point selects established and partial squads, excluding entirely inbound squads")
	check(ui.selection_text().contains("2 squads · 3 living selected"),"selected living count includes members of partially established squads")
	check(ui.context_details().contains("inbound (not all inbound squads selected)"),"point population is distinguished from selected population")
	var id: int = first.squad.order_id
	var center: Vector2 = commands.orders[id].center
	var orders_before := var_to_str(commands.orders)
	var selected_before: Array = commands.selected_ids.duplicate()
	var preview: Dictionary = ui.preview_state(recognition("ADVANCE",center))
	check(preview.valid and preview.target_id == id and preview.text.contains("Reinforce"),"open endpoint previews the actual friendly reinforcement target")
	var loop: Dictionary = ui.preview_state(recognition("DEFEND",center))
	check(loop.target_id == -1 and not loop.text.contains("Reinforce"),"terminal loop never masquerades as reinforcement")
	var illegal: Dictionary = ui.preview_state(recognition("DEFEND",Vector2(3200,10)))
	check(not illegal.valid and illegal.text.contains("No-Hold"),"illegal defense explains the prohibition before release")
	check(var_to_str(commands.orders) == orders_before and commands.selected_ids == selected_before and game.economies[2].current_command == before,"predictions never mutate orders, selection or resources")
	var reinforcement: Dictionary = commands.issue_selected("ADVANCE",Vector2.ZERO,0,PackedVector2Array([center]))
	check(reinforcement.success and first.squad.order_id == preview.target_id,"release acceptance agrees with reinforcement preview")
	game.hud.controls_help.visible = true
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	var ids_before: Array = commands.selected_ids.duplicate()
	ui._input(right)
	check(not game.hud.controls_help.visible and commands.selected_ids == ids_before,"right-click closes help before touching tactical selection")
	for resolution in [Vector2i(960,700),Vector2i(1280,800),Vector2i(1920,1080)]:
		root.size = resolution
		await process_frame
		await process_frame
		game.hud._layout()
		var viewport_width: float = hand.get_viewport_rect().size.x
		check(game.hud.camera_toolbar.get_global_rect().end.x <= viewport_width,"toolbar fits scaled viewport at " + str(resolution))
		check(hand.package_label.get_global_rect().end.x <= viewport_width and hand.context_label.get_global_rect().end.x <= viewport_width,"bounded summary fits scaled viewport at " + str(resolution))
		game.hud.controls_help.visible = true
		check(not game._camera_point_allowed(game.hud.controls_help.global_position+Vector2(25,25)),"controls help blocks battlefield input " + str(resolution))
		game.hud.controls_help.visible = false
	ui.close_all()
	print("UI CLARITY: %d assertions, %s" % [checks,"FAILED" if failed else "PASSED"])
	quit(1 if failed else 0)
