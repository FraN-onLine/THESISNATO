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

# ===== Comparative-study timing & metrics =================================
## Wall-clock timing for the adaptive-learning phase: set when the first skill
## starts being taught and frozen the moment the algorithm deems the learner
## knowledgeable enough for the post test. (Adaptive Learning Completion Time)
var adaptive_start_msec: int = 0
var adaptive_end_msec: int = 0
## Whole-session stopwatch: starts when this session object comes into existence
## (the learner entering the Testing Grounds, or an explicit reset_session()) and
## freezes when the post test is completed. This is the headline "start to
## finish" number; the adaptive and post-test clocks below are phases inside it.
var session_start_msec: int = 0
var session_end_msec: int = 0
## Pretest phase window — the only phase not otherwise timed, so with the two
## clocks below the total can be accounted for phase by phase.
var pretest_start_msec: int = 0
var pretest_end_msec: int = 0
## Post-test stopwatch, mirrored by CountingTimerOverlay. These two fields are
## the single source of truth; the overlay only renders them.
var timer_started: float = 0.0
var timer_raw_seconds: float = 0.0
## True once this completed session has been written into its own results folder,
## so repeated save_session_data() calls cannot duplicate it.
var _student_results_saved: bool = false
## Path of the session record written this run (for display).
var _student_results_path: String = ""
## Same idempotency guard, for the per-run algorithm-performance summary.
var _algorithm_summary_saved: bool = false
var _algorithm_summary_path: String = ""
## The model's learned / not-learned verdict per skill, snapshotted the instant
## adaptive learning ends (BEFORE any post-test answer can move the beliefs).
## Compared against the real post-test results for Knowledge State Accuracy.
var predicted_knowledge_state: Dictionary = {}

func _init() -> void:
	profile_manager = ProfileManager.new()
	knowledge_tracer = KnowledgeTracer.new(KnowledgeTracer.AlgorithmType.HMM)
	gamification = Gamification.new()
	_start_session_clock()

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
	_reset_study_timing()
	_start_session_clock()
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
	if pretest_start_msec == 0:
		pretest_start_msec = Time.get_ticks_msec()
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
			_close_pretest_window()
		elif state == SessionState.POST_TEST:
			state = SessionState.COMPLETE
			stop_posttest_timer()
			_close_session_window()
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
	# First skill of the run starts the Adaptive-Learning-Completion-Time clock.
	if adaptive_start_msec == 0:
		adaptive_start_msec = Time.get_ticks_msec()
	# Keep pretest evidence in the model, but start a fresh mastery evidence window.
	knowledge_tracer.begin_learning(skill)

# ===== Adaptive learning helpers ==========================================

## Skills to visit in this learner's weakness order, SKIPPING the ones already
## mastered. The old flow re-taught mastered skills, which wasted the learner's
## time and diluted the evidence for the skills that actually needed work.
## An EMPTY result means every topic is accepted: the caller must then end the
## pass rather than fall back to the full order and repeat it all.
func learning_plan() -> Array:
	var plan: Array = []
	for skill in knowledge_tracer.get_skills_by_weakness():
		if not knowledge_tracer.is_learned(str(skill)):
			plan.append(str(skill))
	return plan

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
	_close_adaptive_window()
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
		"skipped": bool(stats.get("skipped", false)),
		"attempts": stats.get("attempts", 0),
		"wrong_attempts": stats.get("wrong_attempts", 0),
		"connections_made": stats.get("connections_made", 0),
		"time_seconds": stats.get("time_seconds", 0.0),
	})
	save_session_data()

## Record a SKIPPED whiteboard task. Skipping is a deliberate "I cannot build this
## machine" signal: it is NOT an answer (so it never counts as a question), and the
## active knowledge-tracing model is penalised in proportion to how much of the
## skill is still UNKNOWN - a heavy drop at low mastery, almost nothing once the
## skill is nearly mastered (see KnowledgeTracer.apply_skip_penalty).
## Returns the penalty that was applied: {skill, before, after, drop}.
func record_workshop_skip(skill: String, stats: Dictionary) -> Dictionary:
	if skill == "" or not knowledge_tracer.SKILL_ORDER.has(skill):
		return {}
	if not workshop_attempts.has(skill):
		workshop_attempts[skill] = []
	workshop_attempts[skill].append({
		"correct": false,
		"skipped": true,
		"attempts": stats.get("attempts", 0),
		"wrong_attempts": stats.get("wrong_attempts", 0),
		"connections_made": stats.get("connections_made", 0),
		"time_seconds": stats.get("time_seconds", 0.0),
	})
	var penalty: Dictionary = knowledge_tracer.apply_skip_penalty(skill)
	if gamification != null:
		gamification.set_mastery(skill, knowledge_tracer.get_mastery_percentage(skill))
	save_session_data()
	return penalty

## Get the recorded whiteboard analytics per skill.
func get_workshop_attempts() -> Dictionary:
	return workshop_attempts.duplicate(true)

## Start the post test
func start_posttest() -> void:
	state = SessionState.POST_TEST
	# The post test is the algorithm's verdict that the learner IS knowledgeable:
	# freeze the adaptive clock (if still running), snapshot the model's
	# knowledge state, and start the post-test stopwatch.
	_close_pretest_window()
	_close_adaptive_window()
	if timer_started <= 0.0:
		timer_started = Time.get_unix_time_from_system()
		timer_raw_seconds = 0.0
	current_question_index = 0
	current_question_answered = false
	posttest_answers.clear()
	# Same 15 pretest items for comparison PLUS 2 hands-on DFA builds.
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

# ===== Comparative-study metrics & per-student storage ====================

## A skill counts as "actually known" on the post test at or above this
## percentage — the independent bar used to check the model's end-of-learning
## verdict against real behaviour (Knowledge State Accuracy). It is deliberately
## NOT the mastery gate: the gate decides when teaching stops, this one decides
## whether that decision turned out to be right.
const KNOWLEDGE_CONFIRM_THRESHOLD := 70.0

## Reset every study clock / snapshot for a brand-new learner.
func _reset_study_timing() -> void:
	adaptive_start_msec = 0
	adaptive_end_msec = 0
	session_start_msec = 0
	session_end_msec = 0
	pretest_start_msec = 0
	pretest_end_msec = 0
	timer_started = 0.0
	timer_raw_seconds = 0.0
	predicted_knowledge_state = {}
	_student_results_saved = false
	_student_results_path = ""
	_algorithm_summary_saved = false
	_algorithm_summary_path = ""
	# A new learner gets a NEW run folder: reusing the cached one would file two
	# different runs under the same algorithm/student/second name.
	_run_results_dir = ""
	_results_indexed = false

## Stop the post-test stopwatch and freeze its value.
func stop_posttest_timer() -> void:
	if timer_started > 0.0:
		timer_raw_seconds = Time.get_unix_time_from_system() - timer_started
		timer_started = 0.0

## Re-enter a paused post test: keep the seconds already spent and keep
## counting from there (no time is lost or double-counted).
func resume_posttest_timer() -> void:
	if timer_started <= 0.0:
		timer_started = Time.get_unix_time_from_system() - timer_raw_seconds

## Seconds the post-test stopwatch is currently showing (live while running).
func get_posttest_seconds() -> float:
	if timer_started > 0.0:
		return Time.get_unix_time_from_system() - timer_started
	return timer_raw_seconds

## Freeze the adaptive-learning clock and snapshot the model's learned /
## not-learned verdict per skill exactly as it stood at the END of learning.
## Idempotent: the first close wins, so post-test answers can never rewrite
## the prediction that Knowledge State Accuracy is measured against.
func _close_adaptive_window() -> void:
	if adaptive_end_msec == 0:
		adaptive_end_msec = Time.get_ticks_msec()
	if predicted_knowledge_state.is_empty():
		for skill in knowledge_tracer.SKILL_ORDER:
			predicted_knowledge_state[str(skill)] = knowledge_tracer.is_learned(str(skill))

## Seconds from the first skill taught until the algorithm declared mastery
## (0.0 when no adaptive learning happened this session).
func get_adaptive_completion_seconds() -> float:
	if adaptive_start_msec <= 0:
		return 0.0
	var end_msec := adaptive_end_msec if adaptive_end_msec > 0 else Time.get_ticks_msec()
	return float(end_msec - adaptive_start_msec) / 1000.0

## Start the whole-session clock. Idempotent, so the first start wins and no
## later phase can reset the total.
func _start_session_clock() -> void:
	if session_start_msec == 0:
		session_start_msec = Time.get_ticks_msec()

## Freeze the total at post-test completion. Idempotent, so re-entering the
## results screen cannot stretch the recorded duration.
func _close_session_window() -> void:
	if session_end_msec == 0 and session_start_msec > 0:
		session_end_msec = Time.get_ticks_msec()

func _close_pretest_window() -> void:
	if pretest_end_msec == 0 and pretest_start_msec > 0:
		pretest_end_msec = Time.get_ticks_msec()

## TOTAL time from entering the system until the post test was completed
## (live while the run is still in progress).
func get_total_session_seconds() -> float:
	if session_start_msec <= 0:
		return 0.0
	var end_msec := session_end_msec if session_end_msec > 0 else Time.get_ticks_msec()
	return float(end_msec - session_start_msec) / 1000.0

## Seconds spent inside the pretest itself.
func get_pretest_seconds() -> float:
	if pretest_start_msec <= 0:
		return 0.0
	var end_msec := pretest_end_msec if pretest_end_msec > 0 else Time.get_ticks_msec()
	return float(end_msec - pretest_start_msec) / 1000.0

## "M:SS" rendering of a duration, for the results screen and the PDF report.
static func format_duration(seconds: float) -> String:
	var total := int(round(seconds))
	return "%d:%02d" % [int(total / 60.0), total % 60]

## The numbers a completed session contributes to the comparative study:
##   average_pretest_score         mean % across the pretest items
##   average_posttest_score        mean % across the post-test items
##   performance_improvement_rate  relative gain over the pretest baseline (%)
##   predictive_accuracy           hit-rate of the algorithm actually used (%)
##   adaptive_learning_seconds     start of learning -> algorithm says mastered
##   knowledge_state_accuracy      end-of-learning snapshot vs real post test (%)
##   total_session_seconds         entering the system -> post test completed
##   pretest_seconds / posttest_seconds  the two remaining phases of that total
func get_study_metrics() -> Dictionary:
	var pretest := _calculate_test_results(pretest_answers)
	var posttest := _calculate_test_results(posttest_answers)
	var avg_pre: float = pretest["percentage"]
	var avg_post: float = posttest["percentage"]

	# Performance Improvement Rate: relative gain over the pretest baseline.
	var improvement_rate := 0.0
	if avg_pre > 0.0:
		improvement_rate = (avg_post - avg_pre) / avg_pre * 100.0
	elif avg_post > 0.0:
		improvement_rate = 100.0

	# Predictive Accuracy of the algorithm actually used this session.
	var algo_key := "HMM"
	match selected_algorithm:
		KnowledgeTracer.AlgorithmType.BKT:
			algo_key = "BKT"
		KnowledgeTracer.AlgorithmType.KST:
			algo_key = "KST"
	var comparison: Dictionary = knowledge_tracer.get_algorithm_comparison()
	var predictive_accuracy := 0.0
	if comparison.has(algo_key):
		predictive_accuracy = float(comparison[algo_key].get("accuracy", 0.0))

	var ksa := _knowledge_state_accuracy(posttest)
	return {
		"average_pretest_score": avg_pre,
		"average_posttest_score": avg_post,
		"performance_improvement_rate": improvement_rate,
		"predictive_accuracy": predictive_accuracy,
		"predictive_accuracy_algorithm": algo_key,
		"adaptive_learning_seconds": get_adaptive_completion_seconds(),
		"knowledge_state_accuracy": ksa["accuracy"],
		"knowledge_state_detail": ksa,
		"total_session_seconds": get_total_session_seconds(),
		"pretest_seconds": get_pretest_seconds(),
		"posttest_seconds": get_posttest_seconds(),
	}

## Knowledge State Accuracy: was the learner ACTUALLY knowledgeable when the
## algorithm stopped teaching? Compares the end-of-learning snapshot against
## the real post-test result for every skill, skill by skill.
func _knowledge_state_accuracy(posttest: Dictionary) -> Dictionary:
	var per_skill := {}
	var matches := 0
	var compared := 0
	var skill_results: Dictionary = posttest["skill_results"]
	for skill in knowledge_tracer.SKILL_ORDER:
		var s := str(skill)
		if not skill_results.has(s):
			continue  # Skill never reached the post test - nothing to verify.
		var predicted: bool = bool(predicted_knowledge_state.get(s, false))
		var actual_pct: float = float(skill_results[s]["percentage"])
		var actually_known: bool = actual_pct >= KNOWLEDGE_CONFIRM_THRESHOLD
		compared += 1
		if predicted == actually_known:
			matches += 1
		per_skill[s] = {
			"predicted_learned": predicted,
			"posttest_percentage": actual_pct,
			"actually_known": actually_known,
			"match": predicted == actually_known,
		}
	var accuracy := float(matches) / float(compared) * 100.0 if compared > 0 else 0.0
	return {"accuracy": accuracy, "matches": matches, "compared": compared, "per_skill": per_skill}

# ===== Per-run results folders ==============================================

## Root that holds every recorded run.
const RESULTS_ROOT := "user://results"
## Cross-run index: one entry per completed run, so the study can group runs by
## algorithm / learner / input mode without opening a single folder.
const RESULTS_INDEX := "user://results/index.json"
## The files written inside a run folder: the full session record, the algorithm
## comparison, and the printable profile report.
const SESSION_FILE := "session.json"
const SUMMARY_FILE := "algorithm_summary.json"
const REPORT_FILE := "profile_report.pdf"

## Folder this run writes into, cached on first use so every file of one session
## lands in the same place even when the clock ticks over between saves.
var _run_results_dir := ""
## Set once this run has its entry in RESULTS_INDEX.
var _results_indexed := false

## Filesystem-safe version of a label: letters, digits, - and _ survive, every
## other character collapses into a single underscore.
func _safe_name(value: String, fallback: String) -> String:
	var safe := ""
	for i in range(value.length()):
		var c := value[i]
		if "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_".contains(c):
			safe += c
		elif not safe.ends_with("_"):
			safe += "_"
	safe = safe.strip_edges()
	if safe == "" or safe == "_":
		return fallback
	return safe

## The learner's display name, or "student" when the profile was never filled in.
func _student_name() -> String:
	var profile: Dictionary = profile_manager.get_profile()
	var student_name := str(profile.get("name", "")).strip_edges()
	return student_name if student_name != "" else "student"

## "VR" or "PC". Resolved through the scene tree at RUNTIME: InputMode is an
## autoload, and naming it directly here would break the headless test runs that
## load this script before the autoloads exist.
func _input_mode_label() -> String:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var manager: Node = (loop as SceneTree).root.get_node_or_null("InputMode")
		if manager != null and manager.has_method("is_vr"):
			return "VR" if manager.call("is_vr") else "PC"
	return "PC"

## Every rule that decided whether THIS learner counted as knowledgeable, quoted
## into the record and onto the results screen. The folder name says which
## algorithm ran; this says under which criteria it ran, so a run can be re-read
## later without trusting memory.
func get_run_criteria() -> Dictionary:
	var learned_at_gate := 0
	for skill in predicted_knowledge_state:
		if bool(predicted_knowledge_state[skill]):
			learned_at_gate += 1
	return {
		"algorithm": get_algorithm_label(),
		"algorithm_callout": get_algorithm_callout(),
		"algorithm_id": selected_algorithm,
		"input_mode": _input_mode_label(),
		"mastery_threshold": KnowledgeTracer.MASTERY_THRESHOLD,
		"min_evidence": KnowledgeTracer.MIN_EVIDENCE,
		"recent_window": KnowledgeTracer.RECENT_WINDOW,
		"mastery_gate_skills": KnowledgeTracer.MASTERY_GATE_SKILLS,
		"skills_total": KnowledgeTracer.SKILL_ORDER.size(),
		"skills_learned_at_gate": learned_at_gate,
		"skip_penalty": KnowledgeTracer.SKIP_PENALTY,
		"skipped_tasks": knowledge_tracer.get_skip_stats(),
		"knowledge_confirm_threshold": KNOWLEDGE_CONFIRM_THRESHOLD,
	}

## Folder for THIS run: <ALGO>__<Student>__<MODE>__<YYYY-MM-DD_HHMMSS>. The name
## carries the factors the comparative study groups by, so runs stay tellable
## apart from the file system alone; a numeric suffix separates two runs started
## in the same second.
func _results_run_dir() -> String:
	if _run_results_dir != "":
		return _run_results_dir
	DirAccess.make_dir_recursive_absolute(RESULTS_ROOT)
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("T", "_")
	var base := "%s__%s__%s__%s" % [
		get_algorithm_callout(), _safe_name(_student_name(), "student"), _input_mode_label(), stamp]
	var dir := "%s/%s" % [RESULTS_ROOT, base]
	var suffix := 2
	while DirAccess.dir_exists_absolute(dir):
		dir = "%s/%s_%d" % [RESULTS_ROOT, base, suffix]
		suffix += 1
	DirAccess.make_dir_recursive_absolute(dir)
	_run_results_dir = dir
	return dir

## One entry per completed run in user://results/index.json — the cross-run view
## that replaces the old single shared summary file.
func _append_results_index() -> void:
	if _results_indexed:
		return
	var dir := _results_run_dir()
	var metrics: Dictionary = get_study_metrics()
	metrics.erase("knowledge_state_detail")  # bulky per-skill table: lives in session.json
	var entry := {
		"folder": dir.get_file(),
		"path": dir,
		"timestamp": Time.get_datetime_string_from_system(),
		"student": _student_name(),
		"criteria": get_run_criteria(),
		"metrics": metrics,
	}
	var runs: Array = []
	if FileAccess.file_exists(RESULTS_INDEX):
		var existing := FileAccess.open(RESULTS_INDEX, FileAccess.READ)
		if existing:
			var json := JSON.new()
			if json.parse(existing.get_as_text()) == OK and json.data is Dictionary \
					and json.data.has("runs") and json.data["runs"] is Array:
				runs = json.data["runs"]
			existing.close()
	runs.append(entry)
	_write_json(RESULTS_INDEX, {
		"layout": "one folder per completed run, holding %s, %s and %s" % [SESSION_FILE, SUMMARY_FILE, REPORT_FILE],
		"runs": runs,
		"run_count": runs.size(),
	})
	_results_indexed = true

## Write this completed run as <run folder>/session.json: the learner profile, the
## criteria in force, the study metrics, both tests and their answers, the model
## state and the whiteboard analytics. One folder per run (instead of one growing
## file per student) keeps two runs of the same learner on DIFFERENT algorithms
## side by side and comparable. Idempotent per session: a second call returns the
## same path without rewriting. Returns the path written.
func save_student_results() -> String:
	if _student_results_saved and _student_results_path != "":
		return _student_results_path
	var path := "%s/%s" % [_results_run_dir(), SESSION_FILE]
	_write_json(path, {
		"saved_at": Time.get_datetime_string_from_system(),
		"student": profile_manager.get_profile(),
		"criteria": get_run_criteria(),
		"metrics": get_study_metrics(),
		"pretest": _calculate_test_results(pretest_answers),
		"posttest": _calculate_test_results(posttest_answers),
		"pretest_answers": pretest_answers,
		"posttest_answers": posttest_answers,
		"predicted_knowledge_state": predicted_knowledge_state,
		"knowledge_tracer": knowledge_tracer.to_dict(),
		"workshop_attempts": workshop_attempts,
	})
	_student_results_saved = true
	_student_results_path = path
	_append_results_index()
	return path

## Write this run's algorithm-performance summary as <run folder>/algorithm_summary.json:
## each algorithm's prediction hit-rate (HMM / BKT / KST), the accuracy of the one
## actually used, and which model performed best in this run — the evidence for
## "which model should the POC ship". The cross-run accumulation lives in
## user://results/index.json. Idempotent per session, exactly like
## save_student_results(). Returns the path written.
func save_algorithm_summary() -> String:
	if _algorithm_summary_saved and _algorithm_summary_path != "":
		return _algorithm_summary_path
	var path := "%s/%s" % [_results_run_dir(), SUMMARY_FILE]
	var comparison: Dictionary = knowledge_tracer.get_algorithm_comparison()
	var best_key := ""
	var best_acc := -1.0
	for key in ["HMM", "BKT", "KST"]:
		var stats: Dictionary = comparison.get(key, {})
		if stats.is_empty():
			continue
		if float(stats.get("accuracy", 0.0)) > best_acc:
			best_acc = float(stats.get("accuracy", 0.0))
			best_key = key
	var metrics: Dictionary = get_study_metrics()
	_write_json(path, {
		"timestamp": Time.get_datetime_string_from_system(),
		"student": _student_name(),
		"criteria": get_run_criteria(),
		"algorithm_id": selected_algorithm,
		"algorithm_label": get_algorithm_label(),
		"comparison": comparison,
		"predictive_accuracy": metrics["predictive_accuracy"],
		"knowledge_state_accuracy": metrics["knowledge_state_accuracy"],
		"recommended": best_key,
	})
	_algorithm_summary_saved = true
	_algorithm_summary_path = path
	_append_results_index()
	return path

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
	# Once the session is COMPLETE (post test finished), also write the full
	# comparative-study record into this run's own folder under
	# user://results/<ALGO>__<Student>__<MODE>__<timestamp>/. save_student_results()
	# is idempotent per session, so this cannot duplicate the record.
	if state == SessionState.COMPLETE:
		save_student_results()

func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()

## Write a simple portable PDF report after the post-test is complete. It lands in
## THIS run's folder next to the JSON records, so every artifact of one run travels
## together and the report names the algorithm and criteria it was produced under.
func generate_profile_pdf() -> String:
	var profile: Dictionary = profile_manager.get_profile()
	var pretest := _calculate_test_results(pretest_answers)
	var posttest := _calculate_test_results(posttest_answers)
	var criteria := get_run_criteria()
	var lines: Array[String] = [
		"AUTOLAB PROFILE REPORT",
		"Name: %s" % profile.get("name", ""),
		"Gender: %s" % profile.get("gender", ""),
		"Age: %s" % profile.get("age", ""),
		"Familiar with automata: %s" % ("Yes" if profile.get("familiar_with_automata", false) else "No"),
		"",
		"Algorithm: %s" % str(criteria.get("algorithm", "")),
		"Input mode: %s" % str(criteria.get("input_mode", "")),
		"Mastery gate: learned at %.0f%% with %d+ answers, or the last %d correct" % [
			float(criteria.get("mastery_threshold", 0.0)) * 100.0,
			int(criteria.get("min_evidence", 0)),
			int(criteria.get("recent_window", 0))],
		"Post test unlocked at %d of %d topics learned; reached %d" % [
			int(criteria.get("mastery_gate_skills", 0)),
			int(criteria.get("skills_total", 0)),
			int(criteria.get("skills_learned_at_gate", 0))],
		"Run folder: %s" % _results_run_dir().get_file(),
		"",
		"Pretest: %d/%d (%.1f%%)" % [pretest["correct"], pretest["total"], pretest["percentage"]],
		"Post-test: %d/%d (%.1f%%)" % [posttest["correct"], posttest["total"], posttest["percentage"]],
		"",
		"Total session time: %s" % format_duration(get_total_session_seconds()),
		"  Pretest %s / adaptive learning %s / post test %s" % [
			format_duration(get_pretest_seconds()),
			format_duration(get_adaptive_completion_seconds()),
			format_duration(get_posttest_seconds())],
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
	var path := "%s/%s" % [_results_run_dir(), REPORT_FILE]
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
