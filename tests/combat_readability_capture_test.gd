extends SceneTree
var game: Node
var checks := 0
var failed := false
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error(label)
func soldier(kind: String, team: int, point: Vector2) -> Unit:
	var spec: Dictionary = game.card_catalog[kind].base_stats()
	spec.team = team
	spec.lane = 1
	spec.unit_type = kind
	spec.spawn_positions = [point]
	game.spawn_deployment(spec)
	var unit: Unit = game.units.back()
	unit.set_physics_process(false)
	return unit
func frames(count: int = 3) -> void:
	for i in range(count): await physics_frame
func clear_units() -> void:
	for unit in game.units.duplicate(): unit.die()
func run() -> void:
	game = load("res://main.tscn").instantiate()
	game.tuning = game.tuning.duplicate()
	game.tuning.enemy_enabled = false
	root.add_child(game)
	current_scene = game
	game.set_process(false)
	game.set_physics_process(false)
	await process_frame
	var expected := {"rifle_squad":[100,45,300,0.75,650,6,3],"assault_squad":[225,25.6,420,0.25,400,4,4],"conscript_wave":[75,27.5,250,1.1,585,12,2]}
	for kind in expected:
		var card: BattleCard = game.card_catalog[kind]
		var v: Array = expected[kind]
		for index in range(v.size()):
			check(is_equal_approx(float([card.health,card.damage,card.move_speed,card.attack_interval,card.attack_range,card.quantity,card.command_cost][index]),float(v[index])), kind + " provisional stat " + str(index))
		for i in range(12):
			var u := soldier(kind,2,Vector2(3000+i*160,4000))
			check(absf(u.attack_interval/u.base_attack_interval-1) <= 0.06001,"interval variance bounded")
			check(absf(u.move_speed/u.base_move_speed-1) <= 0.03001,"speed variance bounded")
			check(u.total_health == card.health and u.attack_ranged_strength == card.damage and u.attack_range == card.attack_range,"role stats fixed")
	clear_units()
	await frames()
	var rifle := soldier("rifle_squad",2,Vector2(3000,game.field_size.y+300))
	var enemy := soldier("rifle_squad",1,Vector2(3000,game.field_size.y-200))
	rifle.has_entered_battlefield = false
	rifle.assigned_formation_slot = Vector2(3000,3300)
	rifle.state = Unit.State.ENTERING_BATTLEFIELD
	await frames()
	var interval := rifle.attack_interval
	rifle._physics_process(0.016)
	check(enemy.current_health == 55 and rifle.velocity == Vector2.ZERO,"incoming reinforcement stops and fires before arrival")
	check(not rifle.has_entered_battlefield and rifle.assigned_formation_slot == Vector2(3000,3300),"engagement retains entry geometry")
	rifle._physics_process(interval*0.5)
	check(enemy.current_health == 55,"rifle cadence does not fire early")
	rifle._physics_process(interval*0.5)
	check(enemy.current_health == 10 and rifle.attack_interval == interval,"rifle cadence fires again without reroll")
	enemy.die()
	await frames()
	rifle._physics_process(0.016)
	check(rifle.state == Unit.State.ENTERING_BATTLEFIELD,"reinforcement resumes immediate forward entry after threat dies")
	clear_units()
	await frames()
	var assault := soldier("assault_squad",2,Vector2(3000,3500))
	enemy = soldier("rifle_squad",1,Vector2(3000,2920))
	await frames()
	check(enemy.nearest_enemy() == assault and assault.nearest_enemy() == null,"rifles threaten assault outside assault range")
	assault.position.y = 3250
	await frames()
	check(assault.nearest_enemy() == enemy,"assault engages at close range")
	assault._physics_process(.016)
	assault._physics_process(assault.attack_interval)
	check(is_equal_approx(enemy.current_health, 48.8),"assault rapid fire applies two close ranged shots")
	clear_units()
	await frames()
	var attacker := soldier("rifle_squad",2,Vector2(3000,600))
	var defender := soldier("rifle_squad",1,Vector2(3300,600))
	await frames()
	attacker._physics_process(.016)
	check(attacker.state == Unit.State.CAPTURING and attacker.target == null,"capture threshold commits attacker to objective")
	check(attacker.modulate.a == 1 and attacker.is_alive(),"capturing remains fully visible and targetable")
	check(is_equal_approx(attacker.velocity.length(),attacker.move_speed*1.2),"capture speed bonus")
	check(defender.nearest_enemy() == attacker,"defender can acquire capturing attacker")
	attacker.apply_damage(1000)
	check(game.scores[2] == 0,"death before score line awards nothing")
	defender.die()
	await frames()
	attacker = soldier("rifle_squad",2,Vector2(3000,150))
	attacker._physics_process(.016)
	check(game.scores[2] == 0,"capture band does not award score")
	attacker.position.y = 120
	attacker._physics_process(.016)
	check(game.scores[2] == 1 and attacker.state == Unit.State.EXITING,"actual line awards score and starts exit")
	check(not attacker.is_alive() and not game.units.has(attacker),"exit removes unit from active combat")
	game.score_unit(attacker)
	check(game.scores[2] == 1,"exit cannot score twice")
	await create_timer(.15).timeout
	check(is_instance_valid(attacker) and attacker.modulate.a < 1,"fade happens after scoring")
	await create_timer(.4).timeout
	check(not is_instance_valid(attacker),"exit frees after fade")
	game.scores[1] = game.tuning.victory_score-1
	attacker = soldier("rifle_squad",1,Vector2(3000,game.field_size.y-120))
	attacker._physics_process(.016)
	check(not game.battle_active and attacker.state == Unit.State.EXITING,"enemy score line and winning exit")
	await create_timer(.6).timeout
	check(not is_instance_valid(attacker),"winning scorer completes fade after battle ends")
	print("COMBAT READABILITY CAPTURE: %d assertions, %s" % [checks,"FAILED" if failed else "PASSED"])
	quit(1 if failed else 0)
