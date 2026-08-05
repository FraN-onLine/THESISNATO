extends CharacterBody3D
## Handles joystick movement and physical movement tracking for VR.

@export var move_speed: float = 3.0
@export var deadzone: float = 0.1

@onready var xr_origin: XROrigin3D = $XROrigin3D
@onready var left_controller: XRController3D = $XROrigin3D/XRController_left
@onready var right_controller: XRController3D = $XROrigin3D/XRController_right

var _origin_initial_x: float = 0.0
var _origin_initial_z: float = 0.0

func _ready() -> void:
	if xr_origin:
		_origin_initial_x = xr_origin.position.x
		_origin_initial_z = xr_origin.position.z

func _physics_process(delta: float) -> void:
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

	# Use move_and_slide so the body collides with the CSG walls.
	move_and_slide()
