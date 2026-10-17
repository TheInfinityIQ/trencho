extends RefCounted

var zone_id: String
var team_id: int
var lane_id: int
var bounds: Rect2
var is_occupied := false
var occupying_units: Array = []
var spawn_points: Array[Vector2] = []

func _init(team: int, lane: int, area: Rect2) -> void:
	team_id = team
	lane_id = lane
	bounds = area
	zone_id = "%d_%d" % [team, lane]

func refresh(units: Array, radius: float) -> void:
	occupying_units.clear()
	for unit in units:
		if not is_instance_valid(unit) or not unit.is_alive():
			continue
		var point: Vector2 = unit.global_position
		var closest := Vector2(clampf(point.x, bounds.position.x, bounds.end.x), clampf(point.y, bounds.position.y, bounds.end.y))
		if point.distance_squared_to(closest) <= radius * radius:
			occupying_units.append(unit)
	is_occupied = not occupying_units.is_empty()

func has_enemy() -> bool:
	for unit in occupying_units:
		if unit.team_id != team_id:
			return true
	return false
