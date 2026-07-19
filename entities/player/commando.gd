class_name Commando
extends Character

@warning_ignore("unused_signal")
signal used_ability(ability_name: String)

@export var knife_range: float = 1.5
@export var knife_damage: float = 100.0
@export var distract_range: float = 12.0

var has_knife: bool = true
var distract_count: int = 3

var _distract_projectile_scene: PackedScene = null

func _init() -> void:
    team = Team.PLAYER

func _ready() -> void:
    super._ready()
    add_to_group("commandos")
    character_name = "Commando"

func try_knife() -> bool:
    if not has_knife or current_state == State.DEAD:
        return false
    var nearest: Enemy = null
    var nearest_dist := knife_range
    for node in get_tree().get_nodes_in_group("enemies"):
        if not is_instance_valid(node) or not node is Enemy:
            continue
        var enemy: Enemy = node
        if enemy.current_state == State.DEAD:
            continue
        var dist := global_position.distance_to(enemy.global_position)
        if dist < nearest_dist:
            nearest = enemy
            nearest_dist = dist
    if nearest != null:
        nearest.take_damage(knife_damage)
        used_ability.emit("knife")
        return true
    return false

func try_distract(target_position: Vector3) -> bool:
    if distract_count <= 0 or current_state == State.DEAD:
        return false
    distract_count -= 1
    _spawn_noise_source(target_position, 8.0, 3.0)
    used_ability.emit("distract")
    return true

func _spawn_noise_source(position: Vector3, radius: float, duration: float) -> void:
    var noise := NoiseSource.new()
    noise.global_position = position
    noise.radius = radius
    noise.duration = duration
    get_tree().current_scene.add_child(noise)

func get_inventory() -> Dictionary:
    return {
        "knife": has_knife,
        "distract": distract_count
    }

func to_dict() -> Dictionary:
    var data := super.to_dict()
    data["knife"] = has_knife
    data["distract"] = distract_count
    return data
