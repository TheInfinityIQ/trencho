extends SceneTree

var game: Node
var checks := 0
var failed := false
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error("FAILED: "+label)

# Frozen reference: the pre-optimization full-grid global-sort algorithm.
# It intentionally does not use the candidate cache, heap, or solve signature.
func reference(inputs: Array) -> Dictionary:
	var service = game.squad_commands.points
	var allocation: Array = []
	var cells: Dictionary = {}
	var owners: Dictionary = {}
	var extent := Vector2i((game.field_size/service.cell_size()).ceil())
	for input in inputs:
		cells[input.id] = {}
		for y in range(extent.y):
			for x in range(extent.x):
				var cell := Vector2i(x,y)
				if not service.legal(cell,input.team): continue
				var point: Vector2 = (Vector2(cell)+Vector2.ONE*0.5)*service.cell_size()
				var distance := INF
				for anchor in input.anchors: distance = minf(distance,point.distance_squared_to(anchor))
				for index in range(1,input.anchors.size()): distance = minf(distance,point.distance_squared_to(Geometry2D.get_closest_point_to_segment(point,input.anchors[index-1],input.anchors[index])))
				allocation.append({"id":input.id,"cell":cell,"score":distance/pow(maxf(1,input.count),0.35)})
	allocation.sort_custom(func(a,b): return a.score < b.score if not is_equal_approx(a.score,b.score) else (a.id < b.id if a.id != b.id else (a.cell.y < b.cell.y if a.cell.y != b.cell.y else a.cell.x < b.cell.x)))
	var lookup: Dictionary = {}
	for input in inputs: lookup[input.id] = input
	for candidate in allocation:
		var input: Dictionary = lookup[candidate.id]
		if cells[candidate.id].size() >= service.budget(input.count) or owners.has(candidate.cell): continue
		var connected := false
		for anchor in input.anchors:
			if service.position(candidate.cell).distance_to(anchor) <= service.cell_size()*0.72: connected = true
		for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			if cells[candidate.id].has(candidate.cell+offset): connected = true
		if connected:
			owners[candidate.cell] = candidate.id
			cells[candidate.id][candidate.cell] = true
	return owners

func squad(count: int, center: Vector2, team: int) -> BattleSquad:
	var spec: Dictionary = game.card_catalog.rifle_squad.base_stats()
	spec.team = team
	spec.unit_type = "rifle_squad"
	spec.lane = 1
	spec.spawn_positions = []
	for index in range(count): spec.spawn_positions.append(center+Vector2(index%4,index/4)*180)
	game.spawn_deployment(spec)
	for unit in spec.squad.members: unit.set_physics_process(false)
	# This suite compares the unchanged radial candidate/heap algorithm only.
	# New front geometry, legality, and pressure are exercised separately.
	var commands = game.squad_commands
	var id: int = commands.next_order_id
	commands.next_order_id += 1
	commands.orders[id] = {"id":id,"team":team,"center":center,"anchors":[center],"squads":[spec.squad.squad_id],"cells":{},"preview_cells":{},"radius":0.0,"dirty":false,"enemies":[],"enemy_cache_valid":false,"established":0,"inbound":0,"lifecycle":"PENDING","desired_cells":0,"desired_area":0.0,"actual_area":0.0,"pressure":0.0,"capacity":0,"capacity_state":"STABLE","neighbors":[],"contributors":{}}
	spec.squad.order_id = id
	spec.squad.intent = "DEFEND"
	commands._repack(id)
	for unit in spec.squad.members:
		unit.position = spec.squad.defense_positions[unit.squad_member_index]
		unit.defense_established = true
	return spec.squad

func run() -> void:
	game = load("res://main.tscn").instantiate()
	game.tuning = game.tuning.duplicate()
	game.tuning.enemy_enabled = false
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	await process_frame
	var commands = game.squad_commands
	var service = commands.points
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261018
	for scene in range(8):
		var inputs: Array = []
		for index in range(1+scene%6):
			var team := 1+index%2
			var center := Vector2(rng.randf_range(180,game.field_size.x-180),rng.randf_range(1500,game.field_size.y-1500))
			var count := rng.randi_range(1,18)
			var group := squad(count,center,team)
			var anchors: Array = [center]
			if scene%3 == 0: anchors.append(center+Vector2(320,160))
			commands.orders[group.order_id].anchors = anchors
			inputs.append({"id":group.order_id,"team":team,"anchors":anchors,"count":count})
		var expected := reference(inputs)
		service.update(0,true)
		check(service.owners==expected,"optimized ownership exactly matches original full-sort solver, scene %d" % scene)
		for unit in game.units.duplicate(): unit.die()
		commands.prune()
		service.update(0,true)
	var garrison := squad(6,Vector2(3200,3500),2)
	service.update(0,true)
	var revision: int = service.revision
	var builds: int = service.candidate_builds
	var owners: Dictionary = service.owners.duplicate()
	for iteration in range(4): service.update(1)
	check(service.revision==revision and service.owners==owners,"unchanged positions reuse identical ownership without a new solve")
	check(service.candidate_builds==builds,"unchanged update does not rescan or sort the battlefield")
	commands.orders[garrison.order_id].capacity_state = "CRITICAL"
	service.update(1)
	check(commands.orders[garrison.order_id].capacity_state=="STABLE","cached ownership still refreshes active capacity after a projected packing warning")
	garrison.members[0].die()
	service.update(1)
	check(service.revision>revision and commands.orders[garrison.order_id].established==5,"casualty invalidates the solve even when square-footprint budget stays equal")
	revision = service.revision
	var inbound := squad(2,Vector2(4500,4500),2)
	# Add inbound metadata to the explicit legacy point without invoking the
	# new front planner (which requires oriented formation geometry).
	commands.orders[inbound.order_id].squads.erase(inbound.squad_id)
	inbound.order_id = garrison.order_id
	commands.orders[garrison.order_id].squads.append(inbound.squad_id)
	for unit in inbound.members: unit.defense_established = false
	commands.prune()
	commands._repack(garrison.order_id)
	service.update(1)
	check(commands.orders[garrison.order_id].inbound==2,"inbound counts remain fresh even when active geometry is reused")
	var before: int = service.candidate_builds
	service.invalidate_terrain()
	service.update(1)
	check(service.candidate_builds>before,"terrain invalidation rebuilds cached candidates")
	var before_cells: Dictionary = service.owners.duplicate()
	var before_visits: int = service.allocation_visits
	service.update(0,true)
	check(service.owners==before_cells,"explicit forced solve preserves deterministic ownership")
	check(service.allocation_visits-before_visits <= service.budget(5)+1,"uncontested allocation stops at the area quota rather than traversing the full battlefield")
	revision = service.revision
	game.tuning.defense_area_margin += 0.1
	service.update(1)
	check(service.revision>revision,"area tuning changes invalidate the cached ownership solve")
	var ui = game.command_ui
	var shape := {Vector2i(0,0):true,Vector2i(1,0):true,Vector2i(2,0):true,Vector2i(0,1):true,Vector2i(2,1):true,Vector2i(0,2):true,Vector2i(1,2):true,Vector2i(2,2):true}
	var geometry: Dictionary = ui._territory_geometry(shape,160)
	var covered: Dictionary = {}
	var overlap := false
	for row in geometry.rows:
		var start := Vector2i(row.position/160)
		for x in range(int(row.size.x/160)):
			var cell := start+Vector2i(x,0)
			if covered.has(cell): overlap = true
			covered[cell] = true
	check(covered==shape and not overlap,"batched fill preserves exact cell coverage, including holes")
	check(geometry.boundary.size()==32,"batched outline retains external and hole boundary edges")
	var geometry_builds: int = ui.geometry_builds
	ui._territory_geometry(shape,160)
	check(ui.geometry_builds==geometry_builds,"unchanged territory reuses visual geometry")
	shape[Vector2i(1,1)] = true
	geometry = ui._territory_geometry(shape,160)
	check(ui.geometry_builds>geometry_builds and geometry.boundary.size()==24,"changed cells invalidate geometry and remove filled hole edges")
	var friends: Array = garrison.living_members()
	check(friends[0].get_node("SpriteBody").material==friends[1].get_node("SpriteBody").material,"same-team soldiers share one shader material")
	var enemy := squad(1,Vector2(2000,2000),1)
	check(friends[0].get_node("SpriteBody").material!=enemy.members[0].get_node("SpriteBody").material,"opposing teams keep independent color material")
	var readout: Node
	for child in friends[0].get_children():
		if child.get_script()==load("res://scripts/ui/unit_readout.gd"): readout=child
	readout._process(0)
	var redraws: int = readout.redraw_requests
	for iteration in range(30): readout._process(0)
	check(readout.redraw_requests==redraws,"stationary unchanged soldier visuals do not rebuild every frame")
	friends[0].apply_damage(5)
	readout._process(0)
	check(readout.redraw_requests==redraws+1,"health damage invalidates cached health bar")
	game.get_node("Camera2D").zoom *= 1.1
	readout._process(0)
	check(readout.redraw_requests==redraws+2,"camera zoom invalidates icon sizing")
	game.hud.debug_panel.visible = true
	readout._process(0)
	check(readout.redraw_requests==redraws+3,"debug toggle invalidates state symbols")
	print("TERRITORY PERFORMANCE: %d assertions, %s" % [checks,"FAILED" if failed else "PASSED"])
	quit(1 if failed else 0)
