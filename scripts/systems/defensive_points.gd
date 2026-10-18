extends RefCounted

# Deterministic coarse territory, not fluid simulation or a per-soldier pathfinder.
# orders remains the public point dictionary for existing debug integrations.
var command_ref: WeakRef
var commands: RefCounted:
	get: return command_ref.get_ref()
var battle: Node
var owners: Dictionary = {}
var clock := 0.0
var terrain: Dictionary = {}
var revision := 0
var candidate_cache: Dictionary = {}
var last_signature: Array = []
var candidate_builds := 0
var allocation_visits := 0
var solve_count := 0
var unchanged_skips := 0

func _init(service: RefCounted) -> void:
	command_ref = weakref(service)
	battle = service.battle

func cell_size() -> float:
	return maxf(battle.tuning.unit_radius*2+16,battle.tuning.territory_cell_size)

func cell_at(position: Vector2) -> Vector2i:
	return Vector2i((position/cell_size()).floor())

func position(cell: Vector2i) -> Vector2:
	return (Vector2(cell)+Vector2.ONE*0.5)*cell_size()

func legal(cell: Vector2i, team: int) -> bool:
	var point := position(cell)
	var half := cell_size()*0.5
	if point.x-half < 0 or point.x+half > battle.field_size.x or point.y-half < 0 or point.y+half > battle.field_size.y: return false
	if team == 2 and point.y-half < battle.tuning.no_hold_depth: return false
	if team == 1 and point.y+half > battle.field_size.y-battle.tuning.no_hold_depth: return false
	if not terrain.has(cell): terrain[cell] = battle.formation_manager.terrain_blocks(point)
	return not terrain[cell]

func contains(order: Dictionary, point: Vector2) -> bool:
	return order.get("cells",{}).has(cell_at(point))

func budget(count: int) -> int:
	var spacing: float = maxf(battle.tuning.defense_spacing,battle.tuning.unit_radius*4+16)
	var side := ceili(sqrt(count))
	return ceili(maxf(1,side*side)*spacing*spacing*battle.tuning.defense_area_margin/(cell_size()*cell_size())) if count > 0 else 0

func anchor_distance(point: Vector2, anchors: Array) -> float:
	var distance := INF
	for anchor in anchors: distance = minf(distance,point.distance_squared_to(anchor))
	for index in range(1,anchors.size()):
		distance = minf(distance,point.distance_squared_to(Geometry2D.get_closest_point_to_segment(point,anchors[index-1],anchors[index])))
	return distance

func candidates(team: int, anchors: Array) -> Array:
	var key: Array = [team,anchors.duplicate(),battle.field_size,cell_size(),battle.tuning.no_hold_depth]
	if candidate_cache.has(key): return candidate_cache[key]
	if candidate_cache.size() >= 32: candidate_cache.clear()
	candidate_builds += 1
	var result: Array = []
	var extent := Vector2i((battle.field_size/cell_size()).ceil())
	for y in range(extent.y):
		for x in range(extent.x):
			var cell := Vector2i(x,y)
			if legal(cell,team): result.append({"cell":cell,"distance":anchor_distance(position(cell),anchors)})
	result.sort_custom(func(a,b): return a.distance < b.distance if not is_equal_approx(a.distance,b.distance) else (a.cell.y < b.cell.y if a.cell.y != b.cell.y else a.cell.x < b.cell.x))
	candidate_cache[key] = result
	return result

func _before(a: Dictionary, b: Dictionary) -> bool:
	return a.score < b.score if not is_equal_approx(a.score,b.score) else (a.id < b.id if a.id != b.id else (a.cell.y < b.cell.y if a.cell.y != b.cell.y else a.cell.x < b.cell.x))

func _push(heap: Array, item: Dictionary) -> void:
	heap.append(item)
	var index := heap.size()-1
	while index > 0:
		var parent := (index-1)/2
		if not _before(item,heap[parent]): break
		heap[index] = heap[parent]
		index = parent
	heap[index] = item

func _pop(heap: Array) -> Dictionary:
	var result: Dictionary = heap[0]
	var tail: Dictionary = heap.pop_back()
	if heap.is_empty(): return result
	var index := 0
	while index*2+1 < heap.size():
		var child := index*2+1
		if child+1 < heap.size() and _before(heap[child+1],heap[child]): child += 1
		if not _before(heap[child],tail): break
		heap[index] = heap[child]
		index = child
	heap[index] = tail
	return result

func isolated(team: int, anchors: Array, count: int) -> Dictionary:
	var cells: Dictionary = {}
	var wanted := budget(count)
	for candidate in candidates(team,anchors):
		cells[candidate.cell] = true
		if cells.size() >= wanted: break
	return cells

func homes(cells: Dictionary, count: int, center: Vector2, compact: bool = false) -> Array:
	var options: Array = []
	var spacing: float = cell_size() if compact else maxf(battle.tuning.defense_spacing,battle.tuning.unit_radius*4+16)
	var stride := maxi(1,ceili(spacing/cell_size()))
	var origin := cell_at(center)
	for cell in cells:
		# Full cell ownership around a center guarantees the physical body fits.
		if not compact and (posmod(cell.x-origin.x,stride) != 0 or posmod(cell.y-origin.y,stride) != 0): continue
		options.append(position(cell))
	options.sort_custom(func(a,b): return a.distance_squared_to(center) < b.distance_squared_to(center) if not is_equal_approx(a.distance_squared_to(center),b.distance_squared_to(center)) else (a.y < b.y if a.y != b.y else a.x < b.x))
	var chosen: Array = []
	for point in options:
		var clear := true
		for prior in chosen:
			if point.distance_to(prior) < spacing-0.01:
				clear = false
				break
		if clear: chosen.append(point)
		if chosen.size() == count: break
	return chosen

func plan(team: int, count: int, center: Vector2) -> Dictionary:
	var result: Dictionary = commands.result(false,"DEFEND","INVALID_DEFEND_LOCATION")
	if count < 1 or count > 512 or not center.is_finite() or not legal(cell_at(center),team): return result
	var cells := isolated(team,[center],count)
	var positions := homes(cells,count,center)
	if positions.size() < count: positions = homes(cells,count,center,true)
	if positions.size() < count:
		result.failure_reason = "POSITION_UNREACHABLE"
		return result
	result.success = true
	result.failure_reason = ""
	result.defense_center = center
	result.defense_radius = bounds_radius(cells,center)
	result.expanded = true
	result.positions = positions
	result.preview_cells = cells
	return result

func bounds_radius(cells: Dictionary, center: Vector2) -> float:
	var radius := 0.0
	for cell in cells: radius = maxf(radius,position(cell).distance_to(center)+cell_size()*0.71)
	return radius

func point_at(team: int, point: Vector2) -> int:
	var id: int = owners.get(cell_at(point),-1)
	if commands.orders.has(id) and commands.orders[id].team == team and commands.orders[id].lifecycle == "ACTIVE": return id
	return -1

func update(delta: float, force: bool = false) -> void:
	clock -= delta
	if clock > 0 and not force: return
	clock = maxf(0.05,battle.tuning.territory_update_interval)
	var allocation: Array = []
	var erased: Array = []
	var previous: Dictionary = {}
	var signature: Array = [battle.field_size,cell_size(),battle.tuning.unit_radius,battle.tuning.no_hold_depth,battle.tuning.defense_spacing,battle.tuning.defense_area_margin]
	for id in commands.orders:
		var order: Dictionary = commands.orders[id]
		var established := 0
		var inbound := 0
		for squad_id in order.squads:
			if not commands.squads.has(squad_id): continue
			var squad: BattleSquad = commands.squads[squad_id]
			for unit in squad.living_members():
				if unit.defense_established: established += 1
				else: inbound += 1
			inbound += commands.count_members(squad)-squad.living_members().size()
		order.established = established
		order.inbound = inbound
		order.lifecycle = "ACTIVE" if established > 0 else "PENDING"
		order.desired_cells = budget(established)
		order.desired_area = order.desired_cells*cell_size()*cell_size()
		order.pressure = float(established)
		previous[id] = order.cells
		if established+inbound == 0:
			erased.append(id)
			continue
		signature.append([id,order.team,order.anchors.duplicate(),established])
	for id in erased: commands.orders.erase(id)
	if not force and signature == last_signature:
		# Repacking can temporarily mark a projected reinforcement as Critical.
		# Refresh derived active capacity even when ownership itself is cached.
		for order in commands.orders.values():
			order.capacity_state = "CRITICAL" if order.capacity < order.established else ("COMPRESSED" if order.cells.size() < order.desired_cells else "STABLE")
			order.radius = maxf(order.radius,bounds_radius(order.cells,order.center))
		unchanged_skips += 1
		return
	last_signature = signature.duplicate(true)
	owners.clear()
	revision += 1
	solve_count += 1
	var streams: Dictionary = {}
	for id in commands.orders:
		var order: Dictionary = commands.orders[id]
		order.cells = {}
		order.neighbors = []
		if order.established == 0: continue
		var options := candidates(order.team,order.anchors)
		if options.is_empty(): continue
		var weight := pow(maxf(1,order.pressure),0.35)
		streams[id] = {"options":options,"cursor":0,"weight":weight}
		_push(allocation,{"id":id,"cell":options[0].cell,"score":options[0].distance/weight})
	# Merge the per-point sorted streams. Quota-complete streams stop producing
	# candidates; no full-map cross-product or global comparator sort is needed.
	while not allocation.is_empty():
		var candidate := _pop(allocation)
		allocation_visits += 1
		var order: Dictionary = commands.orders[candidate.id]
		if order.cells.size() >= order.desired_cells: continue
		var stream: Dictionary = streams[candidate.id]
		stream.cursor += 1
		if stream.cursor < stream.options.size():
			var next: Dictionary = stream.options[stream.cursor]
			_push(allocation,{"id":candidate.id,"cell":next.cell,"score":next.distance/stream.weight})
		if owners.has(candidate.cell): continue
		# Only grow from anchors or adjacent owned cells; no remote islands.
		var connected := false
		for anchor in order.anchors:
			if position(candidate.cell).distance_to(anchor) <= cell_size()*0.72: connected = true
		for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			if order.cells.has(candidate.cell+offset): connected = true
		if not connected: continue
		owners[candidate.cell] = candidate.id
		order.cells[candidate.cell] = true
	for id in commands.orders.keys():
		if not commands.orders.has(id): continue
		var order: Dictionary = commands.orders[id]
		if previous.has(id) and previous[id] != order.cells and order.established > 0 and order.inbound == 0: order.dirty = true
		order.actual_area = order.cells.size()*cell_size()*cell_size()
		order.capacity = homes(order.cells,order.established,order.center,true).size() if order.established > 0 else 0
		order.capacity_state = "CRITICAL" if order.capacity < order.established else ("COMPRESSED" if order.cells.size() < order.desired_cells else "STABLE")
		for anchor in order.anchors:
			var neighbor: int = owners.get(cell_at(anchor),-1)
			if neighbor != -1 and neighbor != id and not order.neighbors.has(neighbor): order.neighbors.append(neighbor)
		for cell in order.cells:
			for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var neighbor: int = owners.get(cell+offset,-1)
				if neighbor != -1 and neighbor != id and not order.neighbors.has(neighbor): order.neighbors.append(neighbor)
		order.radius = maxf(order.radius,bounds_radius(order.cells,order.center))
		if order.capacity_state == "CRITICAL" and order.established > 0:
			var stronger := -1
			var opponent := -1
			for other_id in order.neighbors:
				if not commands.orders.has(other_id): continue
				var other: Dictionary = commands.orders[other_id]
				if other.team == order.team and other.pressure > order.pressure and (stronger < 0 or other.pressure > commands.orders[stronger].pressure): stronger = other_id
				if other.team != order.team and other.pressure > order.pressure: opponent = other_id
			if stronger >= 0: absorb(id,stronger)
			elif opponent >= 0: commands.break_point(id,true)
			else: commands.break_point(id,false)

func absorb(weak_id: int, strong_id: int) -> void:
	if not commands.orders.has(weak_id) or not commands.orders.has(strong_id): return
	if battle.telemetry != null: battle.telemetry.point_absorbed(weak_id,strong_id)
	var weak: Dictionary = commands.orders[weak_id]
	var strong: Dictionary = commands.orders[strong_id]
	for anchor in weak.anchors:
		if not strong.anchors.has(anchor): strong.anchors.append(anchor)
	for squad_id in weak.squads:
		if not commands.squads.has(squad_id): continue
		var squad: BattleSquad = commands.squads[squad_id]
		squad.order_id = strong_id
		strong.squads.append(squad_id)
	strong.dirty = true
	commands.orders.erase(weak_id)
	clock = 0

func projection(id: int, extra: int) -> Dictionary:
	if not commands.orders.has(id): return {}
	var order: Dictionary = commands.orders[id]
	var cells := isolated(order.team,order.anchors,order.established+order.inbound+extra)
	for cell in cells.keys():
		if owners.has(cell) and owners[cell] != id and commands.orders.has(owners[cell]): cells.erase(cell)
	return {"cells":cells,"warning":order.capacity_state != "STABLE" or cells.size() < budget(order.established+order.inbound+extra)}


func invalidate_terrain() -> void:
	terrain.clear()
	candidate_cache.clear()
	last_signature.clear()
	clock = 0
