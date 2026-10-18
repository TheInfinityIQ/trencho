extends SceneTree

var game: Node
var checks := 0
var failed := false

# Observe after the battle and soldiers have completed each fixed simulation tick.
class PhysicsWindow extends Node:
	signal completed
	var ticks := 0
	func _ready() -> void:
		process_physics_priority = 100
	func _physics_process(_delta: float) -> void:
		ticks += 1
		if ticks == 180:
			set_physics_process(false)
			completed.emit()

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error("FAILED: " + label)

func run() -> void:
	check(Engine.physics_ticks_per_second == 60, "battle simulation runs at 60 physics ticks per second")
	game = load("res://main.tscn").instantiate()
	game.tuning = game.tuning.duplicate()
	game.tuning.enemy_enabled = false
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	await process_frame
	var initial: float = game.economies[2].current_command
	var elapsed: float = game.formation_manager.elapsed
	for i in range(10):
		game._process(0.25)
	check(is_equal_approx(game.economies[2].current_command, initial), "render callbacks do not regenerate Command")
	check(is_equal_approx(game.formation_manager.elapsed, elapsed), "render callbacks do not advance logistics")
	check(game.formation_manager.pending.is_empty(), "render callbacks do not deploy enemies")
	# Reset these inputs so a pre-fix failure cannot conceal subsequent failures.
	game.economies[2].current_command = 3
	game.formation_manager.elapsed = 0
	game.set_physics_process(true)
	var window := PhysicsWindow.new()
	root.add_child(window)
	await window.completed
	game.set_physics_process(false)
	check(is_equal_approx(game.economies[2].current_command, 6), "180 physics ticks regenerate exactly three Command")
	check(is_equal_approx(game.formation_manager.elapsed, 3), "logistics use the same three-second clock")
	check(not game.player_deployment_confirmed and game.units.is_empty(), "physics time alone does not unlock the enemy")
	window.queue_free()
	game.economies[2].current_command = 10
	var result: Dictionary = game.deployment_manager.request_formation(2, [game.card_catalog.rifle_squad], Rect2(1200, 5300, 940, 140))
	check(result.is_valid, "clock scenario accepts a six-soldier entry formation")
	game.set_physics_process(true)
	window = PhysicsWindow.new()
	root.add_child(window)
	await window.completed
	game.set_physics_process(false)
	var flow: Dictionary = game.formation_manager.flow_counts(2)
	check(flow.queued == 0 and flow.entering == 0 and flow.active == 6, "six soldiers enter and advance on the physics clock")
	check(is_equal_approx(game.formation_manager.elapsed, 6), "second physics window adds exactly three seconds")
	var positions: Array = []
	for unit in game.units:
		unit.set_physics_process(false)
		positions.append([snappedf(unit.position.x, 0.01), snappedf(unit.position.y, 0.01)])
	print("CLOCK SNAPSHOT: " + JSON.stringify({"command": snappedf(game.economies[2].current_command, 0.001), "positions": positions, "queued": flow.queued, "entering": flow.entering, "active": flow.active}))
	print("SIMULATION CLOCK: %d assertions, %s" % [checks, "FAILED" if failed else "PASSED"])
	quit(1 if failed else 0)
