extends RefCounted

static func type_icon(canvas: CanvasItem, center: Vector2, radius: float, kind: String, color: Color = Color.WHITE) -> void:
	if kind == "assault_squad":
		var points := PackedVector2Array([Vector2(0.2,-1),Vector2(-0.7,0.1),Vector2(-0.1,0.1),Vector2(-0.3,1),Vector2(0.8,-0.2),Vector2(0.1,-0.2)])
		for i in range(points.size()): points[i] = center + points[i] * radius
		canvas.draw_colored_polygon(points, color)
	elif kind == "conscript_wave":
		for offset in [-0.65, 0.0, 0.65]: canvas.draw_circle(center + Vector2(offset * radius, 0), radius * 0.23, color)
	else:
		canvas.draw_colored_polygon(PackedVector2Array([center+Vector2(0,-radius),center+Vector2(radius*0.7,0),center+Vector2(0,radius),center-Vector2(radius*0.7,0)]),color)

static func state_icon(canvas: CanvasItem, center: Vector2, radius: float, state: int) -> void:
	var white := Color.WHITE
	var width := radius * 0.18
	if state == -1:
		canvas.draw_arc(center,radius*0.8,0,TAU,24,white,width,true)
		canvas.draw_line(center,center-Vector2(0,radius*0.55),white,width,true)
		canvas.draw_line(center,center+Vector2(radius*0.4,0),white,width,true)
	elif state == 4 or state == 5:
		canvas.draw_line(center+Vector2(-radius*0.6,radius),center+Vector2(-radius*0.6,-radius),white,width,true)
		canvas.draw_colored_polygon(PackedVector2Array([center+Vector2(-radius*0.6,-radius),center+Vector2(radius,-radius*0.5),center+Vector2(-radius*0.6,0)]),Color(1,0.85,0.25))
	elif state == 1:
		canvas.draw_arc(center,radius*0.65,0,TAU,24,white,width,true)
		canvas.draw_line(center-Vector2(radius,0),center+Vector2(radius,0),white,width,true)
		canvas.draw_line(center-Vector2(0,radius),center+Vector2(0,radius),white,width,true)
	else:
		canvas.draw_line(center+Vector2(0,radius),center-Vector2(0,radius),white,width,true)
		canvas.draw_polyline(PackedVector2Array([center+Vector2(-radius*0.6,-radius*0.2),center-Vector2(0,radius),center+Vector2(radius*0.6,-radius*0.2)]),white,width,true)

static func shield_icon(canvas: CanvasItem, center: Vector2, radius: float, color: Color = Color.WHITE) -> void:
	canvas.draw_polyline(PackedVector2Array([center + Vector2(-radius, -radius), center + Vector2(radius, -radius), center + Vector2(radius * 0.8, radius * 0.35), center + Vector2(0, radius), center + Vector2(-radius * 0.8, radius * 0.35), center + Vector2(-radius, -radius)]), color, maxf(1, radius * 0.18), true)
