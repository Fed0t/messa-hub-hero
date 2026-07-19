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

@export_group("")
## Bifează pentru a regenera totul cu setările curente.
@export var regenerate := false: set = _set_regenerate

var _noise := FastNoiseLite.new()
var _river: Curve3D = null


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


func generate() -> void:
	_configure_noise()
	_ensure_river()
	_build_terrain()
	_build_water()
	_build_grass()
	_snap_trees()
	_place_bridge()
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
	if not has_node("Bridge") or _river == null or _river.point_count < 2:
		return
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

	# model 3D de pod (glb) — îl așezăm pe râu, dacă nu e pe control manual
	if has_node("BridgeModel") and not bridge_manual:
		var bm := get_node("BridgeModel") as Node3D
		var s := bridge_scale
		# rotim modelul 90° ca axa lui lungă (Z) să treacă de-a curmezișul râului
		var mb := basis * Basis(Vector3.UP, PI * 0.5)
		bm.transform = Transform3D(mb.scaled(Vector3(s, s, s)), Vector3(p.x, water_level, p.z))
