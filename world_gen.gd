@tool
extends Node3D

## Generator procedural: teren deluros din noise + iarbă și copaci pe suprafață,
## plus un râu șerpuit (spline) cu apă și un pod peste el.
## Rulează în editor (@tool) și la runtime. Reglează din inspector.

@export_group("Dealuri")
## Cât de înalte sunt dealurile (metri). 0 = teren plat.
@export var hilliness := 2.0
## Cât de dese/mari sunt dealurile (mai mic = dealuri late și line).
@export var hill_scale := 0.022
@export var noise_seed := 1337
@export var terrain_size := 200.0
@export var terrain_subdiv := 140
@export var ground_uv := 0.25
## Ridică terenul deasupra apei, ca apa să apară DOAR în albia râului.
@export var terrain_base := 2.0

@export_group("Iarbă")
@export var grass_count := 3000
@export var grass_area := 55.0
## Cât de mult se înclină iarba după panta dealului (0 = vertical, 1 = complet pe pantă).
@export_range(0.0, 1.0) var grass_slope_align := 0.85

@export_group("Râu")
## Lățimea albiei (partea plată de jos).
@export var river_width := 9.0
## Cât de lat e malul (tranziția lină spre teren normal).
@export var river_bank := 5.0
## Adâncimea fundului albiei.
@export var river_bed_level := -2.6
## Nivelul suprafeței apei.
@export var water_level := -1.3

@export_group("Pod")
## Unde e podul de-a lungul râului (0 = început, 1 = sfârșit).
@export_range(0.0, 1.0) var bridge_at := 0.5
## Garda tablierului deasupra nivelului malului.
@export var bridge_height := 0.4
## Mărimea modelului 3D de pod (glb).
@export var bridge_scale := 10.0
## Dacă e bifat, generatorul NU mai atinge modelul de pod —
## îl poziționezi și scalezi manual în editor, iar modificările rămân.
@export var bridge_manual := false

@export_group("Modele (Props)")
## Dacă e bifat, generatorul NU mai așază modelele din Props pe teren —
## le poziționezi complet manual (inclusiv pe pod, la orice înălțime).
@export var props_manual := false

@export_group("Decor militar")
@export var military_props_enabled := true
@export var military_fence_height := 2.1
@export var military_collision_enabled := true

@export_group("")
## Bifează pentru a regenera totul cu setările curente.
@export var regenerate := false: set = _set_regenerate

const OBSTACLE_COLLISION_LAYER := 1 << 2

var _noise := FastNoiseLite.new()
var _river: Curve3D = null
var _military_blockers: Array[Dictionary] = []
var _cover_zones: Array[Dictionary] = []


func _set_regenerate(_v: bool) -> void:
	regenerate = false
	if is_node_ready():
		generate()


func _ready() -> void:
	generate()


func _configure_noise() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.seed = noise_seed
	_noise.frequency = hill_scale
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 3


func _ensure_river() -> void:
	_river = null
	if not has_node("River"):
		return
	var path := get_node("River") as Path3D
	if path.curve == null:
		path.curve = Curve3D.new()
	# populează un traseu implicit șerpuit dacă e gol (utilizatorul îl poate edita)
	if path.curve.point_count < 2:
		var default_pts := [
			Vector3(-95, 0, -28), Vector3(-45, 0, 16),
			Vector3(2, 0, -22), Vector3(48, 0, 18), Vector3(95, 0, -26),
		]
		for i in range(default_pts.size()):
			var p: Vector3 = default_pts[i]
			var handle := Vector3.ZERO
			if i > 0 and i < default_pts.size() - 1:
				handle = (default_pts[i + 1] - default_pts[i - 1]) * 0.25
			path.curve.add_point(p, -handle, handle)
	path.curve.bake_interval = 1.0
	_river = path.curve


func height_at(x: float, z: float) -> float:
	var h := _noise.get_noise_2d(x, z) * hilliness + terrain_base
	if _river != null:
		var d := river_dist(x, z)
		var carve := 1.0 - smoothstep(river_width * 0.5, river_width * 0.5 + river_bank, d)
		h = lerpf(h, river_bed_level, carve)
	return h


## Distanța în plan (XZ) de la (x,z) la axa râului.
func river_dist(x: float, z: float) -> float:
	if _river == null or _river.point_count < 2:
		return 1e9
	var p := _river.get_closest_point(Vector3(x, 0, z))
	return Vector2(x, z).distance_to(Vector2(p.x, p.z))


## Normala suprafeței la (x,z), din diferențe finite ale înălțimii.
func normal_at(x: float, z: float) -> Vector3:
	var e := 0.5
	var h_l := height_at(x - e, z)
	var h_r := height_at(x + e, z)
	var h_d := height_at(x, z - e)
	var h_u := height_at(x, z + e)
	return Vector3(h_l - h_r, 2.0 * e, h_d - h_u).normalized()


func is_military_blocked(x: float, z: float, padding: float = 0.25) -> bool:
	for block in _military_blockers:
		var center: Vector2 = block["center"]
		var half: Vector2 = block["half"] + Vector2(padding, padding)
		var yaw: float = block["yaw"]
		var rel := Vector2(x, z) - center
		var c := cos(-yaw)
		var s := sin(-yaw)
		var local := Vector2(rel.x * c - rel.y * s, rel.x * s + rel.y * c)
		if absf(local.x) <= half.x and absf(local.y) <= half.y:
			return true
	return false


func is_bridge_walkable(x: float, z: float, padding: float = 0.0) -> bool:
	var bridge := _get_bridge_nav_data()
	if bridge.is_empty():
		return false
	var center: Vector3 = bridge["center"]
	var perp: Vector3 = bridge["perp"]
	var dir: Vector3 = bridge["dir"]
	var rel := Vector3(x - center.x, 0.0, z - center.z)
	var across := rel.dot(perp)
	var along := rel.dot(dir)
	var half_length: float = bridge["half_length"] + padding
	var half_width: float = bridge["half_width"] + padding
	return absf(across) <= half_length and absf(along) <= half_width


func bridge_walk_y(x: float, z: float) -> float:
	var bridge := _get_bridge_nav_data()
	if bridge.is_empty():
		return height_at(x, z)
	return bridge["deck_y"]


func cover_visibility_multiplier(pos: Vector3, stance: int) -> float:
	var multiplier := 1.0
	var x := pos.x
	var z := pos.z
	var crouched := stance == 2
	var prone := stance == 3
	for zone in _cover_zones:
		var center: Vector2 = zone["center"]
		var radius: float = zone["radius"]
		var dist := Vector2(x, z).distance_to(center)
		if dist <= radius:
			var zone_multiplier: float = zone["multiplier"]
			if prone:
				zone_multiplier = maxf(0.28, zone_multiplier - 0.12)
			elif crouched:
				zone_multiplier = maxf(0.36, zone_multiplier - 0.06)
			multiplier = minf(multiplier, zone_multiplier)
	if crouched or prone:
		if _inside_grass_cover(x, z):
			multiplier = minf(multiplier, 0.58 if prone else 0.78)
		if _near_tree_cover(x, z):
			multiplier = minf(multiplier, 0.46 if prone else 0.66)
	return multiplier


func _inside_grass_cover(x: float, z: float) -> bool:
	if absf(x) > grass_area or absf(z) > grass_area:
		return false
	if _river != null and river_dist(x, z) <= river_width * 0.5 + 1.2:
		return false
	return height_at(x, z) > water_level + 0.4


func _near_tree_cover(x: float, z: float) -> bool:
	var trees := get_node_or_null("Trees")
	if trees == null:
		return false
	var p := Vector2(x, z)
	for child in trees.get_children():
		if not child is Node3D:
			continue
		var tree := child as Node3D
		if p.distance_to(Vector2(tree.global_position.x, tree.global_position.z)) <= 4.2:
			return true
	return false


func generate() -> void:
	_configure_noise()
	_ensure_river()
	_build_terrain()
	_build_water()
	_build_grass()
	_snap_trees()
	_place_bridge()
	_build_military_props()
	_snap_props()


func _build_terrain() -> void:
	if not has_node("Terrain/Mesh"):
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var res := terrain_subdiv
	var half := terrain_size * 0.5
	var step := terrain_size / float(res)

	for zi in range(res):
		for xi in range(res):
			var x0 := -half + xi * step
			var x1 := x0 + step
			var z0 := -half + zi * step
			var z1 := z0 + step
			var p00 := Vector3(x0, height_at(x0, z0), z0)
			var p10 := Vector3(x1, height_at(x1, z0), z0)
			var p01 := Vector3(x0, height_at(x0, z1), z1)
			var p11 := Vector3(x1, height_at(x1, z1), z1)
			_add_vertex(st, p00)
			_add_vertex(st, p11)
			_add_vertex(st, p01)
			_add_vertex(st, p00)
			_add_vertex(st, p10)
			_add_vertex(st, p11)

	st.generate_normals()
	st.generate_tangents()
	var mesh := st.commit()

	var mi := get_node("Terrain/Mesh") as MeshInstance3D
	mi.mesh = mesh
	if has_node("Terrain/CollisionShape3D"):
		(get_node("Terrain/CollisionShape3D") as CollisionShape3D).shape = mesh.create_trimesh_shape()


func _add_vertex(st: SurfaceTool, p: Vector3) -> void:
	st.set_uv(Vector2(p.x, p.z) * ground_uv)
	st.add_vertex(p)


func _build_water() -> void:
	if not has_node("Water"):
		return
	var water := get_node("Water") as MeshInstance3D
	# un singur plan mare la nivelul apei; terenul (ridicat) o ascunde peste tot
	# în afară de albia râului -> țărmul e exact conturul terenului, fără margini.
	var h := terrain_size * 0.5
	var y := water_level
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var p00 := Vector3(-h, y, -h)
	var p10 := Vector3(h, y, -h)
	var p01 := Vector3(-h, y, h)
	var p11 := Vector3(h, y, h)
	_wv(st, p00, Vector2(-h, -h))
	_wv(st, p11, Vector2(h, h))
	_wv(st, p01, Vector2(-h, h))
	_wv(st, p00, Vector2(-h, -h))
	_wv(st, p10, Vector2(h, -h))
	_wv(st, p11, Vector2(h, h))
	st.generate_tangents()
	water.mesh = st.commit()


func _wv(st: SurfaceTool, p: Vector3, uv: Vector2) -> void:
	# suprafață plană orizontală: normală în sus peste tot (fără fațetare)
	st.set_normal(Vector3.UP)
	st.set_uv(uv)
	st.add_vertex(p)


func _build_grass() -> void:
	if not has_node("Grass"):
		return
	var grass := get_node("Grass") as MultiMeshInstance3D
	var rng := RandomNumberGenerator.new()
	rng.seed = 20240719
	var transforms: Array[Transform3D] = []
	for i in range(grass_count):
		var x := rng.randf_range(-grass_area, grass_area)
		var z := rng.randf_range(-grass_area, grass_area)
		var y := height_at(x, z)
		# nu pune iarbă sub apă (ar ieși prin suprafață) sau chiar în albie
		if y < water_level + 0.15 or river_dist(x, z) < river_width * 0.5:
			continue
		var yaw := rng.randf_range(0.0, TAU)
		var s := rng.randf_range(0.8, 1.3)
		var up := Vector3.UP.lerp(normal_at(x, z), grass_slope_align).normalized()
		var basis := _basis_from_up(up, yaw).scaled(Vector3(s, s, s))
		transforms.append(Transform3D(basis, Vector3(x, y, z)))

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = load("res://addons/simplegrasstextured/default_mesh.tres")
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
	grass.multimesh = mm


## Așază modelele decorative (Props) pe suprafața terenului.
func _snap_props() -> void:
	if props_manual or not has_node("Props"):
		return
	for child in get_node("Props").get_children():
		if child is Node3D:
			var p: Vector3 = child.position
			p.y = height_at(p.x, p.z)
			child.position = p


## Orientare cu axa Y aliniată la `up`, apoi rotită cu `yaw` în jurul lui.
func _basis_from_up(up: Vector3, yaw: float) -> Basis:
	var x_axis := up.cross(Vector3.FORWARD)
	if x_axis.length() < 0.001:
		x_axis = up.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis := x_axis.cross(up).normalized()
	var basis := Basis(x_axis, up, z_axis)
	return basis.rotated(up, yaw)


func _snap_trees() -> void:
	if not has_node("Trees"):
		return
	var keep_out := river_width * 0.5 + 8.0
	for child in get_node("Trees").get_children():
		if not (child is Node3D):
			continue
		var p: Vector3 = child.position
		# împinge copacul afară din râu/apă dacă a nimerit prea aproape
		var d := river_dist(p.x, p.z)
		if d < keep_out:
			var near := _river.get_closest_point(Vector3(p.x, 0, p.z))
			var dir := Vector2(p.x, p.z) - Vector2(near.x, near.z)
			if dir.length() < 0.01:
				dir = Vector2(1, 0)
			var away := dir.normalized() * keep_out
			p.x = near.x + away.x
			p.z = near.z + away.y
		p.y = height_at(p.x, p.z)
		child.position = p


func _place_bridge() -> void:
	if not has_node("Bridge"):
		return
	var site := _get_bridge_site()
	if site.is_empty():
		return
	var p: Vector3 = site["center"]
	var dir: Vector3 = site["dir"]
	var perp: Vector3 = site["perp"]
	# X = de-a curmezișul râului (deschiderea podului), Z = de-a lungul râului
	var basis := Basis(perp, Vector3.UP, dir)
	# înălțime = nivelul malului mai înalt din cele două + garda podului,
	# ca tablierul să stea drept și să prindă ambele maluri
	var bank_off := river_width * 0.5 + river_bank + 1.0
	var bank_a := p + perp * bank_off
	var bank_b := p - perp * bank_off
	var bank_h := maxf(height_at(bank_a.x, bank_a.z), height_at(bank_b.x, bank_b.z))
	var deck_y := bank_h + bridge_height
	var bridge := get_node("Bridge") as Node3D
	bridge.transform = Transform3D(basis, Vector3(p.x, deck_y, p.z))

	# ascundem podul CSG (folosim modelul 3D)
	bridge.visible = false
	if bridge is CSGCombiner3D:
		var csg_bridge := bridge as CSGCombiner3D
		csg_bridge.use_collision = false
		csg_bridge.collision_layer = 0
		csg_bridge.collision_mask = 0

	# model 3D de pod (glb) — îl așezăm pe râu, dacă nu e pe control manual
	if has_node("BridgeModel") and not bridge_manual:
		var bm := get_node("BridgeModel") as Node3D
		var s := bridge_scale
		# rotim modelul 90° ca axa lui lungă (Z) să treacă de-a curmezișul râului
		var mb := basis * Basis(Vector3.UP, PI * 0.5)
		bm.transform = Transform3D(mb.scaled(Vector3(s, s, s)), Vector3(p.x, water_level, p.z))


func _get_bridge_site() -> Dictionary:
	if _river == null or _river.point_count < 2:
		return {}
	var length := _river.get_baked_length()
	var off := clampf(bridge_at, 0.0, 1.0) * length
	var p := _river.sample_baked(off)
	var p2 := _river.sample_baked(minf(off + 1.0, length))
	var dir := p2 - p
	dir.y = 0.0
	if dir.length() < 0.0001:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	var perp := Vector3(-dir.z, 0.0, dir.x)
	return {"center": p, "dir": dir, "perp": perp}


func _get_bridge_nav_data() -> Dictionary:
	var site := _get_bridge_site()
	if site.is_empty():
		return {}
	var center: Vector3 = site["center"]
	var dir: Vector3 = site["dir"]
	var perp: Vector3 = site["perp"]
	var bank_off := river_width * 0.5 + river_bank + 1.0
	var bank_a := center + perp * bank_off
	var bank_b := center - perp * bank_off
	var bank_h := maxf(height_at(bank_a.x, bank_a.z), height_at(bank_b.x, bank_b.z))
	var deck_y := bank_h + bridge_height
	return {
		"center": center,
		"dir": dir,
		"perp": perp,
		"deck_y": deck_y,
		"half_length": river_width * 0.5 + river_bank + 12.0,
		"half_width": 3.2,
	}


func _build_military_props() -> void:
	_military_blockers.clear()
	_cover_zones.clear()
	var existing := get_node_or_null("MilitaryProps")
	if existing != null:
		remove_child(existing)
		existing.queue_free()
	if not military_props_enabled:
		return

	var root := Node3D.new()
	root.name = "MilitaryProps"
	add_child(root)

	var mats := _military_materials()
	var site := _get_bridge_site()
	if not site.is_empty():
		var center: Vector3 = site["center"]
		var dir: Vector3 = site["dir"]
		var perp: Vector3 = site["perp"]
		var bank_off := river_width * 0.5 + river_bank + 3.6
		var bridge_a := _military_land_point(center + perp * bank_off)
		var bridge_b := _military_land_point(center - perp * bank_off)
		_create_checkpoint(root, bridge_a, perp, dir, mats, "CheckpointA")
		_create_checkpoint(root, bridge_b, -perp, dir, mats, "CheckpointB")
		_create_sandbag_wall(root, _military_land_point(bridge_a - perp * 3.8 + dir * 2.5), dir, mats, "SandbagsBridgeA")
		_create_sandbag_wall(root, _military_land_point(bridge_b + perp * 3.8 - dir * 2.5), dir, mats, "SandbagsBridgeB")

	_create_barbed_fence_line(root, Vector3(-38, 0, -36), Vector3(-4, 0, -36), mats, "FenceNorth")
	_create_barbed_fence_line(root, Vector3(-38, 0, -36), Vector3(-39, 0, -21), mats, "FenceWest")
	_create_barbed_fence_line(root, Vector3(-4, 0, -36), Vector3(6, 0, -25), mats, "FenceGateReturn")
	_create_barbed_fence_line(root, Vector3(10, 0, -19), Vector3(39, 0, -13), mats, "FenceRiverBank")
	_create_barbed_fence_line(root, Vector3(42, 0, -10), Vector3(43, 0, 7), mats, "FenceEast")

	_create_concrete_barrier(root, _military_land_point(Vector3(-27, 0, -30)), deg_to_rad(8.0), mats, "ConcreteBarrierNestA")
	_create_concrete_barrier(root, _military_land_point(Vector3(-9, 0, -29)), deg_to_rad(-18.0), mats, "ConcreteBarrierNestB")
	_create_concrete_barrier(root, _military_land_point(Vector3(22, 0, -9)), deg_to_rad(24.0), mats, "ConcreteBarrierRoadA")
	_create_concrete_barrier(root, _military_land_point(Vector3(32, 0, -1)), deg_to_rad(-14.0), mats, "ConcreteBarrierRoadB")

	_create_hedgehog(root, _military_land_point(Vector3(-31, 0, -25)), deg_to_rad(18.0), mats, "HedgehogNestA")
	_create_hedgehog(root, _military_land_point(Vector3(11, 0, -17)), deg_to_rad(-20.0), mats, "HedgehogRoadA")
	_create_hedgehog(root, _military_land_point(Vector3(27, 0, -14)), deg_to_rad(36.0), mats, "HedgehogRoadB")

	_create_watchtower(root, _military_land_point(Vector3(-34, 0, -33)), deg_to_rad(44.0), mats, "WatchtowerNorthWest")
	_create_watchtower(root, _military_land_point(Vector3(39, 0, -9)), deg_to_rad(-126.0), mats, "WatchtowerEast")
	_create_generator(root, _military_land_point(Vector3(-18, 0, -32)), deg_to_rad(8.0), mats, "GeneratorNest")
	_create_gate(root, _military_land_point(Vector3(3, 0, -24)), deg_to_rad(48.0), mats, "BaseGate")

	_create_alarm_post(root, _military_land_point(Vector3(-5, 0, -33)), deg_to_rad(20.0), mats, "AlarmNest")
	_create_alarm_post(root, _military_land_point(Vector3(29, 0, -9)), deg_to_rad(-35.0), mats, "AlarmRoad")


func _military_materials() -> Dictionary:
	return {
		"metal": _military_mat(Color(0.37, 0.40, 0.38), 0.58),
		"dark_metal": _military_mat(Color(0.10, 0.12, 0.11), 0.72),
		"wire": _military_mat(Color(0.58, 0.61, 0.58), 0.45),
		"concrete": _military_mat(Color(0.52, 0.55, 0.50), 0.9),
		"sand": _military_mat(Color(0.62, 0.55, 0.38), 0.86),
		"wood": _military_mat(Color(0.31, 0.25, 0.17), 0.82),
		"roof": _military_mat(Color(0.18, 0.22, 0.19), 0.75),
		"generator_green": _military_mat(Color(0.18, 0.27, 0.18), 0.68),
		"lamp_glass": _military_mat(Color(1.0, 0.82, 0.36), 0.28, Color(1.0, 0.68, 0.18), 1.2),
		"warning_red": _military_mat(Color(0.86, 0.08, 0.05), 0.55, Color(0.9, 0.05, 0.03), 0.35),
		"warning_yellow": _military_mat(Color(0.95, 0.70, 0.12), 0.5),
		"paint_white": _military_mat(Color(0.88, 0.86, 0.78), 0.6),
		"sign": _military_mat(Color(0.08, 0.12, 0.11), 0.65),
		"beacon": _military_mat(Color(1.0, 0.05, 0.03), 0.35, Color(1.0, 0.03, 0.02), 1.6),
	}


func _military_mat(albedo: Color, roughness: float, emission: Color = Color.BLACK, emission_energy: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.roughness = roughness
	if emission_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = emission_energy
	return mat


func _military_land_point(pos: Vector3, y_offset: float = 0.0, keep_out_margin: float = 1.0) -> Vector3:
	var p := pos
	if _river != null:
		var min_dist := river_width * 0.5 + keep_out_margin
		var d := river_dist(p.x, p.z)
		if d < min_dist:
			var near := _river.get_closest_point(Vector3(p.x, 0.0, p.z))
			var away := Vector2(p.x, p.z) - Vector2(near.x, near.z)
			if away.length() < 0.01:
				away = Vector2(1.0, 0.0)
			away = away.normalized() * min_dist
			p.x = near.x + away.x
			p.z = near.z + away.y
	p.y = height_at(p.x, p.z) + y_offset
	return p


func _yaw_for_x_axis(dir: Vector3) -> float:
	var d := Vector2(dir.x, dir.z)
	if d.length() < 0.001:
		return 0.0
	d = d.normalized()
	return atan2(-d.y, d.x)


func _create_checkpoint(root: Node3D, center: Vector3, approach_axis: Vector3, cross_axis: Vector3, mats: Dictionary, checkpoint_name: String) -> void:
	var cross := cross_axis.normalized()
	var approach := approach_axis.normalized()
	var yaw_cross := _yaw_for_x_axis(cross)
	var arm_center := center + Vector3.UP * 1.05
	_add_box(root, "%sArm" % checkpoint_name, arm_center, Vector3(5.2, 0.13, 0.13), mats["paint_white"], yaw_cross, false)
	for i in range(5):
		var stripe_pos := arm_center + cross * (-2.0 + float(i) * 1.0)
		_add_box(root, "%sStripe%d" % [checkpoint_name, i], stripe_pos, Vector3(0.38, 0.15, 0.16), mats["warning_red"], yaw_cross, false)
	_add_box(root, "%sPost" % checkpoint_name, center - cross * 2.8 + Vector3.UP * 0.55, Vector3(0.42, 1.1, 0.42), mats["dark_metal"], yaw_cross, true)
	_create_concrete_barrier(root, _military_land_point(center + cross * 3.25), yaw_cross, mats, "%sBlockR" % checkpoint_name)
	_create_concrete_barrier(root, _military_land_point(center - cross * 3.25), yaw_cross, mats, "%sBlockL" % checkpoint_name)
	_create_warning_sign(root, _military_land_point(center - approach * 2.2 + cross * 2.15), yaw_cross, mats, "STOP", "%sSign" % checkpoint_name)


func _create_barbed_fence_line(root: Node3D, raw_start: Vector3, raw_end: Vector3, mats: Dictionary, fence_name: String) -> void:
	var start := _military_land_point(raw_start, 0.0, 2.0)
	var end := _military_land_point(raw_end, 0.0, 2.0)
	var flat := Vector3(end.x - start.x, 0.0, end.z - start.z)
	var length := flat.length()
	if length < 1.0:
		return
	var dir := flat.normalized()
	var segments: int = max(1, int(ceil(length / 4.0)))
	var points: Array[Vector3] = []
	for i in range(segments + 1):
		var t := float(i) / float(segments)
		points.append(_military_land_point(start.lerp(end, t), 0.0, 2.0))

	for p in points:
		_add_vertical_cylinder(root, "%sPost" % fence_name, p, military_fence_height, 0.08, mats["dark_metal"], 10)
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		for h in [0.75, 1.28, 1.78]:
			_add_cylinder_between(root, "%sWire" % fence_name, a + Vector3.UP * h, b + Vector3.UP * h, 0.025, mats["wire"], 8)
		var coils: int = max(1, int(a.distance_to(b) / 0.8))
		for c in range(coils):
			var t := (float(c) + 0.5) / float(coils)
			var coil_pos := a.lerp(b, t) + Vector3.UP * (military_fence_height + 0.12)
			_add_barbed_loop(root, "%sCoil" % fence_name, coil_pos, _yaw_for_x_axis(dir), mats["wire"])

	if military_collision_enabled:
		var mid := (start + end) * 0.5 + Vector3.UP * (military_fence_height * 0.5)
		_add_collision_box(root, "%sCollision" % fence_name, mid, Vector3(length, military_fence_height, 0.35), _yaw_for_x_axis(dir))
		_register_cover_zone(mid, maxf(2.2, length * 0.18), 0.72)


func _create_concrete_barrier(root: Node3D, pos: Vector3, yaw: float, mats: Dictionary, barrier_name: String) -> void:
	_add_box(root, "%sBase" % barrier_name, pos + Vector3.UP * 0.38, Vector3(2.8, 0.76, 0.54), mats["concrete"], yaw, true)
	_add_box(root, "%sCap" % barrier_name, pos + Vector3.UP * 0.92, Vector3(2.35, 0.34, 0.34), mats["concrete"], yaw, false)
	var side := Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0, -0.29)
	for i in range(3):
		var stripe_pos := pos + Vector3.UP * 0.78 + side + (Basis(Vector3.UP, yaw) * Vector3(-0.78 + i * 0.78, 0.0, 0.0))
		_add_box(root, "%sMark%d" % [barrier_name, i], stripe_pos, Vector3(0.34, 0.28, 0.035), mats["paint_white"], yaw, false)
	_register_cover_zone(pos, 2.3, 0.62)


func _create_sandbag_wall(root: Node3D, center: Vector3, axis: Vector3, mats: Dictionary, wall_name: String) -> void:
	var dir := axis.normalized()
	var side := Vector3(-dir.z, 0.0, dir.x)
	for row in range(2):
		for i in range(5):
			var offset := dir * (-2.2 + float(i) * 1.1) + side * (float(row) * 0.22)
			var a := _military_land_point(center + offset - dir * 0.46, 0.32 + row * 0.22)
			var b := _military_land_point(center + offset + dir * 0.46, 0.32 + row * 0.22)
			_add_capsule_between(root, "%sBag" % wall_name, a, b, 0.18, mats["sand"])
	if military_collision_enabled:
		_add_collision_box(root, "%sCollision" % wall_name, center + Vector3.UP * 0.45, Vector3(5.4, 0.9, 0.65), _yaw_for_x_axis(dir))
	_register_cover_zone(center, 3.2, 0.48)


func _create_hedgehog(root: Node3D, pos: Vector3, yaw: float, mats: Dictionary, hedgehog_name: String) -> void:
	var basis := Basis(Vector3.UP, yaw)
	_add_box(root, "%sBeamX" % hedgehog_name, pos + Vector3.UP * 0.72, Vector3(2.3, 0.18, 0.18), mats["metal"], yaw, false)
	_add_box(root, "%sBeamZ" % hedgehog_name, pos + Vector3.UP * 0.72, Vector3(2.3, 0.18, 0.18), mats["metal"], yaw + PI * 0.5, false)
	var diag_a := pos + basis * Vector3(-0.78, 0.12, -0.78)
	var diag_b := pos + basis * Vector3(0.78, 1.35, 0.78)
	_add_cylinder_between(root, "%sBeamDiagA" % hedgehog_name, diag_a, diag_b, 0.09, mats["metal"], 6)
	var diag_c := pos + basis * Vector3(0.78, 0.12, -0.78)
	var diag_d := pos + basis * Vector3(-0.78, 1.35, 0.78)
	_add_cylinder_between(root, "%sBeamDiagB" % hedgehog_name, diag_c, diag_d, 0.09, mats["metal"], 6)
	if military_collision_enabled:
		_add_collision_box(root, "%sCollision" % hedgehog_name, pos + Vector3.UP * 0.65, Vector3(2.1, 1.3, 2.1), yaw)
	_register_cover_zone(pos, 2.0, 0.82)


func _create_watchtower(root: Node3D, pos: Vector3, yaw: float, mats: Dictionary, tower_name: String) -> void:
	var tower := Node3D.new()
	tower.name = tower_name
	tower.position = pos
	tower.rotation.y = yaw
	root.add_child(tower)

	var post_offsets := [
		Vector3(-1.15, 0.0, -0.95),
		Vector3(1.15, 0.0, -0.95),
		Vector3(-1.15, 0.0, 0.95),
		Vector3(1.15, 0.0, 0.95),
	]
	for i in range(post_offsets.size()):
		_add_box(tower, "%sPost%d" % [tower_name, i], post_offsets[i] + Vector3.UP * 1.55, Vector3(0.18, 3.1, 0.18), mats["wood"], 0.0, false)
	_add_box(tower, "%sPlatform" % tower_name, Vector3(0.0, 3.05, 0.0), Vector3(2.8, 0.24, 2.35), mats["wood"], 0.0, false)
	_add_box(tower, "%sCabinBack" % tower_name, Vector3(0.0, 3.72, 0.82), Vector3(2.55, 1.15, 0.18), mats["wood"], 0.0, false)
	_add_box(tower, "%sCabinLeft" % tower_name, Vector3(-1.23, 3.62, -0.1), Vector3(0.14, 0.9, 1.72), mats["wood"], 0.0, false)
	_add_box(tower, "%sCabinRight" % tower_name, Vector3(1.23, 3.62, -0.1), Vector3(0.14, 0.9, 1.72), mats["wood"], 0.0, false)
	_add_box(tower, "%sRoof" % tower_name, Vector3(0.0, 4.45, 0.0), Vector3(3.15, 0.18, 2.7), mats["roof"], 0.0, false)
	_add_box(tower, "%sFrontRail" % tower_name, Vector3(0.0, 3.72, -1.05), Vector3(2.7, 0.12, 0.12), mats["dark_metal"], 0.0, false)
	_add_box(tower, "%sLeftRail" % tower_name, Vector3(-1.28, 3.72, 0.0), Vector3(0.12, 0.12, 2.1), mats["dark_metal"], 0.0, false)
	_add_box(tower, "%sRightRail" % tower_name, Vector3(1.28, 3.72, 0.0), Vector3(0.12, 0.12, 2.1), mats["dark_metal"], 0.0, false)
	for step in range(5):
		_add_box(tower, "%sLadderStep%d" % [tower_name, step], Vector3(-1.48, 0.65 + step * 0.45, 0.82), Vector3(0.55, 0.06, 0.07), mats["metal"], 0.0, false)

	var spotlight := Node3D.new()
	spotlight.name = "%sSearchlight" % tower_name
	spotlight.position = Vector3(0.0, 3.76, -1.22)
	var script := load("res://entities/props/rotating_spotlight.gd")
	if script != null:
		spotlight.set_script(script)
	tower.add_child(spotlight)
	_add_box(spotlight, "%sSearchlightBody" % tower_name, Vector3(0.0, 0.0, -0.18), Vector3(0.58, 0.32, 0.44), mats["dark_metal"], 0.0, false)
	_add_box(spotlight, "%sSearchlightLens" % tower_name, Vector3(0.0, 0.0, -0.43), Vector3(0.42, 0.22, 0.05), mats["lamp_glass"], 0.0, false)
	var lamp := SpotLight3D.new()
	lamp.name = "Lamp"
	lamp.light_color = Color(1.0, 0.82, 0.45)
	lamp.light_energy = 3.0
	lamp.spot_range = 28.0
	lamp.spot_angle = 26.0
	lamp.shadow_enabled = true
	lamp.rotation_degrees.x = -32.0
	spotlight.add_child(lamp)

	if military_collision_enabled:
		_add_collision_box(root, "%sFootprintCollision" % tower_name, pos + Vector3.UP * 1.0, Vector3(2.8, 2.0, 2.4), yaw)
	_register_cover_zone(pos, 3.1, 0.55)


func _create_generator(root: Node3D, pos: Vector3, yaw: float, mats: Dictionary, generator_name: String) -> void:
	var generator := Node3D.new()
	generator.name = generator_name
	generator.position = pos
	generator.rotation.y = yaw
	root.add_child(generator)

	_add_box(generator, "%sMain" % generator_name, Vector3(0.0, 0.62, 0.0), Vector3(2.8, 1.15, 1.55), mats["generator_green"], 0.0, false)
	_add_box(generator, "%sTop" % generator_name, Vector3(0.0, 1.28, 0.0), Vector3(2.55, 0.22, 1.32), mats["metal"], 0.0, false)
	_add_box(generator, "%sVentA" % generator_name, Vector3(-0.72, 0.68, -0.8), Vector3(0.12, 0.56, 0.06), mats["dark_metal"], 0.0, false)
	_add_box(generator, "%sVentB" % generator_name, Vector3(-0.28, 0.68, -0.8), Vector3(0.12, 0.56, 0.06), mats["dark_metal"], 0.0, false)
	_add_box(generator, "%sVentC" % generator_name, Vector3(0.16, 0.68, -0.8), Vector3(0.12, 0.56, 0.06), mats["dark_metal"], 0.0, false)
	_add_box(generator, "%sWarningStripeA" % generator_name, Vector3(1.16, 0.68, -0.81), Vector3(0.5, 0.12, 0.07), mats["warning_yellow"], deg_to_rad(18.0), false)
	_add_box(generator, "%sWarningStripeB" % generator_name, Vector3(0.72, 0.68, -0.81), Vector3(0.5, 0.12, 0.07), mats["warning_yellow"], deg_to_rad(18.0), false)
	_add_vertical_cylinder(generator, "%sExhaustPipe" % generator_name, Vector3(1.25, 1.22, 0.45), 0.83, 0.08, mats["dark_metal"], 10)
	var status_light := OmniLight3D.new()
	status_light.name = "StatusLight"
	status_light.light_color = Color(0.1, 1.0, 0.35)
	status_light.light_energy = 0.7
	status_light.omni_range = 4.0
	status_light.position = Vector3(-1.22, 1.25, -0.58)
	generator.add_child(status_light)

	if military_collision_enabled:
		_add_collision_box(root, "%sCollision" % generator_name, pos + Vector3.UP * 0.7, Vector3(3.0, 1.4, 1.8), yaw)
	_register_cover_zone(pos, 3.0, 0.58)


func _create_gate(root: Node3D, pos: Vector3, yaw: float, mats: Dictionary, gate_name: String) -> void:
	var gate := Node3D.new()
	gate.name = gate_name
	gate.position = pos
	gate.rotation.y = yaw
	root.add_child(gate)

	_add_box(gate, "%sLeftPost" % gate_name, Vector3(-2.45, 1.25, 0.0), Vector3(0.36, 2.5, 0.36), mats["dark_metal"], 0.0, false)
	_add_box(gate, "%sRightPost" % gate_name, Vector3(2.45, 1.25, 0.0), Vector3(0.36, 2.5, 0.36), mats["dark_metal"], 0.0, false)
	_add_box(gate, "%sTopBeam" % gate_name, Vector3(0.0, 2.55, 0.0), Vector3(5.2, 0.18, 0.18), mats["metal"], 0.0, false)
	_add_box(gate, "%sLeftOpenArm" % gate_name, Vector3(-3.55, 1.16, -0.55), Vector3(2.55, 0.18, 0.18), mats["paint_white"], deg_to_rad(-28.0), false)
	_add_box(gate, "%sRightOpenArm" % gate_name, Vector3(3.55, 1.16, -0.55), Vector3(2.55, 0.18, 0.18), mats["paint_white"], deg_to_rad(28.0), false)
	for i in range(4):
		_add_box(gate, "%sTopWire%d" % [gate_name, i], Vector3(-1.8 + float(i) * 1.2, 2.9, 0.0), Vector3(0.08, 0.42, 0.08), mats["wire"], deg_to_rad(24.0), false)

	var basis := Basis(Vector3.UP, yaw)
	_create_warning_sign(root, _military_land_point(pos + basis * Vector3(0.0, 0.0, -1.35)), yaw, mats, "STOP", "%sStopSign" % gate_name)
	if military_collision_enabled:
		_add_collision_box(root, "%sLeftPostCollision" % gate_name, pos + basis * Vector3(-2.45, 1.25, 0.0), Vector3(0.55, 2.5, 0.55), yaw)
		_add_collision_box(root, "%sRightPostCollision" % gate_name, pos + basis * Vector3(2.45, 1.25, 0.0), Vector3(0.55, 2.5, 0.55), yaw)
	_register_cover_zone(pos + basis * Vector3(-2.45, 0.0, 0.0), 1.7, 0.64)
	_register_cover_zone(pos + basis * Vector3(2.45, 0.0, 0.0), 1.7, 0.64)


func _create_alarm_post(root: Node3D, pos: Vector3, yaw: float, mats: Dictionary, alarm_name: String) -> void:
	var alarm := Area3D.new()
	alarm.name = alarm_name
	var script := load("res://entities/props/alarm_trigger.gd")
	if script != null:
		alarm.set_script(script)
	alarm.collision_layer = 0
	alarm.collision_mask = 1 << 1
	alarm.position = pos
	alarm.rotation.y = yaw
	root.add_child(alarm)
	if alarm.has_method("configure"):
		alarm.call("configure", 4.5, 34.0, 5.0)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 4.5
	shape.shape = sphere
	shape.position.y = 1.0
	alarm.add_child(shape)

	_add_vertical_cylinder(alarm, "Pole", Vector3.ZERO, 2.6, 0.09, mats["dark_metal"], 12)
	_add_box(alarm, "ControlBox", Vector3(0.0, 1.0, -0.12), Vector3(0.42, 0.56, 0.18), mats["metal"], 0.0, false)
	_add_box(alarm, "Horn", Vector3(0.0, 2.15, -0.28), Vector3(0.58, 0.28, 0.34), mats["dark_metal"], 0.0, false)
	var beacon := MeshInstance3D.new()
	beacon.name = "Beacon"
	var beacon_mesh := SphereMesh.new()
	beacon_mesh.radius = 0.22
	beacon_mesh.height = 0.28
	beacon.mesh = beacon_mesh
	beacon.position = Vector3(0.0, 2.75, 0.0)
	beacon.material_override = mats["beacon"]
	alarm.add_child(beacon)
	var light := OmniLight3D.new()
	light.name = "AlarmLight"
	light.light_color = Color(1.0, 0.1, 0.05)
	light.light_energy = 0.45
	light.omni_range = 5.0
	light.position = Vector3(0.0, 2.75, 0.0)
	alarm.add_child(light)
	_add_collision_box(root, "%sPoleCollision" % alarm_name, pos + Vector3.UP * 1.3, Vector3(0.35, 2.6, 0.35), yaw)


func _create_warning_sign(root: Node3D, pos: Vector3, yaw: float, mats: Dictionary, text: String, sign_name: String) -> void:
	_add_vertical_cylinder(root, "%sPole" % sign_name, pos, 1.35, 0.045, mats["dark_metal"], 8)
	_add_box(root, "%sPlate" % sign_name, pos + Vector3.UP * 1.48, Vector3(1.12, 0.52, 0.06), mats["sign"], yaw, false)
	var label := Label3D.new()
	label.name = "%sLabel" % sign_name
	label.text = text
	label.font_size = 28
	label.pixel_size = 0.015
	label.modulate = Color(0.92, 0.08, 0.06)
	label.position = pos + Vector3.UP * 1.49 + Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0, -0.035)
	label.rotation.y = yaw
	root.add_child(label)


func _add_box(parent: Node, node_name: String, pos: Vector3, size: Vector3, mat: Material, yaw: float, collision: bool) -> MeshInstance3D:
	var holder: Node3D
	if collision:
		var body := StaticBody3D.new()
		body.collision_layer = OBSTACLE_COLLISION_LAYER
		body.collision_mask = 0
		holder = body
		_register_military_blocker(pos, size, yaw)
	else:
		holder = Node3D.new()
	holder.name = node_name
	holder.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	parent.add_child(holder)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = mat
	holder.add_child(mesh_instance)
	if collision:
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		holder.add_child(col)
	return mesh_instance


func _add_collision_box(parent: Node, node_name: String, pos: Vector3, size: Vector3, yaw: float) -> void:
	_register_military_blocker(pos, size, yaw)
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = OBSTACLE_COLLISION_LAYER
	body.collision_mask = 0
	body.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	parent.add_child(body)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)


func _register_military_blocker(pos: Vector3, size: Vector3, yaw: float) -> void:
	_military_blockers.append({
		"center": Vector2(pos.x, pos.z),
		"half": Vector2(size.x * 0.5, size.z * 0.5),
		"yaw": yaw,
	})


func _register_cover_zone(pos: Vector3, radius: float, multiplier: float) -> void:
	_cover_zones.append({
		"center": Vector2(pos.x, pos.z),
		"radius": radius,
		"multiplier": multiplier,
	})


func _add_vertical_cylinder(parent: Node, node_name: String, bottom_pos: Vector3, height: float, radius: float, mat: Material, sides: int) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = sides
	mesh_instance.mesh = mesh
	mesh_instance.material_override = mat
	mesh_instance.position = bottom_pos + Vector3.UP * (height * 0.5)
	parent.add_child(mesh_instance)
	return mesh_instance


func _add_cylinder_between(parent: Node, node_name: String, a: Vector3, b: Vector3, radius: float, mat: Material, sides: int) -> MeshInstance3D:
	var len := a.distance_to(b)
	if len < 0.05:
		return null
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = len
	mesh.radial_segments = sides
	mesh_instance.mesh = mesh
	mesh_instance.material_override = mat
	parent.add_child(mesh_instance)
	var mid := (a + b) * 0.5
	mesh_instance.look_at_from_position(mid, b, Vector3.UP)
	mesh_instance.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	return mesh_instance


func _add_capsule_between(parent: Node, node_name: String, a: Vector3, b: Vector3, radius: float, mat: Material) -> MeshInstance3D:
	var len := a.distance_to(b)
	if len < 0.05:
		return null
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = len + radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 4
	mesh_instance.mesh = mesh
	mesh_instance.material_override = mat
	parent.add_child(mesh_instance)
	var mid := (a + b) * 0.5
	mesh_instance.look_at_from_position(mid, b, Vector3.UP)
	mesh_instance.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	return mesh_instance


func _add_barbed_loop(parent: Node, node_name: String, pos: Vector3, yaw: float, mat: Material) -> MeshInstance3D:
	var loop := MeshInstance3D.new()
	loop.name = node_name
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.18
	mesh.outer_radius = 0.22
	loop.mesh = mesh
	loop.material_override = mat
	loop.transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, PI * 0.5), pos)
	parent.add_child(loop)
	return loop
