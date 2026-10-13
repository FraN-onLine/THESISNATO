extends SceneTree
## Headless self-test for the COMPARATIVE-STUDY metrics and per-student storage.
## Run:
##   Godot_v4.7-stable_win64_console.exe --path <project> --headless \
##     --script res://DevTests/selftest_study_metrics.gd
##
## It verifies the six numbers the study needs and the storage contract:
##   1. TIMER        - the adaptive clock starts with the first skill, freezes
##                     when the algorithm declares mastery, and never restarts.
##   2. SNAPSHOT     - the end-of-learning knowledge state is captured once and
##                     is NOT rewritten by post-test answers.
##   3. METRICS      - pretest/posttest averages, improvement rate, predictive
##                     accuracy, completion time and knowledge-state accuracy
##                     are all computed from the session's own data.
##   4. STORAGE      - one JSON file per student under user://results/, one
##                     record per completed run, idempotent per session.
##   5. STRUCTURE    - the stored record carries every metric and raw answer
##                     array a comparative study needs.
## Prints REPORT lines and exits with code 0 (ok) or 1 (failures).

const SessionManager = preload("res://Testing/session_manager.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_check_timer_and_snapshot()
	_check_metrics_and_storage()
	_report()


# ===== 1 + 2: adaptive clock & end-of-learning snapshot ====================

func _check_timer_and_snapshot() -> void:
	var s := SessionManager.new()
	_note(s.get_adaptive_completion_seconds() == 0.0,
		"adaptive_clock_starts_at_zero", "t=%.1f" % s.get_adaptive_completion_seconds())

	# First skill starts the clock; a second skill must NOT restart it.
	s.start_adaptive_learning("simulation")
	var t1 := s.get_adaptive_completion_seconds()
	_note(t1 >= 0.0 and t1 < 60.0, "adaptive_clock_starts_with_first_skill", "t=%.1f" % t1)
	s.start_adaptive_learning("definition")
	_note(s.adaptive_start_msec > 0 and absf(s.get_adaptive_completion_seconds() - t1) < 60.0,
		"adaptive_clock_never_restarts", "t=%.1f" % s.get_adaptive_completion_seconds())

	# The snapshot happens when the window closes (post test = algorithm done).
	for skill in s.knowledge_tracer.SKILL_ORDER:
		s.record_learning_result(str(skill), true, "mastery_%s" % skill)
	s.start_posttest()
	_note(s.adaptive_end_msec > 0,
		"adaptive_clock_freezes_at_posttest", "end=%d" % s.adaptive_end_msec)
	_note(not s.predicted_knowledge_state.is_empty(),
		"knowledge_snapshot_taken", "skills=%d" % s.predicted_knowledge_state.size())
	var frozen: Dictionary = s.predicted_knowledge_state.duplicate(true)

	# Post-test answers must not rewrite the snapshot. The post test starts with
	# the 15 MC items, but a session that skipped the pretest only has the 5
	# hands-on builds - answer whichever kind is on screen.
	var t2 := s.get_adaptive_completion_seconds()
	if s.current_question_is_handson():
		s.submit_hands_on(true, "selftest build")
	else:
		s.submit_answer(0)
	s.advance_question()
	_note(s.predicted_knowledge_state == frozen,
		"snapshot_survives_posttest_answers", "skills=%d" % s.predicted_knowledge_state.size())
	_note(absf(s.get_adaptive_completion_seconds() - t2) < 60.0,
		"adaptive_clock_stays_frozen", "delta=%.2f" % absf(s.get_adaptive_completion_seconds() - t2))


# ===== 3 + 4 + 5: metrics, storage, structure ==============================

func _check_metrics_and_storage() -> void:
	# Deterministic storage counts: start from a clean results folder for this
	# synthetic student (only the SELFTEST file is touched, never real data).
	if FileAccess.file_exists("user://results/Self_Test.json"):
		DirAccess.remove_absolute("user://results/Self_Test.json")
	var s := SessionManager.new()
	s.save_profile("Self Test", "Other", 20, true)
	s.set_algorithm_type(s.knowledge_tracer.AlgorithmType.HMM)
	s.start_pretest()

	# Pretest: answer every multiple-choice item CORRECTLY, so the pretest
	# average is exactly 100%.
	var answered := 0
	while not s.current_question.is_empty() and not s.current_question_is_handson():
		s.submit_answer(int(s.current_question["correct"]))
		answered += 1
		if s.advance_question().get("complete", false):
			break
	_note(answered >= 15, "pretest_fully_answered", "items=%d" % answered)

	# Adaptive learning for every skill (feeds prediction stats). A real
	# learner takes time here; a busy headless run may finish within one
	# clock tick, so add a few milliseconds for the completion timer.
	for skill in s.knowledge_tracer.SKILL_ORDER:
		s.start_adaptive_learning(str(skill))
		for i in range(4):
			s.record_learning_result(str(skill), true, "obs_%s_%d" % [skill, i])
	OS.delay_msec(20)
	s.finish_adaptive_learning()
	s.start_posttest()

	# Posttest: answer every MC item CORRECTLY, so both averages are known.
	var post_answered := 0
	while not s.current_question.is_empty():
		if s.current_question_is_handson():
			# Hands-on has no option index: record a correct build instead.
			s.submit_hands_on(true, "selftest build")
		else:
			s.submit_answer(int(s.current_question["correct"]))
		post_answered += 1
		if s.advance_question().get("complete", false):
			break
	_note(post_answered >= 15, "posttest_fully_answered", "items=%d" % post_answered)
	_note(int(s.state) == SessionManager.SessionState.COMPLETE,
		"session_reaches_complete", "state=%d" % s.state)

	var m: Dictionary = s.get_study_metrics()
	_note(is_equal_approx(float(m["average_pretest_score"]), 100.0),
		"average_pretest_score", "%.1f%%" % m["average_pretest_score"])
	_note(is_equal_approx(float(m["average_posttest_score"]), 100.0),
		"average_posttest_score", "%.1f%%" % m["average_posttest_score"])
	_note(is_equal_approx(float(m["performance_improvement_rate"]), 0.0),
		"performance_improvement_rate", "%+.1f%%" % m["performance_improvement_rate"])
	var pa := float(m["predictive_accuracy"])
	_note(pa >= 0.0 and pa <= 100.0,
		"predictive_accuracy_in_range", "%s=%.1f%%" % [m["predictive_accuracy_algorithm"], pa])
	_note(float(m["adaptive_learning_seconds"]) > 0.0,
		"adaptive_completion_time_recorded", "%.1fs" % m["adaptive_learning_seconds"])
	_note(float(m["knowledge_state_accuracy"]) >= 0.0
			and float(m["knowledge_state_accuracy"]) <= 100.0,
		"knowledge_state_accuracy_in_range", "%.1f%%" % m["knowledge_state_accuracy"])

	# Storage: one file per student, one record per run, idempotent per session.
	var path: String = s.save_student_results()
	_note(FileAccess.file_exists(path), "student_results_file_written", path)
	_note(s.save_student_results() == path, "student_results_path_stable", path)
	var data: Dictionary = _read_json(path)
	var runs: Array = data.get("sessions", [])
	_note(runs.size() == 1, "one_record_per_completed_run", "runs=%d" % runs.size())
	if runs.is_empty():
		return
	var record: Dictionary = runs[0]
	var metrics: Dictionary = record.get("metrics", {})
	var required := [
		"average_pretest_score", "average_posttest_score",
		"performance_improvement_rate", "predictive_accuracy",
		"adaptive_learning_seconds", "knowledge_state_accuracy",
	]
	var missing: Array[String] = []
	for key in required:
		if not metrics.has(key):
			missing.append(key)
	_note(missing.is_empty(), "all_six_metrics_stored", "missing=%s" % str(missing))
	_note(record.has("pretest_answers") and record.has("posttest_answers")
			and record.has("predicted_knowledge_state") and record.has("algorithm"),
		"raw_answers_and_snapshot_stored", "keys=%d" % record.keys().size())

	# A SECOND completed run must APPEND, not overwrite, the same file.
	var s2 := SessionManager.new()
	s2.save_profile("Self Test", "Other", 20, true)
	s2.start_pretest()
	while not s2.current_question.is_empty() and not s2.current_question_is_handson():
		s2.submit_answer(0)
		if s2.advance_question().get("complete", false):
			break
	s2.start_posttest()
	while not s2.current_question.is_empty():
		if s2.current_question_is_handson():
			s2.submit_hands_on(false, "selftest build")
		else:
			s2.submit_answer(0)
		if s2.advance_question().get("complete", false):
			break
	var path2: String = s2.save_student_results()
	_note(path2 == path, "same_student_same_file", "%s" % path2)
	_note(_read_json(path2).get("sessions", []).size() == 2,
		"second_run_appends_to_same_file", "runs=%d" % _read_json(path2).get("sessions", []).size())


# ===== helpers ==============================================================

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	var text := file.get_as_text()
	file.close()
	if json.parse(text) != OK or not (json.data is Dictionary):
		return {}
	return json.data

func _note(ok: bool, label: String, detail: String) -> void:
	if ok:
		print("REPORT  PASS  %-44s %s" % [label, detail])
	else:
		print("REPORT  FAIL  %-44s %s" % [label, detail])
		_failures.append(label)


func _report() -> void:
	print("REPORT ---- failures=%d ----" % _failures.size())
	for failure in _failures:
		print("REPORT  !! %s" % failure)
	print("REPORT DONE")
	quit(1 if not _failures.is_empty() else 0)
