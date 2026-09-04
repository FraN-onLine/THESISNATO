extends Node3D
## Main controller for the Testing Grounds VR scene.
## Handles the full flow: Profile Setup → Algorithm Selection → Pretest → Analysis → Adaptive Learning → Post Test → Results.

const SessionManager = preload("res://Testing/session_manager.gd")
const QuestionBank = preload("res://Testing/Data/question_bank.gd")
const AdaptiveContent = preload("res://Testing/Data/adaptive_content.gd")

# How each knowledge-tracing algorithm works — displayed whenever the user picks
# one, and all three run in parallel so we can compare them for the POC.
const ALGORITHM_INFO := {
	0: {
		"name": "HMM (Hidden Markov Model)",
		"how": "Each skill is its own HMM with two HIDDEN states: 'knows' and 'doesn't know'. The visible states are the learner's answers (right/wrong). Every answer updates P(knows) with Bayes' rule — a correct answer raises it, a wrong one lowers it, and a small learning/forgetting transition nudges the estimate each step. The driver reads this P(knows) to decide if the skill is mastered."
	},
	1: {
		"name": "BKT (Bayesian Knowledge Tracing)",
		"how": "The classic four-parameter model per skill: P(L0) initial chance of knowing, P(T) chance of learning after one practice, P(S) the 'slip' chance of answering wrong despite knowing, P(G) the 'guess' chance of answering right without knowing. Each answer reweights P(learned) with Bayes — mastery requires repeated evidence — and it is intentionally simple and explainable."
	},
	2: {
		"name": "DKT (Deep Knowledge Tracing)",
		"how": "A small neural network (a hidden layer with tanh, a sigmoid output per skill) learns, from the sequence of answers, to predict each skill's next-answer probability. It sees the raw answer history (one-hot per skill+correctness) and is trained by back-propagation after every answer, capturing cross-skill transfer that HMM/BKT cannot."
	},
}

# Whiteboard (automata builder) challenges the learner must construct on the real
# board before the free-choice multiple-choice questions of that topic. Each one
# carries the instruction plus the accept/reject test strings used by Check task.
const WORKSHOP_TASKS := {
	"building": [
		{"instruction": "Build a DFA over {a,b} that ACCEPTS any string ending in 'ab' and REJECTS others.", "accepted": "ab", "rejected": "aa", "accept": ["ab", "aab", "bab"], "reject": ["a", "aa", "ba"]},
		{"instruction": "Build a DFA over {a,b} that ACCEPTS strings with an EVEN number of 'a's.", "accepted": "aab", "rejected": "a", "accept": ["", "aa", "baab"], "reject": ["a", "aba", "aaa"]},
	],
	"regex": [
		{"instruction": "Build a DFA for the regex a*b (zero or more a's then one b).", "accepted": "aab", "rejected": "aba", "accept": ["b", "ab", "aab"], "reject": ["" ,"a", "aba", "abab"]},
		{"instruction": "Build a DFA for the regex (a|b)*a (any string ending in 'a').", "accepted": "bba", "rejected": "ab", "accept": ["a", "ba", "aba", "bba"], "reject": ["b", "ab", "aab"]},
	],
	"set_builder": [
		{"instruction": "Build a DFA for {w over {0,1} : w contains '00'}.", "accepted": "1001", "rejected": "101", "accept": ["00", "100", "1001", "000"], "reject": ["0", "1", "10", "101"]},
		{"instruction": "Build a DFA for {w over {a,b} : |w| is even}.", "accepted": "aa", "rejected": "a", "accept": ["", "aa", "abab"], "reject": ["a", "aaa", "ab"]},
	],
	"simulation": [
		{"instruction": "Build a DFA over {a,b} ACCEPTING strings ending in 'a'.", "accepted": "ba", "rejected": "ab", "accept": ["a", "ba", "aba"], "reject": ["b", "ab", "ba"]},
		{"instruction": "Build a DFA over {a,b} ACCEPTING 'ba' and REJECTING 'ab'.", "accepted": "ba", "rejected": "ab", "accept": ["ba"], "reject": ["ab"]},
		{"instruction": "Build a DFA over {0,1} ACCEPTING strings ending in '1'.", "accepted": "101", "rejected": "111", "accept": ["1", "01", "101"], "reject": ["0", "10", "10", "00"]},
	],
	"list": [
		{"instruction": "From the list {ab, aab, aaab, ...} build a DFA (a+b).", "accepted": "aab", "rejected": "ababb", "accept": ["ab", "aab", "aaab"], "reject": ["a", "b", "abab", "aba"]},
	],
}

# The ordered DFA-centered course. The whole lesson is taught as ONE sequence of
# topics (each folds in the relevant 7 segments under the hood), then adaptive
# review re-visits each skill in the learner's weakest-first order, then post test.
# "demo" steps first show "explain" text (what the language means) and then pass a
# flexible task to the whiteboard: the learner may build ANY correct automaton —
# validation uses the accept/reject string lists, so any valid construction passes.
const DFA_LESSON_SPEC := [
	{"m": "content", "skill": "definition", "field": "definition", "title": "WHAT IS A DFA", "subtitle": "Definition, purpose, and the idea of finite memory."},
	{"m": "content", "skill": "definition", "field": "guided", "title": "PARTS OF A DFA & THE 5-TUPLE", "subtitle": "States Set Q, Alphabet, Transition, Start, Final(s)."},
	{"m": "content", "skill": "definition", "field": "example", "title": "THE 5-TUPLE NOTATION IN PRACTICE", "subtitle": "Q, Sigma, delta, q0, F written out for a real machine."},
	{"m": "content", "skill": "identification", "field": "definition", "title": "HOW DFAs ARE REPRESENTED", "subtitle": "Tables, transition diagrams & formal 5-tuples."},
	{"m": "demo", "skill": "building", "title": "SEE A DFA AT THE WHITEBOARD",
	 "explain": "This is a complete DFA over {a,b}: it ACCEPTS strings ending in 'a' (like 'a', 'ba', 'aba') and REJECTS strings ending in 'b'. Notice the accepting state has a double ring. Every state has exactly one arrow per symbol.",
	 "task": {"instruction": "This reference DFA is already built for you. Press Check task to confirm it works.", "seed": true, "accepted": "ba", "rejected": "bb", "accept": ["a", "ba", "aba", "bba"], "reject": ["b", "ab", "bb", "aab"]}},
	{"m": "content", "skill": "building", "field": "application", "title": "DFAs IN REAL LIFE", "subtitle": "Firewalls, lexical analysers, regex engines, text search."},
	{"m": "content", "skill": "simulation", "field": "definition", "title": "SIMULATION", "subtitle": "Tracing input strings through states to accept or reject."},
	{"m": "demo", "skill": "simulation", "title": "SIMULATE ON THE WHITEBOARD",
	 "explain": "We say 'string ends in a' means the LAST symbol is 'a'. So 'ba' is accepted, 'ab' is rejected. Now build any DFA that accepts exactly the strings ending in 'a' over {a,b} — there are several correct ways.",
	 "task": {"instruction": "Build a DFA over {a,b} that ACCEPTS strings ending in 'a' and REJECTS those ending in 'b'. Then simulate some strings.", "accepted": "ba", "rejected": "ab", "accept": ["a", "ba", "aba", "bba"], "reject": ["b", "ab", "bb", "aab"]}},
	{"m": "content", "skill": "building", "field": "guided", "title": "HOW DO WE KNOW A DFA IS CORRECT?", "subtitle": "Test accepted/rejected strings on the whiteboard."},
	{"m": "demo", "skill": "building", "title": "BUILD: LIST / RULE / REGEX",
	 "explain": "The list {a, aa, aaa, ...} means 'one or more a's', written a+ in regex, or {w : w is only a's and |w| >= 1} as a rule. All three describe the SAME language — build any DFA for it.",
	 "task": {"instruction": "From the list {a, aa, aaa, ...} build a DFA for a+ (one or more a's). ACCEPT any all-a string, REJECT anything with a b or the empty string.", "accepted": "aaa", "rejected": "b", "accept": ["a", "aa", "aaa"], "reject": ["", "b", "ab", "ba"]}},
	{"m": "content", "skill": "regex", "field": "definition", "title": "DFA FROM REGEX", "subtitle": "a*, a+, a|b, a*b patterns become machines."},
	{"m": "demo", "skill": "regex", "title": "MAKE 01* TRUE ON THE WHITEBOARD",
	 "explain": "01* means: a '0' followed by zero or more '1's. So the ACCEPTED strings are 0, 01, 011, 0111, ... Everything else is rejected. Now build ANY automaton that accepts exactly this language.",
	 "task": {"instruction": "Build a DFA over {0,1} that ACCEPTS exactly the language 01* (0 then any number of 1s).", "accepted": "011", "rejected": "10", "accept": ["0", "01", "011", "0111"], "reject": ["", "1", "00", "10", "010", "11"]}},
	{"m": "content", "skill": "set_builder", "field": "definition", "title": "DFA FROM SET BUILDER", "subtitle": "{w : condition(w)} becomes a machine."},
	{"m": "demo", "skill": "set_builder", "title": "BUILD A SET-BUILDER DFA",
	 "explain": "{w in {0,1}* : w contains '00'} means: the string '00' appears somewhere. '1001' is accepted, '101' is rejected. Build any DFA for this language.",
	 "task": {"instruction": "Build a DFA over {0,1} that ACCEPTS strings containing the substring '00'.", "accepted": "1001", "rejected": "101", "accept": ["00", "100", "1001", "000"], "reject": ["0", "1", "10", "101"]}},
	{"m": "content", "skill": "list", "field": "definition", "title": "DFA FROM LIST", "subtitle": "Infer the hidden language from example strings."},
	{"m": "demo", "skill": "list", "title": "INFER A DFA FROM A LIST",
	 "explain": "The list {ab, aab, aaab, ...} shows the pattern: one or more a's then a final b, written a+b. Build any automaton that accepts exactly those strings.",
	 "task": {"instruction": "From {ab, aab, aaab, ...} infer the language a+b and build a DFA for it.", "accepted": "aab", "rejected": "ababb", "accept": ["ab", "aab", "aaab"], "reject": ["a", "b", "aba", "abab"]}},
	{"m": "practice", "skill": "simulation", "title": "PRACTICE PROBLEMS | SIMULATION"},
	{"m": "practice", "skill": "building", "title": "PRACTICE PROBLEMS | BUILDING"},
	{"m": "practice", "skill": "definition", "title": "QUESTIONS | DFA & ITS 5-TUPLE"},
]

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

# Statistics side-panel references
@onready var stats_panel: PanelContainer = $SubViewport/Root/StatsPanel
@onready var stats_title: Label = $SubViewport/Root/StatsPanel/StatsVBox/StatsTitle
@onready var stats_algo: Label = $SubViewport/Root/StatsPanel/StatsVBox/StatsAlgo
@onready var stats_phase: Label = $SubViewport/Root/StatsPanel/StatsVBox/StatsPhase
@onready var stats_progress: Label = $SubViewport/Root/StatsPanel/StatsVBox/StatsProgress
@onready var stats_score: Label = $SubViewport/Root/StatsPanel/StatsVBox/StatsScore
@onready var stats_skills: Label = $SubViewport/Root/StatsPanel/StatsVBox/StatsSkills
@onready var stats_workshop: Label = $SubViewport/Root/StatsPanel/StatsVBox/StatsWorkshop
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

# DFA-centered lesson navigation
var _in_dfa_lesson := false
var _dfa_lesson_index := 0
var _dfa_practice_index := 0
var _dfa_practice_skill := "simulation"
var _dfa_practice_answered := false
var _dfa_practice_board_active := false
var _dfa_board_practice_index := 0
var _dfa_board_practice_active := false
var _dfa_board_practice_skill := "simulation"

# Workshop (automata builder) task navigation during a skill's interactive phase
var _workshop_phase := false
var _workshop_task_index := 0
# True while the whiteboard is paired with a multiple-choice challenge (so the
# board's Check task only gives feedback and does NOT advance the lesson).
var _adaptive_board_paired := false

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
		workshop.set_active(false)

	# The SessionBridge owns the single live session shared with the separate
	# Pretest / Post-test room, so returning here keeps all answers and states.
	session = SessionBridge.get_session()

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

	question_label.text = "Welcome to the DFA Testing Grounds!\n\nThis adaptive system walks you through:\n1. Pretest (30 questions across all DFA topics)\n2. Knowledge Analysis\n3. DFA Lesson (taught as ONE course, whiteboard + practice)\n4. Adaptive Review (weakest topics first)\n5. Post Test\n\nSelect an algorithm to begin:"
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
	_show_algorithm_explanation(algo_type)

func _show_algorithm_explanation(algo_type: int) -> void:
	title_label.text = "ALGORITHM EXPLANATION"
	_clear_content()
	var info: Dictionary = ALGORITHM_INFO.get(algo_type, {})
	question_label.text = "You selected: %s\n\nHow it works:\n%s\n\nNote: all three models (HMM, BKT, DKT) run in parallel during this session so we can compare their prediction accuracy on the stats board — the best one will be chosen for the POC. The one you picked just drives the lesson/masternese decisions." % [info.get("name", ""), info.get("how", "")]
	question_label.visible = true
	_clear_options()

	var continue_btn := Button.new()
	continue_btn.text = "Continue to Profile Setup"
	continue_btn.custom_minimum_size = Vector2(800, 50)
	continue_btn.add_theme_font_size_override("font_size", 20)
	continue_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	continue_btn.add_theme_stylebox_override("normal", _create_button_style(Color(0.16, 0.28, 0.62, 1)))
	continue_btn.add_theme_stylebox_override("hover", _create_button_style(Color(0.3, 0.48, 0.95, 1)))
	continue_btn.add_theme_stylebox_override("pressed", _create_button_style(Color(0.1, 0.19, 0.45, 1)))
	continue_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	continue_btn.pressed.connect(_show_profile_setup)
	options_box.add_child(continue_btn)
	feedback_label.text = ""
	progress_label.text = ""
	back_button.visible = true
	back_button.text = "Back"
	next_button.visible = false

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

	question_label.text += summary_text + "\n\nA guided DFA lesson will now teach the whole topic (5-tuple, representations, whiteboard building, simulation, correctness) as ONE course, then adaptively review every topic in the order of your weaknesses.\n\nClick Next to begin the DFA Lesson."

	back_button.visible = true
	back_button.text = "Back"
	next_button.visible = true
	next_button.text = "Start DFA Lesson"

# ===== DFA-CENTERED LESSON =====

func _begin_dfa_lesson() -> void:
	_in_dfa_lesson = true
	_dfa_lesson_index = 0
	_dfa_practice_index = 0
	_dfa_board_practice_index = 0
	_dfa_board_practice_active = false
	_dfa_board_practice_skill = "simulation"
	_show_dfa_lesson_step()

func _show_dfa_lesson_step() -> void:
	if _dfa_lesson_index >= DFA_LESSON_SPEC.size():
		_finish_dfa_lesson()
		return
	var step: Dictionary = DFA_LESSON_SPEC[_dfa_lesson_index]
	match step["m"]:
		"content":
			_show_dfa_content(step)
		"demo":
			_open_dfa_workshop(step)
		"practice":
			_dfa_practice_skill = step["skill"]
			_dfa_practice_index = 0
			var practice_tasks: Array = WORKSHOP_TASKS.get(step["skill"], [])
			if workshop != null and workshop.builder is Control and not practice_tasks.is_empty():
				# Board-task practice: build & verify each DFA on the board to proceed.
				_dfa_board_practice_skill = step["skill"]
				_dfa_board_practice_active = true
				_dfa_board_practice_index = 0
				_open_dfa_board_practice(step["skill"], practice_tasks[0])
			else:
				# Question practice: answer each multiple-choice question to proceed.
				_show_dfa_practice(step)

func _show_dfa_content(step: Dictionary) -> void:
	title_label.text = "DFA LESSON — %s" % step["title"]
	_clear_content()
	_enter_learning_room()
	var field: String = step.get("field", "definition")
	var body := ""
	match field:
		"definition": body = AdaptiveContent.get_definition(step["skill"])
		"guided": body = AdaptiveContent.get_guided(step["skill"])
		"example": body = AdaptiveContent.get_example(step["skill"])
		"application": body = AdaptiveContent.get_application(step["skill"])
		_: body = AdaptiveContent.get_definition(step["skill"])
	body = "%s\n\n%s" % [step.get("subtitle", ""), body]
	question_label.text = "Step %d / %d\n\n%s" % [_dfa_lesson_index + 1, DFA_LESSON_SPEC.size(), body]
	question_label.visible = true
	_clear_options()
	feedback_label.text = ""
	progress_label.text = "DFA Lesson  ·  %s" % QuestionBank.get_skill_name(step["skill"])
	back_button.visible = false
	next_button.visible = true
	next_button.text = "Next >>"

var _dfa_pending_explain: Dictionary = {}
var _dfa_pending_skill: Dictionary = {}

func _open_dfa_workshop(step: Dictionary) -> void:
	if workshop == null:
		_dfa_lesson_index += 1
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
	back_button.visible = false
	next_button.visible = true
	next_button.text = "Build it on the Whiteboard"

func _activate_dfa_board(step: Dictionary) -> void:
	var task: Dictionary = step.get("task", {})
	_dfa_pending_skill = {}
	if workshop.builder is Control and not task.is_empty():
		if task.has("accept") and task.has("reject") and not task["accept"].is_empty():
			workshop.builder.call("reset_for_task_lists",
				task.get("instruction", "Build the DFA on the whiteboard."),
				task["accept"], task["reject"])
		else:
			workshop.builder.call("reset_for_task",
				task.get("instruction", "Build the DFA on the whiteboard."),
				task.get("accepted", "aa"),
				task.get("rejected", "ab"))
		# Optional reference graph to show a complete example.
		if task.get("seed", false):
			workshop.builder.call("seed_reference_graph")
	_enter_learning_room()
	workshop.set_active(true)
	if sprite:
		sprite.visible = false
	_set_player_paused(true)
	title_label.text = "DFA LESSON — %s" % step["title"]
	question_label.text = "Build it on the whiteboard.\n\nCreate states, toggle accepting, connect transitions, then press Check task to verify. The board accepts ANY correct construction — not just one specific one.\n\n%s" % step.get("task", {}).get("instruction", "")
	question_label.visible = true
	_clear_options()
	feedback_label.text = ""
	progress_label.text = "DFA Lesson  ·  Whiteboard"
	back_button.visible = false
	next_button.visible = false

func _show_dfa_practice(step: Dictionary) -> void:
	title_label.text = "DFA LESSON — %s" % step["title"]
	_dfa_practice_answered = false
	_clear_content()
	_enter_learning_room()
	var challenges: Array = AdaptiveContent.get_challenge_questions(_dfa_practice_skill)
	if _dfa_practice_index >= challenges.size():
		# All questions for this skill are done → close the paired board, continue.
		_close_paired_board()
		_dfa_lesson_index += 1
		_show_dfa_lesson_step()
		return
	var current: Dictionary = challenges[_dfa_practice_index]
	# Pair the whiteboard with this question so the learner can build/test while
	# answering. The board task matches the skill AND the question number.
	var paired := _pair_practice_board(_dfa_practice_skill, _dfa_practice_index)
	_dfa_practice_board_active = paired
	var hint := "\n\nUse the whiteboard to build and test the automaton before choosing your answer." if paired else ""
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
	back_button.visible = false
	next_button.visible = false

## Activate the whiteboard with a task matching the practice skill + question.
func _pair_practice_board(skill: String, index: int) -> bool:
	if workshop == null or workshop.builder is not Control:
		return false
	var tasks: Array = WORKSHOP_TASKS.get(skill, [])
	if tasks.is_empty():
		return false
	var task: Dictionary = tasks[index % tasks.size()]
	_reset_board_for_task(task)
	workshop.set_active(true)
	if sprite:
		sprite.visible = false
	_set_player_paused(true)
	return true

## Shared helper: push a WORKSHOP_TASKS / DFA_LESSON_SPEC task into the builder.
func _reset_board_for_task(task: Dictionary) -> void:
	if workshop == null or workshop.builder is not Control:
		return
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
	var skill_tasks: Array = WORKSHOP_TASKS.get(skill, [])
	_enter_learning_room()
	if workshop.builder is Control:
		if task.has("accept") and task.has("reject") and not task["accept"].is_empty():
			workshop.builder.call("reset_for_task_lists", task["instruction"], task["accept"], task["reject"])
		else:
			workshop.builder.call("reset_for_task", task["instruction"], task["accepted"], task["rejected"])
	workshop.set_active(true)
	if sprite:
		sprite.visible = false
	_set_player_paused(true)
	question_label.text = "Whiteboard practice %d / %d - %s\n\n%s\n\nBuild the DFA on the board, then press Check task. Any correct construction is accepted; wrong attempts stay here until the build passes." % [_dfa_board_practice_index + 1, skill_tasks.size(), QuestionBank.get_skill_name(skill), task["instruction"]]
	question_label.visible = true
	_clear_options()
	feedback_label.text = ""
	progress_label.text = "DFA Lesson · Whiteboard practice · %s" % QuestionBank.get_skill_name(skill)
	back_button.visible = false
	next_button.visible = false

func _on_dfa_practice_answer(selected_index: int) -> void:
	if _dfa_practice_answered:
		return
	var challenges: Array = AdaptiveContent.get_challenge_questions(_dfa_practice_skill)
	if _dfa_practice_index >= challenges.size():
		return
	var current: Dictionary = challenges[_dfa_practice_index]
	_dfa_practice_answered = true
	var correct: bool = selected_index == current["correct"]
	session.knowledge_tracer.record_learning_observation(_dfa_practice_skill, correct)
	feedback_label.text = ("Correct! " if correct else "Incorrect. ") + current.get("explanation", "")
	feedback_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6, 1) if correct else Color(1, 0.5, 0.5, 1))
	_dfa_practice_index += 1
	if _dfa_practice_index >= challenges.size():
		next_button.visible = true
		next_button.text = "Next Topic >>"
	else:
		next_button.visible = true
		next_button.text = "Next Question >>"
	back_button.visible = false

func _handle_dfa_lesson_next() -> void:
	# Transition from the "explanation" step screen into the whiteboard build.
	if not _dfa_pending_skill.is_empty():
		var pending: Dictionary = _dfa_pending_skill
		_dfa_pending_skill = {}
		_activate_dfa_board(pending)
		return
	var step: Dictionary = DFA_LESSON_SPEC[_dfa_lesson_index]
	match step["m"]:
		"content":
			_dfa_lesson_index += 1
			_show_dfa_lesson_step()
		"practice":
			var challenges: Array = AdaptiveContent.get_challenge_questions(_dfa_practice_skill)
			if _dfa_practice_index >= challenges.size():
				# All questions answered → next topic.
				_close_paired_board()
				_dfa_lesson_index += 1
				_show_dfa_lesson_step()
			else:
				# Still more questions — show the NEXT one (index already advanced
				# by _on_dfa_practice_answer) WITHOUT resetting to question 1.
				_show_dfa_practice(step)
		_:
			_dfa_lesson_index += 1
			_show_dfa_lesson_step()

func _finish_dfa_lesson() -> void:
	_in_dfa_lesson = false
	# The guided lesson is complete; adaptive review then re-visits every one of
	# the seven topics in the learner's personal weakness order, followed by the
	# post test.
	_start_adaptive_learning()

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
	_workshop_task_index = 0
	_workshop_phase = false
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
	# Builder phase: the learner must construct a working DFA on the whiteboard
	# (one task per WORKSHOP_TASKS entry) BEFORE the free-response challenges.
	if workshop and WORKSHOP_TASKS.has(_learning_skill):
		var tasks: Array = WORKSHOP_TASKS[_learning_skill]
		if _workshop_task_index < tasks.size():
			_open_builder_task(tasks[_workshop_task_index])
			return
	var challenges: Array = AdaptiveContent.get_challenge_questions(_learning_skill)
	if _challenge_index >= challenges.size():
		# All challenges done
		_show_challenge_feedback()
		return

	_current_challenge = challenges[_challenge_index]
	_challenge_answered = false

	# Pair the whiteboard with this challenge so the learner can build/test while
	# choosing an answer (only for skills that have a build task).
	var paired := _pair_practice_board(_learning_skill, _challenge_index)
	_adaptive_board_paired = paired
	var hint := "\n\nUse the whiteboard to build and test the automaton before choosing your answer." if paired else ""
	question_label.text = "Challenge %d/%d\n\n%s%s" % [_challenge_index + 1, challenges.size(), _current_challenge["question"], hint]
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
	progress_label.text = "Skill: %s | Challenge %d/%d%s" % [QuestionBank.get_skill_name(_learning_skill), _challenge_index + 1, challenges.size(), "  ·  whiteboard active — build/check, then answer" if _adaptive_board_paired else ""]
	back_button.visible = false
	next_button.visible = false

func _on_challenge_answer(selected_index: int) -> void:
	if _challenge_answered:
		return
	_challenge_answered = true
	_challenge_total += 1
	_adaptive_board_paired = false

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

func _open_builder_task(task: Dictionary) -> void:
	_workshop_phase = true
	_adaptive_board_paired = false
	_enter_learning_room()
	if workshop:
		if workshop.builder is Control:
			if task.has("accept") and task.has("reject") and not task["accept"].is_empty():
				workshop.builder.call("reset_for_task_lists", task.get("instruction", "Build the DFA on the whiteboard."), task["accept"], task["reject"])
			else:
				workshop.builder.call("reset_for_task", task.get("instruction", "Build the DFA on the whiteboard."), task.get("accepted", "aa"), task.get("rejected", "ab"))
		workshop.set_active(true)
	if sprite:
		sprite.visible = false
	_set_player_paused(true)
	question_label.text = "Whiteboard task: build the DFA, then press Check task. Any correct construction is accepted.\n\n%s" % task.get("instruction", "")
	question_label.visible = true
	_clear_options()
	feedback_label.text = ""
	progress_label.text = "Interactive Challenge  ·  %s  ·  press Check task to verify" % QuestionBank.get_skill_name(_learning_skill)
	back_button.visible = false
	next_button.visible = false

func _on_workshop_evaluated(correct: bool, message: String) -> void:
	# --- DFA lesson whiteboard phase ---
	if _in_dfa_lesson:
		var dfa_skill: String = DFA_LESSON_SPEC[_dfa_lesson_index].get("skill", "building") if _dfa_lesson_index < DFA_LESSON_SPEC.size() else "building"
		var dfa_stats: Dictionary = workshop.builder.call("get_attempt_stats") if workshop.builder is Control else {}
		session.record_workshop_attempt(dfa_skill, correct, dfa_stats)
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
			var bp_tasks: Array = WORKSHOP_TASKS.get(_dfa_board_practice_skill, [])
			_dfa_board_practice_index += 1
			if _dfa_board_practice_index < bp_tasks.size():
				_open_dfa_board_practice(_dfa_board_practice_skill, bp_tasks[_dfa_board_practice_index])
				return
			# All board tasks for this skill are verified -> on to the next step.
			_dfa_board_practice_active = false
			_clear_content()
			workshop.set_active(false)
			_set_player_paused(false)
			_dfa_lesson_index += 1
			_show_dfa_lesson_step()
			return
		_dfa_lesson_index += 1
		_clear_content()
		workshop.set_active(false)
		_set_player_paused(false)
		_show_dfa_lesson_step()
		return
	# --- Adaptive skill builder phase ---
	if _challenge_answered or workshop == null:
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
		# Pause: stay on the board; only a successful build advances the lesson.
		feedback_label.text = message + "\nTry again — adjust states or transitions on the whiteboard."
		feedback_label.add_theme_color_override("font_color", Color(1, 0.5, 0.5, 1))
		return
	# Correct build → next workshop task or on to the multiple-choice challenges.
	_workshop_task_index += 1
	session.knowledge_tracer.record_learning_observation(_learning_skill, true)
	feedback_label.text = "Correct! " + message
	feedback_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6, 1))
	var tasks: Array = WORKSHOP_TASKS.get(_learning_skill, [])
	if _workshop_task_index < tasks.size():
		_open_builder_task(tasks[_workshop_task_index])
		return
	_workshop_phase = false
	_challenge_answered = false
	_challenge_index = 0
	_clear_content()
	workshop.set_active(false)
	_set_player_paused(false)
	_show_challenge()

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

	# --- Algorithm comparison → pick the best model for the POC ---
	if session and session.knowledge_tracer:
		text += "\nALGORITHM COMPARISON  (prediction hit-rate)\n"
		var cmp: Dictionary = session.knowledge_tracer.get_algorithm_comparison()
		var best_key := "HMM"
		var best_acc := -1.0
		for key in ["HMM", "BKT", "DKT"]:
			var s: Dictionary = cmp[key]
			text += "  %s: %d/%d hits (%.1f%%)\n" % [key, s["hits"], s["total"], s["accuracy"]]
			if s["accuracy"] > best_acc:
				best_acc = s["accuracy"]
				best_key = key
		text += "\n★ Recommended for the POC: %s (highest prediction accuracy)\n" % best_key

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
			for r in records3:
				wrong_tries += r.get("wrong_attempts", 0)
				conns += r.get("connections_made", 0)
				time_s += float(r.get("time_seconds", 0.0))
				if r.get("correct", false):
					ok_count += 1
			text += "  %s: %d builds passed, %d wrong checks, %d connection edits, %.0fs on task\n" % [QuestionBank.get_skill_name(skill3), ok_count, wrong_tries, conns, time_s]

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
			elif next_button.text == "Learn Next Skill" or next_button.text == "Next Topic":
				# Start learning the next weak skill
				_learning_skill = _analysis_skills[_analysis_skill_index]
				_challenge_index = 0
				_challenge_correct = 0
				_challenge_total = 0
				_challenge_answered = false
				_handholding = false
				_workshop_task_index = 0
				_workshop_phase = false
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
		workshop.set_active(false)
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

	# --- Whiteboard (automata builder) analytics ---
	var wshop_lines: Array[String] = ["Whiteboard:"]
	var wdata: Dictionary = session.get_workshop_attempts() if session else {}
	for skill in wdata:
		var records: Array = wdata[skill]
		var total_attempts := 0
		var wrong := 0
		var conns := 0
		var time_s := 0.0
		var successes := 0
		for r in records:
			total_attempts += r.get("attempts", 0)
			wrong += r.get("wrong_attempts", 0)
			conns += r.get("connections_made", 0)
			time_s += float(r.get("time_seconds", 0.0))
			if r.get("correct", false):
				successes += 1
		if records.is_empty():
			continue
		var sname: String = QuestionBank.get_skill_name(skill)
		wshop_lines.append("%s: %d/%d ok · %d attempts · %d wrong · %d conns · %.0fs" % [sname, successes, records.size(), total_attempts, wrong, conns, time_s])
	if stats_workshop:
		stats_workshop.text = "\n".join(wshop_lines)

	# --- 3D stats blackboard report (always faces the player) ---
	_update_stats_board(phase, answered, correct, acc)

func _update_stats_board(phase: String, answered: int, correct: int, acc: float) -> void:
	if stats_board == null or session == null:
		return
	var lines: Array[String] = []
	lines.append("SESSION STATS  ·  " + phase)
	lines.append("Mode: %s   |   Active algorithm drives learning:" % InputMode.get_mode_name())
	var algo_view := "HMM"
	if session.knowledge_tracer:
		var at: int = session.knowledge_tracer.algorithm_type
		if at == 1:
			algo_view = "BKT"
		elif at == 2:
			algo_view = "DKT"
		# The other two models still run in the background for the POC comparison.
		lines.append("Primary: %s   (all 3 models run in parallel for comparison)" % algo_view)
		lines.append("")
		lines.append("ALGORITHM COMPARISON  (prediction hit-rate)")
		var cmp: Dictionary = session.knowledge_tracer.get_algorithm_comparison()
		for key in ["HMM", "BKT", "DKT"]:
			var s: Dictionary = cmp[key]
			lines.append("  %s: %d/%d hits  (%.1f%%)" % [key, s["hits"], s["total"], s["accuracy"]])
		lines.append("")
		lines.append("MASTERY BY SKILL   (HMM  |  BKT  |  DKT)")
		for skill in session.knowledge_tracer.SKILL_ORDER:
			var hmm_p = session.knowledge_tracer.hmm_models.get(skill)
			var bkt_p = session.knowledge_tracer.bkt_models.get(skill)
			var dkt_pkg = session.knowledge_tracer.dkt_model
			var hmm_v = hmm_p.get_knowledge_probability() * 100.0 if hmm_p else 0.0
			var bkt_v = bkt_p.get_knowledge_probability() * 100.0 if bkt_p else 0.0
			var dkt_v = dkt_pkg.get_knowledge_probability(skill) * 100.0 if dkt_pkg else 0.0
			lines.append("  %-16s %.0f%%  |  %.0f%%  |  %.0f%%" % [QuestionBank.get_skill_name(skill), hmm_v, bkt_v, dkt_v])
	lines.append("")
	lines.append("SCORE: %d/%d  (%.1f%%)" % [correct, answered, acc])
	lines.append("")
	# Whiteboard attempt analytics
	var wdata2: Dictionary = session.get_workshop_attempts()
	if not wdata2.is_empty():
		lines.append("WHITEBOARD BUILDS")
		wdata2 = session.get_workshop_attempts()
		for skill2 in wdata2:
			var records2: Array = wdata2[skill2]
			if records2.is_empty():
				continue
			var ok_count := 0
			var try_count := 0
			for r in records2:
				try_count += r.get("attempts", 0)
				if r.get("correct", false):
					ok_count += 1
			lines.append("  %s: %d build(s) passed, %d total checks" % [QuestionBank.get_skill_name(skill2), ok_count, try_count])
	lines.append("")
	lines.append("Live-updating — build, simulate and check tasks to watch it change.")
	stats_board.call("set_stats_text", "\n".join(lines))

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
