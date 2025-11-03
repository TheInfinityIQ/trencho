extends Node2D

@onready var team1: Node = get_node("team1")
@onready var team2: Node = get_node("team2")
@onready var map: Node = get_node("MapTest")

func _ready() -> void:
	print(team1)
	init_map()

func init_map() -> void:
	map.init()
	pass
