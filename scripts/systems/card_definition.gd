extends Resource
class_name BattleCard

enum Type { UNIT, MODIFIER }
@export var card_id: String = ""
@export var display_name: String = ""
@export var card_type: Type = Type.UNIT
@export var tags: PackedStringArray = []
@export var required_target_tags: PackedStringArray = []
@export var command_cost: float = 3.0
@export_multiline var description: String = ""
@export var art: Texture2D
@export_group("Unit stats")
@export var quantity: int = 6
@export var health: float = 100.0
@export var damage: float = 45.0
@export var melee_damage: float = 25.0
@export var move_speed: float = 300.0
@export var attack_range: float = 650.0
@export var attack_interval: float = 0.75
@export var melee_range: float = 100.0
@export var melee_interval: float = 1.5
@export var score_value: int = 1
@export_group("Modifier effects")
@export var additive: Dictionary = {}
@export var multiplicative: Dictionary = {}
@export var overrides: Dictionary = {}

func base_stats() -> Dictionary:
	return {"quantity": quantity, "health": health, "damage": damage,
		"melee_damage": melee_damage, "move_speed": move_speed,
		"attack_range": attack_range, "attack_interval": attack_interval,
		"melee_range": melee_range, "melee_interval": melee_interval, "score_value": score_value}

func compatible_with(unit_card: Resource) -> bool:
	for tag in required_target_tags:
		if not unit_card.tags.has(tag):
			return false
	return true
