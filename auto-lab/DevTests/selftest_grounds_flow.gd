extends SceneTree
## Headless regression test for the TESTING GROUNDS adaptive flow.
## Run:
##   Godot_v4.7-stable_win64_console.exe --path <project> --headless \
##     --script res://DevTests/selftest_grounds_flow.gd
##
## It covers the three behaviours changed in the room controller:
##   1. NO FROZEN PLAYER - no lesson or adaptive screen may leave the player
##      with physics/process disabled. This is the reported "the trap / dead
##      state part of the lesson freezes the player" bug: the board steps used
##      to disable the body while also hiding Next and Back.
##   2. ADAPTIVE RE-TEACH - when the tracer will not call a skill learned, the
##      room re-explains it and re-asks ONLY the questions answered wrong, and
##      the loop terminates instead of spinning forever.
##   3. POST-TEST GATE - "Proceed to Post Test" stays locked until the
##      algorithm considers the learner knowledgeable enough (or the review
##      sweeps are spent, so the session always terminates).

const Library = preload("res://Testing/Lessons/lesson_library.gd")
## Autoloads are not visible as identifiers in --script mode, so the shared
## session is fetched from the tree by path.
const BRIDGE_PATH := "/root/SessionBridge"

var _failures: Array[String] = []
var _frames := 0
var _grounds: Node = null
var _player: Node = null

func _initialize() -> void:
	# The SceneTree root is not usable yet, so the scene is built on the first
	# _process tick instead (see _boot).
	print("REPORT boot=pending")

var _booted := false

func _boot() -> void:
	_booted = true
	var bridge := root.get_node_or_null("SessionBridge")
	if bridge == null:
		_note(false, "session_bridge_available", "autoload missing")
		return
	bridge.call("reset_session")
	var session = bridge.call("get_session")
	session.selected_algorithm = session.knowledge_tracer.AlgorithmType.HMM
	bridge.set("test_mode", "selftest")

	var packed: PackedScene = load("res://Testing/TestingGrounds.tscn")
	var scene_root: Node = packed.instantiate()
	root.add_child(scene_root)
	# The controller script is attached to the UI_Panel child, not the scene
	# root, so it is looked up by capability rather than by path.
	_grounds = _find_controller(scene_root)
	print("REPORT scene_loaded=%s" % ("ok" if _grounds != null else "no_controller"))


## Depth-first search for the node that carries the room controller.
func _find_controller(from: Node) -> Node:
	if from.has_method("_show_dfa_content"):
		return from
	for child in from.get_children():
		var found := _find_controller(child)
		if found != null:
			return found
	return null


func _process(_delta: float) -> bool:
	if not _booted:
		_boot()
		return false
	_frames += 1
	if _frames < 8:
		return false
	if _grounds == null:
		_note(false, "grounds_scene_instantiated", "no scene")
		_report()
		return true
	_player = _grounds.get_parent().get_node_or_null("CharacterBody3D")
	if _player == null:
		_player = _grounds.get_node_or_null("CharacterBody3D")

	_check_player_never_frozen()
	_check_adaptive_reteach()
	_check_posttest_gate()
	_report()
	return true


func _note(ok: bool, label: String, detail: String) -> void:
	if ok:
		print("REPORT  PASS  %-38s %s" % [label, detail])
	else:
		print("REPORT  FAIL  %-38s %s" % [label, detail])
		_failures.append(label)


## True when the player body can still move and look around.
func _player_is_free() -> bool:
	return _player != null and _player.is_physics_processing() and _player.is_processing()

# ===== 1. The freeze =======================================================

func _check_player_never_frozen() -> void:
	var offenders: Array[String] = []
	var seen := 0

	# Worst case first: a body that is already frozen must be restored by the
	# very next screen the room shows.
	if _player != null:
		_player.set_physics_process(false)
		_player.set_process(false)

	# (a) every authored lesson screen, including the "THE TRAP (DEAD) STATE"
	#     panel and the whiteboard practice step that follows it.
	for step in Library.course_steps():
		_grounds.set("_in_dfa_lesson", true)
		match str(step.get("m", "")):
			"content":
				_grounds.call("_show_dfa_content", step)
			"demo":
				_grounds.call("_open_dfa_workshop", step)
			"freebuild":
				_grounds.call("_open_free_build", true)
			"practice":
				var tasks: Array = Library.workshop_tasks(str(step.get("skill", "")))
				if tasks.is_empty():
					continue
				_grounds.call("_open_dfa_board_practice", str(step.get("skill", "")), tasks[0])
		seen += 1
		if not _player_is_free():
			offenders.append("lesson %d (%s)" % [seen, str(step.get("title", ""))])

	# (b) every adaptive-phase screen.
	_grounds.call("_begin_learning_skill", "list")
	for phase in range(0, 8):
		_grounds.call("_show_learning_phase", phase)
		seen += 1
		if not _player_is_free():
			offenders.append("adaptive phase %d" % phase)
	_grounds.call("_show_remedy_round")
	seen += 1
	if not _player_is_free():
		offenders.append("remedy round")
	_grounds.call("_show_challenge")
	seen += 1
	if not _player_is_free():
		offenders.append("challenge")
	_grounds.call("_show_challenge_feedback")
	_grounds.call("_show_learning_end")
	seen += 2
	if not _player_is_free():
		offenders.append("feedback / skill end")
	_grounds.call("_open_builder_task", {"instruction": "Build a DFA.", "accept": ["a"], "reject": ["b"]})
	seen += 1
	if not _player_is_free():
		offenders.append("builder task")

	_note(offenders.is_empty(), "player_never_frozen_on_any_screen",
		"screens=%d offenders=%s" % [seen, str(offenders)])

# ===== 2. Adaptive re-teach ===============================================

func _check_adaptive_reteach() -> void:
	# "definition" has no whiteboard build task, so the challenge phase goes
	# straight to the questions and the flow drives deterministically.
	var skill := "definition"
	_grounds.call("_begin_learning_skill", skill)
	_grounds.session.learning_phase = 5
	_grounds.call("_show_challenge")

	var pool: Array = _grounds.call("_challenge_list")
	_note(pool.size() >= 3, "reask_pool_has_enough_areas", "questions=%d" % pool.size())

	# Answer only the LAST question correctly, so the model stays below its
	# mastery threshold and the room is forced into the re-teach branch.
	var total: int = _grounds.get("_challenge_queue").size()
	var wrong_should_be: Array = []
	var answered := 0
	var guard := 0
	while answered < total and guard < 200:
		guard += 1
		var q_index := int(_grounds.call("_current_challenge_index"))
		if q_index < 0:
			break
		var challenge: Dictionary = _grounds.get("_current_challenge")
		if challenge.is_empty():
			break
		var answer_correctly := answered == total - 1
		var pick := int(challenge.get("correct", 0))
		if not answer_correctly:
			pick = (pick + 1) % maxi(challenge.get("options", []).size(), 1)
			wrong_should_be.append(q_index)
		_grounds.call("_on_challenge_answer", pick)
		answered += 1
		if answered < total:
			_grounds.call("_on_learning_next")

	_note(not wrong_should_be.is_empty(), "reask_records_the_missed_questions",
		"missed=%s" % str(wrong_should_be))

	# Close the round, then let the phase-6 decision run.
	_grounds.call("_on_learning_next")
	var phase_after_round := int(_grounds.session.learning_phase)
	_grounds.call("_on_learning_next")
	var phase_after_decision := int(_grounds.session.learning_phase)

	_note(phase_after_decision == 8, "reteach_triggers_until_algorithm_says_learned",
		"phase_after_round=%d phase_after_decision=%d" % [phase_after_round, phase_after_decision])
	if phase_after_decision != 8:
		return

	# The re-explanation panel must name the missed items, and the next press
	# must queue EXACTLY those items.
	var question_label: Label = _grounds.get("question_label")
	_note(question_label.text.contains("WHAT YOU GOT WRONG"),
		"remedy_panel_explains_the_missed_areas", "explains_misses=true")

	_grounds.call("_on_learning_next")
	var queue: Array = _grounds.get("_challenge_queue")
	_note(queue == wrong_should_be, "reask_queue_is_exactly_the_wrong_items",
		"queue=%s expected=%s" % [str(queue), str(wrong_should_be)])

	# Termination: once the rounds for this skill are spent, the room must stop
	# re-teaching and move on to the skill end, even if nothing was learnt.
	_grounds.call("_begin_learning_skill", skill)
	_grounds.set("_remedy_rounds", {skill: _grounds.MAX_REMEDY_ROUNDS})
	_grounds.session.learning_phase = 5
	_grounds.call("_show_challenge")
	var guard2 := 0
	while guard2 < 200 and int(_grounds.session.learning_phase) == 5 \
			and int(_grounds.get("_challenge_queue_pos")) < _grounds.get("_challenge_queue").size():
		guard2 += 1
		var challenge: Dictionary = _grounds.get("_current_challenge")
		if challenge.is_empty():
			break
		if not bool(_grounds.get("_challenge_answered")):
			var pick := (int(challenge.get("correct", 0)) + 1) % maxi(challenge.get("options", []).size(), 1)
			_grounds.call("_on_challenge_answer", pick)
		_grounds.call("_on_learning_next")
	# Phase 6 now decides: the cap is spent, so it must go to the skill end (7)
	# instead of opening another re-teach round (8).
	_grounds.call("_on_learning_next")
	_note(int(_grounds.session.learning_phase) == 7, "reteach_stops_at_the_round_cap",
		"phase=%d cap=%d" % [int(_grounds.session.learning_phase), _grounds.MAX_REMEDY_ROUNDS])

# ===== 3. Post-test gate ==================================================

func _check_posttest_gate() -> void:
	var tracer = _grounds.session.knowledge_tracer
	_grounds.call("_begin_learning_skill", "list")
	tracer.begin_learning("list")
	_note(not bool(_grounds.call("_ready_for_posttest")), "posttest_locked_below_the_gate",
		"mastered=%d need=%d" % [int(_grounds.call("_mastered_skill_count")), _grounds.MASTERY_GATE_SKILLS])

	# Feed the model enough correct evidence that it calls the skills learned.
	var guard := 0
	while int(_grounds.call("_mastered_skill_count")) < _grounds.MASTERY_GATE_SKILLS and guard < 400:
		guard += 1
		for skill in tracer.SKILL_ORDER:
			tracer.begin_learning(str(skill))
			for i in range(4):
				tracer.record_learning_observation(str(skill), true)
	_note(bool(_grounds.call("_ready_for_posttest")), "posttest_unlocks_once_knowledgeable",
		"mastered=%d need=%d" % [int(_grounds.call("_mastered_skill_count")), _grounds.MASTERY_GATE_SKILLS])


func _report() -> void:
	print("REPORT ---- failures=%d ----" % _failures.size())
	for failure in _failures:
		print("REPORT   failed: %s" % failure)
	print("REPORT DONE")
	quit(1 if not _failures.is_empty() else 0)