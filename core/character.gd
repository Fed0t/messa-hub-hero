class_name Character
extends CharacterBody3D

enum Team { PLAYER, ENEMY, NEUTRAL }
enum State { IDLE, MOVING, CROUCH, PRONE, DEAD }

@export var character_name: String = "Unit"
@export var team: Team = Team.PLAYER
@export var max_health: float = 100.0
@export var walk_speed: float = 3.5
@export var crouch_speed: float = 1.5
@export var prone_speed: float = 0.7

var health: float = 100.0
var current_state: State = State.IDLE
var is_selected: bool = false

var _nav_agent: NavigationAgent3D = null
var _collision_shape: CollisionShape3D = null
var _selection_ring: MeshInstance3D = null
var _selection_material: StandardMaterial3D = null
var _body_mesh: MeshInstance3D = null
var _head_mesh: MeshInstance3D = null
var _uniform_material: StandardMaterial3D = null
var _skin_material: StandardMaterial3D = null
var _gear_material: StandardMaterial3D = null
var _model_root: Node3D = null
var _animation_player: AnimationPlayer = null
var _active_animation := ""
var _model_base_position := Vector3.ZERO
var _model_base_rotation := Vector3.ZERO
var _model_base_scale := Vector3.ONE
var _left_arm_pivot: Node3D = null
var _right_arm_pivot: Node3D = null
var _left_leg_pivot: Node3D = null
var _right_leg_pivot: Node3D = null
var _weapon_pivot: Node3D = null
var _walk_phase := 0.0

var _move_target: Vector3 = Vector3.ZERO

func _ready() -> void:
    health = max_health
    add_to_group("characters")
    _setup_collision()
    _setup_navigation()
    _setup_visuals()

func _setup_collision() -> void:
    collision_layer = 0
    collision_mask = 0
    match team:
        Team.PLAYER:
            collision_layer = 2  # Units
            collision_mask = 1 | 3  # Ground + Obstacles
        Team.ENEMY:
            collision_layer = 2  # Units
            collision_mask = 1 | 3
        _:
            collision_layer = 2
            collision_mask = 1 | 3
    _collision_shape = CollisionShape3D.new()
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.38
    capsule.height = 1.8
    _collision_shape.shape = capsule
    _collision_shape.position.y = 0.9
    add_child(_collision_shape)

func _setup_navigation() -> void:
    _nav_agent = NavigationAgent3D.new()
    _nav_agent.path_desired_distance = 0.5
    _nav_agent.target_desired_distance = 0.5
    _nav_agent.path_height_offset = 0.0
    _nav_agent.radius = 0.4
    _nav_agent.max_speed = walk_speed
    _nav_agent.avoidance_enabled = true
    _nav_agent.navigation_layers = 1 | 3
    add_child(_nav_agent)

func _setup_visuals() -> void:
    _uniform_material = StandardMaterial3D.new()
    _skin_material = StandardMaterial3D.new()
    _gear_material = StandardMaterial3D.new()
    _skin_material.albedo_color = Color(0.78, 0.62, 0.46)
    _skin_material.roughness = 0.65
    _gear_material.albedo_color = Color(0.12, 0.11, 0.08)
    _gear_material.roughness = 0.75
    if not _try_add_resource_character_model():
        # Body
        _body_mesh = MeshInstance3D.new()
        _body_mesh.mesh = CapsuleMesh.new()
        _body_mesh.mesh.height = 1.7
        _body_mesh.mesh.radius = 0.3
        _body_mesh.position.y = 0.85
        add_child(_body_mesh)
        # Head
        _head_mesh = MeshInstance3D.new()
        _head_mesh.mesh = SphereMesh.new()
        _head_mesh.mesh.radius = 0.22
        _head_mesh.mesh.height = 0.44
        _head_mesh.position.y = 1.75
        _head_mesh.material_override = _skin_material
        add_child(_head_mesh)
        _add_soldier_gear()
    # Selection ring
    _selection_ring = MeshInstance3D.new()
    var torus := TorusMesh.new()
    torus.inner_radius = 0.48
    torus.outer_radius = 0.55
    _selection_ring.mesh = torus
    _selection_ring.position.y = 0.05
    _selection_ring.visible = false
    _selection_material = StandardMaterial3D.new()
    _selection_material.albedo_color = Color(0.15, 0.85, 1.0)
    _selection_material.emission_enabled = true
    _selection_material.emission = Color(0.12, 0.65, 0.95)
    _selection_material.emission_energy_multiplier = 0.55
    _selection_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    _selection_ring.material_override = _selection_material
    add_child(_selection_ring)
    _update_color()

func _try_add_resource_character_model() -> bool:
    # doar comandourile primesc modelul 3D de soldat; inamicii rămân procedurali (capsulă)
    if team != Team.PLAYER:
        return false
    var model_paths := [
        "res://assets/models/soldier/base_basic_pbr.glb",
    ]
    var packed: PackedScene = null
    for model_path in model_paths:
        if not FileAccess.file_exists(model_path) or not ResourceLoader.exists(model_path, "PackedScene"):
            continue
        packed = load(model_path) as PackedScene
        if packed != null:
            break
    if packed == null:
        return false
    var imported_model := packed.instantiate() as Node3D
    if imported_model == null:
        return false
    _model_root = Node3D.new()
    _model_root.name = "SoldierModel"
    _model_root.scale = Vector3(0.88, 0.88, 0.88)
    _model_root.position = Vector3(0, 0.0, 0)
    _model_root.rotation_degrees.y = 180
    add_child(_model_root)
    imported_model.name = "ImportedCharacterBody"
    imported_model.position = Vector3.ZERO
    imported_model.rotation_degrees = Vector3.ZERO
    _model_root.add_child(imported_model)
    _model_base_position = _model_root.position
    _model_base_rotation = _model_root.rotation_degrees
    _model_base_scale = _model_root.scale
    _animation_player = _find_animation_player(_model_root)
    return true

func _add_procedural_combat_rig() -> void:
    var suit_color := Color(0.08, 0.16, 0.10) if team == Team.PLAYER else Color(0.20, 0.13, 0.10)
    var team_color := Color(0.05, 0.82, 1.0) if team == Team.PLAYER else Color(1.0, 0.17, 0.10)
    var dark_color := Color(0.025, 0.025, 0.022)
    _left_arm_pivot = _create_limb_pivot("LeftArmSwing", Vector3(-0.36, 1.28, -0.02), 0.55, 0.055, suit_color)
    _right_arm_pivot = _create_limb_pivot("RightArmSwing", Vector3(0.36, 1.28, -0.02), 0.55, 0.055, suit_color)
    _left_leg_pivot = _create_limb_pivot("LeftLegSwing", Vector3(-0.18, 0.78, 0.02), 0.55, 0.065, dark_color)
    _right_leg_pivot = _create_limb_pivot("RightLegSwing", Vector3(0.18, 0.78, 0.02), 0.55, 0.065, dark_color)
    _weapon_pivot = Node3D.new()
    _weapon_pivot.name = "WeaponSway"
    _weapon_pivot.position = Vector3(0.42, 1.15, -0.18)
    _model_root.add_child(_weapon_pivot)
    var rifle := MeshInstance3D.new()
    var rifle_mesh := BoxMesh.new()
    rifle_mesh.size = Vector3(0.08, 0.08, 0.78)
    rifle.mesh = rifle_mesh
    rifle.position = Vector3(0, -0.02, -0.18)
    rifle.rotation_degrees.x = -15
    rifle.material_override = _make_character_material(dark_color, Color(0.04, 0.04, 0.035), 0.0)
    _weapon_pivot.add_child(rifle)
    _create_rig_badge("TeamHelmetMark", Vector3(0, 1.86, -0.08), Vector3(0.34, 0.045, 0.08), team_color, 0.7)
    _create_rig_badge("TeamChestMark", Vector3(0, 1.32, -0.29), Vector3(0.38, 0.08, 0.035), team_color, 0.45)

func _create_limb_pivot(limb_name: String, local_pos: Vector3, length: float, radius: float, color: Color) -> Node3D:
    var pivot := Node3D.new()
    pivot.name = limb_name
    pivot.position = local_pos
    _model_root.add_child(pivot)
    var limb := MeshInstance3D.new()
    var limb_mesh := CapsuleMesh.new()
    limb_mesh.radius = radius
    limb_mesh.height = length
    limb.mesh = limb_mesh
    limb.position.y = -length * 0.5
    limb.material_override = _make_character_material(color)
    pivot.add_child(limb)
    return pivot

func _create_rig_badge(badge_name: String, local_pos: Vector3, size: Vector3, color: Color, emission_energy: float) -> void:
    var badge := MeshInstance3D.new()
    badge.name = badge_name
    var badge_mesh := BoxMesh.new()
    badge_mesh.size = size
    badge.mesh = badge_mesh
    badge.position = local_pos
    badge.material_override = _make_character_material(color, color, emission_energy)
    _model_root.add_child(badge)

func _make_character_material(albedo: Color, emission: Color = Color.BLACK, emission_energy: float = 0.0) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = albedo
    mat.roughness = 0.72
    if emission_energy > 0.0:
        mat.emission_enabled = true
        mat.emission = emission
        mat.emission_energy_multiplier = emission_energy
    return mat

func _find_animation_player(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer:
        return node
    for child in node.get_children():
        var found := _find_animation_player(child)
        if found != null:
            return found
    return null

func _play_first_available_animation(keywords: Array[String]) -> void:
    if _animation_player == null:
        return
    for animation_name in _animation_player.get_animation_list():
        var lowered := animation_name.to_lower()
        for keyword in keywords:
            if lowered.contains(keyword):
                var animation := _animation_player.get_animation(animation_name)
                if animation != null:
                    animation.loop_mode = Animation.LOOP_LINEAR
                if _active_animation != animation_name or not _animation_player.is_playing():
                    _active_animation = animation_name
                    _animation_player.play(animation_name)
                return

func _animate_character_visual(delta: float, moving: bool) -> void:
    if _model_root == null:
        return
    _model_root.position = _model_base_position
    _model_root.rotation_degrees = _model_base_rotation

func _animate_procedural_locomotion(moving: bool) -> void:
    if _left_arm_pivot == null:
        return
    if moving:
        var swing := sin(_walk_phase) * 32.0
        var counter_swing := -swing
        _left_arm_pivot.rotation_degrees.x = swing
        _right_arm_pivot.rotation_degrees.x = counter_swing
        _left_leg_pivot.rotation_degrees.x = counter_swing * 0.8
        _right_leg_pivot.rotation_degrees.x = swing * 0.8
        _weapon_pivot.rotation_degrees = Vector3(-10.0 + abs(sin(_walk_phase)) * 5.0, sin(_walk_phase) * 5.0, cos(_walk_phase) * 3.0)
    else:
        var idle := sin(_walk_phase) * 2.0
        _left_arm_pivot.rotation_degrees.x = -4.0 + idle
        _right_arm_pivot.rotation_degrees.x = 4.0 - idle
        _left_leg_pivot.rotation_degrees.x = 0.0
        _right_leg_pivot.rotation_degrees.x = 0.0
        _weapon_pivot.rotation_degrees = Vector3(-10.0 + idle, 0.0, 0.0)

func _update_color() -> void:
    match team:
        Team.PLAYER:
            _uniform_material.albedo_color = Color(0.11, 0.28, 0.15)
        Team.ENEMY:
            _uniform_material.albedo_color = Color(0.38, 0.34, 0.25)
        _:
            _uniform_material.albedo_color = Color(0.55, 0.55, 0.48)
    _uniform_material.roughness = 0.7
    if _body_mesh:
        _body_mesh.material_override = _uniform_material

func _add_soldier_gear() -> void:
    var helmet := MeshInstance3D.new()
    var helmet_mesh := SphereMesh.new()
    helmet_mesh.radius = 0.27
    helmet_mesh.height = 0.28
    helmet.mesh = helmet_mesh
    helmet.position.y = 1.92
    helmet.scale = Vector3(1.1, 0.45, 1.05)
    helmet.material_override = _uniform_material
    add_child(helmet)

    var backpack := MeshInstance3D.new()
    var pack_mesh := BoxMesh.new()
    pack_mesh.size = Vector3(0.42, 0.58, 0.18)
    backpack.mesh = pack_mesh
    backpack.position = Vector3(0, 1.05, 0.34)
    backpack.material_override = _gear_material
    add_child(backpack)

    var belt := MeshInstance3D.new()
    var belt_mesh := BoxMesh.new()
    belt_mesh.size = Vector3(0.68, 0.12, 0.18)
    belt.mesh = belt_mesh
    belt.position = Vector3(0, 0.95, -0.18)
    belt.material_override = _gear_material
    add_child(belt)

    var rifle := MeshInstance3D.new()
    var rifle_mesh := BoxMesh.new()
    rifle_mesh.size = Vector3(0.09, 0.09, 0.9)
    rifle.mesh = rifle_mesh
    rifle.position = Vector3(0.42, 1.05, -0.12)
    rifle.rotation_degrees.x = -18
    rifle.material_override = _gear_material
    add_child(rifle)

    if team == Team.ENEMY:
        var armband := MeshInstance3D.new()
        var armband_mesh := BoxMesh.new()
        armband_mesh.size = Vector3(0.7, 0.14, 0.08)
        armband.mesh = armband_mesh
        armband.position = Vector3(0, 1.35, -0.32)
        var enemy_mark := StandardMaterial3D.new()
        enemy_mark.albedo_color = Color(0.7, 0.08, 0.06)
        enemy_mark.emission_enabled = true
        enemy_mark.emission = Color(0.5, 0.02, 0.01)
        enemy_mark.emission_energy_multiplier = 0.35
        armband.material_override = enemy_mark
        add_child(armband)

func set_selected(selected: bool) -> void:
    is_selected = selected
    if _selection_ring:
        _selection_ring.visible = selected

func move_to(target: Vector3) -> void:
    if _nav_agent:
        _nav_agent.set_target_position(target)
        _move_target = target
        current_state = State.MOVING

func set_state(state: State) -> void:
    if current_state == State.DEAD:
        return
    current_state = state

func toggle_crouch() -> void:
    if current_state == State.DEAD:
        return
    if current_state == State.CROUCH:
        set_state(State.IDLE)
    else:
        set_state(State.CROUCH)
    _update_stance_visuals()

func toggle_prone() -> void:
    if current_state == State.DEAD:
        return
    if current_state == State.PRONE:
        set_state(State.IDLE)
    else:
        set_state(State.PRONE)
    _update_stance_visuals()

func _update_stance_visuals() -> void:
    if _body_mesh == null or _head_mesh == null:
        if _model_root != null:
            match current_state:
                State.CROUCH:
                    _model_root.scale = Vector3(_model_base_scale.x * 1.04, _model_base_scale.y * 0.72, _model_base_scale.z * 1.04)
                State.PRONE:
                    _model_root.scale = Vector3(_model_base_scale.x * 1.12, _model_base_scale.y * 0.34, _model_base_scale.z * 1.25)
                _:
                    _model_root.scale = _model_base_scale
        return
    match current_state:
        State.CROUCH:
            _body_mesh.mesh.height = 1.0
            _body_mesh.position.y = 0.5
            _head_mesh.position.y = 1.05
        State.PRONE:
            _body_mesh.mesh.height = 0.4
            _body_mesh.position.y = 0.2
            _head_mesh.position.y = 0.45
        _:
            _body_mesh.mesh.height = 1.7
            _body_mesh.position.y = 0.85
            _head_mesh.position.y = 1.75

func get_current_speed() -> float:
    match current_state:
        State.CROUCH:
            return crouch_speed
        State.PRONE:
            return prone_speed
        State.MOVING:
            return walk_speed
        _:
            return walk_speed

func take_damage(amount: float) -> void:
    if current_state == State.DEAD:
        return
    health -= amount
    if health <= 0.0:
        health = 0.0
        die()

func die() -> void:
    current_state = State.DEAD
    set_selected(false)
    if _selection_ring:
        _selection_ring.visible = false
    # Ragdoll-like fall
    rotation.x = PI * 0.45
    if _body_mesh:
        _body_mesh.position.y = 0.2
    if _head_mesh:
        _head_mesh.position.y = 0.45
    add_to_group("corpses")

func _physics_process(delta: float) -> void:
    if current_state == State.DEAD or _nav_agent == null:
        return
    if team == Team.PLAYER and current_state == State.MOVING:
        _move_directly_to_target(delta)
        return
    if _nav_agent.is_navigation_finished():
        if current_state == State.MOVING:
            current_state = State.IDLE
        _animate_character_visual(delta, false)
        return
    var next_pos := _nav_agent.get_next_path_position()
    var direction := (next_pos - global_position).normalized()
    direction.y = 0.0
    if direction.length_squared() > 0.01:
        look_at(global_position + direction, Vector3.UP)
    velocity = direction * get_current_speed()
    move_and_slide()
    _animate_character_visual(delta, true)

func _move_directly_to_target(delta: float) -> void:
    var direction := _move_target - global_position
    direction.y = 0.0
    if direction.length() <= 0.35:
        velocity = Vector3.ZERO
        current_state = State.IDLE
        _animate_character_visual(delta, false)
        return
    direction = direction.normalized()
    look_at(global_position + direction, Vector3.UP)
    velocity = direction * get_current_speed()
    move_and_slide()
    _animate_character_visual(delta, true)

func get_2d_screen_position(camera: Camera3D) -> Vector2:
    return camera.unproject_position(global_position + Vector3.UP * 1.8)

func get_noise_radius() -> float:
    match current_state:
        State.PRONE:
            return 1.0
        State.CROUCH:
            return 3.0
        State.MOVING:
            return 6.0
        _:
            return 0.0

func get_visibility_factor() -> float:
    # Base visibility factor; hiding spots can modify this externally
    match current_state:
        State.PRONE:
            return 0.3
        State.CROUCH:
            return 0.6
        _:
            return 1.0

func is_spotted() -> bool:
    return false

func is_target_reachable() -> bool:
    if _nav_agent == null:
        return false
    return _nav_agent.is_target_reachable()

func get_navigation_map() -> RID:
    if _nav_agent == null:
        return RID()
    return _nav_agent.get_navigation_map()

func to_dict() -> Dictionary:
    return {
        "name": character_name,
        "health": health,
        "max_health": max_health,
        "state": State.keys()[current_state]
    }
