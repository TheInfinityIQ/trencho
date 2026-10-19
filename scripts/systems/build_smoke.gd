extends Node
var checks := 0
var root: Window:
	get: return get_tree().root
var failed := false
func _ready() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error("EXPORT SMOKE: "+label)
func play_button(node: Node) -> Button:
	if node is Button and node.text=="Play": return node
	for child in node.get_children():
		var found := play_button(child)
		if found!=null: return found
	return null
func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	for index in range(3): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "user://consolidation-export-"+name+".png"
	check(root.get_texture().get_image().save_png(path)==OK,"save screenshot")
	print("EXPORT CAPTURE: ",ProjectSettings.globalize_path(path))
## Explicit developer-only --build-smoke run; ordinary Play never loads this node.
func run() -> void:
	print("EXPORT SMOKE STARTED")
	if DisplayServer.get_name()!="headless": DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size=Vector2i(1280,800)
	check(not OS.has_feature("editor"),"running exported runtime")
	check(ProjectSettings.get_setting("application/config/version")=="0.5.2-consolidation","release version")
	var menu: Node = get_tree().current_scene
	await get_tree().process_frame
	await capture("menu")
	var play := play_button(menu)
	check(play!=null,"ordinary Play button")
	play.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var game = get_tree().current_scene
	check(game.scene_file_path=="res://main.tscn","Play loads exported battle")
	game.tuning = game.tuning.duplicate()
	game.tuning.enemy_enabled=false
	game.economies[2].current_command=10
	check(game.telemetry.enabled and not game.hud.debug_panel.visible,"background telemetry without debug overlay")
	game.hand.cards.assign([game.card_catalog.rifle_squad])
	game.hand.selected_indices.assign([0])
	game.command_ui.open_blueprint(Vector2(3328,4000))
	await get_tree().process_frame
	check(not game.command_ui.confirm_button.disabled,"usable exported default blueprint")
	await capture("blueprint")
	game.command_ui.cancel_current()
	var card = game.card_catalog.rifle_squad
	var size: Vector2 = game.deployment_manager.default_blueprint_size(card.quantity)
	var response: Dictionary = game.deployment_manager.request_squad(2,[card],Rect2(Vector2(2500,0),size),"DEFEND",Vector2(3328,4000))
	check(response.is_valid,"exported normal resource purchase")
	check(game.squad_commands.orders[response.command_result.defensive_point_id].facing==Vector2.UP,"exported enemy-facing front")
	for index in range(120): await get_tree().physics_frame
	game.show_overview()
	await capture("battle")
	game.finish_battle(2,"Export smoke check")
	check(not game.telemetry.export_path.is_empty(),"ordinary end-of-battle telemetry saved")
	print("EXPORTED PLAY SMOKE: %d checks, %s" % [checks,"FAILED" if failed else "PASSED"])
	get_tree().quit(1 if failed else 0)
