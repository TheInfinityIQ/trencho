extends SceneTree
# Matched population, real automatic 60 Hz movement, optional rendered wall pacing.
var game: Node
var options: Dictionary
var cases: Array = []
var collecting := false
var frame_last := 0
var frame_intervals: Array = []
func _initialize() -> void: call_deferred("run")
func observe_frame() -> void:
	var now := Time.get_ticks_usec()
	if collecting and frame_last>0: frame_intervals.append(float(now-frame_last)/1000)
	frame_last = now

func stats(values: Array) -> Dictionary:
	if values.is_empty(): return {}
	var ordered = values.duplicate()
	ordered.sort()
	var total = 0.0
	for value in values: total += value
	return {"samples":values.size(),"mean":total/values.size(),"p95":ordered[mini(ordered.size()-1,floori(ordered.size()*0.95))],"p99":ordered[mini(ordered.size()-1,floori(ordered.size()*0.99))],"max":ordered[-1]}
func spawn(count: int, columns: int, center: Vector2, step: float) -> BattleSquad:
	var spec: Dictionary = game.card_catalog.conscript_wave.base_stats()
	spec.merge({"team":2,"unit_type":"conscript_wave","lane":1,"spawn_positions":[]},true)
	for index in range(count): spec.spawn_positions.append(center+Vector2((index%columns-(columns-1)*0.5)*step,floori(float(index)/columns)*step))
	game.spawn_deployment(spec)
	return spec.squad
func trial(crossing: bool) -> void:
	game = load("res://main.tscn").instantiate()
	game.tuning = game.tuning.duplicate()
	game.tuning.enemy_enabled = false
	game.tuning.move_speed_variance = 0
	game.tuning.score_victory_enabled = false
	game.match_options = {"presentation":not options.has("cpu"),"profile":not options.has("uninstrumented")}
	root.add_child(game)
	current_scene = game
	var defenders = spawn(48,8,Vector2(1250 if not crossing else 4800,3000),160)
	var result: Dictionary = game.squad_commands.issue_group([defenders],"DEFEND",Vector2(1250 if not crossing else 4800,3300))
	if not result.success:
		push_error("Crossing profile fixture rejected: "+result.failure_reason)
		quit(1)
		return
	for unit in defenders.members:
		unit.position = defenders.defense_positions[unit.squad_member_index]
		unit.defense_established = true
		unit.state = Unit.State.DEFENDING
	game.squad_commands.points.update(0,true)
	var movers: Array = []
	for row in range(12): movers.append(spawn(12,12,Vector2(4800,4700+row*160),160))
	game.squad_commands.issue_group(movers,"ADVANCE",Vector2.ZERO,0,PackedVector2Array([Vector2(4800,4300),Vector2(4800,1500)]))
	game.command_ui.feedback.clear()
	game.show_overview()
	var samples: Dictionary = {}
	frame_intervals.clear()
	collecting = false
	var maxima = {"stalled":0,"traversing":0,"moving":0}
	var start = game.simulation_time
	var previous = Time.get_ticks_usec()
	var last_metrics = {}
	var ticks: int = int(options.get("ticks",1200))
	for tick in range(ticks):
		await physics_frame
		var now = Time.get_ticks_usec()
		if tick >= 180:
			collecting = true
			var record = {"physics_interval_ms":float(now-previous)/1000,"engine_physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000,"engine_process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000,"living":game.units.size(),"moving":0,"stalled":0,"traversing":0}
			for unit in game.units:
				if unit.squad == defenders: continue
				if unit.velocity.length()>1: record.moving += 1
				if unit.steering_stalled: record.stalled += 1
				if unit.position.y>2400 and unit.position.y<4200 and absf(unit.position.x-4800)<1280: record.traversing += 1
			for key in ["stalled","traversing","moving"]: maxima[key] = maxi(maxima[key],record[key])
			for key in game.profile_metrics:
				record[key.trim_suffix("_us")+"_ms" if key.ends_with("_us") else key] = (game.profile_metrics[key]-last_metrics.get(key,0))/1000.0 if key.ends_with("_us") else game.profile_metrics[key]-last_metrics.get(key,0)
			for key in record:
				if not samples.has(key): samples[key] = []
				samples[key].append(record[key])
		previous = now
		last_metrics = game.profile_metrics.duplicate()
	collecting = false
	samples["wall_frame_ms"] = frame_intervals.duplicate()
	var summaries = {}
	for key in samples: summaries[key] = stats(samples[key])
	var result_record = {"case":"friendly_crossing" if crossing else "open_control","ticks":ticks,"simulation_seconds":game.simulation_time-start,"initial_living":192,"defensive_slots":48,"maxima":maxima,"recovery":game.formation_manager.recovery.metrics.duplicate(),"timings":summaries}
	cases.append(result_record)
	print("CROSSING CASE ",JSON.stringify(result_record))
	game.queue_free()
	await process_frame
	await physics_frame
func run() -> void:
	process_frame.connect(observe_frame)
	options = preload("res://scripts/systems/mirror_io.gd").arguments()
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1
	Engine.max_fps = 0 if options.has("cpu") else 120
	if not options.has("cpu"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		root.size = Vector2i(1280,800)
	await trial(false)
	await trial(true)
	var report = {"engine":Engine.get_version_info().string,"build":ProjectSettings.get_setting("application/config/version"),"mode":"cpu_headless" if options.has("cpu") else "rendered_120_fps_cap","instrumented":not options.has("uninstrumented"),"cases":cases,"notes":"Actual physics-frame wall intervals; engine monitors can update late. Nested timers overlap and must not be summed. Timers and observation add measurement overhead. Not a deterministic timing guarantee."}
	var path: String = options.get("output","res://.test-results/friendly_crossing_profile.json")
	var file = FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(report))
	print("CROSSING PROFILE COMPLETED ",ProjectSettings.globalize_path(path))
	quit()
