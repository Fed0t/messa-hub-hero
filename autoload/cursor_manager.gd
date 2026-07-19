extends Node

enum CursorType { DEFAULT, SELECT, MOVE, ATTACK, INTERACT, FORBIDDEN }

var current_type: CursorType = CursorType.DEFAULT

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS

func set_cursor(type: CursorType) -> void:
    if current_type == type:
        return
    current_type = type
    # Godot does not easily load custom cursors from code without image resources.
    # For the prototype we change the default shape where possible.
    match type:
        CursorType.MOVE:
            Input.set_default_cursor_shape(Input.CURSOR_MOVE)
        CursorType.ATTACK:
            Input.set_default_cursor_shape(Input.CURSOR_CROSS)
        CursorType.INTERACT:
            Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
        CursorType.FORBIDDEN:
            Input.set_default_cursor_shape(Input.CURSOR_FORBIDDEN)
        _:
            Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func reset_cursor() -> void:
    set_cursor(CursorType.DEFAULT)

func get_cursor_type() -> CursorType:
    return current_type
