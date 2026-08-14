extends Node2D
class_name Spawn

@onready var col: CollisionShape2D = $CollisionShape2D

var spawn_direction: Vector2
var width: int
var height: int

func init(width_pixels, height_pixels, new_position) -> void:
	width = width_pixels
	height = height_pixels
	
	self.position = new_position
	
	var rectShape: RectangleShape2D = RectangleShape2D.new()
	rectShape.size = Vector2(width, height)
	col.shape = rectShape

func get_spawn_position() -> Vector2:
	return Vector2(
		randi_range(0, width),
		randi_range(0, height)
	)
