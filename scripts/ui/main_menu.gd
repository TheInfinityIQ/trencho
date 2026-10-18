extends Control
const IO = preload("res://scripts/systems/mirror_io.gd")

func _ready() -> void:
	var options := IO.arguments()
	if options.has("pathing-worker"):
		add_child(preload("res://scripts/systems/pathing_trials.gd").new())
		return
	if options.has("mirror-match-worker"):
		add_child(preload("res://scripts/systems/mirror_match_worker.gd").new())
		return
	if options.has("mirror-batch"):
		add_child(preload("res://scripts/systems/mirror_batch.gd").new())
		return
	RenderingServer.set_default_clear_color(Color("101b25"))
	var background := ColorRect.new()
	background.color = Color("101b25")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(460,0)
	column.add_theme_constant_override("separation",20)
	center.add_child(column)
	var title := Label.new()
	title.text = "TRENCHO"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size",54)
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Draw the order. Build the force."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color("a1becb")
	column.add_child(subtitle)
	for label in ["Play","Mirror test match","Pathing trials"]:
		var button := Button.new()
		button.text = label
		button.custom_minimum_size.y = 56
		button.add_theme_font_size_override("font_size",22)
		column.add_child(button)
		if label == "Play": button.pressed.connect(func(): get_tree().change_scene_to_file("res://main.tscn"))
		elif label == "Mirror test match": button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/mirror_tests.tscn"))
		else: button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/pathing_tests.tscn"))
	var hint := Label.new()
	hint.text = "Mirror tests: Wall / Wall · Wall / Triangle · Triangle / Triangle\nAI vs AI, accelerated in the background. Logs saved automatically.\nPathing trials: seeded movement challenges with arrival and collision checks."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size",14)
	hint.modulate = Color("a1becb")
	column.add_child(hint)
