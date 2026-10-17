extends RefCounted

signal command_changed(current: float, maximum: float)
var current_command: float
var maximum_command: float
var command_regeneration_rate: float

func _init(maximum: float = 10, starting: float = 3, regeneration: float = 1) -> void:
	maximum_command = maxf(0, maximum)
	current_command = clampf(starting, 0, maximum_command)
	command_regeneration_rate = maxf(0, regeneration)

func tick(delta: float) -> void:
	var previous := current_command
	current_command = minf(maximum_command, current_command + command_regeneration_rate * delta)
	if current_command != previous:
		command_changed.emit(current_command, maximum_command)

func can_spend(amount: float) -> bool:
	return amount >= 0 and current_command + 0.00001 >= amount

func spend(amount: float) -> bool:
	if not can_spend(amount):
		return false
	current_command = maxf(0, current_command - amount)
	command_changed.emit(current_command, maximum_command)
	return true
