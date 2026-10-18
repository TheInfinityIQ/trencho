extends CharacterBody2D
class_name Unit

signal died(unit: Unit)
enum State { ADVANCING, ENGAGING, DEAD, ENTERING_BATTLEFIELD, CAPTURING, EXITING, MOVING_TO_DEFEND, DEFENDING, RETURNING_TO_DEFENSE, RETREATING }
var state: State = State.ADVANCING
var telemetry_id := 0
var team_id: int = 2
var lane_id: int = 1
var battle: Node
var squad: BattleSquad
var squad_member_index := 0
var defense_established := false
var defense_avoid_side := 1.0
var unit_type := "rifle_squad"
var direction_vector := Vector2.UP
var init_direction_vector := Vector2.UP
var total_health: float = 100
var current_health: float = 100
var attack_ranged_strength: float = 45
var attack_melee_strength: float = 25
var move_speed: float = 300
var attack_range: float = 650
var attack_interval: float = 0.75
var melee_range: float = 100
var melee_interval: float = 1.5
var score_value: int = 1
var attack_remaining := 0.0
var is_deployed := false
var is_attacking := false
var target: Unit
var assigned_formation_slot := Vector2.ZERO
var reservation_id := -1
var has_entered_battlefield := true
var queue_wait := 0.0
var spawn_age := 0.0
var entry_elapsed := -1.0
var base_attack_interval: float
var base_move_speed: float
const READOUT = preload("res://scripts/ui/unit_readout.gd")
const TEAM_SHADER = preload("res://scripts/ui/unit_team.gdshader")
static var team_materials: Dictionary = {}
var SMOKE_PUFF = preload("res://scripts/fx/fx_smoke.gd")
@onready var team_node: Node = get_parent()
@onready var health_node: ColorRect = $CurrentHealth
@onready var health_width: float = health_node.size.x

func configure(owner_battle: Node, deployment: Dictionary, lane: int) -> void:
	battle = owner_battle
	squad = deployment.get("squad", null)
	team_id = deployment.team
	lane_id = lane
	unit_type = deployment.unit_type
	total_health = deployment.health
	current_health = total_health
	attack_ranged_strength = deployment.damage
	attack_melee_strength = deployment.melee_damage
	move_speed = deployment.move_speed
	attack_range = deployment.attack_range
	attack_interval = deployment.attack_interval
	melee_range = deployment.melee_range
	melee_interval = deployment.melee_interval
	score_value = deployment.score_value
	base_attack_interval = attack_interval
	base_move_speed = move_speed
	attack_interval *= 1.0 + battle.unit_rng.randf_range(-battle.tuning.attack_interval_variance, battle.tuning.attack_interval_variance)
	move_speed *= 1.0 + battle.unit_rng.randf_range(-battle.tuning.move_speed_variance, battle.tuning.move_speed_variance)

func _ready() -> void:
	z_index = 20
	if battle == null:
		team_id = 1 if team_node.name == "TEAM_ONE" else 2
	direction_vector = Vector2.DOWN if team_id == 1 else Vector2.UP
	init_direction_vector = direction_vector
	rotation = PI if team_id == 1 else 0.0
	collision_layer = 4 if team_id == 1 else 8
	collision_mask = 1
	if is_instance_valid(battle):
		$CollisionShape2D.scale = Vector2.ONE
		$CollisionShape2D.shape = $CollisionShape2D.shape.duplicate()
		$CollisionShape2D.shape.radius = battle.tuning.unit_radius
	for area_name in ["MeleeArea2D", "RangedArea2D"]:
		var area: Area2D = get_node(area_name)
		area.collision_layer = 0
		area.collision_mask = 8 if team_id == 1 else 4
		var shape: CollisionShape2D = area.get_node("CollisionShape2D")
		shape.shape = shape.shape.duplicate()
		shape.shape.radius = melee_range if area_name == "MeleeArea2D" else attack_range
	if not team_materials.has(team_id):
		var material := ShaderMaterial.new()
		material.shader = TEAM_SHADER
		material.set_shader_parameter("team_color", Color(1, 0.16, 0.12) if team_id == 1 else Color(0.12, 0.48, 1))
		team_materials[team_id] = material
	$SpriteBody.material = team_materials[team_id]
	$HealthBar.hide()
	$CurrentHealth.hide()
	var readout := READOUT.new()
	readout.unit = self
	add_child(readout)
	is_deployed = true
	set_notify_local_transform(true)
	update_health_bar()

func is_alive() -> bool:
	return state != State.DEAD and state != State.EXITING and current_health > 0 and not is_queued_for_deletion()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(battle) or not battle.battle_active or not is_alive(): return
	_simulate(delta)
	battle.telemetry.observe_unit(self,delta)

func _simulate(delta: float) -> void:
	if not is_alive() or (is_instance_valid(battle) and not battle.battle_active):
		return
	spawn_age += delta
	_update_entry_status()
	if squad != null and squad.retreating:
		_retreat_tick(delta)
		return
	if squad != null and squad.intent == "DEFEND":
		attack_remaining = maxf(0, attack_remaining - delta)
		_defend_tick(delta)
		_update_entry_status()
		return
	if is_instance_valid(battle) and (squad == null or squad.route_waypoints.is_empty() or not squad.route_target(self).is_finite()) and battle.crossed_capture_threshold(self):
		state = State.CAPTURING
	if state == State.CAPTURING:
		target = null
		is_attacking = false
		rotation = PI if team_id == 1 else 0.0
		velocity = init_direction_vector * move_speed * battle.tuning.capture_speed_multiplier
		move_and_slide()
		if battle.crossed_score_line(self):
			battle.score_unit(self)
		return
	attack_remaining = maxf(0, attack_remaining - delta)
	target = nearest_enemy()
	if is_instance_valid(target):
		_fire_at_target()
	else:
		is_attacking = false
		state = State.ADVANCING if has_entered_battlefield else State.ENTERING_BATTLEFIELD
		rotation = PI if team_id == 1 else 0.0
		var route_target: Vector2 = squad.route_target(self) if squad != null and has_entered_battlefield else Vector2.INF
		var strategic: float = squad.strategic_speed if squad != null and squad.strategic_speed > 0 else move_speed
		var combat_target: Unit = _cohesion_enemy()
		var next_position: Vector2 = route_target if route_target.is_finite() else global_position+direction_vector*300
		var interception: Unit = battle.squad_commands.intercepted_enemy(self,next_position) if squad != null else null
		if interception != null: combat_target = interception
		if combat_target != null:
			var approach: Vector2 = combat_target.global_position + combat_target.global_position.direction_to(global_position)*maxf(melee_range,attack_range*0.85)
			if interception != null or approach.distance_to(squad.combat_center) <= battle.tuning.cohesion_leash:
				state = State.ENGAGING
				_move_defender(approach,delta)
				return
		if route_target.is_finite():
			_move_defender(route_target,delta,strategic)
			_update_entry_status()
			return
		velocity = direction_vector * strategic
		if is_instance_valid(battle) and not battle.formation_manager.can_move_to(global_position + velocity * delta, self):
			velocity = Vector2.ZERO
		else:
			move_and_slide()
		_update_entry_status()

func nearest_enemy() -> Unit:
	var nearest: Unit = null
	var nearest_distance := INF
	var candidates: Array[Node2D] = $RangedArea2D.get_overlapping_bodies()
	for body in $MeleeArea2D.get_overlapping_bodies():
		if not candidates.has(body):
			candidates.append(body)
	for body in candidates:
		if body is Unit and body.team_id != team_id and body.is_alive():
			var distance := global_position.distance_squared_to(body.global_position)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest = body
	return nearest

func _update_entry_status() -> void:
	if has_entered_battlefield or not is_instance_valid(battle):
		return
	var radius: float = battle.tuning.unit_radius
	var entered: bool = global_position.y >= radius if team_id == 1 else global_position.y <= battle.field_size.y - radius
	if entered:
		has_entered_battlefield = true
		entry_elapsed = queue_wait + spawn_age
		battle.formation_manager.release_unit(self)
		if state == State.ENTERING_BATTLEFIELD:
			state = State.ADVANCING

func apply_damage(amount: float, attacker: Unit = null, source: String = "external") -> void:
	if not is_alive():
		return
	if squad != null and squad.retreating: amount *= battle.tuning.rout_damage_multiplier
	amount = maxf(0,amount)
	var before := current_health
	current_health = maxf(0, current_health - amount)
	battle.telemetry.damage(attacker,self,amount,before,current_health,source)
	update_health_bar()
	if current_health <= 0:
		die()

func update_health_bar() -> void:
	health_node.size.x = health_width * clampf(current_health / total_health, 0, 1)

func die() -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	current_health = 0
	died.emit(self)
	if is_instance_valid(battle):
		battle.unregister_unit(self)
	queue_free()

func spawn_smoke_at_weapon(direction: Vector2) -> void:
	if not is_instance_valid(battle):
		return
	var smoke = SMOKE_PUFF.new()
	smoke.z_index = 22
	battle.add_child(smoke)
	smoke.setup($MuzzleLocation.global_position, direction)

func begin_exit() -> void:
	state = State.EXITING
	target = null
	is_attacking = false
	velocity = Vector2.ZERO
	set_physics_process(false)
	set_deferred("collision_layer", 0)
	var duration: float = battle.tuning.exit_fade_duration
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, duration)
	tween.tween_property(self, "position", position + init_direction_vector * move_speed * 1.5 * duration, duration)
	tween.chain().tween_callback(queue_free)

func _base_debug_description() -> String:
	return "%s | Team %d | %s\nInterval base %.3fs / spawned %.3fs\nSpeed base %.1f / spawned %.1f | Range %.0f\nTarget: %s\nEntry origin: %s | On field: %s\nQueue wait %.2fs | Since spawn %.2fs | Entry total %.2fs\nCapturing: %s" % [unit_type, team_id, State.keys()[state], base_attack_interval, attack_interval, base_move_speed, move_speed, attack_range, str(target.get_instance_id()) if is_instance_valid(target) else "none", assigned_formation_slot, has_entered_battlefield, queue_wait, spawn_age, entry_elapsed, state == State.CAPTURING]

func _defense_pursuit_allowed(enemy: Unit) -> bool:
	# Territory restricts movement and pursuit, not shots within weapon range.
	return squad == null or squad.intent != "DEFEND" or not defense_established or battle.squad_commands.inside_defense(squad,enemy.global_position)

func _fire_at_target() -> void:
	state = State.ENGAGING
	is_attacking = true
	velocity = Vector2.ZERO
	rotation = global_position.direction_to(target.global_position).angle() + PI / 2
	if attack_remaining <= 0:
		var melee: bool = $MeleeArea2D.get_overlapping_bodies().has(target)
		attack_remaining = melee_interval if melee else attack_interval
		if not melee: spawn_smoke_at_weapon(global_position.direction_to(target.global_position))
		battle.squad_commands.record_damage(self,target)
		var multiplier: float = battle.tuning.breakthrough_damage_multiplier if squad != null and squad.breakthrough_remaining > 0 else 1.0
		target.apply_damage((attack_melee_strength if melee else attack_ranged_strength)*multiplier,self,"melee" if melee else "ranged")

func _defend_tick(delta: float) -> void:
	var destination: Vector2 = squad.defense_positions.get(squad_member_index, squad.defense_center)
	var waypoint: Vector2 = squad.route_target(self) if has_entered_battlefield else Vector2.INF
	if waypoint.is_finite(): destination = waypoint
	target = nearest_enemy()
	if is_instance_valid(target):
		_fire_at_target()
		return
	is_attacking = false
	if not waypoint.is_finite() and not defense_established and global_position.distance_to(destination) <= 10:
		defense_established = true
	if defense_established:
		var distance := INF
		for enemy in battle.squad_commands.defense_enemies(squad):
			if is_instance_valid(enemy) and enemy.is_alive() and _defense_pursuit_allowed(enemy):
				var candidate: float = global_position.distance_squared_to(enemy.global_position)
				if candidate < distance:
					distance = candidate
					target = enemy
		if is_instance_valid(target):
			state = State.ENGAGING
			var approach: Vector2 = target.global_position + target.global_position.direction_to(global_position) * maxf(melee_range, attack_range * 0.8)
			if not battle.squad_commands.inside_defense(squad,approach): approach = destination
			_move_defender(approach, delta)
			return
	state = State.RETURNING_TO_DEFENSE if defense_established else State.MOVING_TO_DEFEND
	if global_position.distance_to(destination) <= 10:
		state = State.DEFENDING
		velocity = Vector2.ZERO
	else:
		var speed: float = move_speed if defense_established else (squad.strategic_speed if squad.strategic_speed > 0 else move_speed)
		_move_defender(destination, delta, speed)

func _move_defender(destination: Vector2, delta: float, speed: float = -1) -> void:
	var displacement := destination - global_position
	var step := minf((move_speed if speed < 0 else speed) * delta, displacement.length())
	var direction := displacement.normalized()
	velocity = Vector2.ZERO
	# Bounded local steering only: no grid, graph search or navigation agent.
	# A persistent passing side avoids alternating left/right every frame.
	var side := defense_avoid_side
	var fallback := Vector2.ZERO
	var lookahead := minf(displacement.length(), battle.tuning.unit_radius * 2 + step)
	for angle in [0.0, side * 0.65, side * 1.2, side * 1.57, side * 2.1, -side * 0.65, -side * 1.2]:
		var heading := direction.rotated(angle)
		var proposed := global_position + heading * step
		if defense_established and battle.squad_commands.inside_defense(squad,global_position) and not battle.squad_commands.inside_defense(squad,proposed): continue
		if not battle.formation_manager.can_move_to(proposed, self): continue
		if fallback == Vector2.ZERO: fallback = heading
		var probe := global_position + heading * lookahead
		if defense_established and battle.squad_commands.inside_defense(squad,global_position) and not battle.squad_commands.inside_defense(squad,probe): continue
		if battle.formation_manager.can_move_to(probe, self):
			fallback = heading
			if absf(angle) > 0.1: defense_avoid_side = signf(angle)
			break
	if fallback != Vector2.ZERO:
		velocity = fallback * (step / maxf(delta, 0.0001))
		rotation = fallback.angle() + PI / 2
		move_and_slide()
func debug_description() -> String:
	var prefix := "No squad"
	if squad != null:
		prefix = "Squad %d | %s | Order %d | Selected %s | Living %d\nDefense %s radius %.0f" % [squad.squad_id, squad.intent, squad.order_id, squad.selected, squad.living_members().size(), squad.defense_center, squad.defense_radius]
	return prefix + "\n" + _base_debug_description()

func _notification(what: int) -> void:
	if not is_deployed or not is_instance_valid(battle) or battle.formation_manager == null: return
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED:
		battle.formation_manager.track_unit(self)
	elif what == NOTIFICATION_EXIT_TREE:
		battle.formation_manager.untrack_unit(self)


func _cohesion_enemy() -> Unit:
	if squad == null or not has_entered_battlefield: return null
	var best: Unit = null
	var distance := INF
	# Share one combat-neighborhood lookup per squad per physics tick.
	for enemy in squad.combat_candidates:
		if not is_instance_valid(enemy) or not enemy.is_alive(): continue
		var candidate: float = global_position.distance_squared_to(enemy.global_position)
		if candidate < distance:
			distance = candidate
			best = enemy
	return best

func _retreat_tick(delta: float) -> void:
	state = State.RETREATING
	target = null
	is_attacking = false
	attack_remaining = maxf(0,attack_remaining-delta)
	var home_y: float = battle.field_size.y-200 if team_id == 2 else 200
	var advance_speed: float = squad.strategic_speed if squad.strategic_speed > 0 else move_speed
	_move_defender(Vector2(global_position.x,home_y),delta,advance_speed*battle.tuning.rout_speed_multiplier)
	var recovered: bool = true
	for member in squad.living_members():
		if (member.global_position.y < home_y-15 if team_id == 2 else member.global_position.y > home_y+15): recovered = false
	if recovered:
		squad.retreating = false
		battle.telemetry.rout_ended(squad)
		for member in squad.living_members(): member.state = State.ADVANCING
