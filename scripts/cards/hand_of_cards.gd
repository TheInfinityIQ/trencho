extends Control
const UNIT_SYMBOLS = preload("res://scripts/ui/unit_symbols.gd")

signal card_selected(card)
signal card_deselected(card)
signal hand_changed
@export var starting_deck: Array[String] = [
	"rifle_squad", "rifle_squad", "rifle_squad", "assault_squad", "assault_squad",
	"conscript_wave", "conscript_wave", "commander_mojo", "forced_march", "defensive_officer"]
var game: Node2D
var draw_pile: Array[BattleCard] = []
var discard_pile: Array[BattleCard] = []
var cards: Array[BattleCard] = []
var selected_indices: Array[int] = []
var dragged_index := -1
var pressed_index := -1
var pressed_zone := -1
var pressed_discard := false
var discard_hovered := false
var press_position := Vector2.ZERO
var drag_offset := Vector2.ZERO
var card_lifts: Dictionary = {}
var selection_tween: Tween
var rng := RandomNumberGenerator.new()
var shuffle_count := 0
var message := "Width sets frontage; depth sets ranks. Troops enter from your edge. Right-click clears."
var preview_failure := ""
var has_footprint := false
var footprint := Rect2()
var drawing_footprint := false
var footprint_mode := "draw"
var footprint_anchor := Vector2.ZERO
var footprint_press_world := Vector2.ZERO
var footprint_before_edit := Rect2()
var preview_elapsed := 0.0
const CARD_SIZE := Vector2(132, 190)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rng.seed = game.tuning.random_seed
	for id in starting_deck:
		if game.card_catalog.has(id):
			draw_pile.append(game.card_catalog[id])
	_shuffle(draw_pile)
	_refill_hand()
	get_viewport().size_changed.connect(queue_redraw)

func _shuffle(pile: Array[BattleCard]) -> void:
	for index in range(pile.size() - 1, 0, -1):
		var swap := rng.randi_range(0, index)
		var card := pile[index]
		pile[index] = pile[swap]
		pile[swap] = card

func _draw_card() -> bool:
	if draw_pile.is_empty() and not discard_pile.is_empty():
		draw_pile.assign(discard_pile)
		discard_pile.clear()
		_shuffle(draw_pile)
		shuffle_count += 1
	if draw_pile.is_empty():
		return false
	cards.append(draw_pile.pop_back())
	return true

func _refill_hand() -> void:
	while cards.size() < game.tuning.maximum_hand_size:
		if not _draw_card():
			break
	hand_changed.emit()
	queue_redraw()

func selected_cards() -> Array:
	var package: Array = []
	for index in selected_indices:
		if index >= 0 and index < cards.size():
			package.append(cards[index])
	return package

func _unit_index() -> int:
	for index in selected_indices:
		if cards[index].card_type == BattleCard.Type.UNIT:
			return index
	return -1

func _modifier_count() -> int:
	var count := 0
	for index in selected_indices:
		if cards[index].card_type == BattleCard.Type.MODIFIER:
			count += 1
	return count

func _can_attach(index: int) -> bool:
	if _modifier_count() >= game.tuning.maximum_modifiers:
		return false
	var unit := _unit_index()
	return unit < 0 or cards[index].compatible_with(cards[unit])

func _unit_compatible(index: int) -> bool:
	for selected in selected_indices:
		if cards[selected].card_type == BattleCard.Type.MODIFIER and not cards[selected].compatible_with(cards[index]):
			return false
	return true

func _toggle_card(index: int) -> void:
	if selected_indices.has(index):
		selected_indices.erase(index)
		card_deselected.emit(cards[index])
	elif cards[index].card_type == BattleCard.Type.UNIT:
		if not _unit_compatible(index):
			message = "INCOMPATIBLE_MODIFIER: this Unit cannot use the selected modifiers."
			return
		var previous_unit := _unit_index()
		if previous_unit >= 0:
			selected_indices.erase(previous_unit)
			card_deselected.emit(cards[previous_unit])
		selected_indices.insert(0, index)
		card_selected.emit(cards[index])
	elif _can_attach(index):
		selected_indices.append(index)
		card_selected.emit(cards[index])
	else:
		message = "TOO_MANY_MODIFIERS" if _modifier_count() >= game.tuning.maximum_modifiers else "INCOMPATIBLE_MODIFIER"
		return
	message = "Draw a rectangle in the blue area. Release green to deploy. Right-click clears."
	if _unit_index() < 0 and not selected_indices.is_empty():
		message = "Modifiers selected. Choose a Unit to complete the package. Right-click clears."
	_animate_selection()
	_update_preview(get_viewport().get_mouse_position())
func _animate_selection() -> void:
	if selection_tween:
		selection_tween.kill()
	if cards.is_empty():
		return
	selection_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for index in range(cards.size()):
		selection_tween.tween_method(_set_lift.bind(index), float(card_lifts.get(index, 0)), 22.0 if selected_indices.has(index) else 0.0, 0.18)

func _set_lift(value: float, index: int) -> void:
	card_lifts[index] = value
	queue_redraw()

func _clear_selected_events() -> void:
	for card in selected_cards():
		card_deselected.emit(card)
	selected_indices.clear()

func cancel_selection() -> void:
	_clear_selected_events()
	dragged_index = -1
	pressed_index = -1
	pressed_zone = -1
	pressed_discard = false
	discard_hovered = false
	preview_failure = ""
	game.clear_footprint()
	has_footprint = false
	drawing_footprint = false
	_animate_selection()
	queue_redraw()

func _consume(indices: Array[int]) -> void:
	var used: Array[int] = indices.duplicate()
	used.sort()
	used.reverse()
	cancel_selection()
	if selection_tween:
		selection_tween.kill()
	for index in used:
		discard_pile.append(cards.pop_at(index))
	card_lifts.clear()
	_refill_hand()

func _play_selected(zone: int) -> bool:
	var result: Dictionary = game.deployment_manager.request_deployment(2, selected_cards(), zone)
	if not result.is_valid:
		message = result.failure_reason + ": deployment rejected; no cards or Command spent."
		return false
	_consume(selected_indices)
	message = "Reinforcements ordered: %d units, %.0f Command" % [result.resolved_deployment.quantity, result.total_cost]
	return true

func _discard_selected() -> bool:
	if selected_indices.is_empty() or not game.battle_active:
		return false
	var count := selected_indices.size()
	_consume(selected_indices)
	message = "Discarded %d card(s) and drew replacements" % count
	return true

func _evaluate_footprint() -> Dictionary:
	var result: Dictionary = game.deployment_manager.validate_formation(2, selected_cards(), footprint)
	game.show_footprint(footprint, result)
	preview_failure = result.failure_reason
	return result

func _confirm_footprint() -> bool:
	if not has_footprint:
		return false
	var result: Dictionary = game.deployment_manager.request_formation(2, selected_cards(), footprint)
	if not result.is_valid:
		game.show_footprint(footprint, result)
		preview_failure = result.failure_reason
		message = "Adjust the red rectangle or change cards. No cards or Command spent."
		return false
	_consume(selected_indices)
	message = "Reinforcements ordered: %d units, %.0f Command" % [result.resolved_deployment.quantity, result.total_cost]
	return true

func _update_preview(point: Vector2) -> void:
	discard_hovered = not selected_indices.is_empty() and _discard_rect().has_point(point)
	if has_footprint and not selected_indices.is_empty() and game.battle_active and not discard_hovered:
		_evaluate_footprint()
	else:
		game.clear_footprint()
		preview_failure = ""

func _process(delta: float) -> void:
	preview_elapsed += delta
	if not selected_indices.is_empty() and preview_elapsed >= 0.1:
		preview_elapsed = 0.0
		_update_preview(get_viewport().get_mouse_position())
	queue_redraw()

func _corners(rectangle: Rect2) -> Array[Vector2]:
	return [rectangle.position, rectangle.position + Vector2(rectangle.size.x, 0), rectangle.end, rectangle.position + Vector2(0, rectangle.size.y)]

func _start_footprint(point: Vector2) -> bool:
	if selected_indices.is_empty() or not game._camera_point_allowed(point):
		return false
	var world: Vector2 = game.screen_to_battle(point)
	footprint_before_edit = footprint
	footprint_press_world = world
	footprint_mode = "draw"
	if has_footprint:
		var corners := _corners(footprint)
		for index in range(4):
			if (game.get_canvas_transform() * corners[index]).distance_to(point) <= 10:
				footprint_mode = "resize"
				footprint_anchor = corners[(index + 2) % 4]
				drawing_footprint = true
				return true
		if footprint.has_point(world):
			footprint_mode = "move"
			drawing_footprint = true
			return true
	if not game.formation_manager.regions[2].has_point(world):
		return false
	footprint_anchor = world
	footprint = Rect2(world, Vector2.ZERO)
	has_footprint = true
	drawing_footprint = true
	_update_preview(point)
	return true

func _drag_footprint(point: Vector2) -> void:
	var world: Vector2 = game.screen_to_battle(point)
	if footprint_mode == "move":
		footprint = Rect2(footprint_before_edit.position + world - footprint_press_world, footprint_before_edit.size)
	else:
		footprint = Rect2(footprint_anchor, world - footprint_anchor).abs()
	# Never clamp or auto-expand the requested footprint.
	_update_preview(point)
func _card_rect(index: int) -> Rect2:
	var screen := get_viewport_rect().size
	var step := minf(144, maxf(20, (screen.x - 300 - CARD_SIZE.x) / maxi(cards.size() - 1, 1)))
	var width := (cards.size() - 1) * step + CARD_SIZE.x
	return Rect2(Vector2((screen.x - width) * 0.5 + index * step, screen.y - 205 - float(card_lifts.get(index, 0))), CARD_SIZE)

func _deck_rect() -> Rect2:
	return Rect2(Vector2(18, get_viewport_rect().size.y - 183), Vector2(108, 160))

func _discard_rect() -> Rect2:
	return Rect2(Vector2(get_viewport_rect().size.x - 126, get_viewport_rect().size.y - 183), Vector2(108, 160))

func _card_at(point: Vector2) -> int:
	var hit_order: Array[int] = selected_indices.duplicate()
	hit_order.reverse()
	for index in range(cards.size() - 1, -1, -1):
		if not hit_order.has(index):
			hit_order.append(index)
	for index in hit_order:
		if _card_rect(index).has_point(point):
			return index
	return -1

func _input(event: InputEvent) -> void:
	# Continue an existing drag over HUD controls, including release outside the
	# region. Native controls must not swallow its release or activate underneath.
	if drawing_footprint or dragged_index >= 0 or pressed_index >= 0:
		if event is InputEventMouseMotion or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed):
			_unhandled_input(event)
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		cancel_selection()
		get_viewport().set_input_as_handled()
		return
	if not game.battle_active:
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			cancel_selection()
			get_viewport().set_input_as_handled()
		elif event.keycode in [KEY_ENTER, KEY_KP_ENTER] and has_footprint:
			_confirm_footprint()
			get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			press_position = event.position
			pressed_index = _card_at(event.position)
			pressed_discard = not selected_indices.is_empty() and _discard_rect().has_point(event.position)
			if pressed_index >= 0:
				drag_offset = event.position - _card_rect(pressed_index).position
			elif not pressed_discard:
				_start_footprint(event.position)
		else:
			if drawing_footprint:
				_drag_footprint(event.position)
				drawing_footprint = false
				_confirm_footprint()
			elif dragged_index >= 0:
				if _discard_rect().has_point(event.position):
					_discard_selected()
				else:
					message = "Cards selected. Now drag a rectangle inside the blue deployment area."
				dragged_index = -1
			elif pressed_discard and _discard_rect().has_point(event.position):
				_discard_selected()
			elif pressed_index >= 0 and _card_at(event.position) == pressed_index:
				_toggle_card(pressed_index)
			pressed_index = -1
			pressed_discard = false
		get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion:
		if drawing_footprint:
			_drag_footprint(event.position)
			get_viewport().set_input_as_handled()
			queue_redraw()
			return
		elif pressed_index >= 0 and dragged_index < 0 and event.position.distance_to(press_position) > 8:
			dragged_index = pressed_index
			if not selected_indices.has(dragged_index):
				_toggle_card(dragged_index)
			if not selected_indices.has(dragged_index):
				dragged_index = -1
		_update_preview(event.position)
	queue_redraw()
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(game) and is_instance_valid(game.preview):
		cancel_selection()

func package_description() -> String:
	if selected_indices.is_empty():
		return "Select a Unit and up to two Modifiers in either order; drag a formation in the blue area"
	var names: Array[String] = []
	for card in selected_cards():
		names.append(card.display_name)
	var result: Dictionary = game.deployment_manager.resolve_package(selected_cards())
	if not result.is_valid:
		return " + ".join(names) + " | " + ("Choose a compatible Unit card" if result.failure_reason == "NO_UNIT_CARD" else result.failure_reason)
	return "%s | Units %d -> %d | Command %.0f -> %.0f" % [" + ".join(names), result.resolved_deployment.base_quantity, result.resolved_deployment.quantity, cards[_unit_index()].command_cost, result.total_cost]

func _draw() -> void:
	var screen := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(0, screen.y - 270, screen.x, 270), Color(0.045, 0.065, 0.085, 0.98))
	draw_string(font, Vector2(16, screen.y - 250), package_description(), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.7, 0.9, 1))
	var detail := message
	var resolved: Dictionary = game.deployment_manager.resolve_package(selected_cards())
	if resolved.is_valid:
		var stats: Dictionary = resolved.resolved_deployment
		detail = "Health %.0f | DPS %.1f | Speed %.0f | %s" % [stats.health, stats.damage / maxf(stats.attack_interval, 0.001), stats.move_speed, game.deployment_message(preview_failure) if not preview_failure.is_empty() else message]
	draw_string(font, Vector2(16, screen.y - 233), detail, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.8, 0.5) if not preview_failure.is_empty() else Color(0.85, 0.85, 0.85))
	_paint_piles()
	for index in range(cards.size()):
		if not selected_indices.has(index) and index != dragged_index:
			_paint_card(_card_rect(index), cards[index], index)
	for index in selected_indices:
		if index != dragged_index:
			_paint_card(_card_rect(index), cards[index], index)
	if dragged_index >= 0:
		var rect := Rect2(get_viewport().get_mouse_position() - drag_offset, CARD_SIZE)
		_paint_card(rect, cards[dragged_index], dragged_index)
		if selected_indices.size() > 1:
			draw_string(font, rect.position + Vector2(8, -8), "%d-card package" % selected_indices.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)

func _paint_piles() -> void:
	var deck := _deck_rect()
	var discard := _discard_rect()
	var font := ThemeDB.fallback_font
	for offset in [Vector2(6, -6), Vector2(3, -3), Vector2.ZERO]:
		var rect := Rect2(deck.position + offset, deck.size)
		draw_rect(rect, Color(0.07, 0.18, 0.32))
		draw_rect(rect, Color(0.35, 0.65, 0.95), false, 2)
	draw_rect(deck.grow(-10), Color(0.35, 0.65, 0.95), false, 1)
	draw_string(font, deck.position + Vector2(22, 45), "DRAW", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	draw_string(font, deck.position + Vector2(18, 75), "%d cards" % draw_pile.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	draw_string(font, deck.position + Vector2(11, 118), "Auto-shuffle", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.65, 0.8, 1))
	draw_rect(discard, Color(0.28, 0.21, 0.12) if discard_hovered else Color(0.13, 0.12, 0.14))
	draw_rect(discard, Color(1, 0.8, 0.35) if discard_hovered else Color(0.65, 0.55, 0.4), false, 4 if discard_hovered else 2)
	if not discard_pile.is_empty() and discard_pile.back().art:
		draw_texture_rect(discard_pile.back().art, Rect2(discard.position + Vector2(34, 8), Vector2(40, 54)), false, Color(0.7, 0.7, 0.7))
	draw_string(font, discard.position + Vector2(12, 88), "DISCARD", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
	draw_string(font, discard.position + Vector2(19, 110), "%d cards" % discard_pile.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	draw_string(font, discard.position + Vector2(7, 145), "Discard selection", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.85, 0.6))

func _paint_card(rect: Rect2, card: BattleCard, index: int) -> void:
	var selected := selected_indices.has(index)
	var disabled := not selected and (not _can_attach(index) if card.card_type == BattleCard.Type.MODIFIER else not _unit_compatible(index))
	var tint := Color(0.4, 0.4, 0.4) if disabled else Color.WHITE
	var border := Color(0.4, 0.8, 1) if card.card_type == BattleCard.Type.UNIT else Color(0.9, 0.65, 0.3)
	draw_rect(rect, Color(0.10, 0.17, 0.22) if selected else Color(0.08, 0.10, 0.13))
	draw_rect(rect, Color.WHITE if selected else border * tint, false, 3 if selected else 2)
	var font := ThemeDB.fallback_font
	draw_string(font, rect.position + Vector2(6, 18), card.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, tint)
	if card.art:
		draw_texture_rect(card.art, Rect2(rect.position + Vector2(25, 25), Vector2(82, 110)), false, tint)
	draw_string(font, rect.position + Vector2(7, 146), "UNIT" if card.card_type == BattleCard.Type.UNIT else "MODIFIER", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, border * tint)
	var effects: Array[String] = []
	if card.card_type == BattleCard.Type.UNIT:
		UNIT_SYMBOLS.type_icon(self, rect.position + Vector2(116, 143), 7, card.card_id, tint)
		effects.assign(["%d infantry" % card.quantity, "%.0f HP / %.1f DPS" % [card.health, card.damage / maxf(card.attack_interval, 0.001)]])
	else:
		var labels := {"quantity": "units", "health": "health", "move_speed": "speed", "damage": "DPS"}
		for key in labels:
			if card.multiplicative.has(key):
				var percent := roundi((float(card.multiplicative[key]) - 1) * 100)
				effects.append(("+" if percent > 0 else "") + str(percent) + "% " + labels[key])
	for line in range(mini(effects.size(), 2)):
		draw_string(font, rect.position + Vector2(7, 160 + line * 12), effects[line], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, tint)
	draw_string(font, rect.position + Vector2(7, 186), str(card.command_cost) + " Command", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.55, 0.9, 1) * tint)
