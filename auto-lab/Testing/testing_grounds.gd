extends Node3D
## Main controller for the Testing Grounds VR scene.
## Handles the full flow: Profile Setup → Algorithm Selection → Pretest → Analysis → Adaptive Learning → Post Test → Results.

const SessionManager = preload("res://Testing/session_manager.gd")
const QuestionBank = preload("res://Testing/Data/question_bank.gd")
const AdaptiveContent = preload("res://Testing/Data/adaptive_content.gd")

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
@onready var workshop: Node3D = $AutomataWorkshopWhiteboard

# Full-screen overlay references (desktop mode only)
@onready var overlay_layer: CanvasLayer = $OverlayLayer
@onready var overlay_rect: TextureRect = $OverlayLayer/OverlayRect

# Statistics side-panel references
@onready var stats_panel: PanelContainer = $SubViewport/Root/StatsPanel
@onready var stats_title: Label = $SubViewport/Root/StatsPanel/StatsVBox/StatsTitle
@onready var stats_algo: Label = $SubViewport/Root/StatsPanel/StatsVBox/StatsAlgo
@onready var stats_phase: Label = $SubViewport/Root/StatsPanel/StatsVBox/StatsPhase
@onready var stats_progress: Label = $SubViewport/Root/StatsPanel/StatsVBox/StatsProgress
@onready var stats_score: Label = $SubViewport/Root/StatsPanel/StatsVBox/StatsScore
@onready var stats_skills: Label = $SubViewport/Root/StatsPanel/StatsVBox/StatsSkills
@onready var stats_mode: Label = $SubViewport/Root/StatsPanel/StatsVBox/StatsMode

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
var _handholding: bool = false

# Analysis state
var _analysis_skill_index: int = 0
var _analysis_skills: Array = []
var _adaptive_review_pass: bool = false

# Results state
var _results: Dictionary = {}

func _ready() -> void:
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
		workshop.visible = false

	# Initialize session
	session = SessionManager.new()
	_enter_test_panel()

	# Show the main menu
	_show_main_menu()

func _process(_delta: float) -> void:
	if workshop and workshop.visible:
		_update_stats_panel()
		return
	_update_pointer()
	_update_stats_panel()

func _input(event: InputEvent) -> void:
	# Track the real left mouse button so Desktop mode can click the panel.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_desktop_mouse_down = event.pressed
	# In desktop mode forward keyboard input to the SubViewport so text fields
	# (e.g. the name LineEdit) can be typed normally on a physical keyboard.
	if InputMode.is_desktop():
		_forward_keyboard(event)

# ===== UI NAVIGATION =====

func _show_main_menu() -> void:
	title_label.text = "TESTING GROUNDS"
	_clear_content()

	question_label.text = "Welcome to the DFA Testing Grounds!\n\nThis system will guide you through:\n1. Pretest (30 questions)\n2. Knowledge Analysis\n3. Adaptive Learning\n4. Post Test\n\nSelect an algorithm to begin:"
	question_label.visible = true

	# Create algorithm selection buttons
	_create_algorithm_buttons()
	feedback_label.text = ""
	progress_label.text = ""
	back_button.visible = true
	back_button.text = "Back to Lab"
	next_button.visible = false

func _create_algorithm_buttons() -> void:
	_clear_options()

	var algorithms := [
		{"name": "HMM (Hidden Markov Model)", "type": 0, "desc": "Tracks knowledge per skill using hidden states"},
		{"name": "BKT (Bayesian Knowledge Tracing)", "type": 1, "desc": "Classic BKT with 4 parameters per skill"},
		{"name": "DKT (Deep Knowledge Tracing)", "type": 2, "desc": "Neural network-based knowledge tracing"}
	]

	for algo in algorithms:
		var btn := Button.new()
		btn.text = algo["name"] + "\n" + algo["desc"]
		btn.custom_minimum_size = Vector2(800, 60)
		btn.add_theme_font_size_override("font_size", 18)
		btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
		btn.add_theme_color_override("font_pressed_color", Color(0.8, 0.85, 1, 1))
		btn.add_theme_stylebox_override("normal", _create_button_style(Color(0.16, 0.28, 0.62, 1)))
		btn.add_theme_stylebox_override("hover", _create_button_style(Color(0.3, 0.48, 0.95, 1)))
		btn.add_theme_stylebox_override("pressed", _create_button_style(Color(0.1, 0.19, 0.45, 1)))
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		btn.pressed.connect(_on_algorithm_selected.bind(algo["type"]))
		options_box.add_child(btn)

func _on_algorithm_selected(algo_type: int) -> void:
	session.set_algorithm_type(algo_type)
	# Collect current credentials for every run so the exported session data is complete.
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

	question_label.text = "You will now take a 30-question pretest on DFA (Deterministic Finite Automata).\n\nThe questions cover 7 skill areas:\n• Simulation\n• Identification of Diagrams\n• DFA Definition and Parts\n• DFA Building\n• DFA from Regex\n• DFA from Set Builder\n• DFA from List\n\nAnswer each question to the best of your ability. Your results will determine your adaptive learning path."
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
	session.start_pretest()
	session.save_session_data()
	_show_question()

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
	# get_skills_by_weakness() returns ALL 7 skills sorted weakest-first. We keep
	# that order so adaptive learning COVERS every topic but starts by prioritising
	# the topics the user was weakest on in the pretest.
	_analysis_skills = ["simulation", "identification", "definition", "building", "regex", "set_builder", "list"]
	_analysis_skill_index = 0
	_adaptive_review_pass = false

	question_label.text = "Based on your pretest results (used to drive knowledge-tracing), here is your analysis:\n\n"
	question_label.visible = true
	_clear_options()

	# Build skill summary text
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

	question_label.text += summary_text + "\n\nAdaptive learning will now COVER ALL %d topics, starting with your weakest skill (%s) and using your pretest performance as the knowledge model's basis.\n\nClick Next to begin." % [_analysis_skills.size(), QuestionBank.get_skill_name(_analysis_skills[0])]

	back_button.visible = true
	back_button.text = "Back"
	next_button.visible = true
	next_button.text = "Start Learning"

# ===== ADAPTIVE LEARNING =====

func _start_adaptive_learning() -> void:
	_enter_learning_room()
	_analysis_skill_index = 0
	_learning_skill = _analysis_skills[_analysis_skill_index]
	_challenge_index = 0
	_challenge_correct = 0
	_challenge_total = 0
	_challenge_answered = false
	_handholding = false
	session.start_adaptive_learning(_learning_skill)
	_show_learning_phase(0)

func _show_learning_phase(phase: int) -> void:
	var skill_name: String = QuestionBank.get_skill_name(_learning_skill)

	match phase:
		0: # Learning Objective
			title_label.text = "LEARNING OBJECTIVE - %s" % skill_name
			_show_learning_content(AdaptiveContent.get_objective(_learning_skill), "Next: Definition")
		1: # Definition
			title_label.text = "DEFINITION - %s" % skill_name
			_show_learning_content(AdaptiveContent.get_definition(_learning_skill), "Next: Example")
		2: # Example
			title_label.text = "EXAMPLE - %s" % skill_name
			_show_learning_content(AdaptiveContent.get_example(_learning_skill), "Next: Application Example")
		3: # Application Example
			title_label.text = "APPLICATION - %s" % skill_name
			_show_learning_content(AdaptiveContent.get_application(_learning_skill), "Next: Guided Demonstration")
		4: # Guided Demonstration
			title_label.text = "GUIDED DEMONSTRATION - %s" % skill_name
			_show_learning_content(AdaptiveContent.get_guided(_learning_skill), "Next: Interactive Challenge")
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

	feedback_label.text = ""
	progress_label.text = "Skill: %s" % QuestionBank.get_skill_name(_learning_skill)
	back_button.visible = true
	back_button.text = "Back"
	next_button.visible = true
	next_button.text = next_text

func _show_challenge() -> void:
	title_label.text = "INTERACTIVE CHALLENGE - %s" % QuestionBank.get_skill_name(_learning_skill)
	_clear_content()
	if workshop and _learning_skill in ["building", "regex", "set_builder"]:
		_enter_learning_room()
		workshop.visible = true
		if sprite:
			sprite.visible = false
		_set_player_paused(true)
		question_label.text = "Interactive workshop: build and test the automaton on the whiteboard."
		question_label.visible = true
		back_button.visible = false
		next_button.visible = false
		return
	var challenges: Array = AdaptiveContent.get_challenge_questions(_learning_skill)
	if _challenge_index >= challenges.size():
		# All challenges done
		_show_challenge_feedback()
		return

	_current_challenge = challenges[_challenge_index]
	_challenge_answered = false

	question_label.text = "Challenge %d/%d\n\n%s" % [_challenge_index + 1, challenges.size(), _current_challenge["question"]]
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
	progress_label.text = "Skill: %s | Challenge %d/%d" % [QuestionBank.get_skill_name(_learning_skill), _challenge_index + 1, challenges.size()]
	back_button.visible = false
	next_button.visible = false

func _on_challenge_answer(selected_index: int) -> void:
	if _challenge_answered:
		return
	_challenge_answered = true
	_challenge_total += 1

	var correct: bool = selected_index == _current_challenge["correct"]
	if correct:
		_challenge_correct += 1

	# Record adaptive evidence separately from the pretest baseline.
	session.knowledge_tracer.record_learning_observation(_learning_skill, correct)

	# Show feedback
	feedback_label.text = "Correct!" if correct else "Incorrect."
	feedback_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6, 1) if correct else Color(1, 0.5, 0.5, 1))
	feedback_label.text += "\n\n" + _current_challenge["explanation"]

	# Show next button
	next_button.visible = true
	next_button.text = "Next Challenge"
	back_button.visible = false

func _on_workshop_evaluated(correct: bool, message: String) -> void:
	if _challenge_answered:
		return
	_challenge_answered = true
	_challenge_total += 1
	if correct:
		_challenge_correct += 1
	session.knowledge_tracer.record_learning_observation(_learning_skill, correct)
	feedback_label.text = ("Correct! " if correct else "Keep trying. ") + message
	feedback_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6, 1) if correct else Color(1, 0.5, 0.5, 1))
	next_button.visible = true
	next_button.text = "Next Workshop Task"
	back_button.visible = false

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
	var learned: bool = session.knowledge_tracer.is_learned(_learning_skill)

	question_label.text = "You have completed the learning activity for %s.\n\nCurrent knowledge level: %.1f%%\n\n%s" % [
		QuestionBank.get_skill_name(_learning_skill),
		knowledge,
		"Excellent! You have mastered this skill." if learned else "You have improved, but may need more practice."
	]
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
	elif not _adaptive_review_pass:
		_adaptive_review_pass = true
		_analysis_skills = session.get_skills_by_weakness()
		_analysis_skill_index = 0
		question_label.text += "\n\nThe ordered DFA lesson is complete. Now adaptive review will revisit topics in pretest weakness order."
		next_button.text = "Start Adaptive Review"
	else:
		question_label.text += "\n\nAll seven topics and the adaptive review have now been covered."
		next_button.text = "Proceed to Post Test"

	feedback_label.text = ""
	progress_label.text = "Adaptive Learning Progress"
	back_button.visible = true
	back_button.text = "Back"
	next_button.visible = true

func _on_learning_next() -> void:
	var phase: int = session.get_learning_phase()

	match phase:
		0, 1, 2, 3, 4:
			session.advance_learning_phase()
			_show_learning_phase(phase + 1)
		5: # Challenge phase - next challenge or feedback
			var challenges: Array = AdaptiveContent.get_challenge_questions(_learning_skill)
			_challenge_index += 1
			if _challenge_index < challenges.size():
				_show_challenge()
			else:
				session.advance_learning_phase()
				_show_learning_phase(6)
		6: # Feedback - check if learned, if not, handhold
			var learned: bool = session.knowledge_tracer.is_learned(_learning_skill)
			if not learned:
				# Handhold: go back to definition and example
				_handholding = true
				_challenge_index = 0
				_challenge_correct = 0
				_challenge_total = 0
				_challenge_answered = false
				session.learning_phase = 1
				_show_learning_phase(1)
			else:
				session.advance_learning_phase()
				_show_learning_phase(7)
		7: # End - move to next skill or post test
			# This is handled by _on_next_pressed
			pass

# ===== POST TEST =====

func _start_posttest() -> void:
	_enter_test_panel()
	session.start_posttest()
	_show_posttest_question()

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

	var pretest: Dictionary = _results["pretest"]
	var posttest: Dictionary = _results["posttest"]

	var text := "Pretest Results:\n"
	text += "Score: %d/%d (%.1f%%)\n\n" % [pretest["correct"], pretest["total"], pretest["percentage"]]

	text += "Post Test Results:\n"
	text += "Score: %d/%d (%.1f%%)\n\n" % [posttest["correct"], posttest["total"], posttest["percentage"]]

	var improvement: float = posttest["percentage"] - pretest["percentage"]
	text += "Improvement: %+.1f%%\n\n" % improvement
	text += "Profile report saved to: %s\n\n" % report_path

	text += "Knowledge Summary:\n"
	var summary: Dictionary = _results["knowledge_summary"]
	for skill in summary:
		var data: Dictionary = summary[skill]
		text += "%s: %.1f%%\n" % [data["name"], data["mastery_percentage"]]

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

	# Go back to main menu
	_show_main_menu()

func _on_next_pressed() -> void:
	match session.state:
		SessionManager.SessionState.ANALYSIS:
			_start_adaptive_learning()
		SessionManager.SessionState.ADAPTIVE_LEARNING:
			if next_button.text == "Proceed to Post Test":
				_start_posttest()
			elif next_button.text == "Learn Next Skill" or next_button.text == "Next Topic":
				# Start learning the next weak skill
				_learning_skill = _analysis_skills[_analysis_skill_index]
				_challenge_index = 0
				_challenge_correct = 0
				_challenge_total = 0
				_challenge_answered = false
				_handholding = false
				session.start_adaptive_learning(_learning_skill)
				_enter_learning_room()
				_show_learning_phase(0)
			else:
				_on_learning_next()
		SessionManager.SessionState.COMPLETE:
			_show_results()

# ===== UI HELPERS =====

func _clear_content() -> void:
	if workshop:
		workshop.visible = false
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
	if overlay_layer:
		overlay_layer.visible = false
	if sprite:
		sprite.visible = true
	var player := get_node_or_null("../CharacterBody3D")
	if player:
		player.set_physics_process(true)
		player.set_process(true)

func _enter_test_panel() -> void:
	if workshop:
		workshop.visible = false
	if overlay_layer:
		overlay_layer.visible = true
	if sprite:
		sprite.visible = false
	var player := get_node_or_null("../CharacterBody3D")
	if player:
		player.set_physics_process(false)
		player.set_process(false)

func _set_player_paused(paused: bool) -> void:
	var player := get_node_or_null("../CharacterBody3D")
	if player:
		player.set_physics_process(not paused)
		player.set_process(not paused)

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

func _update_stats_panel() -> void:
	if stats_panel == null or session == null:
		return
	stats_panel.visible = true
	stats_title.text = "SESSION STATS"
	stats_mode.text = "Mode: %s" % InputMode.get_mode_name()

	# --- Algorithm ---
	var algo := "HMM"
	if session.knowledge_tracer:
		var at: int = session.knowledge_tracer.algorithm_type
		if at == 1:
			algo = "BKT"
		elif at == 2:
			algo = "DKT"
	stats_algo.text = "Algorithm: %s" % algo

	# --- Phase ---
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
	stats_phase.text = "Phase: %s" % phase

	# --- Progress ---
	if session.state == SessionManager.SessionState.PRETEST or session.state == SessionManager.SessionState.POST_TEST:
		stats_progress.text = "Progress: Q %d / %d" % [session.get_current_question_number(), session.get_total_questions()]
	else:
		stats_progress.text = "Progress: —"

	# --- Score (accumulated correct answers) ---
	var answered := 0
	var correct := 0
	for answer in session.pretest_answers:
		answered += 1
		if answer["correct"]:
			correct += 1
	for answer in session.posttest_answers:
		answered += 1
		if answer["correct"]:
			correct += 1
	var acc := 0.0
	if answered > 0:
		acc = float(correct) / float(answered) * 100.0
	stats_score.text = "Score: %d/%d (%.0f%%)" % [correct, answered, acc]

	# --- Per-skill accuracy ---
	var summary: Dictionary = session.knowledge_tracer.get_full_summary() if session.knowledge_tracer else {}
	var lines: Array[String] = []
	for skill in summary:
		var data: Dictionary = summary[skill]
		lines.append("%s: %d/%d · %.0f%%" % [data["name"], data["correct"], data["total"], data["accuracy_percentage"]])
	if lines.is_empty():
		stats_skills.text = "Skills:\nNo data yet"
	else:
		stats_skills.text = "Skills (acc):\n" + "\n".join(lines)

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