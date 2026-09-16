extends Node3D
## Controller for the Algorithm Select screen that appears BEFORE the Testing
## Grounds opens. The learner picks the knowledge-tracing algorithm that will
## drive the whole session (HMM, BKT, or KST) and reads exactly HOW each one
## learns through the three phases:
##   1. PRETEST  -> pretest answers are the ONLY input / starting elements.
##   2. LEARNING -> interactive answers analyse mastery; terminate when learnt.
##   3. POST TEST-> a no-feedback test proves the theory.
## The choice is stored on the shared session, then the Testing Grounds opens.

const AlgorithmCatalog = preload("res://Testing/Algorithms/algorithm_catalog.gd")
const SessionManager = preload("res://Testing/session_manager.gd")

@onready var viewport: SubViewport = $UI_Panel/SubViewport
@onready var sprite: Sprite3D = $UI_Panel/Billboard
@onready var overlay_layer: CanvasLayer = $UI_Panel/OverlayLayer
@onready var overlay_rect: TextureRect = $UI_Panel/OverlayLayer/OverlayRect
@onready var title_label: Label = $UI_Panel/SubViewport/Root/Center/Panel/VBox/TitleContainer/Title
@onready var question_label: Label = $UI_Panel/SubViewport/Root/Center/Panel/VBox/Content/QuestionLabel
@onready var options_box: VBoxContainer = $UI_Panel/SubViewport/Root/Center/Panel/VBox/Content/OptionsBox
@onready var feedback_label: Label = $UI_Panel/SubViewport/Root/Center/Panel/VBox/Content/FeedbackLabel
@onready var progress_label: Label = $UI_Panel/SubViewport/Root/Center/Panel/VBox/Content/ProgressLabel
@onready var back_button: Button = $UI_Panel/SubViewport/Root/Center/Panel/VBox/ButtonBox/BackButton
@onready var next_button: Button = $UI_Panel/SubViewport/Root/Center/Panel/VBox/ButtonBox/NextButton

var session = null

# The algorithm the learner has committed to (HMM=0, BKT=1, KST=2).
var _selected: int = AlgorithmCatalog.TYPE_HMM
# Which algorithm's full description is currently on screen (browsing).
var _viewing: int = AlgorithmCatalog.TYPE_HMM

var _last_mouse_pos := Vector2(-1, -1)
var _is_pressed := false
var _desktop_mouse_down := false
var _lasers := {}

func _ready() -> void:
	if viewport and sprite:
		sprite.texture = viewport.get_texture()
	if overlay_rect:
		overlay_rect.texture = viewport.get_texture()
	session = SessionBridge.get_session()
	# A previously finished session should not block a fresh algorithm run.
	if session.state == SessionManager.SessionState.COMPLETE:
		SessionBridge.reset_session()
		session = SessionBridge.get_session()

	back_button.pressed.connect(_on_back_pressed)
	_show_selection()
	_enter_panel()

func _enter_panel() -> void:
	# The panel is always shown fullscreen on desktop and as a billboard in VR.
	if overlay_layer:
		overlay_layer.visible = not InputMode.is_vr()
	if sprite:
		sprite.visible = InputMode.is_vr()

func _process(_delta: float) -> void:
	_update_pointer()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_desktop_mouse_down = event.pressed

# ===== SCREENS =====

func _show_selection() -> void:
	title_label.text = "ALGORITHM SELECT"
	_clear_options()
	question_label.text = """Welcome to the DFA Learning Lab!

Before the Testing Grounds opens, choose the algorithm that will watch YOU learn. Every algorithm follows the same three-phase pipeline:

[1] PRETEST — your pretest answers are the ONLY input / starting elements.
[2] INTERACTIVE LEARNING — your practice answers are analysed one by one; a topic STOPS as soon as the algorithm decides you have learnt it.
[3] POST TEST — a fresh, no-feedback test proves (or disproves) the theory.

Pick an algorithm to see exactly how it learns:"""
	question_label.visible = true

	for algo_type in AlgorithmCatalog.catalog_all_types():
		var info: Dictionary = AlgorithmCatalog.catalog_info(algo_type)
		var btn := Button.new()
		btn.text = "%s\n%s\n%s" % [info["name"], info["tagline"], info["needs_summary"]]
		btn.custom_minimum_size = Vector2(1100, 104)
		btn.add_theme_font_size_override("font_size", 17)
		btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
		btn.add_theme_color_override("font_pressed_color", Color(0.8, 0.9, 1, 1))
		btn.add_theme_stylebox_override("normal", _create_button_style(info["accent"].darkened(0.35)))
		btn.add_theme_stylebox_override("hover", _create_button_style(info["accent"]))
		btn.add_theme_stylebox_override("pressed", _create_button_style(info["accent"].darkened(0.55)))
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		btn.pressed.connect(_on_algorithm_picked.bind(algo_type))
		options_box.add_child(btn)

	var library_btn := Button.new()
	library_btn.text = "❓  How do these algorithms learn?  (Algorithm Library)"
	library_btn.custom_minimum_size = Vector2(1100, 48)
	library_btn.add_theme_font_size_override("font_size", 18)
	library_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	library_btn.add_theme_stylebox_override("normal", _create_button_style(Color(0.2, 0.3, 0.5, 1)))
	library_btn.add_theme_stylebox_override("hover", _create_button_style(Color(0.35, 0.5, 0.8, 1)))
	library_btn.add_theme_stylebox_override("pressed", _create_button_style(Color(0.12, 0.2, 0.35, 1)))
	library_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	library_btn.pressed.connect(_show_library)
	options_box.add_child(library_btn)

	feedback_label.text = ""
	progress_label.text = "Testing Grounds is locked until an algorithm is selected."
	back_button.visible = true
	back_button.text = "Back to Lab"
	next_button.visible = false
func _on_algorithm_picked(algo_type: int) -> void:
	_selected = algo_type
	_viewing = algo_type
	_show_detail()

## Algorithm Library: read the full description of each algorithm (browse mode).
func _show_library() -> void:
	_viewing = _selected if _selected >= 0 else AlgorithmCatalog.TYPE_HMM
	_show_detail(true)

func _show_detail(browsing := false) -> void:
	var info: Dictionary = AlgorithmCatalog.catalog_info(_viewing)
	var selected_name: String = AlgorithmCatalog.catalog_name(_selected)
	title_label.text = "HOW %s LEARNS" % info["callout"]
	_clear_options()

	var text := "SELECTED FOR THIS SESSION: %s\n\n" % selected_name
	text += "■ HOW IT WORKS\n%s\n\n" % info["how_works"]
	text += "■ THE MATH\n%s\n\n" % info["formula"]
	text += "■ ITS LEARNING PIPELINE\n%s\n\n" % AlgorithmCatalog.catalog_pipeline_summary(_viewing)
	text += "■ WHY USE IT\n%s\n\n■ LIMITATION\n%s" % [info["best_for"], info["limit"]]
	question_label.text = text
	question_label.visible = true

	# Switch to another algorithm's page (browse mode never overrides the pick).
	var switch_row := HBoxContainer.new()
	switch_row.add_theme_constant_override("separation", 8)
	switch_row.alignment = BoxContainer.ALIGNMENT_CENTER
	for algo_type in AlgorithmCatalog.catalog_all_types():
		var sw := Button.new()
		var highlight = algo_type == _viewing
		sw.text = AlgorithmCatalog.catalog_callout(algo_type)
		sw.custom_minimum_size = Vector2(140, 40)
		sw.add_theme_font_size_override("font_size", 16)
		sw.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		var base := Color(0.85, 0.6, 0.15, 1) if highlight else Color(0.16, 0.28, 0.62, 1)
		sw.add_theme_stylebox_override("normal", _create_button_style(base))
		sw.add_theme_stylebox_override("hover", _create_button_style(base.lightened(0.25)))
		sw.add_theme_stylebox_override("pressed", _create_button_style(base.darkened(0.2)))
		sw.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		sw.pressed.connect(func():
			_viewing = algo_type
			_show_detail(browsing)
		)
		switch_row.add_child(sw)
	options_box.add_child(switch_row)

	var continue_btn := Button.new()
	continue_btn.text = "Use %s → Enter Testing Grounds" % AlgorithmCatalog.catalog_callout(_selected)
	continue_btn.custom_minimum_size = Vector2(1100, 52)
	continue_btn.add_theme_font_size_override("font_size", 19)
	continue_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	continue_btn.add_theme_stylebox_override("normal", _create_button_style(Color(0.1, 0.55, 0.35, 1)))
	continue_btn.add_theme_stylebox_override("hover", _create_button_style(Color(0.2, 0.75, 0.45, 1)))
	continue_btn.add_theme_stylebox_override("pressed", _create_button_style(Color(0.07, 0.4, 0.25, 1)))
	continue_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	continue_btn.pressed.connect(_on_continue)
	options_box.add_child(continue_btn)

	if browsing:
		var back_to_select := Button.new()
		back_to_select.text = "← Back to the algorithm list"
		back_to_select.custom_minimum_size = Vector2(1100, 44)
		back_to_select.add_theme_font_size_override("font_size", 17)
		back_to_select.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		back_to_select.add_theme_stylebox_override("normal", _create_button_style(Color(0.2, 0.3, 0.5, 1)))
		back_to_select.add_theme_stylebox_override("hover", _create_button_style(Color(0.35, 0.5, 0.8, 1)))
		back_to_select.add_theme_stylebox_override("pressed", _create_button_style(Color(0.12, 0.2, 0.35, 1)))
		back_to_select.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		back_to_select.pressed.connect(_show_selection)
		options_box.add_child(back_to_select)

	feedback_label.text = ""
	progress_label.text = "Stage 1: Pretest (only input)  →  Stage 2: Learn (terminate at mastery)  →  Stage 3: Post Test (proof)"
	back_button.visible = true
	back_button.text = "Back"
	next_button.visible = false

func _on_continue() -> void:
	if session == null:
		session = SessionBridge.get_session()
	session.set_algorithm_type(_selected)
	get_tree().change_scene_to_file("res://Testing/TestingGrounds.tscn")

func _on_back_pressed() -> void:
	if back_button.text == "Back to Lab":
		get_tree().change_scene_to_file("res://World/World.tscn")
		return
	_show_selection()

# ===== STYLE HELPERS =====

func _clear_options() -> void:
	for child in options_box.get_children():
		options_box.remove_child(child)
		child.queue_free()

func _create_button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(12)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style
# ===== POINTER (desktop overlay + VR laser) =====

func _update_pointer() -> void:
	if InputMode.is_desktop():
		_update_overlay_pointer()
	else:
		_update_vr_pointer()

func _update_overlay_pointer() -> void:
	var mouse_screen := get_viewport().get_mouse_position()
	var uv := Vector2(-1, -1)
	if overlay_rect != null and overlay_rect.visible:
		var rect := overlay_rect.get_global_rect()
		if rect.has_point(mouse_screen) and rect.size.x > 0.0 and rect.size.y > 0.0:
			var local := mouse_screen - rect.position
			uv = Vector2(local.x / rect.size.x * viewport.size.x, local.y / rect.size.y * viewport.size.y)
	var on_panel := uv != Vector2(-1, -1)
	if uv != _last_mouse_pos:
		var motion := InputEventMouseMotion.new()
		motion.position = uv
		motion.global_position = uv
		viewport.push_input(motion)
		_last_mouse_pos = uv
	if on_panel and _desktop_mouse_down and not _is_pressed:
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = uv
		press.global_position = uv
		viewport.push_input(press)
		_is_pressed = true
	elif (not _desktop_mouse_down or not on_panel) and _is_pressed:
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.pressed = false
		release.position = uv
		release.global_position = uv
		viewport.push_input(release)
		_is_pressed = false

func _update_vr_pointer() -> void:
	var controllers := get_tree().get_nodes_in_group("xr_controller")
	var hit_any := false
	var active_controller: XRController3D = null
	var active_result: Dictionary = {}
	for controller in controllers:
		if not (controller is XRController3D):
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
		if mouse_pos != _last_mouse_pos:
			var motion := InputEventMouseMotion.new()
			motion.position = mouse_pos
			motion.global_position = mouse_pos
			viewport.push_input(motion)
			_last_mouse_pos = mouse_pos
		var trigger_down: bool = active_controller.is_button_pressed("trigger_click")
		if trigger_down and not _is_pressed:
			var press := InputEventMouseButton.new()
			press.button_index = MOUSE_BUTTON_LEFT
			press.pressed = true
			press.position = mouse_pos
			press.global_position = mouse_pos
			viewport.push_input(press)
			_is_pressed = true
		elif not trigger_down and _is_pressed:
			var release := InputEventMouseButton.new()
			release.button_index = MOUSE_BUTTON_LEFT
			release.pressed = false
			release.position = mouse_pos
			release.global_position = mouse_pos
			viewport.push_input(release)
			_is_pressed = false
	else:
		if _last_mouse_pos != Vector2(-1, -1):
			var motion := InputEventMouseMotion.new()
			motion.position = Vector2(-1000, -1000)
			motion.global_position = Vector2(-1000, -1000)
			viewport.push_input(motion)
			_last_mouse_pos = Vector2(-1, -1)
		if _is_pressed:
			var release := InputEventMouseButton.new()
			release.button_index = MOUSE_BUTTON_LEFT
			release.pressed = false
			release.position = Vector2(-1000, -1000)
			release.global_position = Vector2(-1000, -1000)
			viewport.push_input(release)
			_is_pressed = false

func _ray_intersect_sprite(ray_origin: Vector3, ray_dir: Vector3) -> Dictionary:
	if sprite == null or sprite.texture == null:
		return {}
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return {}
	var sprite_pos: Vector3 = sprite.global_position
	var plane_normal: Vector3 = (camera.global_position - sprite_pos).normalized()
	var denom := plane_normal.dot(ray_dir)
	if absf(denom) < 0.0001:
		return {}
	var t := (sprite_pos - ray_origin).dot(plane_normal) / denom
	if t < 0.0:
		return {}
	var hit := ray_origin + ray_dir * t
	var to_hit := hit - sprite_pos
	var camera_basis := camera.global_transform.basis
	var local_x := to_hit.dot(camera_basis.x)
	var local_y := to_hit.dot(camera_basis.y)
	var tex_size := sprite.texture.get_size()
	var quad_w := tex_size.x * sprite.pixel_size
	var quad_h := tex_size.y * sprite.pixel_size
	if absf(local_x) > quad_w * 0.5 or absf(local_y) > quad_h * 0.5:
		return {}
	return {"uv": Vector2(local_x / quad_w + 0.5, 0.5 - local_y / quad_h), "hit": hit}

func _ensure_laser(controller: XRController3D) -> MeshInstance3D:
	if _lasers.has(controller):
		return _lasers[controller]
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.008, 0.008, 1.0)
	mesh_instance.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.6, 1.0, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.6, 1.0)
	mat.emission_energy_multiplier = 2.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_instance.material_override = mat
	mesh_instance.visible = false
	controller.add_child(mesh_instance)
	_lasers[controller] = mesh_instance
	return mesh_instance
