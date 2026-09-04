extends Node3D
## Controller for the standalone Pretest / Post-test room.
##
## The room is a walkable 3D space (like the diagnostic workshop room) with two
## floating billboards: a question panel (TestPanelBillboard) and the same
## automata workshop board used everywhere in the game.
##
## Question kinds:
##   - mc / image : answered on the floating panel (image questions show a
##                  diagram first). One click records and advances.
##   - handson    : the question panel shows the task and the automata board is
##                  activated with that task. The learner must build the DFA and
##                  press "Check task" on the board to submit. Only a correct
##                  build is accepted and advances the test.

const SessionManager = preload("res://Testing/session_manager.gd")

@onready var test_panel: Node3D = $TestPanel
@onready var workshop: Node3D = $Workshop

var session = null
var test_mode := "pretest"  # "pretest" | "posttest"
var awaiting_handson := false

func _ready() -> void:
	session = SessionBridge.get_session()
	test_mode = SessionBridge.test_mode
	if test_mode != "posttest":
		test_mode = "pretest"

	# Make sure the session is in the right phase.
	if test_mode == "posttest":
		if session.state != SessionManager.SessionState.POST_TEST:
			session.start_posttest()
	else:
		if session.state != SessionManager.SessionState.PRETEST:
			session.start_pretest()

	if test_panel:
		test_panel.set_mode(test_mode)
		test_panel.start_pressed.connect(_on_start_pressed)
		test_panel.answer_selected.connect(_on_answer_selected)
		test_panel.next_pressed.connect(_on_next_pressed)
		test_panel.back_pressed.connect(_on_back_pressed)
		_show_intro()
	if workshop:
		workshop.evaluated.connect(_on_workshop_evaluated)
		workshop.set_active(false)

func _show_intro() -> void:
	if test_mode == "posttest":
		test_panel.show_intro("You will now take the POST-TEST on DFA (Deterministic Finite Automata).\n\nAnswer each question to the best of your ability. Some questions show a diagram, and some hands-on tasks require you to BUILD the DFA on the automata board and press \"Check task\" to submit.\n\nPress Start to begin.")
	else:
		test_panel.show_intro("You will now take the PRETEST on DFA (Deterministic Finite Automata).\n\nThe questions cover 7 skill areas and mix multiple-choice, diagram and hands-on board tasks. For hands-on tasks, build the DFA on the automata board and press \"Check task\" to submit - only a correct build continues.\n\nPress Start to begin.")

func _on_start_pressed() -> void:
	_show_current_question()

func _show_current_question() -> void:
	awaiting_handson = false
	var question: Dictionary = session.get_current_question()
	if question.is_empty() or session.get_current_question_number() > session.get_total_questions():
		_finish_test()
		return
	var number: int = session.get_current_question_number()
	var total: int = session.get_total_questions()

	if session.current_question_is_handson():
		awaiting_handson = true
		if workshop:
			workshop.set_active(true)
			var task: Dictionary = session.get_current_hands_on_task()
			if workshop.builder is Control and not task.is_empty():
				workshop.builder.call("reset_for_task_lists",
					task.get("instruction", "Build the DFA on the board."),
					task.get("accept", []),
					task.get("reject", []))
		test_panel.show_hands_on(question, number, total)
	else:
		if workshop:
			workshop.set_active(false)
		test_panel.show_question(question, number, total)

func _on_answer_selected(selected_index: int) -> void:
	if awaiting_handson:
		return
	var result: Dictionary = session.submit_answer(selected_index)
	var correct: bool = result.get("correct", false)
	if result.get("complete", false):
		test_panel.set_feedback("Test complete! Moving on.", correct)
		test_panel.show_next_button("Finish")
		return
	test_panel.set_feedback("Correct!" if correct else "Not quite - keep going.", correct)
	test_panel.show_next_button("Next >>")

func _on_workshop_evaluated(correct: bool, message: String) -> void:
	if not awaiting_handson:
		return
	if correct:
		var result: Dictionary = session.submit_hands_on(true, message)
		if result.get("complete", false):
			test_panel.set_feedback("Hands-on task verified! Test complete!", true)
			test_panel.show_next_button("Finish")
			return
		test_panel.set_feedback("Verified on the board! " + message, true)
		test_panel.show_next_button("Next >>")
	else:
		# Wrong build: stay on the board so the learner can fix and resubmit.
		test_panel.set_feedback(message + "\n\nAdjust the DFA on the board and press \"Check task\" again to submit.", false)

func _on_next_pressed() -> void:
	var is_complete: bool = session.state == SessionManager.SessionState.ANALYSIS or session.state == SessionManager.SessionState.COMPLETE
	if is_complete:
		_finish_test()
		return
	_show_current_question()

func _on_back_pressed() -> void:
	_finish_test()

func _finish_test() -> void:
	if workshop:
		workshop.set_active(false)
	if test_panel:
		test_panel.visible = false
	# Return to the Testing Grounds; its _ready detects the session state and
	# shows Knowledge Analysis (pretest) or Results (post-test).
	get_tree().change_scene_to_file("res://Testing/TestingGrounds.tscn")