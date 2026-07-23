extends Node2D

@onready var team1Spawn: Node = get_node("TEAM_ONE")
@onready var team2Spawn: Node = get_node("TEAM_TWO")
@onready var map: Node = get_node("MapTest")

const unit = preload("res://scenes/entities/soldier_test.tscn")

func _ready() -> void:
	init_map()
	init_spawns()

func init_map() -> void:
	map.init()

func init_spawns() -> void:
	var d = map.get_dimensions()
	var goal_width: int = d.width * 0.9
	var goal_height: int = d.height * 0.2
	var goal_offset_x: int = (d.width - goal_width) * 0.5

	team1Spawn.init(goal_width, goal_height, Vector2(goal_offset_x, 0))
	team2Spawn.init(goal_width, goal_height, Vector2(goal_offset_x, d.width - goal_height))

func TEST_FAKE_UNITS(num: int, spawn: Spawn) -> void:
	for n in num:
		spawn.place_entity(unit.instantiate())

func _on_team_1_spawn_timer_timeout() -> void:
	TEST_FAKE_UNITS(randi_range(10, 25), $TEAM_ONE)


func _on_team_2_spawn_timer_timeout() -> void:
	TEST_FAKE_UNITS(randi_range(10, 25), $TEAM_TWO)
