extends Area2D
class_name Card

@onready var card_sprite: Sprite2D = $Sprite2D
@onready var area: CollisionShape2D = $CollisionShape2D

var start_position: Vector2
var is_selected: bool = false
var is_draggable: bool = false
var is_over_dropzone: bool = false
var elevated_offset: int = -25

func _ready():
	_set_col_shape_size()

func set_card_texture(t: Texture2D):
	card_sprite.texture = t

func _set_col_shape_size():
	print(card_sprite.texture.get_size())
	area.shape.size = card_sprite.texture.get_size()
	print(area.shape.size)

func set_start_position(p: Vector2):
	start_position = p

func _on_mouse_entered() -> void:
	elevate()

func _on_mouse_exited() -> void:
	depress()

func elevate():
	print("Hovering")
	var elevate_tween = create_tween()
	elevate_tween.tween_property(self, "position", Vector2(position.x, position.y + elevated_offset), 0.05)

func depress():
	print("Off")
	var return_tween = create_tween()
	return_tween.tween_property(self, "position", start_position, 0.2)
