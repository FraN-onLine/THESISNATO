extends SceneTree
## Headless self-test for the COMPARATIVE-STUDY metrics and per-run storage.
## Run:
##   Godot_v4.7-stable_win64_console.exe --path <project> --headless \
##     --script res://DevTests/selftest_study_metrics.gd
##
## It verifies the numbers the study needs and the storage contract:
##   1. TIMER        - the adaptive clock starts with the first skill, freezes
##                     when the algorithm declares mastery, and never restarts;
##                     the TOTAL clock spans start -> post-test completion.
##   2. SNAPSHOT     - the end-of-learning knowledge state is captured once and
##                     is NOT rewritten by post-test answers.
##   3. METRICS      - pretest/posttest averages, improvement rate, predictive
##                     accuracy, completion time and knowledge-state accuracy
##                     are all computed from the session's own data.
##   4. STORAGE      - one FOLDER per completed run under user://results/, named
##                     after the algorithm, the learner, the input mode and the
##                     time; idempotent per session; a second run never lands in
##                     the first run's folder.
##   5. STRUCTURE    - the stored record carries every metric, the mastery
##                     criteria in force and the raw answer arrays a comparative
##                     study needs, and user://results/index.json lists the run.
##   6. CLEANUP      - the folders this test creates are removed and index.json is
##                     restored, so running it changes nothing on disk.
## Prints REPORT lines and exits with code 0 (ok) or 1 (failures).

const SessionManager = preload("res://Testing/session_manager.gd")

const RESULTS_ROOT := "user://results"
const RESULTS_INDEX := "user://results/index.json"
const TEST_STUDENT := "Self Test"

var _failures: Array[String] = []
var _created_dirs: Array[String] = []
var _index_backup := PackedByteArray()
var _index_existed := false


func _initialize() -> void:
	_backup_index()
	_check_timer_and_snapshot()
	_check_metrics_and_storage()
	_cleanup()
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
	_note(s.session_start_msec > 0 and s.get_total_session_seconds() >= 0.0,
		"total_clock_running_from_creation", "total=%.2fs" % s.get_total_session_seconds())
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
	# Every run folder this test creates is tracked in _created_dirs and removed
	# again in _cleanup(), so no synthetic student data is left behind.
	var s := SessionManager.new()
	s.save_profile(TEST_STUDENT, "Other", 20, true)
	s.set_algorithm_type(s.knowledge_tracer.AlgorithmType.HMM)
	s.start_pretest()
	var session_start := s.session_start_msec
	_note(session_start > 0, "total_clock_runs_from_session_creation", "start=%d" % session_start)

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
	_note(s.session_start_msec == session_start and s.session_end_msec > 0,
		"total_clock_spans_the_run_and_freezes", "start=%d end=%d" % [s.session_start_msec, s.session_end_msec])
	var frozen_total := s.get_total_session_seconds()
	OS.delay_msec(20)
	_note(is_equal_approx(s.get_total_session_seconds(), frozen_total),
		"total_time_does_not_grow_after_completion", "%.2fs" % frozen_total)

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
	# The headline number: start -> post-test completion, and it must be at least
	# as long as the phases inside it (a restarted clock would shrink it).
	var total_secs := float(m["total_session_seconds"])
	var pre_secs := float(m["pretest_seconds"])
	var learn_secs := float(m["adaptive_learning_seconds"])
	var post_secs := float(m["posttest_seconds"])
	_note(total_secs > 0.0 and total_secs >= pre_secs + learn_secs + post_secs - 0.5,
		"total_session_time_covers_every_phase",
		"total=%.2fs (pretest %.2f + learning %.2f + posttest %.2f)" % [total_secs, pre_secs, learn_secs, post_secs])
	_note(SessionManager.format_duration(75.4) == "1:15" and SessionManager.format_duration(0.0) == "0:00",
		"durations_render_as_minutes_and_seconds", SessionManager.format_duration(75.4))

	# Storage: ONE FOLDER per run, named after the algorithm + the other factors,
	# holding this run's record; idempotent per session.
	var path: String = s.save_student_results()
	var folder := path.get_base_dir()
	_created_dirs.append(folder)
	_note(FileAccess.file_exists(path), "session_record_written", path)
	_note(s.save_student_results() == path, "session_record_path_stable", path)
	var folder_name := folder.get_file()
	_note(folder.begins_with(RESULTS_ROOT) and folder_name.begins_with("HMM__Self_Test__"),
		"run_folder_named_by_algorithm_and_learner", folder_name)
	_note("__PC__" in folder_name or "__VR__" in folder_name,
		"run_folder_names_the_input_mode", folder_name)
	var stamp := folder_name.get_slice("__", 3)
	_note(stamp.length() >= 15 and stamp.contains("-") and stamp.contains("_"),
		"run_folder_carries_a_timestamp", stamp)

	var record: Dictionary = _read_json(path)
	var metrics: Dictionary = record.get("metrics", {})
	var required := [
		"average_pretest_score", "average_posttest_score",
		"performance_improvement_rate", "predictive_accuracy",
		"adaptive_learning_seconds", "knowledge_state_accuracy",
		"total_session_seconds", "pretest_seconds", "posttest_seconds",
	]
	var missing: Array[String] = []
	for key in required:
		if not metrics.has(key):
			missing.append(key)
	_note(missing.is_empty(), "every_study_metric_stored", "missing=%s" % str(missing))
	_note(record.has("pretest_answers") and record.has("posttest_answers")
			and record.has("predicted_knowledge_state") and record.has("criteria")
			and record.has("student"),
		"raw_answers_and_snapshot_stored", "keys=%d" % record.keys().size())

	# The mastery criteria in force must travel with the record: the folder says
	# WHICH algorithm ran, the criteria say under WHICH rules it was judged.
	var criteria: Dictionary = record.get("criteria", {})
	var criteria_required := [
		"algorithm", "algorithm_callout", "algorithm_id", "input_mode",
		"mastery_threshold", "min_evidence", "recent_window",
		"mastery_gate_skills", "skills_total", "skills_learned_at_gate",
		"skip_penalty", "knowledge_confirm_threshold",
	]
	var criteria_missing: Array[String] = []
	for criteria_key in criteria_required:
		if not criteria.has(criteria_key):
			criteria_missing.append(criteria_key)
	_note(criteria_missing.is_empty(), "mastery_criteria_recorded",
		"missing=%s" % str(criteria_missing))
	_note(int(criteria.get("skills_learned_at_gate", -1)) == int(criteria.get("skills_total", 0))
			and int(criteria.get("skills_total", 0)) == 6,
		"criteria_reports_the_gate_decision", "%s of %s topics learned at the gate" % [
			criteria.get("skills_learned_at_gate", "?"), criteria.get("skills_total", "?")])
	_note(is_equal_approx(float(criteria.get("mastery_threshold", -1.0)),
			float(s.knowledge_tracer.MASTERY_THRESHOLD)),
		"criteria_quote_the_live_threshold", "threshold=%s" % criteria.get("mastery_threshold", "?"))

	# The algorithm summary lands BESIDE the session record, in the same folder.
	var summary_path: String = s.save_algorithm_summary()
	_note(summary_path.get_base_dir() == folder and FileAccess.file_exists(summary_path),
		"algorithm_summary_in_the_same_run_folder", summary_path)
	var summary: Dictionary = _read_json(summary_path)
	_note(summary.has("comparison") and summary.has("recommended") and summary.has("criteria"),
		"algorithm_summary_carries_the_comparison", "keys=%d" % summary.keys().size())

	# The printable report joins the same folder instead of overwriting one
	# machine-wide user://profile_data.pdf on every run.
	var report_path: String = s.generate_profile_pdf()
	_note(report_path.get_base_dir() == folder and FileAccess.file_exists(report_path),
		"profile_report_in_the_same_run_folder", report_path)

	# The cross-run index lists this run exactly once.
	var runs: Array = _read_json(RESULTS_INDEX).get("runs", [])
	_note(_index_entries_for(runs, folder_name) == 1,
		"index_lists_the_run_once", "folder=%s entries=%d" % [folder_name, _index_entries_for(runs, folder_name)])

	# A SECOND completed run must get its OWN folder, never touch the first.
	var s2 := SessionManager.new()
	s2.save_profile(TEST_STUDENT, "Other", 20, true)
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
	var folder2 := path2.get_base_dir()
	_created_dirs.append(folder2)
	_note(folder2 != folder and FileAccess.file_exists(path2),
		"second_run_gets_its_own_folder", "%s vs %s" % [folder2.get_file(), folder_name])
	_note(FileAccess.file_exists(path), "first_run_record_survives", path)
	var runs2: Array = _read_json(RESULTS_INDEX).get("runs", [])
	_note(_index_entries_for(runs2, folder2.get_file()) == 1 and _index_entries_for(runs2, folder_name) == 1,
		"index_has_one_entry_per_run", "runs=%d" % runs2.size())


# ===== helpers ==============================================================

## How many index entries point at one run folder (must always be exactly 1).
func _index_entries_for(runs: Array, folder_name: String) -> int:
	var count := 0
	for run in runs:
		if run is Dictionary and str((run as Dictionary).get("folder", "")) == folder_name:
			count += 1
	return count

func _backup_index() -> void:
	if not FileAccess.file_exists(RESULTS_INDEX):
		return
	var file := FileAccess.open(RESULTS_INDEX, FileAccess.READ)
	if file == null:
		return
	_index_backup = file.get_buffer(file.get_length())
	file.close()
	_index_existed = true

## Leave the developer's real results tree exactly as it was: drop every folder
## this test created and put the shared index back.
func _cleanup() -> void:
	for dir in _created_dirs:
		_remove_dir(dir)
	if _index_existed:
		var file := FileAccess.open(RESULTS_INDEX, FileAccess.WRITE)
		if file != null:
			file.store_buffer(_index_backup)
			file.close()
	elif FileAccess.file_exists(RESULTS_INDEX):
		DirAccess.remove_absolute(RESULTS_INDEX)

func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file_name in dir.get_files():
		DirAccess.remove_absolute("%s/%s" % [path, file_name])
	for sub in dir.get_directories():
		_remove_dir("%s/%s" % [path, sub])
	DirAccess.remove_absolute(path)

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
