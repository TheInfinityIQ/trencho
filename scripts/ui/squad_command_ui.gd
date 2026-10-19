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
var live_recognition: Dictionary = {}
var preview_target := -1
var preview_projection: Dictionary = {}
var front_preview: Dictionary = {}
var front_preview_elapsed := 0.0
var recognized_samples := -1
var territory_geometry: Dictionary = {}
var geometry_builds := 0
var confirm_button: Button
var capacity_label: Label
var notice := ""
var hovered_point := -1
var live_status: Dictionary = {}
var preview_elapsed := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame_time = Time.get_ticks_usec()
	_build_blueprint()
	game.squad_commands.command_resolved.connect(_on_result)
	game.squad_commands.selection_changed.connect(clear_notice)

func _build_blueprint() -> void:
	blueprint = PanelContainer.new()
	blueprint.visible = false
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.035, 0.055, 0.075, 0.98)
	background.border_color = Color(0.55, 0.8, 0.9)
	background.set_border_width_all(2)
	blueprint.add_theme_stylebox_override("panel", background)
	blueprint.size = Vector2(620, 490)
	add_child(blueprint)
	var content := Control.new()
	content.custom_minimum_size = Vector2(620, 490)
	blueprint.add_child(content)
	package_label = Label.new()
	package_label.position = Vector2(24, 16)
	package_label.size = Vector2(570, 84)
	package_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	package_label.add_theme_font_size_override("font_size",14)
	content.add_child(package_label)
	blueprint_preview = Control.new()
	capacity_label = Label.new()
	capacity_label.position = Vector2(24, 102)
	capacity_label.size = Vector2(570, 24)
	content.add_child(capacity_label)
	blueprint_preview.position = Vector2(24, 132)
	blueprint_preview.size = Vector2(570, 250)
	blueprint_preview.draw.connect(_draw_blueprint)
	content.add_child(blueprint_preview)
	var help := Label.new()
	help.position = Vector2(24, 387)
	help.size = Vector2(570, 34)
	help.add_theme_font_size_override("font_size", 13)
	help.text = "Drag edges/corners to resize. Defend faces the enemy.\nNothing is spent until your order is accepted. Esc / right-click: cancel."
	content.add_child(help)
	var confirm := Button.new()
	confirm_button = confirm
	confirm.text = "Use formation -> draw an order"
	confirm.position = Vector2(24, 430)
	confirm.size = Vector2(370, 40)
	confirm.pressed.connect(confirm_blueprint)
	content.add_child(confirm)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.position = Vector2(420, 430)
	cancel.size = Vector2(165, 40)
	cancel.pressed.connect(cancel_current)
	content.add_child(cancel)

func open_blueprint(world: Vector2) -> void:
	clear_notice()
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
	var default_size: Vector2 = game.deployment_manager.default_blueprint_size(resolved.resolved_deployment.quantity)
	set_blueprint_size(default_size.x,default_size.y)

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
	pending_rectangle = Rect2(clampf(entry_center_x-blueprint_width*0.5,0,game.field_size.x-blueprint_width),0,blueprint_width,blueprint_depth)
	var resolved: Dictionary = game.deployment_manager.resolve_package(pending_cards)
	if not resolved.is_valid: return
	var composition: Array[String] = []
	var modifiers: Array[String] = []
	for index in range(resolved.resolved_deployment.components.size()):
		var component: Dictionary = resolved.resolved_deployment.components[index]
		composition.append("%s: %s ×%d" % ["Front" if index == 0 else "Rear", component.unit_type.replace("_"," ").capitalize(),component.quantity])
	for card in pending_cards:
		if card.card_type == BattleCard.Type.MODIFIER: modifiers.append(card.display_name)
	var capacity: int = game.formation_manager.generate_slots(pending_rectangle,2).size()
	package_label.text = "SQUAD BLUEPRINT · Cost %.0f · Available %.1f Command\n%s\nModifiers: %s" % [resolved.total_cost, game.economies[2].current_command, "\n".join(composition), ", ".join(modifiers) if not modifiers.is_empty() else "None"]
	var quantity: int = resolved.resolved_deployment.quantity
	capacity_label.text = "✓ %d soldiers / %d spaces" % [quantity, capacity] if capacity >= quantity else "! Needs %d spaces · %d available — enlarge the formation" % [quantity, capacity]
	capacity_label.modulate = Color(0.65, 0.95, 1) if capacity >= quantity else Color(1, 0.8, 0.5)
	_update_confirm()
	blueprint_preview.queue_redraw()

func _update_confirm() -> void:
	var validation: Dictionary = game.deployment_manager.validate_squad(2, pending_cards, pending_rectangle, "ADVANCE")
	confirm_button.disabled = not validation.is_valid
	confirm_button.tooltip_text = "Continue to draw an order; nothing spent yet" if validation.is_valid else recovery_text(validation.failure_reason)
	if not validation.is_valid and validation.failure_reason != "NOT_ENOUGH_SPACE":
		capacity_label.text = "! " + recovery_text(validation.failure_reason)
		capacity_label.modulate = Color(1, 0.8, 0.5)

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
	clear_notice()
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
	blueprint_preview.draw_string(ThemeDB.fallback_font, Vector2(340, 20), "FRONT ↑", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	blueprint_preview.draw_rect(blueprint_box, color, false, 2)
	for handle in _blueprint_handles():
		blueprint_preview.draw_rect(Rect2(handle.point - Vector2.ONE * 4, Vector2.ONE * 8), Color.WHITE)
	positions = game.formation_manager.choose_slots(2, pending_rectangle, mini(count, positions.size()), positions)
	var specification: Dictionary = resolved.resolved_deployment
	specification.spawn_positions = positions
	game.deployment_manager.assign_components(specification)
	for index in range(positions.size()):
		var point: Vector2 = positions[index]
		var type_color := color if specification.member_components[index] == 0 else Color(1,0.85,0.5)
		var local := blueprint_box.position + (point-pending_rectangle.position) * _blueprint_scale()
		var component: Dictionary = specification.components[specification.member_components[index]]
		SYMBOLS.type_icon(blueprint_preview, local, maxf(4,game.tuning.unit_radius*_blueprint_scale()), component.unit_type, type_color)
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
	clear_notice()
	live_status = {}
	live_recognition = {}
	recognized_samples = -1
	game.hand.has_footprint = false
	game.hand.drawing_footprint = false
	game.hand.pressed_index = -1
	game.hand.dragged_index = -1
	game.clear_footprint()
	gesture_active = true
	game.camera_panning = false
	stroke = PackedVector2Array([point])
	gesture_origin = game.screen_to_battle(point) if pending_ready else game.squad_commands.centroid()
	had_command_selection = not pending_ready
	game.planning.begin()

func finish_gesture() -> Dictionary:
	gesture_active = false
	gesture_debug = RECOGNIZER.classify(stroke)
	var endpoint: Vector2 = game.screen_to_battle(stroke[-1]) if not stroke.is_empty() else Vector2.INF
	var anchor: int = game.squad_commands.reinforcement_target(2,endpoint) if gesture_debug.command_type=="ADVANCE" else -1
	game.telemetry.event("COMMAND_GESTURE",{"gesture_type":gesture_debug.command_type,"classified":gesture_debug.success,"anchor_targeted":anchor>=0,"point_id":anchor,"final_command":"REINFORCE" if anchor>=0 else gesture_debug.command_type,"failure_reason":gesture_debug.failure_reason})
	if not gesture_debug.success:
		return fail(gesture_debug.failure_reason, gesture_origin)
	var kind: String = gesture_debug.command_type
	var route := PackedVector2Array()
	for index in range(1,gesture_debug.route.size()): route.append(game.screen_to_battle(gesture_debug.route[index]))
	var approach := PackedVector2Array()
	for point in gesture_debug.route: approach.append(game.screen_to_battle(point))
	var center: Vector2 = game.screen_to_battle(gesture_debug.center)
	var radius: float = gesture_debug.radius / game.get_node("Camera2D").zoom.x
	var result: Dictionary
	if pending_ready:
		if game.hand.selected_cards() != pending_cards:
			return fail("INVALID_CARD", gesture_origin)
		var deployment: Dictionary = game.deployment_manager.request_squad(2, pending_cards, pending_rectangle, kind, center, radius, route, approach)
		if not deployment.is_valid: return fail(deployment.failure_reason, center)
		result = deployment.command_result
		game.hand._consume(game.hand.selected_indices)
		pending_cards.clear()
		pending_ready = false
	else:
		result = game.squad_commands.issue_selected(kind, center, radius, route, approach)
	stroke.clear()
	had_command_selection = false
	game.planning.end()
	return result

func fail(reason: String, origin: Vector2) -> Dictionary:
	game.telemetry.event("COMMAND_REJECTED",{"team":2,"failure_reason":reason,"origin":origin})
	gesture_active = false
	had_command_selection = false
	game.hand.has_footprint = false
	game.hand.drawing_footprint = false
	game.clear_footprint()
	game.planning.end()
	failure_reason = reason
	var result: Dictionary = game.squad_commands.result(false, "", reason)
	feedback.append({"result": result, "origin": origin, "age": 0.0, "end": origin})
	stroke.clear()
	notice = recovery_text(reason) + (" Cards and Command unspent." if pending_ready or blueprint.visible else " Existing orders kept.")
	game.hand.message = notice
	return result

func _on_result(result: Dictionary) -> void:
	# AI orders use the same signal but do not own player feedback or notices.
	if result.get("team", 2) != 2: return
	failure_reason = result.failure_reason
	# Bot/system orders share this signal; only our live stroke owns the HUD notice.
	if not stroke.is_empty(): notice = "" if result.success else recovery_text(result.failure_reason) + " Existing orders kept."
	feedback.append({"result": result, "origin": gesture_origin, "age": 0.0, "end": game.screen_to_battle(stroke[-1]) if not stroke.is_empty() else gesture_origin + Vector2(0, -350)})
	if result.expanded: game.hand.message = "Defensive front assigned"

func cancel_current() -> void:
	clear_notice()
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
		notice = game.hand.message
	elif not game.squad_commands.selected_ids.is_empty():
		game.squad_commands.clear_selection()
	else:
		game.hand.cancel_selection()
	game.planning.end()

func close_all() -> void:
	clear_notice()
	gesture_active = false
	pending_ready = false
	pending_cards.clear()
	blueprint.visible = false
	stroke.clear()
	game.squad_commands.clear_selection()
	game.planning.end()

func _input(event: InputEvent) -> void:
	if not game.battle_active: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if game.hud.controls_help.visible:
			game.hud.controls_help.visible = false
			get_viewport().set_input_as_handled()
			return
		cancel_current()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if game.hud.controls_help.visible:
				game.hud.controls_help.visible = false
				get_viewport().set_input_as_handled()
				return
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
	var point_id: int = game.squad_commands.point_anchor_at(world,14.0/game.get_node("Camera2D").zoom.x)
	if point_id >= 0:
		game.hand.cancel_selection()
		game.squad_commands.select_point(point_id)
		get_viewport().set_input_as_handled()
		return
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
	if gesture_active and stroke.size() != recognized_samples:
		recognized_samples = stroke.size()
		live_recognition = RECOGNIZER.classify(stroke)
		preview_target = -1
		preview_projection = {}
		if live_recognition.success and live_recognition.command_type == "ADVANCE" and not stroke.is_empty():
			preview_target = game.squad_commands.reinforcement_target(2,game.screen_to_battle(stroke[-1]))
			if preview_target >= 0:
				var extra := 0
				if pending_ready:
					extra = game.deployment_manager.resolve_package(pending_cards).resolved_deployment.quantity
				else:
					for squad in game.squad_commands.selected_squads():
						if squad.order_id != preview_target: extra += game.squad_commands.count_members(squad)
				preview_projection = game.squad_commands.points.projection(preview_target,extra)
	else:
		if not gesture_active:
			preview_target = -1
			preview_projection = {}
			recognized_samples = -1
	frame_time = now
	front_preview_elapsed += real_delta
	if gesture_active and (front_preview.is_empty() or front_preview_elapsed >= 0.1):
		front_preview = _front_preview_plan()
		front_preview_elapsed = 0.0
	elif not gesture_active: front_preview = {}
	preview_elapsed += real_delta
	if gesture_active and (live_status.is_empty() or preview_elapsed >= 0.1):
		live_status = preview_state(live_recognition)
		preview_elapsed = 0.0
	if blueprint.visible: _update_blueprint()
	hovered_point = -1
	var pointer := get_viewport().get_mouse_position()
	if not blueprint.visible and not gesture_active and not pending_ready and game._camera_point_allowed(pointer):
		hovered_point = game.squad_commands.point_anchor_at(game.screen_to_battle(pointer), 14.0 / game.get_node("Camera2D").zoom.x)
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

func clear_notice() -> void:
	notice = ""
	failure_reason = ""
	feedback = feedback.filter(func(event): return event.result.success)

func recovery_text(reason: String) -> String:
	match reason:
		"AMBIGUOUS_GESTURE", "UNRECOGNIZED_GESTURE": return "Draw an open route or close a full loop. Retry from the white handle."
		"INVALID_DEFEND_LOCATION", "INVALID_DEFEND_AREA": return "The whole formation must fit in clear space, inside the battlefield and outside the No-Hold Zone."
		"POSITION_UNREACHABLE": return "Keep the route and defense inside usable battlefield space."
		"NOT_ENOUGH_SPACE", "INVALID_FORMATION": return "Enlarge the formation using its edges or corners."
		"INSUFFICIENT_COMMAND": return "Not enough Command. Wait for regeneration or cancel setup."
		"SQUAD_RETREATING": return "Routed squads cannot take orders until they reach home."
		"SQUAD_DESTROYED", "NO_SELECTED_UNITS": return "No surviving force selected. Select another squad or position."
		"NO_UNIT_CARD": return "Choose at least one compatible Unit card."
		"INVALID_CARD": return "The package changed. Cancel setup and select your cards again."
		"COMMAND_CANCELLED": return "Drawing cancelled. Retry from the handle or right-click to go back."
		"BATTLE_ENDED": return "Battle ended. Choose Play again or return to Menu."
	return reason.replace("_", " ").capitalize() + ". Retry or right-click to go back."

# Read-only prediction: use the same package and defense validators as acceptance.
# Do not call issue_selected/prune here: a preview must never mutate live orders.
func preview_state(recognition: Dictionary) -> Dictionary:
	var response := {"valid": false, "text": "Draw an open route or close a full loop.", "target_id": -1, "front_plan": {}}
	if not recognition.get("success", false): return response
	var kind: String = recognition.command_type
	var route := PackedVector2Array()
	for index in range(1, recognition.route.size()): route.append(game.screen_to_battle(recognition.route[index]))
	var approach := PackedVector2Array()
	for point in recognition.route: approach.append(game.screen_to_battle(point))
	var center: Vector2 = game.screen_to_battle(recognition.center)
	var reason := ""
	var count := 0
	if pending_ready:
		var validation: Dictionary = game.deployment_manager.validate_squad(2, pending_cards, pending_rectangle, kind, center, 0, route, approach)
		if not validation.is_valid: reason = validation.failure_reason
		response.front_plan = validation.get("defense_plan",{})
		if game.hand.selected_cards() != pending_cards: reason = "INVALID_CARD"
	else:
		var group: Array = game.squad_commands.selected_squads()
		if group.is_empty(): reason = "NO_SELECTED_UNITS"
		for squad in group:
			count += game.squad_commands.count_members(squad)
			if squad.retreating: reason = "SQUAD_RETREATING"
		for waypoint in route:
			if not waypoint.is_finite() or not Rect2(Vector2.ZERO,game.field_size).has_point(waypoint): reason = "POSITION_UNREACHABLE"
		var target: int = game.squad_commands.reinforcement_target(2,route[-1]) if kind == "ADVANCE" and not route.is_empty() else -1
		if reason.is_empty() and (kind == "DEFEND" or target >= 0):
			var plan: Dictionary = game.squad_commands.fronts.plan(group,center,route,target,Vector2.ZERO,game.squad_commands.reinforcement_preference(target,approach) if target>=0 else Vector2.INF)
			response.front_plan = plan
			if not plan.success: reason = plan.failure_reason
	if not game.battle_active: reason = "BATTLE_ENDED"
	if not reason.is_empty():
		response.text = "Cannot release: " + recovery_text(reason)
		return response
	if kind == "ADVANCE" and not route.is_empty(): response.target_id = game.squad_commands.reinforcement_target(2, route[-1])
	response.valid = true
	response.text = "Release: Establish defense" if kind == "DEFEND" else ("Release: Reinforce this position" if response.target_id >= 0 else "Release: Advance along route")
	if response.target_id >= 0:
		var roles: Array = response.front_plan.get("proposed_blocks",[]).map(func(block): return "RESERVE" if block.role=="RESERVE" else "FRONTAGE")
		response.text += " · "+response.front_plan.get("preferred_sector","CENTER")
		if not roles.is_empty(): response.text += " · "+", ".join(roles)
	if response.target_id >= 0 and preview_projection.get("warning", false): response.text += " · Capacity risk"
	return response

func selection_text() -> String:
	var group: Array = game.squad_commands.selected_squads()
	var living := 0
	var queued := 0
	for squad in group:
		living += squad.living_members().size()
		queued += int(game.formation_manager.pending_counts.get(squad.squad_id, 0))
	var text := "%d squads · %d living selected" % [group.size(), living]
	if queued > 0: text += " · %d queued" % queued
	return text

func context_details() -> String:
	var text := context_text()
	var id: int = game.squad_commands.selected_point_id
	if game.squad_commands.orders.has(id):
		var point: Dictionary = game.squad_commands.orders[id]
		text += "\nPosition: %d established · %d inbound (not all inbound squads selected)." % [point.established, point.inbound]
	return text

func context_text() -> String:
	if gesture_active: return live_status.get("text", "Draw an open route or close a full loop.") + " · Esc: cancel drawing"
	if not notice.is_empty(): return notice
	if blueprint.visible: return "Resize your formation, then continue to draw an order. Nothing spent yet."
	if pending_ready: return "Formation ready · Drag the white handle to draw an order · Esc: cancel setup"
	if not game.squad_commands.selected_ids.is_empty(): return "Drag white handle to re-command · Click a soldier for its squad · Esc: clear selection"
	if hovered_point >= 0: return "Click the shield to select defending squads; entirely inbound squads stay unselected."
	if not game.hand.selected_indices.is_empty(): return "Click battlefield for formation · Hover package summary for modified stats · Esc: clear cards"
	return "Select cards to deploy · Click a soldier for its squad, or a friendly shield for defending squads"

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
		draw_string(ThemeDB.fallback_font, Vector2(maxf(20, zone.position.x + 12), maxf(110, zone.end.y - 12)), "NO-HOLD  /  Defend prohibited  |  Advance allowed", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 0.9, 0.6, planning_alpha))
	for squad in game.squad_commands.squads.values():
		if squad.team != 2: continue
		if squad.selected and game.squad_commands.selected_point_id < 0:
			for unit in squad.living_members():
				var pulse := 0.0
				for event in feedback:
					if event.result.success and event.result.affected_squad_ids.has(squad.squad_id): pulse = maxf(pulse, maxf(0, 1 - event.age / 0.45))
				draw_arc(transform * unit.global_position, maxf(9, (game.tuning.unit_radius + 14) * zoom), 0, TAU, 32, Color.WHITE, 2.5 + pulse * 3, true)
	for id in game.squad_commands.orders:
		var point: Dictionary = game.squad_commands.orders[id]
		var selected := false
		for squad_id in point.squads:
			if game.squad_commands.selected_ids.has(squad_id): selected = true
		var color := Color(0.5,0.85,1,0.7 if selected else 0.20) if point.team == 2 else Color(1,0.45,0.35,0.4)
		_draw_territory(point.cells,Color(color,color.a*0.35),transform)
		_draw_front(point,transform,color)
		var whole_point: bool = game.squad_commands.selected_point_id == id
		if hovered_point == id:
			draw_arc(transform*point.center, 20, 0, TAU, 32, Color.WHITE, 2, true)
			var label_position: Vector2 = (transform*point.center+Vector2(24,-22)).clamp(Vector2(20,110),get_viewport_rect().size-Vector2(225,290))
			draw_style_box(_hint_background(),Rect2(label_position-Vector2(6,18),Vector2(214,28)))
			draw_string(ThemeDB.fallback_font,label_position,"Select defending squads",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color.WHITE)
		if whole_point:
			draw_circle(transform*point.center,21,Color(0.1,0.2,0.28,0.9))
			draw_arc(transform*point.center,22,0,TAU,32,Color.WHITE,3,true)
		SYMBOLS.shield_icon(self,transform*point.center,14 if whole_point else 10,Color.WHITE if whole_point else color)
		if point.lifecycle == "PENDING":
			draw_string(ThemeDB.fallback_font,transform*point.center+Vector2(12,4),"Inbound",HORIZONTAL_ALIGNMENT_LEFT,-1,12,color)
	if gesture_active and preview_target >= 0 and game.squad_commands.orders.has(preview_target):
		var point: Dictionary = game.squad_commands.orders[preview_target]
		_draw_territory(point.cells,Color(0.6,0.9,1,0.8),transform)
		_draw_territory(preview_projection.get("cells",{}),Color(0.6,0.9,1,0.25),transform)
		var label := "Reinforce position"
		if preview_projection.get("warning",false): label += "  |  Capacity risk"
		draw_string(ThemeDB.fallback_font,transform*point.center+Vector2(15,-20),label,HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color(1,0.85,0.5))
	elif gesture_active and live_recognition.get("success",false) and live_recognition.command_type == "DEFEND":
		SYMBOLS.shield_icon(self,live_recognition.center,15,Color(0.65,0.95,1,0.7))
	if gesture_active and not front_preview.is_empty():
		var front_plan: Dictionary = front_preview
		for block in front_plan.get("proposed_blocks",[]):
			var tint := Color(0.65,0.95,1,0.85) if front_preview.get("success",false) else Color(1,0.4,0.25,0.85)
			for slot in block.slots:
				draw_arc(transform*slot.home,maxf(3,game.tuning.unit_radius*zoom),0,TAU,12,tint,1.5,true)
			if not block.slots.is_empty():
				draw_string(ThemeDB.fallback_font,transform*block.slots[0].home+Vector2(8,-12),"RESERVE" if block.role == "RESERVE" else "FRONTAGE",HORIZONTAL_ALIGNMENT_LEFT,-1,13,tint)
	if (pending_ready or not game.squad_commands.selected_ids.is_empty()) and not blueprint.visible:
		var knob := knob_position()
		draw_circle(knob, 18, Color(0.05, 0.12, 0.18))
		draw_arc(knob, 18, 0, TAU, 32, Color.WHITE, 3, true)
		draw_line(knob - Vector2(7, 0), knob + Vector2(7, 0), Color.WHITE, 2)
		draw_line(knob - Vector2(0, 7), knob + Vector2(0, 7), Color.WHITE, 2)
	if stroke.size() > 1:
		draw_polyline(stroke, Color(1, 1, 1, 0.65), 2, true)
		if live_recognition.get("success",false) and live_recognition.route.size() > 1:
			draw_polyline(live_recognition.route,Color(0.6,0.9,1,0.6),4,true)
			_arrow(live_recognition.route[-2],live_recognition.route[-1],Color.WHITE,2)
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
			draw_string(ThemeDB.fallback_font, origin + Vector2(20, 4), "Order not issued — see instructions below", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
		elif result.command_type == "DEFEND":
			var center: Vector2 = transform * result.defense_center
			var pulse: float = 1 + 0.06 * sin(minf(event.age / 0.4, 1) * PI)
			draw_arc(center, 22 * pulse, 0, TAU, 32, Color(0.6, 0.95, 1, alpha), 3, true)
			SYMBOLS.shield_icon(self, center, 14, Color(1, 1, 1, alpha))
			_arrow(origin, center, Color(1, 1, 1, alpha))
		else:
			var route: PackedVector2Array = result.get("route",PackedVector2Array())
			if route.size() > 1:
				var path := PackedVector2Array()
				for point in route: path.append(transform*point)
				draw_polyline(path,Color(1,1,1,alpha),3,true)
			else: _arrow(origin, transform * event.end, Color(1, 1, 1, alpha), 4)



func _hint_background() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025,0.045,0.065,0.96)
	return style

func _territory_geometry(cells: Dictionary, size: float) -> Dictionary:
	var key := hash([cells,size])
	if territory_geometry.has(key):
		var cached: Dictionary = territory_geometry[key]
		if cached.size == size and cached.source == cells: return cached
	if territory_geometry.size() >= 32: territory_geometry.clear()
	geometry_builds += 1
	var by_row: Dictionary = {}
	var boundary := PackedVector2Array()
	for cell in cells:
		if not by_row.has(cell.y): by_row[cell.y] = []
		by_row[cell.y].append(cell.x)
		var start := Vector2(cell)*size
		var corners := [start,start+Vector2(size,0),start+Vector2(size,size),start+Vector2(0,size)]
		var neighbors := [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]
		for index in range(4):
			if not cells.has(cell+neighbors[index]):
				boundary.append(corners[index])
				boundary.append(corners[(index+1)%4])
	var rows: Array[Rect2] = []
	for y in by_row:
		var columns: Array = by_row[y]
		columns.sort()
		var first: int = columns[0]
		var last := first
		for index in range(1,columns.size()):
			if columns[index] == last+1:
				last = columns[index]
			else:
				rows.append(Rect2(Vector2(first,y)*size,Vector2(last-first+1,1)*size))
				first = columns[index]
				last = first
		rows.append(Rect2(Vector2(first,y)*size,Vector2(last-first+1,1)*size))
	var geometry := {"source":cells.duplicate(),"size":size,"rows":rows,"boundary":boundary}
	territory_geometry[key] = geometry
	return geometry

func _draw_territory(cells: Dictionary, color: Color, transform: Transform2D) -> void:
	var geometry := _territory_geometry(cells,game.squad_commands.points.cell_size())
	for row in geometry.rows:
		var corners := PackedVector2Array([transform*row.position,transform*(row.position+Vector2(row.size.x,0)),transform*row.end,transform*(row.position+Vector2(0,row.size.y))])
		draw_colored_polygon(corners,Color(color,color.a*0.12))
	if not geometry.boundary.is_empty():
		var boundary := PackedVector2Array()
		for point in geometry.boundary: boundary.append(transform*point)
		draw_multiline(boundary,color,2,true)


func _draw_front(point: Dictionary, transform: Transform2D, tint: Color) -> void:
	var fronts = game.squad_commands.fronts
	var half: float = fronts.spacing()*0.43
	for block in fronts.blocks(point):
		for slot in block.slots:
			if slot.front:
				var center: Vector2 = slot.home+point.facing*fronts.spacing()*0.4
				var occupied: bool = fronts.occupied(slot)
				var unit: Unit = fronts.occupant(slot)
				var color := Color(tint,0.9 if unit != null and unit.defense_established and unit.position.distance_to(slot.home)<fronts.spacing()*0.4 else 0.35)
				if occupied:
					draw_line(transform*(center-point.lateral*half),transform*(center+point.lateral*half),color,3,true)
				else:
					draw_circle(transform*center,2,Color(1,0.55,0.3,0.5))
			elif fronts.occupied(slot):
				draw_circle(transform*slot.home,maxf(2,game.get_node("Camera2D").zoom.x*12),Color(tint,0.22))


# Independent, read-only front prediction shared by the base UI and HUD extensions.
func _front_preview_plan() -> Dictionary:
	if not live_recognition.get("success",false): return {}
	var kind: String = live_recognition.command_type
	var route := PackedVector2Array()
	for index in range(1,live_recognition.route.size()): route.append(game.screen_to_battle(live_recognition.route[index]))
	var approach := PackedVector2Array()
	for point in live_recognition.route: approach.append(game.screen_to_battle(point))
	var center: Vector2 = game.screen_to_battle(live_recognition.center)
	if pending_ready:
		var validation: Dictionary = game.deployment_manager.validate_squad(2,pending_cards,pending_rectangle,kind,center,0,route,approach)
		return validation.get("defense_plan",{})
	var target: int = game.squad_commands.reinforcement_target(2,route[-1]) if kind == "ADVANCE" and not route.is_empty() else -1
	if kind != "DEFEND" and target < 0: return {}
	return game.squad_commands.fronts.plan(game.squad_commands.selected_squads(),center,route,target,Vector2.ZERO,game.squad_commands.reinforcement_preference(target,approach) if target>=0 else Vector2.INF)
