extends Node

var battle: Node
var active := false
var blend := 0.0
var effect: ColorRect
var previous_real_time := 0

func _ready() -> void:
	previous_real_time = Time.get_ticks_usec()
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	effect = ColorRect.new()
	effect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	effect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; uniform sampler2D screen_texture : hint_screen_texture, filter_nearest; uniform float desaturation = 0.0; uniform float brightness = 1.0; void fragment(){vec4 c=texture(screen_texture, SCREEN_UV); float g=dot(c.rgb,vec3(0.299,0.587,0.114)); COLOR=vec4(mix(c.rgb,vec3(g),desaturation)*brightness,c.a);}"
	var material := ShaderMaterial.new()
	material.shader = shader
	effect.material = material
	layer.add_child(effect)
	effect.visible = false

func begin() -> void:
	if battle.battle_active: active = true

func end() -> void:
	active = false

func advance(real_delta: float) -> void:
	var duration: float = battle.tuning.planning_transition_in_duration if active else battle.tuning.planning_transition_out_duration
	blend = move_toward(blend, 1.0 if active else 0.0, real_delta / maxf(0.01, duration))
	var eased := smoothstep(0.0, 1.0, blend)
	Engine.time_scale = lerpf(1.0, battle.tuning.planning_time_scale, eased)
	effect.visible = blend > 0.001
	effect.material.set_shader_parameter("desaturation", eased * battle.tuning.planning_desaturation_amount)
	effect.material.set_shader_parameter("brightness", lerpf(1.0, battle.tuning.planning_brightness_adjustment, eased))

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	advance(minf(0.1, float(now - previous_real_time) / 1000000.0))
	previous_real_time = now

func _exit_tree() -> void:
	# Scene restart/exit must never leave the rest of the application slowed.
	Engine.time_scale = 1.0
