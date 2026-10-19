extends Control

var game: Node2D
var status: Label
var debug_panel: RichTextLabel
var result_panel: PanelContainer
var result_title: Label
var result_reason: Label
var debug_button: Button
var restart_button: Button
var camera_toolbar: HBoxContainer
var score_status: Label
var incoming_status: Label
var enemy_status: Label
var controls_help: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	status = Label.new()
	status.position = Vector2(16, 8)
	status.add_theme_font_size_override("font_size", 16)
	add_child(status)
	for field in ["score", "incoming", "enemy"]:
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 14)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)
		match field:
			"score": score_status = label
			"incoming": incoming_status = label
			"enemy": enemy_status = label
	incoming_status.mouse_filter = Control.MOUSE_FILTER_PASS
	debug_button = Button.new()
	debug_button.text = "Debug (F3)"
	debug_button.pressed.connect(_toggle_debug)
	add_child(debug_button)
	restart_button = Button.new()
	restart_button.text = "Restart"
	restart_button.pressed.connect(game.restart_battle)
	add_child(restart_button)
	camera_toolbar = HBoxContainer.new()
	camera_toolbar.add_theme_constant_override("separation", 6)
	add_child(camera_toolbar)
	for label in ["−", "+", "Overview", "Deploy", "Menu", "Fullscreen (F11)"]:
		var button := Button.new()
		button.text = label
		button.custom_minimum_size = Vector2(38, 32)
		match label:
			"−": button.pressed.connect(func(): game.zoom_camera(1.0 / 1.2))
			"+": button.pressed.connect(func(): game.zoom_camera(1.2))
			"Menu": button.pressed.connect(game.return_to_menu)
			"Overview": button.pressed.connect(game.show_overview)
			"Deploy": button.pressed.connect(game.show_deployment)
			"Fullscreen (F11)": button.pressed.connect(game.toggle_fullscreen)
		camera_toolbar.add_child(button)
	var help := Button.new()
	help.text = "Controls"
	help.tooltip_text = "Scroll or +/−: zoom\nMiddle drag / WASD / arrows: pan\nHome: overview · F11: fullscreen\nClick soldier: squad · Shift+click: add/remove squad\nClick friendly shield: defending squads\nDrag white handle: route; close a loop: Defend (auto-faces enemy)\nEnd open route on a friendly shield: reinforce\nEsc / right-click: back one step\nHover selected package summary: modified unit stats"
	help.pressed.connect(func(): controls_help.visible = not controls_help.visible)
	camera_toolbar.add_child(help)
	controls_help = Label.new()
	controls_help.text = help.tooltip_text
	controls_help.visible = false
	controls_help.mouse_filter = Control.MOUSE_FILTER_STOP
	controls_help.position = Vector2(16, 112)
	controls_help.add_theme_stylebox_override("normal", _help_style())
	add_child(controls_help)
	debug_panel = RichTextLabel.new()
	debug_panel.visible = false
	debug_panel.add_theme_font_size_override("normal_font_size", 14)
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.035, 0.05, 0.07, 0.96)
	background.content_margin_left = 12
	background.content_margin_right = 12
	background.content_margin_top = 10
	debug_panel.add_theme_stylebox_override("normal", background)
	add_child(debug_panel)
	result_panel = PanelContainer.new()
	result_panel.visible = false
	add_child(result_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	result_panel.add_child(column)
	result_title = Label.new()
	result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_title.add_theme_font_size_override("font_size", 28)
	column.add_child(result_title)
	result_reason = Label.new()
	result_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(result_reason)
	var restart := Button.new()
	restart.text = "Play again"
	restart.pressed.connect(game.restart_battle)
	column.add_child(restart)
	if OS.is_debug_build():
		var folder := Button.new()
		folder.text = "Open combat log folder"
		folder.pressed.connect(func(): OS.shell_open(ProjectSettings.globalize_path("user://combat_logs")))
		column.add_child(folder)
		var copy := Button.new()
		copy.text = "Copy match summary"
		copy.pressed.connect(func(): DisplayServer.clipboard_set(game.telemetry.summary_text()))
		column.add_child(copy)
		var retry := Button.new()
		retry.text = "Save / retry combat log"
		retry.pressed.connect(func():
			game.telemetry.save()
			_on_battle_ended(game.winner,game.end_reason))
		column.add_child(retry)
	game.battle_ended.connect(_on_battle_ended)
	get_viewport().size_changed.connect(_layout)
	_layout()

func _layout() -> void:
	var screen := get_viewport_rect().size
	camera_toolbar.position = Vector2(16, 72)
	status.position = Vector2(16, 6)
	status.size = Vector2(320, 24)
	score_status.position = Vector2(16, 34)
	incoming_status.position = Vector2(maxf(350, screen.x * 0.40), 6)
	enemy_status.position = Vector2(maxf(350, screen.x * 0.40), 34)
	debug_button.position = Vector2(screen.x - 205, 12)
	debug_button.size = Vector2(105, 34)
	restart_button.position = Vector2(screen.x - 90, 12)
	restart_button.size = Vector2(76, 34)
	debug_panel.position = Vector2(16, 112)
	debug_panel.size = Vector2(minf(365, screen.x - 32), maxf(100, screen.y - 386))
	result_panel.position = Vector2((screen.x - 440) * 0.5, maxf(75, (screen.y - 450) * 0.5))
	result_panel.custom_minimum_size = Vector2(440, 150)
	queue_redraw()

func _toggle_debug() -> void:
	debug_panel.visible = not debug_panel.visible
	game._apply_camera()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_toggle_debug()
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	var player = game.economies[2]
	var enemy = game.economies[1]
	status.text = "COMMAND  %.1f / %.0f  %s" % [player.current_command, player.maximum_command, "· FULL" if player.current_command >= player.maximum_command else "(+%.1f/s)" % player.command_regeneration_rate]
	score_status.text = "SCORE  You %d : %d Enemy  ·  Target %d" % [game.scores[2], game.scores[1], game.tuning.victory_score]
	enemy_status.text = "Enemy Command %.1f / %.0f" % [enemy.current_command, enemy.maximum_command]
	enemy_status.modulate = Color(0.75,0.78,0.8)
	var flow: Dictionary = game.formation_manager.flow_counts(2)
	incoming_status.text = "INCOMING  %d" % flow.incoming
	incoming_status.tooltip_text = "Queued %d · Entering %d\nIncoming soldiers are not all combat-ready yet." % [flow.queued, flow.entering]
	if debug_panel.visible:
		_update_debug()

func _update_debug() -> void:
	var enemy = game.enemy_controller
	var lines: Array[String] = ["BATTLE DEBUG", "Seed: %d" % game.tuning.random_seed,
		"State: " + ("Active" if game.battle_active else "Ended"),
		"Enemy startup: " + ("Active" if game.player_deployment_confirmed else "Waiting for player deployment"),
		"Last rejection: " + game.last_rejection,
		"", "ENEMY", "Next decision: %.2fs" % enemy.remaining,
		"Decision: " + enemy.last_decision,
		"Doctrine: %s | Cooldown %.2f | Reinforce %s" % [enemy.doctrine,enemy.deployment_cooldown,enemy.reinforcement_priority],
		"Chosen lane: %d / %s" % [enemy.chosen_lane + 1, enemy.chosen_deployment],
		"Open lanes: " + str(enemy.last_open),
		"Player lane strengths: " + str(enemy.last_strengths),
		"Regen: %.1f/s" % game.economies[1].command_regeneration_rate, ""]
	var flow_lines: Array[String] = ["REINFORCEMENT FLOW"]
	for side in [2, 1]:
		var flow: Dictionary = game.formation_manager.flow_counts(side)
		flow_lines.append("PLAYER" if side == 2 else "ENEMY")
		flow_lines.append("Queued %d | Entering %d | Active %d" % [flow.queued, flow.entering, flow.active])
		flow_lines.append("Advancing %d | Engaging %d | Capturing %d" % [flow.advancing, flow.engaging, flow.capturing])
		flow_lines.append("Exiting %d | Dead %d | Oldest incoming %.1fs" % [flow.exiting, flow.dead, flow.oldest_incoming])
	flow_lines.append("Entering includes soldiers fighting before fully crossing the edge.")
	flow_lines.append("")
	lines = flow_lines + lines
	for team in [2, 1]:
		lines.append("PLAYER LANE OBSERVATION" if team == 2 else "ENEMY LANE OBSERVATION")
		var total := 0
		for lane in range(3):
			var zone = game.deployment_zones[team][lane]
			var friends := 0
			var enemies := 0
			for unit in zone.occupying_units:
				if is_instance_valid(unit):
					if unit.team_id == team:
						friends += 1
					else:
						enemies += 1
			var living: int = game.lane_strength(team, lane)
			total += living
			lines.append("%s: %d friendly / %d enemy; lane alive %d" % [["L", "M", "R"][lane], friends, enemies, living])
		lines.append("Living total %d | Lock %.1f / %.1fs" % [total, game.blocked_duration[team], game.tuning.deployment_block_defeat_delay])
		lines.append("")
	lines.append("PACKAGE: " + game.hand.package_description())
	lines.append("\nFORMATION ENTRY")
	lines.append("Queued arrivals: %d | Reserved entry slots: %d" % [game.formation_manager.pending.size(), game.formation_manager.reservations.size()])
	if not game.footprint_preview.is_empty():
		var footprint: Dictionary = game.footprint_preview
		lines.append("Footprint: %s" % footprint.rectangle)
		lines.append("Required %d | Available %d | Candidates %d" % [footprint.required, footprint.capacity, footprint.candidate_slots.size()])
		lines.append("State: " + ("VALID" if footprint.is_valid else footprint.failure_reason))
		var reasons: Dictionary = {}
		for blocked in footprint.invalid_slots:
			reasons[blocked.reason] = int(reasons.get(blocked.reason, 0)) + 1
		lines.append("Blocked slots: " + str(reasons))
	lines.append("Green slots: free | Red: blocked | Amber: reserved")
	lines.append("Blue rings: friendly space | Red rings: enemy exclusion")
	lines.append("Pan behind either map edge to inspect queued ranks.
Clock: queued | Arrow: entry/advance | Crosshair: combat")
	lines.append("\nUNIT INSPECTION — hover a soldier")
	var inspected: Unit = null
	var distance := 160.0 * 160.0
	for unit in game.units:
		if is_instance_valid(unit):
			var candidate: float = unit.global_position.distance_squared_to(game.get_global_mouse_position())
			if candidate < distance:
				distance = candidate
				inspected = unit
	if inspected:
		lines.append(inspected.debug_description())
	lines.append("\nSQUAD COMMANDS" + "\nSelected: " + str(game.squad_commands.selected_ids))
	lines.append("Planning %s | Speed %.2f | Blend %.2f" % [game.planning.active, Engine.time_scale, game.planning.blend])
	lines.append("Gesture: " + str(game.command_ui.gesture_debug) + " | Failure: " + game.command_ui.failure_reason)
	for squad in game.squad_commands.squads.values():
		lines.append("Squad %d %s | %s | living %d | order %d | center %s r %.0f" % [squad.squad_id, squad.unit_type, squad.intent, squad.living_members().size(), squad.order_id, squad.defense_center, squad.defense_radius])
	for id in game.squad_commands.orders:
		var point: Dictionary = game.squad_commands.orders[id]
		lines.append("Point %d %s | established %d inbound %d | area %.0f/%.0f | %s | pressure %.1f | anchors %s | neighbors %s" % [id,point.lifecycle,point.established,point.inbound,point.actual_area,point.desired_area,point.capacity_state,point.pressure,point.anchors,point.neighbors])
	debug_panel.text = "\n".join(lines)

func _on_battle_ended(winner: int, reason: String) -> void:
	result_title.text = "Victory" if winner == 2 else ("Defeat" if winner == 1 else "Draw")
	result_reason.text = reason
	if game.telemetry.enabled:
		result_reason.text += "\nCombat log saved" if not game.telemetry.export_path.is_empty() else "\n"+game.telemetry.export_error
	result_panel.visible = true

func _draw() -> void:
	draw_rect(Rect2(0, 0, get_viewport_rect().size.x, 66), Color(0.04, 0.06, 0.08, 0.97))

func _help_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025,0.04,0.06,0.98)
	style.set_content_margin_all(12)
	return style
