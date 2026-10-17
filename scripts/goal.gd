extends Area2D

@onready var collision: CollisionShape2D = $CollisionShape2D
var team_id: int

func init(width_pixels, height_pixels, new_position, team) -> void:
	position = new_position
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(width_pixels, height_pixels)
	collision.shape = rectangle
	team_id = team
	collision_layer = 0
	collision_mask = 8 if team_id == 1 else 4

func _on_body_entered(body: Node2D) -> void:
	if body is Unit and body.team_id != team_id and is_instance_valid(body.battle) and body.battle.crossed_score_line(body):
		body.battle.score_unit(body)
