class_name Commando
extends Character

@warning_ignore("unused_signal")
signal used_ability(ability_name: String)

@export var knife_range: float = 1.5
@export var knife_damage: float = 100.0
@export var distract_range: float = 12.0
@export var shoot_range: float = 18.0
@export var shoot_damage: float = 55.0
@export var shoot_cooldown: float = 0.6

var has_knife: bool = true
var distract_count: int = 3

var _distract_projectile_scene: PackedScene = null
var _shoot_cd: float = 0.0

func _init() -> void:
    team = Team.PLAYER

func _process(delta: float) -> void:
    if _shoot_cd > 0.0:
        _shoot_cd -= delta

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

func try_shoot() -> bool:
    if current_state == State.DEAD or _shoot_cd > 0.0:
        return false
    var target := _nearest_enemy_los(shoot_range)
    if target == null:
        return false
    _shoot_cd = shoot_cooldown
    var aim := target.global_position
    aim.y = global_position.y
    look_at(aim, Vector3.UP)
    var muzzle := global_position + Vector3(0.0, 1.4, 0.0) - global_transform.basis.z * 0.6
    spawn_tracer(muzzle, target.global_position + Vector3(0.0, 1.2, 0.0))
    target.take_damage(shoot_damage)
    # focul de armă e zgomotos -> alertează gardienii din jur
    _spawn_noise_source(global_position, 18.0, 1.0)
    used_ability.emit("shoot")
    return true

func _nearest_enemy_los(rng: float) -> Enemy:
    var best: Enemy = null
    var best_d := rng
    for node in get_tree().get_nodes_in_group("enemies"):
        if not is_instance_valid(node) or not node is Enemy:
            continue
        var e: Enemy = node
        if e.current_state == State.DEAD:
            continue
        var d := global_position.distance_to(e.global_position)
        if d < best_d and _has_shot_los(e.global_position):
            best = e
            best_d = d
    return best

func _has_shot_los(target_pos: Vector3) -> bool:
    var space := get_world_3d().direct_space_state
    var from := global_position + Vector3(0.0, 1.4, 0.0)
    var to := target_pos + Vector3(0.0, 1.2, 0.0)
    var q := PhysicsRayQueryParameters3D.create(from, to)
    q.collision_mask = 1 | 4  # Ground + Obstacles blochează glonțul
    q.exclude = [self]
    return space.intersect_ray(q).is_empty()

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
