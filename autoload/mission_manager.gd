extends Node

signal objective_updated(id: String, status: ObjectiveStatus)
signal mission_completed()
signal mission_failed(reason: String)
signal enemy_alerted(count: int)

enum ObjectiveStatus { ACTIVE, COMPLETED, FAILED }

class Objective:
    var id: String
    var title: String
    var description: String
    var status: ObjectiveStatus

    func _init(p_id: String, p_title: String, p_description: String) -> void:
        id = p_id
        title = p_title
        description = p_description
        status = ObjectiveStatus.ACTIVE

var objectives: Dictionary = {}
var _enemy_alert_count := 0

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS

func register_mission(mission_data: Array[Dictionary]) -> void:
    objectives.clear()
    for data in mission_data:
        var obj := Objective.new(data["id"], data["title"], data["description"])
        objectives[obj.id] = obj

func complete_objective(id: String) -> void:
    if not objectives.has(id):
        return
    var obj: Objective = objectives[id]
    if obj.status == ObjectiveStatus.COMPLETED:
        return
    obj.status = ObjectiveStatus.COMPLETED
    objective_updated.emit(id, obj.status)
    _check_mission_end()

func fail_objective(id: String) -> void:
    if not objectives.has(id):
        return
    var obj: Objective = objectives[id]
    if obj.status == ObjectiveStatus.FAILED:
        return
    obj.status = ObjectiveStatus.FAILED
    objective_updated.emit(id, obj.status)
    mission_failed.emit("Objective failed: %s" % obj.title)

func fail_mission(reason: String) -> void:
    mission_failed.emit(reason)

func is_objective_complete(id: String) -> bool:
    if not objectives.has(id):
        return false
    return objectives[id].status == ObjectiveStatus.COMPLETED

func get_active_objectives() -> Array[Objective]:
    var result: Array[Objective] = []
    for obj in objectives.values():
        if obj.status == ObjectiveStatus.ACTIVE:
            result.append(obj)
    return result

func register_enemy_alert() -> void:
    _enemy_alert_count += 1
    enemy_alerted.emit(_enemy_alert_count)

func get_alert_count() -> int:
    return _enemy_alert_count

func _check_mission_end() -> void:
    for obj in objectives.values():
        if obj.status != ObjectiveStatus.COMPLETED:
            return
    mission_completed.emit()
