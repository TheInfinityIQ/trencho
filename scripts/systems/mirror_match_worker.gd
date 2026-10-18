extends Node
## Runs the actual battle scene through Godot's normal 60 Hz physics loop.
const IO = preload("res://scripts/systems/mirror_io.gd")
var game: Node
var options: Dictionary
var started := Time.get_ticks_msec()
var last_status := 0
var surrender_time := -1.0
var done := false

func _ready() -> void:
	options = IO.arguments()
	Engine.max_fps = 0
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0
	game = load("res://main.tscn").instantiate()
	game.match_options = {"mirror":true,"presentation":options.get("presentation","false") == "true",
		"seed":int(options.get("seed",16102026)),"doctrines":[options.get("side-one","LINE"),options.get("side-two","LINE")],
		"runner":"normal_godot_physics","physics_hz":60,"surrender_limit_seconds":float(options.get("limit",1800))}
	add_child(game)
	write_status(false)

func _physics_process(_delta: float) -> void:
	if done: return
	if not game.battle_active:
		complete("natural" if surrender_time < 0 else "timeout_surrender")
		return
	var probe := float(options.get("probe",0))
	if probe > 0 and game.simulation_time >= probe:
		complete("parity_probe")
		return
	if surrender_time < 0 and game.simulation_time >= float(options.get("limit",1800)):
		surrender_time = game.simulation_time
		var team := 1 if game.scores[1] < game.scores[2] else 2
		if game.scores[1] == game.scores[2]: team = 1+int(options.get("seed",16102026))%2
		game.surrender(team)
	if surrender_time >= 0 and game.simulation_time-surrender_time > 120:
		game.finish_battle(3-game.surrendered_team,"Surrender resolution safety limit")
		complete("surrender_resolution_safety_limit")
		return
	var now := Time.get_ticks_msec()
	if now-last_status >= 500:
		last_status = now
		write_status(false)

func state_snapshot() -> Dictionary:
	var units: Array = []
	for unit in game.units:
		units.append([unit.simulation_id,unit.team_id,unit.unit_type,unit.position.x,unit.position.y,unit.current_health,unit.attack_remaining,unit.state,unit.squad.squad_id])
	return {"time":game.simulation_time,"scores":game.scores,"units":units,"unit_rng":str(game.unit_rng.state),
		"ai_rng":[str(game.enemy_controller.rng.state),str(game.player_controller.rng.state)],"pending":game.formation_manager.pending.size()}

func write_status(completed: bool, termination: String = "") -> void:
	var status := {"completed":completed,"termination":termination,"simulation_seconds":game.simulation_time,
		"real_seconds":(Time.get_ticks_msec()-started)/1000.0,"scores":game.scores,
		"winner":game.winner,"surrendered_team":game.surrendered_team,"living_soldiers":game.units.size(),
		"doctrines":game.match_options.doctrines,"seed":game.tuning.random_seed,
		"combat_log":ProjectSettings.globalize_path(game.telemetry.export_path) if not game.telemetry.export_path.is_empty() else ""}
	if completed:
		var snapshot := state_snapshot()
		status.snapshot_sha256 = JSON.stringify(snapshot).sha256_text()
		if termination == "parity_probe":
			status.snapshot = snapshot
			var entries: Array = []
			for unit in game.units:
				if unit.has_entered_battlefield or entries.size() >= 3: continue
				var next: Vector2 = unit.position+unit.direction_vector*unit.squad.strategic_speed/60.0
				var blockers: Array = []
				for other in game.units:
					if unit != other and other.position.distance_to(next) < game.tuning.unit_radius*2+2: blockers.append(other.simulation_id)
				entries.append({"id":unit.simulation_id,"position":[unit.position.x,unit.position.y],"velocity":[unit.velocity.x,unit.velocity.y],"can_move":game.formation_manager.can_move_to(next,unit),"terrain":game.formation_manager.terrain_blocks(next),"blockers":blockers,"strategic":unit.squad.strategic_speed})
			status.entry_diagnostics = entries
		status.summary = game.telemetry.data.summary
	var destination: String = options.get("result","user://mirror_probe.json")
	if not IO.write_json(destination,status):
		push_error("Could not write mirror match status: "+destination)
		get_tree().quit(2)

func complete(termination: String) -> void:
	done = true
	write_status(true,termination)
	print("MIRROR MATCH: ",termination," scores=",game.scores," simulation_seconds=",game.simulation_time)
	get_tree().quit(0 if termination == "parity_probe" or not game.telemetry.export_path.is_empty() else 2)
