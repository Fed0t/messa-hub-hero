class_name NoiseSource
extends Node3D

signal expired(source: NoiseSource)

@export var radius: float = 5.0
@export var duration: float = 2.0

var _timer: float = 0.0
var _visual: MeshInstance3D = null
var _ring: MeshInstance3D = null

func _ready() -> void:
    add_to_group("noise_sources")
    _visual = MeshInstance3D.new()
    var sphere := SphereMesh.new()
    sphere.radius = radius
    sphere.height = radius * 2.0
    _visual.mesh = sphere
    _visual.transparency = 0.7
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(1.0, 0.9, 0.1, 0.2)
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    mat.emission_enabled = true
    mat.emission = Color(1.0, 0.85, 0.1)
    mat.emission_energy_multiplier = 0.6
    _visual.material_override = mat
    add_child(_visual)
    _ring = MeshInstance3D.new()
    var torus := TorusMesh.new()
    torus.inner_radius = radius * 0.95
    torus.outer_radius = radius
    _ring.mesh = torus
    _ring.position.y = 0.08
    var ring_mat := StandardMaterial3D.new()
    ring_mat.albedo_color = Color(1.0, 0.95, 0.15, 0.75)
    ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    ring_mat.emission_enabled = true
    ring_mat.emission = Color(1.0, 0.9, 0.2)
    ring_mat.emission_energy_multiplier = 1.2
    _ring.material_override = ring_mat
    add_child(_ring)
    call_deferred("_notify_enemies")

func _notify_enemies() -> void:
    for node in get_tree().get_nodes_in_group("enemies"):
        if node != null and node.has_method("hear_noise"):
            var enemy := node as Enemy
            if enemy != null and global_position.distance_to(enemy.global_position) <= radius:
                enemy.hear_noise(global_position)

func _process(delta: float) -> void:
    _timer += delta
    var pulse := 1.0 + sin(_timer * 10.0) * 0.04
    if _ring:
        _ring.scale = Vector3(pulse, 1.0, pulse)
    if _timer >= duration:
        expired.emit(self)
        queue_free()

func is_in_range(position: Vector3) -> bool:
    return global_position.distance_to(position) <= radius
