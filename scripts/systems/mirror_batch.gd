extends Node
const IO = preload("res://scripts/systems/mirror_io.gd")
const PAIRS = [["LINE","LINE"],["LINE","TRIANGLE"],["TRIANGLE","TRIANGLE"]]
var graphical := true
var directory := ""
var jobs: Array = []
var results: Array = []
var index := 0
var started := Time.get_ticks_msec()
var last_poll := 0
var budget := 0.0
var finished := false
var status: Label
var report: Dictionary = {}

func _ready() -> void:
	var options := IO.arguments()
	budget = float(options.get("budget",0))
	graphical = not options.has("mirror-batch")
	if not graphical: Engine.max_fps = 30
	directory = "user://mirror_tests/%s_%d" % [Time.get_datetime_string_from_system(true).replace(":",""),Time.get_ticks_usec()]
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_error("Could not create mirror test folder")
		get_tree().quit(2)
		return
	if graphical: build_ui()
	for worker in range(3): launch_next()

func build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("101b25")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(620,0)
	column.add_theme_constant_override("separation",18)
	center.add_child(column)
	status = Label.new()
	status.add_theme_font_size_override("font_size",22)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(status)
	var folder := Button.new()
	folder.text = "Open test results"
	folder.pressed.connect(func(): OS.shell_open(ProjectSettings.globalize_path(directory)))
	column.add_child(folder)
	var back := Button.new()
	back.text = "Back to menu"
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/menu.tscn"))
	column.add_child(back)

func launch_next() -> void:
	if finished: return
	var options := IO.arguments()
	var pair: Array = PAIRS[index%3]
	var destination := directory+"/match_%03d.json" % (index+1)
	var seed := int(options.get("seed",16102026))+index/3
	var flags: Array[String] = ["--headless","--fixed-fps","60","--","--mirror-match-worker",
		"--seed=%d" % seed,"--side-one="+pair[0],"--side-two="+pair[1],"--result="+destination,
		"--limit="+str(options.get("limit",1800))]
	var pid := IO.launch(flags)
	if pid <= 0:
		finish("WORKER_LAUNCH_FAILED")
		return
	jobs.append({"pid":pid,"path":destination,"number":index+1,"pair":pair})
	index += 1
	update_label()

func _process(_delta: float) -> void:
	if finished: return
	var now := Time.get_ticks_msec()
	if now-last_poll < 150: return
	last_poll = now
	var expired: bool = budget > 0 and (now-started)/1000.0 >= budget
	for job in jobs.duplicate():
		if OS.is_process_running(job.pid): continue
		var latest := IO.read_json(job.path)
		if not latest.get("completed",false):
			finish("WORKER_FAILED")
			return
		latest.match_number = job.number
		results.append(latest)
		jobs.erase(job)
		if budget > 0 and not expired: launch_next()
	if expired:
		finish("WALL_TIME_BUDGET")
		return
	if budget <= 0 and jobs.is_empty():
		finish("THREE_MATCHES_COMPLETED")
		return
	update_label()

func update_label() -> void:
	if not graphical or status == null: return
	status.text = "Mirror test matches\n\n"
	for job in jobs:
		var latest := IO.read_json(job.path)
		status.text += "%s vs %s: %.1f game minutes | %d soldiers\n" % [job.pair[0].replace("LINE","WALL"),job.pair[1].replace("LINE","WALL"),float(latest.get("simulation_seconds",0))/60.0,latest.get("living_soldiers",0)]
	status.text += "\nCompleted: %d / 3\nAI vs AI, running three matches in the background." % results.size()

func finish(reason: String) -> void:
	finished = true
	var incomplete: Array = []
	for job in jobs:
		var latest := IO.read_json(job.path)
		if latest.get("completed",false):
			latest.match_number = job.number
			results.append(latest)
		else: incomplete.append(latest)
		if OS.is_process_running(job.pid): OS.kill(job.pid)
	jobs.clear()
	results.sort_custom(func(a,b): return a.match_number < b.match_number)
	report = {"reason":reason,"real_seconds":(Time.get_ticks_msec()-started)/1000.0,"completed_matches":results,
		"incomplete_matches":incomplete,"requested_pairs":PAIRS,"physics_hz":60,
		"note":"Natural results and timeout surrenders are reported separately. Incomplete matches are not wins."}
	IO.write_json(directory+"/batch_summary.json",report)
	print("MIRROR BATCH: ",results.size()," completed in ",report.real_seconds,"s; ",ProjectSettings.globalize_path(directory))
	if graphical:
		status.text = "Mirror tests complete\n\n"+str(results.size())+" matches finished\n"
		for result in results:
			status.text += "%s vs %s: %s / %s (%s)\n" % [result.doctrines[0].replace("LINE","WALL"),result.doctrines[1].replace("LINE","WALL"),result.scores.get("1",0),result.scores.get("2",0),result.termination.replace("_"," ")]
		status.text += "\n"+reason.replace("_"," ").capitalize()
	else: get_tree().quit(0 if reason in ["WALL_TIME_BUDGET","THREE_MATCHES_COMPLETED"] else 2)

func _exit_tree() -> void:
	for job in jobs:
		if OS.is_process_running(job.pid): OS.kill(job.pid)
