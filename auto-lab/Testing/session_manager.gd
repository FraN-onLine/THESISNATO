extends RefCounted
## Session Manager for the Testing Grounds.
## Orchestrates the full flow: Pretest → Analysis → Adaptive Learning → Post Test.

const QuestionBank = preload("res://Testing/Data/question_bank.gd")
const KnowledgeTracer = preload("res://Testing/Algorithms/knowledge_tracer.gd")
const ProfileManager = preload("res://Testing/profile_manager.gd")
const Gamification = preload("res://Testing/gamification.gd")

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
var current_question_answered := false
var pretest_answers: Array = []  # Array of {question_id, skill, correct, selected}
var posttest_answers: Array = []

# Adaptive learning data
var adaptive_learning_complete: bool = false

## Lesson checkpoints already fed to the models, so replaying one (scene reload,
## re-shown step) can never count as a second piece of evidence.
var _recorded_lesson_observations: Dictionary = {}

## The algorithm chosen BEFORE entering the Testing Grounds (HMM=0, BKT=1, KST=2).
var selected_algorithm: int = -1

## Gamification tracker (XP, streaks, badges, mastery stars) for the session.
var gamification: Gamification = null
var current_learning_skill: String = ""
var learning_phase: int = 0  # 0=objective, 1=definition, 2=example, 3=guided, 4=challenge, 5=feedback

# Whiteboard (automata builder) attempt analytics per skill.
# skill -> Array of {correct, attempts, wrong_attempts, connections_made, time_seconds}
var workshop_attempts: Dictionary = {}

func _init() -> void:
	profile_manager = ProfileManager.new()
	knowledge_tracer = KnowledgeTracer.new(KnowledgeTracer.AlgorithmType.HMM)
	gamification = Gamification.new()

## Set the algorithm type (HMM, BKT, or KST)
func set_algorithm_type(algo_type: int) -> void:
	knowledge_tracer.set_algorithm_type(algo_type)
	selected_algorithm = algo_type

## Display name of the chosen algorithm (for menus / stats boards).
func get_algorithm_label() -> String:
	return knowledge_tracer.get_algorithm_name() if knowledge_tracer else "HMM"

func get_algorithm_callout() -> String:
	return knowledge_tracer.get_algorithm_callout() if knowledge_tracer else "HMM"

## Start a new session
func start_session() -> void:
	state = SessionState.PROFILE_SETUP
	pretest_answers.clear()
	posttest_answers.clear()
	posttest_questions.clear()
	current_question_index = 0
	current_question_answered = false
	current_question = {}
	adaptive_learning_complete = false
	current_learning_skill = ""
	learning_phase = 0
	workshop_attempts.clear()
	_recorded_lesson_observations.clear()
	# A new session must re-seed the models from ITS OWN pretest, otherwise the
	# previous learner's priors keep driving the estimates (old bug: the priors
	# were only ever applied once per process).
	reset_analysis_priors()

## Start the World-scene learning demo without collecting a real pretest.
## The seeded answers create believable, varied HMM priors for UI/testing.
func start_learning_demo() -> void:
	state = SessionState.ANALYSIS
	selected_algorithm = KnowledgeTracer.AlgorithmType.HMM
	knowledge_tracer = KnowledgeTracer.new(KnowledgeTracer.AlgorithmType.HMM)
	pretest_answers.clear()
	posttest_answers.clear()
	pretest_questions = QuestionBank.QUESTIONS.duplicate(true)
	posttest_questions.clear()
	current_question_index = 0
	current_question_answered = false
	current_question = {}
	adaptive_learning_complete = false
	current_learning_skill = ""
	learning_phase = 0
	workshop_attempts.clear()
	_recorded_lesson_observations.clear()
	reset_analysis_priors()

	var dummy_correct := {
		"simulation": 4,
		"identification": 2,
		"definition": 3,
		"building": 1,
		"set_builder": 2,
		"list": 4,
	}
	for skill in knowledge_tracer.SKILL_ORDER:
		for index in range(5):
			pretest_answers.append({
				"skill": skill,
				"correct": index < int(dummy_correct[skill]),
			})
	knowledge_tracer.apply_pretest_priors(pretest_answers)
	_priors_applied = true

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
	current_question_answered = false
	pretest_answers.clear()
	# The official pretest is exactly the 15 multiple-choice items in fixed order.
	pretest_questions = QuestionBank.QUESTIONS.duplicate(true)
	_current_question()

## Get the current question
func get_current_question() -> Dictionary:
	return current_question

## Get the current question index (1-based)
func get_current_question_number() -> int:
	return current_question_index + 1

## Get the total number of questions
func get_total_questions() -> int:
	var questions := _active_questions()
	if questions.is_empty():
		questions = pretest_questions if not pretest_questions.is_empty() else posttest_questions
	return questions.size()

## Submit an answer for the current question.
##
## PRETEST INTEGRITY: the selection is FINAL for the item it was made on. The
## answer is recorded immediately and the item locks, but the index does NOT
## advance here - the learner advances with advance_question(). That way a stray
## second tap can never be attributed to the following question, and no answer
## key or explanation is revealed while the item is on screen.
func submit_answer(selected_index: int) -> Dictionary:
	if current_question_answered or current_question.is_empty():
		return {"accepted": false, "complete": false, "correct": false}
	current_question_answered = true
	var question: Dictionary = current_question
	var correct: bool = selected_index == question["correct"]
	var skills: Array = QuestionBank.get_question_skills(question)
	var skill: String = str(skills[0]) if not skills.is_empty() else "definition"
	var answer := {
		"question_id": question["id"],
		"skill": skill,
		"skills": skills,
		"correct": correct,
		"selected": selected_index,
		"correct_index": question["correct"],
		"question": question["question"],
		"options": question["options"],
		"explanation": question["explanation"]
	}
	return _record_answer(answer, correct, skills)

## Submit the result of a hands-on (board-built) question. `correct` comes from
## the automata board evaluation of the built DFA, not from choosing an option.
func submit_hands_on(correct: bool, board_message: String) -> Dictionary:
	if current_question_answered or current_question.is_empty():
		return {"accepted": false, "complete": false, "correct": false}
	current_question_answered = true
	var question: Dictionary = current_question
	var skills: Array = QuestionBank.get_question_skills(question)
	var skill: String = str(skills[0]) if not skills.is_empty() else "definition"
	var answer := {
		"question_id": question["id"],
		"skill": skill,
		"skills": skills,
		"correct": correct,
		"selected": -1,
		"correct_index": -1,
		"question": question["question"],
		"options": [],
		"explanation": question.get("explanation", ""),
		"type": "handson",
		"board_message": board_message,
	}
	return _record_answer(answer, correct, skills)

## True while the current item has been answered but not yet left behind.
func is_awaiting_advance() -> bool:
	return current_question_answered and not current_question.is_empty()

## Move to the next question (called when the learner presses Next). Returns
## {"complete": true} when the whole test is finished.
func advance_question() -> Dictionary:
	if not current_question_answered:
		return {"accepted": false, "complete": false, "correct": false, "skill": ""}
	current_question_index += 1
	var questions: Array = _active_questions()
	if current_question_index >= questions.size():
		if state == SessionState.PRETEST:
			state = SessionState.ANALYSIS
		elif state == SessionState.POST_TEST:
			state = SessionState.COMPLETE
		current_question = {}
		current_question_answered = false
		return {"accepted": true, "complete": true, "correct": false, "skill": ""}
	_current_question()
	return {"accepted": true, "complete": false, "correct": false, "skill": ""}

## The question list the current phase walks through.
func _active_questions() -> Array:
	if state == SessionState.POST_TEST:
		return posttest_questions
	return pretest_questions

## Record the answer, feed the tracer, save. Advancing is a separate step so the
## item stays on screen (and locked) until the learner chooses to move on.
func _record_answer(answer: Dictionary, correct: bool, skills: Array) -> Dictionary:
	var primary: String = str(skills[0]) if not skills.is_empty() else "definition"
	if state == SessionState.PRETEST or state == SessionState.POST_TEST:
		if state == SessionState.PRETEST:
			pretest_answers.append(answer)
			knowledge_tracer.set_state_hint("pretest")
		else:
			posttest_answers.append(answer)
			knowledge_tracer.set_state_hint("posttest")
		# Keep the tracer's per-phase counters in sync with what was recorded.
		for tagged_skill in skills:
			knowledge_tracer.record_observation(tagged_skill, correct)
		save_session_data()
	var questions: Array = _active_questions()
	return {
		"accepted": true,
		"complete": current_question_index + 1 >= questions.size(),
		"correct": correct,
		"skill": primary,
	}

## True when the current question is a hands-on board task (needs the automata
## board built and submitted), as opposed to a multiple-choice question.
func current_question_is_handson() -> bool:
	return current_question.get("type", "mc") == "handson"

## Returns the board task dict ({instruction, accept, reject}) for a hands-on
## question, or an empty Dictionary when not applicable.
func get_current_hands_on_task() -> Dictionary:
	if not current_question_is_handson():
		return {}
	return current_question.get("task", {})
## Get the current question's correct answer index
func get_correct_answer_index() -> int:
	return current_question.get("correct", -1)

## Get the analysis summary after pretest
## Pretest-derived priors are applied once, when the analysis is first built.
var _priors_applied: bool = false

func get_analysis_summary() -> Dictionary:
	if not _priors_applied:
		_priors_applied = true
		# The pretest IS the starting estimate: BKT P(L0), HMM Pi, KST state.
		knowledge_tracer.apply_pretest_priors(pretest_answers)
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
	# Keep pretest evidence in the model, but start a fresh mastery evidence window.
	knowledge_tracer.begin_learning(skill)

# ===== Adaptive learning helpers ==========================================

## Skills to visit in this learner's weakness order, SKIPPING the ones already
## mastered. The old flow re-taught mastered skills, which wasted the learner's
## time and diluted the evidence for the skills that actually needed work.
func learning_plan() -> Array:
	var order: Array = knowledge_tracer.get_skills_by_weakness()
	var plan: Array = []
	for skill in order:
		if not knowledge_tracer.is_learned(str(skill)):
			plan.append(str(skill))
	if plan.is_empty():
		plan = order.duplicate()
	return plan

## Skill to teach at `index` of a plan, or "" when the plan is exhausted.
func plan_skill_at(plan: Array, index: int) -> String:
	if index < 0 or index >= plan.size():
		return ""
	return str(plan[index])

## Record exactly ONE adaptive observation per lesson checkpoint. `source_id`
## makes the call idempotent: re-showing the same graded checkpoint (after a
## remedy panel, a scene reload or a stray double event) cannot inflate the
## evidence and push a skill to "mastered" by accident.
func record_learning_result(skill: String, correct: bool, source_id := "") -> bool:
	if skill == "" or not knowledge_tracer.SKILL_ORDER.has(skill):
		return false
	if source_id != "":
		if _recorded_lesson_observations.has(source_id):
			return false
		_recorded_lesson_observations[source_id] = true
	knowledge_tracer.record_learning_observation(skill, correct)
	if gamification != null:
		gamification.set_mastery(skill, knowledge_tracer.get_mastery_percentage(skill))
	return true

## True when a lesson observation with this id was already recorded.
func has_recorded(source_id: String) -> bool:
	return _recorded_lesson_observations.has(source_id)

## Called once the adaptive phase has visited every skill in the plan.
func finish_adaptive_learning() -> void:
	adaptive_learning_complete = true
	if gamification != null:
		for skill in knowledge_tracer.SKILL_ORDER:
			gamification.set_mastery(skill, knowledge_tracer.get_mastery_percentage(skill))
	save_session_data()

## Let the pretest priors be applied again (new session, or a retaken pretest).
func reset_analysis_priors() -> void:
	_priors_applied = false

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

## Record one whiteboard (automata builder) attempt. `stats` comes from the
## builder's get_attempt_stats(): attempts, wrong_attempts, connections_made,
## time_seconds. This richer evidence (failed tries, rework, time on task) is
## stored per skill so the knowledge-tracing algorithms can use it later.
func record_workshop_attempt(skill: String, correct: bool, stats: Dictionary) -> void:
	if not workshop_attempts.has(skill):
		workshop_attempts[skill] = []
	workshop_attempts[skill].append({
		"correct": correct,
		"attempts": stats.get("attempts", 0),
		"wrong_attempts": stats.get("wrong_attempts", 0),
		"connections_made": stats.get("connections_made", 0),
		"time_seconds": stats.get("time_seconds", 0.0),
	})
	save_session_data()

## Get the recorded whiteboard analytics per skill.
func get_workshop_attempts() -> Dictionary:
	return workshop_attempts.duplicate(true)

## Start the post test
func start_posttest() -> void:
	state = SessionState.POST_TEST
	current_question_index = 0
	current_question_answered = false
	posttest_answers.clear()
	# Same 15 pretest items for comparison PLUS 5 hands-on DFA builds.
	posttest_questions = pretest_questions.duplicate() + QuestionBank.POSTTEST_QUESTIONS
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
	var questions: Array = pretest_questions if state == SessionState.PRETEST else posttest_questions
	if current_question_index < questions.size():
		current_question = questions[current_question_index]
		current_question_answered = false
	else:
		current_question = {}

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
		"workshop_attempts": workshop_attempts,
		"selected_algorithm": selected_algorithm,
		"gamification": gamification.to_dict() if gamification else {},
		"timestamp": Time.get_datetime_string_from_system()
	}
	
	var file := FileAccess.open("user://session_data.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
	_write_json("user://pretest_data.json", {"profile": profile_manager.get_profile(), "answers": pretest_answers})
	_write_json("user://posttest_data.json", {"profile": profile_manager.get_profile(), "answers": posttest_answers})

func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()

## Write a simple portable PDF report after the post-test is complete.
func generate_profile_pdf() -> String:
	var profile: Dictionary = profile_manager.get_profile()
	var pretest := _calculate_test_results(pretest_answers)
	var posttest := _calculate_test_results(posttest_answers)
	var lines: Array[String] = [
		"AUTOLAB PROFILE REPORT",
		"Name: %s" % profile.get("name", ""),
		"Gender: %s" % profile.get("gender", ""),
		"Age: %s" % profile.get("age", ""),
		"Familiar with automata: %s" % ("Yes" if profile.get("familiar_with_automata", false) else "No"),
		"",
		"Pretest: %d/%d (%.1f%%)" % [pretest["correct"], pretest["total"], pretest["percentage"]],
		"Post-test: %d/%d (%.1f%%)" % [posttest["correct"], posttest["total"], posttest["percentage"]],
		"",
		"Skill summary:"
	]
	for skill in knowledge_tracer.SKILL_ORDER:
		var stats: Dictionary = knowledge_tracer.get_skill_stats(skill)
		var accuracy := float(stats["correct"]) / float(stats["total"]) * 100.0 if stats["total"] > 0 else 0.0
		lines.append("%s: %d/%d (%.1f%%)" % [QuestionBank.get_skill_name(skill), stats["correct"], stats["total"], accuracy])

	var content := "BT\n/F1 12 Tf\n50 760 Td\n"
	for index in range(lines.size()):
		var escaped := lines[index].replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
		content += "(%s) Tj\n0 -18 Td\n" % escaped
	content += "ET\n"
	var objects: Array[String] = [
		"<< /Type /Catalog /Pages 2 0 R >>",
		"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
		"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
		"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
		"<< /Length %d >>\nstream\n%sendstream" % [content.length(), content]
	]
	var pdf := "%PDF-1.4\n"
	var offsets: Array[int] = [0]
	for index in range(objects.size()):
		offsets.append(pdf.to_utf8_buffer().size())
		pdf += "%d 0 obj\n%s\nendobj\n" % [index + 1, objects[index]]
	var xref_offset := pdf.to_utf8_buffer().size()
	pdf += "xref\n0 %d\n0000000000 65535 f \n" % (objects.size() + 1)
	for offset in offsets.slice(1):
		pdf += "%010d 00000 n \n" % offset
	pdf += "trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF" % [objects.size() + 1, xref_offset]
	var path := "user://profile_data.pdf"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_buffer(pdf.to_utf8_buffer())
		file.close()
	return path

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
	if data.has("workshop_attempts") and data["workshop_attempts"] is Dictionary:
		workshop_attempts = data["workshop_attempts"]
	if data.has("selected_algorithm"):
		selected_algorithm = int(data["selected_algorithm"])
		if selected_algorithm >= 0:
			knowledge_tracer.set_algorithm_type(selected_algorithm)
	if data.has("gamification") and gamification:
		gamification.from_dict(data["gamification"])
	
	return true
