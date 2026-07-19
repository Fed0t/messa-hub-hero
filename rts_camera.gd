extends Node3D

## Cameră tactică stil Commandos 2 / RTS.
## Se atașează pe un pivot (Node3D) care are un Camera3D copil.
## Pivotul se plimbă pe sol (pan), se rotește (yaw), iar camera copil
## stă înclinată deasupra lui; zoom-ul apropie/depărtează camera.
##
## Mouse liber. Pan: WASD / săgeți / marginile ecranului.
## Rotire: Q/E sau ține apăsat butonul din mijloc și trage.
## Zoom: rotița mouse-ului.

@export var pan_speed := 16.0
@export var edge_pan := true
@export var edge_margin := 26.0
@export var rotate_speed := 2.0
@export var mouse_rotate_sensitivity := 0.006
@export var zoom_step := 0.22
@export var min_zoom := 4.0
@export var max_zoom := 60.0
@export_range(20.0, 85.0) var pitch_deg := 45.0

@onready var _cam: Camera3D = $Camera3D

var _zoom := 20.0
var _mmb_held := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_update_camera()


func _update_camera() -> void:
	var pitch := deg_to_rad(pitch_deg)
	# camera plasată în spate + deasupra pivotului, privind în jos spre el
	_cam.position = Vector3(0.0, sin(pitch), cos(pitch)) * _zoom
	_cam.rotation = Vector3(-pitch, 0.0, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = clampf(_zoom * (1.0 - zoom_step), min_zoom, max_zoom)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = clampf(_zoom * (1.0 + zoom_step), min_zoom, max_zoom)
			_update_camera()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_mmb_held = event.pressed

	if event is InputEventMouseMotion and _mmb_held:
		rotation.y -= event.relative.x * mouse_rotate_sensitivity


func _process(delta: float) -> void:
	# --- Rotire cu Q/E ---
	var rot := 0.0
	if Input.is_physical_key_pressed(KEY_Q):
		rot += 1.0
	if Input.is_physical_key_pressed(KEY_E):
		rot -= 1.0
	rotation.y += rot * rotate_speed * delta

	# --- Pan (deplasare pe sol) ---
	var input := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		input.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		input.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		input.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		input.x += 1.0

	if edge_pan:
		input += _edge_pan_input()

	if input == Vector2.ZERO:
		return

	input = input.limit_length(1.0)
	# direcții orizontale relative la rotația pivotului
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := global_transform.basis.x
	right.y = 0.0
	right = right.normalized()

	# viteza crește ușor când ești depărtat (zoom mare)
	var speed := pan_speed * (_zoom / 24.0)
	position += (right * input.x + forward * input.y) * speed * delta


func _edge_pan_input() -> Vector2:
	var vp := get_viewport()
	var mouse := vp.get_mouse_position()
	var size := vp.get_visible_rect().size
	# ignoră dacă mouse-ul e în afara ferestrei
	if mouse.x < 0.0 or mouse.y < 0.0 or mouse.x > size.x or mouse.y > size.y:
		return Vector2.ZERO
	var e := Vector2.ZERO
	if mouse.x < edge_margin:
		e.x -= 1.0
	elif mouse.x > size.x - edge_margin:
		e.x += 1.0
	if mouse.y < edge_margin:
		e.y -= 1.0
	elif mouse.y > size.y - edge_margin:
		e.y += 1.0
	return e
