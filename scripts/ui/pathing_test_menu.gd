extends Control
const IO = preload("res://scripts/systems/mirror_io.gd")
var worker := -1
var directory := ""
var result_path := ""
var last_poll := 0
var seed_input: SpinBox
var repetitions_input: SpinBox
var start_button: Button
var status: Label
var details: RichTextLabel
var requested_seed := 0
var requested_repetitions := 0
var report: Dictionary = {}

func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color("101b25")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,30)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",12)
	margin.add_child(column)
	var title := Label.new()
	title.text = "Pathing trials"
	title.add_theme_font_size_override("font_size",30)
	column.add_child(title)
	var description := Label.new()
	description.text = "Queued squads, drawn routes, whole-position moves, reinforcement, crossing forces, obstacles and map edges.\nEach seed changes placement and alternates sides. Every soldier must arrive; blocked goals are tested separately."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(description)
	var options := HBoxContainer.new()
	options.add_theme_constant_override("separation",12)
	column.add_child(options)
	var seed_label := Label.new()
	seed_label.text = "Starting seed"
	options.add_child(seed_label)
	seed_input = SpinBox.new()
	seed_input.min_value = 0
	seed_input.max_value = 2147483000
	seed_input.value = 16102026
	seed_input.custom_minimum_size.x = 180
	options.add_child(seed_input)
	var repetitions_label := Label.new()
	repetitions_label.text = "Seeds"
	options.add_child(repetitions_label)
	repetitions_input = SpinBox.new()
	repetitions_input.min_value = 1
	repetitions_input.max_value = 20
	repetitions_input.value = 3
	options.add_child(repetitions_input)
	start_button = Button.new()
	start_button.text = "Run trials"
	start_button.pressed.connect(start_trials)
	options.add_child(start_button)
	var folder := Button.new()
	folder.text = "Open results"
	folder.pressed.connect(func():
		if not directory.is_empty(): OS.shell_open(ProjectSettings.globalize_path(directory)))
	options.add_child(folder)
	var back := Button.new()
	back.text = "Back to menu"
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/menu.tscn"))
	options.add_child(back)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size",18)
	column.add_child(status)
	details = RichTextLabel.new()
	details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_theme_font_size_override("normal_font_size",16)
	column.add_child(details)
	start_trials()

func start_trials() -> void:
	if worker > 0 and OS.is_process_running(worker): return
	requested_seed = int(seed_input.value)
	requested_repetitions = int(repetitions_input.value)
	directory = "user://pathing_tests/%s_%d" % [Time.get_datetime_string_from_system(true).replace(":",""),Time.get_ticks_usec()]
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		status.text = "Could not create the results folder."
		return
	result_path = directory+"/trial_report.json"
	report = {}
	worker = IO.launch(["--headless","--fixed-fps","60","--","--pathing-worker","--seed=%d" % requested_seed,"--repetitions=%d" % requested_repetitions,"--result="+result_path])
	if worker <= 0:
		status.text = "Could not start pathing trials."
		return
	start_button.disabled = true
	seed_input.editable = false
	repetitions_input.editable = false
	details.text = "Starting trials. Results and failure snapshots are saved automatically."
	status.text = "Running %d trials in the background…" % (requested_repetitions*preload("res://scripts/systems/pathing_trials.gd").CASES.size())

func _process(_delta: float) -> void:
	if worker <= 0 or Time.get_ticks_msec()-last_poll < 200: return
	last_poll = Time.get_ticks_msec()
	var latest := IO.read_json(result_path)
	if not latest.is_empty() and latest != report:
		report = latest
		var passed := 0
		var lines: Array[String] = []
		for result in report.get("results",[]):
			if result.passed: passed += 1
			var progress: Array[String] = []
			for stage in result.get("stages",[]): progress.append("%d/%d%s" % [stage.arrived,stage.expected," blocked as expected" if stage.get("expected_blocked",false) else " arrived"])
			lines.append("%s · %s · Seed %d · Side %d · %.1fs · %s" % ["PASS" if result.passed else "FAIL",result.case.replace("_"," ").capitalize(),result.seed,result.team,result.simulation_seconds,", ".join(progress)])
		details.text = "\n".join(lines)
		status.text = "%d / %d completed · %d passed · %d failed\n%s" % [report.results.size(),requested_repetitions*preload("res://scripts/systems/pathing_trials.gd").CASES.size(),passed,report.results.size()-passed,"Complete. Choose another seed range to repeat." if report.get("completed",false) else "Running: "+str(report.get("current_case","")).replace("_"," ")]
	if not OS.is_process_running(worker):
		worker = -1
		start_button.disabled = false
		seed_input.editable = true
		repetitions_input.editable = true
		seed_input.value = requested_seed+requested_repetitions
		if not report.get("completed",false): status.text = "Trials stopped before completion. See saved results; incomplete trials are not passes."

func _exit_tree() -> void:
	if worker > 0 and OS.is_process_running(worker): OS.kill(worker)
