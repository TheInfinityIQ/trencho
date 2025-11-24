extends Node

var team_one_score: int = 0
var team_two_score: int = 0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func score_goal(team, score):
	if team == 1:
		team_one_score += score
		return
	team_two_score += score
