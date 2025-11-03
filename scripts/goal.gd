extends Area2D

@onready var collision = $CollisionShape2D

func init(width_pixels, height_pixels, new_position) -> void:
	self.position = new_position
	print(new_position)
	
	var rectShape: RectangleShape2D = RectangleShape2D.new()
	rectShape.size = Vector2(width_pixels, height_pixels)
	collision.shape = rectShape
