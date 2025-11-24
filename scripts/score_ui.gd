extends Control

var format_team_one_text: String = "Team 1 score: %s"
var format_team_two_text: String = "Team 2 score: %s"
@onready var team_one_label: Label = get_node("TeamOneScore")
@onready var team_two_label: Label = get_node("TeamTwoScore")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	team_one_label.text = format_team_one_text % GameMaster.team_one_score
	team_two_label.text = format_team_two_text % GameMaster.team_two_score
	pass
