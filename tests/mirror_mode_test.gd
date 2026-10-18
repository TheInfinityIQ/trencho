extends SceneTree
var checks := 0
var failed := false
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error("FAILED: "+label)
func soldier(game: Node, team: int, position: Vector2) -> Unit:
	var spec: Dictionary = game.card_catalog.rifle_squad.base_stats()
	spec.merge({"team":team,"lane":1,"unit_type":"rifle_squad","spawn_positions":[position]},true)
	game.spawn_deployment(spec)
	var unit: Unit = game.units[-1]
	unit.set_physics_process(false)
	return unit
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	game.match_options = {"mirror":true,"presentation":false,"seed":7731,"doctrines":["LINE","TRIANGLE"]}
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	check(game.player_controller != null and game.player_deployment_confirmed,"Both AI start automatically")
	check(game.enemy_controller.team == 1 and game.player_controller.team == 2,"Same controller supports both sides")
	check(game.enemy_controller.doctrine == "LINE" and game.player_controller.doctrine == "TRIANGLE","Requested doctrine pairing")
	check(game.economies[1].maximum_command == game.economies[2].maximum_command and game.economies[1].current_command == game.economies[2].current_command and game.economies[1].command_regeneration_rate == game.economies[2].command_regeneration_rate,"Mirror economy is equal")
	for index in range(12):
		var first: Array = game.enemy_controller.next_package().map(func(card): return card.card_id)
		var second: Array = game.player_controller.next_package().map(func(card): return card.card_id)
		check(first == second,"Identical AI package policy and seeded random stream")
	var loser := soldier(game,1,Vector2(1800,2200))
	var winner := soldier(game,2,Vector2(4200,4400))
	game.squad_commands.issue_group([loser.squad],"DEFEND",loser.position)
	game.squad_commands.issue_group([winner.squad],"DEFEND",winner.position)
	game.economies[1].current_command = 10
	game.deployment_manager.request_squad(1,[game.card_catalog.rifle_squad],game.preset_footprint(1,0),"ADVANCE")
	check(not game.formation_manager.pending.is_empty(),"Surrender fixture includes queued soldiers")
	game.surrender(1)
	check(game.surrendered_team == 1 and game.telemetry.data.match.forced_surrender.team == 1,"Forced surrender is explicit in export")
	check(game.units.size() == 1 and game.units[0] == winner,"Surrender withdraws only losing soldiers")
	check(game.formation_manager.pending.is_empty(),"Surrender cancels losing queued soldiers")
	check(game.scores[1] == 0 and game.scores[2] == 0,"Withdrawal does not fabricate objective score")
	check(game.deaths_by_team[1] == 0,"Withdrawal does not fabricate combat deaths")
	check(winner.squad.intent == "ADVANCE" and game.player_controller.advance_only,"Winner releases its defense and advances")
	check(game.telemetry.soldiers[loser.telemetry_id].record.end_reason == "surrendered","Withdrawal reason preserved")
	winner.position.y = 0
	game.score_unit(winner)
	check(game.scores[2] == winner.score_value,"Victorious side scores through normal objective rule")
	game.finish_battle(2,"mirror fixture")
	check(not game.telemetry.export_path.is_empty(),"Mirror match exports normal combat log")
	check(game.telemetry.data.match.test_configuration.mirror,"Export labels mirror conditions")
	var pairs: Array = preload("res://scripts/systems/mirror_batch.gd").PAIRS
	check(pairs == [["LINE","LINE"],["LINE","TRIANGLE"],["TRIANGLE","TRIANGLE"]],"Exactly the requested three doctrine matchups")
	print("MIRROR MODE: %d assertions, %s" % [checks,"FAILED" if failed else "PASSED"])
	quit(1 if failed else 0)
