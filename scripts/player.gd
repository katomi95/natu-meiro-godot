extends CharacterBody3D
## 一人称移動：WASD / マウス / Shiftで走る。

const WALK := 3.0
const RUN := 5.6
var eye := 1.55

signal stepped(running: bool)

var yaw := 0.0
var pitch := 0.0
var bob_t := 0.0
var locked := false
var step_acc := 0.0
var mouse_sens := 0.0022

@onready var cam: Camera3D = $Camera


func _ready() -> void:
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	$Collision.shape = cap
	$Collision.position = Vector3(0, 0.85, 0)
	cam.position = Vector3(0, eye, 0)
	floor_max_angle = deg_to_rad(40)
	floor_snap_length = 0.4


func set_look(y: float, p: float) -> void:
	yaw = y
	pitch = p
	_apply_look()


func _apply_look() -> void:
	rotation = Vector3(0, yaw, 0)
	cam.rotation = Vector3(pitch, 0, 0)


func _unhandled_input(event: InputEvent) -> void:
	if locked:
		return
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sens
		pitch = clampf(pitch - event.relative.y * mouse_sens, -1.35, 1.35)
		_apply_look()


func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if not locked:
		if Input.is_physical_key_pressed(KEY_W): input.y -= 1
		if Input.is_physical_key_pressed(KEY_S): input.y += 1
		if Input.is_physical_key_pressed(KEY_A): input.x -= 1
		if Input.is_physical_key_pressed(KEY_D): input.x += 1
	input = input.normalized()
	var running := Input.is_physical_key_pressed(KEY_SHIFT)
	var speed := RUN if running else WALK
	var dir := (transform.basis * Vector3(input.x, 0, input.y))
	var target := dir * speed
	var accel := 10.0 if input != Vector2.ZERO else 12.0
	velocity.x = lerpf(velocity.x, target.x, 1.0 - exp(-accel * delta))
	velocity.z = lerpf(velocity.z, target.z, 1.0 - exp(-accel * delta))
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = 0.0
	move_and_slide()
	# 歩行の揺れ
	var hspeed := Vector2(velocity.x, velocity.z).length()
	bob_t += delta * hspeed * (2.1 if running else 2.4)
	var amp := clampf(hspeed / RUN, 0.0, 1.0) * (0.05 if running else 0.035)
	cam.position = Vector3(sin(bob_t * 0.5) * amp * 0.6, eye + absf(sin(bob_t)) * amp, 0)
	# 足音
	if is_on_floor() and hspeed > 0.6:
		step_acc += hspeed * delta
		if step_acc > (0.78 if running else 0.62):
			step_acc = 0.0
			stepped.emit(running)
	var fov_target := 76.0 if running and hspeed > 3.5 else 72.0
	cam.fov = lerpf(cam.fov, fov_target, 1.0 - exp(-4.0 * delta))
