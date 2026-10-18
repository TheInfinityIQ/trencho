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

func living_members() -> Array:
	return members.filter(func(unit): return is_instance_valid(unit) and unit.is_alive())
