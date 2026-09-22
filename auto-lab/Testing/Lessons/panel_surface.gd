extends RefCounted
## Shared input bridge for every 3D board/panel that shows a SubViewport on a
## Sprite3D (the automata whiteboard, the test panel, the lesson panel).
##
## It replaces the pointer code that used to be copy-pasted into each scene:
##   * desktop: the OS cursor is ray-cast onto the flat surface,
##   * VR: each controller gets a visible laser and the trigger acts as a click,
##   * both: a release is re-delivered at the press origin when the pointer
##     drifted less than CLICK_SLOP pixels, so wobble never cancels a click.
##
## WALL RULE: a board mounted on a wall must be FLAT. `make_flat()` disables
## billboarding so the board keeps the orientation the level designer gave it
## (facing +Z, flush with the wall) instead of turning to stare at the player.
## Only floating, free-standing panels should call `face_player()`.

const CLICK_SLOP := 92.0

var host: Node3D = null
var sprite: Sprite3D = null
var viewport: SubViewport = null
var active := true
## Optional callable(event) -> void, run before pointer translation (used to
## forward physical keyboard typing into the panel's text fields).
var keyboard_filter: Callable = Callable()

var _last_mouse_pos := Vector2(-1, -1)
var _pressed := false
var _mouse_down := false
var _press_start := Vector2(-1, -1)
var _lasers := {}

func setup(host_node: Node3D, sprite_node: Sprite3D, viewport_node: SubViewport) -> void:
	host = host_node
	sprite = sprite_node
	viewport = viewport_node

func set_active(value: bool) -> void:
	active = value
	if not value:
		_pressed = false
		_mouse_down = false
		_press_start = Vector2(-1, -1)
		_last_mouse_pos = Vector2(-1, -1)

## Call from the host's _input() so desktop clicks/keyboard reach the panel.
func handle_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_mouse_down = event.pressed
	if not keyboard_filter.is_null() and keyboard_filter.is_valid():
		keyboard_filter.call(event)

## Call from the host's _process().
func process_pointer() -> void:
	if not active or viewport == null or sprite == null or host == null:
		return
	if InputMode.is_desktop():
		_update_desktop_pointer()
	else:
		_update_vr_pointer()

# ===== Flat vs facing the player ==========================================

## Keep the designer's orientation: flush against the wall it is mounted on.
static func make_flat(target: Sprite3D) -> void:
	if target == null:
		return
	target.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	target.axis = Vector3.AXIS_Z

## Free-standing panel that turns to face the player.
static func face_player(target: Sprite3D) -> void:
	if target == null:
		return
	target.billboard = BaseMaterial3D.BILLBOARD_ENABLED

## True when the sprite is currently rendered flat (no billboarding).
static func is_flat(target: Sprite3D) -> bool:
	return target != null and target.billboard == BaseMaterial3D.BILLBOARD_DISABLED

# ===== Pointer translation =================================================

func _update_desktop_pointer() -> void:
	var view := host.get_viewport()
	var camera: Camera3D = view.get_camera_3d() if view != null else null
	var uv := Vector2(-1, -1)
	if camera != null and sprite.texture != null:
		var mouse := view.get_mouse_position()
		var result := ray_intersect_sprite(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
		if not result.is_empty():
			uv = Vector2(result["uv"].x * viewport.size.x, result["uv"].y * viewport.size.y)
	_send_pointer(uv, uv != Vector2(-1, -1), _mouse_down)

func _update_vr_pointer() -> void:
	var hit_any := false
	var active_controller: XRController3D = null
	var active_result: Dictionary = {}
	for controller in host.get_tree().get_nodes_in_group("xr_controller"):
		if not controller is XRController3D:
			continue
		var laser := _ensure_laser(controller)
		if not controller.get_is_active():
			laser.visible = false
			continue
		var result := ray_intersect_sprite(controller.global_position, -controller.global_transform.basis.z)
		if result.is_empty():
			laser.visible = false
			continue
		laser.visible = true
		var distance: float = controller.global_position.distance_to(result["hit"])
		laser.position = Vector3(0, 0, -distance * 0.5)
		laser.scale = Vector3(1, 1, distance)
		if not hit_any:
			hit_any = true
			active_controller = controller
			active_result = result
	if hit_any and active_controller != null:
		var mouse_pos := Vector2(active_result["uv"].x * viewport.size.x, active_result["uv"].y * viewport.size.y)
		var was_pressed := _pressed
		_send_pointer(mouse_pos, true, active_controller.is_button_pressed("trigger_click"))
		if _pressed and not was_pressed:
			active_controller.trigger_haptic_pulse("haptic", 0.0, 0.4, 0.07, 0)
	else:
		_send_pointer(Vector2(-1, -1), false, false)

func _send_pointer(uv: Vector2, valid: bool, down: bool) -> void:
	if valid and uv != _last_mouse_pos:
		var motion := InputEventMouseMotion.new()
		motion.position = uv
		motion.global_position = uv
		viewport.push_input(motion)
		_last_mouse_pos = uv
	if valid and down and not _pressed:
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = uv
		press.global_position = uv
		viewport.push_input(press)
		_pressed = true
		_press_start = uv
	elif (not down or not valid) and _pressed:
		# Pin the release to the press origin when the pointer barely drifted,
		# so an unsteady hand still completes the click it started.
		var release_point := _press_start
		if valid and _press_start != Vector2(-1, -1) and uv.distance_to(_press_start) > CLICK_SLOP:
			release_point = uv
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.pressed = false
		release.position = release_point
		release.global_position = release_point
		viewport.push_input(release)
		_pressed = false
		_press_start = Vector2(-1, -1)
	if not valid and not down and _last_mouse_pos != Vector2(-1, -1):
		var leave := InputEventMouseMotion.new()
		leave.position = Vector2(-1, -1)
		leave.global_position = Vector2(-1, -1)
		viewport.push_input(leave)
		_last_mouse_pos = Vector2(-1, -1)

## Straight-line intersection between a ray and the flat surface.
func ray_intersect_sprite(origin: Vector3, direction: Vector3) -> Dictionary:
	if sprite == null or sprite.texture == null:
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

