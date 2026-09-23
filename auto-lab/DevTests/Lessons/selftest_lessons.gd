extends SceneTree
## Headless self-test for the adaptive lesson system (Testing/Lessons).
## Run:
##   Godot_v4.7-stable_win64_console.exe --path <project> --headless \
##     --script res://DevTests/Lessons/selftest_lessons.gd
##
## It checks four layers and prints REPORT lines, exiting 0 when everything
## passes and 1 when anything fails:
##   1. LIBRARY  - every module is complete and every checkpoint is gradable.
##   2. ENGINE   - a perfect run, a struggling run (remedy injection), mastery
##                 gating and the practice-round cap.
##   3. DIRECTOR - a full six-module lesson then an adaptive phase.
##   4. UI       - the checkpoint card and the maze panel, laid out at the real
##                 panel size, with tap targets a VR laser can hit.

const Library = preload("res://Testing/Lessons/lesson_library.gd")
const Checkpoint = preload("res://Testing/Lessons/checkpoint.gd")
const DfaModel = preload("res://Testing/Lessons/dfa_model.gd")
const LessonEngine = preload("res://Testing/Lessons/lesson_engine.gd")
const LessonDirector = preload("res://Testing/Lessons/lesson_director.gd")
const CheckpointCard = preload("res://Testing/Lessons/checkpoint_card.gd")
const MazePanel = preload("res://Testing/Lessons/maze_panel.gd")
const LessonVoice = preload("res://Testing/Lessons/lesson_voice.gd")
const Gamification = preload("res://Testing/gamification.gd")

const PANEL_W := 2000.0
const PANEL_H := 1250.0
const MIN_TAP_PX := 44.0

var _failures: Array[String] = []
var _frames := 0
var _card: Control
var _maze: Control
var _maze_response: Dictionary = {}
var _card_response = null

## Stand-in for the knowledge tracer: records what it was told and answers the
## two questions the engine asks (mastery % and "is it learned").
class FakeTracer extends RefCounted:
	const SKILL_ORDER := ["simulation", "identification", "definition", "building", "set_builder", "list"]
	var observations: Array = []
	var mastered := false
	var mastery := 0.0

	func record_learning_observation(skill: String, correct: bool) -> void:
		observations.append({"skill": skill, "correct": correct})

	func record_observation(skill: String, correct: bool) -> void:
		observations.append({"skill": skill, "correct": correct})

	func get_mastery_percentage(_skill: String) -> float:
		return mastery

	func is_learned(_skill: String) -> bool:
		return mastered

	func count_for(skill: String) -> int:
		var total := 0
		for entry in observations:
			if str(entry["skill"]) == skill:
				total += 1
		return total


func _initialize() -> void:
	_card = CheckpointCard.new()
	_card.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_card.size = Vector2(PANEL_W, PANEL_H)
	_card.responded.connect(func(response): _card_response = response)
	root.add_child(_card)

	_maze = MazePanel.new()
	_maze.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_maze.size = Vector2(PANEL_W, PANEL_H)
	_maze.responded.connect(func(response): _maze_response = response)
	root.add_child(_maze)
	print("REPORT scene_loaded=ok")


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 6:
		return false
	_card.size = Vector2(PANEL_W, PANEL_H)
	_maze.size = Vector2(PANEL_W, PANEL_H)
	if _frames < 12:
		return false

	_check_library()
	_check_engine_perfect_run()
	_check_remedy_and_practice()
	_check_mastery_gate()
	_check_director()
	_check_voice()
	_check_card_layout()
	_check_maze_walk()
	_report()
	return true


func _note(ok: bool, label: String, detail: String) -> void:
	if ok:
		print("REPORT  PASS  %-38s %s" % [label, detail])
	else:
		print("REPORT  FAIL  %-38s %s" % [label, detail])
		_failures.append(label)

# ===== Helpers =============================================================

func _all_checkpoints() -> Array:
	var found: Array = []
	for module in Library.modules():
		for step in module.get("steps", []):
			if str(step.get("kind", "")) == "checkpoint":
				found.append(step.get("checkpoint", {}))
		for step in module.get("practice", []):
			if str(step.get("kind", "")) == "checkpoint":
				found.append(step.get("checkpoint", {}))
	return found

## The response a fully correct learner would give.
func _correct_response(cp: Dictionary) -> Variant:
	match Checkpoint.kind_of(cp):
		Checkpoint.KIND_MC, Checkpoint.KIND_IDENTIFY:
			return Checkpoint.correct_index_of(cp)
		Checkpoint.KIND_TRACE:
			return str(DfaModel.trace(cp.get("spec", {}), str(cp.get("input", ""))).get("final", ""))
		Checkpoint.KIND_MAZE:
			return _maze_escape(cp.get("spec", {}))
		Checkpoint.KIND_BUILD:
			return {"correct": true, "message": "The board verified your machine."}
	return ""

## A wrong answer that stays wrong for every kind (used to force remediation).
func _wrong_response(cp: Dictionary) -> Variant:
	match Checkpoint.kind_of(cp):
		Checkpoint.KIND_MC, Checkpoint.KIND_IDENTIFY:
			return (Checkpoint.correct_index_of(cp) + 1) % maxi(Checkpoint.options_of(cp).size(), 1)
		Checkpoint.KIND_TRACE:
			return "__not_a_state__"
		Checkpoint.KIND_MAZE:
			return {"escaped": false, "path": "", "final": ""}
		Checkpoint.KIND_BUILD:
			return {"correct": false, "message": "The board rejected this machine."}
	return ""

## A walk that escapes: an accepted string, walked door by door.
func _maze_escape(spec: Dictionary) -> Dictionary:
	var path := _accepted_string(spec)
	var traced := DfaModel.trace(spec, path)
	return {
		"escaped": true,
		"path": path,
		"final": str(traced.get("final", "")),
		"escapes_done": 1,
	}

func _accepted_string(spec: Dictionary) -> String:
	var samples := DfaModel.sample_strings(spec, 4, 4)
	var accepted: Array = samples.get("accept", [])
	if accepted.is_empty():
		return ""
	return str(accepted[0])

## Runs a module to the end. `misses_first` = answer this many times wrongly
## before getting it right (0 = perfect run).
func _play_module(module: Dictionary, tracer, misses_first := 0, max_steps := 600) -> Dictionary:
	var engine = LessonEngine.new(module)
	engine.tracer = tracer
	engine.gamification = Gamification.new()
	var tries := {}
	var guard := 0
	engine.start()
	while not engine.finished() and guard < max_steps:
		guard += 1
		if engine.current_is_checkpoint():
			var cp: Dictionary = engine.current_checkpoint()
			var id := Checkpoint.id_of(cp)
			var used := int(tries.get(id, 0))
			tries[id] = used + 1
			var response = _wrong_response(cp) if used < misses_first else _correct_response(cp)
			var result: Dictionary = engine.submit(response)
			if bool(result.get("resolved", false)):
				engine.advance()
		else:
			engine.advance()
	return engine.summary()

# ===== 1. Library ==========================================================

func _check_library() -> void:
	var modules := Library.modules()
	_note(modules.size() == 6, "library_module_count", "modules=%d" % modules.size())
	_note(Library.skills().size() == 6, "library_skill_count", "skills=%d" % Library.skills().size())

	var problems: Array[String] = []
	for module in modules:
		var skill := str(module.get("skill", ""))
		if skill == "" or not FakeTracer.SKILL_ORDER.has(skill):
			problems.append("unknown skill '%s'" % skill)
		if (module.get("steps", []) as Array).is_empty():
			problems.append("%s has no steps" % skill)
		if (module.get("remedy", []) as Array).is_empty():
			problems.append("%s has no remedy pool" % skill)
		if (module.get("practice", []) as Array).is_empty():
			problems.append("%s has no practice pool" % skill)
		if (module.get("intro", {}) as Dictionary).is_empty():
			problems.append("%s has no intro panel" % skill)
	_note(problems.is_empty(), "library_modules_complete", "problems=%s" % str(problems))

	# Every checkpoint must be answerable: a choice index in range, a trace whose
	# expected answer really is where the machine stops, a build with test
	# strings, a walkable maze.
	var bad: Array[String] = []
	var traced := 0
	for cp in _all_checkpoints():
		var id := Checkpoint.id_of(cp)
		match Checkpoint.kind_of(cp):
			Checkpoint.KIND_MC, Checkpoint.KIND_IDENTIFY:
				var count: int = Checkpoint.options_of(cp).size()
				if count < 2 or Checkpoint.correct_index_of(cp) < 0 or Checkpoint.correct_index_of(cp) >= count:
					bad.append("%s: bad option index" % id)
				if Checkpoint.explain_of(cp) == "":
					bad.append("%s: no explanation" % id)
			Checkpoint.KIND_TRACE:
				traced += 1
				var result := DfaModel.trace(cp.get("spec", {}), str(cp.get("input", "")))
				if not bool(result.get("ok", false)):
					bad.append("%s: machine cannot run (%s)" % [id, str(result.get("error", ""))])
				elif str(cp.get("answer", "")) != str(result.get("final", "")):
					bad.append("%s: answer '%s' but run stops in '%s'" % [id, str(cp.get("answer", "")), str(result.get("final", ""))])
			Checkpoint.KIND_MAZE:
				var spec: Dictionary = cp.get("spec", {})
				if _accepted_string(spec) == "" and not DfaModel.accepts(spec, ""):
					bad.append("%s: no accepted string to escape with" % id)
			Checkpoint.KIND_BUILD:
				var task: Dictionary = cp.get("task", {})
				if (task.get("accept", []) as Array).is_empty() or (task.get("reject", []) as Array).is_empty():
					bad.append("%s: board task without accept/reject strings" % id)
			_:
				bad.append("%s: unknown kind '%s'" % [id, Checkpoint.kind_of(cp)])
	_note(bad.is_empty(), "library_checkpoints_gradable",
		"checked=%d traces=%d problems=%s" % [_all_checkpoints().size(), traced, str(bad)])

# ===== 2. Engine ===========================================================

func _check_engine_perfect_run() -> void:
	var tracer := FakeTracer.new()
	tracer.mastered = true
	var summaries: Array = []
	for module in Library.modules():
		summaries.append(_play_module(module, tracer))
	var scores: Array[String] = []
	var ok := true
	for entry in summaries:
		scores.append("%s=%.0f" % [str(entry.get("skill", "?")), float(entry.get("score", 0.0))])
		if float(entry.get("score", 0.0)) < 99.9:
			ok = false
		if int(entry.get("practice_rounds", 0)) != 0:
			ok = false
		if int(entry.get("solved", 0)) != int(entry.get("checkpoints", -1)):
			ok = false
	_note(ok, "engine_perfect_run_all_modules", "scores=%s" % ", ".join(scores))

	# One observation per graded checkpoint, and none from info panels.
	var expected := 0
	for module in Library.modules():
		for step in module.get("steps", []):
			if str(step.get("kind", "")) == "checkpoint":
				expected += 1
	_note(tracer.observations.size() == expected, "engine_records_one_observation_per_checkpoint",
		"recorded=%d expected=%d" % [tracer.observations.size(), expected])

func _check_remedy_and_practice() -> void:
	# A learner who misses every checkpoint twice must get the remedy panel,
	# then extra practice, and must still reach the end of the module.
	var tracer := FakeTracer.new()
	tracer.mastered = false
	var definition := Library.get_module("definition")
	var summary := _play_module(definition, tracer, 2)
	_note(int(summary.get("remedies", 0)) >= 1, "engine_remedy_injected_after_misses",
		"remedies=%d misses=%d" % [int(summary.get("remedies", 0)), int(summary.get("misses", 0))])
	_note(int(summary.get("practice_rounds", 0)) >= 1, "engine_practice_added_when_unmastered",
		"rounds=%d score=%.0f" % [int(summary.get("practice_rounds", 0)), float(summary.get("score", 0.0))])
	_note(int(summary.get("practice_rounds", 0)) <= LessonEngine.MAX_PRACTICE_ROUNDS,
		"engine_practice_rounds_capped", "rounds=%d cap=%d" % [
			int(summary.get("practice_rounds", 0)), LessonEngine.MAX_PRACTICE_ROUNDS])

func _check_mastery_gate() -> void:
	var mastered := FakeTracer.new()
	mastered.mastered = true
	mastered.mastery = 91.0
	var summary := _play_module(Library.get_module("list"), mastered)
	_note(int(summary.get("practice_rounds", 0)) == 0 and bool(summary.get("mastered", false)),
		"engine_mastery_gate_skips_practice",
		"rounds=%d mastered=%s mastery=%.0f" % [
			int(summary.get("practice_rounds", 0)), str(summary.get("mastered", false)),
			float(summary.get("mastery_pct", 0.0))])

# ===== 3. Director =========================================================

func _check_director() -> void:
	var tracer := FakeTracer.new()
	tracer.mastered = true
	tracer.mastery = 88.0
	var director = LessonDirector.new()
	director.tracer = tracer
	director.gamification = Gamification.new()
	var modes: Array = []
	var modules_seen: Array = [0]
	director.phase_finished.connect(func(mode): modes.append(mode))
	director.module_started.connect(func(_module, _index, _total, _intro): modules_seen[0] += 1)

	_auto_play(director, "lesson")
	_note(modes.size() == 1 and str(modes[0]) == "lesson", "director_lesson_phase_finished",
		"modes=%s modules=%d" % [str(modes), int(modules_seen[0])])
	_note(int(modules_seen[0]) == 6, "director_lesson_visits_all_modules", "modules=%d" % int(modules_seen[0]))
	# Phase one is over: reset the counters so the adaptive phase is measured
	# on its own (one module per skill in the plan handed to the director).
	modes.clear()
	modules_seen[0] = 0

	_auto_play(director, "adaptive")
	_note(modes.size() == 1 and str(modes[0]) == "adaptive", "director_adaptive_phase_finished",
		"modes=%s" % str(modes))
	_note(int(modules_seen[0]) == 2, "director_adaptive_visits_planned_skills",
		"modules=%d plan=2" % int(modules_seen[0]))

## Drives a director to the end of one phase by answering everything correctly.
func _auto_play(director, phase: String) -> void:
	if phase == "lesson":
		director.start_lesson()
	else:
		director.start_adaptive(["definition", "simulation"])
	var guard := 0
	while not director.is_finished() and guard < 4000:
		guard += 1
		if director.showing_intro():
			director.advance()
			continue
		if director.awaiting_module_continue():
			director.advance()
			continue
		var step: Dictionary = director.current_step()
		if step.is_empty():
			director.advance()
			continue
		match str(step.get("kind", "")):
			"checkpoint":
				var cp: Dictionary = step.get("checkpoint", {})
				if Checkpoint.needs_maze(cp):
					director.submit(_maze_escape(cp.get("spec", {})))
				elif Checkpoint.needs_board(cp):
					director.submit_board_result(true, "board verified")
				else:
					director.submit(_correct_response(cp))
			"board":
				director.submit_board_result(true, "board verified")
			"freebuild":
				director.sandbox_finished()
			_:
				director.advance()

# ===== 4. Voice hook =======================================================

func _check_voice() -> void:
	var voice = LessonVoice.new()
	_note(voice.enabled == false, "voice_silent_by_default", "enabled=%s" % str(voice.enabled))
	voice.speak("Checkpoint two. Trace the string.", "narration")
	voice.announce_checkpoint(2, 9, "Trace the string", "sim_trace_1")
	_note(voice.get_script_log().size() == 2, "voice_logs_lines_for_later_recording",
		"lines=%d" % voice.get_script_log().size())
	voice.clip_root = "res://Audio/Voice"
	_note(voice.clip_path_for("sim_trace_1") == "res://Audio/Voice/sim_trace_1.ogg",
		"voice_clip_path_convention", "path=%s" % voice.clip_path_for("sim_trace_1"))
	var captions: Array = []
	voice.captions_changed.connect(func(text, _kind): captions.append(text))
	voice.speak("Captions must work while muted.", "narration")
	_note(captions.size() == 1, "voice_captions_while_muted", "captions=%d" % captions.size())

# ===== 5. Checkpoint card and maze panel ===================================

func _check_card_layout() -> void:
	var mc: Dictionary = Library.get_module("definition").get("steps", [])[3]
	var cp: Dictionary = mc.get("checkpoint", {})
	_card.show_checkpoint(cp)
	var buttons := _buttons_in(_card)
	var too_small: Array[String] = []
	for button in buttons:
		if minf(button.size.x, button.size.y) < MIN_TAP_PX - 0.5:
			too_small.append("%s(%d)" % [str(button.name), int(minf(button.size.x, button.size.y))])
	_note(buttons.size() >= 5, "card_builds_options_and_controls", "buttons=%d" % buttons.size())
	_note(too_small.is_empty(), "card_tap_targets_min_%dpx" % int(MIN_TAP_PX), "offenders=%s" % str(too_small))

	# Tapping the first option must answer with its index.
	_card_response = null
	for button in buttons:
		if str(button.text).begins_with("A."):
			button.emit_signal("pressed")
			break
	_note(_card_response == 0, "card_option_tap_reports_index", "response=%s" % str(_card_response))

	# The trace kind answers with typed text.
	var trace_step: Dictionary = Library.get_module("simulation").get("steps", [])[3]
	var trace_cp: Dictionary = trace_step.get("checkpoint", {})
	_card.show_checkpoint(trace_cp)
	var input: LineEdit = _card.get("_answer_input")
	input.text = " q2 "
	_card_response = null
	_card.call("_on_submit_answer")
	_note(_card_response == "q2", "card_trace_answer_is_trimmed", "response=%s" % str(_card_response))

	# The build kind must explain the board task and the test strings.
	var build_cp: Dictionary = Library.get_module("building").get("steps", [])[3].get("checkpoint", {})
	_card.show_checkpoint(build_cp)
	var points: Label = _card.get("_points_label")
	_note("ACCEPTED" in points.text and "Check task" in points.text, "card_build_explains_board_task",
		"text=%s" % points.text.substr(0, 60))

func _check_maze_walk() -> void:
	var maze_cp: Dictionary = Library.get_module("simulation").get("steps", [])[4].get("checkpoint", {})
	var spec: Dictionary = maze_cp.get("spec", {})
	_maze.show_maze(spec, str(maze_cp.get("objective", "")), int(maze_cp.get("escapes", 1)))
	var path := _accepted_string(spec)
	for index in path.length():
		_maze.call("_walk_through", path.substr(index, 1))
	_maze_response = {}
	_maze.call("_on_submit")
	var graded := Checkpoint.grade(maze_cp, _maze_response)
	_note(bool(graded.get("correct", false)), "maze_walk_is_graded_like_typed_answer",
		"path='%s' response=%s" % [path, str(_maze_response)])
	_note(_maze.call("is_escaped"), "maze_reports_escape", "escaped=%s" % str(_maze.call("is_escaped")))

	# A dead-end walk must not count as an escape.
	var rejected := ""
	for candidate in ["", "b", "bb"]:
		if not DfaModel.accepts(spec, candidate):
			rejected = candidate
			break
	_maze.show_maze(spec, "reject test", 1)
	for index in rejected.length():
		_maze.call("_walk_through", rejected.substr(index, 1))
	_maze_response = {}
	_maze.call("_on_submit")
	var graded_bad := Checkpoint.grade(maze_cp, _maze_response)
	_note(not bool(graded_bad.get("correct", false)), "maze_rejects_non_accepting_walk",
		"walk='%s' escaped=%s" % [rejected if rejected != "" else "(empty)", str(_maze_response.get("escaped", false))])

# ===== Reporting ===========================================================

func _buttons_in(node: Node) -> Array:
	var found: Array = []
	for child in node.get_children():
		if child is Button:
			found.append(child)
		found.append_array(_buttons_in(child))
	return found

func _report() -> void:
	print("REPORT ---- failures=%d ----" % _failures.size())
	for failure in _failures:
		print("REPORT  !! %s" % failure)
	print("REPORT DONE")
	quit(1 if _failures.size() > 0 else 0)




