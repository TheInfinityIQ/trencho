extends RefCounted

static func simplify(points: PackedVector2Array, tolerance: float = 12.0) -> PackedVector2Array:
	if points.size() <= 2: return points.duplicate()
	var best := 0.0
	var split := 0
	for index in range(1, points.size()-1):
		var distance := points[index].distance_to(Geometry2D.get_closest_point_to_segment(points[index], points[0], points[-1]))
		if distance > best:
			best = distance
			split = index
	if best <= tolerance: return PackedVector2Array([points[0], points[-1]])
	var left := simplify(points.slice(0, split+1), tolerance)
	left.remove_at(left.size()-1)
	left.append_array(simplify(points.slice(split), tolerance))
	return left

static func _metrics(points: PackedVector2Array) -> Dictionary:
	var minimum := points[0]
	var maximum := minimum
	var length := 0.0
	var area := 0.0
	var turn := 0.0
	for index in range(points.size()):
		minimum = minimum.min(points[index])
		maximum = maximum.max(points[index])
		if index > 0: length += points[index].distance_to(points[index-1])
		area += points[index].cross(points[(index+1)%points.size()])
		if index > 1: turn += (points[index-1]-points[index-2]).angle_to(points[index]-points[index-1])
	var size := maximum-minimum
	var diameter := maxf(size.x,size.y)
	return {"length":length,"closure":points[0].distance_to(points[-1]),"area":absf(area)*0.5,"turn":absf(turn),"center":(minimum+maximum)*0.5,"radius":diameter*0.5,"aspect":minf(size.x,size.y)/maxf(1,diameter),"box_area":size.x*size.y}

static func classify(points: PackedVector2Array) -> Dictionary:
	var result := {"success":false,"command_type":"","failure_reason":"UNRECOGNIZED_GESTURE","length":0.0,"closure":0.0,"area":0.0,"center":Vector2.ZERO,"radius":0.0,"route":PackedVector2Array(),"raw_count":points.size(),"simplified_count":0,"ambiguous":false,"loop_detected":false}
	if points.size() < 2: return result
	for point in points:
		if not point.is_finite(): return result
	var clean := simplify(points, 4)
	var metrics := _metrics(clean)
	result.merge(metrics,true)
	if metrics.length < 35 or metrics.radius < 12.5: return result
	var loop_start := -1
	var best := INF
	var attempted_loop := false
	# Only a complete terminal revolution counts, regardless of winding or entry side.
	for index in range(maxi(1,points.size()-5)):
		var tail := simplify(points.slice(index),3)
		if tail.size() < 5: continue
		var shape := _metrics(tail)
		var diameter: float = shape.radius*2
		var round_enough: bool = diameter >= 40 and shape.aspect >= 0.4 and shape.area/maxf(1,shape.box_area) >= 0.35
		if not round_enough: continue
		if shape.turn > PI*1.2 and shape.length > diameter*1.7: attempted_loop = true
		if shape.turn < TAU*0.84 or shape.closure > maxf(12,diameter*0.20) or shape.length > diameter*5.5: continue
		var score: float = shape.closure/maxf(1,diameter)
		if score < best:
			best = score
			loop_start = index
			result.merge(shape,true)
	if loop_start >= 0:
		result.command_type = "DEFEND"
		result.loop_detected = true
		result.route = simplify(points.slice(0,loop_start+1)) if loop_start > 0 else PackedVector2Array()
	elif attempted_loop or metrics.closure < 30 or metrics.turn > PI*1.6:
		result.failure_reason = "AMBIGUOUS_GESTURE"
		result.ambiguous = true
		return result
	else:
		result.command_type = "ADVANCE"
		var tolerance := 12.0
		result.route = simplify(points,tolerance)
		while result.route.size() > 5:
			tolerance *= 1.35
			result.route = simplify(points,tolerance)
	var route_tolerance := 12.0
	while result.route.size() > 5:
		route_tolerance *= 1.35
		result.route = simplify(result.route,route_tolerance)
	result.simplified_count = result.route.size()
	result.success = true
	result.failure_reason = ""
	return result
