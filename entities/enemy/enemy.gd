class_name Enemy
extends Character

enum AiState { PATROL, SEARCH, ALERT, ATTACK }

@export var patrol_points: Array[Vector3] = []
@export var vision_range: float = 12.0
@export var vision_angle: float = 120.0  # degrees
@export var reaction_time: float = 1.0
@export var alert_time: float = 2.0
@export var search_time: float = 6.0
@export var alarm_search_time: float = 11.0
@export var alarm_vision_bonus: float = 4.0
@export var alarm_boost_duration: float = 8.0
@export var patrol_wait: float = 2.0
@export var attack_range: float = 14.0
@export var attack_damage: float = 12.0
@export var attack_cooldown: float = 1.2
@export var show_debug_vision: bool = true

var ai_state: AiState = AiState.PATROL
var current_patrol_index: int = 0

var _vision_area: Area3D = null
var _vision_mesh: MeshInstance3D = null
var _alert_indicator: MeshInstance3D = null
var _state_label: Label3D = null

var _reaction_timer: float = 0.0
var _alert_timer: float = 0.0
var _search_timer: float = 0.0
var _patrol_wait_timer: float = 0.0
var _attack_cooldown_timer: float = 0.0
var _alarm_timer: float = 0.0

var _last_known_position: Vector3 = Vector3.ZERO
var _suspicion_level: float = 0.0
var _target_commando: Commando = null

func _init() -> void:
    team = Team.ENEMY

func _ready() -> void:
    super._ready()
    add_to_group("enemies")
    character_name = "Enemy Guard"
    _setup_vision()
    _setup_alert_indicator()

func _setup_vision() -> void:
    _vision_area = Area3D.new()
    _vision_area.name = "VisionArea"
    _vision_area.collision_layer = 0
    _vision_area.collision_mask = 2  # Units
    _vision_area.body_entered.connect(_on_body_entered_vision)
    _vision_area.body_exited.connect(_on_body_exited_vision)
    add_child(_vision_area)
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(vision_range, 3.0, vision_range * 2.0)
    shape.shape = box
    shape.position = Vector3(0, 1.5, -vision_range * 0.5)
    _vision_area.add_child(shape)
    # Visual cone
    _vision_mesh = MeshInstance3D.new()
    _vision_mesh.mesh = _create_cone_mesh(vision_range, vision_angle, 24)
    _vision_mesh.position = Vector3(0, 0.08, 0)
    _vision_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var mat := StandardMaterial3D.new()
    mat.albedo_color = _get_vision_color()
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.vertex_color_use_as_albedo = true
    mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
    # desenăm mereu deasupra terenului -> fără z-fighting cu relieful deluros (fără pâlpâire)
    mat.no_depth_test = true
    mat.render_priority = 1
    _vision_mesh.material_override = mat
    _vision_mesh.visible = show_debug_vision
    add_child(_vision_mesh)

func _create_cone_mesh(radius: float, angle_deg: float, segments: int) -> ArrayMesh:
    var mesh := ArrayMesh.new()
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    var verts := PackedVector3Array()
    var colors := PackedColorArray()
    var indices := PackedInt32Array()
    # Apex at the guard: brightest here, fades to transparent at the far rim and
    # toward the angular edges, so the cone reads as a soft light gradient.
    verts.append(Vector3.ZERO)
    colors.append(Color(1, 1, 1, 0.24))
    var half_rad := deg_to_rad(angle_deg * 0.5)
    for i in range(segments + 1):
        var t := float(i) / segments
        var a := -half_rad + t * half_rad * 2.0
        var x := sin(a) * radius
        var z := -cos(a) * radius
        verts.append(Vector3(x, 0.0, z))
        # Fade out at the tip (far) and soften the two side edges.
        var edge_fade: float = 1.0 - pow(abs(t * 2.0 - 1.0), 2.0)
        colors.append(Color(1, 1, 1, 0.02 + 0.06 * edge_fade))
    for i in range(1, segments + 1):
        indices.append(0)
        indices.append(i)
        indices.append(i + 1)
    arrays[Mesh.ARRAY_VERTEX] = verts
    arrays[Mesh.ARRAY_COLOR] = colors
    arrays[Mesh.ARRAY_INDEX] = indices
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return mesh

func _setup_alert_indicator() -> void:
    _alert_indicator = MeshInstance3D.new()
    var sphere := SphereMesh.new()
    sphere.radius = 0.2
    sphere.height = 0.4
    _alert_indicator.mesh = sphere
    _alert_indicator.position = Vector3(0, 2.2, 0)
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(1.0, 0.0, 0.0)
    mat.emission_enabled = true
    mat.emission = Color(1.0, 0.0, 0.0)
    _alert_indicator.material_override = mat
    _alert_indicator.visible = false
    add_child(_alert_indicator)
    _state_label = Label3D.new()
    _state_label.text = "PATROL"
    _state_label.position = Vector3(0, 2.7, 0)
    _state_label.font_size = 28
    _state_label.modulate = Color(0.9, 0.9, 0.9)
    _state_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    add_child(_state_label)

func _on_body_entered_vision(body: Node3D) -> void:
    if not body is Commando or body.current_state == State.DEAD:
        return

func _on_body_exited_vision(body: Node3D) -> void:
    if body == _target_commando:
        _target_commando = null

func _physics_process(delta: float) -> void:
    if current_state == State.DEAD:
        return
    _update_timers(delta)
    _scan_for_targets()
    _process_ai_state(delta)

func _update_timers(delta: float) -> void:
    _attack_cooldown_timer = max(0.0, _attack_cooldown_timer - delta)
    _alarm_timer = max(0.0, _alarm_timer - delta)
    if _alert_indicator:
        _alert_indicator.visible = ai_state != AiState.PATROL
        var indicator_mat := _alert_indicator.material_override as StandardMaterial3D
        if indicator_mat:
            indicator_mat.albedo_color = _get_ai_color()
            indicator_mat.emission = _get_ai_color()
    if _state_label:
        _state_label.text = AiState.keys()[ai_state]
        _state_label.modulate = _get_ai_color()
    if _vision_mesh:
        var vision_mat := _vision_mesh.material_override as StandardMaterial3D
        if vision_mat:
            vision_mat.albedo_color = _get_vision_color()

func _scan_for_targets() -> void:
    if ai_state == AiState.ATTACK:
        return
    _target_commando = null
    var best_candidate: Commando = null
    var best_suspicion := 0.0
    var effective_range := _current_vision_range()
    for node in get_tree().get_nodes_in_group("commandos"):
        if not is_instance_valid(node) or not node is Commando:
            continue
        var cmd: Commando = node
        if cmd.current_state == State.DEAD:
            continue
        var dist := global_position.distance_to(cmd.global_position)
        if dist > effective_range:
            continue
        var to_target := (cmd.global_position - global_position).normalized()
        var forward := -global_transform.basis.z.normalized()
        var angle := rad_to_deg(acos(clamp(forward.dot(to_target), -1.0, 1.0)))
        if angle > vision_angle * 0.5:
            continue
        if not _has_line_of_sight(cmd.global_position + Vector3.UP * 1.0):
            continue
        var suspicion := cmd.get_visibility_factor() * (1.0 - dist / effective_range)
        if suspicion > best_suspicion:
            best_suspicion = suspicion
            best_candidate = cmd
    if best_candidate != null:
        _target_commando = best_candidate
        _last_known_position = _target_commando.global_position
        if ai_state != AiState.ATTACK:
            if ai_state == AiState.PATROL:
                ai_state = AiState.ALERT
            _suspicion_level += best_suspicion * 0.5
            if _suspicion_level >= 1.0:
                ai_state = AiState.ATTACK
                _suspicion_level = 1.0
                MissionManager.register_enemy_alert()
    else:
        _suspicion_level = max(0.0, _suspicion_level - 0.02)

func _has_line_of_sight(target_pos: Vector3) -> bool:
    var world := get_world_3d().direct_space_state
    var query := PhysicsRayQueryParameters3D.new()
    query.from = global_position + Vector3.UP * 1.6
    query.to = target_pos
    query.collision_mask = 1 | 4  # Ground + Obstacles
    query.collide_with_bodies = true
    query.collide_with_areas = false
    var result := world.intersect_ray(query)
    if result.is_empty():
        return true
    var collider := result["collider"] as Node3D
    return collider == null or collider.is_in_group("commandos")

func _process_ai_state(delta: float) -> void:
    match ai_state:
        AiState.PATROL:
            _process_patrol(delta)
        AiState.SEARCH:
            _process_search(delta)
        AiState.ALERT:
            _process_alert(delta)
        AiState.ATTACK:
            _process_attack(delta)

func _process_patrol(delta: float) -> void:
    if patrol_points.is_empty() or current_state == State.DEAD:
        current_state = State.IDLE
        _animate_character_visual(delta, false)
        return
    var target := patrol_points[current_patrol_index]
    if _nav_agent.is_navigation_finished():
        _animate_character_visual(delta, false)
        _patrol_wait_timer += delta
        if _patrol_wait_timer >= patrol_wait:
            _patrol_wait_timer = 0.0
            current_patrol_index = (current_patrol_index + 1) % patrol_points.size()
            _nav_agent.set_target_position(patrol_points[current_patrol_index])
    else:
        _nav_agent.set_target_position(target)
        current_state = State.MOVING
        _move_along_path(delta)

func _process_search(delta: float) -> void:
    _search_timer += delta
    if _nav_agent.is_navigation_finished():
        _nav_agent.set_target_position(_last_known_position + Vector3(randf() - 0.5, 0, randf() - 0.5) * 4.0)
    _move_along_path(delta)
    if _search_timer >= _current_search_time():
        _search_timer = 0.0
        ai_state = AiState.PATROL

func _process_alert(delta: float) -> void:
    _alert_timer += delta
    if _target_commando != null and is_instance_valid(_target_commando):
        var target_pos := _target_commando.global_position
        target_pos.y = global_position.y
        look_at(target_pos, Vector3.UP)
    if _alert_timer >= alert_time:
        _alert_timer = 0.0
        ai_state = AiState.ATTACK
        MissionManager.register_enemy_alert()

func _process_attack(delta: float) -> void:
    if _target_commando == null or not is_instance_valid(_target_commando) or _target_commando.current_state == State.DEAD:
        ai_state = AiState.SEARCH
        return
    var dist := global_position.distance_to(_target_commando.global_position)
    var target_pos := _target_commando.global_position
    target_pos.y = global_position.y
    look_at(target_pos, Vector3.UP)
    if dist > attack_range:
        _nav_agent.set_target_position(_target_commando.global_position)
        _move_along_path(delta)
    else:
        current_state = State.IDLE
        _animate_character_visual(delta, false)
        if _attack_cooldown_timer <= 0.0:
            var muzzle := global_position + Vector3(0.0, 1.4, 0.0) - global_transform.basis.z * 0.6
            spawn_tracer(muzzle, _target_commando.global_position + Vector3(0.0, 1.2, 0.0), Color(1.0, 0.3, 0.2))
            _target_commando.take_damage(attack_damage)
            _attack_cooldown_timer = attack_cooldown

func _move_along_path(delta: float) -> void:
    if _nav_agent.is_navigation_finished():
        current_state = State.IDLE
        return
    var next_pos := _nav_agent.get_next_path_position()
    global_position.y = lerpf(global_position.y, next_pos.y, clamp(delta * 8.0, 0.0, 1.0))
    var direction := (next_pos - global_position).normalized()
    direction.y = 0.0
    if direction.length_squared() > 0.01:
        look_at(global_position + direction, Vector3.UP)
    velocity = direction * get_current_speed()
    move_and_slide()
    _animate_character_visual(delta, true)

func hear_noise(noise_pos: Vector3) -> void:
    if ai_state == AiState.ATTACK or current_state == State.DEAD:
        return
    _last_known_position = noise_pos
    if ai_state == AiState.PATROL:
        ai_state = AiState.SEARCH

func hear_alarm(alarm_pos: Vector3) -> void:
    if ai_state == AiState.ATTACK or current_state == State.DEAD:
        return
    _last_known_position = alarm_pos
    _search_timer = 0.0
    _alarm_timer = maxf(_alarm_timer, alarm_boost_duration)
    if ai_state == AiState.PATROL or ai_state == AiState.SEARCH:
        ai_state = AiState.SEARCH

func _current_vision_range() -> float:
    if _alarm_timer > 0.0:
        return vision_range + alarm_vision_bonus
    return vision_range

func _current_search_time() -> float:
    if _alarm_timer > 0.0:
        return alarm_search_time
    return search_time

func set_patrol_points(points: Array) -> void:
    patrol_points = points
    if not points.is_empty() and ai_state == AiState.PATROL:
        _nav_agent.set_target_position(points[0])

func show_vision_debug(show: bool) -> void:
    if _vision_mesh:
        _vision_mesh.visible = show

func _get_ai_color() -> Color:
    match ai_state:
        AiState.SEARCH:
            return Color(1.0, 0.85, 0.1)
        AiState.ALERT:
            return Color(1.0, 0.45, 0.05)
        AiState.ATTACK:
            return Color(1.0, 0.05, 0.05)
        _:
            return Color(0.85, 0.85, 0.85)

func _get_vision_color() -> Color:
    # Additive tint for the vision cone; escalates with alert state (alpha scales intensity).
    match ai_state:
        AiState.SEARCH:
            return Color(1.0, 0.78, 0.14, 0.34)
        AiState.ALERT:
            return Color(1.0, 0.5, 0.08, 0.38)
        AiState.ATTACK:
            return Color(1.0, 0.16, 0.1, 0.42)
        _:
            return Color(0.86, 0.72, 0.32, 0.26)

func to_dict() -> Dictionary:
    var data := super.to_dict()
    data["ai_state"] = AiState.keys()[ai_state]
    return data
