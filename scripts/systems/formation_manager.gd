extends RefCounted

var battle: Node
var regions: Dictionary = {}
var reservations: Dictionary = {}
var pending: Array[Dictionary] = []
var pending_counts: Dictionary = {}
var next_id := 1
var next_deployment_id := 1
var elapsed := 0.0
var spawn_clock := {1: 0.0, 2: 0.0}
var terrain_shape := CircleShape2D.new()
var body_cells: Dictionary = {}
var unit_cells: Dictionary = {}
var recovery: RefCounted

func _init(owner_battle: Node) -> void:
	battle = owner_battle
	recovery = preload("res://scripts/systems/movement_recovery.gd").new(self)
	var size: Vector2 = battle.field_size
	regions[2] = Rect2(size.x * 0.05, size.y * 0.70, size.x * 0.90, size.y * 0.26)
	regions[1] = Rect2(size.x * 0.05, size.y * 0.04, size.x * 0.90, size.y * 0.26)
	terrain_shape.radius = battle.tuning.unit_radius

func generate_slots(rectangle: Rect2, team: int) -> Array[Vector2]:
	var slots: Array[Vector2] = []
	var diameter: float = battle.tuning.unit_radius * 2.0
	var spacing: float = maxf(battle.tuning.spawn_spacing, diameter + 4)
	if rectangle.size.x < diameter or rectangle.size.y < diameter:
		return slots
	var columns := mini(128, floori((rectangle.size.x - diameter) / spacing) + 1)
	var rows := mini(128, floori((rectangle.size.y - diameter) / spacing) + 1)
	var origin := rectangle.get_center() - Vector2(columns - 1, rows - 1) * spacing * 0.5
	for row in range(rows):
		var y := row if team == 2 else rows - 1 - row
		for column in range(columns):
			slots.append(origin + Vector2(column, y) * spacing)
	return slots

func terrain_blocks(point: Vector2) -> bool:
	var begin := Time.get_ticks_usec() if battle.profile_enabled else 0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = terrain_shape
	query.transform = Transform2D(0, point)
	query.collision_mask = 1
	query.collide_with_areas = false
	var blocked: bool = not battle.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()
	if battle.profile_enabled:
		battle.profile_add("terrain_us",Time.get_ticks_usec()-begin)
		battle.profile_add("terrain_queries",1)
	return blocked

func contains_center(rectangle: Rect2, point: Vector2) -> bool:
	return point.x >= rectangle.position.x - 0.01 and point.y >= rectangle.position.y - 0.01 and point.x <= rectangle.end.x + 0.01 and point.y <= rectangle.end.y + 0.01

func choose_slots(team: int, rectangle: Rect2, count: int, available: Array) -> Array[Vector2]:
	var chosen: Array[Vector2] = []
	if count < 1 or available.is_empty():
		return chosen
	var remaining: Array = available.duplicate()
	var inner := rectangle.grow(-battle.tuning.unit_radius)
	var spacing: float = maxf(battle.tuning.spawn_spacing, battle.tuning.unit_radius * 2 + 4)
	var max_columns := maxi(1, floori(inner.size.x / spacing) + 1)
	var max_rows := maxi(1, floori(inner.size.y / spacing) + 1)
	var columns := clampi(ceili(sqrt(count * maxf(spacing, inner.size.x) / maxf(spacing, inner.size.y))), maxi(1, ceili(float(count) / max_rows)), mini(max_columns, count))
	var rows := ceili(float(count) / columns)
	# Balance partial rows, spread them through the requested shape, then choose
	# the nearest remaining legal candidates. Holes never force overlap.
	for row in range(rows):
		var row_count := int(count / rows) + (1 if row < count % rows else 0)
		var y_ratio := float(row) / (rows - 1) if rows > 1 else 0.5
		if team == 1:
			y_ratio = 1.0 - y_ratio
		for column in range(row_count):
			if remaining.is_empty():
				return chosen
			var x_ratio := float(column) / (row_count - 1) if row_count > 1 else 0.5
			var target := inner.position + inner.size * Vector2(x_ratio, y_ratio)
			var nearest := 0
			for index in range(1, remaining.size()):
				if target.distance_squared_to(remaining[index]) < target.distance_squared_to(remaining[nearest]):
					nearest = index
			chosen.append(remaining.pop_at(nearest))
	return chosen

func block_reason(team: int, point: Vector2, ignore_id: int = -1, ignore_unit: Unit = null) -> String:
	if not regions.has(team) or not contains_center(regions[team].grow(-battle.tuning.unit_radius), point):
		return "OUTSIDE_DEPLOYMENT_AREA"
	var spacing: float = maxf(battle.tuning.spawn_spacing, battle.tuning.unit_radius * 2 + 4)
	for id in reservations:
		if id != ignore_id and point.distance_squared_to(reservations[id].position) < spacing * spacing - 0.01:
			return "RESERVED_SPACE"
	for unit in battle.units:
		if unit == ignore_unit or not is_instance_valid(unit) or not unit.is_alive():
			continue
		var distance := point.distance_squared_to(unit.global_position)
		if unit.team_id == team:
			if distance < spacing * spacing - 0.01:
				return "FRIENDLY_CONGESTION"
		elif distance < pow(battle.tuning.enemy_exclusion_radius, 2):
			return "ENEMY_TOO_CLOSE"
	if terrain_blocks(point):
		return "BLOCKED_BY_TERRAIN"
	return ""

func evaluate(team: int, rectangle: Rect2, count: int) -> Dictionary:
	var result := {"rectangle": rectangle, "candidate_slots": [], "valid_slots": [], "invalid_slots": [], "required": count, "capacity": 0, "is_valid": false, "failure_reason": "OUTSIDE_DEPLOYMENT_AREA"}
	if not regions.has(team) or not rectangle.size.is_finite() or not rectangle.position.is_finite() or not regions[team].encloses(rectangle) or rectangle.size.x <= 0 or rectangle.size.y <= 0:
		return result
	result.candidate_slots = generate_slots(rectangle, team)
	for point in result.candidate_slots:
		var reason := block_reason(team, point)
		if reason.is_empty():
			result.valid_slots.append(point)
		else:
			result.invalid_slots.append({"position": point, "reason": reason})
	result.capacity = result.valid_slots.size()
	result["chosen_slots"] = choose_slots(team, rectangle, mini(count, result.capacity), result.valid_slots)
	result.is_valid = count > 0 and result.capacity >= count
	result.failure_reason = "" if result.is_valid else "NOT_ENOUGH_SPACE"
	if not result.is_valid and result.candidate_slots.size() >= count:
		for reason in ["ENEMY_TOO_CLOSE", "BLOCKED_BY_TERRAIN", "RESERVED_SPACE", "FRIENDLY_CONGESTION"]:
			for blocked in result.invalid_slots:
				if blocked.reason == reason:
					result.failure_reason = reason
					return result
	return result

func entry_positions(team: int, points: Array) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	if points.is_empty():
		return positions
	var front: float = points[0].y
	for point in points:
		front = minf(front, point.y) if team == 2 else maxf(front, point.y)
	for point in points:
		positions.append(entry_point(team, point.x) + Vector2(0, point.y - front))
	return positions

func reserve(specification: Dictionary) -> void:
	battle.deployment_manager.assign_components(specification)
	var entries := entry_positions(specification.team, specification.spawn_positions)
	var deployment_id := next_deployment_id
	next_deployment_id += 1
	for index in range(specification.spawn_positions.size()):
		var point: Vector2 = specification.spawn_positions[index]
		var id := next_id
		next_id += 1
		var slot := {"id": id, "team": specification.team, "position": point,
			"entry_position": entries[index], "deployment_id": deployment_id,
			"ordered_at": elapsed, "member_index": index, "rectangle": specification.requested_rectangle,
			"state": "QUEUED", "unit": null, "specification": specification}
		reservations[id] = slot
		pending.append(slot)
		var squad_id: int = specification.squad.squad_id
		pending_counts[squad_id] = pending_counts.get(squad_id,0)+1

func release_unit(unit: Unit) -> void:
	for id in reservations.keys():
		if reservations[id].unit == unit:
			reservations.erase(id)

func clear() -> void:
	recovery.clear()
	pending.clear()
	pending_counts.clear()
	reservations.clear()

func tick(delta: float) -> void:
	elapsed += delta
	recovery.tick()
	for id in reservations.keys():
		var unit = reservations[id].unit
		if unit != null and (not is_instance_valid(unit) or not unit.is_alive() or unit.has_entered_battlefield):
			reservations.erase(id)
	for team in [1, 2]:
		spawn_clock[team] = maxf(0, spawn_clock[team] - delta)
		if spawn_clock[team] > 0:
			continue
		# One eligible rank per interval, all clear files in that rank together.
		# A blocked file waits without holding up safe files or other formations.
		var selected_deployment := -1
		var selected_rank := 0.0
		for slot in pending.duplicate():
			if slot.team != team:
				continue
			if selected_deployment != -1 and (slot.deployment_id != selected_deployment or not is_equal_approx(slot.entry_position.y, selected_rank)):
				continue
			if not can_move_to(slot.entry_position, null):
				continue
			selected_deployment = slot.deployment_id
			selected_rank = slot.entry_position.y
			var unit: Unit = battle.spawn_reinforcement(slot, slot.entry_position)
			slot.unit = unit
			slot.state = "ENTERING"
			pending.erase(slot)
			var squad_id: int = slot.specification.squad.squad_id
			pending_counts[squad_id] = pending_counts.get(squad_id,1)-1
		if selected_deployment != -1:
			spawn_clock[team] = battle.tuning.reinforcement_interval

func entry_point(team: int, x: float) -> Vector2:
	return Vector2(x, -battle.tuning.offscreen_spawn_margin if team == 1 else battle.field_size.y + battle.tuning.offscreen_spawn_margin)

func flow_counts(team: int) -> Dictionary:
	var counts := {"queued": 0, "entering": 0, "active": 0, "advancing": 0, "engaging": 0, "capturing": 0, "exiting": 0, "dead": battle.deaths_by_team[team], "oldest_incoming": 0.0}
	for slot in pending:
		if slot.team == team:
			counts.queued += 1
			counts.oldest_incoming = maxf(counts.oldest_incoming, elapsed - slot.ordered_at)
	for unit in battle.get_node("TEAM_ONE" if team == 1 else "TEAM_TWO").get_children():
		if not unit is Unit:
			continue
		if unit.state == Unit.State.EXITING:
			counts.exiting += 1
		elif unit.is_alive():
			if not unit.has_entered_battlefield:
				counts.entering += 1
				counts.oldest_incoming = maxf(counts.oldest_incoming, unit.queue_wait + unit.spawn_age)
			else:
				counts.active += 1
			if unit.state == Unit.State.ADVANCING: counts.advancing += 1
			if unit.state == Unit.State.ENGAGING: counts.engaging += 1
			if unit.state == Unit.State.CAPTURING: counts.capturing += 1
	counts["incoming"] = counts.queued + counts.entering
	return counts

func _body_cell_size() -> float:
	return maxf(1, battle.tuning.unit_radius * 2 + 2)

func track_unit(unit: Unit) -> void:
	if not unit.is_alive():
		untrack_unit(unit)
		return
	var cell := Vector2i((unit.global_position / _body_cell_size()).floor())
	if unit_cells.has(unit) and unit_cells[unit] == cell: return
	untrack_unit(unit)
	if not body_cells.has(cell): body_cells[cell] = []
	body_cells[cell].append(unit)
	unit_cells[unit] = cell

func untrack_unit(unit: Unit) -> void:
	if not unit_cells.has(unit): return
	var cell: Vector2i = unit_cells[unit]
	body_cells[cell].erase(unit)
	if body_cells[cell].is_empty(): body_cells.erase(cell)
	unit_cells.erase(unit)

func near_units(center: Vector2, radius: float) -> Array:
	var result: Array = []
	var first := Vector2i(((center-Vector2.ONE*radius)/_body_cell_size()).floor())
	var last := Vector2i(((center+Vector2.ONE*radius)/_body_cell_size()).floor())
	for y in range(first.y,last.y+1):
		for x in range(first.x,last.x+1):
			for unit in body_cells.get(Vector2i(x,y),[]):
				if is_instance_valid(unit) and unit.is_alive() and unit.position.distance_to(center) <= radius: result.append(unit)
	result.sort_custom(func(a,b): return a.simulation_id < b.simulation_id)
	return result

func cancel_pending_team(team: int) -> void:
	pending = pending.filter(func(slot): return slot.team != team)
	pending_counts.clear()
	for slot in pending:
		var id: int = slot.specification.squad.squad_id
		pending_counts[id] = pending_counts.get(id,0)+1

func can_move_to(point: Vector2, ignored: Unit) -> bool:
	var begin := Time.get_ticks_usec() if battle.profile_enabled else 0
	var minimum: float = battle.tuning.unit_radius * 2 + 2
	var first := Vector2i(((point - Vector2.ONE * minimum) / _body_cell_size()).floor())
	var last := Vector2i(((point + Vector2.ONE * minimum) / _body_cell_size()).floor())
	for y in range(first.y,last.y+1):
		for x in range(first.x,last.x+1):
			for unit in body_cells.get(Vector2i(x,y),[]):
				if unit != ignored and is_instance_valid(unit) and unit.is_alive() and unit.global_position.distance_squared_to(point) < minimum * minimum:
					if battle.profile_enabled: battle.profile_add("body_checks_us",Time.get_ticks_usec()-begin)
					return false
	if battle.profile_enabled: battle.profile_add("body_checks_us",Time.get_ticks_usec()-begin)
	return not terrain_blocks(point)

# Bounded body-only visibility for a nearby route guide. Terrain remains subject
# to the normal physics query and every real movement step still checks bodies.
func body_segment_clear(from: Vector2, to: Vector2, ignored: Unit, extra_clearance: float = 0) -> bool:
	var minimum: float = battle.tuning.unit_radius*2+2+extra_clearance
	var first := Vector2i(((from.min(to)-Vector2.ONE*minimum)/_body_cell_size()).floor())
	var last := Vector2i(((from.max(to)+Vector2.ONE*minimum)/_body_cell_size()).floor())
	for y in range(first.y,last.y+1):
		for x in range(first.x,last.x+1):
			for unit in body_cells.get(Vector2i(x,y),[]):
				if unit == ignored or not is_instance_valid(unit) or not unit.is_alive(): continue
				var closest := Geometry2D.get_closest_point_to_segment(unit.position,from,to)
				if unit.position.distance_squared_to(closest) < minimum*minimum-0.01: return false
	return true

func region_overrun(team: int) -> bool:
	# Optional defeat now requires enemy exclusion across the entire region.
	var enemies: Array = []
	for unit in battle.units:
		if is_instance_valid(unit) and unit.is_alive() and unit.team_id != team:
			enemies.append(unit)
	if enemies.is_empty():
		return false
	for point in generate_slots(regions[team], team):
		var excluded := false
		for unit in enemies:
			if point.distance_squared_to(unit.global_position) < pow(battle.tuning.enemy_exclusion_radius, 2):
				excluded = true
				break
		if not excluded:
			return false
	return true
