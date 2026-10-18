extends RefCounted
class_name BattleSquad

var squad_id: int
var team: int
var unit_type: String
var source_cards: Array = []
var members: Array = []
var intent := "ADVANCE"
var order_id := -1
var defense_center := Vector2.ZERO
var defense_radius := 0.0
var defense_positions: Dictionary = {}
var selected := false
var route_waypoints := PackedVector2Array()
var route_indices: Dictionary = {}
var route_offsets: Dictionary = {}
var retreating := false
var breakthrough_remaining := 0.0
var strategic_speed := 0.0
var combat_center := Vector2.ZERO
var composition: Dictionary = {}
var combat_candidates: Array = []
var combat_target: Unit
var corridor_offset := Vector2.ZERO
var route_bounds := Rect2()

func refresh_travel() -> void:
	strategic_speed = INF
	combat_center = Vector2.ZERO
	var living := living_members()
	composition.clear()
	for unit in living:
		strategic_speed = minf(strategic_speed,unit.move_speed)
		combat_center += unit.global_position
		composition[unit.unit_type] = composition.get(unit.unit_type,0)+1
	if not living.is_empty(): combat_center /= living.size()
	else: strategic_speed = 0

func route_target(unit) -> Vector2:
	var index: int = route_indices.get(unit.squad_member_index,0)
	var offset: Vector2 = route_offsets.get(unit.squad_member_index,Vector2.ZERO)
	while index < route_waypoints.size() and unit.global_position.distance_to(_bounded_waypoint(route_waypoints[index]+offset)) < 45:
		index += 1
	route_indices[unit.squad_member_index] = index
	return _bounded_waypoint(route_waypoints[index]+offset) if index < route_waypoints.size() else Vector2.INF

func _bounded_waypoint(point: Vector2) -> Vector2:
	return point.clamp(route_bounds.position,route_bounds.end) if route_bounds.size.x > 0 else point

func living_members() -> Array:
	return members.filter(func(unit): return is_instance_valid(unit) and unit.is_alive())
