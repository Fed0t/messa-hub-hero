extends CanvasLayer

var _selection_panel: Panel = null
var _selection_label: Label = null
var _hp_bar: ProgressBar = null
var _state_label: Label = null
var _objective_list: VBoxContainer = null
var _message_label: Label = null
var _message_timer: Timer = null

var _selection_box: Control = null

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    _build_ui()
    update_objectives()

func _make_ignore_mouse(control: Control) -> void:
    control.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _build_ui() -> void:
    # Selection panel (bottom-left)
    _selection_panel = Panel.new()
    _selection_panel.anchor_left = 0.0
    _selection_panel.anchor_top = 1.0
    _selection_panel.anchor_right = 0.0
    _selection_panel.anchor_bottom = 1.0
    _selection_panel.offset_left = 12
    _selection_panel.offset_top = -156
    _selection_panel.offset_right = 272
    _selection_panel.offset_bottom = -12
    _make_ignore_mouse(_selection_panel)
    add_child(_selection_panel)
    var vbox := VBoxContainer.new()
    vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
    _make_ignore_mouse(vbox)
    _selection_panel.add_child(vbox)
    _selection_label = Label.new()
    _selection_label.text = "No selection"
    _make_ignore_mouse(_selection_label)
    vbox.add_child(_selection_label)
    _hp_bar = ProgressBar.new()
    _hp_bar.max_value = 100
    _hp_bar.value = 100
    _hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _make_ignore_mouse(_hp_bar)
    vbox.add_child(_hp_bar)
    _state_label = Label.new()
    _state_label.text = "State: IDLE"
    _make_ignore_mouse(_state_label)
    vbox.add_child(_state_label)
    var hint := Label.new()
    hint.text = "1:Knife 2:Distract C:Crouch P:Prone"
    hint.add_theme_font_size_override("font_size", 10)
    _make_ignore_mouse(hint)
    vbox.add_child(hint)

    # Objective list (top-right)
    var objective_panel := Panel.new()
    objective_panel.anchor_left = 1.0
    objective_panel.anchor_top = 0.0
    objective_panel.anchor_right = 1.0
    objective_panel.anchor_bottom = 0.0
    objective_panel.offset_left = -272
    objective_panel.offset_top = 12
    objective_panel.offset_right = -12
    objective_panel.offset_bottom = 166
    _make_ignore_mouse(objective_panel)
    add_child(objective_panel)
    _objective_list = VBoxContainer.new()
    _objective_list.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
    _make_ignore_mouse(_objective_list)
    objective_panel.add_child(_objective_list)
    var obj_title := Label.new()
    obj_title.name = "Objectives"
    obj_title.text = "Objectives"
    obj_title.add_theme_font_size_override("font_size", 14)
    _make_ignore_mouse(obj_title)
    _objective_list.add_child(obj_title)

    # Message label (center)
    _message_label = Label.new()
    _message_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
    _message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _message_label.add_theme_font_size_override("font_size", 24)
    _message_label.visible = false
    _make_ignore_mouse(_message_label)
    add_child(_message_label)

    # Help text at top center
    var help_label := Label.new()
    help_label.anchor_left = 0.0
    help_label.anchor_top = 0.0
    help_label.anchor_right = 1.0
    help_label.anchor_bottom = 0.0
    help_label.offset_left = 12
    help_label.offset_top = 8
    help_label.offset_right = -270
    help_label.offset_bottom = 46
    help_label.text = "LMB select unit | RMB move | WASD/arrows camera | Q/E rotate | Wheel zoom | 1 Knife | 2 Distract"
    help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    help_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    help_label.clip_text = true
    help_label.add_theme_font_size_override("font_size", 13)
    _make_ignore_mouse(help_label)
    add_child(help_label)

    _message_timer = Timer.new()
    _message_timer.one_shot = true
    _message_timer.timeout.connect(_hide_message)
    add_child(_message_timer)

    # Selection box overlay
func update_selection(selected: Array[Node3D]) -> void:
    if selected.is_empty():
        _selection_label.text = "No selection"
        _hp_bar.value = 0
        _state_label.text = "State: -"
        return
    var unit := selected[0]
    if not is_instance_valid(unit) or not unit is Character:
        return
    var char: Character = unit
    _selection_label.text = "%s (%d/%d)" % [char.character_name, selected.size(), 1 if selected.size() == 1 else selected.size()]
    _hp_bar.max_value = char.max_health
    _hp_bar.value = char.health
    _state_label.text = "State: %s" % Character.State.keys()[char.current_state]

func update_objectives() -> void:
    # Clear existing rows
    for child in _objective_list.get_children():
        if child.name != "Objectives":
            child.queue_free()
    for obj in MissionManager.get_active_objectives():
        var label := Label.new()
        label.text = "[ ] %s" % obj.title
        label.add_theme_font_size_override("font_size", 12)
        _make_ignore_mouse(label)
        _objective_list.add_child(label)
    for id in MissionManager.objectives.keys():
        var obj = MissionManager.objectives[id]
        if obj.status == MissionManager.ObjectiveStatus.COMPLETED:
            var label := Label.new()
            label.text = "[x] %s" % obj.title
            label.add_theme_color_override("font_color", Color.GREEN)
            label.add_theme_font_size_override("font_size", 12)
            _make_ignore_mouse(label)
            _objective_list.add_child(label)
        elif obj.status == MissionManager.ObjectiveStatus.FAILED:
            var label := Label.new()
            label.text = "[!] %s" % obj.title
            label.add_theme_color_override("font_color", Color.RED)
            label.add_theme_font_size_override("font_size", 12)
            _make_ignore_mouse(label)
            _objective_list.add_child(label)

func show_message(text: String, color: Color) -> void:
    _message_label.text = text
    _message_label.add_theme_color_override("font_color", color)
    _message_label.visible = true
    _message_timer.start(4.0)

func show_action_feedback(text: String, color: Color = Color.WHITE) -> void:
    show_message(text, color)

func _hide_message() -> void:
    _message_label.visible = false

func _ready_connection() -> void:
    pass
