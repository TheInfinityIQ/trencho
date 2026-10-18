extends RefCounted

signal command_changed(current: float, maximum: float)
var telemetry: RefCounted
var telemetry_team := 0
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
	if telemetry != null:
		var generated := command_regeneration_rate*delta
		var wasted := maxf(0,previous+generated-maximum_command)
		var cap_seconds := wasted/command_regeneration_rate if command_regeneration_rate > 0 else (delta if previous >= maximum_command else 0.0)
		telemetry.economy_tick(telemetry_team,generated,wasted,cap_seconds)
	if current_command != previous:
		command_changed.emit(current_command, maximum_command)

func can_spend(amount: float) -> bool:
	return amount >= 0 and current_command + 0.00001 >= amount

func spend(amount: float) -> bool:
	if not can_spend(amount):
		return false
	current_command = maxf(0, current_command - amount)
	if telemetry != null and telemetry.enabled and not telemetry.closed: telemetry.data.economy[str(telemetry_team)].command_spent += amount
	command_changed.emit(current_command, maximum_command)
	return true
