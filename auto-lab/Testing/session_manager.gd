extends RefCounted
## Session Manager for the Testing Grounds.
## Orchestrates the full flow: Pretest → Analysis → Adaptive Learning → Post Test.

const QuestionBank = preload("res://Testing/Data/question_bank.gd")
const KnowledgeTracer = preload("res://Testing/Algorithms/knowledge_tracer.gd")
const ProfileManager = preload("res://Testing/profile_manager.gd")

# Session states
enum SessionState {
	PROFILE_SETUP,
	PRETEST,
	ANALYSIS,
	ADAPTIVE_LEARNING,
	POST_TEST,
	COMPLETE
}

# Current state
var state: int = SessionState.PROFILE_SETUP

# Managers
var profile_manager: ProfileManager
var knowledge_tracer: KnowledgeTracer

# Test data
var pretest_questions: Array = []
var posttest_questions: Array = []
var current_question_index: int = 0
var current_question: Dictionary = {}
var pretest_answers: Array = []  # Array of {question_id, skill, correct, selected}
var posttest_answers: Array = []

# Adaptive learning data
var adaptive_learning_complete: bool = false
var current_learning_skill: String = ""
var learning_phase: int = 0  # 0=objective, 1=definition, 2=example, 3=guided, 4=challenge, 5=feedback

func _init() -> void:
	profile_manager = ProfileManager.new()
	knowledge_tracer = KnowledgeTracer.new(KnowledgeTracer.AlgorithmType.HMM)

## Set the algorithm type (HMM, BKT, or DKT)
func set_algorithm_type(algo_type: int) -> void:
	knowledge_tracer.set_algorithm_type(algo_type)

## Start a new session
func start_session() -> void:
	state = SessionState.PROFILE_SETUP
	pretest_answers.clear()
	posttest_answers.clear()
	current_question_index = 0
	adaptive_learning_complete = false

## Check if profile setup is needed
func needs_profile_setup() -> bool:
	return not profile_manager.has_profile()

## Save the profile
func save_profile(name: String, gender: String, age: int, familiar: bool) -> void:
	profile_manager.create_profile(name, gender, age, familiar)

## Start the pretest
func start_pretest() -> void:
	state = SessionState.PRETEST
	current_question_index = 0
	pretest_answers.clear()
	pretest_questions = _shuffle_questions(QuestionBank.QUESTIONS)
	_current_question()

## Get the current question
func get_current_question() -> Dictionary:
	return current_question

## Get the current question index (1-based)
func get_current_question_number() -> int:
	return current_question_index + 1

## Get the total number of questions
func get_total_questions() -> int:
	return pretest_questions.size()

## Submit an answer for the current question
func submit_answer(selected_index: int) -> Dictionary:
	var question: Dictionary = current_question
	var correct: bool = selected_index == question["correct"]
	var skill: String = question["skill"]
	
	var answer := {
		"question_id": question["id"],
		"skill": skill,
		"correct": correct,
		"selected": selected_index,
		"correct_index": question["correct"],
		"question": question["question"],
		"options": question["options"],
		"explanation": question["explanation"]
	}
	
	if state == SessionState.PRETEST:
		pretest_answers.append(answer)
		# Record observation in the knowledge tracer
		knowledge_tracer.record_observation(skill, correct)
	elif state == SessionState.POST_TEST:
		posttest_answers.append(answer)
		knowledge_tracer.record_observation(skill, correct)
	
	# Advance to next question
	current_question_index += 1
	
	if current_question_index >= pretest_questions.size():
		# Test is complete
		if state == SessionState.PRETEST:
			state = SessionState.ANALYSIS
		elif state == SessionState.POST_TEST:
			state = SessionState.COMPLETE
		return {"complete": true, "correct": correct, "skill": skill}
	
	_current_question()
	return {"complete": false, "correct": correct, "skill": skill}

## Get the current question's correct answer index
func get_correct_answer_index() -> int:
	return current_question.get("correct", -1)

## Get the analysis summary after pretest
func get_analysis_summary() -> Dictionary:
	return knowledge_tracer.get_full_summary()

## Get the weakest skill (for adaptive learning focus)
func get_weakest_skill() -> String:
	return knowledge_tracer.get_weakest_skill()

## Get skills sorted by weakness
func get_skills_by_weakness() -> Array:
	return knowledge_tracer.get_skills_by_weakness()

## Start adaptive learning for a specific skill
func start_adaptive_learning(skill: String) -> void:
	state = SessionState.ADAPTIVE_LEARNING
	current_learning_skill = skill
	learning_phase = 0

## Get the current learning phase
func get_learning_phase() -> int:
	return learning_phase

## Advance to the next learning phase
func advance_learning_phase() -> void:
	learning_phase += 1

## Check if adaptive learning is complete for the current skill
func is_skill_learned(skill: String) -> bool:
	return knowledge_tracer.is_learned(skill)

## Complete adaptive learning
func complete_adaptive_learning() -> void:
	adaptive_learning_complete = true

## Start the post test
func start_posttest() -> void:
	state = SessionState.POST_TEST
	current_question_index = 0
	posttest_answers.clear()
	# Use the same questions as the pretest for comparison
	posttest_questions = pretest_questions.duplicate()
	_current_question()

## Get the post test results
func get_posttest_results() -> Dictionary:
	var results := {
		"pretest": _calculate_test_results(pretest_answers),
		"posttest": _calculate_test_results(posttest_answers),
		"knowledge_summary": knowledge_tracer.get_full_summary()
	}
	return results

## Calculate test results from answers
func _calculate_test_results(answers: Array) -> Dictionary:
	var total := answers.size()
	var correct := 0
	var skill_results := {}
	
	for answer in answers:
		if answer["correct"]:
			correct += 1
		
		var skill: String = answer["skill"]
		if not skill_results.has(skill):
			skill_results[skill] = {"correct": 0, "total": 0}
		skill_results[skill]["total"] += 1
		if answer["correct"]:
			skill_results[skill]["correct"] += 1
	
	var percentage := 0.0
	if total > 0:
		percentage = float(correct) / float(total) * 100.0
	
	# Calculate per-skill percentages
	for skill in skill_results:
		var stats: Dictionary = skill_results[skill]
		stats["percentage"] = float(stats["correct"]) / float(stats["total"]) * 100.0 if stats["total"] > 0 else 0.0
	
	return {
		"total": total,
		"correct": correct,
		"percentage": percentage,
		"skill_results": skill_results
	}

## Get the current question
func _current_question() -> void:
	if current_question_index < pretest_questions.size():
		current_question = pretest_questions[current_question_index]

## Shuffle questions
func _shuffle_questions(questions: Array) -> Array:
	var shuffled := questions.duplicate()
	# Fisher-Yates shuffle
	for i in range(shuffled.size() - 1, 0, -1):
		var j := randi() % (i + 1)
		var temp = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = temp
	return shuffled

## Save session data to JSON
func save_session_data() -> void:
	var data := {
		"profile": profile_manager.get_profile(),
		"pretest_answers": pretest_answers,
		"posttest_answers": posttest_answers,
		"knowledge_tracer": knowledge_tracer.to_dict(),
		"adaptive_learning_complete": adaptive_learning_complete,
		"timestamp": Time.get_datetime_string_from_system()
	}
	
	var file := FileAccess.open("user://session_data.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()

## Load session data from JSON
func load_session_data() -> bool:
	if not FileAccess.file_exists("user://session_data.json"):
		return false
	
	var file := FileAccess.open("user://session_data.json", FileAccess.READ)
	if not file:
		return false
	
	var text := file.get_as_text()
	file.close()
	
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK or not (json.data is Dictionary):
		return false
	
	var data: Dictionary = json.data
	if data.has("pretest_answers"):
		pretest_answers = data["pretest_answers"]
	if data.has("posttest_answers"):
		posttest_answers = data["posttest_answers"]
	if data.has("knowledge_tracer"):
		knowledge_tracer.from_dict(data["knowledge_tracer"])
	if data.has("adaptive_learning_complete"):
		adaptive_learning_complete = data["adaptive_learning_complete"]
	
	return true