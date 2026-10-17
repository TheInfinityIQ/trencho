extends Resource
class_name BattleTuning

@export_group("Economy")
@export var command_max: float = 10.0
@export var command_start: float = 3.0
@export var command_regeneration_rate: float = 1.0
@export var enemy_command_max: float = 10.0
@export var enemy_command_start: float = 3.0
@export var enemy_command_regeneration_rate: float = 1.0
@export_group("Cards and spawning")
@export_range(1, 10) var maximum_hand_size: int = 5
@export_range(0, 2) var maximum_modifiers: int = 2
@export var random_seed: int = 16102026
@export_range(140, 400) var spawn_spacing: float = 160.0
@export_range(1, 100) var unit_radius: float = 70.0
@export_group("Formation entry")
@export_range(140, 1000) var enemy_exclusion_radius: float = 144.0
# Delay between ranks; soldiers across each rank enter together.
@export_range(0.05, 1) var reinforcement_interval: float = 0.12
@export_range(100, 1000) var offscreen_spawn_margin: float = 240.0
@export_group("Enemy")
@export var enemy_enabled: bool = true
@export_range(0.1, 10) var enemy_decision_interval: float = 1.0
@export_range(0, 1) var enemy_weak_lane_weight: float = 0.7
@export_group("Battle resolution")
@export var score_victory_enabled: bool = true
@export var victory_score: int = 100
@export var deployment_lock_defeat_enabled: bool = false
@export var deployment_block_defeat_delay: float = 4.0

@export_group("Combat and capture")
@export_range(0, 0.2) var attack_interval_variance: float = 0.06
@export_range(0, 0.2) var move_speed_variance: float = 0.03
@export_range(100, 1500) var capture_depth: float = 600.0
@export_range(1, 1.5) var capture_speed_multiplier: float = 1.20
@export_range(0.3, 0.6) var exit_fade_duration: float = 0.45
