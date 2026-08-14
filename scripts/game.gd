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

func register_node(node: Node) -> void:
	add_child(node)

func init_spawns() -> void:
	var map_dimensions_tiles = map.get_tile_dimensions()
	var goal_width_pixels: int = map_dimensions_tiles.width * 0.9 * map.get_tile_size()
	var goal_height_pixels: int = map_dimensions_tiles.height * 0.2 * map.get_tile_size()
	var goal_offset_x: int = (map_dimensions_tiles.width - goal_width_pixels) * 0.5

	print(goal_width_pixels)

	team1Spawn.init(goal_width_pixels, goal_height_pixels, Vector2(goal_offset_x, 0))
	team2Spawn.init(goal_width_pixels, goal_height_pixels, Vector2(goal_offset_x, map_dimensions_tiles.height * map.get_tile_size() - goal_height_pixels))

func TEST_FAKE_UNITS(num: int, spawn: Spawn) -> void:
	for n in num:
		var entity: Unit = unit.instantiate()
		add_child(entity)
		entity.global_position = spawn.get_spawn_position()

func _on_team_1_spawn_timer_timeout() -> void:
	print("spawning team 1")
	TEST_FAKE_UNITS(randi_range(10, 25), $TEAM_ONE)

func _on_team_2_spawn_timer_timeout() -> void:
	print("spawning team 2")
	TEST_FAKE_UNITS(randi_range(10, 25), $TEAM_TWO)
