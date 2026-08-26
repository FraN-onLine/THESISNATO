extends Node3D
## Billboard presentation wrapper for the reusable AutomataWorkshop Control.

signal evaluated(correct: bool, message: String)

@onready var viewport: SubViewport = $SubViewport
@onready var sprite: Sprite3D = $Billboard
@onready var builder: Control = $SubViewport/Builder

var _last_mouse_pos := Vector2(-1, -1)
var _pressed := false
var _mouse_down := false

func _ready() -> void:
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sprite.texture = viewport.get_texture()
	sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	builder.evaluated.connect(_on_builder_evaluated)

func _on_builder_evaluated(correct: bool, message: String) -> void:
	# The host lesson may connect to this signal on the wrapper instance.
	evaluated.emit(correct, message)
	builder.set_meta("last_evaluation", {"correct": correct, "message": message})

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_mouse_down = event.pressed

func _process(_delta: float) -> void:
	if InputMode.is_desktop():
		_update_desktop_pointer()
	else:
		_update_vr_pointer()

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
	elif (not valid or not down) and _pressed:
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.pressed = false
		release.position = point
		release.global_position = point
		viewport.push_input(release)
		_pressed = false

func _update_vr_pointer() -> void:
	for controller in get_tree().get_nodes_in_group("xr_controller"):
		if not controller is XRController3D or not controller.get_is_active():
			continue
		var result := _ray_intersect_sprite(controller.global_position, -controller.global_transform.basis.z)
		if result.is_empty():
			continue
		var point := Vector2(result["uv"].x * viewport.size.x, result["uv"].y * viewport.size.y)
		_send_pointer(point, true, controller.is_button_pressed("trigger_click"))
		return
	_send_pointer(Vector2(-1, -1), false, false)

func _ray_intersect_sprite(origin: Vector3, direction: Vector3) -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	if camera == null or sprite.texture == null:
		return {}
	var normal := (camera.global_position - sprite.global_position).normalized()
	var denominator := normal.dot(direction)
	if absf(denominator) < 0.0001:
		return {}
	var distance := (sprite.global_position - origin).dot(normal) / denominator
	if distance < 0.0:
		return {}
	var hit := origin + direction * distance
	var offset := hit - sprite.global_position
	var camera_basis := camera.global_transform.basis
	var width := sprite.texture.get_size().x * sprite.pixel_size
	var height := sprite.texture.get_size().y * sprite.pixel_size
	var x := offset.dot(camera_basis.x)
	var y := offset.dot(camera_basis.y)
	if absf(x) > width * 0.5 or absf(y) > height * 0.5:
		return {}
	return {"uv": Vector2(x / width + 0.5, 0.5 - y / height)}
