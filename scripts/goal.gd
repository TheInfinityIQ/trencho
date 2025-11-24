extends Area2D

@onready var collision = $CollisionShape2D
var team_id: int

func init(width_pixels, height_pixels, new_position, team) -> void:
	self.position = new_position
	print(new_position)
	
	var rectShape: RectangleShape2D = RectangleShape2D.new()
	rectShape.size = Vector2(width_pixels, height_pixels)
	collision.shape = rectShape
	
	team_id = team
	
	if team_id == 1:
		collision_mask = 4
		return
	collision_mask = 3

func _on_body_entered(body: Node2D) -> void:
	GameMaster.score_goal(team_id, 1)
