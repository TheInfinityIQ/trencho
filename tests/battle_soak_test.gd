extends SceneTree
var accepted := {1: 0, 2: 0}
var deaths := 0
var goals := 0
var maximum_living := 0
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var game = load("res://main.tscn").instantiate()
	game.tuning = game.tuning.duplicate()
	root.add_child(game)
	current_scene = game
	game.deployment_accepted.connect(func(team, _spec): accepted[team] += 1)
	game.unit_died.connect(func(_unit): deaths += 1)
	game.unit_reached_goal.connect(func(_unit): goals += 1)
	var hand = game.hand
	for frame in range(60 * 180):
		await physics_frame
		maximum_living = maxi(maximum_living, game.units.size())
		if not game.battle_active:
			break
		# A repeatable test player chooses affordable cards and open lanes.
		if frame % 60 == 0:
			var deployed := false
			for index in range(hand.cards.size()):
				if hand.cards[index].card_type != BattleCard.Type.UNIT:
					continue
				for lane in range(3):
					var target_lane := (lane + int(frame / 60)) % 3
					if game.deployment_manager.validate_squad(2, [hand.cards[index]], game.preset_footprint(2,target_lane), "ADVANCE").is_valid:
						hand.cancel_selection()
						hand._toggle_card(index)
						var accepted_order: Dictionary = game.deployment_manager.request_squad(2,hand.selected_cards(),game.preset_footprint(2,target_lane),"ADVANCE")
						if accepted_order.is_valid: hand._consume(hand.selected_indices)
						deployed = true
						break
				if deployed:
					break
			if not deployed and not hand.cards.is_empty():
				hand.cancel_selection()
				hand._toggle_card(0)
				hand._discard_selected()
	var success: bool = accepted[1] > 5 and accepted[2] > 5 and deaths > 0 and goals > 0
	print("BATTLE SOAK: deployments=%s deaths=%d goals=%d peak_units=%d score=%s active=%s" % [accepted, deaths, goals, maximum_living, game.scores, game.battle_active])
	if not success:
		push_error("Sustained battle did not exercise expected combat and scoring")
	quit(0 if success else 1)
