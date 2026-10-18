extends SceneTree
## Short deterministic contact fixture for comparing rendered/headless physics.
const IO = preload("res://scripts/systems/mirror_io.gd")
var game: Node
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var options := IO.arguments()
	game = load("res://main.tscn").instantiate()
	game.match_options = {"mirror":true,"presentation":options.get("presentation","false") == "true",
		"seed":42,"doctrines":["LINE","TRIANGLE"],"probe_fixture":true}
	root.add_child(game)
	current_scene = game
	for team in [1,2]:
		for kind_index in range(3):
			var kind: String = ["rifle_squad","conscript_wave","assault_squad"][kind_index]
			var card: Resource = game.card_catalog[kind]
			var spec: Dictionary = card.base_stats()
			spec.merge({"team":team,"lane":1,"unit_type":kind,"source_cards":[card],"spawn_positions":[]},true)
			for index in range(card.quantity):
				spec.spawn_positions.append(Vector2(1700+kind_index*1500+(index%6)*180,3000 if team == 1 else 3550)+(Vector2(0,-180 if team == 1 else 180)*(index/6)))
			game.spawn_deployment(spec)
	while game.simulation_time < 10: await physics_frame
	var worker = preload("res://scripts/systems/mirror_match_worker.gd").new()
	worker.game = game
	var snapshot: Dictionary = worker.state_snapshot()
	worker.free()
	snapshot.deaths = game.deaths_by_team
	var damage := 0.0
	var closing := 0.0
	for record in game.telemetry.data.soldiers:
		damage += record.damage_dealt
		closing += record.time_closing_to_range
	snapshot.damage = damage
	snapshot.closing_time = closing
	var result := {"snapshot":snapshot,"sha256":JSON.stringify(snapshot).sha256_text()}
	if not IO.write_json(options.get("result","user://mirror_parity_probe.json"),result):
		push_error("Could not save parity probe")
		quit(1)
		return
	if damage <= 0 or closing <= 0 or game.deaths_by_team[1]+game.deaths_by_team[2] <= 0:
		push_error("Parity fixture did not exercise damage, deaths and tactical closing")
		quit(1)
		return
	print("MIRROR PARITY PROBE: ",result.sha256," damage=",damage," closing_seconds=",closing)
	quit()
