extends Node2D

@onready var team1Spawn: Node = $TEAM_ONE/Spawn
@onready var team2Spawn: Node = $TEAM_TWO/Spawn
@onready var map: Node = get_node("MapTest")

const unit = preload("res://scenes/entities/soldier_test.tscn")

func _ready() -> void:
	init_map()
	init_spawns()

func init_map() -> void:
	map.init()

func init_spawns() -> void:
	var map_dimensions_tiles = map.get_tile_dimensions()
	var goal_width_pixels: int = map_dimensions_tiles.width * 0.9 * map.get_tile_size()
	var goal_height_pixels: int = map_dimensions_tiles.height * 0.2 * map.get_tile_size()
	var goal_offset_x: int = (map_dimensions_tiles.width - goal_width_pixels) * 0.5

	print(goal_width_pixels)

	team1Spawn.init(goal_width_pixels, goal_height_pixels, Vector2(goal_offset_x, 0))
	team2Spawn.init(goal_width_pixels, goal_height_pixels, Vector2(goal_offset_x, map_dimensions_tiles.height * map.get_tile_size() - goal_height_pixels))

func TEST_FAKE_UNITS(num: int, team: int) -> void:
	for n in num:
		var entity: Unit = unit.instantiate()
		var team_node = $TEAM_ONE if team == 1 else $TEAM_TWO
		if team == 1:
			entity.global_position = team1Spawn.get_spawn_position()
		else:
			var pos: Vector2 = team2Spawn.get_spawn_position()
			pos.y += map.get_tile_dimensions().height * map.get_tile_size() - (map.get_tile_dimensions().height * 0.2 * map.get_tile_size())
			entity.global_position = pos
		add_node_to_team(entity, team_node)

func add_node_to_team(child_node: Node, team_node: Node):
	team_node.add_child(child_node)
	pass

func _on_team_1_spawn_timer_timeout() -> void:
	print("spawning team 1")
	TEST_FAKE_UNITS(randi_range(5, 15), 1)

func _on_team_2_spawn_timer_timeout() -> void:
	print("spawning team 2")
	TEST_FAKE_UNITS(randi_range(5, 15), 2)
