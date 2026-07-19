extends Node

# Mouse actions configured via project.godot
# Keyboard actions: rotate_left, rotate_right, ability_knife, ability_distract,
# toggle_crouch, toggle_prone, select, add_select

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    _ensure_input_map()

func _ensure_input_map() -> void:
    _add_mouse_action("move_to", MOUSE_BUTTON_RIGHT)
    _add_mouse_action("select", MOUSE_BUTTON_LEFT)
    _add_key_action("ui_left", KEY_A)
    _add_key_action("ui_right", KEY_D)
    _add_key_action("ui_up", KEY_W)
    _add_key_action("ui_down", KEY_S)
    _add_key_action("add_select", KEY_SHIFT)
    _add_key_action("rotate_left", KEY_Q)
    _add_key_action("rotate_right", KEY_E)
    _add_key_action("ability_knife", KEY_1)
    _add_key_action("ability_distract", KEY_2)
    _add_key_action("toggle_crouch", KEY_C)
    _add_key_action("toggle_prone", KEY_P)
    _add_key_action("pause", KEY_ESCAPE)

func _add_mouse_action(action_name: String, button: int) -> void:
    if not InputMap.has_action(action_name):
        InputMap.add_action(action_name)
    var event := InputEventMouseButton.new()
    event.button_index = button
    event.pressed = true
    InputMap.action_add_event(action_name, event)

func _add_key_action(action_name: String, keycode: int) -> void:
    if not InputMap.has_action(action_name):
        InputMap.add_action(action_name)
    var event := InputEventKey.new()
    event.physical_keycode = keycode
    event.pressed = true
    InputMap.action_add_event(action_name, event)

func get_terrain_mouse_position(camera: Camera3D, collision_mask: int = 1) -> Vector3:
    var mouse_pos := get_viewport().get_mouse_position()
    var ray_origin := camera.project_ray_origin(mouse_pos)
    var ray_dir := camera.project_ray_normal(mouse_pos)
    var world := camera.get_world_3d().direct_space_state
    var query := PhysicsRayQueryParameters3D.new()
    query.from = ray_origin
    query.to = ray_origin + ray_dir * 1000.0
    query.collision_mask = collision_mask
    query.collide_with_areas = false
    query.collide_with_bodies = true
    var result := world.intersect_ray(query)
    if result.is_empty():
        return Vector3.ZERO
    return result["position"]

func raycast_mouse(camera: Camera3D, collision_mask: int, length: float = 1000.0) -> Dictionary:
    var mouse_pos := get_viewport().get_mouse_position()
    var ray_origin := camera.project_ray_origin(mouse_pos)
    var ray_dir := camera.project_ray_normal(mouse_pos)
    var world := camera.get_world_3d().direct_space_state
    var query := PhysicsRayQueryParameters3D.new()
    query.from = ray_origin
    query.to = ray_origin + ray_dir * length
    query.collision_mask = collision_mask
    query.collide_with_areas = true
    query.collide_with_bodies = true
    return world.intersect_ray(query)

func is_mouse_at_screen_edge(margin: int = 10) -> Vector2:
    var viewport := get_viewport()
    if viewport == null:
        return Vector2.ZERO
    var window := viewport.get_window()
    if window == null or not window.has_focus():
        return Vector2.ZERO
    var size := viewport.get_visible_rect().size
    if size.x <= 0 or size.y <= 0:
        return Vector2.ZERO
    var mouse := viewport.get_mouse_position()
    if not viewport.get_visible_rect().has_point(mouse):
        return Vector2.ZERO
    var dir := Vector2.ZERO
    if mouse.x < margin:
        dir.x = -1.0
    elif mouse.x > size.x - margin:
        dir.x = 1.0
    if mouse.y < margin:
        dir.y = -1.0
    elif mouse.y > size.y - margin:
        dir.y = 1.0
    return dir
