extends RefCounted
## Shared, incremental local search, used only after sustained failed progress.
var formation_ref: WeakRef
var battle: Node
var queue: Array = []
var requested: Dictionary = {}
var job: Dictionary = {}
var terrain: Dictionary = {}
var shape := CircleShape2D.new()
var metrics := {"requests":0,"paths":0,"no_path":0,"cancelled":0,"max_queue":0,"max_slice_us":0,"max_cells_per_tick":0,"cells":0}
const STEP := 40.0
const HALF := 24
const CELLS_PER_TICK := 128
const SLICE_US := 2000

func _init(formation: RefCounted) -> void:
	formation_ref = weakref(formation)
	battle = formation.battle
	shape.radius = battle.tuning.unit_radius+4

func clear() -> void:
	queue.clear()
	requested.clear()
	job.clear()

func invalidate_terrain() -> void:
	terrain.clear()
	shape.radius = battle.tuning.unit_radius+4
	clear()

func request(unit: Unit, goal: Vector2) -> void:
	if requested.get(unit.simulation_id,-1) == unit.recovery_generation or queue.size() >= 32: return
	requested[unit.simulation_id] = unit.recovery_generation
	queue.append({"unit":weakref(unit),"id":unit.simulation_id,"generation":unit.recovery_generation,"goal":goal})
	metrics.requests += 1
	metrics.max_queue = maxi(metrics.max_queue,queue.size())

func _unit(task: Dictionary) -> Unit:
	var unit = task.unit.get_ref()
	if not is_instance_valid(unit) or not unit.is_alive() or unit.recovery_generation != task.generation: return null
	if unit.steering_goal.distance_to(task.goal) > battle.tuning.unit_radius*2+2: return null
	return unit

func _release(task: Dictionary) -> void:
	if requested.get(task.id,-1) == task.generation: requested.erase(task.id)

func _terrain_blocked(cell: Vector2i, point: Vector2) -> bool:
	if not terrain.has(cell):
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = shape
		query.transform = Transform2D(0,point)
		query.collision_mask = 1
		query.collide_with_areas = false
		terrain[cell] = not battle.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty()
	return terrain[cell]

func tick() -> void:
	var begin := Time.get_ticks_usec()
	if shape.radius != battle.tuning.unit_radius+4: invalidate_terrain()
	if job.is_empty():
		while not queue.is_empty():
			job = queue.pop_front()
			var unit := _unit(job)
			if unit == null:
				_release(job)
				job = {}
				metrics.cancelled += 1
				continue
			var center := Vector2i((unit.position/STEP).round())
			var grid := AStarGrid2D.new()
			grid.region = Rect2i(center-Vector2i(HALF,HALF),Vector2i(HALF*2+1,HALF*2+1))
			grid.cell_size = Vector2.ONE*STEP
			grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
			grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
			grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
			grid.update()
			job.grid = grid
			job.cursor = 0
			break
	if job.is_empty(): return
	var unit := _unit(job)
	if unit == null:
		_release(job)
		job = {}
		metrics.cancelled += 1
		return
	var formation = formation_ref.get_ref()
	var grid: AStarGrid2D = job.grid
	var width := grid.region.size.x
	var total := width*grid.region.size.y
	var visits := 0
	while job.cursor < total and visits < CELLS_PER_TICK and Time.get_ticks_usec()-begin < SLICE_US:
		var cell: Vector2i = grid.region.position+Vector2i(job.cursor%width,job.cursor/width)
		var point := Vector2(cell)*STEP
		var radius: float = battle.tuning.unit_radius
		var solid: bool = point.x < radius or point.y < radius or point.x > battle.field_size.x-radius or point.y > battle.field_size.y-radius
		if not solid and unit.defense_established and battle.squad_commands.inside_defense(unit.squad,unit.position): solid = not battle.squad_commands.inside_defense(unit.squad,point)
		if not solid: solid = _terrain_blocked(cell,point) or not formation.body_segment_clear(point,point,unit,4)
		grid.set_point_solid(cell,solid)
		job.cursor += 1
		visits += 1
		metrics.cells += 1
	if job.cursor >= total:
		_finish(unit,grid,formation)
		_release(job)
		job = {}
	metrics.max_cells_per_tick = maxi(metrics.max_cells_per_tick,visits)
	metrics.max_slice_us = maxi(metrics.max_slice_us,Time.get_ticks_usec()-begin)

func _finish(unit: Unit, grid: AStarGrid2D, formation: RefCounted) -> void:
	var nearest := Vector2i((unit.position/STEP).round())
	var start := Vector2i.ZERO
	var distance := INF
	for y in range(-3,4):
		for x in range(-3,4):
			var cell := nearest+Vector2i(x,y)
			if not grid.is_in_boundsv(cell) or grid.is_point_solid(cell): continue
			var point := Vector2(cell)*STEP
			var candidate := unit.position.distance_squared_to(point)
			if candidate >= distance or not formation.body_segment_clear(unit.position,point,unit): continue
			if formation.terrain_blocks((unit.position+point)*0.5): continue
			start = cell
			distance = candidate
	if not is_finite(distance):
		metrics.no_path += 1
		return
	var end := Vector2i((Vector2(job.goal)/STEP).round())
	end = Vector2i(clampi(end.x,grid.region.position.x,grid.region.end.x-1),clampi(end.y,grid.region.position.y,grid.region.end.y-1))
	var path := grid.get_point_path(start,end,true)
	if path.size() < 2:
		metrics.no_path += 1
		return
	unit.recovery_path = path
	unit.recovery_index = 0
	unit.recovery_blocked = 0
	metrics.paths += 1
	battle.telemetry.recovery_path(unit)
