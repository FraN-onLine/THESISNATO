extends Node3D
## Wires the SubViewport render texture to the billboard Sprite3D
## and handles UI interaction.
## - VR: controller ray casting toward the billboard.
## - Desktop (no headset): the OS mouse cursor is ray-cast onto the billboard
##   so the panel is simply clickable, and a Controls button toggles between
##   Keyboard+Mouse and AR/VR modes.

@onready var viewport: SubViewport = $SubViewport
@onready var sprite: Sprite3D = $Billboard
@onready var overlay_layer: CanvasLayer = $OverlayLayer
@onready var overlay_rect: TextureRect = $OverlayLayer/OverlayRect

var _last_mouse_pos := Vector2(-1, -1)
var _is_pressed := false
var _lasers := {}  # XRController3D -> MeshInstance3D
var _settings_popup: Control = null
const SETTINGS_PATH := "user://settings.cfg"
var _desktop_mouse_down := false

func _ready() -> void:
	_load_settings()
	if viewport and sprite:
		sprite.texture = viewport.get_texture()
	if overlay_rect:
		overlay_rect.texture = viewport.get_texture()
	if overlay_layer:
		overlay_layer.visible = false
	if sprite:
		sprite.visible = true
	
	# Connect button signals (test every button actually leads somewhere).
	var start_button: Button = viewport.get_node("Root/Center/Panel/VBox/StartButton")
	var testing_button: Button = viewport.get_node("Root/Center/Panel/VBox/TestingButton")
	var settings_button: Button = viewport.get_node("Root/Center/Panel/VBox/SettingsButton")
	var mode_button: Button = viewport.get_node("Root/Center/Panel/VBox/ModeButton")
	var exit_button: Button = viewport.get_node("Root/Center/Panel/VBox/ExitButton")
	
	start_button.pressed.connect(_on_start_pressed)
	testing_button.pressed.connect(_on_testing_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	if mode_button:
		mode_button.pressed.connect(_on_mode_toggle_pressed)
		_update_mode_button_text(mode_button)
	exit_button.pressed.connect(_on_exit_pressed)

func _input(event: InputEvent) -> void:
	# Track the real left mouse button so Desktop mode can click the panel.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_desktop_mouse_down = event.pressed

func _process(_delta: float) -> void:
	if sprite:
		sprite.rotation.y += _delta * 0.12
	_update_pointer()

func _update_mode_button_text(btn: Button) -> void:
	btn.text = "Controls: %s" % ("AR / VR" if InputMode.is_vr() else "Keyboard + Mouse (WASD)")

func _on_mode_toggle_pressed() -> void:
	# Toggle between Keyboard+Mouse and AR/VR. `set_mode()` internally tries
	# to initialize OpenXR when switching into VR and falls back to Desktop if
	# no headset is detected (staying on Keyboard + Mouse).
	_apply_input_mode(not InputMode.is_vr())
	_save_settings()
	# Refresh the label (and if we just entered the menu the button exists).
	var mode_button: Button = viewport.get_node_or_null("Root/Center/Panel/VBox/ModeButton")
	if mode_button:
		_update_mode_button_text(mode_button)
	# Reload the current scene so the player is re-created in the chosen mode.
	get_tree().reload_current_scene()


## Ask InputMode for `want_vr` and report whether that mode is really active.
## VR needs a connected headset - when none answers the mode stays PC and the
## previous preference is kept (nothing is silently locked to PC), so callers
## can react (e.g. snap the Settings switch back).
func _apply_input_mode(want_vr: bool) -> bool:
	InputMode.set_mode(want_vr)
	return InputMode.is_vr() == want_vr

func _update_pointer() -> void:
	if InputMode.is_desktop():
		_update_desktop_pointer()
	else:
		_update_vr_pointer()

func _update_desktop_pointer() -> void:
	# Ray-cast the real OS mouse cursor onto the billboard and translate the
	# resulting UV into mouse events for the SubViewport UI. This makes the
	# whole panel directly clickable without a headset.
	var camera := get_viewport().get_camera_3d()
	if camera == null or sprite == null or sprite.texture == null:
		return

	var mouse_screen := get_viewport().get_mouse_position()
	var ray_origin: Vector3 = camera.project_ray_origin(mouse_screen)
	var ray_dir: Vector3 = camera.project_ray_normal(mouse_screen)
	var result: Dictionary = _ray_intersect_sprite(ray_origin, ray_dir)

	var uv := Vector2(-1, -1)
	if not result.is_empty():
		var raw_uv: Vector2 = result.get("uv", Vector2(-1, -1))
		uv = Vector2(raw_uv.x * viewport.size.x, raw_uv.y * viewport.size.y)

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
func _update_overlay_pointer() -> void:
	var mouse_screen := get_viewport().get_mouse_position()
	var uv := Vector2(-1, -1)
	if overlay_rect and overlay_rect.visible:
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
		
		var ray_origin: Vector3 = controller.global_position
		var ray_dir: Vector3 = -controller.global_transform.basis.z
		var result: Dictionary = _ray_intersect_sprite(ray_origin, ray_dir)
		
		if result.is_empty():
			laser.visible = false
			continue
		
		# Show the laser beam from the controller to the sprite
		laser.visible = true
		var distance: float = ray_origin.distance_to(result["hit"])
		laser.position = Vector3(0, 0, -distance * 0.5)
		laser.scale = Vector3(1, 1, distance)
		
		# Only the first controller that hits drives the input
		if not hit_any:
			hit_any = true
			active_controller = controller
			active_result = result
	
	# Handle input for the first controller that hits the sprite
	if hit_any and active_controller:
		var mouse_pos := Vector2(active_result["uv"].x * viewport.size.x, active_result["uv"].y * viewport.size.y)
		
		# Send mouse motion to update hover state
		if mouse_pos != _last_mouse_pos:
			var motion := InputEventMouseMotion.new()
			motion.position = mouse_pos
			motion.global_position = mouse_pos
			viewport.push_input(motion)
			_last_mouse_pos = mouse_pos
		
		# Send press/release based on trigger
		var trigger_down: bool = active_controller.is_button_pressed("trigger_click")
		if trigger_down and not _is_pressed:
			var press := InputEventMouseButton.new()
			press.button_index = MOUSE_BUTTON_LEFT
			press.pressed = true
			press.position = mouse_pos
			press.global_position = mouse_pos
			viewport.push_input(press)
			_is_pressed = true
			active_controller.trigger_haptic_pulse("haptic", 0.0, 0.5, 0.05, 0)
		elif not trigger_down and _is_pressed:
			var release := InputEventMouseButton.new()
			release.button_index = MOUSE_BUTTON_LEFT
			release.pressed = false
			release.position = mouse_pos
			release.global_position = mouse_pos
			viewport.push_input(release)
			_is_pressed = false
	else:
		# No controller is pointing at the sprite, clear hover/press state
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
	## Returns { "uv": Vector2, "hit": Vector3 } if the ray hits the billboard, else {}.
	if sprite == null or sprite.texture == null:
		return {}
	
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return {}
	
	# Billboard sprites face the camera at render time, so the plane normal
	# must be computed from the camera position, not the node's transform.
	var sprite_pos: Vector3 = sprite.global_position
	var plane_normal: Vector3 = (camera.global_position - sprite_pos).normalized()
	var plane_point: Vector3 = sprite_pos
	
	var denom := plane_normal.dot(ray_dir)
	if absf(denom) < 0.0001:
		return {}
	
	var t := (plane_point - ray_origin).dot(plane_normal) / denom
	if t < 0.0:
		return {}
	
	var hit := ray_origin + ray_dir * t
	var to_hit := hit - sprite_pos
	
	# Billboard sprites align their X/Y axes with the camera's right/up at render time.
	var camera_basis := camera.global_transform.basis
	var right: Vector3 = camera_basis.x
	var up: Vector3 = camera_basis.y
	
	var local_x := to_hit.dot(right)
	var local_y := to_hit.dot(up)
	
	var tex_size := sprite.texture.get_size()
	var quad_w := tex_size.x * sprite.pixel_size
	var quad_h := tex_size.y * sprite.pixel_size
	
	if absf(local_x) > quad_w * 0.5 or absf(local_y) > quad_h * 0.5:
		return {}
	
	var u := local_x / quad_w + 0.5
	var v := 0.5 - local_y / quad_h
	
	return { "uv": Vector2(u, v), "hit": hit }

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

func _on_start_pressed() -> void:
	SessionBridge.reset_session()
	SessionBridge.get_session().start_learning_demo()
	SessionBridge.test_mode = "learning_demo"
	get_tree().change_scene_to_file("res://Testing/TestingGrounds.tscn")

func _on_testing_pressed() -> void:
	# Enter the Testing Grounds directly. The learner is first BRIEFED on how
	# each algorithm learns, THEN picks one (selection happens after the
	# briefing), before any pretest data is collected.
	get_tree().change_scene_to_file("res://Testing/TestingGrounds.tscn")

func _on_settings_pressed() -> void:
	# In-panel Options popup. It is built INSIDE the SubViewport so it is clickable
	# in BOTH desktop (mouse ray) and VR (controller laser), like the rest of this
	# panel. Pressing Settings while it is open closes it.
	if _settings_popup and is_instance_valid(_settings_popup):
		_settings_popup.queue_free()
		_settings_popup = null
		return

	var root: Control = viewport.get_node("Root")

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)

	var panel := PanelContainer.new()
	var pb := StyleBoxFlat.new()
	pb.bg_color = Color(0.07, 0.09, 0.16, 0.98)
	pb.corner_radius_top_left = 16
	pb.corner_radius_top_right = 16
	pb.corner_radius_bottom_right = 16
	pb.corner_radius_bottom_left = 16
	pb.content_margin_left = 44
	pb.content_margin_right = 44
	pb.content_margin_top = 30
	pb.content_margin_bottom = 30
	panel.add_theme_stylebox_override("panel", pb)
	panel.custom_minimum_size = Vector2(820, 0)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "OPTIONS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	vbox.add_child(title)

	# VR / PC play mode - the same InputMode the main-menu Controls button uses,
	# but reachable from Settings and persisted to user://settings.cfg.
	var vr_mode := CheckButton.new()
	vr_mode.text = "VR mode (headset) - OFF = PC (Keyboard + Mouse)"
	vr_mode.button_pressed = InputMode.is_vr()
	vr_mode.add_theme_font_size_override("font_size", 24)
	vbox.add_child(vr_mode)

	var vr_hint := Label.new()
	vr_hint.text = "ON = VR (headset + controllers). OFF = PC (keyboard + mouse). The scene reloads to apply the change; without a headset the game stays in PC mode."
	vr_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vr_hint.add_theme_font_size_override("font_size", 17)
	vr_hint.add_theme_color_override("font_color", Color(0.72, 0.82, 0.98, 1))
	vbox.add_child(vr_hint)

	vr_mode.toggled.connect(func(on: bool):
		if _apply_input_mode(on):
			_save_settings()
			# Reload so the player / camera is re-created for the chosen mode
			# (the popup closes with the scene, like the Controls button).
			get_tree().reload_current_scene()
		else:
			# No headset attached: snap the switch back and stay on PC.
			vr_mode.set_pressed_no_signal(false)
			vr_hint.text = "No headset detected - staying in PC mode."
			_save_settings())

	var collect := CheckButton.new()
	collect.text = "Collect profile data (name / age / gender)"
	collect.button_pressed = not SessionBridge.skip_profile_collection
	collect.add_theme_font_size_override("font_size", 24)
	collect.toggled.connect(func(on: bool):
		SessionBridge.skip_profile_collection = not on
		_save_settings())
	vbox.add_child(collect)

	var hint := Label.new()
	hint.text = "OFF = skip Profile Setup, so the flow becomes: Algorithm briefing -> Pretest (dev / no personal data is written)."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 17)
	hint.add_theme_color_override("font_color", Color(0.72, 0.82, 0.98, 1))
	vbox.add_child(hint)

	var verbose := CheckButton.new()
	verbose.text = "Verbose stats board (per-skill detail)"
	verbose.button_pressed = SessionBridge.verbose_board
	verbose.add_theme_font_size_override("font_size", 24)
	verbose.toggled.connect(func(on: bool):
		SessionBridge.verbose_board = on
		_save_settings())
	vbox.add_child(verbose)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(320, 58)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.add_theme_font_size_override("font_size", 24)
	close_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	close_btn.pressed.connect(func():
		if is_instance_valid(dim):
			dim.queue_free()
		_settings_popup = null)
	vbox.add_child(close_btn)

	_settings_popup = dim

func _save_settings() -> void:
	# Start from the existing file so a preference that must not change right
	# now (e.g. vr_mode while the mode is still AUTO) survives the rewrite.
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("options", "skip_profile_collection", SessionBridge.skip_profile_collection)
	cfg.set_value("options", "verbose_board", SessionBridge.verbose_board)
	if InputMode.mode_pref != InputMode.Pref.AUTO:
		cfg.set_value("options", "vr_mode", InputMode.mode_pref == InputMode.Pref.VR)
	cfg.save(SETTINGS_PATH)

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		SessionBridge.skip_profile_collection = bool(cfg.get_value("options", "skip_profile_collection", SessionBridge.skip_profile_collection))
		SessionBridge.verbose_board = bool(cfg.get_value("options", "verbose_board", SessionBridge.verbose_board))

func _on_exit_pressed() -> void:
	get_tree().quit()
