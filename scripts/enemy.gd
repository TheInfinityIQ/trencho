extends CharacterBody2D

const movement_speed: float = 300
var movement_speed_modifier: float
var direction_vector: Vector2

var total_health: int = 100
var current_health: int = total_health
var health_bar_modifier = 1

@onready var team_node = get_parent()
@onready var body = $CollisionShape2D
@onready var health_node: ColorRect = $CurrentHealth
@onready var total_health_node_size: int = health_node.size.x
@onready var current_health_node_size: int = total_health_node_size

func _ready() -> void:
	movement_speed_modifier = randf_range(0.85, 1.20)
	if team_node.name == "team1":
		direction_vector = Vector2.DOWN
		return
	direction_vector = Vector2.UP

func _physics_process(delta: float) -> void:
	if get_slide_collision_count():
		velocity = Vector2.ZERO
		print("MELEE_FIGHT!")
		return
	
	velocity = (movement_speed * movement_speed_modifier) * direction_vector
	move_and_slide()
# Layout -> Transform -> Size
func deal_damage(incoming_damage) -> void:
	if current_health - incoming_damage < 0:
		print("DEAD")
		die()
		return
	
	current_health = current_health - incoming_damage

func update_health_bar():
	var percentage_health_remaining: float = roundf((current_health / total_health) * 100)
	print()
	#health_node()

func die() -> void:
	queue_free()
