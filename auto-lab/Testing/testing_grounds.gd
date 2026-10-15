extends Node3D
## Main controller for the Testing Grounds VR scene.
## Handles the full flow: Profile Setup → Algorithm Selection → Pretest → Analysis → Adaptive Learning → Post Test → Results.

const SessionManager = preload("res://Testing/session_manager.gd")
const QuestionBank = preload("res://Testing/Data/question_bank.gd")
const AlgorithmCatalog = preload("res://Testing/Algorithms/algorithm_catalog.gd")
const LessonEngine = preload("res://Testing/Lessons/lesson_engine.gd")
const LessonLibrary = preload("res://Testing/Lessons/lesson_library.gd")
const LessonVoice = preload("res://Testing/Lessons/lesson_voice.gd")

# Every algorithm description now lives in ONE place: AlgorithmCatalog
# (Testing/Algorithms/algorithm_catalog.gd). The briefing, the selection buttons
# and the confirm panel all read catalog_briefing()/catalog_tagline(), so the
# three can never drift apart.

# UI references
@onready var viewport: SubViewport = $SubViewport
@onready var sprite: Sprite3D = $Billboard
@onready var title_label: Label = $SubViewport/Root/Center/Panel/VBox/TitleContainer/Title
@onready var content_box: VBoxContainer = $SubViewport/Root/Center/Panel/VBox/Content
@onready var question_label: Label = $SubViewport/Root/Center/Panel/VBox/Content/QuestionLabel
@onready var options_box: VBoxContainer = $SubViewport/Root/Center/Panel/VBox/Content/OptionsBox
@onready var feedback_label: Label = $SubViewport/Root/Center/Panel/VBox/Content/FeedbackLabel
@onready var progress_label: Label = $SubViewport/Root/Center/Panel/VBox/Content/ProgressLabel
@onready var back_button: Button = $SubViewport/Root/Center/Panel/VBox/ButtonBox/BackButton
@onready var next_button: Button = $SubViewport/Root/Center/Panel/VBox/ButtonBox/NextButton
@onready var workshop: Node3D = $"../AutomataWorkshopWhiteboard"
@onready var stats_board: Node3D = $"../StatsBoard"

# Full-screen overlay references (desktop mode only)
@onready var overlay_layer: CanvasLayer = $OverlayLayer
@onready var overlay_rect: TextureRect = $OverlayLayer/OverlayRect

# Session manager
var session: SessionManager

# UI state
var _last_mouse_pos := Vector2(-1, -1)
var _is_pressed := false
var _lasers := {}
var _desktop_mouse_down := false

# Profile setup state
var _profile_name: String = ""
var _profile_gender: String = "Male"
var _profile_age: int = 18
var _profile_familiar: bool = false
# The age is entered through an on-screen keypad. Because the keypad edits a
# string (digits get appended / removed) we keep the raw text here and only
# convert it to an int when the user presses Continue.
var _profile_age_str: String = ""

# Adaptive learning state
var _learning_skill: String = ""
var _challenge_index: int = 0
var _challenge_correct: int = 0
var _challenge_total: int = 0
var _challenge_answered: bool = false
var _current_challenge: Dictionary = {}

# Analysis state
var _analysis_skill_index: int = 0
var _analysis_skills: Array = []
var _adaptive_review_pass: bool = false

# Results state
var _results: Dictionary = {}

# DFA-centered lesson navigation
var _in_dfa_lesson := false
var _dfa_lesson_index := 0
var _lesson_engine: LessonEngine
## Narrator for lesson panels. Lines with a recorded clip (res://Audio/Voice/
## <line_id>.ogg) play that clip; lines WITHOUT one fall back to the OS
## text-to-speech voice, so every panel is audible out of the box.
var _lesson_voice: LessonVoice
var _dfa_practice_index := 0
var _dfa_practice_skill := "simulation"
var _dfa_practice_answered := false
var _dfa_practice_board_active := false
var _dfa_board_practice_index := 0
var _dfa_board_practice_active := false
var _dfa_board_practice_skill := "simulation"
## Signature (instruction + accepted/rejected) of the task currently loaded on
## the whiteboard. Re-pushing the same task is a no-op, so navigating Back and
## forward again never wipes a build the learner is halfway through.
var _board_task_signature := ""

# Workshop (automata builder) task navigation during a skill's interactive phase
var _workshop_phase := false
var _workshop_task_index := 0
# True while the whiteboard is paired with a multiple-choice challenge (so the
# board's Check task only gives feedback and does NOT advance the lesson).
var _adaptive_board_paired := false

# --- Free-build sandbox (custom automata during learning) ---
var _in_free_build := false
var _free_build_from_lesson := false
## True while a TEST screen (pretest / post-test / algorithm select / results)
## is the active panel. In VR the whiteboard stays visible in the room during
## those screens, so this flag keeps its Check task a harmless sandbox: nothing
## built on it may reach the knowledge tracer or the session record.
var _test_screen_active := false
# --- Algorithm-driven mastery termination ---
var _terminated_by_algorithm := false
var _mastered_skills: Array = []
# --- Algorithm library browsing ---
var _library_view: int = -1

# ===== ADAPTIVE REMEDIATION ================================================
# When the authored content and the practice set run out and the knowledge
# tracer still does NOT consider the skill learned, the room re-explains the
# exact areas the learner missed and re-asks ONLY those questions. This repeats
# until the algorithm says LEARNED (or the caps below are reached, so a learner
# is never trapped in an endless loop and always reaches the post test).

## Extra explain/re-ask rounds already spent, per skill.
var _remedy_rounds: Dictionary = {}
## Indices into LessonLibrary.adaptive_questions(skill) answered WRONG.
var _wrong_challenges: Dictionary = {}
## The order this skill's questions will be asked in the current round. It is
## rebuilt from performance every round, so the missed items come first.
var _challenge_queue: Array = []
## Cursor inside _challenge_queue.
var _challenge_queue_pos := 0
## How many times the whole weak-skill set has been revisited end to end.
var _weak_sweeps := 0
## Set when Back is pressed on the remedy screen: the learner re-reads the
## lecture and Next must flow STRAIGHT back into the targeted re-ask, without
## running the phase-6 decision (and its remedy counter) a second time.
var _resume_reask := false

## Re-explain/re-ask rounds allowed per skill before the room moves on.
const MAX_REMEDY_ROUNDS := 3
## How many of the six skills the tracer must call LEARNED before the post test
## unlocks. Below this the room keeps teaching the weak topics.
const MASTERY_GATE_SKILLS := 5
## How many extra end-to-end sweeps over the weak skills are allowed before the
## post test unlocks regardless, so the session always terminates.
const MAX_WEAK_SKILL_SWEEPS := 2

func _ready() -> void:
	# Phase progress (Pretest -> Learning -> Adaptive -> Post Test) and the
	# adaptive-learning stopwatch. Added first so they survive the early returns
	# below. DESKTOP: flat screen overlays. VR: a CanvasLayer never renders in a
	# headset, so the same readout floats in the room above the main panel
	# instead (RoomHUD).
	add_child(load("res://Testing/phase_hud.gd").new())
	add_child(load("res://Testing/Lessons/counting_timer_overlay.gd").new())
	if InputMode.is_vr():
		var room_hud: Node3D = load("res://Testing/room_hud.gd").new()
		# Just above the main panel billboard (panel at y=2, 3 m tall).
		room_hud.position = Vector3(0, 3.95, -4)
		add_child(room_hud)
	# The same UI is always displayed on the in-room billboard in both desktop and VR.
	if viewport and sprite:
		sprite.texture = viewport.get_texture()
	if overlay_rect:
		overlay_rect.texture = viewport.get_texture()
	if overlay_layer:
		overlay_layer.visible = false
	if sprite:
		sprite.visible = false

	# Connect buttons
	if back_button:
		back_button.pressed.connect(_on_back_pressed)
	if next_button:
		next_button.pressed.connect(_on_next_pressed)
	if workshop:
		workshop.evaluated.connect(_on_workshop_evaluated)
		workshop.skipped.connect(_on_workshop_skipped)
		workshop.set_active(false)

	# Narrator: a recorded clip wins per line; when a line has NO clip the OS
	# text-to-speech voice reads it instead, so no panel is silently voiceless.
	_lesson_voice = LessonVoice.new(self)
	_lesson_voice.clip_root = "res://Audio/Voice"
	_lesson_voice.system_tts = true
	_lesson_voice.enabled = SessionBridge.voice_enabled

	# The SessionBridge owns the single live session shared with the separate
	# Pretest / Post-test room, so returning here keeps all answers and states.
	session = SessionBridge.get_session()
	if SessionBridge.test_mode == "learning_demo":
		SessionBridge.test_mode = ""
		_analysis_skills = ["simulation", "identification", "definition", "building", "set_builder", "list"]
		_enter_learning_room()
		_begin_dfa_lesson()
		return

	# The algorithm is chosen INSIDE the Grounds now: the learner is briefed on
	# how each algorithm learns FIRST, then picks one. A fresh arrival
	# (selected_algorithm < 0) simply starts at the briefing - it no longer
	# bounces out to a separate Algorithm Select scene.
	if session.selected_algorithm >= 0:
		session.set_algorithm_type(session.selected_algorithm)
	gamification_sync()

	# If we just came back from the Pretest room (Analysis) or the Post-test room
	# (Results), show the correct next screen instead of the main menu.
	match session.state:
		SessionManager.SessionState.ANALYSIS:
			_show_analysis()
			return
		SessionManager.SessionState.COMPLETE:
			_show_results()
			return

	_enter_test_panel()
	_show_algorithm_briefing()

## Refresh the in-scene gamification/stats readout from the shared session.
## The gamification tracker (XP, streaks, badges) lives on the session object
## so it survives scene changes; calling this re-reads it into the panel.
func gamification_sync() -> void:
	pass
func _process(_delta: float) -> void:
	# The lesson board may stay visible beside the lesson panel. It must not
	# prevent the panel billboard from receiving pointer input.
	_update_pointer()
	_sync_stats_board()

func _input(event: InputEvent) -> void:
	# Track the real left mouse button so Desktop mode can click the panel.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_desktop_mouse_down = event.pressed
	# In desktop mode forward keyboard input to the SubViewport so text fields
	# (e.g. the name LineEdit) can be typed normally on a physical keyboard.
	if InputMode.is_desktop():
		_forward_keyboard(event)

# ===== UI NAVIGATION =====

var _menu_stage := "briefing"  # "briefing" | "detail" | "select" | "explain"

func _show_algorithm_briefing() -> void:
	_menu_stage = "briefing"
	title_label.text = "HOW EACH ALGORITHM LEARNS"
	_clear_content()
	question_label.text = "Welcome to the DFA Testing Grounds.\n\nThis adaptive system walks you through:\n1. Pretest (covers all 6 DFA skill areas)\n2. Knowledge Analysis\n3. DFA Lesson (one course, whiteboard + practice)\n4. Adaptive Review (weakest topics first)\n5. Post Test\n\nBefore you begin, read HOW each knowledge-tracing algorithm learns. Only ONE runs during your session, so runs can be compared fairly. When you are ready, choose the one that will drive it."
	question_label.visible = true

	# One briefing button per algorithm, in the shared new format (catalog).
	for algo_type in AlgorithmCatalog.catalog_all_types():
		var btn := Button.new()
		btn.text = "%s\n%s" % [AlgorithmCatalog.catalog_name(algo_type), AlgorithmCatalog.catalog_tagline(algo_type)]
		btn.custom_minimum_size = Vector2(800, 60)
		btn.add_theme_font_size_override("font_size", 18)
		btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
		btn.add_theme_color_override("font_pressed_color", Color(0.8, 0.85, 1, 1))
		btn.add_theme_stylebox_override("normal", _create_button_style(Color(0.16, 0.28, 0.62, 1)))
		btn.add_theme_stylebox_override("hover", _create_button_style(Color(0.3, 0.48, 0.95, 1)))
		btn.add_theme_stylebox_override("pressed", _create_button_style(Color(0.1, 0.19, 0.45, 1)))
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		btn.pressed.connect(_show_algorithm_detail.bind(algo_type))
		options_box.add_child(btn)

	# Advance straight to the selection phase (after the briefing).
	var choose_btn := Button.new()
	choose_btn.text = "Choose my algorithm >>"
	choose_btn.custom_minimum_size = Vector2(800, 50)
	choose_btn.add_theme_font_size_override("font_size", 20)
	choose_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	choose_btn.add_theme_stylebox_override("normal", _create_button_style(Color(0.1, 0.55, 0.35, 1)))
	choose_btn.add_theme_stylebox_override("hover", _create_button_style(Color(0.15, 0.7, 0.45, 1)))
	choose_btn.add_theme_stylebox_override("pressed", _create_button_style(Color(0.07, 0.4, 0.25, 1)))
	choose_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	choose_btn.pressed.connect(_show_algorithm_select)
	options_box.add_child(choose_btn)

	feedback_label.text = ""
	progress_label.text = ""
	back_button.visible = true
	back_button.text = "Back to Lab"
	next_button.visible = false

func _show_algorithm_detail(algo_type: int) -> void:
	_menu_stage = "detail"
	title_label.text = "HOW IT LEARNS"
	_clear_content()
	question_label.text = AlgorithmCatalog.catalog_briefing(algo_type)
	question_label.visible = true

	var back_btn := Button.new()
	back_btn.text = "<< Back to briefing"
	back_btn.custom_minimum_size = Vector2(800, 50)
	back_btn.add_theme_font_size_override("font_size", 20)
	back_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	back_btn.add_theme_stylebox_override("normal", _create_button_style(Color(0.16, 0.28, 0.62, 1)))
	back_btn.add_theme_stylebox_override("hover", _create_button_style(Color(0.3, 0.48, 0.95, 1)))
	back_btn.add_theme_stylebox_override("pressed", _create_button_style(Color(0.1, 0.19, 0.45, 1)))
	back_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	back_btn.pressed.connect(_show_algorithm_briefing)
	options_box.add_child(back_btn)

	var pick_btn := Button.new()
	pick_btn.text = "Pick %s" % AlgorithmCatalog.catalog_callout(algo_type)
	pick_btn.custom_minimum_size = Vector2(800, 50)
	pick_btn.add_theme_font_size_override("font_size", 20)
	pick_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	pick_btn.add_theme_stylebox_override("normal", _create_button_style(Color(0.1, 0.55, 0.35, 1)))
	pick_btn.add_theme_stylebox_override("hover", _create_button_style(Color(0.15, 0.7, 0.45, 1)))
	pick_btn.add_theme_stylebox_override("pressed", _create_button_style(Color(0.07, 0.4, 0.25, 1)))
	pick_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	pick_btn.pressed.connect(_on_algorithm_selected.bind(algo_type))
	options_box.add_child(pick_btn)

	feedback_label.text = ""
	progress_label.text = ""
	back_button.visible = false
	next_button.visible = false

func _show_algorithm_select() -> void:
	_menu_stage = "select"
	title_label.text = "CHOOSE YOUR ALGORITHM"
	_clear_content()
	question_label.text = "Pick the ONE algorithm that will drive your whole session. Its live parameters and mastery states appear on the in-room Stats Board."
	question_label.visible = true

	for algo_type in AlgorithmCatalog.catalog_all_types():
		var btn := Button.new()
		btn.text = "%s\n%s" % [AlgorithmCatalog.catalog_name(algo_type), AlgorithmCatalog.catalog_tagline(algo_type)]
		btn.custom_minimum_size = Vector2(800, 60)
		btn.add_theme_font_size_override("font_size", 18)
		btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
		btn.add_theme_color_override("font_pressed_color", Color(0.8, 0.85, 1, 1))
		btn.add_theme_stylebox_override("normal", _create_button_style(Color(0.16, 0.28, 0.62, 1)))
		btn.add_theme_stylebox_override("hover", _create_button_style(Color(0.3, 0.48, 0.95, 1)))
		btn.add_theme_stylebox_override("pressed", _create_button_style(Color(0.1, 0.19, 0.45, 1)))
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		btn.pressed.connect(_on_algorithm_selected.bind(algo_type))
		options_box.add_child(btn)

	feedback_label.text = ""
	progress_label.text = ""
	back_button.visible = true
	back_button.text = "Back"
	next_button.visible = false

func _on_algorithm_selected(algo_type: int) -> void:
	session.set_algorithm_type(algo_type)
	_show_algorithm_explanation(algo_type)

func _show_algorithm_explanation(algo_type: int) -> void:
	_menu_stage = "explain"
	title_label.text = "ALGORITHM CONFIRM"
	_clear_content()
	question_label.text = "You picked: %s\n\n%s\n\nOnly this algorithm runs during the session, so runs can be compared fairly. Its parameters and live mastery states are shown on the in-room Stats Board." % [AlgorithmCatalog.catalog_name(algo_type), AlgorithmCatalog.catalog_briefing(algo_type)]
	question_label.visible = true
	_clear_options()

	var continue_btn := Button.new()
	continue_btn.text = "Continue" if SessionBridge.skip_profile_collection else "Continue to Profile Setup"
	continue_btn.custom_minimum_size = Vector2(800, 50)
	continue_btn.add_theme_font_size_override("font_size", 20)
	continue_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	continue_btn.add_theme_stylebox_override("normal", _create_button_style(Color(0.1, 0.55, 0.35, 1)))
	continue_btn.add_theme_stylebox_override("hover", _create_button_style(Color(0.15, 0.7, 0.45, 1)))
	continue_btn.add_theme_stylebox_override("pressed", _create_button_style(Color(0.07, 0.4, 0.25, 1)))
	continue_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	continue_btn.pressed.connect(_on_algorithm_confirmed)
	options_box.add_child(continue_btn)
	feedback_label.text = ""
	progress_label.text = ""
	back_button.visible = true
	back_button.text = "Back"
	next_button.visible = false

func _on_algorithm_confirmed() -> void:
	# Dev/privacy toggle: when profile collection is skipped, flow Algorithm
	# Select -> Pretest. Otherwise collect the profile first.
	if SessionBridge.skip_profile_collection:
		_show_pretest_intro()
	else:
		_show_profile_setup()

# ===== PROFILE SETUP =====

func _show_profile_setup() -> void:
	title_label.text = "PROFILE SETUP"
	_clear_content()

	# Reset the keypad state so a previously entered (partial) age doesn't leak
	# in when the user opens the profile screen again.
	_profile_age_str = ""
	_profile_age = 18

	question_label.text = "Please enter your details before starting the pretest:"
	question_label.visible = true
	_clear_options()

	# Name input
	var name_label := Label.new()
	name_label.text = "Name:"
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	options_box.add_child(name_label)

	var name_input := LineEdit.new()
	name_input.placeholder_text = "Enter your name"
	name_input.custom_minimum_size = Vector2(800, 40)
	name_input.add_theme_font_size_override("font_size", 18)
	name_input.add_theme_stylebox_override("normal", _create_input_style())
	name_input.add_theme_stylebox_override("focus", _create_input_style())
	name_input.text_changed.connect(func(text): _profile_name = text)
	options_box.add_child(name_input)

	# Gender selection
	var gender_label := Label.new()
	gender_label.text = "Gender:"
	gender_label.add_theme_font_size_override("font_size", 18)
	gender_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	options_box.add_child(gender_label)

	# GENDER: two explicit buttons. The currently-selected option is highlighted
	# green so the user can always see which one is active (the previous version
	# styled both buttons identically, making selection invisible/broken).
	var gender_box := HBoxContainer.new()
	gender_box.add_theme_constant_override("separation", 10)
	options_box.add_child(gender_box)

	var male_btn := Button.new()
	var female_btn := Button.new()
	var gender_group := ButtonGroup.new()

	# Recolour both buttons so the active gender is green and the other blue.
	var style_gender := func():
		var green := Color(0.1, 0.55, 0.35, 1)
		var blue := Color(0.16, 0.28, 0.62, 1)
		male_btn.add_theme_stylebox_override("normal", _create_button_style(green if _profile_gender == "Male" else blue))
		female_btn.add_theme_stylebox_override("normal", _create_button_style(green if _profile_gender == "Female" else blue))

	for btn in [male_btn, female_btn]:
		btn.custom_minimum_size = Vector2(390, 44)
		btn.toggle_mode = true
		btn.button_group = gender_group
		btn.add_theme_font_size_override("font_size", 18)
		btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
		btn.add_theme_stylebox_override("hover", _create_button_style(Color(0.3, 0.48, 0.95, 1)))
		btn.add_theme_stylebox_override("pressed", _create_button_style(Color(0.1, 0.19, 0.45, 1)))
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		gender_box.add_child(btn)

	male_btn.text = "Male"
	female_btn.text = "Female"
	male_btn.button_pressed = true
	style_gender.call()
	male_btn.pressed.connect(func():
		_profile_gender = "Male"
		style_gender.call()
	)
	female_btn.pressed.connect(func():
		_profile_gender = "Female"
		style_gender.call()
	)

	# --- Age input via an on-screen numeric keypad ---
	# A SpinBox relies on keyboard focus which is awkward on a panel (and
	# impossible in VR), so we build a real numeric keypad instead. Tapping the
	# digit buttons builds the age string one digit at a time, with Del/Clear
	# to fix mistakes, and a live readout label shows the current value.
	var age_label := Label.new()
	age_label.text = "Age:"
	age_label.add_theme_font_size_override("font_size", 18)
	age_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	options_box.add_child(age_label)

	# Live readout of the age currently being typed on the keypad.
	var age_display := Label.new()
	age_display.text = "-"
	age_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	age_display.add_theme_font_size_override("font_size", 34)
	age_display.add_theme_color_override("font_color", Color(0.7, 0.9, 1, 1))
	age_display.custom_minimum_size = Vector2(800, 50)
	age_display.add_theme_stylebox_override("normal", _create_input_style())
	options_box.add_child(age_display)

	# Refresh the readout label after every keypad press.
	var refresh_age := func():
		age_display.text = _profile_age_str if _profile_age_str != "" else "-"

	# Append a digit (capped at 3 digits so the age stays inside 5–100).
	var press_digit := func(digit: String):
		if _profile_age_str.length() < 3:
			_profile_age_str += digit
		refresh_age.call()

	# Remove the trailing digit ("Del" button).
	var press_back := func():
		if _profile_age_str.length() > 0:
			_profile_age_str = _profile_age_str.substr(0, _profile_age_str.length() - 1)
			refresh_age.call()

	# Clear the whole age ("C" button).
	var press_clear := func():
		_profile_age_str = ""
		refresh_age.call()

	# Helper that builds a styled keypad button.
	var make_key := func(label: String) -> Button:
		var kb := Button.new()
		kb.text = label
		kb.custom_minimum_size = Vector2(120, 46)
		kb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		kb.add_theme_font_size_override("font_size", 22)
		kb.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		kb.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
		kb.add_theme_color_override("font_pressed_color", Color(0.8, 0.85, 1, 1))
		kb.add_theme_stylebox_override("normal", _create_button_style(Color(0.16, 0.28, 0.62, 1)))
		kb.add_theme_stylebox_override("hover", _create_button_style(Color(0.3, 0.48, 0.95, 1)))
		kb.add_theme_stylebox_override("pressed", _create_button_style(Color(0.1, 0.19, 0.45, 1)))
		kb.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		return kb

	# GridContainer arranges the keys 3 per row, centered under the readout.
	var keypad := GridContainer.new()
	keypad.columns = 3
	keypad.add_theme_constant_override("h_separation", 10)
	keypad.add_theme_constant_override("v_separation", 10)
	keypad.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	options_box.add_child(keypad)

	# Digits 1–9.
	for d in ["1", "2", "3", "4", "5", "6", "7", "8", "9"]:
		var kb: Button = make_key.call(d)
		kb.pressed.connect(press_digit.bind(d))
		keypad.add_child(kb)

	# Last keypad row: Del (backspace) / 0 / Clear.
	var back: Button = make_key.call("Del")
	back.pressed.connect(press_back)
	keypad.add_child(back)

	var zero: Button = make_key.call("0")
	zero.pressed.connect(press_digit.bind("0"))
	keypad.add_child(zero)

	var clear: Button = make_key.call("C")
	clear.pressed.connect(press_clear)
	keypad.add_child(clear)

	# --- Name virtual keypad (VR-friendly) ---
	# The name LineEdit still accepts a physical keyboard on desktop, but VR users
	# can tap A–Z on this on-screen board; both stay in sync via _profile_name.
	var name_key_label := Label.new()
	name_key_label.text = "Name keypad (tap letters):"
	name_key_label.add_theme_font_size_override("font_size", 16)
	name_key_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	options_box.add_child(name_key_label)
	var name_keypad := GridContainer.new()
	name_keypad.columns = 7
	name_keypad.add_theme_constant_override("h_separation", 6)
	name_keypad.add_theme_constant_override("v_separation", 6)
	name_keypad.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	options_box.add_child(name_keypad)
	for letter in "ABCDEFGHIJKLMNOPQRSTUVWXYZ":
		var ltr := letter
		var letter_key: Button = make_key.call(ltr)
		letter_key.custom_minimum_size = Vector2(72, 42)
		letter_key.pressed.connect(func():
			_profile_name += ltr
			name_input.text = _profile_name
		)
		name_keypad.add_child(letter_key)
	var space_n: Button = make_key.call("SPACE")
	space_n.custom_minimum_size = Vector2(140, 42)
	space_n.pressed.connect(func():
		_profile_name += " "
		name_input.text = _profile_name
	)
	name_keypad.add_child(space_n)
	var del_n: Button = make_key.call("DEL")
	del_n.custom_minimum_size = Vector2(90, 42)
	del_n.pressed.connect(func():
		if _profile_name.length() > 0:
			_profile_name = _profile_name.substr(0, _profile_name.length() - 1)
			name_input.text = _profile_name
	)
	name_keypad.add_child(del_n)
	var clear_n: Button = make_key.call("CLEAR")
	clear_n.custom_minimum_size = Vector2(90, 42)
	clear_n.pressed.connect(func():
		_profile_name = ""
		name_input.text = ""
	)
	name_keypad.add_child(clear_n)

	# --- Familiarity: two explicit buttons (Yes / No) ---
	# Two separate buttons are clearer than a single toggling button.
	var familiar_label := Label.new()
	familiar_label.text = "Are you familiar with Automata Theory?"
	familiar_label.add_theme_font_size_override("font_size", 18)
	familiar_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	options_box.add_child(familiar_label)

	var familiar_box := HBoxContainer.new()
	familiar_box.add_theme_constant_override("separation", 10)
	options_box.add_child(familiar_box)

	# Style two buttons; the currently-selected choice gets a green highlight so
	# the user can always see which answer is active.
	var style_familiar := func(yes: Button, no: Button):
		var green := Color(0.1, 0.55, 0.35, 1)
		var blue := Color(0.16, 0.28, 0.62, 1)
		yes.add_theme_stylebox_override("normal", _create_button_style(green if _profile_familiar else blue))
		no.add_theme_stylebox_override("normal", _create_button_style(blue if _profile_familiar else green))

	var yes_btn := Button.new()
	yes_btn.text = "Yes, familiar"
	yes_btn.custom_minimum_size = Vector2(390, 44)
	yes_btn.add_theme_font_size_override("font_size", 18)
	yes_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	yes_btn.add_theme_stylebox_override("hover", _create_button_style(Color(0.3, 0.48, 0.95, 1)))
	yes_btn.add_theme_stylebox_override("pressed", _create_button_style(Color(0.1, 0.19, 0.45, 1)))
	yes_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	familiar_box.add_child(yes_btn)

	var no_btn := Button.new()
	no_btn.text = "No, not familiar"
	no_btn.custom_minimum_size = Vector2(390, 44)
	no_btn.add_theme_font_size_override("font_size", 18)
	no_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	no_btn.add_theme_stylebox_override("hover", _create_button_style(Color(0.3, 0.48, 0.95, 1)))
	no_btn.add_theme_stylebox_override("pressed", _create_button_style(Color(0.1, 0.19, 0.45, 1)))
	no_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	familiar_box.add_child(no_btn)

	# Apply the initial highlight and wire the two-button selection.
	style_familiar.call(yes_btn, no_btn)
	yes_btn.pressed.connect(func():
		_profile_familiar = true
		style_familiar.call(yes_btn, no_btn)
	)
	no_btn.pressed.connect(func():
		_profile_familiar = false
		style_familiar.call(yes_btn, no_btn)
	)

	# Continue button
	var continue_btn := Button.new()
	continue_btn.text = "Continue"
	continue_btn.custom_minimum_size = Vector2(800, 50)
	continue_btn.add_theme_font_size_override("font_size", 20)
	continue_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	continue_btn.add_theme_stylebox_override("normal", _create_button_style(Color(0.16, 0.28, 0.62, 1)))
	continue_btn.add_theme_stylebox_override("hover", _create_button_style(Color(0.3, 0.48, 0.95, 1)))
	continue_btn.add_theme_stylebox_override("pressed", _create_button_style(Color(0.1, 0.19, 0.45, 1)))
	continue_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	continue_btn.pressed.connect(_on_profile_continue)
	options_box.add_child(continue_btn)

	feedback_label.text = ""
	progress_label.text = ""
	back_button.visible = true
	back_button.text = "Back"
	next_button.visible = false

func _on_profile_continue() -> void:
	# Validate the name first.
	if _profile_name.is_empty():
		feedback_label.text = "Please enter your name."
		feedback_label.add_theme_color_override("font_color", Color(1, 0.5, 0.5, 1))
		return

	# Validate the age that was typed on the keypad (must be 5–100).
	if _profile_age_str.is_empty():
		feedback_label.text = "Please enter your age using the keypad."
		feedback_label.add_theme_color_override("font_color", Color(1, 0.5, 0.5, 1))
		return
	var parsed_age := _profile_age_str.to_int()
	if parsed_age < 5 or parsed_age > 100:
		feedback_label.text = "Age must be between 5 and 100."
		feedback_label.add_theme_color_override("font_color", Color(1, 0.5, 0.5, 1))
		return
	_profile_age = parsed_age

	session.save_profile(_profile_name, _profile_gender, _profile_age, _profile_familiar)
	feedback_label.text = ""
	_show_pretest_intro()

# ===== PRETEST =====

func _show_pretest_intro() -> void:
	title_label.text = "PRETEST"
	_clear_content()

	question_label.text = "You will now take the DFA pretest (Deterministic Finite Automata).\n\nThe questions cover 6 skill areas:\n\u2022 Simulation\n\u2022 Identification of Diagrams\n\u2022 DFA Definition and Parts\n\u2022 DFA Building\n\u2022 DFA from Set Builder\n\u2022 DFA from List\n\nAnswer each question to the best of your ability. Your results will determine your adaptive learning path."
	question_label.visible = true
	_clear_options()

	var start_btn := Button.new()
	start_btn.text = "Start Pretest"
	start_btn.custom_minimum_size = Vector2(800, 50)
	start_btn.add_theme_font_size_override("font_size", 20)
	start_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	start_btn.add_theme_stylebox_override("normal", _create_button_style(Color(0.16, 0.28, 0.62, 1)))
	start_btn.add_theme_stylebox_override("hover", _create_button_style(Color(0.3, 0.48, 0.95, 1)))
	start_btn.add_theme_stylebox_override("pressed", _create_button_style(Color(0.1, 0.19, 0.45, 1)))
	start_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	start_btn.pressed.connect(_on_start_pretest)
	options_box.add_child(start_btn)

	feedback_label.text = ""
	progress_label.text = ""
	back_button.visible = true
	back_button.text = "Back"
	next_button.visible = false

func _on_start_pretest() -> void:
	SessionBridge.test_mode = "pretest"
	get_tree().change_scene_to_file("res://Testing/TestRoom.tscn")

func _show_question() -> void:
	title_label.text = "PRETEST"
	_clear_content()

	var question: Dictionary = session.get_current_question()
	question_label.text = "Question %d/%d\n\n%s" % [session.get_current_question_number(), session.get_total_questions(), question["question"]]
	question_label.visible = true

	_clear_options()
	var options: Array = question["options"]
	for i in range(options.size()):
		var btn := Button.new()
		btn.text = options[i]
		btn.custom_minimum_size = Vector2(800, 0)
		btn.add_theme_font_size_override("font_size", 18)
		btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
		btn.add_theme_color_override("font_pressed_color", Color(0.8, 0.85, 1, 1))
		btn.add_theme_stylebox_override("normal", _create_option_style(Color(0.12, 0.15, 0.3, 1)))
		btn.add_theme_stylebox_override("hover", _create_option_style(Color(0.2, 0.25, 0.5, 1)))
		btn.add_theme_stylebox_override("pressed", _create_option_style(Color(0.1, 0.12, 0.25, 1)))
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		btn.pressed.connect(_on_answer_selected.bind(i))
		options_box.add_child(btn)

	feedback_label.text = ""
	progress_label.text = "Question %d of %d" % [session.get_current_question_number(), session.get_total_questions()]
	back_button.visible = false
	next_button.visible = false

func _on_answer_selected(selected_index: int) -> void:
	var result: Dictionary = session.submit_answer(selected_index)

	if result["complete"]:
		if session.state == SessionManager.SessionState.ANALYSIS:
			_show_analysis()
		elif session.state == SessionManager.SessionState.COMPLETE:
			_show_results()
	else:
		_show_question()

# ===== ANALYSIS =====

func _show_analysis() -> void:
	_enter_learning_room()
	title_label.text = "KNOWLEDGE ANALYSIS"
	_clear_content()

	var summary: Dictionary = session.get_analysis_summary()
	# get_skills_by_weakness() returns ALL 6 skills sorted weakest-first, so the
	# adaptive phase COVERS every topic but starts with the ones the learner was
	# actually weakest on in the pretest. Fresh remediation state for this run.
	_analysis_skills = session.get_skills_by_weakness()
	_analysis_skill_index = 0
	_adaptive_review_pass = false
	_remedy_rounds.clear()
	_wrong_challenges.clear()
	_challenge_queue.clear()
	_challenge_queue_pos = 0
	_weak_sweeps = 0

	question_label.text = "Based on your pretest results (used to drive knowledge-tracing), here is your analysis:\n\n"
	question_label.visible = true
	_clear_options()

	# Build skill summary text, already in the order the topics will be taught.
	var summary_text := ""
	for skill in _analysis_skills:
		var data: Dictionary = summary[skill]
		summary_text += "%s: %d/%d (%.1f%% accurate) - Know: %.1f%%\n" % [
			data["name"],
			data["correct"],
			data["total"],
			data["accuracy_percentage"],
			data["mastery_percentage"]
		]

	var weakest: String = str(_analysis_skills[0]) if not _analysis_skills.is_empty() else "definition"
	question_label.text += summary_text
	question_label.text += "\nWe will start with your weakest topic: %s.\n" % QuestionBank.get_skill_name(weakest)
	question_label.text += "\nA guided DFA lesson will now teach the whole topic (5-tuple, representations, whiteboard building, simulation, correctness) as ONE course, then adaptively review every topic in the order of your weaknesses. If the model decides you have not learned a topic yet, it will re-explain it and ask you the questions you got wrong again.\n\nClick Next to begin the DFA Lesson."

	back_button.visible = true
	back_button.text = "Back"
	next_button.visible = true
	next_button.text = "Start DFA Lesson"

# ===== DFA-CENTERED LESSON =====

func _begin_dfa_lesson() -> void:
	_in_dfa_lesson = true
	_dfa_lesson_index = 0
	_lesson_engine = LessonEngine.new(LessonLibrary.course_steps())
	_lesson_engine.voice = _lesson_voice
	_lesson_engine.start()
	_dfa_practice_index = 0
	_dfa_board_practice_index = 0
	_dfa_board_practice_active = false
	_dfa_board_practice_skill = "simulation"
	_forget_board_task()
	_show_dfa_lesson_step()

func _advance_lesson_step() -> void:
	if _lesson_engine:
		_lesson_engine.advance()
	_dfa_lesson_index = _lesson_engine.position if _lesson_engine else _dfa_lesson_index + 1

## Opens the whiteboard in FREE-BUILD sandbox mode (used by the DFA Lesson's
## "freebuild" step). The learner can design ANY automaton and explore how
## accept/reject depends on their structure. The board's "Done - exit sandbox"
## button routes back through _close_free_build() into the lesson flow.
func _open_free_build(from_lesson: bool) -> void:
	if workshop == null or workshop.builder is not Control:
		if from_lesson:
			_advance_lesson_step()
			_show_dfa_lesson_step()
		return
	_in_free_build = true
	_free_build_from_lesson = from_lesson
	_enter_learning_room()
	# The sandbox wipes the graph itself; the next real task must load fresh.
	_forget_board_task()
	workshop.builder.call("reset_for_free_build")
	workshop.builder.set("sandbox_exit_callback", func(): _close_free_build())
	workshop.set_active(true)
	_set_player_paused(true)
	question_label.text = "FREE BUILD SANDBOX\n\nDesign ANY automaton you like: tap Add node for a state, pick a symbol and connect states, toggle accepting, set the start - then type any string and press Simulate to watch it run. There is no right or wrong answer, just explore. Press \"Done - exit sandbox\" on the board when you are ready to continue."
	question_label.visible = true
	_clear_options()
	feedback_label.text = ""
	if from_lesson:
		progress_label.text = "DFA Lesson  -  free-build sandbox"
	else:
		progress_label.text = "Adaptive Learning  -  free-build sandbox"
	back_button.visible = false
	next_button.visible = false

## Closes the free-build sandbox and returns to the previous learning flow.
func _close_free_build() -> void:
	_in_free_build = false
	var from_lesson := _free_build_from_lesson
	_free_build_from_lesson = false
	if workshop:
		workshop.set_active(false)
	if sprite:
		sprite.visible = true
	_set_player_paused(false)
	if from_lesson:
		# Skip past the freebuild step itself and continue the lesson.
		_advance_lesson_step()
		_show_dfa_lesson_step()

func _show_dfa_lesson_step() -> void:
	# Safety net: NO lesson step may ever leave the player frozen. Every board
	# step lives in the walkable room, so movement is always restored here.
	_unfreeze_player()
	if _lesson_engine == null:
		_lesson_engine = LessonEngine.new(LessonLibrary.course_steps())
		_lesson_engine.voice = _lesson_voice
	if _lesson_engine.finished():
		_finish_dfa_lesson()
		return
	_dfa_lesson_index = _lesson_engine.position
	var step: Dictionary = _lesson_engine.current()
	match step["m"]:
		"content":
			_show_dfa_content(step)
		"freebuild":
			_open_free_build(true)
		"demo":
			_open_dfa_workshop(step)
		"practice":
			_dfa_practice_skill = step["skill"]
			_dfa_practice_index = 0
			var practice_tasks: Array = LessonLibrary.workshop_tasks(step["skill"])
			if workshop != null and workshop.builder is Control and not practice_tasks.is_empty():
				# Board-task practice: build & verify each DFA on the board to proceed.
				_dfa_board_practice_skill = step["skill"]
				_dfa_board_practice_active = true
				_dfa_board_practice_index = 0
				_open_dfa_board_practice(step["skill"], practice_tasks[0])
			else:
				# Question practice: answer each multiple-choice question to proceed.
				_show_dfa_practice(step)

## Render one explanatory panel as labelled sections instead of a wall of text:
## WHERE YOU ARE (topic + step x of y) / WHAT THIS IS (lead) / KEY POINTS /
## REMEMBER THIS (callout) / UP NEXT. The learner can always answer "where am
## I, what does this mean, and what comes next?" from a single screen.
func _show_dfa_content(step: Dictionary) -> void:
	title_label.text = "DFA LESSON — %s" % step["title"]
	_clear_content()
	_enter_learning_room()
	_unfreeze_player()

	var lead := str(step.get("lead", ""))
	if lead.is_empty():
		lead = LessonLibrary.adaptive_text(step["skill"], "definition")
	var points: Array = step.get("points", [])
	var callout := str(step.get("callout", ""))

	# Fall back to the engine's own cursor when a step was not projected with
	# numbers. The fallback is computed up front because Dictionary.get()
	# evaluates its default argument eagerly, so inlining `_lesson_engine`
	# there would crash on a null engine.
	var fallback_no := 1
	var fallback_total := 1
	if _lesson_engine != null:
		fallback_no = _lesson_engine.position + 1
		fallback_total = _lesson_engine.step_count()
	var step_no := int(step.get("step_no", fallback_no))
	var step_total := int(step.get("step_total", fallback_total))
	var header := "TOPIC %s  ·  STEP %d OF %d" % [
		str(step.get("topic", QuestionBank.get_skill_name(step["skill"]))), step_no, maxi(step_total, step_no)]
	var subtitle := str(step.get("subtitle", ""))
	if subtitle != "":
		header += "\n" + subtitle

	var text := "%s\n\n%s\n\n%s" % [header, str(step.get("title", "")), lead]
	if not points.is_empty():
		text += "\n\nKEY POINTS\n" + "\n".join(points)
	if callout != "":
		text += "\n\nREMEMBER THIS\n" + callout
	var next_title := str(step.get("next_title", ""))
	if next_title != "":
		text += "\n\nUP NEXT\n" + next_title

	question_label.text = text
	question_label.visible = true
	_clear_options()
	feedback_label.text = ""
	progress_label.text = "DFA Lesson  ·  %s  ·  press Next to continue" % QuestionBank.get_skill_name(step["skill"])
	back_button.visible = _lesson_engine != null and _lesson_engine.position > 0
	back_button.text = "Back"
	next_button.visible = true
	next_button.text = "Next >>"
	# Narrate the FULL panel: recorded clip if one exists for this line, or the
	# OS text-to-speech voice if not — no audio file means the panel is still
	# spoken. Captions show the same text.
	var spoken := str(step.get("title", "")) + ". " + lead
	if not points.is_empty():
		spoken += " " + " ".join(points).replace("•", "")
	if callout != "":
		spoken += " Remember: " + callout
	_narrate_panel(spoken)

var _dfa_pending_explain: Dictionary = {}
var _dfa_pending_skill: Dictionary = {}

func _open_dfa_workshop(step: Dictionary) -> void:
	if workshop == null:
		_advance_lesson_step()
		_show_dfa_lesson_step()
		return
	# Show the "what does this mean" explanation first, then pass the build task.
	if step.has("explain") and step.get("explain", "") != "":
		_dfa_pending_skill = step
		_show_dfa_explanation(step)
		return
	_activate_dfa_board(step)

func _show_dfa_explanation(step: Dictionary) -> void:
	_enter_learning_room()
	title_label.text = "DFA LESSON — %s" % step["title"]
	_clear_content()
	question_label.text = "EXPLANATION — what does the language mean?\n\n%s" % step.get("explain", "")
	question_label.visible = true
	_clear_options()
	feedback_label.text = ""
	progress_label.text = "DFA Lesson  ·  first understand, then build"
	back_button.visible = _lesson_engine != null and _lesson_engine.position > 0
	back_button.text = "Back"
	next_button.visible = true
	next_button.text = "Build it on the Whiteboard"
	_narrate_panel(str(step.get("explain", "")))

func _activate_dfa_board(step: Dictionary) -> void:
	var task: Dictionary = step.get("task", {})
	_dfa_pending_skill = {}
	if workshop.builder is Control and not task.is_empty():
		_apply_board_task(task)
	_enter_learning_room()
	workshop.set_active(true)
	title_label.text = "DFA LESSON — %s" % step["title"]
	question_label.text = "Build it on the whiteboard.\n\nCreate states, toggle accepting, connect transitions, then press Check task to verify. The board accepts ANY correct construction — not just one specific one.\n\n%s" % step.get("task", {}).get("instruction", "")
	question_label.visible = true
	_clear_options()
	feedback_label.text = ""
	progress_label.text = "DFA Lesson  ·  Whiteboard"
	back_button.visible = _lesson_engine != null and _lesson_engine.position > 0
	back_button.text = "Back"
	next_button.visible = false

func _show_dfa_practice(step: Dictionary) -> void:
	title_label.text = "DFA LESSON — %s" % step["title"]
	_dfa_practice_answered = false
	_clear_content()
	_enter_learning_room()
	var challenges: Array = LessonLibrary.adaptive_questions(_dfa_practice_skill)
	if _dfa_practice_index >= challenges.size():
		# All questions for this skill are done → close the paired board, continue.
		_close_paired_board()
		_advance_lesson_step()
		_show_dfa_lesson_step()
		return
	var current: Dictionary = challenges[_dfa_practice_index]
	# Pair the whiteboard with this question. A question may carry its OWN
	# reference machine ("read the DFA on the board"); otherwise fall back to a
	# build task that matches the skill AND the question number.
	var has_reference := _pair_reference_board(current)
	var paired := false
	if not has_reference:
		paired = _pair_practice_board(_dfa_practice_skill, _dfa_practice_index)
	_dfa_practice_board_active = paired
	var hint := ""
	if has_reference:
		hint = "\n\nRefer to the DFA shown on the whiteboard to answer."
	elif paired:
		hint = "\n\nUse the whiteboard to build and test the automaton before choosing your answer."
	question_label.text = "Practice %d / %d\n\n%s%s" % [_dfa_practice_index + 1, challenges.size(), current["question"], hint]
	question_label.visible = true
	_clear_options()
	var options: Array = current["options"]
	for i in range(options.size()):
		var btn := Button.new()
		btn.text = options[i]
		btn.custom_minimum_size = Vector2(800, 0)
		btn.add_theme_font_size_override("font_size", 18)
		btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
		btn.add_theme_color_override("font_pressed_color", Color(0.8, 0.85, 1, 1))
		btn.add_theme_stylebox_override("normal", _create_option_style(Color(0.12, 0.15, 0.3, 1)))
		btn.add_theme_stylebox_override("hover", _create_option_style(Color(0.2, 0.25, 0.5, 1)))
		btn.add_theme_stylebox_override("pressed", _create_option_style(Color(0.1, 0.12, 0.25, 1)))
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		btn.pressed.connect(_on_dfa_practice_answer.bind(i))
		options_box.add_child(btn)
	feedback_label.text = ""
	progress_label.text = "DFA Lesson  ·  %s  ·  %s" % [QuestionBank.get_skill_name(_dfa_practice_skill), "whiteboard active — build/check freely, then answer" if paired else "answer the question"]
	back_button.visible = _lesson_engine != null and _lesson_engine.position > 0
	back_button.text = "Back"
	next_button.visible = false
	if has_reference:
		_narrate_panel("Refer to the DFA on the whiteboard. " + str(current["question"]))
	else:
		_narrate_panel(str(current["question"]))

## Activate the whiteboard with a task matching the practice skill + question.
func _pair_practice_board(skill: String, index: int) -> bool:
	if workshop == null or workshop.builder is not Control:
		return false
	var tasks: Array = LessonLibrary.workshop_tasks(skill)
	if tasks.is_empty():
		return false
	var task: Dictionary = tasks[index % tasks.size()]
	_apply_board_task(task)
	workshop.set_active(true)
	_set_player_paused(true)
	return true

## Board-referenced questions: a question may carry a "board" machine spec
## (authored in the lesson library). The whiteboard then displays that machine
## and the learner must READ it to answer ("Refer to the DFA on the board").
## The board runs display-only (the builder's reference mode): Check and Skip
## grade nothing, Simulate still works for experimentation.
## Returns true when a reference machine was loaded.
func _pair_reference_board(question: Dictionary) -> bool:
	if workshop == null or workshop.builder is not Control:
		return false
	var spec: Dictionary = question.get("board", {})
	if spec.is_empty():
		# A previous question's reference machine must not linger on the board.
		if bool(workshop.builder.get("reference_mode")):
			workshop.set_active(false)
		return false
	workshop.builder.call("load_machine_spec", spec,
		"REFERENCE DFA — read the machine on this board to answer the question.")
	workshop.set_active(true)
	return true

## Push a library-authored task into the builder — but ONLY when it is a new
## task. Back -> re-read -> Next must not wipe the machine the learner is
## halfway through, so the reset is guarded by a task signature (its instruction
## + accepted/rejected strings). Returns true when the board was (re)loaded.
func _apply_board_task(task: Dictionary) -> bool:
	if workshop == null or workshop.builder is not Control:
		return false
	var signature := "%s|%s|%s" % [str(task.get("instruction", "")), str(task.get("accept", [])), str(task.get("reject", []))]
	if signature == _board_task_signature:
		return false
	_board_task_signature = signature
	if task.has("accept") and task.has("reject") and not task["accept"].is_empty():
		workshop.builder.call("reset_for_task_lists",
			task.get("instruction", "Build the DFA on the whiteboard."),
			task["accept"], task["reject"])
	else:
		workshop.builder.call("reset_for_task",
			task.get("instruction", "Build the DFA on the whiteboard."),
			task.get("accepted", "aa"),
			task.get("rejected", "ab"))
	if task.get("seed", false):
		workshop.builder.call("seed_reference_graph")
	return true

## Forget the current task signature (the next task resets the board even if it
## repeats an earlier instruction). Called when a lesson / skill / sandbox starts.
func _forget_board_task() -> void:
	_board_task_signature = ""

func _close_paired_board() -> void:
	_dfa_practice_board_active = false
	_adaptive_board_paired = false
	if workshop:
		workshop.set_active(false)
	if sprite:
		sprite.visible = true
	_set_player_paused(false)

func _open_dfa_board_practice(skill: String, task: Dictionary) -> void:
	_dfa_board_practice_active = true
	_dfa_board_practice_skill = skill
	var skill_tasks: Array = LessonLibrary.workshop_tasks(skill)
	_enter_learning_room()
	_apply_board_task(task)
	workshop.set_active(true)
	_set_player_paused(true)
	question_label.text = "Whiteboard practice %d / %d - %s\n\n%s\n\nBuild the DFA on the board, then press Check task. Any correct construction is accepted; wrong attempts stay here until the build passes." % [_dfa_board_practice_index + 1, skill_tasks.size(), QuestionBank.get_skill_name(skill), task["instruction"]]
	question_label.visible = true
	_clear_options()
	feedback_label.text = ""
	progress_label.text = "DFA Lesson · Whiteboard practice · %s" % QuestionBank.get_skill_name(skill)
	back_button.visible = _lesson_engine != null and _lesson_engine.position > 0
	back_button.text = "Back"
	next_button.visible = false

func _on_dfa_practice_answer(selected_index: int) -> void:
	if _dfa_practice_answered:
		return
	var challenges: Array = LessonLibrary.adaptive_questions(_dfa_practice_skill)
	if _dfa_practice_index >= challenges.size():
		return
	var current: Dictionary = challenges[_dfa_practice_index]
	_dfa_practice_answered = true
	var correct: bool = selected_index == current["correct"]
	session.knowledge_tracer.record_learning_observation(_dfa_practice_skill, correct)
	feedback_label.text = ("Correct! " if correct else "Incorrect. ") + current.get("explanation", "")
	feedback_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6, 1) if correct else Color(1, 0.5, 0.5, 1))
	_narrate_panel(feedback_label.text)
	_dfa_practice_index += 1
	if _dfa_practice_index >= challenges.size():
		next_button.visible = true
		next_button.text = "Next Topic >>"
	else:
		next_button.visible = true
		next_button.text = "Next Question >>"
	# Back stays available: the learner may walk back through the questions of
	# this round (each one is shown unanswered again), or further into the lesson.
	back_button.visible = _lesson_engine != null and _lesson_engine.position > 0
	back_button.text = "Back"

func _handle_dfa_lesson_next() -> void:
	# Transition from the "explanation" step screen into the whiteboard build.
	if not _dfa_pending_skill.is_empty():
		var pending: Dictionary = _dfa_pending_skill
		_dfa_pending_skill = {}
		_activate_dfa_board(pending)
		return
	var step: Dictionary = _lesson_engine.current() if _lesson_engine else LessonLibrary.course_steps()[_dfa_lesson_index]
	match step["m"]:
		"content":
			_advance_lesson_step()
			_show_dfa_lesson_step()
		"practice":
			var challenges: Array = LessonLibrary.adaptive_questions(_dfa_practice_skill)
			if _dfa_practice_index >= challenges.size():
				# All questions answered → next topic.
				_close_paired_board()
				_advance_lesson_step()
				_show_dfa_lesson_step()
			else:
				# Still more questions — show the NEXT one (index already advanced
				# by _on_dfa_practice_answer) WITHOUT resetting to question 1.
				_show_dfa_practice(step)
		_:
			_advance_lesson_step()
			_show_dfa_lesson_step()

func _finish_dfa_lesson() -> void:
	_in_dfa_lesson = false
	# The guided lesson is complete; adaptive review then re-visits every one of
	# the six topics in the learner's personal weakness order, followed by the
	# post test.
	_start_adaptive_learning()

# ===== ADAPTIVE LEARNING =====

func _start_adaptive_learning() -> void:
	_enter_learning_room()
	_analysis_skill_index = 0
	_begin_learning_skill(_analysis_skills[_analysis_skill_index])

## Start (or restart) the adaptive sequence for one skill. Every per-skill
## counter is reset here EXCEPT the remediation bookkeeping, which survives on
## purpose: `_remedy_rounds` and `_wrong_challenges` are what let the room come
## back to this skill later and re-ask exactly the items that were missed.
func _begin_learning_skill(skill: String) -> void:
	_learning_skill = skill
	_challenge_index = 0
	_challenge_correct = 0
	_challenge_total = 0
	_challenge_answered = false
	_workshop_task_index = 0
	_workshop_phase = false
	_challenge_queue.clear()
	_challenge_queue_pos = 0
	_resume_reask = false
	_forget_board_task()
	session.start_adaptive_learning(_learning_skill)
	_show_learning_phase(0)

# ===== ADAPTIVE REMEDIATION ================================================

## The question set for the current skill: every choice checkpoint the module
## offers (practice pool first, then the lesson's own questions), so a re-ask
## round has enough "areas" to actually target what the learner got wrong.
func _challenge_list() -> Array:
	return LessonLibrary.review_questions(_learning_skill)

## Rebuild the order the questions are asked in, from performance data.
## `targeted_only` keeps just the items this learner got WRONG, which is what a
## re-ask round uses; otherwise the whole set is asked, missed items first.
func _build_challenge_queue(targeted_only := false) -> void:
	_challenge_queue = LessonLibrary.review_order(_wrong_indices(), _challenge_list().size(), targeted_only)
	_challenge_queue_pos = 0

## Indices of the current skill's questions answered wrong so far.
func _wrong_indices() -> Array:
	var wrong: Array = _wrong_challenges.get(_learning_skill, [])
	return wrong.duplicate()

## Remember a missed question so the re-ask round can target it.
func _note_wrong_challenge(index: int) -> void:
	var wrong: Array = _wrong_challenges.get(_learning_skill, [])
	if not wrong.has(index):
		wrong.append(index)
	_wrong_challenges[_learning_skill] = wrong

## Index into _challenge_list() of the question currently on screen, or -1.
func _current_challenge_index() -> int:
	if _challenge_queue_pos < 0 or _challenge_queue_pos >= _challenge_queue.size():
		return -1
	return int(_challenge_queue[_challenge_queue_pos])

## True when the tracer considers the current skill learned.
func _skill_is_learned() -> bool:
	return session.knowledge_tracer.is_learned(_learning_skill)

## How many of the six skills the tracer calls LEARNED.
func _mastered_skill_count() -> int:
	var mastered := 0
	for skill in session.knowledge_tracer.SKILL_ORDER:
		if session.knowledge_tracer.is_learned(str(skill)):
			mastered += 1
	return mastered

## The post test only unlocks once the algorithm considers the learner
## knowledgeable enough: at least MASTERY_GATE_SKILLS of the six skills learned.
func _ready_for_posttest() -> bool:
	return _mastered_skill_count() >= MASTERY_GATE_SKILLS

## Skills still not learned, weakest first (falls back to the full order).
func _weak_skills() -> Array:
	var out: Array = []
	for skill in session.get_skills_by_weakness():
		if not session.knowledge_tracer.is_learned(str(skill)):
			out.append(str(skill))
	if out.is_empty():
		out = session.get_skills_by_weakness()
	return out

## ADAPTIVE RE-EXPLANATION. The content and the practice set for this skill are
## exhausted, but the algorithm still does not call the skill learned. This
## panel explains WHY, recaps the idea, and then re-asks only the questions the
## learner actually got wrong. Rounds repeat until `is_learned` flips or
## MAX_REMEDY_ROUNDS is reached, so the session always terminates.
func _show_remedy_round() -> void:
	var skill := _learning_skill
	var rounds := int(_remedy_rounds.get(skill, 0)) + 1
	_remedy_rounds[skill] = rounds
	var challenges := _challenge_list()
	var wrong := _wrong_indices()
	_clear_content()
	_enter_learning_room()
	_unfreeze_player()

	var mastery := session.knowledge_tracer.get_mastery_percentage(skill)
	var text := "STILL LEARNING — %s" % QuestionBank.get_skill_name(skill)
	text += "\nRound %d of %d  ·  your score this round: %d/%d" % [
		rounds, MAX_REMEDY_ROUNDS, _challenge_correct, _challenge_total]
	text += "\n\n%s says this topic is not learned yet (mastery %.0f%%). " % [session.get_algorithm_label(), mastery]
	if wrong.is_empty():
		text += "You answered the practice set correctly, so the model simply needs more evidence — here is another pass over the same ground."
	else:
		text += "Let us re-explain the parts you missed and ask those again."

	var recap := LessonLibrary.recap(skill)
	if recap != "":
		text += "\n\nREMEMBER (the short version)\n" + recap

	if not wrong.is_empty():
		text += "\n\nWHAT YOU GOT WRONG (%d of %d)" % [wrong.size(), challenges.size()]
		for index in wrong:
			if index < 0 or index >= challenges.size():
				continue
			var item: Dictionary = challenges[index]
			text += "\n\nQ%d. %s\n→ %s" % [index + 1, str(item.get("question", "")), str(item.get("explanation", ""))]
		text += "\n\nUP NEXT\nThe same questions again, starting with the ones you missed."

	question_label.text = text
	question_label.visible = true
	_clear_options()
	feedback_label.text = ""
	progress_label.text = "Adaptive re-teach  ·  %s  ·  %s" % [QuestionBank.get_skill_name(skill), session.get_algorithm_label()]
	back_button.visible = true
	back_button.text = "Back"
	next_button.visible = true
	next_button.text = "Re-ask the ones I missed >>"
	# Spoken version of the remedy panel: headline + the short recap, so the
	# re-teach is audible without reading the whole list aloud.
	var spoken := "Still learning %s. Round %d of %d." % [
		QuestionBank.get_skill_name(skill), rounds, MAX_REMEDY_ROUNDS]
	if recap != "":
		spoken += " " + recap
	_narrate_panel(spoken)

func _show_learning_phase(phase: int) -> void:
	var skill_name: String = QuestionBank.get_skill_name(_learning_skill)

	match phase:
		0: # Learning Objective
			title_label.text = "LEARNING OBJECTIVE - %s" % skill_name
			_show_learning_content(LessonLibrary.adaptive_text(_learning_skill, "objective"), "Next: Definition")
		1: # Definition
			title_label.text = "DEFINITION - %s" % skill_name
			_show_learning_content(LessonLibrary.adaptive_text(_learning_skill, "definition"), "Next: Example")
		2: # Example
			title_label.text = "EXAMPLE - %s" % skill_name
			_show_learning_content(LessonLibrary.adaptive_text(_learning_skill, "example"), "Next: Application Example")
		3: # Application Example
			title_label.text = "APPLICATION - %s" % skill_name
			_show_learning_content(LessonLibrary.adaptive_text(_learning_skill, "application"), "Next: Guided Demonstration")
		4: # Guided Demonstration
			title_label.text = "GUIDED DEMONSTRATION - %s" % skill_name
			_show_learning_content(LessonLibrary.adaptive_text(_learning_skill, "guided"), "Next: Interactive Challenge")
		5: # Interactive Challenge
			_show_challenge()
		6: # Feedback
			_show_challenge_feedback()
		7: # End
			_show_learning_end()

func _show_learning_content(content: String, next_text: String) -> void:
	_clear_content()
	if sprite:
		sprite.visible = true
	question_label.text = content
	question_label.visible = true
	_clear_options()
	_narrate_panel(content)

	feedback_label.text = ""
	progress_label.text = "Skill: %s" % QuestionBank.get_skill_name(_learning_skill)
	# Panel 0 is the entry panel of the skill: there is nothing earlier to reach.
	back_button.visible = session.get_learning_phase() > 0
	back_button.text = "Back"
	next_button.visible = true
	next_button.text = next_text

## Read one panel line aloud through the narrator service: a recorded clip
## (res://Audio/Voice/<line_id>.ogg) when one exists for the line, otherwise the
## OS text-to-speech voice. Captions always show the full text; this only adds
## the voice, so a missing audio file never leaves a panel silent.
func _narrate_panel(text: String) -> void:
	if _lesson_voice == null:
		return
	_lesson_voice.speak(str(text).strip_edges(), "narration")

func _show_challenge() -> void:
	title_label.text = "INTERACTIVE CHALLENGE - %s" % QuestionBank.get_skill_name(_learning_skill)
	_clear_content()
	# Builder phase: the learner must construct a working DFA on the whiteboard
	# before the free-response challenges.
	var lesson_tasks: Array = LessonLibrary.workshop_tasks(_learning_skill)
	if workshop and not lesson_tasks.is_empty():
		var tasks: Array = lesson_tasks
		if _workshop_task_index < tasks.size():
			_open_builder_task(tasks[_workshop_task_index])
			return
	var challenges := _challenge_list()
	# The queue is rebuilt from performance each round, so a re-ask round can
	# start from the items this learner previously got wrong.
	if _challenge_queue.is_empty():
		_build_challenge_queue()
	if _challenge_queue_pos >= _challenge_queue.size():
		# All challenges done
		_show_challenge_feedback()
		return

	var question_index := _current_challenge_index()
	if question_index < 0 or question_index >= challenges.size():
		_show_challenge_feedback()
		return
	_challenge_index = question_index
	_current_challenge = challenges[question_index]
	_challenge_answered = false

	# Pair the whiteboard with this challenge. A question may carry its OWN
	# reference machine ("read the DFA on the board"); otherwise fall back to a
	# build task (only for skills that have one).
	var has_reference := _pair_reference_board(_current_challenge)
	var paired := false
	if not has_reference:
		paired = _pair_practice_board(_learning_skill, _challenge_index)
	_adaptive_board_paired = paired
	var hint := ""
	if has_reference:
		hint = "\n\nRefer to the DFA shown on the whiteboard to answer."
	elif paired:
		hint = "\n\nUse the whiteboard to build and test the automaton before choosing your answer."
	question_label.text = "Question %d/%d\n\n%s%s" % [_challenge_queue_pos + 1, _challenge_queue.size(), _current_challenge["question"], hint]
	question_label.visible = true
	_clear_options()

	var options: Array = _current_challenge["options"]
	for i in range(options.size()):
		var btn := Button.new()
		btn.text = options[i]
		btn.custom_minimum_size = Vector2(800, 0)
		btn.add_theme_font_size_override("font_size", 18)
		btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
		btn.add_theme_color_override("font_pressed_color", Color(0.8, 0.85, 1, 1))
		btn.add_theme_stylebox_override("normal", _create_option_style(Color(0.12, 0.15, 0.3, 1)))
		btn.add_theme_stylebox_override("hover", _create_option_style(Color(0.2, 0.25, 0.5, 1)))
		btn.add_theme_stylebox_override("pressed", _create_option_style(Color(0.1, 0.12, 0.25, 1)))
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		btn.pressed.connect(_on_challenge_answer.bind(i))
		options_box.add_child(btn)

	feedback_label.text = ""
	progress_label.text = "Skill: %s | Question %d/%d%s" % [QuestionBank.get_skill_name(_learning_skill), _challenge_queue_pos + 1, _challenge_queue.size(), "  ·  whiteboard active — build/check, then answer" if _adaptive_board_paired else ""]
	back_button.visible = true
	back_button.text = "Back"
	next_button.visible = false
	_narrate_panel(str(_current_challenge.get("question", "")))

func _on_challenge_answer(selected_index: int) -> void:
	if _challenge_answered:
		return
	_challenge_answered = true
	_challenge_total += 1
	_adaptive_board_paired = false

	var correct: bool = selected_index == _current_challenge["correct"]
	if correct:
		_challenge_correct += 1
		# Fixed it: drop this item from the re-ask list so the remedy round only
		# covers questions that are STILL wrong, not ones already answered right
		# on a later attempt.
		var fixed: Array = _wrong_challenges.get(_learning_skill, [])
		fixed.erase(_current_challenge_index())
		_wrong_challenges[_learning_skill] = fixed
	else:
		# Remember WHICH item was missed so the re-ask round can target it
		# instead of repeating the whole practice set.
		_note_wrong_challenge(_current_challenge_index())

	# Record adaptive evidence separately from the pretest baseline.
	session.knowledge_tracer.record_learning_observation(_learning_skill, correct)

	# Show feedback
	feedback_label.text = "Correct!" if correct else "Incorrect."
	feedback_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6, 1) if correct else Color(1, 0.5, 0.5, 1))
	feedback_label.text += "\n\n" + _current_challenge["explanation"]
	_narrate_panel("%s %s" % [feedback_label.text.split("\n")[0], _current_challenge["explanation"]])

	# Show next button. The label says whether another question is queued or
	# whether this was the last one, so the learner always knows what pressing
	# it does.
	next_button.visible = true
	next_button.text = "Next Question >>" if _challenge_queue_pos + 1 < _challenge_queue.size() else "See My Result >>"
	back_button.visible = true
	back_button.text = "Back"

func _open_builder_task(task: Dictionary) -> void:
	_workshop_phase = true
	_adaptive_board_paired = false
	_enter_learning_room()
	if workshop:
		_apply_board_task(task)
		workshop.set_active(true)
	_set_player_paused(true)
	question_label.text = "Whiteboard task: build the DFA, then press Check task. Any correct construction is accepted.\n\n%s" % task.get("instruction", "")
	question_label.visible = true
	_clear_options()
	feedback_label.text = ""
	progress_label.text = "Interactive Challenge  ·  %s  ·  press Check task to verify" % QuestionBank.get_skill_name(_learning_skill)
	back_button.visible = true
	back_button.text = "Back"
	next_button.visible = false

func _on_workshop_evaluated(correct: bool, message: String) -> void:
	# VR keeps the whiteboard standing in the room during test screens. There it
	# is a pure sandbox: verify freely, but nothing is graded or recorded.
	if _test_screen_active:
		feedback_label.text = ("Whiteboard check: " if correct else "Whiteboard check failed: ") + message \
			+ "\n\n(Practice only - the board is not graded while a test screen is open.)"
		feedback_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6, 1) if correct else Color(1, 0.5, 0.5, 1))
		return
	# --- DFA lesson whiteboard phase ---
	if _in_dfa_lesson:
		var course_steps := LessonLibrary.course_steps()
		var dfa_skill: String = course_steps[_dfa_lesson_index].get("skill", "building") if _dfa_lesson_index < course_steps.size() else "building"
		var dfa_stats: Dictionary = workshop.builder.call("get_attempt_stats") if workshop.builder is Control else {}
		session.record_workshop_attempt(dfa_skill, correct, dfa_stats)
		# A board build IS evidence: a verified machine counts as a correct
		# observation and a failed check as an incorrect one, so the whiteboard
		# feeds DFA knowledge on SUCCESSFUL AND FAILED attempts alike.
		session.knowledge_tracer.record_learning_observation(dfa_skill, correct)
		if not correct:
			feedback_label.text = message + "\nAdjust the states / transitions and press Check task again until it passes."
			feedback_label.add_theme_color_override("font_color", Color(1, 0.5, 0.5, 1))
			return
		feedback_label.text = "Whiteboard verified! " + message
		feedback_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6, 1))
		if _dfa_practice_board_active:
			# Board is paired with a practice multiple-choice question — verify
			# the build but keep the question on screen; answering it advances.
			return
		if _dfa_board_practice_active:
			var bp_tasks: Array = LessonLibrary.workshop_tasks(_dfa_board_practice_skill)
			_dfa_board_practice_index += 1
			if _dfa_board_practice_index < bp_tasks.size():
				_open_dfa_board_practice(_dfa_board_practice_skill, bp_tasks[_dfa_board_practice_index])
				return
			# All board tasks for this skill are verified -> on to the next step.
			_dfa_board_practice_active = false
			_clear_content()
			workshop.set_active(false)
			_set_player_paused(false)
			_advance_lesson_step()
			_show_dfa_lesson_step()
			return
		_advance_lesson_step()
		_clear_content()
		workshop.set_active(false)
		_set_player_paused(false)
		_show_dfa_lesson_step()
		return
	# --- Adaptive skill builder phase ---
	# Only the challenge phase (5) GRADES board builds. On any other adaptive
	# screen (lecture panels, feedback, and in VR the board stays in view) a
	# Check task is sandbox feedback and must not touch the session.
	if workshop == null or _challenge_answered:
		return
	if session.get_learning_phase() != 5:
		feedback_label.text = ("Whiteboard check: " if correct else "Whiteboard check failed: ") + message \
			+ "\n\n(Sandbox check - press Next to continue, or answer the challenge to record progress.)"
		feedback_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6, 1) if correct else Color(1, 0.5, 0.5, 1))
		return
	# Record EVERY attempt (count, wrong tries, connection edits, time) so the
	# knowledge-tracing algorithms can use richer evidence than right/wrong alone.
	var stats: Dictionary = workshop.builder.call("get_attempt_stats") if workshop.builder is Control else {}
	session.record_workshop_attempt(_learning_skill, correct, stats)
	if _adaptive_board_paired:
		# Board is paired with an adaptive multiple-choice challenge — verifying
		# the build gives feedback but the challenge answer drives progress.
		feedback_label.text = ("Whiteboard verified! " if correct else "Whiteboard: ") + message
		feedback_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6, 1) if correct else Color(1, 0.5, 0.5, 1))
		return
	if not correct:
		# Keep the failed build as evidence too: the whiteboard changes DFA
		# "building" knowledge on failed attempts, not only on successful ones.
		session.knowledge_tracer.record_learning_observation(_learning_skill, false)
		# Pause: stay on the board; only a successful build advances the lesson.
		feedback_label.text = message + "\nTry again — adjust states or transitions on the whiteboard, or press \"Skip task\" to move on."
		feedback_label.add_theme_color_override("font_color", Color(1, 0.5, 0.5, 1))
		return
	# Correct build → next workshop task or on to the multiple-choice challenges.
	_workshop_task_index += 1
	session.knowledge_tracer.record_learning_observation(_learning_skill, true)
	feedback_label.text = "Correct! " + message
	feedback_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6, 1))
	var tasks: Array = LessonLibrary.workshop_tasks(_learning_skill)
	if _workshop_task_index < tasks.size():
		_open_builder_task(tasks[_workshop_task_index])
		return
	_workshop_phase = false
	_challenge_answered = false
	_challenge_index = 0
	# The builder phase runs before any question, so the ask-order is rebuilt
	# from this learner's performance on the next _show_challenge().
	_challenge_queue.clear()
	_challenge_queue_pos = 0
	_clear_content()
	workshop.set_active(false)
	_set_player_paused(false)
	_show_challenge()

## The learner pressed "Skip task" on the whiteboard.
##
## A skip costs KNOWLEDGE, not just time: the ACTIVE model is penalised by the
## part of the skill that is still unknown, so a skip at low mastery is a heavy
## drop while a skip at high mastery barely moves the needle. The flow then
## continues exactly as if the task had been verified, so a learner can never be
## trapped on a build they cannot finish.
##
## The branches below MIRROR the success path of _on_workshop_evaluated(): the
## only differences are (a) the skip penalty instead of an observation and
## (b) the board stays open for a paired multiple-choice challenge.
func _on_workshop_skipped(_message: String) -> void:
	if workshop == null:
		return
	if _test_screen_active:
		# Sandbox board during a test screen: a skip costs nothing and does nothing.
		return
	var stats: Dictionary = workshop.builder.call("get_attempt_stats") if workshop.builder is Control else {}
	# --- DFA lesson whiteboard phase ---
	if _in_dfa_lesson:
		var course_steps := LessonLibrary.course_steps()
		var dfa_skill: String = course_steps[_dfa_lesson_index].get("skill", "building") if _dfa_lesson_index < course_steps.size() else "building"
		_show_skip_feedback(dfa_skill, session.record_workshop_skip(dfa_skill, stats))
		if _dfa_practice_board_active:
			# Board paired with a practice question: the answer still advances.
			return
		if _dfa_board_practice_active:
			var bp_tasks: Array = LessonLibrary.workshop_tasks(_dfa_board_practice_skill)
			_dfa_board_practice_index += 1
			if _dfa_board_practice_index < bp_tasks.size():
				_open_dfa_board_practice(_dfa_board_practice_skill, bp_tasks[_dfa_board_practice_index])
				return
			_dfa_board_practice_active = false
			_clear_content()
			workshop.set_active(false)
			_set_player_paused(false)
			_advance_lesson_step()
			_show_dfa_lesson_step()
			return
		_advance_lesson_step()
		_clear_content()
		workshop.set_active(false)
		_set_player_paused(false)
		_show_dfa_lesson_step()
		return
	# --- Adaptive skill builder phase ---
	if _challenge_answered:
		return
	# A skip only means something during the challenge phase; anywhere else the
	# board is a sandbox and skipping costs nothing.
	if session.get_learning_phase() != 5:
		return
	_show_skip_feedback(_learning_skill, session.record_workshop_skip(_learning_skill, stats))
	if _adaptive_board_paired:
		# Board paired with an adaptive challenge: that answer drives progress.
		return
	_workshop_task_index += 1
	var tasks: Array = LessonLibrary.workshop_tasks(_learning_skill)
	if _workshop_task_index < tasks.size():
		_open_builder_task(tasks[_workshop_task_index])
		return
	_workshop_phase = false
	_challenge_answered = false
	_challenge_index = 0
	_challenge_queue.clear()
	_challenge_queue_pos = 0
	_clear_content()
	workshop.set_active(false)
	_set_player_paused(false)
	_show_challenge()

## Report a skip in plain numbers so the learner sees what giving up cost.
func _show_skip_feedback(skill: String, penalty: Dictionary) -> void:
	if penalty.is_empty():
		return
	var before := float(penalty.get("before", 0.0)) * 100.0
	var after := float(penalty.get("after", 0.0)) * 100.0
	feedback_label.text = "Skipped.\n%s knowledge: %.0f%% -> %.0f%%  (a skip costs more the less you already knew)" % [
		QuestionBank.get_skill_name(skill), before, after]
	feedback_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.42, 1))


func _show_challenge_feedback() -> void:
	title_label.text = "CHALLENGE FEEDBACK - %s" % QuestionBank.get_skill_name(_learning_skill)
	_clear_content()

	var percentage: float = 0.0
	if _challenge_total > 0:
		percentage = float(_challenge_correct) / float(_challenge_total) * 100.0

	var knowledge: float = session.knowledge_tracer.get_mastery_percentage(_learning_skill)
	var learned: bool = session.knowledge_tracer.is_learned(_learning_skill)

	question_label.text = "You answered %d/%d challenges correctly (%.1f%%).\n\nCurrent knowledge level: %.1f%%\n\n%s" % [
		_challenge_correct,
		_challenge_total,
		percentage,
		knowledge,
		"Great job! You have mastered this skill!" if learned else "You need more practice. Let's review the material again."
	]
	question_label.visible = true
	_clear_options()

	feedback_label.text = ""
	progress_label.text = "Skill: %s" % QuestionBank.get_skill_name(_learning_skill)
	back_button.visible = true
	back_button.text = "Back"
	next_button.visible = true
	next_button.text = "Continue"

func _show_learning_end() -> void:
	title_label.text = "SKILL COMPLETE - %s" % QuestionBank.get_skill_name(_learning_skill)
	_clear_content()

	var knowledge: float = session.knowledge_tracer.get_mastery_percentage(_learning_skill)
	var learned: bool = _skill_is_learned()

	question_label.text = "You have completed the learning activity for %s.\n\nCurrent knowledge level: %.1f%%\n\n%s" % [
		QuestionBank.get_skill_name(_learning_skill),
		knowledge,
		"Excellent! You have mastered this skill." if learned else "You have improved, but the model does not consider this topic learned yet."
	]
	if not learned:
		question_label.text += "\nIt will be queued again in the extra review pass below."
	question_label.visible = true
	_clear_options()

	# Check if there are more skills to cover. Adaptive learning walks through
	# ALL topics (weakest-first) so nothing is skipped; the "next" step is simply
	# the next skill in the pretest-derived priority order.
	_analysis_skill_index += 1
	if _analysis_skill_index < _analysis_skills.size():
		var next_skill: String = _analysis_skills[_analysis_skill_index]
		var next_knowledge: float = session.knowledge_tracer.get_mastery_percentage(next_skill)
		question_label.text += "\n\nNext topic to cover: %s (current knowledge %.1f%%)" % [QuestionBank.get_skill_name(next_skill), next_knowledge]
		next_button.text = "Next Topic"
	elif _ready_for_posttest():
		# Mastery gate ALREADY passed: go straight to the post test. Checking
		# this BEFORE the review pass is what stops a fully-mastered run from
		# being dragged through a redundant second pass of every topic.
		var gate_note := "%s considers you knowledgeable enough: %d of 6 topics learned." % [
			session.get_algorithm_label(), _mastered_skill_count()]
		question_label.text += "\n\nAll six topics have been covered.\n" + gate_note
		next_button.text = "Proceed to Post Test"
	elif not _adaptive_review_pass:
		_adaptive_review_pass = true
		# Revisit ONLY the topics the tracer still calls unlearned (weakest
		# first) - re-running skills that already hit mastery is the
		# repetition this gate exists to prevent.
		_analysis_skills = _weak_skills()
		_analysis_skill_index = 0
		if _analysis_skills.is_empty():
			_analysis_skills = session.get_skills_by_weakness()
		question_label.text += "\n\nThe ordered DFA lesson is complete. Adaptive review will revisit the topics that still need work, weakest first: %s." % ", ".join(_skill_names(_analysis_skills))
		next_button.text = "Start Adaptive Review"
	elif _weak_sweeps < MAX_WEAK_SKILL_SWEEPS:
		# The post test stays LOCKED until the algorithm considers the learner
		# knowledgeable enough. Below the gate, go back to the skills that are
		# still unlearned (weakest first) for another full pass - including their
		# accumulated re-ask history, so the missed items come back around.
		_weak_sweeps += 1
		var weak := _weak_skills()
		_analysis_skills = weak
		_analysis_skill_index = 0
		question_label.text += "\n\n%s still needs work on %d of 6 topics (mastered %d, need %d). Extra review pass %d of %d: weakest first." % [
			session.get_algorithm_label(), weak.size(), _mastered_skill_count(), MASTERY_GATE_SKILLS,
			_weak_sweeps, MAX_WEAK_SKILL_SWEEPS]
		question_label.text += "\nWeaker topics: %s" % ", ".join(_skill_names(weak))
		next_button.text = "Review My Weak Topics >>"
	else:
		# The sweeps are spent without reaching the gate: go to the post test
		# anyway and report honestly what the model thinks.
		var gate_note := "%s considers you knowledgeable enough: %d of 6 topics learned." % [
			session.get_algorithm_label(), _mastered_skill_count()]
		if not _ready_for_posttest():
			gate_note = "Review passes are complete. Going to the post test even though only %d of 6 topics are at the mastery threshold." % _mastered_skill_count()
		question_label.text += "\n\nAll six topics and the adaptive review have now been covered.\n" + gate_note
		next_button.text = "Proceed to Post Test"

	feedback_label.text = ""
	progress_label.text = "Adaptive Learning Progress  ·  %d / %d topics learned" % [_mastered_skill_count(), MASTERY_GATE_SKILLS]
	# No Back here on purpose: rendering this screen already commits the "next
	# topic" bookkeeping, so a re-read must not re-run it. Next drives forward.
	back_button.visible = false
	next_button.visible = true

## Display names for a list of skill ids (used by the weak-topic report).
func _skill_names(skills: Array) -> Array[String]:
	var out: Array[String] = []
	for skill in skills:
		out.append(QuestionBank.get_skill_name(str(skill)))
	return out

func _on_learning_next() -> void:
	var phase: int = session.get_learning_phase()

	match phase:
		0, 1, 2, 3, 4:
			if phase == 4 and _resume_reask:
				# Back was pressed on the remedy screen: this Next re-enters the
				# targeted re-ask directly (the same work the phase-8 branch
				# below does), so no decision runs twice.
				_resume_reask = false
				_build_challenge_queue(true)
				_challenge_correct = 0
				_challenge_total = 0
				session.learning_phase = 5
				_show_challenge()
				return
			session.advance_learning_phase()
			_show_learning_phase(phase + 1)
		5: # Challenge phase - next question in this round's order, then feedback
			_challenge_queue_pos += 1
			if _challenge_queue_pos < _challenge_queue.size():
				_show_challenge()
			else:
				session.advance_learning_phase()
				_show_learning_phase(6)
		6: # Round over - the algorithm decides: learned, or re-explain + re-ask
			if _skill_is_learned():
				session.advance_learning_phase()
				_show_learning_phase(7)
			elif int(_remedy_rounds.get(_learning_skill, 0)) < MAX_REMEDY_ROUNDS:
				# Not learned yet: re-explain the missed areas, then re-ask only those
				# questions. This is the adaptive loop the learner keeps getting
				# better at until the tracer says LEARNED.
				session.learning_phase = 8
				_show_remedy_round()
			else:
				# Rounds spent: report honestly and move on. The end-of-session
				# mastery gate still pulls this skill back into the weak-topic pass.
				session.advance_learning_phase()
				_show_learning_phase(7)
		7: # End - the Next button text routes to the next skill / post test
			pass
		8: # Remediation -> re-ask ONLY the questions that were answered wrong
			_build_challenge_queue(true)
			_challenge_correct = 0
			_challenge_total = 0
			session.learning_phase = 5
			_show_challenge()
		_:
			session.advance_learning_phase()
			_show_learning_phase(mini(session.get_learning_phase() + 1, 7))

# ===== POST TEST =====

func _start_posttest() -> void:
	SessionBridge.test_mode = "posttest"
	get_tree().change_scene_to_file("res://Testing/TestRoom.tscn")

func _show_posttest_question() -> void:
	title_label.text = "POST TEST"
	_clear_content()

	var question: Dictionary = session.get_current_question()
	question_label.text = "Question %d/%d\n\n%s" % [session.get_current_question_number(), session.get_total_questions(), question["question"]]
	question_label.visible = true

	_clear_options()
	var options: Array = question["options"]
	for i in range(options.size()):
		var btn := Button.new()
		btn.text = options[i]
		btn.custom_minimum_size = Vector2(800, 0)
		btn.add_theme_font_size_override("font_size", 18)
		btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
		btn.add_theme_color_override("font_pressed_color", Color(0.8, 0.85, 1, 1))
		btn.add_theme_stylebox_override("normal", _create_option_style(Color(0.12, 0.15, 0.3, 1)))
		btn.add_theme_stylebox_override("hover", _create_option_style(Color(0.2, 0.25, 0.5, 1)))
		btn.add_theme_stylebox_override("pressed", _create_option_style(Color(0.1, 0.12, 0.25, 1)))
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		btn.pressed.connect(_on_posttest_answer.bind(i))
		options_box.add_child(btn)

	feedback_label.text = ""
	progress_label.text = "Post Test: Question %d of %d" % [session.get_current_question_number(), session.get_total_questions()]
	back_button.visible = false
	next_button.visible = false

func _on_posttest_answer(selected_index: int) -> void:
	var result: Dictionary = session.submit_answer(selected_index)

	if result["complete"]:
		_show_results()
	else:
		_show_posttest_question()

# ===== RESULTS =====

func _show_results() -> void:
	_enter_test_panel()
	title_label.text = "RESULTS"
	_clear_content()

	_results = session.get_posttest_results()
	session.save_session_data()
	var report_path := session.generate_profile_pdf()
	# Append this run to the student's own comparative-study file
	# (user://results/<name>.json) and show the six study metrics.
	var study_metrics: Dictionary = session.get_study_metrics()
	var student_results_path: String = session.save_student_results()
	# Shared per-machine algorithm summary (all students, all runs).
	var algorithm_summary_path: String = session.save_algorithm_summary()

	var pretest: Dictionary = _results["pretest"]
	var posttest: Dictionary = _results["posttest"]

	var text := "Pretest Results:\n"
	text += "Score: %d/%d (%.1f%%)\n\n" % [pretest["correct"], pretest["total"], pretest["percentage"]]

	text += "Post Test Results:\n"
	text += "Score: %d/%d (%.1f%%)\n\n" % [posttest["correct"], posttest["total"], posttest["percentage"]]

	# --- Comparative-study metrics (the six numbers of the study) ---
	text += "COMPARATIVE STUDY METRICS\n"
	text += "  Average Pretest Score: %.1f%%\n" % study_metrics["average_pretest_score"]
	text += "  Average Posttest Score: %.1f%%\n" % study_metrics["average_posttest_score"]
	text += "  Performance Improvement Rate: %+.1f%%\n" % study_metrics["performance_improvement_rate"]
	text += "  Predictive Accuracy (%s): %.1f%%\n" % [study_metrics["predictive_accuracy_algorithm"], study_metrics["predictive_accuracy"]]
	var adaptive_secs: float = study_metrics["adaptive_learning_seconds"]
	text += "  Adaptive Learning Completion Time: %02d:%02d (%.1f min)\n" % [int(adaptive_secs) / 60, int(adaptive_secs) % 60, adaptive_secs / 60.0]
	var ksa: Dictionary = study_metrics["knowledge_state_detail"]
	text += "  Knowledge State Accuracy: %.1f%% (%d/%d skills verified)\n" % [study_metrics["knowledge_state_accuracy"], int(ksa["matches"]), int(ksa["compared"])]
	text += "  Student data saved to: %s\n\n" % student_results_path

	var improvement: float = posttest["percentage"] - pretest["percentage"]
	text += "Improvement: %+.1f%%\n\n" % improvement
	text += "Profile report saved to: %s\n\n" % report_path

	text += "Knowledge Summary:\n"
	var summary: Dictionary = _results["knowledge_summary"]
	for skill in summary:
		var data: Dictionary = summary[skill]
		text += "%s: %.1f%%\n" % [data["name"], data["mastery_percentage"]]

	# --- Algorithm comparison → pick the best model for the POC ---
	if session and session.knowledge_tracer:
		text += "\nALGORITHM COMPARISON  (prediction hit-rate)\n"
		var cmp: Dictionary = session.knowledge_tracer.get_algorithm_comparison()
		var best_key := "HMM"
		var best_acc := -1.0
		for key in ["HMM", "BKT", "KST"]:
			var s: Dictionary = cmp[key]
			text += "  %s: %d/%d hits (%.1f%%)\n" % [key, s["hits"], s["total"], s["accuracy"]]
			if s["accuracy"] > best_acc:
				best_acc = s["accuracy"]
				best_key = key
		text += "\n★ Recommended for the POC: %s (highest prediction accuracy)\n" % best_key
		text += "Algorithm summary saved to: %s\n" % algorithm_summary_path

	# --- Whiteboard build analytics ---
	var wdata3: Dictionary = session.get_workshop_attempts()
	if not wdata3.is_empty():
		text += "\nWHITEBOARD BUILDS\n"
		for skill3 in wdata3:
			var records3: Array = wdata3[skill3]
			if records3.is_empty():
				continue
			var ok_count := 0
			var wrong_tries := 0
			var conns := 0
			var time_s := 0.0
			var skipped := 0
			for r in records3:
				wrong_tries += r.get("wrong_attempts", 0)
				conns += r.get("connections_made", 0)
				time_s += float(r.get("time_seconds", 0.0))
				if r.get("skipped", false):
					skipped += 1
				elif r.get("correct", false):
					ok_count += 1
			text += "  %s: %d builds passed, %d skipped, %d wrong checks, %d connection edits, %.0fs on task\n" % [QuestionBank.get_skill_name(skill3), ok_count, skipped, wrong_tries, conns, time_s]

	question_label.text = text
	question_label.visible = true
	_clear_options()

	feedback_label.text = ""
	progress_label.text = "Session Complete"
	back_button.visible = true
	back_button.text = "Back to Lab"
	next_button.visible = false

# ===== BUTTON HANDLERS =====

func _on_back_pressed() -> void:
	if back_button.text == "Back to Lab":
		get_tree().change_scene_to_file("res://World/World.tscn")
		return

	# In-session back-routing comes FIRST: while a lesson or the adaptive review
	# is running, Back must walk the learner up the lesson - never kick them out
	# to the algorithm menu mid-session.
	if _in_dfa_lesson:
		_back_in_dfa_lesson()
		return
	if session != null and session.state == SessionManager.SessionState.ADAPTIVE_LEARNING:
		_back_in_adaptive_learning()
		return

	# Menu back-routing follows the briefing-first flow: confirm -> select ->
	# briefing -> (Back to Lab) World.
	if _menu_stage == "explain":
		_show_algorithm_select()
		return
	_show_algorithm_briefing()

## Back inside the guided DFA lesson: retrace the lesson without restarting it.
## Most local retreat first, so the learner never loses more progress than one
## press:
##   * mid-practice question  -> the previous question of the same skill
##   * demo build screen      -> the same step's explanation panel (if any)
##   * anything else          -> one lesson step back (engine cursor; silent)
func _back_in_dfa_lesson() -> void:
	if _lesson_engine == null:
		return
	var step: Dictionary = _lesson_engine.current()
	var kind := str(step.get("m", ""))

	# (a) Inside a practice round: step back question by question. The question
	# is shown unanswered again so it can be re-read (and re-answered).
	if kind == "practice" and not _dfa_board_practice_active and _dfa_practice_index > 0:
		_dfa_practice_index -= 1
		_dfa_practice_answered = false
		_show_dfa_practice(step)
		return

	# (b) On a demo step's build screen: re-read its explanation first.
	if kind == "demo" and _dfa_pending_skill.is_empty() and str(step.get("explain", "")) != "":
		_dfa_pending_skill = step
		_show_dfa_explanation(step)
		return

	# (c) General retreat: one step back through the lesson cursor. Any pending
	# "explain then build" state is dropped so Next follows the new position.
	_dfa_pending_skill = {}
	_dfa_pending_explain = {}
	_dfa_board_practice_active = false
	_dfa_practice_board_active = false
	_dfa_practice_answered = false
	_close_paired_board()
	if _lesson_engine.back():
		_dfa_lesson_index = _lesson_engine.position
		_show_dfa_lesson_step()

## Back inside the adaptive learning phase: retrace the lecture of the current
## skill WITHOUT losing the quiz state. The challenge cursor (`_challenge_queue`
## and its position) is deliberately untouched, so pressing Next after the
## detour resumes at the exact same question. Nothing is re-graded or
## re-announced on the way back.
func _back_in_adaptive_learning() -> void:
	if _learning_skill == "":
		return
	var phase := session.get_learning_phase()

	# Lecture panels (0..4): step back one panel at a time.
	if phase >= 1 and phase <= 4:
		session.learning_phase = phase - 1
		_show_learning_phase(phase - 1)
		return

	# Quiz (5), feedback (6) or remedy (8): retreat to the summary panel. The
	# round is re-entered from there with the cursor where it stood.
	if phase == 5 or phase == 6 or phase == 8:
		if phase == 8:
			# The targeted re-ask has not been built yet: rebuild it on the way
			# back in, instead of running the phase-6 decision a second time.
			_resume_reask = true
		_adaptive_board_paired = false
		_workshop_phase = false
		session.learning_phase = 4
		_show_learning_phase(4)
		return

	# Phase 0 (entry panel) and 7 (skill end) have nothing earlier to show.

func _on_next_pressed() -> void:
	if _in_dfa_lesson:
		_handle_dfa_lesson_next()
		return
	match session.state:
		SessionManager.SessionState.ANALYSIS:
			if next_button.text == "Start DFA Lesson":
				_begin_dfa_lesson()
			else:
				_start_adaptive_learning()
		SessionManager.SessionState.ADAPTIVE_LEARNING:
			if next_button.text == "Proceed to Post Test":
				_start_posttest()
			elif next_button.text == "Learn Next Skill" or next_button.text == "Next Topic" \
					or next_button.text == "Start Adaptive Review" or next_button.text == "Review My Weak Topics >>":
				# Begin the next skill in the (weakness-ordered) plan. The
				# remediation bookkeeping is deliberately NOT reset, so a skill
				# revisited in a later weak-topic pass still remembers which
				# questions this learner got wrong.
				_begin_learning_skill(_analysis_skills[_analysis_skill_index])
			else:
				_on_learning_next()
		SessionManager.SessionState.COMPLETE:
			_show_results()

# ===== UI HELPERS =====

func _clear_content() -> void:
	if workshop:
		workshop.set_active(false)
	_set_player_paused(false)
	question_label.text = ""
	question_label.visible = false
	_clear_options()
	feedback_label.text = ""
	progress_label.text = ""

func _clear_options() -> void:
	for child in options_box.get_children():
		options_box.remove_child(child)
		child.queue_free()

func _enter_learning_room() -> void:
	# Learning happens in the walkable room. Only testing screens use the desktop overlay.
	_test_screen_active = false
	if workshop:
		workshop.set_persistent_overlay(true)
		if workshop.builder is Control:
			# Board tasks are part of learning again: the Skip option is back.
			workshop.builder.call("set_skip_enabled", true)
	if overlay_layer:
		overlay_layer.visible = false
	if sprite:
		sprite.visible = true
	var player := get_node_or_null("../CharacterBody3D")
	if player:
		player.set_physics_process(true)
		player.set_process(true)

## Test screens (algorithm select / briefing / pretest / post-test / results).
##
## DESKTOP: the panel is drawn as a fullscreen CanvasLayer overlay and the
## player body is frozen, because the overlay IS the interface.
##
## VR: there is no flat overlay to look at - a CanvasLayer does not exist in
## the headset. The SAME panel content is shown on the in-room billboard
## Sprite3D instead, the player stays free to walk up to it, and the algorithm
## select / briefing / pretest are all reachable as a floating room panel. This
## is the fix for "in VR the testing grounds shows no algorithm select and
## never reaches the pretest": the old code hid the sprite and showed a
## CanvasLayer that the headset can never see.
func _enter_test_panel() -> void:
	var vr := InputMode.is_vr()
	_test_screen_active = true
	if workshop:
		# In VR the whiteboard stays standing in the room even during tests.
		workshop.set_persistent_overlay(vr)
		if not vr:
			workshop.set_active(false)
		if workshop.builder is Control:
			# A sandbox must not offer "Skip task": there is no task to skip.
			workshop.builder.call("set_skip_enabled", false)
	if overlay_layer:
		overlay_layer.visible = not vr
	if sprite:
		sprite.visible = true
	var player := get_node_or_null("../CharacterBody3D")
	if player and not vr:
		player.set_physics_process(false)
		player.set_process(false)

## Learning happens in a WALKABLE room: the lesson billboard and the automata
## whiteboard are both 3D boards standing in the room, so the player must stay
## able to move, look around and walk up to whichever board they are using.
##
## BUG THIS REPLACES: board-only steps used to call `_set_player_paused(true)`
## and hide both Next and Back. That stranded the learner on a frozen avatar
## with no way forward - most visibly on the "THE TRAP (DEAD) STATE" panel of
## the DFA-building topic, whose practice step is a whiteboard build: the room
## literally parked the player in a dead state. The learning room now always
## keeps the player unfrozen; the argument is kept so the call sites still read
## correctly and so `_enter_test_panel` can keep its own full freeze.
func _set_player_paused(_paused: bool) -> void:
	_unfreeze_player()

## Restore movement + look input on the player body (desktop WASD and VR alike).
func _unfreeze_player() -> void:
	var player := get_node_or_null("../CharacterBody3D")
	if player:
		player.set_physics_process(true)
		player.set_process(true)

func _create_button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(12)
	style.content_margin_left = 20.0
	style.content_margin_top = 12.0
	style.content_margin_right = 20.0
	style.content_margin_bottom = 12.0
	return style

func _create_option_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(10)
	style.content_margin_left = 16.0
	style.content_margin_top = 10.0
	style.content_margin_right = 16.0
	style.content_margin_bottom = 10.0
	return style

func _create_input_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.2, 1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 12.0
	style.content_margin_top = 8.0
	style.content_margin_right = 12.0
	style.content_margin_bottom = 8.0
	return style

# ===== UI POINTER =====

func _update_pointer() -> void:
	if InputMode.is_desktop():
		if overlay_layer and overlay_layer.visible:
			_update_overlay_pointer()
		else:
			_update_desktop_pointer()
	else:
		_update_vr_pointer()

# ===== DESKTOP POINTER =====

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

# ===== IN-ROOM DESKTOP POINTER (mouse ray-cast onto the billboard) =====

func _update_desktop_pointer() -> void:
	# Convert the desktop cursor into a camera ray and intersect the visible
	# billboard, keeping interaction consistent with the VR controller ray.
	var mouse_screen := get_viewport().get_mouse_position()
	var uv := Vector2(-1, -1)
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null and sprite != null and sprite.texture != null:
		var result := _ray_intersect_sprite(camera.project_ray_origin(mouse_screen), camera.project_ray_normal(mouse_screen))
		if not result.is_empty():
			uv = Vector2(result["uv"].x * viewport.size.x, result["uv"].y * viewport.size.y)

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

func _forward_keyboard(event: InputEvent) -> void:
	# Route physical-keyboard typing into the SubViewport, but ONLY while a text
	# field inside the UI has focus. This lets the user type their name normally
	# while WASD/arrows are untouched everywhere else.
	if not (event is InputEventKey):
		return
	var focus_owner: Control = viewport.gui_get_focus_owner()
	if focus_owner == null:
		return
	if not (focus_owner is LineEdit or focus_owner is TextEdit):
		return
	viewport.push_input(event)

func _sync_stats_board() -> void:
	if session == null:
		return
	var phase := "Main Menu"
	match session.state:
		SessionManager.SessionState.PROFILE_SETUP:
			phase = "Profile Setup"
		SessionManager.SessionState.PRETEST:
			phase = "Pretest"
		SessionManager.SessionState.ANALYSIS:
			phase = "Knowledge Analysis"
		SessionManager.SessionState.ADAPTIVE_LEARNING:
			phase = "Adaptive Learning"
		SessionManager.SessionState.POST_TEST:
			phase = "Post Test"
		SessionManager.SessionState.COMPLETE:
			phase = "Complete"
	_update_stats_board(phase, 0, 0, 0.0)

func _update_stats_board(phase: String, _answered: int, _correct: int, _acc: float) -> void:
	if stats_board == null or session == null:
		return
	# ONE ACTIVE ALGORITHM only: the board shows that model's probabilities /
	# knowledge per skill (HMM hidden beliefs, BKT 4 params, KST space), plus a
	# one-line-each description of every parameter on show, because the letters
	# (K / L / L0 / T / G / S / E / n) mean nothing on their own.
	var tracer = session.knowledge_tracer
	if tracer == null:
		return
	var data := {
		"algorithm": tracer.get_algorithm_callout(),
		"phase": phase,
		"lines": tracer.get_active_stats_lines(),
		"params": tracer.get_param_lines(),
		"skips": tracer.get_skip_stats(),
	}
	if stats_board.has_method("set_active_stats"):
		stats_board.call("set_active_stats", data)
	else:
		stats_board.call("set_stats_text", "\n".join(data["lines"]))

# ===== VR POINTER =====

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

		laser.visible = true
		var distance: float = ray_origin.distance_to(result["hit"])
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
	var plane_point: Vector3 = sprite_pos

	var denom := plane_normal.dot(ray_dir)
	if absf(denom) < 0.0001:
		return {}

	var t := (plane_point - ray_origin).dot(plane_normal) / denom
	if t < 0.0:
		return {}

	var hit := ray_origin + ray_dir * t
	var to_hit := hit - sprite_pos

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
