class_name RotatingSpotlight
extends Node3D

@export var sweep_degrees: float = 68.0
@export var sweep_speed: float = 0.55
@export var alarm_speed_multiplier: float = 2.25

var _base_yaw := 0.0
var _alarm_timer := 0.0


func _ready() -> void:
	_base_yaw = rotation.y
	add_to_group("rotating_spotlights")


func _process(delta: float) -> void:
	if _alarm_timer > 0.0:
		_alarm_timer = maxf(0.0, _alarm_timer - delta)
	var speed := sweep_speed
	if _alarm_timer > 0.0:
		speed *= alarm_speed_multiplier
	var phase := Time.get_ticks_msec() * 0.001 * speed
	rotation.y = _base_yaw + sin(phase) * deg_to_rad(sweep_degrees)


func start_alarm_sweep(duration: float = 7.0) -> void:
	_alarm_timer = maxf(_alarm_timer, duration)
