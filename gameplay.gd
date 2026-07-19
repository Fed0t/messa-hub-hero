extends Node3D
## Bootstrap tactic (stil Commandos) pentru messa-hub-hero.
## Spawnează comandouri + gardieni pe terenul procedural, construiește un
## navmesh care urmează relieful, pornește camera izometrică, HUD și misiunea.
## Adaptat din main.gd al prototipului new-game-project.

var _camera: IsometricCamera = null
var _hud = null
var _move_marker: Node3D = null
var _commandos: Array[Node3D] = []
var _world: Node = null

const NAV_HALF := 60.0
const NAV_STEP := 2.0
const UNIT_NAV_Y_OFFSET := 1.0
const UNIT_PICK_MASK := 1 << 1
const DRAG_SELECT_THRESHOLD := 10.0
var _extract_point := Vector3(34, 0, 20)
var _eliminate_done := false
var _extract_done := false
var _drag_select_active := false
var _drag_select_origin := Vector2.ZERO
var _drag_select_current := Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_world = get_parent()
	# Terenul e generat în World._ready (rulează după copii), deci amânăm.
	call_deferred("_setup")


func _setup() -> void:
	_build_navigation()
	_spawn_units()
	_setup_camera()
	_setup_night()
	_setup_rain()
	_setup_hud()
	_setup_mission()
	if _hud != null:
		_hud.update_objectives()
	MissionManager.mission_completed.connect(_on_mission_completed)
	MissionManager.mission_failed.connect(_on_mission_failed)
	MissionManager.enemy_alerted.connect(_on_enemy_alerted)
	MissionManager.objective_updated.connect(_on_objective_updated)
	SelectionManager.selection_changed.connect(_on_selection_changed)
	_move_marker = _create_move_marker()
	add_child(_move_marker)
	call_deferred("_select_starting_commandos")


func _terrain_height(x: float, z: float) -> float:
	if _world != null and _world.has_method("height_at"):
		return _world.height_at(x, z)
	return 0.0


func _water_level() -> float:
	if _world != null and "water_level" in _world:
		return _world.water_level
	return -1.3


func _clear_of_obstacles(x: float, z: float, padding: float = 1.3) -> bool:
	if _world != null and _world.has_method("is_military_blocked"):
		return not _world.is_military_blocked(x, z, padding)
	return true


func _on_bridge(x: float, z: float, padding: float = 0.0) -> bool:
	if _world != null and _world.has_method("is_bridge_walkable"):
		return _world.is_bridge_walkable(x, z, padding)
	return false


func _bridge_y(x: float, z: float) -> float:
	if _world != null and _world.has_method("bridge_walk_y"):
		return _world.bridge_walk_y(x, z)
	return _terrain_height(x, z)


func _on_land(x: float, z: float, obstacle_padding: float = 1.3) -> bool:
	# uscat = departe de albia râului ȘI deasupra nivelului apei
	var far_from_river := true
	if _world != null and _world.has_method("river_dist"):
		far_from_river = _world.river_dist(x, z) > 6.0
	return far_from_river and _clear_of_obstacles(x, z, obstacle_padding) and _terrain_height(x, z) > _water_level() + 0.4


func _walkable_height(x: float, z: float) -> float:
	if _on_bridge(x, z, 0.4):
		return _bridge_y(x, z)
	return _terrain_height(x, z)


func _is_walkable_point(x: float, z: float, bridge_padding: float = 0.0, obstacle_padding: float = 1.3) -> bool:
	if not _clear_of_obstacles(x, z, obstacle_padding):
		return false
	if _on_bridge(x, z, bridge_padding):
		return true
	return _on_land(x, z, obstacle_padding)


func _is_nav_cell_walkable(x0: float, z0: float) -> bool:
	var x1 := x0 + NAV_STEP
	var z1 := z0 + NAV_STEP
	var center_x := x0 + NAV_STEP * 0.5
	var center_z := z0 + NAV_STEP * 0.5
	if not _is_walkable_point(center_x, center_z, 0.45, 1.2):
		return false
	return (
		_is_walkable_point(x0, z0, 0.75, 0.55)
		and _is_walkable_point(x1, z0, 0.75, 0.55)
		and _is_walkable_point(x0, z1, 0.75, 0.55)
		and _is_walkable_point(x1, z1, 0.75, 0.55)
	)


func _find_land(near: Vector3) -> Vector3:
	# caută în spirală un punct de uscat lângă `near`
	if _on_land(near.x, near.z):
		return Vector3(near.x, _terrain_height(near.x, near.z), near.z)
	for r in range(2, 30, 2):
		for a in range(0, 360, 30):
			var rad := deg_to_rad(a)
			var x := near.x + cos(rad) * r
			var z := near.z + sin(rad) * r
			if _on_land(x, z):
				return Vector3(x, _terrain_height(x, z), z)
	return Vector3(near.x, _terrain_height(near.x, near.z), near.z)


func _build_navigation() -> void:
	var region := NavigationRegion3D.new()
	region.name = "NavRegion"
	var navmesh := NavigationMesh.new()
	navmesh.agent_radius = 0.5
	navmesh.agent_height = 1.6
	var verts := PackedVector3Array()
	var cols := int(NAV_HALF * 2.0 / NAV_STEP)
	var w := cols + 1
	for zi in range(w):
		for xi in range(w):
			var x := -NAV_HALF + xi * NAV_STEP
			var z := -NAV_HALF + zi * NAV_STEP
			verts.append(Vector3(x, _walkable_height(x, z) + UNIT_NAV_Y_OFFSET, z))
	navmesh.vertices = verts
	for zi in range(cols):
		for xi in range(cols):
			var x0 := -NAV_HALF + xi * NAV_STEP
			var z0 := -NAV_HALF + zi * NAV_STEP
			# sărim peste apă; peste râu acceptăm numai culoarul podului.
			if not _is_nav_cell_walkable(x0, z0):
				continue
			var a := zi * w + xi
			var b := zi * w + xi + 1
			var c := (zi + 1) * w + xi + 1
			var d := (zi + 1) * w + xi
			navmesh.add_polygon(PackedInt32Array([a, b, c]))
			navmesh.add_polygon(PackedInt32Array([a, c, d]))
	region.navigation_mesh = navmesh
	add_child(region)


func _spawn_units() -> void:
	var cmd_positions := [Vector3(34, 0, 24), Vector3(37, 0, 26), Vector3(34, 0, 28)]
	for i in range(cmd_positions.size()):
		var c := Commando.new()
		c.character_name = "Commando %d" % (i + 1)
		add_child(c)
		var p := _find_land(cmd_positions[i])
		c.global_position = Vector3(p.x, p.y + 1.0, p.z)
		_commandos.append(c)

	# Gardieni cu rute mai clare: pod, gard, bază și malul râului.
	var guards := [
		{"points": [Vector3(11, 0, -4), Vector3(22, 0, -7), Vector3(30, 0, -3), Vector3(20, 0, 2)]},
		{"points": [Vector3(-30, 0, -29), Vector3(-16, 0, -32), Vector3(-5, 0, -28), Vector3(-20, 0, -24)]},
		{"points": [Vector3(2, 0, -18), Vector3(15, 0, -15), Vector3(28, 0, -11), Vector3(16, 0, -9)]},
		{"points": [Vector3(36, 0, -7), Vector3(42, 0, 1), Vector3(38, 0, 9), Vector3(31, 0, 1)]},
	]
	for g in guards:
		var e := Enemy.new()
		add_child(e)
		var pts: Array[Vector3] = []
		for raw_point in g["points"]:
			var p := _find_land(raw_point)
			pts.append(Vector3(p.x, p.y + UNIT_NAV_Y_OFFSET, p.z))
		if pts.is_empty():
			continue
		e.global_position = pts[0]
		e.set_patrol_points(pts)
		if e._nav_agent != null:
			e._nav_agent.target_desired_distance = 1.8


func _setup_camera() -> void:
	var old := _world.get_node_or_null("CameraRig")
	if old != null:
		old.queue_free()
	_camera = IsometricCamera.new()
	_camera.position = Vector3(35, 0, 26)
	# zona de mișcare a camerei — generoasă, cât aproape tot terenul (200)
	_camera.set_level_size(180.0)
	add_child(_camera)


func _setup_hud() -> void:
	_hud = load("res://ui/hud.gd").new()
	add_child(_hud)


func _setup_night() -> void:
	# lumină de amurg: păstrează stealth-ul, dar ridică umbrele ca scena să fie lizibilă
	var we := _world.get_node_or_null("WorldEnvironment")
	if we != null and we.environment != null:
		var env: Environment = we.environment
		env.tonemap_mode = Environment.TONE_MAPPER_AGX
		env.tonemap_exposure = 1.45
		env.tonemap_white = 1.25
		env.background_energy_multiplier = 1.05
		if env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
			var sm: ProceduralSkyMaterial = env.sky.sky_material
			sm.sky_top_color = Color(0.18, 0.30, 0.48)
			sm.sky_horizon_color = Color(0.46, 0.56, 0.66)
			sm.ground_bottom_color = Color(0.18, 0.22, 0.18)
			sm.ground_horizon_color = Color(0.34, 0.40, 0.34)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_sky_contribution = 1.0
		env.ambient_light_energy = 2.25
		env.sdfgi_enabled = true
		env.sdfgi_use_occlusion = true
		env.sdfgi_bounce_feedback = 0.72
		env.sdfgi_cascades = 4
		env.sdfgi_energy = 1.75
		env.glow_enabled = true
		env.glow_intensity = 0.22
		env.glow_strength = 0.65
		env.glow_bloom = 0.05
		env.glow_hdr_threshold = 1.1
		env.ssao_enabled = true
		env.ssao_intensity = 0.45
		env.ssao_radius = 0.9
		env.ssao_power = 1.1
		env.fog_enabled = true
		env.fog_light_color = Color(0.55, 0.63, 0.72)
		env.fog_light_energy = 0.55
		env.fog_density = 0.0012
		env.fog_aerial_perspective = 0.14
	var sun := _world.get_node_or_null("Sun")
	if sun != null and sun is DirectionalLight3D:
		var d: DirectionalLight3D = sun
		d.light_energy = 1.55
		d.light_color = Color(0.86, 0.91, 1.0)
		d.rotation_degrees = Vector3(-46, 34, 0)
		d.shadow_enabled = true
		d.shadow_opacity = 0.58
		d.shadow_blur = 2.1
		d.light_angular_distance = 2.2


func _setup_rain() -> void:
	var rain := GPUParticles3D.new()
	rain.name = "Rain"
	rain.amount = 650
	rain.lifetime = 1.1
	rain.local_coords = false
	rain.position = Vector3(0, 26, 0)
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0.06, -1, 0.02)
	mat.spread = 2.0
	mat.gravity = Vector3(0, -32, 0)
	mat.initial_velocity_min = 12.0
	mat.initial_velocity_max = 16.0
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(34, 1, 34)
	rain.process_material = mat
	var streak := BoxMesh.new()
	streak.size = Vector3(0.015, 0.42, 0.015)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.72, 0.82, 0.95, 0.32)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	streak.material = smat
	rain.draw_pass_1 = streak
	# atașăm ploaia de cameră ca să urmeze vederea
	if _camera != null:
		_camera.add_child(rain)
	else:
		add_child(rain)


func _setup_mission() -> void:
	var mission: Array[Dictionary] = [
		{"id": "eliminate", "title": "Elimină gardienii", "description": "Neutralizează toată paza."},
		{"id": "extract", "title": "Evacuare", "description": "Du echipa la punctul de extracție."},
	]
	MissionManager.register_mission(mission)


# ---------------- INPUT ----------------

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		GameManager.toggle_pause()
		return
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		var is_select_all_key := key_event.physical_keycode == KEY_A or key_event.keycode == KEY_A
		if key_event.pressed and not key_event.echo and (key_event.ctrl_pressed or key_event.meta_pressed) and is_select_all_key:
			_cancel_drag_select()
			_select_all_commandos(true)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion and _drag_select_active:
		var motion_event := event as InputEventMouseMotion
		_drag_select_current = motion_event.position
		if _drag_select_origin.distance_to(_drag_select_current) >= DRAG_SELECT_THRESHOLD and _hud != null and _hud.has_method("show_selection_box"):
			_hud.show_selection_box(_drag_select_origin, _drag_select_current)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed:
			if mouse_event.double_click and _find_commando_under_mouse() != null:
				_cancel_drag_select()
				_select_all_commandos(true)
			else:
				_drag_select_active = true
				_drag_select_origin = mouse_event.position
				_drag_select_current = mouse_event.position
				if _hud != null and _hud.has_method("hide_selection_box"):
					_hud.hide_selection_box()
		elif _drag_select_active:
			_drag_select_current = mouse_event.position
			if _drag_select_origin.distance_to(_drag_select_current) >= DRAG_SELECT_THRESHOLD:
				_select_commandos_in_drag_rect()
			else:
				_handle_select()
			_cancel_drag_select()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_cancel_drag_select()
		_handle_move()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("toggle_crouch"):
		_toggle_stance(Character.State.CROUCH)
	if event.is_action_pressed("toggle_prone"):
		_toggle_stance(Character.State.PRONE)
	if event.is_action_pressed("ability_knife"):
		_use_ability_knife()
	if event.is_action_pressed("ability_shoot"):
		_use_ability_shoot()
	if event.is_action_pressed("ability_distract"):
		_use_ability_distract()


func _handle_select() -> void:
	if _camera == null:
		return
	var add_mode := Input.is_action_pressed("add_select")
	var nearest := _find_commando_under_mouse()
	if nearest != null:
		_apply_commando_selection([nearest], add_mode)
	elif not add_mode:
		SelectionManager.clear_selection()


func _select_commandos_in_drag_rect() -> void:
	var rect := Rect2(_drag_select_origin, _drag_select_current - _drag_select_origin).abs()
	var units := _commandos_in_rect(rect)
	var add_mode := Input.is_action_pressed("add_select")
	if units.is_empty():
		if not add_mode:
			SelectionManager.clear_selection()
		return
	_apply_commando_selection(units, add_mode)


func _commandos_in_rect(rect: Rect2) -> Array[Node3D]:
	var result: Array[Node3D] = []
	if _camera == null or _camera.get_camera() == null:
		return result
	var cam := _camera.get_camera()
	for node in get_tree().get_nodes_in_group("commandos"):
		if not is_instance_valid(node) or not node is Character:
			continue
		var ch: Character = node
		if ch.current_state == Character.State.DEAD:
			continue
		var samples := [
			ch.global_position + Vector3.UP * 0.25,
			ch.global_position + Vector3.UP * 0.95,
			ch.global_position + Vector3.UP * 1.7,
		]
		for sample in samples:
			if cam.is_position_behind(sample):
				continue
			if rect.has_point(cam.unproject_position(sample)):
				result.append(ch)
				break
	return result


func _apply_commando_selection(units: Array[Node3D], add_mode: bool) -> void:
	if add_mode:
		for unit in units:
			SelectionManager.add_to_selection(unit)
	else:
		SelectionManager.select_multiple(units)


func _cancel_drag_select() -> void:
	_drag_select_active = false
	if _hud != null and _hud.has_method("hide_selection_box"):
		_hud.hide_selection_box()


func _find_commando_under_mouse() -> Node3D:
	if _camera == null or _camera.get_camera() == null:
		return null
	var hit := InputManager.raycast_mouse(_camera.get_camera(), UNIT_PICK_MASK)
	if not hit.is_empty():
		var picked := _commando_from_node(hit["collider"] as Node)
		if picked != null:
			return picked

	var mouse_pos := get_viewport().get_mouse_position()
	var nearest: Node3D = null
	var nearest_dist := 64.0
	for node in get_tree().get_nodes_in_group("commandos"):
		if not is_instance_valid(node) or not node is Character:
			continue
		var ch: Character = node
		if ch.current_state == Character.State.DEAD:
			continue
		var dist := _commando_screen_pick_distance(ch, mouse_pos)
		if dist < nearest_dist:
			nearest = ch
			nearest_dist = dist
	return nearest


func _commando_from_node(node: Node) -> Node3D:
	var current := node
	while current != null:
		if current is Commando:
			var commando := current as Commando
			if commando.current_state != Character.State.DEAD:
				return commando
			return null
		current = current.get_parent()
	return null


func _commando_screen_pick_distance(ch: Character, mouse_pos: Vector2) -> float:
	var cam := _camera.get_camera()
	var samples := [
		ch.global_position + Vector3.UP * 0.25,
		ch.global_position + Vector3.UP * 0.95,
		ch.global_position + Vector3.UP * 1.7,
	]
	var best := INF
	for sample in samples:
		if cam.is_position_behind(sample):
			continue
		best = minf(best, cam.unproject_position(sample).distance_to(mouse_pos))
	return best


func _handle_move() -> void:
	var target := InputManager.get_terrain_mouse_position(_camera.get_camera(), 1)
	if target == Vector3.ZERO:
		return
	if not _is_walkable_point(target.x, target.z, 0.65, 0.45):
		if _hud != null:
			_hud.show_action_feedback("Țintă inaccesibilă", Color(1.0, 0.72, 0.08))
		return
	target.y = _walkable_height(target.x, target.z) + UNIT_NAV_Y_OFFSET
	SelectionManager.order_move(target)
	_show_move_marker(Vector3(target.x, target.y - UNIT_NAV_Y_OFFSET, target.z))
	CursorManager.set_cursor(CursorManager.CursorType.MOVE)
	if _hud != null:
		_hud.show_action_feedback("Deplasare", Color(0.2, 0.8, 1.0))


func _toggle_stance(target_state: Character.State) -> void:
	for unit in SelectionManager.selected_units:
		if not is_instance_valid(unit) or not unit is Character:
			continue
		var ch: Character = unit
		if ch.current_state == Character.State.DEAD:
			continue
		if target_state == Character.State.CROUCH:
			ch.toggle_crouch()
		elif target_state == Character.State.PRONE:
			ch.toggle_prone()


func _use_ability_knife() -> void:
	var used := false
	for unit in SelectionManager.selected_units:
		if not is_instance_valid(unit) or not unit is Commando:
			continue
		if (unit as Commando).try_knife():
			used = true
	if _hud != null:
		if used:
			_hud.show_action_feedback("Eliminare cu cuțitul", Color(1.0, 0.25, 0.15))
		else:
			_hud.show_action_feedback("Niciun inamic în rază", Color(1.0, 0.85, 0.1))


func _use_ability_shoot() -> void:
	var used := false
	for unit in SelectionManager.selected_units:
		if not is_instance_valid(unit) or not unit is Commando:
			continue
		if (unit as Commando).try_shoot():
			used = true
	if _hud != null:
		if used:
			_hud.show_action_feedback("Foc!", Color(1.0, 0.7, 0.2))
		else:
			_hud.show_action_feedback("Niciun inamic la vedere", Color(1.0, 0.85, 0.1))


func _use_ability_distract() -> void:
	var target := InputManager.get_terrain_mouse_position(_camera.get_camera(), 1)
	if target == Vector3.ZERO:
		return
	for unit in SelectionManager.selected_units:
		if not is_instance_valid(unit) or not unit is Commando:
			continue
		if (unit as Commando).try_distract(target):
			if _hud != null:
				_hud.show_action_feedback("Distragere", Color(1.0, 0.9, 0.1))
			break


# ---------------- PROCESS ----------------

func _process(_delta: float) -> void:
	if GameManager.current_state == GameManager.GameState.PLAYING:
		_update_cursor()
		_check_objectives()
	if _hud != null:
		_hud.update_selection(SelectionManager.selected_units)


func _update_cursor() -> void:
	if _camera == null:
		return
	var result := InputManager.raycast_mouse(_camera.get_camera(), 2)
	if result.is_empty():
		CursorManager.set_cursor(CursorManager.CursorType.DEFAULT)
		return
	var collider := result["collider"] as Node3D
	if collider != null and collider.is_in_group("commandos"):
		CursorManager.set_cursor(CursorManager.CursorType.SELECT)
	elif collider != null and collider.is_in_group("enemies"):
		CursorManager.set_cursor(CursorManager.CursorType.ATTACK)
	else:
		CursorManager.set_cursor(CursorManager.CursorType.DEFAULT)


func _check_objectives() -> void:
	var alive_commandos := 0
	for c in _commandos:
		if is_instance_valid(c) and (c as Character).current_state != Character.State.DEAD:
			alive_commandos += 1
	if alive_commandos == 0:
		MissionManager.fail_mission("Toți comandourii au căzut")
		return

	if not _eliminate_done:
		var guards_alive := 0
		for e in get_tree().get_nodes_in_group("enemies"):
			if is_instance_valid(e) and (e as Character).current_state != Character.State.DEAD:
				guards_alive += 1
		if guards_alive == 0:
			_eliminate_done = true
			MissionManager.complete_objective("eliminate")

	if _eliminate_done and not _extract_done:
		var all_at_extract := true
		for c in _commandos:
			if not is_instance_valid(c):
				continue
			if (c as Character).current_state == Character.State.DEAD:
				continue
			if Vector2(c.global_position.x, c.global_position.z).distance_to(
					Vector2(_extract_point.x, _extract_point.z)) > 5.0:
				all_at_extract = false
				break
		if all_at_extract:
			_extract_done = true
			MissionManager.complete_objective("extract")


# ---------------- SIGNALS ----------------

func _on_selection_changed(selected: Array[Node3D]) -> void:
	if _hud != null:
		_hud.update_selection(selected)
	if _camera != null:
		if selected.is_empty():
			_camera.clear_follow_target()
		else:
			_camera.set_follow_target(selected[0])


func _on_objective_updated(id: String, status: MissionManager.ObjectiveStatus) -> void:
	if _hud == null:
		return
	_hud.update_objectives()
	if MissionManager.objectives.has(id):
		var obj = MissionManager.objectives[id]
		if status == MissionManager.ObjectiveStatus.COMPLETED:
			_hud.show_action_feedback("Obiectiv complet: %s" % obj.title, Color(0.2, 1.0, 0.35))


func _on_enemy_alerted(count: int) -> void:
	if _hud != null:
		if _hud.has_method("show_alarm"):
			_hud.show_alarm(3.5)
		_hud.show_action_feedback("Inamic alertat (%d)" % count, Color(1.0, 0.45, 0.05))


func _on_mission_completed() -> void:
	GameManager.set_game_state(GameManager.GameState.VICTORY)
	if _hud != null:
		_hud.show_message("Misiune îndeplinită", Color.GREEN)


func _on_mission_failed(reason: String) -> void:
	GameManager.set_game_state(GameManager.GameState.GAME_OVER)
	if _hud != null:
		_hud.show_message("Misiune eșuată: %s" % reason, Color.RED)


func _select_starting_commandos() -> void:
	await get_tree().process_frame
	_select_all_commandos(false)


func _select_all_commandos(show_feedback: bool) -> void:
	var starting: Array[Node3D] = []
	for c in _commandos:
		if is_instance_valid(c) and c is Character and (c as Character).current_state != Character.State.DEAD:
			starting.append(c)
	_apply_commando_selection(starting, false)
	if show_feedback and _hud != null:
		_hud.show_action_feedback("Echipă selectată", Color(0.2, 0.8, 1.0))


# ---------------- MOVE MARKER ----------------

func _create_move_marker() -> Node3D:
	var marker := Node3D.new()
	marker.name = "MoveMarker"
	marker.visible = false
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.62
	torus.outer_radius = 0.72
	ring.mesh = torus
	ring.position.y = 0.06
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.9, 0.35, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.7, 0.2)
	mat.emission_energy_multiplier = 0.6
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = mat
	marker.add_child(ring)
	return marker


func _show_move_marker(target: Vector3) -> void:
	if _move_marker == null:
		return
	_move_marker.global_position = target + Vector3.UP * 0.1
	_move_marker.visible = true
