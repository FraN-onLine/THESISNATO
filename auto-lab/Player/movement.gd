extends CharacterBody3D
## Handles player movement.
## - VR: joystick (thumbstick) locomotion + physical room-scale tracking.
## - Desktop (no headset): WASD walk with mouse look (right-button drag or
##   Q/E / arrow keys), and free mouse cursor for clicking world UI panels.

@export var move_speed: float = 3.0
@export var deadzone: float = 0.1
@export var look_sensitivity: float = 0.0035
@export var turn_speed: float = 2.2
@export var eye_height: float = 1.7

@onready var xr_origin: XROrigin3D = $XROrigin3D
@onready var left_controller: XRController3D = $XROrigin3D/XRController_left
@onready var right_controller: XRController3D = $XROrigin3D/XRController_right

var desktop_camera: Camera3D

var _origin_initial_x: float = 0.0
var _origin_initial_z: float = 0.0
var _yaw := 0.0
var _pitch := 0.0

func _ready() -> void:
	if InputMode.is_desktop():
		_setup_desktop_camera()
	elif xr_origin:
		_origin_initial_x = xr_origin.position.x
		_origin_initial_z = xr_origin.position.z

func _is_desktop() -> bool:
	return InputMode.is_desktop()

func _setup_desktop_camera() -> void:
	# In desktop mode the XR origin + hands are meaningless; hide them and give
	# the body a normal first-person camera.
	if xr_origin:
		xr_origin.visible = false
	var cam := Camera3D.new()
	cam.name = "DesktopCamera3D"
	cam.position = Vector3(0, eye_height, 0)
	cam.current = true
	add_child(cam)
	desktop_camera = cam

func _unhandled_input(event: InputEvent) -> void:
	if not _is_desktop():
		return
	# Right-drag to look around (in addition to Q/E and arrow keys).
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_yaw -= event.relative.x * look_sensitivity
		_pitch -= event.relative.y * look_sensitivity
		_pitch = clampf(_pitch, deg_to_rad(-89.0), deg_to_rad(89.0))
		_apply_camera_rotation()

func _physics_process(delta: float) -> void:
	if _is_desktop():
		_process_desktop(delta)
	else:
		_process_vr(delta)
	move_and_slide()

# ===== DESKTOP (mouse + WASD) =====

func _process_desktop(delta: float) -> void:
	if desktop_camera == null:
		return

	# Turning via Q/E keys and arrow keys.
	var turn := 0.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_Q):
		turn += 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_E):
		turn -= 1.0
	if turn != 0.0:
		_yaw += turn * turn_speed * delta
		_apply_camera_rotation()

	# WASD movement relative to the camera's yaw only (pitch is ignored for the
	# ground-plane direction).
	var input_dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		input_dir.y -= 1.0
	if Input.is_key_pressed(KEY_S):
		input_dir.y += 1.0
	if Input.is_key_pressed(KEY_A):
		input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		input_dir.x += 1.0

	if input_dir.length() > 0.0:
		input_dir = input_dir.normalized()
		var basis := desktop_camera.global_transform.basis
		var direction := basis * Vector3(input_dir.x, 0.0, input_dir.y)
		direction.y = 0.0
		direction = direction.normalized()
		velocity = Vector3(direction.x, 0.0, direction.z) * move_speed
	else:
		velocity = Vector3.ZERO

func _apply_camera_rotation() -> void:
	if desktop_camera:
		desktop_camera.rotation = Vector3(_pitch, _yaw, 0.0)

# ===== VR (joystick + physical tracking) =====

func _process_vr(_delta: float) -> void:
	# --- Joystick movement (both hands) ---
	var move_input := Vector2.ZERO

	if left_controller and left_controller.get_is_active():
		move_input += left_controller.get_vector2("primary")
	if right_controller and right_controller.get_is_active():
		move_input += right_controller.get_vector2("primary")

	if move_input.length() > 1.0:
		move_input = move_input.normalized()

	var camera: XRCamera3D = xr_origin.get_node("XRCamera3D") if xr_origin else null
	if camera and move_input.length() > deadzone:
		var camera_basis := camera.global_transform.basis
		var direction := camera_basis * Vector3(move_input.x, 0, -move_input.y)
		direction.y = 0.0
		direction = direction.normalized()
		velocity = Vector3(direction.x, 0.0, direction.z) * move_speed
	else:
		velocity = Vector3.ZERO

	# --- Follow physical movement ---
	# If the player physically walks, the XR origin drifts from the body's center.
	# Move the body to follow and reset the origin so the player can walk freely.
	if xr_origin:
		var origin_offset := xr_origin.position
		var physical_delta: Vector3 = Vector3(
			origin_offset.x - _origin_initial_x,
			0.0,
			origin_offset.z - _origin_initial_z
		)
		global_position.x += physical_delta.x
		global_position.z += physical_delta.z
		xr_origin.position.x = _origin_initial_x
		xr_origin.position.z = _origin_initial_z
