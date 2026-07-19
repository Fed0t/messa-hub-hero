class_name IsometricCamera
extends Node3D

@export var min_distance: float = 5.0
@export var max_distance: float = 46.0
@export var default_distance: float = 24.0
@export var zoom_speed: float = 2.0
@export var pan_speed: float = 18.0
@export var edge_pan_margin: int = 28
@export var edge_pan_enabled: bool = true
@export var rotation_snap: float = 90.0
@export var level_bounds: Rect2 = Rect2(Vector2(-30, -30), Vector2(60, 60))
@export var follow_enabled: bool = true
@export var follow_lerp_speed: float = 7.5
@export var manual_offset_limit: float = 14.0
# Camera tilts down harder when zoomed out (tactical top-down) and eases toward a
# more horizontal cinematic angle when zoomed in, so close-ups read as characters.
@export var far_pitch: float = -60.0
@export var near_pitch: float = -34.0

var _yaw: float = -45.0
var _pitch: float = -60.0
var _distance: float = default_distance
var _camera: Camera3D = null
var _follow_target: Node3D = null
var _manual_offset := Vector3.ZERO

func _ready() -> void:
    _camera = Camera3D.new()
    _camera.name = "Camera3D"
    _camera.fov = 42.0
    _camera.near = 0.05
    _camera.far = 220.0
    add_child(_camera)
    _update_transform()

func _update_transform() -> void:
    var t: float = clamp(inverse_lerp(min_distance, max_distance, _distance), 0.0, 1.0)
    _pitch = lerp(near_pitch, far_pitch, t)
    rotation_degrees = Vector3(_pitch, _yaw, 0.0)
    if _camera:
        _camera.position = Vector3(0, 0, _distance)
        _camera.rotation_degrees = Vector3.ZERO

func _input(event: InputEvent) -> void:
    if GameManager.current_state != GameManager.GameState.PLAYING:
        return
    if event is InputEventMouseButton and event.pressed:
        if event.button_index == MOUSE_BUTTON_WHEEL_UP:
            _distance = clamp(_distance - zoom_speed, min_distance, max_distance)
            _update_transform()
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            _distance = clamp(_distance + zoom_speed, min_distance, max_distance)
            _update_transform()
    if event.is_action_pressed("rotate_left"):
        _yaw -= rotation_snap
        _update_transform()
    if event.is_action_pressed("rotate_right"):
        _yaw += rotation_snap
        _update_transform()

func _process(delta: float) -> void:
    if GameManager.current_state != GameManager.GameState.PLAYING:
        return
    var pan_dir := Vector3.ZERO
    if edge_pan_enabled:
        var edge := InputManager.is_mouse_at_screen_edge(edge_pan_margin)
        if edge.x < 0:
            pan_dir.x -= 1.0
        elif edge.x > 0:
            pan_dir.x += 1.0
        if edge.y < 0:
            pan_dir.z -= 1.0
        elif edge.y > 0:
            pan_dir.z += 1.0
    # Keyboard pan
    if Input.is_action_pressed("ui_left"):
        pan_dir.x -= 1.0
    if Input.is_action_pressed("ui_right"):
        pan_dir.x += 1.0
    if Input.is_action_pressed("ui_up"):
        pan_dir.z -= 1.0
    if Input.is_action_pressed("ui_down"):
        pan_dir.z += 1.0
    if pan_dir.length_squared() > 0.01:
        pan_dir = pan_dir.normalized()
        # Transform pan direction to align with camera yaw
        var basis := Basis(Vector3.UP, deg_to_rad(_yaw))
        var world_pan := basis * pan_dir
        if _follow_target != null and follow_enabled:
            _manual_offset += world_pan * pan_speed * delta
            _manual_offset.x = clamp(_manual_offset.x, -manual_offset_limit, manual_offset_limit)
            _manual_offset.z = clamp(_manual_offset.z, -manual_offset_limit, manual_offset_limit)
        else:
            position += world_pan * pan_speed * delta
            _clamp_to_level_bounds()
    _update_follow(delta)

func get_camera() -> Camera3D:
    return _camera

func set_follow_target(target: Node3D) -> void:
    _follow_target = target
    _manual_offset = Vector3.ZERO
    if _follow_target != null and is_instance_valid(_follow_target):
        center_on(_follow_target.global_position)

func center_on(position_3d: Vector3) -> void:
    position = position_3d
    _clamp_to_level_bounds()

func clear_follow_target() -> void:
    _follow_target = null
    _manual_offset = Vector3.ZERO

func _update_follow(delta: float) -> void:
    if not follow_enabled or _follow_target == null or not is_instance_valid(_follow_target):
        return
    var target_pos := _follow_target.global_position + _manual_offset
    target_pos.y = 0.0
    position = position.lerp(target_pos, clamp(delta * follow_lerp_speed, 0.0, 1.0))
    _clamp_to_level_bounds()

func set_level_size(size: float) -> void:
    var half := size * 0.5
    level_bounds = Rect2(Vector2(-half, -half), Vector2(size, size))
    _clamp_to_level_bounds()

func _clamp_to_level_bounds() -> void:
    position.x = clamp(position.x, level_bounds.position.x, level_bounds.position.x + level_bounds.size.x)
    position.z = clamp(position.z, level_bounds.position.y, level_bounds.position.y + level_bounds.size.y)
