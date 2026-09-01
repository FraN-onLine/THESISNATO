extends Node3D
## Billboard presentation wrapper for the reusable AutomataWorkshop Control.
##
## Translates real input into SubViewport mouse/keyboard events for BOTH control
## styles:
##   - Desktop (no headset): the OS mouse cursor is ray-cast onto the board and
##     the physical keyboard is forwarded so text fields stay typeable.
##   - VR: the controllers get visible laser pointers; the trigger acts as a
##     mouse click with haptic feedback.
##
## Buttons stay easy to toggle with a cursor or laser: while a press is held the
## release is re-delivered at the starting spot (within a small slop distance),
## so unavoidable pointer wobble never cancels a click the player intended.

signal evaluated(correct: bool, message: String)

@onready var viewport: SubViewport = $SubViewport
@onready var sprite: Sprite3D = $Billboard
@onready var builder: Control = $SubViewport/Builder

## Re-deliver the release at the original press point when the pointer drifted
## less than this many viewport pixels, making buttons click reliably.
const CLICK_SLOP := 72.0

var _last_mouse_pos := Vector2(-1, -1)
var _pressed := false
var _mouse_down := false
var _press_start := Vector2(-1, -1)
var _lasers := {}  # XRController3D -> MeshInstance3D

func set_active(active: bool) -> void:
	visible = active
	set_process(active)
	if not active:
		_pressed = false
		_mouse_down = false
		_press_start = Vector2(-1, -1)
		_last_mouse_pos = Vector2(-1, -1)

func _ready() -> void:
	if InputMode.is_desktop():
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sprite.texture = viewport.get_texture()
	sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	builder.evaluated.connect(_on_builder_evaluated)
	set_active(visible)

func _on_builder_evaluated(correct: bool, message: String) -> void:
	evaluated.emit(correct, message)
	builder.set_meta("last_evaluation", {"correct": correct, "message": message})

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_mouse_down = event.pressed
	# On PC the workshop controls live inside a SubViewport, so physical
	# keyboard presses must be forwarded while the simulate field is focused.
	if InputMode.is_desktop() and event is InputEventKey:
		_forward_keyboard(event)

func _process(_delta: float) -> void:
	if InputMode.is_desktop():
		Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	if InputMode.is_desktop():
		_update_desktop_pointer()
	else:
		_update_vr_pointer()

func _forward_keyboard(event: InputEventKey) -> void:
	var line: LineEdit = builder.get("input_line") if builder else null
	var keyboard_active: bool = builder.get("simulation_keyboard_active") if builder else false
	if line == null or not (line.has_focus() or keyboard_active):
		return
	if event.pressed and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
		builder.call("_simulate_input")
		get_viewport().set_input_as_handled()
		return
	viewport.push_input(event)

func _update_desktop_pointer() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null or sprite.texture == null:
		return
	var mouse := get_viewport().get_mouse_position()
	var result := _ray_intersect_sprite(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
	var point := Vector2(-1, -1)
	if not result.is_empty():
		point = Vector2(result["uv"].x * viewport.size.x, result["uv"].y * viewport.size.y)
	_send_pointer(point, point != Vector2(-1, -1), _mouse_down)

## Pushes motion + press/release mouse events into the workshop SubViewport.
## "down" is the held state of the left mouse button (desktop) or the trigger
## (VR). Releases are pinned to the press origin within CLICK_SLOP so buttons
## always complete; dragging past that distance still releases at the pointer.
func _send_pointer(point: Vector2, valid: bool, down: bool) -> void:
	if point != _last_mouse_pos:
		var motion := InputEventMouseMotion.new()
		motion.position = point
		motion.global_position = point
		viewport.push_input(motion)
		_last_mouse_pos = point
	if valid and down and not _pressed:
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = point
		press.global_position = point
		viewport.push_input(press)
		_pressed = true
		_press_start = point
	elif (not valid or not down) and _pressed:
		var release_point := point
		if _press_start != Vector2(-1, -1) and point.distance_to(_press_start) <= CLICK_SLOP:
			release_point = _press_start
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.pressed = false
		release.position = release_point
		release.global_position = release_point
		viewport.push_input(release)
		_pressed = false
		_press_start = Vector2(-1, -1)
	if not valid and not down:
		if builder.has_method("cancel_pointer_interaction"):
			builder.cancel_pointer_interaction()

func _update_vr_pointer() -> void:
	var hit_any := false
	var active_controller: XRController3D = null
	var active_result: Dictionary = {}
	for controller in get_tree().get_nodes_in_group("xr_controller"):
		if not controller is XRController3D:
			continue
		var laser := _ensure_laser(controller)
		if not controller.get_is_active():
			laser.visible = false
			continue
		var result := _ray_intersect_sprite(controller.global_position, -controller.global_transform.basis.z)
		if result.is_empty():
			laser.visible = false
			continue
		# Show the laser beam from the controller to the board.
		laser.visible = true
		var distance: float = controller.global_position.distance_to(result["hit"])
		laser.position = Vector3(0, 0, -distance * 0.5)
		laser.scale = Vector3(1, 1, distance)
		if not hit_any:
			hit_any = true
			active_controller = controller
			active_result = result
	if hit_any and active_controller:
		var mouse_pos := Vector2(active_result["uv"].x * viewport.size.x, active_result["uv"].y * viewport.size.y)
		var was_pressed := _pressed
		_send_pointer(mouse_pos, true, active_controller.is_button_pressed("trigger_click"))
		if _pressed and not was_pressed:
			active_controller.trigger_haptic_pulse("haptic", 0.0, 0.4, 0.07, 0)
	else:
		_send_pointer(Vector2(-1, -1), false, false)

func _ensure_laser(controller: XRController3D) -> MeshInstance3D:
	if _lasers.has(controller):
		return _lasers[controller]
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.008, 0.008, 1.0)
	mesh_instance.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.85, 1.0, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.85, 1.0)
	mat.emission_energy_multiplier = 2.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_instance.material_override = mat
	mesh_instance.visible = false
	controller.add_child(mesh_instance)
	_lasers[controller] = mesh_instance
	return mesh_instance

func _ray_intersect_sprite(origin: Vector3, direction: Vector3) -> Dictionary:
	if sprite.texture == null:
		return {}
	var board_basis := sprite.global_transform.basis
	var normal := board_basis.z.normalized()
	var denominator := normal.dot(direction)
	if absf(denominator) < 0.0001:
		return {}
	var distance := (sprite.global_position - origin).dot(normal) / denominator
	if distance < 0.0:
		return {}
	var hit := origin + direction * distance
	var offset := hit - sprite.global_position
	var width := sprite.texture.get_size().x * sprite.pixel_size
	var height := sprite.texture.get_size().y * sprite.pixel_size
	var x := offset.dot(board_basis.x)
	var y := offset.dot(board_basis.y)
	if absf(x) > width * 0.5 or absf(y) > height * 0.5:
		return {}
	return {"uv": Vector2(x / width + 0.5, 0.5 - y / height), "hit": hit}