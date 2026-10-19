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
func spawn(count: int, center: Vector2, team: int = 2) -> BattleSquad:
	var spec: Dictionary = game.card_catalog.rifle_squad.base_stats()
	spec.merge({"team":team,"unit_type":"rifle_squad","lane":1,"spawn_positions":[]},true)
	for index in range(count): spec.spawn_positions.append(center+Vector2(index%3,index/3)*160)
	game.spawn_deployment(spec)
	for unit in spec.squad.members: unit.set_physics_process(false)
	return spec.squad
func recognition(endpoint: Vector2, kind: String = "ADVANCE") -> Dictionary:
	var transform: Transform2D = game.get_canvas_transform()
	return {"success":true,"command_type":kind,"route":PackedVector2Array([transform*Vector2(endpoint.x,5000),transform*endpoint]),"center":transform*endpoint}
func run() -> void:
	game = load("res://main.tscn").instantiate()
	game.tuning = game.tuning.duplicate()
	game.tuning.enemy_enabled = false
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	game.set_process(false)
	game.planning.set_process(false)
	await physics_frame
	var commands = game.squad_commands
	var ui = game.command_ui
	game.get_node("Camera2D").zoom = Vector2.ONE*0.2
	game.get_node("Camera2D").force_update_scroll()
	var defenders := spawn(6,Vector2(2400,4500))
	var center := Vector2(3328,3500)
	var path := PackedVector2Array([Vector2(2600,4000),Vector2(3000,3500),Vector2(3400,3500)])
	check(commands.issue_group([defenders],"DEFEND",center,0,path).success,"Defend accepts ordinary approach")
	var point_id := defenders.order_id
	check(commands.orders[point_id].facing==Vector2.UP,"horizontal terminal stroke cannot rotate player front")
	for unit in defenders.members:
		unit.position = defenders.defense_positions[unit.squad_member_index]
		unit.defense_established = true
	commands.points.update(0,true)
	var non_anchor := Vector2.ZERO
	for cell in commands.orders[point_id].cells:
		var at: Vector2 = commands.points.position(cell)
		if at.distance_to(center)>commands.anchor_tolerance()*2:
			non_anchor=at
			break
	check(non_anchor!=Vector2.ZERO,"fixture has owned area outside visible shield")
	var movers := spawn(6,Vector2(4200,5000))
	commands.select_unit(movers.members[0])
	var preview: Dictionary = ui.preview_state(recognition(non_anchor))
	check(preview.valid and preview.target_id==-1 and preview.text.contains("Advance"),"owned area without shield previews Advance")
	var response: Dictionary = commands.issue_selected("ADVANCE",Vector2.ZERO,0,PackedVector2Array([center,non_anchor]))
	check(response.success and movers.intent=="ADVANCE" and movers.order_id==-1,"crossing shield and ending elsewhere in territory remains Advance")
	var tolerance: float = commands.anchor_tolerance()
	check(commands.reinforcement_target(2,center+Vector2(tolerance-0.1,0))==point_id,"inside selectable shield radius is deliberate reinforcement")
	check(commands.reinforcement_target(2,center+Vector2(tolerance+0.1,0))==-1,"outside shield radius is never broad territory reinforcement")
	preview = ui.preview_state(recognition(center))
	check(preview.valid and preview.target_id==point_id and preview.text.contains("Reinforce") and preview.text.contains("RESERVE"),"shield previews Reinforce and reserve classification before release")
	var predicted: Array = preview.front_plan.proposed_blocks[0].slots.map(func(slot): return slot.home)
	response = commands.issue_selected("ADVANCE",Vector2.ZERO,0,PackedVector2Array([center]))
	check(response.success and response.reinforcement and movers.order_id==point_id,"shield release resolves the previewed Reinforce")
	check(movers.defense_positions.values()==predicted,"preview homes and committed homes agree")
	game.get_node("Camera2D").zoom=Vector2.ONE*0.1
	check(commands.reinforcement_target(2,center+Vector2(100,0))==point_id,"shield tolerance follows zoomed-out selectable size")
	game.get_node("Camera2D").zoom=Vector2.ONE*0.4
	check(commands.reinforcement_target(2,center+Vector2(100,0))==-1,"zoomed-in shield does not retain giant world-space hitbox")
	var inbound := spawn(1,Vector2(5200,5500))
	commands.issue_group([inbound],"DEFEND",Vector2(5200,4500))
	check(commands.reinforcement_target(2,Vector2(5200,4500))==inbound.order_id,"visible inbound anchor is an intentional reinforcement destination")
	var enemy := spawn(1,Vector2(1500,1300),1)
	commands.issue_group([enemy],"DEFEND",Vector2(1500,2300))
	check(commands.reinforcement_target(2,Vector2(1500,2300))==-1,"enemy shield cannot receive player reinforcements")
	# Broad approach sectors are independent of the endpoint's shield intent.
	game.get_node("Camera2D").zoom=Vector2.ONE*0.2
	game.get_node("Camera2D").force_update_scroll()
	var flankers := spawn(6,Vector2(5800,5100))
	commands.clear_selection()
	commands.select_unit(flankers.members[0])
	var before_blocks: String = str(commands.orders[point_id].blocks)
	for sector in [-1,0,1]:
		var approach := PackedVector2Array([center+Vector2(sector*1000,700),center])
		var rec: Dictionary = recognition(center)
		rec.route = PackedVector2Array([game.get_canvas_transform()*approach[0],game.get_canvas_transform()*center])
		var sector_preview: Dictionary = ui.preview_state(rec)
		var expected: String = "LEFT" if sector<0 else ("RIGHT" if sector>0 else "CENTER")
		check(sector_preview.valid and sector_preview.front_plan.preferred_sector==expected,"full gesture start survives stripped movement route for "+expected)
		check(sector_preview.text.contains(expected),"preview discloses broad sector "+expected)
		if sector!=0: check(sector_preview.front_plan.proposed_blocks[0].role=="FRONT","flank approach retains contiguous extension targeting")
	check(str(commands.orders[point_id].blocks)==before_blocks,"sector previews never move or mutate established blocks")
	var short_preference: Vector2 = commands.reinforcement_preference(point_id,PackedVector2Array([center+Vector2(50,0),center]))
	check(absf(commands.fronts.local(commands.orders[point_id],short_preference).x)<1,"short ambiguous approach defaults center")
	var bend := PackedVector2Array([center+Vector2(-1500,2000),center+Vector2(900,0),center])
	check(commands.fronts.local(commands.orders[point_id],commands.reinforcement_preference(point_id,bend)).x>0,"recent approach takes priority over distant gesture origin")
	var left_approach := PackedVector2Array([center+Vector2(-1000,700),center])
	var left_preview: Dictionary = commands.fronts.plan([flankers],center,PackedVector2Array([center]),point_id,Vector2.ZERO,commands.reinforcement_preference(point_id,left_approach))
	var left_homes: Array = left_preview.proposed_blocks[0].slots.map(func(slot): return slot.home)
	response = commands.issue_selected("ADVANCE",center,0,PackedVector2Array([center]),left_approach)
	check(response.success and flankers.defense_positions.values()==left_homes,"selected flank commit agrees exactly with pure sector preview")
	game.economies[2].current_command=10
	var purchase_cards: Array = [game.card_catalog.rifle_squad]
	var purchase_size: Vector2 = game.deployment_manager.default_blueprint_size(6)
	var rectangle := Rect2(Vector2(2500,0),purchase_size)
	var right_approach := PackedVector2Array([center+Vector2(1000,700),center])
	var purchase: Dictionary = game.deployment_manager.validate_squad(2,purchase_cards,rectangle,"ADVANCE",center,0,PackedVector2Array([center]),right_approach)
	check(purchase.is_valid and purchase.defense_plan.preferred_sector=="RIGHT","purchased reinforcements share approach preference")
	var purchase_homes: Array = purchase.defense_plan.proposed_blocks[0].slots.map(func(slot): return slot.home)
	var bought: Dictionary = game.deployment_manager.request_squad(2,purchase_cards,rectangle,"ADVANCE",center,0,PackedVector2Array([center]),right_approach)
	check(bought.is_valid and bought.defense_plan.proposed_blocks[0].slots.map(func(slot): return slot.home)==purchase_homes,"queued purchase homes match preview exactly")
	# Every current affordable legal package, including repeated modifiers.
	game.economies[2].current_command=10
	var catalog: Array = game.card_catalog.values()
	var packages := 0
	for first in catalog:
		for second_index in range(-1,catalog.size()):
			for third_index in range(-1,catalog.size()):
				if second_index<0 and third_index>=0: continue
				var cards: Array = [first]
				if second_index>=0: cards.append(catalog[second_index])
				if third_index>=0: cards.append(catalog[third_index])
				var package: Dictionary = game.deployment_manager.resolve_package(cards)
				if not package.is_valid or package.total_cost>10: continue
				var size: Vector2 = game.deployment_manager.default_blueprint_size(package.resolved_deployment.quantity)
				var valid: Dictionary = game.deployment_manager.validate_squad(2,cards,Rect2(Vector2(2500,0),size),"ADVANCE")
				check(valid.is_valid,"automatic blueprint fits legal package %s" % str(cards.map(func(card): return card.card_id)))
				packages += 1
	check(packages>50,"automatic formation validation covers combinations, quantities and modifier repeats")
	game.hand.cards.assign([game.card_catalog.conscript_wave,game.card_catalog.conscript_wave,game.card_catalog.commander_mojo])
	game.hand.selected_indices.assign([0,1,2])
	ui.blueprint_width=140
	ui.blueprint_depth=140
	ui.open_blueprint(Vector2(3328,4000))
	check(not ui.confirm_button.disabled and ui.capacity_label.text.contains("48 soldiers"),"largest legal package opens with immediately usable default despite prior small manual shape")
	ui.set_blueprint_size(140,140)
	ui._process(0)
	check(ui.confirm_button.disabled and ui.blueprint_width==140,"optional manual editing is preserved while open")
	ui.cancel_current()
	var events: Array = game.telemetry.data.events
	check(events.any(func(event): return event.type=="COMMAND_INTERPRETATION" and event.final_command=="REINFORCE"),"command telemetry distinguishes reinforcement")
	print("CONSOLIDATION COMMANDS: %d assertions, %s" % [checks,"FAILED" if failed else "PASSED"])
	quit(1 if failed else 0)
