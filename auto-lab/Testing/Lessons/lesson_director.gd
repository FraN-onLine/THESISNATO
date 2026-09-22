extends RefCounted
## Sequences the whole DFA course for the Testing Grounds.
##
## It owns the ORDER of things - the six lesson modules, then the adaptive
## review of the learner's weakest skills - and nothing else. Every presentation
## detail is behind signals, so the same director drives the in-room lesson
## panel, the whiteboard, and a headless test.
##
## SIGNALS THE ROOM REACTS TO
##   mode_started(mode, total)         "lesson" | "adaptive"
##   module_started(module, index, total, intro)
##   step_shown(step)
##   board_requested(task, title)      open the whiteboard with this task
##   sandbox_requested(step)           open the whiteboard with no task
##   skill_started(skill, index, total)
##   phase_finished(mode)              the room moves on (adaptive / post test)
##
## The learner's answers always go through submit()/advance()/reveal(), which
## forward to the current LessonEngine. The director never touches the models
## directly - the engine does that per graded checkpoint.

signal mode_started(mode: String, total: int)
signal module_started(module: Dictionary, index: int, total: int, intro: Dictionary)
signal step_shown(step: Dictionary)
signal board_requested(task: Dictionary, title: String)
signal sandbox_requested(step: Dictionary)
signal skill_started(skill: String, index: int, total: int)
signal phase_finished(mode: String)

const LessonEngine = preload("res://Testing/Lessons/lesson_engine.gd")
const Library = preload("res://Testing/Lessons/lesson_library.gd")
const Checkpoint = preload("res://Testing/Lessons/checkpoint.gd")

var engine = null            # LessonEngine for the module in progress
var tracer = null            # knowledge tracer (optional)
var gamification = null      # XP / streak tracker (optional)
var voice = null             # narrator (optional)
var mastery_check: Callable = Callable()

var mode := ""               # "lesson" | "adaptive"
var modules: Array = []
var module_index := 0
var plan: Array = []
var plan_index := 0

var _showing_intro := false
var _awaiting_module_continue := false
var _session = null

func _init(session = null) -> void:
	attach_session(session)

## Pull the tracer / gamification off the shared session object.
func attach_session(session) -> void:
	_session = session
	if session == null:
		return
	tracer = session.knowledge_tracer
	gamification = session.gamification

# ===== Phase entry points ==================================================

## The guided course: every module in teaching order.
func start_lesson() -> void:
	mode = "lesson"
	modules = Library.modules()
	module_index = 0
	plan = []
	plan_index = 0
	mode_started.emit(mode, modules.size())
	_begin_module()

## Adaptive review: one module per skill, presented in the learner's weakness
## order. `skill_plan` comes from SessionManager.learning_plan(), which already
## skips the skills the model considers mastered.
func start_adaptive(skill_plan: Array) -> void:
	mode = "adaptive"
	plan = skill_plan.duplicate()
	if plan.is_empty():
		plan = Library.skills()
	plan_index = 0
	modules = []
	mode_started.emit(mode, plan.size())
	_begin_module()

func is_finished() -> bool:
	return engine == null and not _showing_intro and not _awaiting_module_continue

## True while the module's intro panel is on screen (answers are ignored then).
func showing_intro() -> bool:
	return _showing_intro

func has_module() -> bool:
	return engine != null

func current_module() -> Dictionary:
	return engine.module if engine != null else {}

func current_skill() -> String:
	return str(engine.skill) if engine != null else ""

func current_step() -> Dictionary:
	return engine.current() if engine != null else {}

func awaiting_module_continue() -> bool:
	return _awaiting_module_continue

# ===== Module lifecycle ====================================================

func _begin_module() -> void:
	var module := _next_module()
	if module.is_empty():
		_finish_phase()
		return
	engine = LessonEngine.new(module)
	engine.tracer = tracer
	engine.gamification = gamification
	engine.voice = voice
	if not mastery_check.is_null() and mastery_check.is_valid():
		engine.mastery_check = mastery_check
	if mode == "adaptive":
		skill_started.emit(engine.skill, plan_index + 1, plan.size())
	var index := module_index if mode == "lesson" else plan_index
	var total := modules.size() if mode == "lesson" else plan.size()
	_showing_intro = true
	_awaiting_module_continue = false
	module_started.emit(engine.module, index, total, engine.intro_step())
	_speak("Topic %d of %d. %s" % [index + 1, total, engine.module_title()])

## The module for the current position of the phase in progress.
func _next_module() -> Dictionary:
	if mode == "adaptive":
		if plan_index >= plan.size():
			return {}
		return Library.get_module(str(plan[plan_index]))
	if module_index >= modules.size():
		return {}
	return modules[module_index]

# ===== Learner interaction =================================================

## Hand an answer to the current checkpoint. Returns the graded result.
func submit(response) -> Dictionary:
	if engine == null or _showing_intro:
		return {}
	var result: Dictionary = engine.submit(response)
	if bool(result.get("resolved", false)):
		_after_current_step()
	else:
		# A miss may have replaced the current step with a remedy panel, so the
		# room re-reads the engine rather than assuming where it is.
		_publish_current()
	return result

## Reveal the answer (no XP), then move on.
func reveal() -> Dictionary:
	if engine == null or _showing_intro:
		return {}
	var result: Dictionary = engine.reveal()
	_after_current_step()
	return result

## Continue past an info / board / sandbox step, or past a finished module.
func advance() -> void:
	if engine == null:
		return
	if _awaiting_module_continue:
		_awaiting_module_continue = false
		_after_module_complete()
		return
	if _showing_intro:
		_showing_intro = false
		engine.start()
		_publish_current()
		return
	if engine.current_is_checkpoint():
		# Continue on an unanswered checkpoint = skip. It is recorded as a miss
		# (never as a pass) so the summary stays honest.
		var current_id := Checkpoint.id_of(engine.current_checkpoint())
		if not engine.solved.has(current_id):
			engine.reveal()
	_after_current_step()

func hint() -> String:
	return engine.current_hint() if engine != null else ""

func module_summary() -> Dictionary:
	return engine.summary() if engine != null else {}

## The whiteboard finished a task the learner was asked to build. Board TASKS
## (kind "board") are practice: a correct build simply moves on. Board
## CHECKPOINTS (kind "build") are graded by the engine.
func submit_board_result(correct: bool, message: String) -> void:
	if engine == null:
		return
	if engine.current_is_checkpoint() and engine.needs_board():
		submit({"correct": correct, "message": message})
		return
	if correct:
		_after_current_step()

## The learner left the sandbox: carry on with the module.
func sandbox_finished() -> void:
	if engine != null and str(engine.current().get("kind", "")) == "freebuild":
		_after_current_step()

## Ask the room to put the current step on the whiteboard.
func request_board() -> void:
	if engine == null:
		return
	var step: Dictionary = engine.current()
	match str(step.get("kind", "")):
		"board":
			board_requested.emit(step.get("task", {}), str(step.get("title", "WHITEBOARD TASK")))
		"freebuild":
			sandbox_requested.emit(step)
		"checkpoint":
			var cp: Dictionary = step.get("checkpoint", {})
			if Checkpoint.kind_of(cp) == Checkpoint.KIND_BUILD:
				board_requested.emit(cp.get("task", {}), Checkpoint.prompt_of(cp))

# ===== Internal transitions ================================================

func _after_current_step() -> void:
	if engine == null:
		return
	if engine.finished():
		_module_complete()
		return
	engine.advance()
	if engine.finished():
		_module_complete()
		return
	_publish_current()

func _publish_current() -> void:
	step_shown.emit(engine.current())

func _module_complete() -> void:
	_awaiting_module_continue = true
	# The room shows the engine's own report card (module_finished signal).
	step_shown.emit({})

func _after_module_complete() -> void:
	if mode == "adaptive":
		plan_index += 1
		if plan_index >= plan.size():
			_finish_phase()
			return
		_begin_module()
		return
	module_index += 1
	if module_index >= modules.size():
		_finish_phase()
		return
	_begin_module()

func _finish_phase() -> void:
	engine = null
	_showing_intro = false
	_awaiting_module_continue = false
	phase_finished.emit(mode)

func _speak(text: String) -> void:
	if voice != null and voice.has_method("speak"):
		voice.speak(text, "narration")

