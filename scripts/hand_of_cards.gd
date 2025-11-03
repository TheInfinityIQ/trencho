extends Control

@onready var image = Image.new()
@onready var commander_image: Texture2D = load("res://assets/cards/card_soldier_test.png")
@onready var soldier_image: Texture2D = load("res://assets/cards/card_commander_test.png")
@onready var CARD = preload("res://scenes/ui/card.tscn")

enum CARD_TYPE {
	COMMANDER,
	SOLDIER
}

var deck = [
	CARD_TYPE.COMMANDER
	, CARD_TYPE.SOLDIER
	, CARD_TYPE.SOLDIER
	, CARD_TYPE.COMMANDER
	, CARD_TYPE.SOLDIER
	]

var num_soldier: int = 3
var num_commander: int = 2
var num_cards: int = num_soldier + num_commander

func _ready() -> void:
	build_deck()

func build_deck() -> void:
	var card_count = 0
	for card: CARD_TYPE in deck:
		build_card(card, card_count)
		card_count += 1

func build_card(card, card_count) -> void:
	var position_x_offset = 100
	var new_card = CARD.instantiate()
	var texture: Texture2D
	if card == CARD_TYPE.SOLDIER:
		texture = soldier_image
	else:
		texture = commander_image
	add_child(new_card)
	new_card.position.x += position_x_offset * card_count
	new_card.create(texture, new_card.position)

func _on_card_mouse_entered() -> void:
	pass # Replace with function body.
