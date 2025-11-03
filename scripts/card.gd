extends TextureRect

var start_position: Vector2
var is_selected: bool = false

@onready var animation_player: AnimationPlayer = $AnimationPlayer
var rotation_tween: Tween
@onready var start_rotation = rotation
var elevated_offset: int = -25

func _on_mouse_entered() -> void:
	if is_selected:
		return
	elevate()

func _on_mouse_exited() -> void:
	if is_selected:
		return
	depress()

func create(new_texture: Texture2D, created_position: Vector2) -> void:
	texture = new_texture
	start_position = created_position

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if not is_selected: 
				select()
				return
			deselect()

func select():
	is_selected = true
	position.y = start_position.y + elevated_offset
	selected_animation()

func deselect():
	is_selected = false
	stop_selected_animation()
	return_to_start()

func selected_animation():
	rotation_tween = create_tween().set_loops()
	rotation_tween.tween_property(self, "rotation", 0.05, 0.33)
	rotation_tween.tween_property(self, "rotation", -0.05, 0.33)

func stop_selected_animation():
	if rotation_tween:
		rotation_tween.kill()
	

func return_to_start():
	reorientate();
	depress()

func elevate():
	var elevate_tween = create_tween()
	elevate_tween.tween_property(self, "position", Vector2(position.x, position.y + elevated_offset), 0.05)

func depress():
	var return_tween = create_tween()
	return_tween.tween_property(self, "position", start_position, 0.2)

func reorientate():
	var return_tween = create_tween()
	return_tween.tween_property(self, "rotation", start_rotation, 0.1)
