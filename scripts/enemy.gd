extends CharacterBody2D

const movement_speed: float = 300
var movement_speed_modifier: float
var direction_vector: Vector2

var total_health: float = 100
var current_health: float = total_health
var health_bar_modifier = 1
var attack_melee_strength: int = 25

@onready var team_node = get_parent()
@onready var body = $CollisionShape2D
@onready var health_node: ColorRect = $CurrentHealth
@onready var total_health_node_size: float = health_node.size.x
@onready var melee_timer: Timer = $Timer
@onready var area_melee_range: Area2D = $Area2D

var is_attacking: bool = false

enum COL_LAYERS {
	BODIES = 2,
	TEAM_ONE = 3,
	TEAM_TWO = 4
}

func _ready() -> void:
	collision_layer = COL_LAYERS.BODIES
	collision_mask = COL_LAYERS.BODIES
	melee_timer.wait_time = randf_range(1, 2)
	movement_speed_modifier = randf_range(0.85, 1.20)
	if team_node.name == "TEAM_ONE":
		direction_vector = Vector2.DOWN
		area_melee_range.collision_layer = COL_LAYERS.TEAM_ONE
		area_melee_range.collision_mask = COL_LAYERS.TEAM_TWO
		collision_layer = COL_LAYERS.TEAM_ONE
		return
	area_melee_range.collision_layer = COL_LAYERS.TEAM_TWO
	area_melee_range.collision_mask = COL_LAYERS.TEAM_ONE
	collision_layer = COL_LAYERS.TEAM_TWO
	direction_vector = Vector2.UP

func _physics_process(_delta: float) -> void:
	if is_attacking:
		velocity = Vector2.ZERO
		return
	
	velocity = (movement_speed * movement_speed_modifier) * direction_vector
	move_and_slide()

func apply_damage(incoming_damage) -> void:
	if current_health - incoming_damage <= 0:
		die()
		return
	
	current_health -= incoming_damage
	update_health_bar()

func update_health_bar():
	var per_health_remaining = current_health / total_health
	var new_size = total_health_node_size * per_health_remaining

	health_node.size.x = new_size

func die() -> void:
	print("DEAD")
	queue_free()

func _on_area_2d_area_shape_entered(area_rid: RID, area: Area2D, area_shape_index: int, local_shape_index: int) -> void:
	try_attack()

func _on_timer_timeout() -> void:
	try_attack()

func try_attack() -> void:
	var target = get_attack_target()
	if target:
		is_attacking = true
		attack_melee(target)
		return
	is_attacking = false
	

func get_attack_target():
	var targets = area_melee_range.get_overlapping_areas()
	for target in targets:
		if target.get_parent().has_method("apply_damage"):
			return target.get_parent()

func attack_melee(enemy) -> void:
	enemy.apply_damage(attack_melee_strength)
	if enemy.is_queued_for_deletion():
		is_attacking = false
		return
	melee_timer.start()
