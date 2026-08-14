extends Node2D

@onready var tile_map: TileMapLayer = $TileMapLayer
@onready var goal1: Area2D = $Goal
@onready var goal2: Area2D = $Goal2

const goal1_tiles_from_top: int = 2
const goal2_tiles_from_top: int = 21
const tile_size_pixels: int = 128
const goal_height: int = tile_size_pixels * 3

func init() -> void:
	var num_tiles = tile_map.get_used_cells().size()
	var map_pixel_width = sqrt(num_tiles) * tile_size_pixels
	
	# 1/2 distance to center of shape + tiles from top~~
	const goal1_pixels_from_top: int = goal1_tiles_from_top * tile_size_pixels + (goal_height / 2)
	goal1.init(
		map_pixel_width
		, goal_height
		, Vector2(
			map_pixel_width / 2
			, goal1_pixels_from_top
		),
		1
	)
	# 1/2 distance to center of shape + tiles from top
	const goal2_pixels_from_top: int = goal2_tiles_from_top * tile_size_pixels + (goal_height / 2)
	goal2.init(
		map_pixel_width
		, goal_height
		, Vector2(
			map_pixel_width / 2
			, goal2_pixels_from_top
		),
		2
	)

func get_tile_dimensions() -> Dictionary:
	var map_rect: Rect2i = tile_map.get_used_rect()
	return { "width" = map_rect.size.x, "height" = map_rect.size.y }

func get_tile_size() -> int:
	return tile_map.tile_set.tile_size.x
