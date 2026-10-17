extends Control

@onready var image = Image.new()
@onready var commander_image: Texture2D = load("res://assets/cards/card_soldier_test.png")
@onready var soldier_image: Texture2D = load("res://assets/cards/card_commander_test.png")
@onready var CARD = preload("res://scenes/ui/LEGACY_card.tscn")

var deck = [
	Global.CARD_TYPE.COMMANDER
	, Global.CARD_TYPE.SOLDIER
	, Global.CARD_TYPE.SOLDIER
	, Global.CARD_TYPE.COMMANDER
	, Global.CARD_TYPE.SOLDIER
	]

var num_soldier: int = 3
var num_commander: int = 2
var num_cards: int = num_soldier + num_commander

func _ready() -> void:
	build_deck()

func build_deck() -> void:
	var card_count = 0
	for card: Global.CARD_TYPE in deck:
		build_card(card, card_count)
		card_count += 1

func build_card(card, card_count) -> void:
	var position_x_offset = 100
	var new_card = CARD.instantiate()
	var texture: Texture2D
	if card == Global.CARD_TYPE.SOLDIER:
		texture = soldier_image
	else:
		texture = commander_image
	add_child(new_card)
	new_card.position.x += position_x_offset * card_count
	new_card.init(texture, new_card.position)
