extends Control

const RECOGNIZER = preload("res://scripts/systems/gesture_recognizer.gd")
const SYMBOLS = preload("res://scripts/ui/unit_symbols.gd")
var game: Node
var blueprint: PanelContainer
var blueprint_preview: Control
var package_label: Label
var blueprint_width := 940.0
var blueprint_depth := 460.0
var pending_cards: Array = []
var pending_rectangle := Rect2()
var entry_center_x := 0.0
var pending_ready := false
var gesture_active := false
var stroke := PackedVector2Array()
var gesture_debug: Dictionary = {}
var failure_reason := ""
var gesture_origin := Vector2.ZERO
var feedback: Array[Dictionary] = []
var had_command_selection := false
var frame_time := 0
var blueprint_box := Rect2()
var blueprint_resizing := false
var resize_origin := Vector2.ZERO
var resize_scale := 1.0
var resize_start_box := Rect2()
var resize_axes := Vector2.ONE
var resize_sign := Vector2.ONE

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame_time = Time.get_ticks_usec()
	_build_blueprint()
	game.squad_commands.command_resolved.connect(_on_result)

func _build_blueprint() -> void:
	blueprint = PanelContainer.new()
	blueprint.visible = false
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.035, 0.055, 0.075, 0.98)
	background.border_color = Color(0.55, 0.8, 0.9)
	background.set_border_width_all(2)
	blueprint.add_theme_stylebox_override("panel", background)
	blueprint.size = Vector2(620, 470)
	add_child(blueprint)
	var content := Control.new()
	content.custom_minimum_size = Vector2(620, 470)
	blueprint.add_child(content)
	package_label = Label.new()
	package_label.position = Vector2(24, 16)
	package_label.size = Vector2(570, 100)
	package_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(package_label)
	blueprint_preview = Control.new()
	blueprint_preview.position = Vector2(24, 120)
	blueprint_preview.size = Vector2(570, 250)
	blueprint_preview.draw.connect(_draw_blueprint)
	content.add_child(blueprint_preview)
	var confirm := Button.new()
	confirm.text = "Use formation → draw an order"
	confirm.position = Vector2(24, 405)
	confirm.size = Vector2(370, 40)
	confirm.pressed.connect(confirm_blueprint)
	content.add_child(confirm)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.position = Vector2(420, 405)
	cancel.size = Vector2(165, 40)
	cancel.pressed.connect(cancel_current)
	content.add_child(cancel)

func open_blueprint(world: Vector2) -> void:
	var resolved: Dictionary = game.deployment_manager.resolve_package(game.hand.selected_cards())
	if not resolved.is_valid:
		fail(resolved.failure_reason, world)
		return
	game.squad_commands.clear_selection()
	pending_cards = game.hand.selected_cards().duplicate()
	entry_center_x = world.x
	pending_ready = false
	blueprint.visible = true
	blueprint.position = (get_viewport_rect().size - blueprint.size) * 0.5
	game.planning.begin()
	set_blueprint_size(blueprint_width, blueprint_depth)

func _blueprint_scale() -> float:
	return minf((blueprint_preview.size.x - 40) / minf(game.field_size.x, 3000), (blueprint_preview.size.y - 40) / 1800)

func set_blueprint_size(width: float, depth: float) -> void:
	var diameter: float = game.tuning.unit_radius * 2
	blueprint_width = clampf(width, diameter, minf(game.field_size.x, 3000))
	blueprint_depth = clampf(depth, diameter, 1800)
	# Fixed world-to-preview scale: no auto-fit/recenter while the pointer moves.
	blueprint_box = Rect2(Vector2(20,20), Vector2(blueprint_width,blueprint_depth) * _blueprint_scale())
	_update_blueprint()

func _update_blueprint() -> void:
	pending_rectangle = Rect2(clampf(entry_center_x - blueprint_width * 0.5, 0, game.field_size.x - blueprint_width), 0, blueprint_width, blueprint_depth)
	var resolved: Dictionary = game.deployment_manager.resolve_package(pending_cards)
	if not resolved.is_valid: return
	var names: Array[String] = []
	for card in pending_cards: names.append(card.display_name)
	var capacity: int = game.formation_manager.generate_slots(pending_rectangle, 2).size()
	package_label.text = "SQUAD BLUEPRINT\n%s\n%d soldiers · %.0f Command · %.0f × %.0f formation · %d spaces\nDrag a corner or edge to resize. No cards or Command spent yet." % [" + ".join(names), resolved.resolved_deployment.quantity, resolved.total_cost, blueprint_width, blueprint_depth, capacity]
	blueprint_preview.queue_redraw()

func _blueprint_handles() -> Array:
	var start := blueprint_box.position
	var end := blueprint_box.end
	var center := blueprint_box.get_center()
	return [
		{"point":start,"anchor":end,"axes":Vector2.ONE},
		{"point":Vector2(end.x,start.y),"anchor":Vector2(start.x,end.y),"axes":Vector2.ONE},
		{"point":end,"anchor":start,"axes":Vector2.ONE},
		{"point":Vector2(start.x,end.y),"anchor":Vector2(end.x,start.y),"axes":Vector2.ONE},
		{"point":Vector2(start.x,center.y),"anchor":Vector2(end.x,center.y),"axes":Vector2(1,0)},
		{"point":Vector2(end.x,center.y),"anchor":Vector2(start.x,center.y),"axes":Vector2(1,0)},
		{"point":Vector2(center.x,start.y),"anchor":Vector2(center.x,end.y),"axes":Vector2(0,1)},
		{"point":Vector2(center.x,end.y),"anchor":Vector2(center.x,start.y),"axes":Vector2(0,1)}
	]

func _begin_blueprint_resize(screen_point: Vector2) -> bool:
	var local := screen_point - blueprint_preview.global_position
	var nearest := 14.0
	var chosen: Dictionary = {}
	for handle in _blueprint_handles():
		var distance: float = local.distance_to(handle.point)
		if distance < nearest:
			nearest = distance
			chosen = handle
	if chosen.is_empty(): return false
	blueprint_resizing = true
	resize_origin = chosen.anchor
	resize_scale = _blueprint_scale()
	resize_start_box = blueprint_box
	resize_axes = chosen.axes
	resize_sign = (chosen.point-chosen.anchor).sign()
	return true

func _resize_blueprint(screen_point: Vector2) -> void:
	var point := screen_point - blueprint_preview.global_position
	var minimum := Vector2(20,20)
	var maximum := blueprint_preview.size - Vector2(20,20)
	var position := resize_start_box.position
	var size := resize_start_box.size
	var diameter: float = game.tuning.unit_radius * 2 * resize_scale
	for axis in range(2):
		if resize_axes[axis] == 0: continue
		var offset: float = point[axis] - resize_origin[axis]
		var direction: float = signf(offset) if absf(offset) > 0.001 else resize_sign[axis]
		var available: float = maximum[axis]-resize_origin[axis] if direction > 0 else resize_origin[axis]-minimum[axis]
		if available < diameter:
			direction = -direction
			available = maximum[axis]-resize_origin[axis] if direction > 0 else resize_origin[axis]-minimum[axis]
		var limit: float = minf(game.field_size.x,3000) if axis == 0 else 1800
		var length := clampf(absf(offset), diameter, minf(available,limit*resize_scale))
		var edge: float = resize_origin[axis]+direction*length
		position[axis] = minf(edge,resize_origin[axis])
		size[axis] = length
	blueprint_box = Rect2(position,size)
	blueprint_width = size.x/resize_scale
	blueprint_depth = size.y/resize_scale
	_update_blueprint()

func _draw_blueprint() -> void:
	if pending_cards.is_empty(): return
	var resolved: Dictionary = game.deployment_manager.resolve_package(pending_cards)
	if not resolved.is_valid: return
	var positions: Array = game.formation_manager.generate_slots(pending_rectangle, 2)
	var count: int = resolved.resolved_deployment.quantity
	var color := Color(0.4, 0.9, 1) if positions.size() >= count else Color(1, 0.25, 0.2)
	blueprint_preview.draw_rect(blueprint_box, color, false, 2)
	for handle in _blueprint_handles():
		blueprint_preview.draw_rect(Rect2(handle.point - Vector2.ONE * 4, Vector2.ONE * 8), Color.WHITE)
	positions = game.formation_manager.choose_slots(2, pending_rectangle, mini(count, positions.size()), positions)
	for point in positions:
		blueprint_preview.draw_circle(blueprint_box.position + (point-pending_rectangle.position) * _blueprint_scale(), maxf(2,game.tuning.unit_radius*_blueprint_scale()), color)
func confirm_blueprint() -> void:
	_update_blueprint()
	var resolved: Dictionary = game.deployment_manager.validate_squad(2, pending_cards, pending_rectangle, "ADVANCE")
	if not resolved.is_valid:
		fail(resolved.failure_reason, game.field_size * Vector2(0.5, 0.75))
		return
	blueprint.visible = false
	pending_ready = true
	game.hand.message = "Drag the white order knob: line = Advance, loop = Defend. Right-click backs out."

func knob_position() -> Vector2:
	var world: Vector2 = game.squad_commands.centroid()
	if pending_ready: world = Vector2(pending_rectangle.get_center().x, game.field_size.y - 450)
	var screen: Vector2 = game.get_canvas_transform() * world + Vector2(0, -38)
	var allowed: Rect2 = game.battlefield_view_rect().grow(-26)
	return screen.clamp(allowed.position, allowed.end)

func begin_gesture(point: Vector2) -> void:
	gesture_active = true
	game.camera_panning = false
	stroke = PackedVector2Array([point])
	gesture_origin = game.screen_to_battle(point) if pending_ready else game.squad_commands.centroid()
	had_command_selection = not pending_ready
	game.planning.begin()

func finish_gesture() -> Dictionary:
	gesture_active = false
	gesture_debug = RECOGNIZER.classify(stroke)
	if not gesture_debug.success:
		return fail("UNRECOGNIZED_GESTURE", gesture_origin)
	var kind: String = gesture_debug.command_type
	var center: Vector2 = game.screen_to_battle(gesture_debug.center)
	var radius: float = gesture_debug.radius / game.get_node("Camera2D").zoom.x
	var result: Dictionary
	if pending_ready:
		if game.hand.selected_cards() != pending_cards:
			return fail("INVALID_CARD", gesture_origin)
		var deployment: Dictionary = game.deployment_manager.request_squad(2, pending_cards, pending_rectangle, kind, center, radius)
		if not deployment.is_valid: return fail(deployment.failure_reason, center)
		result = deployment.command_result
		game.hand._consume(game.hand.selected_indices)
		pending_cards.clear()
		pending_ready = false
	else:
		result = game.squad_commands.issue_selected(kind, center, radius)
	stroke.clear()
	had_command_selection = false
	game.planning.end()
	return result

func fail(reason: String, origin: Vector2) -> Dictionary:
	failure_reason = reason
	var result: Dictionary = game.squad_commands.result(false, "", reason)
	feedback.append({"result": result, "origin": origin, "age": 0.0, "end": origin})
	stroke.clear()
	game.hand.message = reason.replace("_", " ").capitalize() + ". Retry or right-click to cancel."
	return result

func _on_result(result: Dictionary) -> void:
	failure_reason = result.failure_reason
	feedback.append({"result": result, "origin": gesture_origin, "age": 0.0, "end": game.screen_to_battle(stroke[-1]) if not stroke.is_empty() else gesture_origin + Vector2(0, -350)})
	if result.expanded: game.hand.message = "Defense area expanded to fit squad"

func cancel_current() -> void:
	blueprint_resizing = false
	if gesture_active:
		gesture_active = false
		had_command_selection = false
		fail("COMMAND_CANCELLED", gesture_origin)
	elif blueprint.visible or pending_ready:
		blueprint.visible = false
		pending_ready = false
		pending_cards.clear()
		stroke.clear()
		game.hand.message = "Setup cancelled. Cards and Command remain unspent."
	elif not game.squad_commands.selected_ids.is_empty():
		game.squad_commands.clear_selection()
	else:
		game.hand.cancel_selection()
	game.planning.end()

func close_all() -> void:
	gesture_active = false
	pending_ready = false
	pending_cards.clear()
	blueprint.visible = false
	stroke.clear()
	game.squad_commands.clear_selection()
	game.planning.end()

func _input(event: InputEvent) -> void:
	if not game.battle_active: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			cancel_current()
			get_viewport().set_input_as_handled()
		elif event.keycode in [KEY_ENTER, KEY_KP_ENTER] and blueprint.visible:
			confirm_blueprint()
			get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion and blueprint_resizing:
		_resize_blueprint(event.position)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and gesture_active:
		if stroke[-1].distance_to(event.position) >= 3 and stroke.size() < 512: stroke.append(event.position)
		get_viewport().set_input_as_handled()
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT: return
	if blueprint.visible:
		if not event.pressed and blueprint_resizing:
			_resize_blueprint(event.position)
			blueprint_resizing = false
			get_viewport().set_input_as_handled()
			return
		if event.pressed and _begin_blueprint_resize(event.position):
			get_viewport().set_input_as_handled()
			return
		# Native blueprint controls receive their own clicks; nothing passes to battle.
		if not blueprint.get_global_rect().has_point(event.position): get_viewport().set_input_as_handled()
		return
	if not event.pressed and gesture_active:
		if stroke[-1].distance_to(event.position) >= 1: stroke.append(event.position)
		finish_gesture()
		get_viewport().set_input_as_handled()
		return
	if not event.pressed: return
	if (pending_ready or not game.squad_commands.selected_ids.is_empty()) and event.position.distance_to(knob_position()) <= 22:
		begin_gesture(event.position)
		get_viewport().set_input_as_handled()
		return
	if pending_ready:
		# Card package is frozen until the initial order commits or setup is cancelled.
		if event.position.y >= get_viewport_rect().size.y - 270: get_viewport().set_input_as_handled()
		return
	if not game._camera_point_allowed(event.position): return
	var world: Vector2 = game.screen_to_battle(event.position)
	var unit: Unit = game.squad_commands.unit_at(world, maxf(game.tuning.unit_radius, 12.0 / game.get_node("Camera2D").zoom.x))
	if unit != null:
		game.hand.cancel_selection()
		game.squad_commands.select_unit(unit, event.shift_pressed)
		get_viewport().set_input_as_handled()
	elif not game.hand.selected_indices.is_empty():
		open_blueprint(world)
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(game) and is_instance_valid(game.planning):
		if gesture_active or pending_ready or blueprint.visible: cancel_current()

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var real_delta := minf(0.1, float(now - frame_time) / 1000000.0)
	frame_time = now
	blueprint.position = (get_viewport_rect().size - blueprint.size) * 0.5
	if had_command_selection and game.planning.active and game.squad_commands.selected_squads().is_empty():
		gesture_active = false
		had_command_selection = false
		game.squad_commands.clear_selection()
		fail("SQUAD_DESTROYED", gesture_origin)
		game.planning.end()
	for event in feedback: event.age += real_delta
	feedback = feedback.filter(func(event): return event.age < 1.8)
	queue_redraw()

func _arrow(from: Vector2, to: Vector2, color: Color, width: float = 3) -> void:
	if from.distance_to(to) < 2: return
	draw_line(from, to, color, width, true)
	var back := to.direction_to(from) * 13
	draw_polyline(PackedVector2Array([to + back.rotated(0.5), to, to + back.rotated(-0.5)]), color, width, true)

func _draw() -> void:
	var transform: Transform2D = game.get_canvas_transform()
	var zoom: float = game.get_node("Camera2D").zoom.x
	var planning_alpha: float = game.planning.blend
	if planning_alpha > 0.01:
		var edge: float = game.tuning.no_hold_depth
		var top_left := transform * Vector2.ZERO
		var bottom_right := transform * Vector2(game.field_size.x, edge)
		var zone := Rect2(top_left, bottom_right - top_left)
		draw_rect(zone, Color(1, 0.7, 0.2, 0.12 * planning_alpha))
		draw_line(Vector2(zone.position.x, zone.end.y), zone.end, Color(1, 0.8, 0.4, planning_alpha), 2)
		for x in range(floori(zone.position.x), ceili(zone.end.x), 22):
			draw_line(Vector2(x, zone.position.y), Vector2(minf(x + zone.size.y, zone.end.x), zone.end.y), Color(1, 0.8, 0.4, 0.25 * planning_alpha))
		draw_string(ThemeDB.fallback_font, Vector2(maxf(20, zone.position.x + 12), maxf(110, zone.end.y - 12)), "NO-HOLD  /  Defend prohibited · Advance allowed", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 0.9, 0.6, planning_alpha))
	for squad in game.squad_commands.squads.values():
		if squad.team != 2: continue
		if squad.selected:
			for unit in squad.living_members():
				var pulse := 0.0
				for event in feedback:
					if event.result.success and event.result.affected_squad_ids.has(squad.squad_id): pulse = maxf(pulse, maxf(0, 1 - event.age / 0.45))
				draw_arc(transform * unit.global_position, maxf(9, (game.tuning.unit_radius + 14) * zoom), 0, TAU, 32, Color.WHITE, 2.5 + pulse * 3, true)
		if squad.intent == "DEFEND":
			var color := Color(0.5, 0.85, 1, 0.65 if squad.selected else 0.12)
			draw_arc(transform * squad.defense_center, squad.defense_radius * zoom, 0, TAU, 64, color, 2, true)
			SYMBOLS.shield_icon(self, transform * squad.defense_center, 10, color)
	if (pending_ready or not game.squad_commands.selected_ids.is_empty()) and not blueprint.visible:
		var knob := knob_position()
		draw_circle(knob, 18, Color(0.05, 0.12, 0.18))
		draw_arc(knob, 18, 0, TAU, 32, Color.WHITE, 3, true)
		draw_line(knob - Vector2(7, 0), knob + Vector2(7, 0), Color.WHITE, 2)
		draw_line(knob - Vector2(0, 7), knob + Vector2(0, 7), Color.WHITE, 2)
	if stroke.size() > 1: draw_polyline(stroke, Color(1, 1, 1, 0.9), 3, true)
	for event in feedback:
		var result: Dictionary = event.result
		var alpha: float = clampf(1 - event.age / 1.8, 0, 1)
		var origin: Vector2 = transform * event.origin
		if not result.success:
			origin.y -= 14 * event.age + 40 * event.age * event.age
			var color := Color(1, 0.65, 0.4, alpha)
			if result.failure_reason == "INVALID_DEFEND_AREA": SYMBOLS.shield_icon(self, origin, 14, color)
			else: draw_rect(Rect2(origin - Vector2(11, 14), Vector2(22, 28)), color, false, 2)
			draw_line(origin + Vector2(-14, 14), origin + Vector2(14, -14), color, 3, true)
			draw_string(ThemeDB.fallback_font, origin + Vector2(20, 4), result.failure_reason.replace("_", " ").capitalize(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
		elif result.command_type == "DEFEND":
			var center: Vector2 = transform * result.defense_center
			var pulse: float = 1 + 0.06 * sin(minf(event.age / 0.4, 1) * PI)
			draw_arc(center, result.defense_radius * zoom * pulse, 0, TAU, 64, Color(0.6, 0.95, 1, alpha), 3, true)
			SYMBOLS.shield_icon(self, center, 14, Color(1, 1, 1, alpha))
			_arrow(origin, center, Color(1, 1, 1, alpha))
		else:
			_arrow(origin, transform * event.end, Color(1, 1, 1, alpha), 4)

