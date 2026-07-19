extends Node

@warning_ignore("unused_signal")
signal game_state_changed(state: GameState)
@warning_ignore("unused_signal")
signal game_paused(paused: bool)

enum GameState { MENU, PLAYING, PAUSED, VICTORY, GAME_OVER }

var current_state: GameState = GameState.PLAYING
var current_level: Node = null

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS

func set_game_state(new_state: GameState) -> void:
    if current_state == new_state:
        return
    current_state = new_state
    game_state_changed.emit(new_state)
    match new_state:
        GameState.PLAYING:
            get_tree().paused = false
        GameState.PAUSED:
            get_tree().paused = true
        GameState.VICTORY, GameState.GAME_OVER:
            get_tree().paused = true

func toggle_pause() -> void:
    if current_state == GameState.PLAYING:
        set_game_state(GameState.PAUSED)
    elif current_state == GameState.PAUSED:
        set_game_state(GameState.PLAYING)

func register_level(level: Node) -> void:
    current_level = level

func load_level(level_path: String) -> void:
    # TODO: implement scene switching when multiple levels exist
    push_warning("load_level not yet implemented for: %s" % level_path)
