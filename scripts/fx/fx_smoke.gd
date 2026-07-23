extends Node2D

const MIN_PARTICLES := 3
const MAX_PARTICLES := 7

class SmokeParticle:
	var position: Vector2
	var velocity: Vector2
	var radius: float
	var lifetime: float
	var age: float = 0.0
	var alpha: float

var particles: Array[SmokeParticle] = []

func setup(origin: Vector2, direction: Vector2) -> void:
	global_position = origin

	var count := randi_range(MIN_PARTICLES, MAX_PARTICLES)

	for i in count:
		var p := SmokeParticle.new()

		p.position = Vector2.ZERO

		var spread := direction.rotated(randf_range(-0.5, 0.5))
		p.velocity = spread * randf_range(60, 120)

		p.radius = randf_range(16, 64)
		p.lifetime = randf_range(0.8, 1.4)
		p.alpha = randf_range(0.45, 0.85)

		particles.append(p)

func _process(delta: float) -> void:
	var alive := false

	for p in particles:
		if p.age >= p.lifetime:
			continue

		alive = true

		p.age += delta
		p.position += p.velocity * delta

		# Slight expansion
		p.radius += delta * 3.0

		# Slow down over time
		p.velocity *= pow(0.25, delta)

	queue_redraw()

	if !alive:
		queue_free()

func _draw() -> void:
	for p in particles:
		if p.age >= p.lifetime:
			continue

		var t := p.age / p.lifetime

		draw_circle(
			p.position,
			p.radius,
			Color(0.55, 0.55, 0.55, p.alpha * (1.0 - t))
		)
