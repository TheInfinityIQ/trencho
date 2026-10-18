extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var runner = preload("res://scripts/systems/pathing_trials.gd").new()
	root.add_child(runner)
	var options: Dictionary = preload("res://scripts/systems/mirror_io.gd").arguments()
	runner.destination = "user://pathing_tests/verification_%s_%d.json" % [Time.get_datetime_string_from_system(true).replace(":",""),Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute("user://pathing_tests")
	var report: Dictionary = await runner.run(int(options.get("seed",16102026)),clampi(int(options.get("repetitions",2)),1,20),str(options.get("case","")))
	print("PATHING TRIALS: %d trials, %s; %s" % [report.results.size(),"PASSED" if report.passed else "FAILED",ProjectSettings.globalize_path(runner.destination)])
	quit(0 if report.passed else 1)
