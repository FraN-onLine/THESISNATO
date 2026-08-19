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

# Session manager
var session: SessionManager

# UI state
var _last_mouse_pos := Vector2(-1, -1)
var _is_pressed := false
var _lasers := {}

# Profile setup state
var _profile_name: String = ""
var _profile_gender: String = "Male"
var _profile_age: int = 18
var _profile_familiar: bool = false

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

# Results state
var _results: Dictionary = {}

func _ready() -> void:
	if viewport and sprite:
		sprite.texture = viewport.get_texture()
	
	# Connect buttons
	back_button.pressed.connect(_on_back_pressed)
	next_button.pressed.connect(_on_next_pressed)
	
	# Initialize session
	session = SessionManager.new()
	
	# Show the main menu
	_show_main_menu()

func _process(_delta: float) -> void:
	_update_pointer()

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
	
	if session.needs_profile_setup():
		_show_profile_setup()
	else:
		_show_pretest_intro()

# ===== PROFILE SETUP =====

func _show_profile_setup() -> void:
	title_label.text = "PROFILE SETUP"
	_clear_content()
	
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
	
	var gender_box := HBoxContainer.new()
	gender_box.add_theme_constant_override("separation", 10)
	options_box.add_child(gender_box)
	
	var male_btn := Button.new()
	male_btn.text = "Male"
	male_btn.custom_minimum_size = Vector2(390, 40)
	male_btn.add_theme_font_size_override("font_size", 18)
	male_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	male_btn.add_theme_stylebox_override("normal", _create_button_style(Color(0.16, 0.28, 0.62, 1)))
	male_btn.add_theme_stylebox_override("hover", _create_button_style(Color(0.3, 0.48, 0.95, 1)))
	male_btn.add_theme_stylebox_override("pressed", _create_button_style(Color(0.1, 0.19, 0.45, 1)))
	male_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	male_btn.pressed.connect(func(): _profile_gender = "Male")
	gender_box.add_child(male_btn)
	
	var female_btn := Button.new()
	female_btn.text = "Female"
	female_btn.custom_minimum_size = Vector2(390, 40)
	female_btn.add_theme_font_size_override("font_size", 18)
	female_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	female_btn.add_theme_stylebox_override("normal", _create_button_style(Color(0.16, 0.28, 0.62, 1)))
	female_btn.add_theme_stylebox_override("hover", _create_button_style(Color(0.3, 0.48, 0.95, 1)))
	female_btn.add_theme_stylebox_override("pressed", _create_button_style(Color(0.1, 0.19, 0.45, 1)))
	female_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	female_btn.pressed.connect(func(): _profile_gender = "Female")
	gender_box.add_child(female_btn)
	
	# Age input
	var age_label := Label.new()
	age_label.text = "Age:"
	age_label.add_theme_font_size_override("font_size", 18)
	age_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	options_box.add_child(age_label)
	
	var age_input := SpinBox.new()
	age_input.min_value = 5
	age_input.max_value = 100
	age_input.value = 18
	age_input.custom_minimum_size = Vector2(800, 40)
	age_input.add_theme_font_size_override("font_size", 18)
	age_input.value_changed.connect(func(value): _profile_age = int(value))
	options_box.add_child(age_input)
	
	# Familiarity toggle
	var familiar_label := Label.new()
	familiar_label.text = "Are you familiar with Automata Theory?"
	familiar_label.add_theme_font_size_override("font_size", 18)
	familiar_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	options_box.add_child(familiar_label)
	
	var familiar_btn := Button.new()
	familiar_btn.text = "No"
	familiar_btn.custom_minimum_size = Vector2(800, 40)
	familiar_btn.add_theme_font_size_override("font_size", 18)
	familiar_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	familiar_btn.add_theme_stylebox_override("normal", _create_button_style(Color(0.16, 0.28, 0.62, 1)))
	familiar_btn.add_theme_stylebox_override("hover", _create_button_style(Color(0.3, 0.48, 0.95, 1)))
	familiar_btn.add_theme_stylebox_override("pressed", _create_button_style(Color(0.1, 0.19, 0.45, 1)))
	familiar_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	familiar_btn.pressed.connect(func():
		_profile_familiar = not _profile_familiar
		familiar_btn.text = "Yes" if _profile_familiar else "No"
	)
	options_box.add_child(familiar_btn)
	
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
	if _profile_name.is_empty():
		feedback_label.text = "Please enter your name."
		feedback_label.add_theme_color_override("font_color", Color(1, 0.5, 0.5, 1))
		return
	
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
	title_label.text = "KNOWLEDGE ANALYSIS"
	_clear_content()
	
	var summary: Dictionary = session.get_analysis_summary()
	_analysis_skills = session.get_skills_by_weakness()
	_analysis_skill_index = 0
	
	question_label.text = "Based on your pretest results, here is your knowledge analysis:\n\n"
	question_label.visible = true
	_clear_options()
	
	# Build skill summary text
	var summary_text := ""
	for skill in _analysis_skills:
		var data: Dictionary = summary[skill]
		summary_text += "%s: %d/%d (%.1f%%) - Knowledge: %.1f%%\n" % [
			data["name"],
			data["correct"],
			data["total"],
			data["accuracy_percentage"],
			data["mastery_percentage"]
		]
	
	question_label.text += summary_text + "\n\nYour weakest skill is: %s\n\nClick Next to begin adaptive learning." % QuestionBank.get_skill_name(_analysis_skills[0])
	
	back_button.visible = true
	back_button.text = "Back"
	next_button.visible = true
	next_button.text = "Start Learning"

# ===== ADAPTIVE LEARNING =====

func _start_adaptive_learning() -> void:
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
	
	# Record observation in the knowledge tracer
	session.knowledge_tracer.record_observation(_learning_skill, correct)
	
	# Show feedback
	feedback_label.text = "Correct!" if correct else "Incorrect."
	feedback_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6, 1) if correct else Color(1, 0.5, 0.5, 1))
	feedback_label.text += "\n\n" + _current_challenge["explanation"]
	
	# Show next button
	next_button.visible = true
	next_button.text = "Next Challenge"
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
	
	# Check if there are more weak skills to learn
	_analysis_skill_index += 1
	if _analysis_skill_index < _analysis_skills.size():
		var next_skill: String = _analysis_skills[_analysis_skill_index]
		var next_knowledge: float = session.knowledge_tracer.get_mastery_percentage(next_skill)
		if next_knowledge < 70.0:
			question_label.text += "\n\nNext skill to learn: %s (%.1f%%)" % [QuestionBank.get_skill_name(next_skill), next_knowledge]
			next_button.text = "Learn Next Skill"
		else:
			question_label.text += "\n\nAll weak skills have been addressed."
			next_button.text = "Proceed to Post Test"
	else:
		question_label.text += "\n\nAll skills have been covered."
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
	title_label.text = "RESULTS"
	_clear_content()
	
	_results = session.get_posttest_results()
	session.save_session_data()
	
	var pretest: Dictionary = _results["pretest"]
	var posttest: Dictionary = _results["posttest"]
	
	var text := "Pretest Results:\n"
	text += "Score: %d/%d (%.1f%%)\n\n" % [pretest["correct"], pretest["total"], pretest["percentage"]]
	
	text += "Post Test Results:\n"
	text += "Score: %d/%d (%.1f%%)\n\n" % [posttest["correct"], posttest["total"], posttest["percentage"]]
	
	var improvement: float = posttest["percentage"] - pretest["percentage"]
	text += "Improvement: %+.1f%%\n\n" % improvement
	
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
			elif next_button.text == "Learn Next Skill":
				# Start learning the next weak skill
				_learning_skill = _analysis_skills[_analysis_skill_index]
				_challenge_index = 0
				_challenge_correct = 0
				_challenge_total = 0
				_challenge_answered = false
				_handholding = false
				session.start_adaptive_learning(_learning_skill)
				_show_learning_phase(0)
			else:
				_on_learning_next()
		SessionManager.SessionState.COMPLETE:
			_show_results()

# ===== UI HELPERS =====

func _clear_content() -> void:
	question_label.text = ""
	question_label.visible = false
	_clear_options()
	feedback_label.text = ""
	progress_label.text = ""

func _clear_options() -> void:
	for child in options_box.get_children():
		child.queue_free()

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

# ===== VR POINTER =====

func _update_pointer() -> void:
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