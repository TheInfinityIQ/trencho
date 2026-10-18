extends Node2D

signal deployment_requested(team, cards, zone)
signal deployment_rejected(team, reason)
signal deployment_accepted(team, specification)
signal unit_spawned(unit)
signal unit_died(unit)
signal unit_reached_goal(unit)
signal score_changed(team, score)
signal battle_ended(winner, reason)
signal unit_entered_zone(unit, zone)
signal unit_exited_zone(unit, zone)

const UNIT = preload("res://scenes/entities/soldier_test.tscn")
const HAND = preload("res://scenes/cards/hand_of_cards.tscn")
const UNIT_SYMBOLS = preload("res://scripts/ui/unit_symbols.gd")
const HUD = preload("res://scripts/ui/battle_hud.gd")
const ECONOMY = preload("res://scripts/systems/economy.gd")
const ZONE = preload("res://scripts/systems/deployment_zone.gd")
const DEPLOYMENT = preload("res://scripts/systems/deployment_manager.gd")
const FORMATION = preload("res://scripts/systems/formation_manager.gd")
const ENEMY = preload("res://scripts/systems/enemy_controller.gd")
const SQUAD_COMMANDS = preload("res://scripts/systems/squad_commands.gd")
const PLANNING = preload("res://scripts/systems/command_planning.gd")
const COMMAND_UI = preload("res://scripts/ui/squad_command_ui.gd")
@export var tuning: BattleTuning = preload("res://data/battle_tuning.tres")
@export var card_definitions: Array[BattleCard] = [
	preload("res://data/cards/rifle_squad.tres"), preload("res://data/cards/assault_squad.tres"),
	preload("res://data/cards/conscript_wave.tres"), preload("res://data/cards/commander_mojo.tres"),
	preload("res://data/cards/forced_march.tres"), preload("res://data/cards/defensive_officer.tres")]
var match_options: Dictionary = {}
var player_controller: RefCounted
var simulation_time := 0.0
var next_simulation_id := 1
var surrendered_team := 0
var telemetry: RefCounted
var unit_rng := RandomNumberGenerator.new()
var card_catalog: Dictionary = {}
var economies: Dictionary = {}
var deployment_zones: Dictionary = {1: [], 2: []}
var deployment_manager: RefCounted
var enemy_controller: RefCounted
var formation_manager: RefCounted
var squad_commands: RefCounted
var planning: Node
var command_ui: Control
var footprint_preview: Dictionary = {}
var footprint_slots: Array = []
var units: Array = []
var zones: Array[Rect2] = []
var enemy_zones: Array[Rect2] = []
var highlighted := -1
var field_size: Vector2
var zone_overlay: Node2D
var preview: Node2D
var preview_count := 0
var preview_legal := true
var ghost_material: ShaderMaterial
var hand: Control
var hud: Control
var battle_active := true
var player_deployment_confirmed := false
var deaths_by_team := {1: 0, 2: 0}
var winner := 0
var end_reason := ""
var scores: Dictionary = {1: 0, 2: 0}
var blocked_duration: Dictionary = {1: 0.0, 2: 0.0}
var last_rejection := ""
@export_group("Camera")
@export_range(1, 6) var starting_zoom: float = 2.0
@export var camera_pan_speed: float = 900.0
var zoom_multiplier := 2.0
var camera_center := Vector2.ZERO
var base_zoom := 1.0
var camera_panning := false

func _ready() -> void:
	if not match_options.is_empty():
		tuning = tuning.duplicate()
		tuning.random_seed = match_options.get("seed",tuning.random_seed)
	if match_options.get("mirror",false):
		tuning.enemy_command_max = tuning.command_max
		tuning.enemy_command_start = tuning.command_start
		tuning.enemy_command_regeneration_rate = tuning.command_regeneration_rate
		tuning.enemy_enabled = true
		player_deployment_confirmed = true
	unit_rng.seed = tuning.random_seed + 2
	RenderingServer.set_default_clear_color(Color(0.055, 0.075, 0.09))
	GameMaster.team_one_score = 0
	GameMaster.team_two_score = 0
	for card in card_definitions:
		card_catalog[card.card_id] = card
	economies[1] = ECONOMY.new(tuning.enemy_command_max, tuning.enemy_command_start, tuning.enemy_command_regeneration_rate)
	economies[2] = ECONOMY.new(tuning.command_max, tuning.command_start, tuning.command_regeneration_rate)
	$MapTest.init()
	var dimensions: Dictionary = $MapTest.get_tile_dimensions()
	field_size = Vector2(dimensions.width, dimensions.height) * $MapTest.get_tile_size()
	zoom_multiplier = starting_zoom
	camera_center = field_size * Vector2(0.5, 0.74)
	var margin := field_size.x * 0.05
	var width := field_size.x * 0.9 / 3.0
	for lane in range(3):
		zones.append(Rect2(margin + lane * width, field_size.y * 0.83, width, field_size.y * 0.1))
		enemy_zones.append(Rect2(margin + lane * width, field_size.y * 0.07, width, field_size.y * 0.1))
		deployment_zones[2].append(ZONE.new(2, lane, zones[lane]))
		deployment_zones[1].append(ZONE.new(1, lane, enemy_zones[lane]))
	zones.append(Rect2(margin, field_size.y * 0.94, width * 3, field_size.y * 0.05))
	formation_manager = FORMATION.new(self)
	squad_commands = SQUAD_COMMANDS.new(self)
	planning = PLANNING.new()
	planning.battle = self
	add_child(planning)
	deployment_manager = DEPLOYMENT.new(self)
	var doctrines: Array = match_options.get("doctrines",[])
	enemy_controller = ENEMY.new(self,1,doctrines[0] if doctrines.size() == 2 else "")
	if match_options.get("mirror",false): player_controller = ENEMY.new(self,2,doctrines[1])
	zone_overlay = Node2D.new()
	zone_overlay.z_index = 10
	zone_overlay.draw.connect(_draw_zones)
	add_child(zone_overlay)
	preview = Node2D.new()
	preview.z_index = 21
	add_child(preview)
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; void fragment() { vec4 pixel = texture(TEXTURE, UV); float grey = dot(pixel.rgb, vec3(0.299, 0.587, 0.114)); COLOR = vec4(vec3(0.55 + grey * 0.35), pixel.a * 0.72); }"
	ghost_material = ShaderMaterial.new()
	ghost_material.shader = shader
	telemetry = preload("res://scripts/systems/combat_telemetry.gd").new(self)
	deployment_accepted.connect(telemetry.committed)
	unit_spawned.connect(telemetry.spawned)
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	hand = HAND.instantiate()
	hand.game = self
	layer.add_child(hand)
	hud = Control.new()
	hud.set_script(HUD)
	hud.game = self
	layer.add_child(hud)
	command_ui = COMMAND_UI.new()
	command_ui.game = self
	layer.add_child(command_ui)
	get_viewport().size_changed.connect(_fit_camera)
	_fit_camera()
	refresh_occupancy()
	if match_options.get("mirror",false):
		planning.set_process(false)
		hand.set_process_input(false)
		hand.set_process_unhandled_input(false)
		command_ui.set_process_input(false)
	if not match_options.get("presentation",true):
		set_process(false)
		planning.set_process(false)
		for child in get_children():
			if child is CanvasLayer:
				child.hide()
				child.process_mode = Node.PROCESS_MODE_DISABLED

func _process(delta: float) -> void:
	_update_camera_input(delta)

# Economy, reinforcement release and AI share the soldiers' fixed simulation clock.
func _physics_process(delta: float) -> void:
	if not battle_active:
		return
	simulation_time += delta
	telemetry.tick(delta)
	for economy in economies.values():
		economy.tick(delta)
	formation_manager.tick(delta)
	squad_commands.tick(delta)
	refresh_occupancy()
	_check_deployment_lock(delta)
	if battle_active and tuning.enemy_enabled and surrendered_team != 1:
		enemy_controller.tick(delta)
	if battle_active and player_controller != null and surrendered_team != 2:
		player_controller.tick(delta)
	zone_overlay.queue_redraw()

func _fit_camera() -> void:
	var area := battlefield_view_rect()
	base_zoom = minf(area.size.x / field_size.x, area.size.y / field_size.y)
	_apply_camera()

func battlefield_view_rect() -> Rect2:
	var screen := get_viewport_rect().size
	return Rect2(20, 76, maxf(100, screen.x - 40), maxf(100, screen.y - 350))

func _apply_camera() -> void:
	var zoom_level := base_zoom * zoom_multiplier
	var area := battlefield_view_rect()
	var half_visible := area.size / (2.0 * zoom_level)
	for axis in range(2):
		var padding: float = tuning.offscreen_spawn_margin + formation_manager.regions[2].size.y + tuning.unit_radius * 2 if axis == 1 and is_instance_valid(hud) and hud.debug_panel.visible else 0.0
		camera_center[axis] = field_size[axis] * 0.5 if half_visible[axis] * 2 >= field_size[axis] + padding * 2 else clampf(camera_center[axis], half_visible[axis] - padding, field_size[axis] + padding - half_visible[axis])
	$Camera2D.zoom = Vector2.ONE * zoom_level
	$Camera2D.position = camera_center
	$Camera2D.offset = (get_viewport_rect().size * 0.5 - area.get_center()) / zoom_level
	$Camera2D.force_update_scroll()
	zone_overlay.queue_redraw()

func zoom_camera(factor: float, anchor: Vector2 = Vector2(-1, -1)) -> void:
	var anchored := battlefield_view_rect().has_point(anchor)
	var before := get_canvas_transform().affine_inverse() * anchor
	zoom_multiplier = clampf(zoom_multiplier * factor, 1.0, 6.0)
	_apply_camera()
	if anchored:
		camera_center += before - get_canvas_transform().affine_inverse() * anchor
		_apply_camera()

func show_overview() -> void:
	zoom_multiplier = 1.0
	camera_center = field_size * 0.5
	_apply_camera()

func show_deployment() -> void:
	zoom_multiplier = maxf(2.0, zoom_multiplier)
	camera_center = field_size * Vector2(0.5, 0.75)
	_apply_camera()

func toggle_fullscreen() -> void:
	var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)

func _camera_point_allowed(point: Vector2) -> bool:
	if is_instance_valid(command_ui) and (command_ui.blueprint.visible or command_ui.gesture_active): return false
	if not battlefield_view_rect().has_point(point):
		return false
	if is_instance_valid(hud):
		for control in [hud.camera_toolbar, hud.debug_panel, hud.result_panel, hud.controls_help]:
			if control.visible and control.get_global_rect().has_point(point):
				return false
	return true

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER] and is_instance_valid(hand) and hand.has_footprint and battle_active:
		hand._confirm_footprint()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and is_instance_valid(hand):
			command_ui.cancel_current()
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			camera_panning = event.pressed and _camera_point_allowed(event.position)
			if camera_panning:
				get_viewport().set_input_as_handled()
		elif event.pressed and _camera_point_allowed(event.position):
			if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				zoom_camera(1.2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2, event.position)
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and camera_panning:
		camera_center -= event.relative / $Camera2D.zoom.x
		_apply_camera()
		get_viewport().set_input_as_handled()

func _update_camera_input(delta: float) -> void:
	if is_instance_valid(command_ui) and (command_ui.blueprint.visible or command_ui.gesture_active): return
	var direction := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		direction.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		direction.y += 1
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		direction.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		direction.x += 1
	if direction != Vector2.ZERO:
		camera_center += direction.normalized() * camera_pan_speed * delta / $Camera2D.zoom.x
		_apply_camera()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		camera_panning = false

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F11:
				toggle_fullscreen()
			KEY_HOME:
				show_overview()
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
				zoom_camera(1.2)
			KEY_MINUS, KEY_KP_SUBTRACT:
				zoom_camera(1.0 / 1.2)

func refresh_occupancy() -> void:
	for team_zones in deployment_zones.values():
		for zone in team_zones:
			var previous: Array = zone.occupying_units.duplicate()
			zone.refresh(units, tuning.unit_radius)
			for unit in zone.occupying_units:
				if not previous.has(unit):
					unit_entered_zone.emit(unit, zone)
			for unit in previous:
				if is_instance_valid(unit) and not zone.occupying_units.has(unit):
					unit_exited_zone.emit(unit, zone)

func lane_strength(team: int, lane: int) -> int:
	var count := 0
	for unit in units:
		if is_instance_valid(unit) and unit.is_alive() and unit.team_id == team and lane_for_x(unit.global_position.x) == lane:
			count += 1
	return count

func lane_for_x(x: float) -> int:
	return clampi(int((x - zones[0].position.x) / zones[0].size.x), 0, 2)

func _check_deployment_lock(delta: float) -> void:
	if not tuning.deployment_lock_defeat_enabled:
		return
	var defeated: Array[int] = []
	for team in [1, 2]:
		var all_enemy: bool = formation_manager.region_overrun(team)
		blocked_duration[team] = blocked_duration[team] + delta if all_enemy else 0.0
		if all_enemy and blocked_duration[team] >= tuning.deployment_block_defeat_delay:
			defeated.append(team)
	if defeated.size() == 2:
		finish_battle(0, "Both armies lost their deployment zones")
	elif defeated.size() == 1:
		finish_battle(3 - defeated[0], "All opposing deployment zones held for %.1f seconds" % tuning.deployment_block_defeat_delay)

func score_unit(unit: Unit) -> void:
	if not battle_active or not unit.is_alive() or not crossed_score_line(unit):
		return
	var team := unit.team_id
	scores[team] += unit.score_value
	GameMaster.team_one_score = scores[1]
	GameMaster.team_two_score = scores[2]
	unit_reached_goal.emit(unit)
	unit.begin_exit()
	unregister_unit(unit, false)
	score_changed.emit(team, scores[team])
	if tuning.score_victory_enabled and scores[team] >= tuning.victory_score:
		finish_battle(team, "Score target reached")

func unregister_unit(unit: Unit, killed: bool = true, departure_reason: String = "scored") -> void:
	telemetry.removed(unit,killed,departure_reason)
	formation_manager.release_unit(unit)
	formation_manager.untrack_unit(unit)
	units.erase(unit)
	squad_commands.member_removed(unit)
	squad_commands.invalidate_enemy_cache()
	if killed:
		deaths_by_team[unit.team_id] += 1
		unit_died.emit(unit)

func finish_battle(winning_team: int, reason: String) -> void:
	if not battle_active:
		return
	battle_active = false
	formation_manager.clear()
	command_ui.close_all()
	winner = winning_team
	end_reason = reason
	hand.cancel_selection()
	highlight_zone(-1)
	for unit in units:
		if is_instance_valid(unit):
			unit.set_physics_process(false)
	telemetry.finish(winner,reason)
	battle_ended.emit(winner, reason)

func surrender(team: int) -> void:
	if not battle_active or surrendered_team != 0: return
	surrendered_team = team
	telemetry.data.match["forced_surrender"] = {"team":team,"timestamp":simulation_time,"reason":"SIMULATION_TIME_LIMIT","limit_seconds":match_options.get("surrender_limit_seconds",1800)}
	telemetry.event("AI_SURRENDER",{"team":team,"reason":"SIMULATION_TIME_LIMIT","limit_seconds":match_options.get("surrender_limit_seconds",1800)})
	for id in squad_commands.orders.keys():
		if squad_commands.orders[id].team == team:
			telemetry.point_deleted(id,"SCRIPTED_SURRENDER")
			squad_commands.orders.erase(id)
	formation_manager.cancel_pending_team(team)
	for id in formation_manager.reservations.keys():
		if formation_manager.reservations[id].team == team: formation_manager.reservations.erase(id)
	for unit in units.duplicate():
		if unit.team_id == team:
			unit.begin_exit()
			unregister_unit(unit,false,"surrendered")
	var victor := 3-team
	var controller = enemy_controller if victor == 1 else player_controller
	if controller != null: controller.advance_only = true
	var advancing: Array = []
	for squad in squad_commands.squads.values():
		if squad.team == victor and not squad.retreating: advancing.append(squad)
	if not advancing.is_empty(): squad_commands.issue_group(advancing,"ADVANCE")

func return_to_menu() -> void:
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://scenes/menu.tscn")

func restart_battle() -> void:
	get_tree().reload_current_scene()

func zone_at_mouse() -> int:
	return zone_at_screen(get_viewport().get_mouse_position())

func zone_at_screen(screen_position: Vector2) -> int:
	if screen_position.y < 70 or screen_position.y >= get_viewport_rect().size.y - 270:
		return -1
	var world_position := get_canvas_transform().affine_inverse() * screen_position
	for index in range(zones.size()):
		if zones[index].has_point(world_position):
			return index
	return -1

func highlight_zone(index: int, count: int = 0, legal: bool = true) -> void:
	if highlighted == index and preview_count == count and preview_legal == legal:
		return
	highlighted = index
	preview_count = count
	preview_legal = legal
	for child in preview.get_children():
		preview.remove_child(child)
		child.queue_free()
	if index >= 0 and count > 0:
		var template := UNIT.instantiate()
		for spawn_position in get_spawn_positions(count, index):
			var ghost := Node2D.new()
			ghost.position = spawn_position
			preview.add_child(ghost)
			for sprite_name in ["SpriteWeapon", "SpriteBody"]:
				var sprite := template.get_node(sprite_name).duplicate() as Sprite2D
				sprite.material = ghost_material
				ghost.add_child(sprite)
		template.free()
	zone_overlay.queue_redraw()

func spawn_deployment(specification: Dictionary) -> void:
	# Low-level fixture helper; gameplay orders use formation reservations/entry.
	var team: Node = $TEAM_ONE if specification.team == 1 else $TEAM_TWO
	var positions: Array = specification.spawn_positions
	if not specification.has("squad"): squad_commands.create_squad(specification)
	for zone in deployment_zones[specification.team]:
		if specification.lane == 3 or specification.lane == zone.lane_id:
			zone.spawn_points.clear()
	for index in range(positions.size()):
		var lane: int = index % 3 if specification.lane == 3 else specification.lane
		var soldier: Unit = UNIT.instantiate()
		soldier.position = positions[index]
		soldier.configure(self, specification, lane)
		soldier.squad_member_index = index
		soldier.squad.members.append(soldier)
		team.add_child(soldier)
		units.append(soldier)
		formation_manager.track_unit(soldier)
		deployment_zones[specification.team][lane].spawn_points.append(positions[index])
		squad_commands.invalidate_enemy_cache()
		unit_spawned.emit(soldier)
	refresh_occupancy()

# One formation function serves validation, ghosts and actual spawning.
func get_spawn_positions(count: int, zone_index: int, enemy: bool = false) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	if zone_index < 0 or zone_index > 3 or count < 1:
		return positions
	var spawn_zones: Array[Rect2] = enemy_zones if enemy else zones
	for index in range(count):
		var lane := index % 3 if zone_index == 3 else zone_index
		var slot := int(index / 3) if zone_index == 3 else index
		var lane_count := int((count + 2 - lane) / 3) if zone_index == 3 else count
		var area := spawn_zones[lane].grow(-tuning.unit_radius - 10)
		var max_columns := maxi(0, int(area.size.x / tuning.spawn_spacing))
		var max_rows := maxi(0, int(area.size.y / tuning.spawn_spacing))
		if max_columns == 0 or lane_count > max_columns * max_rows:
			return []
		var columns := mini(max_columns, lane_count)
		var rows := ceili(float(lane_count) / columns)
		var row := int(slot / columns)
		var row_columns := mini(columns, lane_count - row * columns)
		positions.append(area.position + Vector2(area.size.x * (slot % columns + 0.5) / row_columns, area.size.y * (row + 0.5) / rows))
	return positions


func preset_footprint(team: int, lane: int) -> Rect2:
	if lane == 3:
		return formation_manager.regions[team]
	return enemy_zones[lane] if team == 1 else zones[lane]

func screen_to_battle(screen_position: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen_position

func can_start_footprint(screen_position: Vector2) -> bool:
	return _camera_point_allowed(screen_position) and formation_manager.regions[2].has_point(screen_to_battle(screen_position))

func clear_footprint() -> void:
	footprint_preview.clear()
	footprint_slots.clear()
	for child in preview.get_children():
		preview.remove_child(child)
		child.queue_free()
	zone_overlay.queue_redraw()

func show_footprint(rectangle: Rect2, result: Dictionary) -> void:
	var formation: Dictionary = result.get("formation", {"rectangle": rectangle, "required": 0, "candidate_slots": [], "valid_slots": [], "invalid_slots": [], "capacity": 0})
	var next: Dictionary = formation.duplicate()
	next["is_valid"] = result.is_valid
	next["failure_reason"] = result.failure_reason
	next["rectangle"] = rectangle
	if footprint_preview == next:
		return
	clear_footprint()
	footprint_preview = next
	footprint_slots = formation.get("chosen_slots", [])
	var template := UNIT.instantiate()
	for point in footprint_slots:
		var ghost := Node2D.new()
		ghost.position = point
		preview.add_child(ghost)
		for sprite_name in ["SpriteWeapon", "SpriteBody"]:
			var sprite := template.get_node(sprite_name).duplicate() as Sprite2D
			sprite.material = ghost_material
			ghost.add_child(sprite)
	template.free()
	zone_overlay.queue_redraw()

func deployment_message(reason: String) -> String:
	return {"NOT_ENOUGH_SPACE": "Not enough room", "OUTSIDE_DEPLOYMENT_AREA": "Outside deployment area", "ENEMY_TOO_CLOSE": "Enemy too close", "BLOCKED_BY_TERRAIN": "Blocked by terrain", "RESERVED_SPACE": "Space reserved for incoming units", "FRIENDLY_CONGESTION": "Troops are occupying these spaces", "INSUFFICIENT_COMMAND": "Not enough Command", "NO_UNIT_CARD": "Choose a Unit card", "INCOMPATIBLE_MODIFIER": "Incompatible modifiers", "TOO_MANY_MODIFIERS": "Too many modifiers"}.get(reason, reason)

func spawn_reinforcement(slot: Dictionary, spawn_point: Vector2) -> Unit:
	var soldier: Unit = UNIT.instantiate()
	soldier.position = spawn_point
	var individual: Dictionary = slot.specification.duplicate()
	if individual.has("components"):
		individual.merge(individual.components[individual.member_components[slot.member_index]],true)
	soldier.configure(self, individual, lane_for_x(slot.position.x))
	soldier.squad_member_index = slot.member_index
	soldier.squad.members.append(soldier)
	if not soldier.squad.route_offsets.has(slot.member_index):
		var entry_front: float = slot.specification.spawn_positions[0].y
		soldier.squad.route_offsets[slot.member_index] = Vector2(slot.position.x-slot.rectangle.get_center().x,slot.position.y-entry_front)
	soldier.assigned_formation_slot = spawn_point
	soldier.queue_wait = formation_manager.elapsed - slot.ordered_at
	soldier.reservation_id = slot.id
	soldier.state = Unit.State.ENTERING_BATTLEFIELD
	soldier.has_entered_battlefield = false
	var team: Node = $TEAM_ONE if slot.team == 1 else $TEAM_TWO
	team.add_child(soldier)
	units.append(soldier)
	soldier.squad.refresh_travel()
	formation_manager.track_unit(soldier)
	squad_commands.invalidate_enemy_cache()
	unit_spawned.emit(soldier)
	return soldier

func _draw_zones() -> void:
	var scale: float = 1.0 / $Camera2D.zoom.x
	var score_inset: float = $MapTest.get_tile_size()
	for edge in [score_inset, field_size.y - score_inset]:
		var capture_y: float = edge + tuning.capture_depth if edge < field_size.y * 0.5 else edge - tuning.capture_depth
		zone_overlay.draw_line(Vector2(0, capture_y), Vector2(field_size.x, capture_y), Color(1, 0.8, 0.25, 0.7), 2 * scale)
		zone_overlay.draw_line(Vector2(0, edge), Vector2(field_size.x, edge), Color(1, 0.95, 0.7), 3 * scale)
		zone_overlay.draw_string(ThemeDB.fallback_font, Vector2(30, capture_y - 12 * scale), "CAPTURE — keep moving to score", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(14 * scale), Color(1, 0.85, 0.35))
	for team in ([1, 2] if is_instance_valid(hud) and hud.debug_panel.visible else []):
		var region: Rect2 = formation_manager.regions[team]
		var color := Color(0.2, 0.55, 1) if team == 2 else Color(1, 0.35, 0.25)
		zone_overlay.draw_rect(region, Color(color, 0.12))
		zone_overlay.draw_rect(region, color, false, 2.5 * scale)
		zone_overlay.draw_string(ThemeDB.fallback_font, region.position + Vector2(8, 18) * scale, "FRIENDLY ENTRY AREA - DRAW WIDTH AND RANKS" if team == 2 else "ENEMY REINFORCEMENT AREA", HORIZONTAL_ALIGNMENT_LEFT, -1, int(12 * scale), Color.WHITE)
	if not footprint_preview.is_empty():
		var rectangle: Rect2 = footprint_preview.rectangle
		var color := Color(0.25, 1, 0.55) if footprint_preview.is_valid else Color(1, 0.2, 0.2)
		zone_overlay.draw_rect(rectangle, Color(color, 0.20))
		zone_overlay.draw_rect(rectangle, color, false, 3 * scale)
		for corner in [rectangle.position, rectangle.position + Vector2(rectangle.size.x, 0), rectangle.end, rectangle.position + Vector2(0, rectangle.size.y)]:
			zone_overlay.draw_rect(Rect2(corner - Vector2.ONE * 4 * scale, Vector2.ONE * 8 * scale), color)
		var label := "Space %d / Needed %d  %s" % [footprint_preview.capacity, footprint_preview.required, "Ready" if footprint_preview.is_valid else deployment_message(footprint_preview.failure_reason)]
		zone_overlay.draw_string(ThemeDB.fallback_font, rectangle.position - Vector2(0, 8) * scale, label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(13 * scale), color)
	for slot in formation_manager.reservations.values():
		if slot.team == 2 and slot.state in ["QUEUED", "ENTERING"] and not slot.specification.get("intent_order", false):
			zone_overlay.draw_circle(slot.position, tuning.unit_radius, Color(0.5, 0.8, 1, 0.16))
			zone_overlay.draw_arc(slot.position, tuning.unit_radius, 0, TAU, 20, Color(0.6, 0.85, 1, 0.5), scale)
	if not is_instance_valid(hud) or not hud.debug_panel.visible:
		return
	if not footprint_preview.is_empty():
		for point in footprint_preview.valid_slots:
			zone_overlay.draw_circle(point, 3 * scale, Color(0.3, 1, 0.5))
		for blocked in footprint_preview.invalid_slots:
			zone_overlay.draw_circle(blocked.position, 4 * scale, Color(1, 0.25, 0.25))
	for unit in units:
		if not is_instance_valid(unit) or not unit.is_alive():
			continue
		var radius: float = tuning.spawn_spacing if unit.team_id == 2 else tuning.enemy_exclusion_radius
		zone_overlay.draw_arc(unit.position, radius, 0, TAU, 32, Color(0.4, 0.75, 1, 0.5) if unit.team_id == 2 else Color(1, 0.25, 0.2, 0.5), scale)
	for slot in formation_manager.reservations.values():
		zone_overlay.draw_circle(slot.position, 5 * scale, Color(1, 0.7, 0.15))
		var entry: Vector2 = slot.entry_position
		zone_overlay.draw_circle(entry, 5 * scale, Color(0.4, 0.8, 1))
		if slot.state == "QUEUED":
			UNIT_SYMBOLS.state_icon(zone_overlay, entry + Vector2(18, 0) * scale, 7 * scale, -1)
		if is_instance_valid(slot.unit):
			zone_overlay.draw_line(slot.unit.position, slot.unit.position + slot.unit.init_direction_vector * 180, Color(1, 0.75, 0.3, 0.5), scale)

func crossed_score_line(unit: Unit) -> bool:
	var line: float = $MapTest.get_tile_size()
	return unit.global_position.y <= line if unit.team_id == 2 else unit.global_position.y >= field_size.y - line

func crossed_capture_threshold(unit: Unit) -> bool:
	var depth: float = $MapTest.get_tile_size() + tuning.capture_depth
	return unit.global_position.y <= depth if unit.team_id == 2 else unit.global_position.y >= field_size.y - depth
