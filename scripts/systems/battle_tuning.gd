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

@export_group("Squad orders")
@export var territory_cell_size: float = 160.0
@export var defense_area_margin: float = 1.20
@export var territory_update_interval: float = 0.25
@export var breakthrough_contribution_window: float = 12.0
@export var cohesion_leash: float = 800.0
@export var rout_speed_multiplier: float = 1.5
@export var rout_damage_multiplier: float = 1.25
@export var breakthrough_heal_fraction: float = 0.10
@export var breakthrough_damage_multiplier: float = 1.15
@export var breakthrough_duration: float = 8.0
@export var breakthrough_duration_cap: float = 2.0
@export_enum("RANDOM", "LINE", "TRIANGLE") var enemy_doctrine: String = "RANDOM"
@export var enemy_defense_depth: float = 2000.0
@export var enemy_apex_extra_depth: float = 650.0
@export_range(160, 600) var defense_spacing: float = 320.0
@export_range(70, 600) var minimum_defense_radius: float = 140.0
@export_range(600, 3000) var maximum_defense_radius: float = 1800.0
@export_range(100, 1800) var no_hold_depth: float = 900.0
@export_group("Command planning")
@export_range(0.1, 1) var planning_time_scale: float = 0.4
@export_range(0.05, 1) var planning_transition_in_duration: float = 0.25
@export_range(0.05, 1) var planning_transition_out_duration: float = 0.25
@export_range(0, 1) var planning_desaturation_amount: float = 0.85
@export_range(0.5, 1) var planning_brightness_adjustment: float = 0.88

@export_group("Combat telemetry")
@export var telemetry_enabled: bool = true
@export_range(0.1, 5) var telemetry_sample_interval: float = 1.0
@export var stuck_distance_threshold: float = 10.0
@export var stuck_time_threshold: float = 2.0

@export_group("Route diagnostics and corridors")
@export var route_lane_spacing: float = 320.0
@export var progress_efficiency_threshold: float = 0.35
@export var friction_time_threshold: float = 2.0
@export var friction_minimum_motion: float = 10.0
