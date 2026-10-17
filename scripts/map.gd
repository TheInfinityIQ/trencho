extends Node2D

@onready var tile_map: TileMapLayer = $TileMapLayer
@onready var goal1: Area2D = $Goal
@onready var goal2: Area2D = $Goal2

func init() -> void:
	var bounds := tile_map.get_used_rect()
	var tile_size := float(get_tile_size())
	var pixel_size := Vector2(bounds.size) * tile_size
	var origin := Vector2(bounds.position) * tile_size
	# Scoring happens behind the deployment areas, allowing enemy zone occupation.
	goal1.init(pixel_size.x, tile_size, origin + Vector2(pixel_size.x * 0.5, tile_size * 0.5), 1)
	goal2.init(pixel_size.x, tile_size, origin + Vector2(pixel_size.x * 0.5, pixel_size.y - tile_size * 0.5), 2)

func get_tile_dimensions() -> Dictionary:
	var bounds := tile_map.get_used_rect()
	return {"width": bounds.size.x, "height": bounds.size.y}

func get_tile_size() -> int:
	return tile_map.tile_set.tile_size.x
