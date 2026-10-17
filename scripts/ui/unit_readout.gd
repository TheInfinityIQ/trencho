extends Node2D
const SYMBOLS = preload("res://scripts/ui/unit_symbols.gd")
var unit: Unit

func _process(_delta: float) -> void:
	global_rotation = 0
	queue_redraw()

func _draw() -> void:
	var camera := get_viewport().get_camera_2d()
	var zoom := camera.zoom.x if camera else 1.0
	# Keep symbols legible in overview while retaining their association with a soldier.
	var radius := maxf(18.0, 5.0 / zoom)
	draw_circle(Vector2.ZERO, radius * 1.35, Color(0.025,0.035,0.05,0.95))
	SYMBOLS.type_icon(self, Vector2.ZERO, radius, unit.unit_type)
	var bar := Rect2(-75, 80, 150, 20)
	draw_rect(bar.grow(4),Color(0.02,0.025,0.035))
	bar.size.x *= clampf(unit.current_health / unit.total_health, 0, 1)
	draw_rect(bar,Color(0.25,0.85,0.4) if unit.team_id == 2 else Color(1,0.25,0.2))
	var debug: bool = is_instance_valid(unit.battle) and is_instance_valid(unit.battle.hud) and unit.battle.hud.debug_panel.visible
	if debug or unit.state in [Unit.State.CAPTURING, Unit.State.EXITING]:
		var state_center := Vector2(105,90)
		draw_circle(state_center,radius*1.4,Color(0.025,0.035,0.05,0.95))
		SYMBOLS.state_icon(self,state_center,radius,unit.state)
