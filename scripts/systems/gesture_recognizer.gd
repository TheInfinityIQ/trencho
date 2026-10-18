extends RefCounted

# Screen-space thresholds make recognition independent of camera zoom.
static func _classify_stroke(points: PackedVector2Array) -> Dictionary:
	var result := {"success": false, "command_type": "", "failure_reason": "UNRECOGNIZED_GESTURE", "length": 0.0, "closure": 0.0, "area": 0.0, "center": Vector2.ZERO, "radius": 0.0}
	if points.size() < 2:
		return result
	var minimum: Vector2 = points[0]
	var maximum: Vector2 = points[0]
	var area := 0.0
	for index in range(points.size()):
		if not points[index].is_finite(): return result
		minimum = minimum.min(points[index])
		maximum = maximum.max(points[index])
		if index > 0: result.length += points[index].distance_to(points[index - 1])
		area += points[index].cross(points[(index + 1) % points.size()])
	result.closure = points[0].distance_to(points[-1])
	result.area = absf(area) * 0.5
	var size := maximum - minimum
	var diameter := maxf(size.x, size.y)
	result.center = (minimum + maximum) * 0.5
	result.radius = diameter * 0.5
	if result.length < 35 or diameter < 25:
		return result
	var box_area := size.x * size.y
	var coherent_loop: bool = diameter >= 40 and minf(size.x, size.y) / diameter >= 0.4 and result.closure <= maxf(22, diameter * 0.35) and box_area > 0 and result.area / box_area >= 0.35 and result.length <= diameter * 5.5
	if coherent_loop:
		result.command_type = "DEFEND"
	elif result.closure >= 35 and result.closure / result.length >= 0.65:
		result.command_type = "ADVANCE"
	else:
		return result
	result.success = true
	result.failure_reason = ""
	return result

static func classify(points: PackedVector2Array) -> Dictionary:
	# A knob-to-loop stem is allowed: recognize a coherent loop at the end of
	# the stroke before considering the whole path as an Advance line.
	var best: Dictionary = {}
	var best_closure := INF
	for index in range(0, maxi(1, points.size() - 7), 2):
		var candidate := _classify_stroke(points.slice(index))
		if candidate.success and candidate.command_type == "DEFEND":
			var closure: float = candidate.closure / maxf(1, candidate.radius * 2)
			if closure < best_closure:
				best_closure = closure
				best = candidate
	return best if not best.is_empty() else _classify_stroke(points)
