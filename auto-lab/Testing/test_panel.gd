extends Node3D
## Floating question panel used by the Pretest / Post-test room.
##
## Renders a question card into a SubViewport and projects it on a billboard
## Sprite3D that always faces the player. Supports three question kinds:
##   - mc      : classic multiple choice (options + correct index)
##   - image   : same as mc but with a diagram / image displayed above options
##   - handson : shows the task text and waits for the automata board to report
##               a correct build (the room controller submits it via the board).
##
## Input is translated from the desktop mouse (ray-cast onto the billboard) or
## the VR controller lasers into SubViewport mouse events, exactly like the main
## menu panel. Button releases are pinned to the press origin (CLICK_SLOP) so a
## unsteady cursor/laser can't cancel a click.

signal start_pressed
signal answer_selected(selected_index: int)
signal next_pressed
signal back_pressed

@onready var viewport: SubViewport = $SubViewport
@onready var sprite: Sprite3D = $Billboard

const CLICK_SLOP := 72.0

var _last_mouse_pos := Vector2(-1, -1)
var _pressed := false
var _mouse_down := false
var _press_start := Vector2(-1, -1)
var _lasers := {}  # XRController3D -> MeshInstance3D

# UI nodes (built in code)
var _root: Control
var _title_label: Label
var _progress_label: Label
var _question_label: Label
var _image_rect: TextureRect
var _options_box: VBoxContainer
var _hands_on_box: PanelContainer
var _hands_on_hint: Label
var _feedback_label: Label
var _back_button: Button
var _start_button: Button
var _next_button: Button

func set_active(active: bool) -> void:
	visible = active
	set_process(active)
	if not active:
		_pressed = false
		_mouse_down = false
		_press_start = Vector2(-1, -1)
		_last_mouse_pos = Vector2(-1, -1)

func set_mode(mode: String) -> void:
	_title_label.text = "PRE TEST" if mode == "pretest" else "POST TEST"

func _ready() -> void:
	if InputMode.is_desktop():
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sprite.texture = viewport.get_texture()
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_build_ui()
	set_active(visible)

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(_root)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(margin)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	margin.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.text = "PRE TEST"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 40)
	_title_label.add_theme_color_override("font_color", Color(0.5, 0.85, 1.0))
	vbox.add_child(_title_label)

	_progress_label = Label.new()
	_progress_label.text = ""
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_label.add_theme_font_size_override("font_size", 22)
	_progress_label.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	vbox.add_child(_progress_label)

	_question_label = Label.new()
	_question_label.text = ""
	_question_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_question_label.add_theme_font_size_override("font_size", 26)
	_question_label.add_theme_color_override("font_color", Color(1, 1, 1))
	vbox.add_child(_question_label)

	_image_rect = TextureRect.new()
	_image_rect.custom_minimum_size = Vector2(900, 420)
	_image_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_image_rect.visible = false
	_image_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vbox.add_child(_image_rect)

	_options_box = VBoxContainer.new()
	_options_box.add_theme_constant_override("separation", 10)
	vbox.add_child(_options_box)

	_hands_on_box = PanelContainer.new()
	var hands_style := StyleBoxFlat.new()
	hands_style.bg_color = Color(0.08, 0.18, 0.3, 0.95)
	hands_style.set_corner_radius_all(14)
	_hands_on_box.add_theme_stylebox_override("panel", hands_style)
	_hands_on_hint = Label.new()
	_hands_on_hint.text = ""
	_hands_on_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hands_on_hint.add_theme_font_size_override("font_size", 22)
	_hands_on_hint.add_theme_color_override("font_color", Color(0.7, 1.0, 0.85))
	var hands_margin := MarginContainer.new()
	hands_margin.add_theme_constant_override("margin_left", 18)
	hands_margin.add_theme_constant_override("margin_right", 18)
	hands_margin.add_theme_constant_override("margin_top", 12)
	hands_margin.add_theme_constant_override("margin_bottom", 12)
	hands_margin.add_child(_hands_on_hint)
	_hands_on_box.add_child(hands_margin)
	_hands_on_box.visible = false
	vbox.add_child(_hands_on_box)

	_feedback_label = Label.new()
	_feedback_label.text = ""
	_feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback_label.add_theme_font_size_override("font_size", 22)
	_feedback_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	vbox.add_child(_feedback_label)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(buttons)

	_back_button = _make_button("Back", Color(0.25, 0.3, 0.45, 1))
	_back_button.pressed.connect(func(): back_pressed.emit())
	buttons.add_child(_back_button)

	_start_button = _make_button("Start", Color(0.14, 0.42, 0.6, 1))
	_start_button.visible = false
	_start_button.pressed.connect(func(): start_pressed.emit())
	buttons.add_child(_start_button)

	_next_button = _make_button("Next >>", Color(0.14, 0.42, 0.6, 1))
	_next_button.visible = false
	_next_button.pressed.connect(func(): next_pressed.emit())
	buttons.add_child(_next_button)

func _make_button(text_value: String, color: Color) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(220, 58)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 24)
	button.add_theme_color_override("font_color", Color(1, 1, 1))
	button.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	button.add_theme_color_override("font_pressed_color", Color(0.85, 0.9, 1, 1))
	var normal := StyleBoxFlat.new()
	normal.bg_color = color
	normal.set_corner_radius_all(10)
	var hover := StyleBoxFlat.new()
	hover.bg_color = color.lightened(0.25)
	hover.set_corner_radius_all(10)
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = color.darkened(0.25)
	pressed.set_corner_radius_all(10)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return button

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.06, 0.12, 0.96)
	style.set_corner_radius_all(22)
	style.set_border_width_all(2)
	style.border_color = Color(0.3, 0.55, 0.9, 0.7)
	return style

# ===== Public API used by the room controller =====

## Shows the welcome / intro card with a single Start button.
func show_intro(body: String) -> void:
	_progress_label.text = ""
	_question_label.text = body
	_question_label.visible = true
	_image_rect.visible = false
	_options_box.visible = false
	_hands_on_box.visible = false
	_feedback_label.text = ""
	_back_button.visible = true
	_start_button.visible = true
	_next_button.visible = false
	_clear_options()

## Renders a multiple-choice / image question with its options.
func show_question(question: Dictionary, number: int, total: int) -> void:
	_progress_label.text = "Question %d of %d" % [number, total]
	_question_label.text = question.get("question", "")
	_question_label.visible = true

	var image_path: String = question.get("image", "")
	if image_path != "":
		var tex := load(image_path) as Texture2D
		if tex:
			_image_rect.texture = tex
		_image_rect.visible = true
	else:
		_image_rect.visible = false

	_options_box.visible = true
	_hands_on_box.visible = false
	_feedback_label.text = ""
	_back_button.visible = true
	_start_button.visible = false
	_next_button.visible = false
	_clear_options()
	var options: Array = question.get("options", [])
	for i in range(options.size()):
		var btn := _make_button(str(options[i]), Color(0.12, 0.18, 0.32, 1))
		btn.custom_minimum_size.x = 1250
		btn.add_theme_font_size_override("font_size", 20)
		btn.pressed.connect(func(): answer_selected.emit(i))
		_options_box.add_child(btn)

## Renders a hands-on task card. The learner must build the DFA on the automata
## board and press its Check task button; the room submits it on success.
func show_hands_on(question: Dictionary, number: int, total: int) -> void:
	_progress_label.text = "Task %d of %d" % [number, total]
	_question_label.text = question.get("question", "")
	_question_label.visible = true
	_image_rect.visible = false
	_options_box.visible = false
	_hands_on_box.visible = true
	_hands_on_hint.text = "Build the DFA on the automata board using states, accepting toggles and transitions. Then press \"Check task\" on the board to submit. Wrong builds stay here until fixed - only a correct build continues."
	_feedback_label.text = ""
	_back_button.visible = true
	_start_button.visible = false
	_next_button.visible = false
	_clear_options()

func set_feedback(text_value: String, is_correct: bool) -> void:
	_feedback_label.text = text_value
	_feedback_label.add_theme_color_override("font_color", Color(0.6, 0.95, 0.7, 1) if is_correct else Color(1.0, 0.5, 0.5, 1))

func clear_feedback() -> void:
	_feedback_label.text = ""
	_feedback_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))

func show_next_button(text_value := "Next >>") -> void:
	_next_button.text = text_value
	_next_button.visible = true

func hide_next_button() -> void:
	_next_button.visible = false

func _clear_options() -> void:
	for child in _options_box.get_children():
		_options_box.remove_child(child)
		child.queue_free()

# ===== Input translation (desktop mouse + VR laser) =====

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

## Ray/plane intersection for a billboarded Sprite3D that always faces the
## camera. The plane normal is computed from the camera rather than the sprite's
## static transform because the sprite is re-oriented at render time.
func _ray_intersect_sprite(ray_origin: Vector3, ray_dir: Vector3) -> Dictionary:
	if sprite.texture == null:
		return {}
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return {}
	var sprite_pos: Vector3 = sprite.global_position
	var plane_normal: Vector3 = (camera.global_position - sprite_pos).normalized()
	var denominator := plane_normal.dot(ray_dir)
	if absf(denominator) < 0.0001:
		return {}
	var distance := (sprite_pos - ray_origin).dot(plane_normal) / denominator
	if distance < 0.0:
		return {}
	var hit := ray_origin + ray_dir * distance
	var offset := hit - sprite_pos
	var camera_basis := camera.global_transform.basis
	var width := sprite.texture.get_size().x * sprite.pixel_size
	var height := sprite.texture.get_size().y * sprite.pixel_size
	var x := offset.dot(camera_basis.x)
	var y := offset.dot(camera_basis.y)
	if absf(x) > width * 0.5 or absf(y) > height * 0.5:
		return {}
	return {"uv": Vector2(x / width + 0.5, 0.5 - y / height), "hit": hit}