class_name CameraRig
extends Node3D
## Camera RTS: WASD per muoversi, Q/E per ruotare, rotella per lo zoom,
## tasto centrale trascinato per ruotare. Il pitch cambia con lo zoom.
## Usa il tempo reale, quindi funziona anche in pausa.

const MIN_DIST := 6.0
const MAX_DIST := 170.0
const LIMIT := 200.0

var cam: Camera3D
var yaw := 0.0
var dist := 75.0
var follow: Regiment = null
var _target_dist := 75.0
var _rotating := false


func _ready() -> void:
	cam = Camera3D.new()
	cam.far = 1500.0
	cam.fov = 60.0
	add_child(cam)
	_apply()


func focus_on(p: Vector3) -> void:
	position = Vector3(p.x, 0.0, p.z)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_dist = maxf(MIN_DIST, _target_dist * 0.88)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_dist = minf(MAX_DIST, _target_dist * 1.12)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_rotating = mb.pressed
	elif event is InputEventMouseMotion and _rotating:
		yaw -= (event as InputEventMouseMotion).relative.x * 0.005


func _process(delta: float) -> void:
	var dt := minf(delta, 0.1)
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move += fwd
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move -= fwd
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move += right
	if Input.is_key_pressed(KEY_A) and not Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_LEFT):
		move -= right
	if Input.is_key_pressed(KEY_Q):
		yaw += 1.6 * dt
	if Input.is_key_pressed(KEY_E):
		yaw -= 1.6 * dt
	if move != Vector3.ZERO:
		follow = null
		var spd := 15.0 + dist * 0.9
		if Input.is_key_pressed(KEY_SHIFT):
			spd *= 2.0
		position += move.normalized() * spd * dt
	if follow != null:
		if follow.is_on_field():
			position = position.lerp(Regiment._flat(follow.mid()), minf(1.0, dt * 4.0))
		else:
			follow = null
	position.x = clampf(position.x, -LIMIT, LIMIT)
	position.z = clampf(position.z, -LIMIT, LIMIT)
	dist = lerpf(dist, _target_dist, minf(1.0, dt * 10.0))
	_apply()


func _apply() -> void:
	var t := inverse_lerp(MIN_DIST, MAX_DIST, dist)
	var pitch := lerpf(deg_to_rad(-14.0), deg_to_rad(-62.0), pow(t, 0.6))
	var b := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	cam.transform = Transform3D(b, Vector3(0.0, 1.5, 0.0) + b.z * dist)
