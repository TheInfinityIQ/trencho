extends CharacterBody2D
class_name Unit

const movement_speed: float = 300
var movement_speed_modifier: float
var direction_vector: Vector2
var init_direction_vector: Vector2

var total_health: float = 100
var current_health: float = total_health
var health_bar_modifier = 1
var attack_melee_strength: int = 25
var attack_ranged_strength: int = 40

@onready var team_node = get_parent()
@onready var body = $CollisionShape2D
@onready var health_node: ColorRect = $CurrentHealth
@onready var total_health_node_size: float = health_node.size.x
@onready var melee_timer: Timer = $MeleeTimer
@onready var ranged_timer: Timer = $RangedTimer
@onready var area_melee_range: Area2D = $MeleeArea2D
@onready var area_ranged_range: Area2D = $RangedArea2D
@onready var weapon_muzzle: Node2D = $MuzzleLocation

var SMOKE_PUFF := preload("res://scripts/fx/fx_smoke.gd")

var is_attacking: bool = false
var is_deployed: bool = false

enum COL_LAYERS {
	BODIES = 2,
	TEAM_ONE = 3,
	TEAM_TWO = 4
}

enum ATTACK_MODES {
	MELEE = 1,
	RANGED = 2
}

func deploy_unit():
	is_deployed = true

func _ready() -> void:
	init_values()

func init_values() -> void:
	melee_timer.wait_time = randf_range(1, 2)
	ranged_timer.wait_time = randf_range(2, 5)
	melee_timer.one_shot = true
	ranged_timer.one_shot = true
	movement_speed_modifier = randf_range(0.85, 1.20)
	set_collision_layers()
	if team_node.name == "TEAM_ONE":
		direction_vector = Vector2.DOWN
		init_direction_vector = direction_vector
		reset_direction()
	else: 
		direction_vector = Vector2.UP
		init_direction_vector = direction_vector
		reset_direction()
	deploy_unit()

func set_collision_layers(): 
	if team_node.name == "TEAM_ONE":
		area_melee_range.collision_layer = COL_LAYERS.TEAM_ONE
		area_melee_range.collision_mask = COL_LAYERS.TEAM_TWO
		area_ranged_range.collision_layer = COL_LAYERS.TEAM_ONE
		area_ranged_range.collision_mask = COL_LAYERS.TEAM_TWO
		collision_layer = COL_LAYERS.TEAM_ONE
		return
	area_melee_range.collision_layer = COL_LAYERS.TEAM_TWO
	area_melee_range.collision_mask = COL_LAYERS.TEAM_ONE
	area_ranged_range.collision_layer = COL_LAYERS.TEAM_TWO
	area_ranged_range.collision_mask = COL_LAYERS.TEAM_ONE
	collision_layer = COL_LAYERS.TEAM_TWO

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

func _on_body_entered_melee_area(body: Node2D) -> void:
	try_attack(ATTACK_MODES.MELEE)

func _on_body_entered_ranged_area(body: Node2D) -> void:
	try_attack(ATTACK_MODES.RANGED)

func _on_melee_timer_timeout() -> void:
	try_attack(ATTACK_MODES.MELEE)

func _on_ranged_timer_timeout() -> void:
	try_attack(ATTACK_MODES.RANGED)

func try_attack(attack_mode: ATTACK_MODES):
	if not is_deployed:
		return
	print("Trying to attack")
	var target
	if attack_mode == ATTACK_MODES.MELEE:
		target = try_melee_attack()
	else:
		target = try_ranged_attack()
	animate_attack(target)

func try_ranged_attack():
	var target = get_attack_target(ATTACK_MODES.RANGED)
	if target:
		is_attacking = true
		attack_ranged(target)
		return target
	is_attacking = false
	return null

func try_melee_attack():
	var target = get_attack_target(ATTACK_MODES.MELEE)
	if target:
		is_attacking = true
		attack_melee(target)
		return target
	is_attacking = false
	return null

func get_attack_target(attack_mode: ATTACK_MODES):
	var targets: Array[Node2D] = []
	if attack_mode == ATTACK_MODES.MELEE:
		targets = area_melee_range.get_overlapping_bodies()
	else:
		targets = area_ranged_range.get_overlapping_bodies()

	if not targets:
		return
	for target in targets:
		if is_valid_target(target):
			return target

func is_valid_target(target: CharacterBody2D) -> bool:
	if target.is_queued_for_deletion(): 
		return false
	return target is Unit && target.team_node.name != team_node.name && target.has_method("apply_damage")

func attack_melee(enemy) -> void:
	enemy.apply_damage(attack_melee_strength)
	if enemy.is_queued_for_deletion():
		is_attacking = false
		on_enemy_destroyed()
		return
	melee_timer.start()

func attack_ranged(enemy) -> void:
	spawn_smoke_at_weapon(global_position.direction_to(enemy.global_position))
	enemy.apply_damage(attack_ranged_strength)
	if enemy.is_queued_for_deletion():
		is_attacking = false
		on_enemy_destroyed()
		return
	ranged_timer.start()

func animate_attack(target):
	if not target:
		reset_direction.call_deferred()
		return
	face_target(target)

func face_target(target: CharacterBody2D) -> void:
	var offset = PI / 2
	var direction := global_position.direction_to(target.global_position)
	global_rotation = direction.angle() + offset

func reset_direction():
	print("Reset direction to init: %s" % init_direction_vector)
	var offset = 0
	if init_direction_vector == Vector2.DOWN:
		offset = PI
	global_rotation = 0 + offset

func on_enemy_destroyed():
	animate_attack(null)

func spawn_smoke_at_weapon(puff_direction: Vector2) -> void:
	var smoke := SMOKE_PUFF.new()
	get_tree().current_scene.add_child(smoke)
	smoke.setup(weapon_muzzle.global_position, puff_direction)
