extends RefCounted

# Formation topology lives here; physical travel remains owned by Unit.
var command_ref: WeakRef
var commands: RefCounted:
	get: return command_ref.get_ref()
var battle: Node
var consolidation_clock = 0.0
var transfers: Array = []

func _init(service: RefCounted) -> void:
	# Avoid a service ownership cycle.
	command_ref = weakref(service)
	battle = service.battle

func spacing() -> float:
	return maxf(battle.tuning.defense_spacing,battle.tuning.unit_radius*4+16)

func remember(squad: BattleSquad, specification: Dictionary) -> void:
	var positions: Array = specification.get("spawn_positions",[])
	if positions.is_empty(): return
	var center = Vector2.ZERO
	for point in positions: center += point
	center /= positions.size()
	var forward = Vector2.UP if squad.team == 2 else Vector2.DOWN
	var lateral = Vector2(-forward.y,forward.x)
	var minimum = INF
	for a in range(positions.size()):
		for b in range(a):
			minimum = minf(minimum,positions[a].distance_to(positions[b]))
	var scale_factor = maxf(1,spacing()/maxf(1,minimum)) if is_finite(minimum) else 1.0
	for index in range(positions.size()):
		var offset: Vector2 = (positions[index]-center)*scale_factor
		squad.formation_offsets[index] = Vector2(offset.dot(lateral),-offset.dot(forward))
		squad.formation_types[index] = specification.components[specification.member_components[index]].unit_type if specification.has("member_components") else specification.get("unit_type",squad.unit_type)
	squad.formation_capacity = positions.size()
	var original = Rect2(positions[0],Vector2.ZERO)
	for point in positions: original = original.expand(point)
	squad.formation_size = specification.requested_rectangle.size if specification.has("requested_rectangle") else original.grow(battle.tuning.unit_radius).size

func facing(team: int, route: PackedVector2Array, explicit: Vector2 = Vector2.ZERO) -> Vector2:
	if explicit.length_squared() > 0.01: return explicit.normalized()
	for index in range(route.size()-1,0,-1):
		if route[index].distance_to(route[index-1]) >= battle.tuning.unit_radius:
			return route[index-1].direction_to(route[index])
	return Vector2.UP if team == 2 else Vector2.DOWN

func alive(sid: int, index: int) -> bool:
	if not commands.squads.has(sid): return false
	for unit in commands.squads[sid].living_members():
		if unit.squad_member_index == index: return true
	for slot in battle.formation_manager.pending:
		if slot.specification.squad.squad_id == sid and slot.member_index == index: return true
	return false

func occupant(slot: Dictionary) -> Unit:
	if slot.who.is_empty() or not commands.squads.has(slot.who.squad): return null
	for unit in commands.squads[slot.who.squad].living_members():
		if unit.squad_member_index == slot.who.index: return unit
	return null

func occupied(slot: Dictionary) -> bool:
	return not slot.who.is_empty() and alive(slot.who.squad,slot.who.index)

func blocks(order: Dictionary) -> Array:
	return order.get("blocks",[])

func local_rect(squad: BattleSquad) -> Rect2:
	var bounds = Rect2()
	var first = true
	for offset in squad.formation_offsets.values():
		if first:
			bounds = Rect2(offset,Vector2.ZERO)
			first = false
		else: bounds = bounds.expand(offset)
	return bounds.grow(spacing()*0.5)

func world(order: Dictionary, local: Vector2) -> Vector2:
	return order.center+order.lateral*local.x-order.facing*local.y

func local(order: Dictionary, point: Vector2) -> Vector2:
	var offset: Vector2 = point-order.center
	return Vector2(offset.dot(order.lateral),-offset.dot(order.facing))

func valid_block(order: Dictionary, block: Dictionary, others: Array, ignored: Array) -> bool:
	for other in others:
		if block.rect.grow(-0.5).intersects(other.rect.grow(-0.5)):
			for old in other.slots:
				if occupied(old) and block.rect.grow(-0.5).has_point(old.local): return false
	for slot in block.slots:
		var radius: float = battle.tuning.unit_radius
		if slot.home.x < radius or slot.home.x > battle.field_size.x-radius or slot.home.y < radius or slot.home.y > battle.field_size.y-radius: return false
		if order.team == 2 and slot.home.y-radius < battle.tuning.no_hold_depth: return false
		if order.team == 1 and slot.home.y+radius > battle.field_size.y-battle.tuning.no_hold_depth: return false
		if not commands.points.legal(commands.points.cell_at(slot.home),order.team): return false
		if battle.formation_manager.terrain_blocks(slot.home): return false
		var owner: int = commands.points.owners.get(commands.points.cell_at(slot.home),-1)
		if owner >= 0 and owner != order.get("id",-1) and commands.orders.has(owner):
			var foreign: Dictionary = commands.orders[owner]
			# Friendly coarse areas may meet and renegotiate ownership. Their
			# physical formation homes below remain an absolute placement limit.
			if foreign.team != order.team and not foreign.squads.all(func(id): return ignored.has(id)): return false
		# Pending formations also reserve their physical homes.
		for point in commands.orders.values():
			if point.get("id",-1) == order.get("id",-1): continue
			for prior in blocks(point):
				if ignored.has(prior.squad): continue
				for old in prior.slots:
					if slot.home.distance_to(old.home) < battle.tuning.unit_radius*2+4: return false
	return true

func make_block(order: Dictionary, squad: BattleSquad, offset: Vector2, role: String) -> Dictionary:
	var rectangle = local_rect(squad)
	var block = {"squad":squad.squad_id,"rect":Rect2(rectangle.position+offset,rectangle.size),"role":role,"slots":[],"capacity":squad.formation_capacity,"blueprint_size":squad.formation_size}
	var front_y = rectangle.position.y+spacing()*0.5
	for index in squad.formation_offsets:
		# Keep holes caused by casualties; original shape and capacity survive.
		var at: Vector2 = squad.formation_offsets[index]+offset
		block.slots.append({"home":world(order,at),"local":at,"front":role == "FRONT" and absf(squad.formation_offsets[index].y-front_y)<1,"original":index,"type":squad.formation_types.get(index,squad.unit_type),"who":{"squad":squad.squad_id,"index":index} if alive(squad.squad_id,index) else {}})
	return block

# Pure plan: commands and previews share it. No live homes are moved here.
func plan(group: Array, center: Vector2, route: PackedVector2Array, target: int = -1, explicit: Vector2 = Vector2.ZERO) -> Dictionary:
	var result: Dictionary = commands.result(false,"DEFEND","POSITION_UNREACHABLE")
	if group.is_empty() or not center.is_finite(): return result
	if target < 0 and not commands.points.legal(commands.points.cell_at(center),group[0].team):
		result.failure_reason = "INVALID_DEFEND_LOCATION"
		return result
	if group.any(func(squad): return squad.team != group[0].team or squad.formation_capacity < 1): return result
	var total = 0
	for squad in group: total += commands.count_members(squad) if squad.squad_id >= 0 else squad.formation_capacity
	if total > 512: return result
	var forward = facing(group[0].team,route,explicit)
	var order = {"id":-1,"team":group[0].team,"center":center,"facing":forward,"lateral":Vector2(-forward.y,forward.x),"blocks":[]}
	var ignored: Array = group.map(func(squad): return squad.squad_id)
	var existing: Array = []
	if commands.orders.has(target):
		order = commands.orders[target]
		existing = blocks(order).filter(func(block): return not ignored.has(block.squad) or block.slots.any(func(slot): return not slot.who.is_empty() and not ignored.has(slot.who.squad)))
	var added: Array = []
	var retired: Array = []
	var initial_depth = 0.0
	if target < 0:
		for squad in group: initial_depth += local_rect(squad).size.y
	var endpoint = local(order,route[-1] if not route.is_empty() else center)
	for squad in group:
		var rectangle = local_rect(squad)
		var options: Array = []
		if existing.is_empty(): options.append({"at":Vector2(0,(-initial_depth+rectangle.size.y)*0.5) if group.size()>1 else Vector2.ZERO,"role":"FRONT"})
		else:
			var fronts: Array = existing.filter(func(block): return block.role == "FRONT")
			var left = INF
			var right = -INF
			var front = 0.0
			for block in fronts:
				left = minf(left,block.rect.position.x)
				right = maxf(right,block.rect.end.x)
				front = minf(front,block.rect.position.y)
			if fronts.is_empty():
				left = existing[0].rect.position.x
				right = existing[0].rect.end.x
			# A whole vacated block is a genuine opening; partial gaps wait for waves.
			for block in fronts:
				if block.slots.all(func(slot): return not occupied(slot)) and block.rect.size.x+1 >= rectangle.size.x and absf(endpoint.x-block.rect.get_center().x) <= block.rect.size.x:
					options.append({"at":Vector2(block.rect.get_center().x,front-rectangle.position.y),"role":"FRONT","replace":block.squad})
			# A contiguous empty frontage can accept a smaller intact block if
			# its depth also fits. Physical occupancy is checked by valid_block.
			var gaps: Array = []
			for prior in fronts:
				var row: Array = prior.slots.filter(func(slot): return slot.front and not slot.get("covered",false))
				row.sort_custom(func(a,b): return a.local.x<b.local.x)
				var run: Array = []
				for slot in row:
					if occupied(slot):
						run.clear()
						continue
					if not run.is_empty() and slot.local.x-run[-1].local.x>spacing()*1.1: run.clear()
					run.append(slot)
					if run.size()*spacing()+0.1>=rectangle.size.x:
						var x: float = (run[0].local.x+run[-1].local.x)*0.5
						gaps.append({"at":Vector2(x,prior.rect.position.y-rectangle.position.y),"role":"FRONT","gap":true})
			gaps.sort_custom(func(a,b): return absf(a.at.x-endpoint.x)<absf(b.at.x-endpoint.x))
			for gap in gaps:
				if absf(gap.at.x-endpoint.x)<=rectangle.size.x: options.append(gap)
			if endpoint.x <= left+spacing()*0.6 or endpoint.x >= right-spacing()*0.6:
				var x: float = left-rectangle.end.x if endpoint.x < (left+right)*0.5 else right-rectangle.position.x
				options.append({"at":Vector2(x,front-rectangle.position.y),"role":"FRONT"})
			else:
				# Stack only this targeted sector. Never push settled blocks sideways.
				var x = clampf(endpoint.x,left-rectangle.position.x,right-rectangle.end.x) if right-left >= rectangle.size.x else endpoint.x
				var rear = front
				for block in existing:
					if block.rect.end.x > x+rectangle.position.x and block.rect.position.x < x+rectangle.end.x: rear = maxf(rear,block.rect.end.y)
				options.append({"at":Vector2(x,rear-rectangle.position.y),"role":"RESERVE"})
		var accepted = false
		for option in options:
			var block = make_block(order,squad,option.at,option.role)
			result["proposed_blocks"] = added+[block]
			var obstacles: Array = existing.filter(func(prior): return prior.squad != option.get("replace",-1))
			if valid_block(order,block,obstacles,ignored):
				if option.get("gap",false):
					for prior in existing:
						for old in prior.slots:
							if not occupied(old) and block.rect.grow(-0.5).has_point(old.local): retired.append(old)
				if option.has("replace"): existing = obstacles
				existing.append(block)
				added.append(block)
				accepted = true
				break
		if not accepted:
			result["front_blocks"] = added
			return result
	result.success = true
	result.failure_reason = ""
	result.defense_center = order.center
	result.defense_radius = 0.0
	result.expanded = true
	result["facing"] = order.facing
	result["retired_slots"] = retired
	result["proposed_blocks"] = added
	result["front_blocks"] = existing
	result["positions"] = []
	for block in existing:
		for slot in block.slots:
			result.positions.append(slot.home)
			result.defense_radius = maxf(result.defense_radius,slot.home.distance_to(order.center)+spacing())
	result["preview_cells"] = {}
	return result

func install(order: Dictionary, plan_result: Dictionary) -> void:
	order.facing = plan_result.facing
	order.lateral = Vector2(-order.facing.y,order.facing.x)
	order.blocks = plan_result.front_blocks
	for slot in plan_result.get("retired_slots",[]):
		slot.front = false
		slot.covered = true
	order.wave_remaining = order.get("wave_remaining",-1.0)
	order.front_revision = order.get("front_revision",0)+1
	sync(order)

func sync(order: Dictionary) -> void:
	for block in blocks(order):
		for slot in block.slots:
			if not occupied(slot):
				slot.who = {}
				continue
			var squad: BattleSquad = commands.squads[slot.who.squad]
			squad.defense_positions[slot.who.index] = slot.home
			squad.defense_roles[slot.who.index] = "FRONT" if slot.front else "RESERVE"
			squad.defense_center = order.center
			squad.defense_radius = order.radius
	order.dirty = false

func release(squad: BattleSquad) -> void:
	if not commands.orders.has(squad.order_id): return
	var order: Dictionary = commands.orders[squad.order_id]
	for block in blocks(order):
		for slot in block.slots:
			if not slot.who.is_empty() and slot.who.squad == squad.squad_id: slot.who = {}
	# Keep an empty frontline footprint as a structural opening.
	for block in blocks(order):
		if block.squad == squad.squad_id: block.detached = true
	squad.defense_roles.clear()

func vacant_front(order: Dictionary) -> Array:
	var result: Array = []
	for block in blocks(order):
		for slot in block.slots:
			if slot.front and not occupied(slot): result.append(slot)
	return result

func reserves(order: Dictionary) -> Array:
	var result: Array = []
	for block in blocks(order):
		for slot in block.slots:
			var unit = occupant(slot)
			if not slot.front and unit != null and unit.defense_established and not in_transfer(unit): result.append(slot)
	return result

func relocate(slot: Dictionary, destination: Dictionary) -> void:
	destination.who = slot.who
	slot.who = {}
	var unit = occupant(destination)
	if unit != null:
		unit.squad.defense_positions[unit.squad_member_index] = destination.home
		unit.squad.defense_roles[unit.squad_member_index] = "FRONT"
		unit.reset_steering()

func replace_lost_blocks(order: Dictionary) -> void:
	for missing in blocks(order).duplicate():
		if missing.role != "FRONT" or missing.slots.any(func(slot): return occupied(slot)): continue
		var best: Dictionary = {}
		var distance = INF
		for candidate in blocks(order):
			if candidate.role != "RESERVE" or not commands.squads.has(candidate.squad): continue
			if candidate.slots.any(func(slot): return occupant(slot) != null and in_transfer(occupant(slot))): continue
			if candidate.slots.any(func(slot): return occupied(slot) and (occupant(slot) == null or not occupant(slot).defense_established)): continue
			if not candidate.slots.any(func(slot): return occupied(slot)): continue
			var lateral: float = absf(candidate.rect.get_center().x-missing.rect.get_center().x)
			if lateral > maxf(candidate.rect.size.x,missing.rect.size.x)*0.5: continue
			if candidate.rect.size.x > missing.rect.size.x+1: continue
			var d: float = candidate.rect.get_center().distance_squared_to(missing.rect.get_center())
			if d < distance:
				distance = d
				best = candidate
		if best.is_empty(): continue
		var shift = Vector2(missing.rect.get_center().x-best.rect.get_center().x,missing.rect.position.y-best.rect.position.y)
		var moved: Dictionary = best.duplicate(true)
		moved.rect.position += shift
		var front_y: float = moved.rect.position.y+spacing()*0.5
		for slot in moved.slots:
			slot.local += shift
			slot.home = world(order,slot.local)
			slot.front = absf(slot.local.y-front_y)<1
		moved.role = "FRONT"
		var others: Array = blocks(order).filter(func(block): return block != missing and block != best)
		if not valid_block(order,moved,others,[]): continue
		order.blocks.erase(missing)
		order.blocks.erase(best)
		order.blocks.append(moved)
		order.front_revision += 1
		sync(order)
		for slot in moved.slots:
			var unit = occupant(slot)
			if unit != null: unit.reset_steering()

func tick(delta: float) -> void:
	for order in commands.orders.values():
		if not order.has("blocks"): continue
		order.blocks = order.blocks.filter(func(block): return block.role == "FRONT" or block.slots.any(func(slot): return occupied(slot)))
		replace_lost_blocks(order)
		var vacancies = vacant_front(order)
		if vacancies.is_empty():
			order.wave_remaining = -1.0
		else:
			if order.wave_remaining < 0: order.wave_remaining = battle.tuning.reserve_wave_delay
			var total = 0
			for block in blocks(order):
				for slot in block.slots:
					if slot.front: total += 1
			if float(vacancies.size())/maxi(1,total) >= battle.tuning.reserve_heavy_loss_fraction: order.wave_remaining = minf(order.wave_remaining,battle.tuning.reserve_heavy_loss_delay)
			order.wave_remaining -= delta
			if order.wave_remaining <= 0:
				var available = reserves(order)
				for vacancy in vacancies:
					if available.is_empty(): break
					available.sort_custom(func(a,b): return absf(a.local.x-vacancy.local.x) < absf(b.local.x-vacancy.local.x) if not is_equal_approx(absf(a.local.x-vacancy.local.x),absf(b.local.x-vacancy.local.x)) else a.home.distance_squared_to(vacancy.home)<b.home.distance_squared_to(vacancy.home))
					relocate(available.pop_front(),vacancy)
				order.wave_remaining = -1.0
		# Keep casualty holes; territory pressure must not globally repack homes.
		sync(order)
	_update_transfers(delta)
	consolidation_clock -= delta
	if consolidation_clock <= 0:
		consolidation_clock = 1.0
		_find_transfers()

func in_transfer(unit: Unit) -> bool:
	return transfers.any(func(item): return item.unit.get_ref() == unit)

func eligible(squad: BattleSquad) -> bool:
	if squad.selected or squad.intent != "DEFEND" or squad.retreating or not commands.orders.has(squad.order_id): return false
	if battle.formation_manager.pending_counts.get(squad.squad_id,0)>0: return false
	return squad.living_members().all(func(unit): return unit.defense_established and not unit.is_attacking and not unit.target and int(squad.route_indices.get(unit.squad_member_index,0)) >= squad.route_waypoints.size())

func _find_transfers() -> void:
	for source in commands.squads.values():
		var living: Array = source.living_members()
		if living.is_empty() or living.size() > battle.tuning.straggler_threshold or not eligible(source): continue
		var order: Dictionary = commands.orders[source.order_id]
		for unit in living:
			if in_transfer(unit): continue
			var choices: Array = []
			for block in blocks(order):
				if block.squad == source.squad_id or not commands.squads.has(block.squad): continue
				var receiver: BattleSquad = commands.squads[block.squad]
				if not eligible(receiver) or receiver.living_members().size() <= living.size(): continue
				if not receiver.formation_types.values().has(unit.unit_type) or receiver.living_members().size()>=receiver.formation_capacity: continue
				for slot in block.slots:
					if slot.get("covered",false) or occupied(slot) or transfers.any(func(item): return item.slot == slot): continue
					var free_indices: Array = []
					for candidate_index in range(receiver.formation_capacity):
						if not alive(receiver.squad_id,candidate_index) and not transfers.any(func(item): return item.receiver == receiver.squad_id and item.index == candidate_index): free_indices.append(candidate_index)
					if free_indices.is_empty(): continue
					# A reserve wave can move member 6 into dead member 0's physical
					# slot. The free member index is independent of the vacant home.
					var original_index: int = slot.original if free_indices.has(slot.original) else free_indices[0]
					var same = receiver.formation_types.values().all(func(type): return source.formation_types.values().has(type)) and source.formation_types.values().all(func(type): return receiver.formation_types.values().has(type))
					choices.append({"slot":slot,"receiver":receiver.squad_id,"index":original_index,"same":same,"sector":absi(floori(local(order,unit.position).x/(spacing()*4))-floori(slot.local.x/(spacing()*4))),"distance":unit.position.distance_squared_to(slot.home)})
			choices.sort_custom(func(a,b): return a.same if a.same != b.same else (a.sector < b.sector if a.sector != b.sector else a.distance < b.distance))
			if choices.is_empty(): continue
			var choice: Dictionary = choices[0]
			choice.unit = weakref(unit)
			choice.source = source.squad_id
			choice.point = source.order_id
			choice.old_home = source.defense_positions[unit.squad_member_index]
			choice.delay = maxf(0,order.wave_remaining) if order.get("wave_remaining",-1.0)>=0 else (battle.tuning.reserve_wave_delay if choice.slot.front else 0.0)
			transfers.append(choice)
			if choice.delay <= 0: unit.squad.defense_positions[unit.squad_member_index] = choice.slot.home
			unit.reset_steering()

func _update_transfers(delta: float) -> void:
	for item in transfers.duplicate():
		var unit: Unit = item.unit.get_ref()
		var receiver: BattleSquad = commands.squads.get(item.receiver)
		var valid = unit != null and unit.is_alive() and receiver != null and commands.orders.has(item.point)
		if valid: valid = unit.squad.squad_id == item.source and unit.squad.order_id == item.point and receiver.order_id == item.point and eligible(unit.squad) and eligible(receiver) and not item.slot.get("covered",false) and blocks(commands.orders[item.point]).any(func(block): return block.slots.has(item.slot)) and not occupied(item.slot) and not alive(receiver.squad_id,item.index)
		if not valid:
			transfers.erase(item)
			if unit != null and unit.is_alive() and unit.squad.order_id == item.point:
				unit.squad.defense_positions[unit.squad_member_index] = item.old_home
				unit.reset_steering()
			continue
		if item.delay > 0:
			var wave: float = commands.orders[item.point].get("wave_remaining",-1.0)
			item.delay = minf(item.delay,wave) if wave >= 0 else item.delay
			item.delay = maxf(0,item.delay-delta)
			if item.delay > 0: continue
		# sync() must not overwrite the internal physical destination.
		unit.squad.defense_positions[unit.squad_member_index] = item.slot.home
		if unit.position.distance_to(item.slot.home)>10: continue
		var source: BattleSquad = unit.squad
		for block in blocks(commands.orders[item.point]):
			for slot in block.slots:
				if not slot.who.is_empty() and slot.who.squad == source.squad_id and slot.who.index == unit.squad_member_index: slot.who = {}
		source.members.erase(unit)
		source.defense_positions.erase(unit.squad_member_index)
		source.defense_roles.erase(unit.squad_member_index)
		unit.squad = receiver
		unit.squad_member_index = item.index
		receiver.members.append(unit)
		item.slot.who = {"squad":receiver.squad_id,"index":item.index}
		receiver.defense_positions[item.index] = item.slot.home
		receiver.defense_roles[item.index] = "FRONT" if item.slot.front else "RESERVE"
		unit.reset_steering()
		battle.telemetry.event("STRAGGLER_CONSOLIDATED",{"unit_id":unit.telemetry_id,"source_squad_id":source.squad_id,"receiving_squad_id":receiver.squad_id})
		transfers.erase(item)
		if source.living_members().is_empty(): battle.telemetry.squad_ended(source.squad_id,"consolidated")
	commands.prune()

func ai_target(id: int) -> Vector2:
	var order: Dictionary = commands.orders[id]
	var fronts: Array = blocks(order).filter(func(block): return block.role == "FRONT")
	if fronts.is_empty(): return order.center
	var best: Dictionary = fronts[0]
	var highest = -1.0
	var least = INF
	for block in fronts:
		var slots: Array = block.slots.filter(func(slot): return slot.front)
		var missing: float = float(slots.filter(func(slot): return not occupied(slot)).size())/maxi(1,slots.size())
		var depth = 0.0
		for reserve in blocks(order):
			if reserve.role == "RESERVE" and absf(reserve.rect.get_center().x-block.rect.get_center().x)<block.rect.size.x: depth += reserve.slots.filter(func(slot): return occupied(slot)).size()
		if missing > highest or (is_equal_approx(missing,highest) and depth < least):
			best = block
			highest = missing
			least = depth
	if highest > 0 or least == 0: return world(order,best.rect.get_center())
	var edge: float = fronts[0].rect.position.x
	var right = edge
	for block in fronts:
		edge = minf(edge,block.rect.position.x)
		right = maxf(right,block.rect.end.x)
	return world(order,Vector2(right if order.get("ai_edge_right",false) else edge,0))

# Territory uses the oriented envelope of the blocks; rear space is secondary.
func distance_to_front(order: Dictionary, point: Vector2) -> float:
	var at = local(order,point)
	var rectangle = Rect2()
	var first = true
	for block in blocks(order):
		rectangle = block.rect if first else rectangle.merge(block.rect)
		first = false
	var nearest = at.clamp(rectangle.position,rectangle.end)
	var outside = at-nearest
	if outside.y < 0: outside.y *= 2.0
	else: outside.y *= 0.75
	# One global tie-break prevents disconnected local minima from starving
	# the connected ownership stream before its neighboring cells are reached.
	return outside.length_squared()+0.01*at.length_squared()
