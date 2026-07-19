class_name AlarmTrigger
extends Area3D

@export var sensor_radius: float = 4.5
@export var alert_radius: float = 24.0
@export var cooldown: float = 5.0

var _cooldown_left := 0.0
var _beacon: MeshInstance3D = null
var _beacon_mat: StandardMaterial3D = null
var _light: OmniLight3D = null


func configure(new_sensor_radius: float, new_alert_radius: float, new_cooldown: float) -> void:
	sensor_radius = new_sensor_radius
	alert_radius = new_alert_radius
	cooldown = new_cooldown


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 << 1
	monitoring = true
	monitorable = false
	add_to_group("alarm_triggers")
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	_ensure_sensor_shape()
	_beacon = find_child("Beacon", true, false) as MeshInstance3D
	if _beacon != null:
		_beacon_mat = _beacon.material_override as StandardMaterial3D
	_light = find_child("AlarmLight", true, false) as OmniLight3D


func _ensure_sensor_shape() -> void:
	for child in get_children():
		if child is CollisionShape3D:
			var shape := (child as CollisionShape3D).shape
			if shape is SphereShape3D:
				(shape as SphereShape3D).radius = sensor_radius
			return
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = sensor_radius
	col.shape = sphere
	col.position.y = 1.0
	add_child(col)


func _process(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(0.0, _cooldown_left - delta)
	var active_pulse := _cooldown_left > cooldown - 1.4
	var pulse := (sin(Time.get_ticks_msec() * 0.018) * 0.5 + 0.5) if active_pulse else 0.25
	if _beacon_mat != null:
		_beacon_mat.emission_energy_multiplier = 0.8 + pulse * 2.4
	if _light != null:
		_light.light_energy = 0.22 + pulse * 0.9


func _on_body_entered(body: Node3D) -> void:
	if _cooldown_left > 0.0:
		return
	if not body is Commando:
		return
	var commando := body as Commando
	if commando.current_state == Character.State.DEAD:
		return
	_trigger_alarm()


func _trigger_alarm() -> void:
	_cooldown_left = cooldown
	MissionManager.register_enemy_alert()
	for node in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(node) or not node is Enemy:
			continue
		var enemy := node as Enemy
		if global_position.distance_to(enemy.global_position) <= alert_radius:
			enemy.hear_noise(global_position)
