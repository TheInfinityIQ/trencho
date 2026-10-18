extends SceneTree
var game: Node
var checks := 0
var failed := false
func _initialize() -> void: call_deferred("run")
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error("FAILED: "+message)
func button(point: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = point
	return event
func run() -> void:
	root.size = Vector2i(1280,900)
	game = load("res://main.tscn").instantiate()
	game.tuning = game.tuning.duplicate()
	game.tuning.enemy_enabled = false
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	game.planning.set_process(false)
	game.hand.cards.assign([game.card_catalog.rifle_squad])
	game.hand._toggle_card(0)
	game.economies[2].current_command = 10
	var ui = game.command_ui
	ui.open_blueprint(Vector2(3200,3500))
	await process_frame
	var start: Vector2 = ui.blueprint_preview.global_position+ui.blueprint_box.end
	var anchor: Vector2 = ui.blueprint_preview.global_position+ui.blueprint_box.position
	ui._input(button(start,true))
	check(ui.blueprint_resizing,"box handle begins resizing")
	for offset in [Vector2(20,12),Vector2(40,30),Vector2(-15,-10),Vector2(35,25)]:
		var motion := InputEventMouseMotion.new()
		motion.position = start+offset
		ui._input(motion)
		var corner: Vector2 = ui.blueprint_preview.global_position+ui.blueprint_box.end
		check(corner.distance_to(motion.position)<1,"diagonal resize handle follows pointer without fit/recenter drift")
		check((ui.blueprint_preview.global_position+ui.blueprint_box.position).distance_to(anchor)<1,"opposite corner stays anchored")
	ui._input(button(start+Vector2(35,25),false))
	check(not ui.blueprint_resizing,"release ends box resize")
	check(game.economies[2].current_command == 10 and game.hand.selected_indices==[0],"resizing preserves cards and resources")
	check(ui.find_children("*","Slider",true,false).is_empty(),"blueprint contains no slider controls")
	for index in range(4):
		ui.set_blueprint_size(940,460)
		var box: Rect2 = ui.blueprint_box
		var corners: Array[Vector2] = [box.position,Vector2(box.end.x,box.position.y),box.end,Vector2(box.position.x,box.end.y)]
		var delta: Vector2 = [Vector2(10,8),Vector2(-10,8),Vector2(-10,-8),Vector2(10,-8)][index]
		var corner: Vector2 = ui.blueprint_preview.global_position+corners[index]
		var opposite: Vector2 = ui.blueprint_preview.global_position+corners[(index+2)%4]
		ui._input(button(corner,true))
		var diagonal := InputEventMouseMotion.new()
		diagonal.position = corner+delta
		ui._input(diagonal)
		var updated: Rect2 = ui.blueprint_box
		var updated_corners: Array[Vector2] = [updated.position,Vector2(updated.end.x,updated.position.y),updated.end,Vector2(updated.position.x,updated.end.y)]
		check((ui.blueprint_preview.global_position+updated_corners[index]).distance_to(diagonal.position)<1,"each corner follows a diagonal drag")
		check((ui.blueprint_preview.global_position+updated_corners[(index+2)%4]).distance_to(opposite)<1,"each corner preserves its opposite anchor")
		ui._input(button(diagonal.position,false))
	ui.set_blueprint_size(940,460)
	var edge_start: Vector2 = ui.blueprint_preview.global_position+Vector2(ui.blueprint_box.end.x,ui.blueprint_box.get_center().y)
	var old_depth: float = ui.blueprint_depth
	ui._input(button(edge_start,true))
	var edge_motion := InputEventMouseMotion.new()
	edge_motion.position = edge_start+Vector2(20,40)
	ui._input(edge_motion)
	check(is_equal_approx(ui.blueprint_depth,old_depth) and ui.blueprint_width>940,"edge resizing affects its axis only")
	ui._input(button(edge_motion.position,false))
	ui.set_blueprint_size(940,460)
	var corner_start: Vector2 = ui.blueprint_preview.global_position+ui.blueprint_box.end
	ui._input(button(corner_start,true))
	var limit_motion := InputEventMouseMotion.new()
	limit_motion.position = corner_start+Vector2(5000,10)
	ui._input(limit_motion)
	var depth_at_limit: float = ui.blueprint_depth
	limit_motion.position.y += 30
	ui._input(limit_motion)
	check(is_equal_approx(ui.blueprint_width,3000) and ui.blueprint_depth>depth_at_limit,"clamping width never freezes diagonal depth movement")
	ui._input(button(Vector2(-1000,-1000),false))
	check(not ui.blueprint_resizing and ui.pending_rectangle.size.x>0 and ui.pending_rectangle.size.y>0,"release outside preview ends captured resize with valid dimensions")
	check(game.economies[2].current_command==10 and game.formation_manager.pending.is_empty(),"resize release outside controls never commits deployment")
	ui.cancel_current()
	print("BLUEPRINT DRAG: %d assertions, %s" % [checks,"FAILED" if failed else "PASSED"])
	quit(1 if failed else 0)
