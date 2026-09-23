extends Node3D
## The lesson panel (contents): a ROTATING board that faces the user, per spec.
##
## 3D nodes (SubViewport / Board sprite / Backdrop) are prebuilt in the
## LessonPanel.tscn scene — this script builds ONLY the 2D lesson UI inside the
## viewport (module header + HUD + info/checkpoint content). The 3D shell is a
## node, not code.
##
## It renders, in one place:
##   * the module header, XP / streak / level HUD and a mastery bar,
##   * information panels (title, body, bullets, call-out),
##   * checkpoint cards (mc / trace / build / maze) via checkpoint_card.gd,
##   * the walkable maze checkpoint via maze_panel.gd,
##   * checkpoint notifications via checkpoint_toast.gd,
##   * captions for the (optional) narrator via lesson_voice.gd.
##
## The panel never grades or decides anything: it forwards answers to
## lesson_engine.gd and paints whatever comes back.

signal responded(response)
signal reveal_requested
signal advance_requested
signal board_requested(step: Dictionary)
signal sandbox_requested(step: Dictionary)

const CheckpointCard = preload("res://Testing/Lessons/checkpoint_card.gd")
const MazePanel = preload("res://Testing/Lessons/maze_panel.gd")
const CheckpointToast = preload("res://Testing/Lessons/checkpoint_toast.gd")
const PanelSurface = preload("res://Testing/Lessons/panel_surface.gd")
const Checkpoint = preload("res://Testing/Lessons/checkpoint.gd")
const Library = preload("res://Testing/Lessons/lesson_library.gd")

const VIEWPORT_SIZE := Vector2i(2000, 1250)
const PIXEL_SIZE := 0.0026      # 2000 x 0.0026 = 5.2 m wide board

@onready var viewport: SubViewport
@onready var sprite: Sprite3D
@onready var backdrop: CSGBox3D

var engine = null
var voice = null

var _root: Control
var _surface = null
var _toasts: Control
var _title_label: Label
var _hud_label: Label
var _progress_label: Label
var _mastery_bar: ProgressBar
var _step_title: Label
var _step_body: Label
var _step_points: Label
var _step_callout: Label
var _card_holder: Control
var _card = null
var _maze = null
var _caption_label: Label
var _footer: HBoxContainer
var _continue_button: Button
var _hint_button: Button
var _reveal_button: Button
var _board_button: Button
var _exit_button: Button

func _ready() -> void:
	if InputMode.is_desktop():
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_ensure_nodes()
	_build_ui()
	_surface = PanelSurface.new()
	_surface.setup(self, sprite, viewport)
	set_process(true)

## 3D shell comes from LessonPanel.tscn when instanced; fall back to building
## it in code only for legacy/headless use (DevTests). The 2D lesson content
## below is always built in _build_ui().
func _ensure_nodes() -> void:
	if viewport == null:
		viewport = get_node_or_null("SubViewport") as SubViewport
	if sprite == null:
		sprite = get_node_or_null("Board") as Sprite3D
	if backdrop == null:
		backdrop = get_node_or_null("Backdrop") as CSGBox3D
	if viewport != null and sprite != null and backdrop != null:
		# SPEC: lesson contents panel ROTATES to face the user.
		PanelSurface.face_player(sprite)
		return
	_build_nodes()

func set_active(active: bool) -> void:
	visible = active
	if _surface != null:
		_surface.set_active(active)
	set_process(active)

func _build_nodes() -> void:
	viewport = SubViewport.new()
	viewport.name = "SubViewport"
	viewport.transparent_bg = true
	viewport.handle_input_locally = false
	viewport.size = VIEWPORT_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	backdrop = CSGBox3D.new()
	backdrop.name = "Backdrop"
	backdrop.position = Vector3(0, 0, -0.12)
	backdrop.size = Vector3(VIEWPORT_SIZE.x * PIXEL_SIZE + 0.3, VIEWPORT_SIZE.y * PIXEL_SIZE + 0.3, 0.16)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.04, 0.06, 0.11, 1)
	backdrop.material = material
	add_child(backdrop)

	sprite = Sprite3D.new()
	sprite.name = "Board"
	sprite.pixel_size = PIXEL_SIZE
	sprite.texture = viewport.get_texture()
	add_child(sprite)
	# SPEC: lesson contents panel ROTATES to face the user (static boards stay flat).
	PanelSurface.face_player(sprite)

func _input(event: InputEvent) -> void:
	if _surface != null:
		_surface.handle_input(event)

func _process(_delta: float) -> void:
	if _surface != null:
		_surface.process_pointer()

# ===== UI construction =====================================================

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_PASS
	viewport.add_child(_root)

	var outer := MarginContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		outer.add_theme_constant_override(side, 24)
	_root.add_child(outer)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	outer.add_child(column)

	# --- header -------------------------------------------------------------
	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", _style(Color(0.1, 0.18, 0.4, 1), 16))
	column.add_child(header)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 14)
	header.add_child(header_row)

	_title_label = Label.new()
	_title_label.text = "LESSON"
	_title_label.add_theme_font_size_override("font_size", 30)
	_title_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(_title_label)

	_progress_label = Label.new()
	_progress_label.add_theme_font_size_override("font_size", 22)
	_progress_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1, 1))
	header_row.add_child(_progress_label)

	_hud_label = Label.new()
	_hud_label.add_theme_font_size_override("font_size", 22)
	_hud_label.add_theme_color_override("font_color", Color(1, 0.85, 0.45, 1))
	header_row.add_child(_hud_label)

	_mastery_bar = ProgressBar.new()
	_mastery_bar.max_value = 100.0
	_mastery_bar.value = 0.0
	_mastery_bar.custom_minimum_size = Vector2(0, 18)
	_mastery_bar.show_percentage = true
	column.add_child(_mastery_bar)

	# --- scrolling step area ------------------------------------------------
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	var step_area := VBoxContainer.new()
	step_area.add_theme_constant_override("separation", 10)
	step_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(step_area)

	_step_title = Label.new()
	_step_title.add_theme_font_size_override("font_size", 28)
	_step_title.add_theme_color_override("font_color", Color(0.65, 0.85, 1, 1))
	_step_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	step_area.add_child(_step_title)

	_step_body = Label.new()
	_step_body.add_theme_font_size_override("font_size", 23)
	_step_body.add_theme_color_override("font_color", Color(0.95, 0.95, 1, 1))
	_step_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	step_area.add_child(_step_body)

	_step_points = Label.new()
	_step_points.add_theme_font_size_override("font_size", 22)
	_step_points.add_theme_color_override("font_color", Color(0.8, 0.9, 1, 1))
	_step_points.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	step_area.add_child(_step_points)

	_step_callout = Label.new()
	_step_callout.add_theme_font_size_override("font_size", 22)
	_step_callout.add_theme_color_override("font_color", Color(1, 0.9, 0.55, 1))
	_step_callout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	step_area.add_child(_step_callout)

	_card_holder = Control.new()
	_card_holder.custom_minimum_size = Vector2(0, 640)
	_card_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	step_area.add_child(_card_holder)

	# --- captions (narrator) ------------------------------------------------
	_caption_label = Label.new()
	_caption_label.add_theme_font_size_override("font_size", 21)
	_caption_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.75, 1))
	_caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption_label.custom_minimum_size = Vector2(0, 52)
	column.add_child(_caption_label)

	# --- footer buttons -----------------------------------------------------
	_footer = HBoxContainer.new()
	_footer.add_theme_constant_override("separation", 10)
	_footer.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(_footer)

	_continue_button = _make_button("Continue >>", Color(0.18, 0.42, 0.72))
	_continue_button.pressed.connect(func(): advance_requested.emit())
	_footer.add_child(_continue_button)

	_hint_button = _make_button("Hint", Color(0.26, 0.3, 0.55))
	_hint_button.pressed.connect(_on_hint)
	_footer.add_child(_hint_button)

	_reveal_button = _make_button("Reveal answer", Color(0.38, 0.24, 0.3))
	_reveal_button.pressed.connect(func(): reveal_requested.emit())
	_footer.add_child(_reveal_button)

	_board_button = _make_button("Open the whiteboard", Color(0.22, 0.4, 0.5))
	_board_button.pressed.connect(func(): board_requested.emit(current_step()))
	_footer.add_child(_board_button)

	_exit_button = _make_button("Exit sandbox", Color(0.3, 0.3, 0.4))
	_exit_button.pressed.connect(func(): sandbox_requested.emit(current_step()))
	_footer.add_child(_exit_button)

	# --- notifications ------------------------------------------------------
	_toasts = CheckpointToast.new()
	_toasts.name = "Toasts"
	_root.add_child(_toasts)

var _step: Dictionary = {}

func current_step() -> Dictionary:
	return _step

# ===== Engine binding ======================================================

## Connect to a lesson engine so the panel shows checkpoints, rewards and HUD.
func bind_engine(source_engine) -> void:
	engine = source_engine
	if engine == null:
		return
	_toasts.name = "Toasts"
	engine.checkpoint_reached.connect(_on_checkpoint_reached)
	engine.checkpoint_solved.connect(_on_checkpoint_solved)
	engine.remediation_injected.connect(_on_remediation)
	engine.practice_injected.connect(_on_practice)
	engine.level_up.connect(_on_level_up)
	engine.module_finished.connect(_on_module_finished)

## The optional narrator. Without one the panel simply shows no captions.
func bind_voice(source_voice) -> void:
	voice = source_voice
	if voice != null and voice.has_signal("captions_changed"):
		voice.captions_changed.connect(_on_caption)

func _on_caption(text: String, kind: String) -> void:
	if _caption_label == null:
		return
	_caption_label.text = text if kind != "checkpoint" else "[narrator] %s" % text

func _on_checkpoint_reached(step: Dictionary, number: int, total: int) -> void:
	var prompt := Checkpoint.prompt_of(step.get("checkpoint", {}))
	_toasts.announce_checkpoint(number, total, prompt)
	if voice != null and voice.has_method("announce_checkpoint"):
		voice.announce_checkpoint(number, total, prompt, Checkpoint.id_of(step.get("checkpoint", {})))
	_refresh_hud()

func _on_checkpoint_solved(_id: String, first_try: bool, xp: int) -> void:
	var streak := int(engine.gamification.streak) if engine.gamification != null else 0
	if _card != null:
		_card.set_feedback(engine.current_result)
	if _maze != null:
		_maze.set_feedback(engine.current_result)
	_toasts.announce_reward(xp, streak, first_try, {})
	if voice != null and voice.has_method("announce_reward"):
		voice.announce_reward(xp, streak)
	_refresh_hud()

func _on_remediation(info_step: Dictionary, attempt: int) -> void:
	_toasts.announce_remedy(attempt, str(info_step.get("title", "extra help")))
	_show_info_step(info_step, true)

func _on_practice(step: Dictionary, round_number: int, remaining: int) -> void:
	_toasts.announce_practice(round_number, remaining, Library.get_title(_skill_of(step)))
	show_step(step)

func _on_level_up(event: Dictionary) -> void:
	_toasts.announce_reward(0, 0, false, event)
	if voice != null and voice.has_method("announce_level"):
		voice.announce_level(int(event.get("level", 1)), str(event.get("title", "")))

func _on_module_finished(summary: Dictionary) -> void:
	show_module_complete(summary)
	_toasts.announce_module(summary)
	if voice != null and voice.has_method("speak"):
		voice.speak(str(summary.get("headline", "")), "mastery")

func _skill_of(step: Dictionary) -> String:
	var cp: Dictionary = step.get("checkpoint", {})
	var skill := Checkpoint.skill_of(cp)
	if skill == "definition" and engine != null and engine.skill != "":
		return engine.skill
	return skill

# ===== Rendering steps =====================================================

## Render whatever the engine currently points at.
func show_step(step: Dictionary) -> void:
	_step = step
	var kind := str(step.get("kind", "info"))
	_clear_card()
	match kind:
		"checkpoint":
			var cp: Dictionary = step.get("checkpoint", {})
			if Checkpoint.kind_of(cp) == Checkpoint.KIND_MAZE:
				_show_maze_step(cp)
			else:
				_show_checkpoint_step(cp)
		"board":
			_show_info_step({
				"title": str(step.get("title", "WHITEBOARD TASK")),
				"body": str(step.get("explain", "")),
				"points": _task_lines(step.get("task", {})),
				"callout": "Press \"Open the whiteboard\" to work on the board, then \"Check task\" there.",
			}, false)
			_show_only(["continue", "board"])
		"freebuild":
			_show_info_step({
				"title": str(step.get("title", "SANDBOX")),
				"body": str(step.get("subtitle", "")),
				"points": [],
				"callout": "Open the sandbox, build anything, and come back when you are done.",
			}, false)
			_show_only(["board", "exit"])
		_:
			_show_info_step(step, false)
	_refresh_hud()

func _show_info_step(step: Dictionary, injected: bool) -> void:
	_step = step
	_step_title.text = str(step.get("title", ""))
	_step_body.text = str(step.get("body", ""))
	var points: Array = step.get("points", [])
	var lines: Array[String] = []
	for point in points:
		lines.append("  *  %s" % str(point))
	_step_points.text = "\n".join(lines)
	_step_callout.text = str(step.get("callout", ""))
	if injected:
		_step_title.text = "EXTRA HELP  -  %s" % _step_title.text
	_show_only(["continue"])

func _show_checkpoint_step(cp: Dictionary) -> void:
	_card = CheckpointCard.new()
	_card.responded.connect(func(response): responded.emit(response))
	_card.reveal_requested.connect(func(): reveal_requested.emit())
	_card_holder.add_child(_card)
	# The card builds its UI in _ready(), so it is shown on the next idle frame.
	_card.show_checkpoint.call_deferred(cp)
	_show_only(["hint", "reveal"])

func _show_maze_step(cp: Dictionary) -> void:
	_maze = MazePanel.new()
	_maze.responded.connect(func(response): responded.emit(response))
	_maze.walk_changed.connect(func(path: String, state: String):
		if _caption_label != null:
			_caption_label.text = "walk = %s   now in %s" % [path if path != "" else "(empty)", state])
	_card_holder.add_child(_maze)
	# show_maze() builds the rooms in _ready(), so defer it one idle frame.
	_maze.show_maze.call_deferred(cp.get("spec", {}), Checkpoint.prompt_of(cp), int(cp.get("escapes", 1)))
	_show_only(["hint", "reveal"])


func set_feedback(result: Dictionary) -> void:
	if _card != null:
		_card.set_feedback(result)
	if _maze != null:
		_maze.set_feedback(result)

## Full-module report card: score, stars, mastery, XP and what happens next.
func show_module_complete(summary: Dictionary) -> void:
	_step = {}
	_clear_card()
	_step_title.text = "MODULE COMPLETE  -  %s" % str(summary.get("title", ""))
	_step_body.text = str(summary.get("headline", ""))
	var stars := int(summary.get("stars", 0))
	_step_points.text = "\n".join([
		"  *  stars: %s" % _stars_line(stars),
		"  *  score: %.0f%%   (first-try answers: %d / %d)" % [
			float(summary.get("score", 0.0)), int(summary.get("first_try", 0)), int(summary.get("checkpoints", 0))],
		"  *  mastery estimate: %.0f%%   ->   %s" % [
			float(summary.get("mastery_pct", 0.0)), "MASTERED" if bool(summary.get("mastered", false)) else "not yet"],
		"  *  misses: %d   remedies: %d   practice rounds: %d" % [
			int(summary.get("misses", 0)), int(summary.get("remedies", 0)), int(summary.get("practice_rounds", 0))],
		"  *  xp earned this module: %d" % int(summary.get("xp", 0)),
	])
	_step_callout.text = "Press Continue to move on to the next topic."
	_show_only(["continue"])
	_refresh_hud()

func _stars_line(stars: int) -> String:
	return "*".repeat(clampi(stars, 0, 3)) + "-".repeat(clampi(3 - stars, 0, 3))

## Keep the header honest: progress, HUD and mastery bar always reflect the
## engine, whatever step happens to be on screen.
func _refresh_hud() -> void:
	if engine == null:
		return
	_title_label.text = engine.module_title()
	_progress_label.text = "%s   |   %s" % [engine.progress_text(), engine.checkpoint_progress_text()]
	var level := 1
	var title := ""
	var xp := 0
	var streak := 0
	if engine.gamification != null:
		level = int(engine.gamification.get_level())
		title = str(engine.gamification.get_level_title())
		xp = int(engine.gamification.total_xp)
		streak = int(engine.gamification.streak)
	_hud_label.text = "LV %d %s   |   %d XP   |   streak x%d" % [level, title, xp, streak]
	_mastery_bar.value = engine.mastery_pct()

func _show_only(which: Array) -> void:
	_continue_button.visible = which.has("continue")
	_hint_button.visible = which.has("hint")
	_reveal_button.visible = which.has("reveal")
	_board_button.visible = which.has("board")
	_exit_button.visible = which.has("exit")
	if which.has("continue"):
		_continue_button.text = "Continue >>"

func _clear_card() -> void:
	if _card != null:
		_card.queue_free()
		_card = null
	if _maze != null:
		_maze.queue_free()
		_maze = null

func _on_hint() -> void:
	if engine == null:
		return
	var hint: String = str(engine.current_hint())
	if hint == "":
		_toasts.announce("No hint for this one - re-read the question slowly.", "info", 2.5)
		return
	if _card != null:
		_card.set_feedback({"correct": false, "message": "HINT: %s" % hint, "misses": 0})

func _task_lines(task: Dictionary) -> Array:
	if task.is_empty():
		return []
	var accept: Array = task.get("accept", [])
	var reject: Array = task.get("reject", [])
	var lines: Array = [str(task.get("instruction", ""))]
	if not accept.is_empty():
		lines.append("must be ACCEPTED: %s" % ", ".join(_as_text(accept)))
	if not reject.is_empty():
		lines.append("must be REJECTED: %s" % ", ".join(_as_text(reject)))
	return lines

func _as_text(values: Array) -> Array:
	var out: Array = []
	for value in values:
		out.append(str(value) if str(value) != "" else "(empty string)")
	return out

func _make_button(text: String, color: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 56)
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	button.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	button.add_theme_stylebox_override("normal", _style(color, 12))
	button.add_theme_stylebox_override("hover", _style(color.lightened(0.18), 12))
	button.add_theme_stylebox_override("pressed", _style(color.darkened(0.22), 12))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return button

func _style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style
