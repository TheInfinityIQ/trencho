extends SceneTree
const RECOGNIZER = preload("res://scripts/systems/gesture_recognizer.gd")
var game: Node
var checks := 0
var failed := false
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error("FAILED: "+label)
func loop_at(center: Vector2, radius: float, winding: float = 1, fraction: float = 1) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(49): points.append(center+Vector2.from_angle(TAU*index/48*winding*fraction)*radius)
	return points
func bodies(kind: String, count: int, team: int, center: Vector2) -> BattleSquad:
	var spec: Dictionary = game.card_catalog[kind].base_stats()
	spec.team = team
	spec.unit_type = kind
	spec.lane = 1
	spec.spawn_positions = []
	for index in range(count): spec.spawn_positions.append(center+Vector2(index%4,index/4)*180)
	game.spawn_deployment(spec)
	for unit in spec.squad.members: unit.set_physics_process(false)
	return spec.squad
func settle(squad: BattleSquad) -> void:
	for unit in squad.living_members():
		unit.position = squad.defense_positions[unit.squad_member_index]
		unit.defense_established = true
		unit.state = Unit.State.DEFENDING
	game.squad_commands.points.update(0,true)
func clear() -> void:
	game.formation_manager.clear()
	for unit in game.units.duplicate(): unit.die()
	game.squad_commands.prune()
	game.squad_commands.points.update(0,true)
	game.economies[1].current_command = 10
	game.economies[2].current_command = 10
func run() -> void:
	game = load("res://main.tscn").instantiate()
	game.tuning = game.tuning.duplicate()
	game.tuning.enemy_enabled = false
	game.tuning.move_speed_variance = 0
	game.tuning.attack_interval_variance = 0
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	await process_frame
	var manager = game.deployment_manager
	var commands = game.squad_commands
	var points = commands.points
	var rifle: BattleCard = game.card_catalog.rifle_squad
	var assault: BattleCard = game.card_catalog.assault_squad
	var conscript: BattleCard = game.card_catalog.conscript_wave
	var mojo: BattleCard = game.card_catalog.commander_mojo
	var march: BattleCard = game.card_catalog.forced_march
	for package in [[rifle],[rifle,mojo],[rifle,mojo,march],[rifle,assault],[rifle,assault,mojo]]:
		check(manager.resolve_package(package).is_valid,"legal package %s" % str(package))
	for package in [[],[mojo],[rifle,assault,conscript],[rifle,assault,mojo,march]]:
		check(not manager.resolve_package(package).is_valid,"illegal package is rejected")
	var a: Dictionary = manager.resolve_package([rifle,mojo,march]).resolved_deployment
	var b: Dictionary = manager.resolve_package([rifle,march,mojo]).resolved_deployment
	check(a.damage==b.damage and a.quantity==b.quantity and a.move_speed==b.move_speed,"modifier selection order does not change stats")
	for team in [1,2]:
		game.economies[team].current_command = 10
		var order: Dictionary = manager.request_squad(team,[assault,conscript,mojo],Rect2(1600,0,2600,620),"ADVANCE")
		check(order.is_valid,"mixed package deploys through shared API")
		if not order.is_valid: continue
		var spec: Dictionary = order.resolved_deployment
		var distribution: Array = spec.member_components
		check(distribution.count(0)==8 and distribution.count(1)==24,"whole-package modifier preserves component quantities")
		manager.assign_components(spec)
		check(distribution==spec.member_components,"mixed assignment is deterministic")
		var front_y: float = spec.spawn_positions[0].y
		var front_indices: Array = []
		for index in range(spec.spawn_positions.size()):
			if is_equal_approx(spec.spawn_positions[index].y,front_y) and distribution[index]==0: front_indices.append(index)
		check(front_indices.size()>=2 and front_indices[-1]-front_indices[0]>=front_indices.size()-1,"front-priority members span file heads")
		game.formation_manager.tick(1)
		for unit in game.units: unit.set_physics_process(false)
		var seen: Dictionary = {}
		for slot in game.formation_manager.pending:
			seen[slot.specification.components[distribution[slot.member_index]].unit_type] = true
		for unit in spec.squad.living_members():
			seen[unit.unit_type] = true
			check(unit.squad==spec.squad,"mixed soldiers retain one squad identity")
		check(seen.size()==2,"both component types survive spawn/queue resolution")
		clear()
	var column_spec: Dictionary = manager.resolve_package([conscript,assault]).resolved_deployment
	column_spec.spawn_positions = []
	for index in range(16): column_spec.spawn_positions.append(Vector2(3000,index*160))
	manager.assign_components(column_spec)
	var assault_depths: Array = []
	for index in range(16):
		if column_spec.member_components[index]==1: assault_depths.append(index)
	check(assault_depths.size()==4 and assault_depths[0]<=4 and assault_depths[-1]>=12,"narrow mixed column proportionally interleaves types instead of creating two blocks")
	for index in range(1,assault_depths.size()): check(assault_depths[index]-assault_depths[index-1]<=4,"minority type stays distributed throughout the column")
	var mixed: BattleSquad = bodies("rifle_squad",1,2,Vector2(3000,4000))
	var faster: BattleSquad = bodies("assault_squad",1,2,Vector2(3200,4000))
	var fast: Unit = faster.members[0]
	faster.members.clear()
	commands.squads.erase(faster.squad_id)
	fast.squad = mixed
	fast.squad_member_index = 1
	mixed.members.append(fast)
	mixed.refresh_travel()
	check(mixed.strategic_speed==300 and fast.move_speed==420,"mixed strategic speed is slowest while native tactical speed is retained")
	var opposing: BattleSquad = bodies("rifle_squad",1,1,Vector2(3100,3400))
	commands.tick()
	fast._physics_process(1.0/60)
	check(fast.state==Unit.State.ENGAGING and is_equal_approx(fast.velocity.length(),420),"short-range mixed soldier actually repositions at native tactical speed")
	opposing.members[0].die()
	mixed.retreating = true
	fast._physics_process(1.0/60)
	check(is_equal_approx(fast.velocity.length(),450),"mixed squad rout uses 1.5x its normal strategic Advance speed")
	mixed.retreating = false
	mixed.members[0].die()
	check(mixed.strategic_speed==420,"removing slowest living type updates travel speed")
	clear()
	for winding in [1.0,-1.0]:
		for angle in [0.0,PI*0.5,PI]:
			var loop := loop_at(Vector2(350,350),80,winding)
			for index in range(loop.size()): loop[index] = Vector2(350,350)+(loop[index]-Vector2(350,350)).rotated(angle)
			check(RECOGNIZER.classify(loop).command_type=="DEFEND","complete loop accepts either winding and entry direction")
			var partial := loop_at(Vector2(350,350),80,winding,0.75)
			check(not RECOGNIZER.classify(partial).success and RECOGNIZER.classify(partial).ambiguous,"attempted incomplete loop never becomes Advance")
	var curve := PackedVector2Array([Vector2(100,100),Vector2(130,60),Vector2(180,40),Vector2(240,65),Vector2(280,120),Vector2(300,190)])
	var recognized: Dictionary = RECOGNIZER.classify(curve)
	check(recognized.success and recognized.command_type=="ADVANCE" and recognized.route.size()>2 and recognized.route.size()<=5,"open broad curve preserves meaningful bounded route")
	var stem := PackedVector2Array([Vector2(50,100),Vector2(100,100),Vector2(150,180),Vector2(430,350)])
	stem.append_array(loop_at(Vector2(350,350),80))
	check(RECOGNIZER.classify(stem).command_type=="DEFEND" and RECOGNIZER.classify(stem).route.size()>1,"route plus terminal loop retains approach route")
	var jitter := PackedVector2Array()
	for index in range(100): jitter.append(Vector2(100+index*3,100+sin(index)*2))
	check(RECOGNIZER.classify(jitter).route.size()==2,"hand jitter simplifies to a line")
	# Real motion: a soldier follows lateral/backward waypoints then resumes Advance.
	var moving: BattleSquad = bodies("rifle_squad",1,2,Vector2(3000,4000))
	commands.issue_group([moving],"ADVANCE",Vector2.ZERO,0,PackedVector2Array([Vector2(3300,4000),Vector2(3300,4300)]))
	var soldier: Unit = moving.members[0]
	for tick in range(105): soldier._physics_process(1.0/60)
	check(soldier.position.x>3250 and soldier.position.y>4150,"route executes lateral then backward movement")
	for tick in range(120): soldier._physics_process(1.0/60)
	check(soldier.position.y<4100,"route completion resumes normal Advance")
	clear()
	var defenders: BattleSquad = bodies("rifle_squad",6,2,Vector2(2700,4000))
	var established: Dictionary = commands.issue_group([defenders],"DEFEND",Vector2(3200,3500))
	var id: int = established.defensive_point_id
	points.update(0,true)
	check(commands.orders[id].lifecycle=="PENDING" and commands.orders[id].cells.is_empty(),"inbound defense controls no active territory")
	settle(defenders)
	check(commands.orders[id].lifecycle=="ACTIVE" and commands.orders[id].established==6,"arrival establishes active territory")
	var old_area: float = commands.orders[id].actual_area
	var passer: BattleSquad = bodies("rifle_squad",1,2,Vector2(3000,5000))
	commands.issue_group([passer],"ADVANCE",Vector2.ZERO,0,PackedVector2Array([Vector2(3200,3500),Vector2(4500,4500)]))
	check(passer.intent=="ADVANCE" and passer.order_id == -1,"passing through a friendly area does not reinforce unless endpoint lands inside")
	passer.members[0].die()
	check(points.projection(id,10000).warning,"insufficient projected territory warns about capacity")
	var incoming: BattleSquad = bodies("assault_squad",4,2,Vector2(3200,5000))
	var reinforcement: Dictionary = commands.issue_group([incoming],"ADVANCE",Vector2.ZERO,0,PackedVector2Array([Vector2(3200,3500)]))
	check(reinforcement.success and incoming.order_id==id and incoming.intent=="DEFEND","only route endpoint captures friendly point")
	points.update(0,true)
	check(commands.orders[id].actual_area==old_area and commands.orders[id].inbound==4,"inbound reinforcement does not inflate territory")
	var ghost: Dictionary = points.projection(id,4)
	check(not ghost.cells.is_empty() and commands.orders[id].actual_area==old_area,"projection is separate from active cells")
	for unit in defenders.members.duplicate(): unit.die()
	points.update(0,true)
	check(commands.orders.has(id) and commands.orders[id].lifecycle=="PENDING" and commands.orders[id].cells.is_empty(),"dead defenders with inbound troops preserve Pending destination")
	settle(incoming)
	check(commands.orders[id].lifecycle=="ACTIVE","inbound arrival reactivates point")
	commands.issue_group([incoming],"ADVANCE")
	points.update(0,true)
	check(not commands.orders.has(id),"redirecting last assigned/inbound squad removes empty point")
	clear()
	for center in [Vector2(110,1100),Vector2(game.field_size.x-110,3500),Vector2(3200,1050)]:
		var squad: BattleSquad = bodies("rifle_squad",6,2,Vector2(3000,4500))
		var response: Dictionary = commands.issue_group([squad],"DEFEND",center,9999)
		check(not response.success and squad.order_id == -1,"formation crossing boundary rejects without silently reshaping")
		if response.success:
			settle(squad)
			var point: Dictionary = commands.orders[squad.order_id]
			check(point.cells.size()==point.desired_cells,"edge-clipped territory redistributes to satisfy finite budget")
			for cell in point.cells: check(points.legal(cell,2),"every owned cell respects map, terrain and No-Hold")
		clear()
	var left: BattleSquad = bodies("rifle_squad",6,2,Vector2(2400,4000))
	var right: BattleSquad = bodies("rifle_squad",6,2,Vector2(4000,4000))
	commands.issue_group([left],"DEFEND",Vector2(2900,3500))
	commands.issue_group([right],"DEFEND",Vector2(4900,3500))
	settle(left)
	settle(right)
	var owned: Dictionary = {}
	for point in commands.orders.values():
		for cell in point.cells:
			check(not owned.has(cell),"territory ownership is unique")
			owned[cell] = true
	var survivor: int = left.order_id
	var absorbed: int = right.order_id
	var prior_anchor: Vector2 = right.defense_center
	points.absorb(absorbed,survivor)
	check(not commands.orders.has(absorbed) and right.order_id==survivor,"friendly absorption transfers squads and deletes losing point")
	check(commands.orders[survivor].anchors.has(prior_anchor),"absorption retains losing anchor")
	commands.tick()
	check(commands.orders[survivor].anchors.size()==2,"merged point retains spatially elongated anchor intent")
	clear()
	# Legacy pressure solver fixtures intentionally overlap point anchors.
	# Pressure/capacity triggers absorption without an explicit merge command.
	var strong: BattleSquad = bodies("rifle_squad",9,2,Vector2(3000,4400))
	var weak: BattleSquad = bodies("rifle_squad",1,2,Vector2(3200,4400))
	legacy_point(strong,Vector2(3200,3500))
	legacy_point(weak,Vector2(3210,3500))
	var weak_id: int = weak.order_id
	for squad in [strong,weak]:
		for unit in squad.members:
			unit.position = squad.defense_positions[unit.squad_member_index]
			unit.defense_established = true
	points.update(0,true)
	check(not commands.orders.has(weak_id) and weak.order_id==strong.order_id,"pressure absorbs a friendly point unable to retain capacity")
	check(commands.orders[strong.order_id].anchors.has(Vector2(3210,3500)),"automatic absorption inherits the losing anchor")
	clear()
	# Opposing pressure only breaks a point at an actual contested cell front.
	strong = bodies("rifle_squad",9,2,Vector2(3000,4400))
	weak = bodies("rifle_squad",1,1,Vector2(3200,4400))
	legacy_point(strong,Vector2(3200,3500))
	legacy_point(weak,Vector2(3210,3500))
	for squad in [strong,weak]:
		for unit in squad.members:
			unit.position = squad.defense_positions[unit.squad_member_index]
			unit.defense_established = true
	commands.record_damage(strong.members[0],weak.members[0])
	points.update(0,true)
	check(weak.retreating and not commands.orders.has(weak.order_id),"enemy capacity defeat at contact causes rout")
	check(strong.breakthrough_remaining>0,"pressure winner rewards materially participating squad")
	clear()
	var attackers: BattleSquad = bodies("rifle_squad",2,2,Vector2(3000,4000))
	var victim: BattleSquad = bodies("rifle_squad",2,1,Vector2(3000,3500))
	commands.issue_group([victim],"DEFEND",Vector2(3000,3500))
	settle(victim)
	id = victim.order_id
	attackers.members[0].current_health = 80
	commands.record_damage(attackers.members[0],victim.members[0])
	commands.break_point(id,true)
	check(victim.retreating and victim.members[0].state==Unit.State.RETREATING,"broken enemy point routs survivors")
	check(attackers.members[0].current_health==90 and attackers.breakthrough_remaining>0,"material damage rewards heal and buff to living squad")
	check(attackers.breakthrough_remaining==12,"unused half of squad heal extends base duration by half")
	var base_speed: float = attackers.members[0].move_speed
	commands.award_breakthrough(attackers)
	commands.award_breakthrough(attackers)
	check(attackers.breakthrough_remaining<=16 and attackers.members[0].move_speed==base_speed,"repeat breakthrough caps duration and never changes speed")
	var routed: Unit = victim.members[0]
	var hp: float = routed.current_health
	routed.apply_damage(8)
	check(routed.current_health==hp-10,"rout increases incoming damage by configured multiplier")
	var position_before: Vector2 = routed.position
	routed._physics_process(1.0/60)
	check(routed.position.y<position_before.y and not routed.is_attacking and routed.target==null,"enemy rout moves home without engaging")
	check(is_equal_approx(routed.velocity.length(),routed.move_speed*1.5),"rout uses 1.5x movement speed")
	check(not commands.issue_group([victim],"DEFEND",Vector2(3000,3500)).success,"retreating squad rejects normal tactical orders")
	for unit in victim.members: unit.position.y = 200
	routed._physics_process(1.0/60)
	check(not victim.retreating,"home arrival restores Advance")
	clear()
	var ai = game.enemy_controller
	for doctrine in ["LINE","TRIANGLE"]:
		ai.doctrine = doctrine
		ai.doctrine_points.clear()
		check(ai.anchor("left").x==game.field_size.x*0.25 and ai.anchor("right").x==game.field_size.x*0.75,"doctrine anchors use battlefield fractions")
		check(ai.priority()==("center" if doctrine=="TRIANGLE" else "left"),"doctrine establishment priority")
		if doctrine=="TRIANGLE": check(ai.anchor("center").y>ai.anchor("left").y,"triangle apex is forward of sides")
		var ordered_keys: Array = ["center","left","right"] if doctrine=="TRIANGLE" else ["left","right","center"]
		var doctrine_squads: Dictionary = {}
		for key in ordered_keys:
			check(ai.priority()==key,"new squads fill the doctrine's next deficit")
			var quantity := 20 if doctrine=="TRIANGLE" and key=="center" else 10
			var garrison: BattleSquad = bodies("rifle_squad",quantity,1,Vector2(2400,1000))
			var placed: Dictionary = commands.issue_group([garrison],"DEFEND",ai.anchor(key))
			ai.doctrine_points[key] = placed.defensive_point_id
			doctrine_squads[key] = garrison
			points.update(0,true)
			if key=="center" and doctrine=="TRIANGLE": check(ai.priority()=="WAIT","triangle does not count inbound center troops as established or skip to side positions")
			settle(garrison)
		check(ai.priority().is_empty(),"excess squads Advance once all doctrine minimums are met")
		var reduced: BattleSquad = doctrine_squads["center"] if doctrine=="TRIANGLE" else doctrine_squads["left"]
		reduced.members[0].die()
		points.update(0,true)
		check(ai.priority()==("center" if doctrine=="TRIANGLE" else "left"),"new forces replenish later doctrine deficits")
		clear()
	game.player_deployment_confirmed = true
	ai.deployment_cooldown = 0
	game.economies[1].current_command = 10
	ai.decide()
	var queued: int = game.formation_manager.pending.size()
	var resource: float = game.economies[1].current_command
	ai.decide()
	check(queued>0 and game.formation_manager.pending.size()==queued and game.economies[1].current_command==resource,"AI cannot deploy twice within cooldown")
	ai.tick(0.4)
	check(ai.deployment_cooldown>0.59,"AI cooldown uses simulation delta")
	game.command_ui.close_all()
	clear()
	print("DRAWN COMMAND V02: %d assertions, %s" % [checks,"FAILED" if failed else "PASSED"])
	quit(1 if failed else 0)


# Bypass new command geometry only to exercise the unchanged legacy pressure model.
func legacy_point(squad: BattleSquad, center: Vector2) -> void:
	var c = game.squad_commands
	var id: int = c.next_order_id
	c.next_order_id += 1
	c.orders[id] = {"id":id,"team":squad.team,"center":center,"anchors":[center],"squads":[squad.squad_id],"cells":{},"preview_cells":{},"radius":0.0,"dirty":false,"enemies":[],"enemy_cache_valid":false,"established":0,"inbound":0,"lifecycle":"PENDING","desired_cells":0,"desired_area":0.0,"actual_area":0.0,"pressure":0.0,"capacity":0,"capacity_state":"STABLE","neighbors":[],"contributors":{}}
	squad.order_id = id
	squad.intent = "DEFEND"
	c._repack(id)
