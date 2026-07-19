extends Node

signal selection_changed(selected: Array[Node3D])
signal single_unit_selected(unit: Node3D)

var selected_units: Array[Node3D] = []

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS

func select(unit: Node3D) -> void:
    clear_selection(false)
    _add_unit(unit)
    single_unit_selected.emit(unit)

func add_to_selection(unit: Node3D) -> void:
    if unit in selected_units:
        _remove_unit(unit)
    else:
        _add_unit(unit)

func select_multiple(units: Array[Node3D]) -> void:
    clear_selection(false)
    for unit in units:
        _add_unit(unit)

func clear_selection(emit: bool = true) -> void:
    for unit in selected_units:
        if is_instance_valid(unit) and unit.has_method("set_selected"):
            unit.set_selected(false)
    selected_units.clear()
    if emit:
        selection_changed.emit(selected_units)

func _add_unit(unit: Node3D) -> void:
    if not is_instance_valid(unit) or unit in selected_units:
        return
    selected_units.append(unit)
    if unit.has_method("set_selected"):
        unit.set_selected(true)
    selection_changed.emit(selected_units)

func _remove_unit(unit: Node3D) -> void:
    if not unit in selected_units:
        return
    selected_units.erase(unit)
    if is_instance_valid(unit) and unit.has_method("set_selected"):
        unit.set_selected(false)
    selection_changed.emit(selected_units)

func get_lead_unit() -> Node3D:
    if selected_units.is_empty():
        return null
    return selected_units[0]

func order_move(target_position: Vector3) -> void:
    if selected_units.is_empty():
        return
    var count := 0
    for unit in selected_units:
        if is_instance_valid(unit) and unit.has_method("move_to"):
            var offset := Vector3.ZERO
            if selected_units.size() > 1:
                var row := count / 3
                var col := count % 3
                offset = Vector3(col - 1, 0, row) * 1.5
            unit.move_to(target_position + offset)
            count += 1
