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
const NAV_STEP := 4.0
var _extract_point := Vector3(34, 0, 20)
var _eliminate_done := false
var _extract_done := false


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


func _on_land(x: float, z: float) -> bool:
	# uscat = departe de albia râului ȘI deasupra nivelului apei
	var far_from_river := true
	if _world != null and _world.has_method("river_dist"):
		far_from_river = _world.river_dist(x, z) > 6.0
	return far_from_river and _terrain_height(x, z) > _water_level() + 0.4


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
			verts.append(Vector3(x, _terrain_height(x, z) + 0.05, z))
	navmesh.vertices = verts
	for zi in range(cols):
		for xi in range(cols):
			var x0 := -NAV_HALF + xi * NAV_STEP
			var z0 := -NAV_HALF + zi * NAV_STEP
			# sărim peste celulele care ating râul/apa -> navmesh doar pe uscat
			if not (_on_land(x0, z0) and _on_land(x0 + NAV_STEP, z0)
					and _on_land(x0, z0 + NAV_STEP) and _on_land(x0 + NAV_STEP, z0 + NAV_STEP)):
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

	# gardieni departe de start (spre nord), fiecare cu o patrulă între 2 puncte
	var guards := [
		{"a": Vector3(12, 0, -2), "b": Vector3(26, 0, -2)},
		{"a": Vector3(34, 0, -10), "b": Vector3(34, 0, 2)},
		{"a": Vector3(2, 0, -14), "b": Vector3(16, 0, -14)},
	]
	for g in guards:
		var e := Enemy.new()
		add_child(e)
		var pa := _find_land(g["a"])
		var pb := _find_land(g["b"])
		e.global_position = Vector3(pa.x, pa.y + 1.0, pa.z)
		var pts: Array[Vector3] = [
			Vector3(pa.x, pa.y + 0.05, pa.z),
			Vector3(pb.x, pb.y + 0.05, pb.z),
		]
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
	# ambient nocturn cinematic: AgX, SDFGI (lumină indirectă), glow, umbre moi
	var we := _world.get_node_or_null("WorldEnvironment")
	if we != null and we.environment != null:
		var env: Environment = we.environment
		# tonemapping cinematic (nu mai strivește umbrele/lumina)
		env.tonemap_mode = Environment.TONE_MAPPER_AGX
		env.tonemap_exposure = 1.1
		env.tonemap_white = 1.0
		# cer nocturn — albastru profund, dar nu negru (dă și ambient)
		env.background_energy_multiplier = 0.6
		if env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
			var sm: ProceduralSkyMaterial = env.sky.sky_material
			sm.sky_top_color = Color(0.04, 0.07, 0.16)
			sm.sky_horizon_color = Color(0.1, 0.14, 0.24)
			sm.ground_bottom_color = Color(0.03, 0.05, 0.09)
			sm.ground_horizon_color = Color(0.08, 0.11, 0.18)
		# ambient din cer + energie decentă -> umbrele devin albastre, nu negre
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_sky_contribution = 1.0
		env.ambient_light_energy = 1.6
		# SDFGI: lumină globală indirectă (bounce) -> umple umbrele, look profesionist
		env.sdfgi_enabled = true
		env.sdfgi_use_occlusion = true
		env.sdfgi_bounce_feedback = 0.6
		env.sdfgi_cascades = 4
		env.sdfgi_energy = 1.3
		# glow subtil pe surse luminoase
		env.glow_enabled = true
		env.glow_intensity = 0.3
		env.glow_strength = 0.9
		env.glow_bloom = 0.05
		env.glow_hdr_threshold = 1.1
		# ocluzie ambientală ușoară (umbre de contact, nu strivite)
		env.ssao_enabled = true
		env.ssao_intensity = 1.0
		env.ssao_radius = 1.2
		env.ssao_power = 1.5
		# ceață atmosferică rece, subtilă
		env.fog_enabled = true
		env.fog_light_color = Color(0.22, 0.28, 0.44)
		env.fog_light_energy = 0.7
		env.fog_density = 0.0025
		env.fog_aerial_perspective = 0.25
	var sun := _world.get_node_or_null("Sun")
	if sun != null and sun is DirectionalLight3D:
		var d: DirectionalLight3D = sun
		# lună: rece, energie moderată, umbre MOI (nu tăioase)
		d.light_energy = 0.85
		d.light_color = Color(0.62, 0.72, 1.0)
		d.rotation_degrees = Vector3(-52, 38, 0)
		d.shadow_enabled = true
		d.shadow_opacity = 0.82
		d.shadow_blur = 1.5
		d.light_angular_distance = 1.8


func _setup_rain() -> void:
	var rain := GPUParticles3D.new()
	rain.name = "Rain"
	rain.amount = 1200
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
	streak.size = Vector3(0.02, 0.55, 0.02)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.7, 0.8, 0.98, 0.5)
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
	if event.is_action_pressed("select"):
		_handle_select()
	elif event.is_action_pressed("move_to"):
		_handle_move()
	if event.is_action_pressed("toggle_crouch"):
		_toggle_stance(Character.State.CROUCH)
	if event.is_action_pressed("toggle_prone"):
		_toggle_stance(Character.State.PRONE)
	if event.is_action_pressed("ability_knife"):
		_use_ability_knife()
	if event.is_action_pressed("ability_distract"):
		_use_ability_distract()


func _handle_select() -> void:
	if _camera == null:
		return
	var add_mode := Input.is_action_pressed("add_select")
	var nearest := _find_commando_under_mouse()
	if nearest != null:
		if add_mode:
			SelectionManager.add_to_selection(nearest)
		else:
			SelectionManager.select(nearest)
	elif not add_mode:
		SelectionManager.clear_selection()


func _find_commando_under_mouse() -> Node3D:
	if _camera == null or _camera.get_camera() == null:
		return null
	var mouse_pos := get_viewport().get_mouse_position()
	var nearest: Node3D = null
	var nearest_dist := 40.0
	for node in get_tree().get_nodes_in_group("commandos"):
		if not is_instance_valid(node) or not node is Character:
			continue
		var ch: Character = node
		if ch.current_state == Character.State.DEAD:
			continue
		var screen_pos := ch.get_2d_screen_position(_camera.get_camera())
		var dist := screen_pos.distance_to(mouse_pos)
		if dist < nearest_dist:
			nearest = ch
			nearest_dist = dist
	return nearest


func _handle_move() -> void:
	var target := InputManager.get_terrain_mouse_position(_camera.get_camera(), 1)
	if target == Vector3.ZERO:
		return
	SelectionManager.order_move(target)
	_show_move_marker(target)
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
	var starting: Array[Node3D] = []
	for c in _commandos:
		if is_instance_valid(c):
			starting.append(c)
	SelectionManager.select_multiple(starting)
	if _hud != null:
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
