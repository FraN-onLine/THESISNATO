extends RefCounted
## Runtime engine for the data-driven lesson modules.
##
## The engine owns every decision that is not drawing: which step comes next,
## when remediation is injected, when extra practice is added, when a module is
## mastered, and which graded observations reach the knowledge tracer. UI code
## only presents `current()` and calls `submit()`, so every presentation surface
## (panel billboard, maze, whiteboard) shares one rule set.
##
## PUBLIC CONTRACT
##   var engine := LessonEngine.new(LessonLibrary.get_module("simulation"))
##   engine.tracer = knowledge_tracer     # optional: graded checkpoints only
##   engine.gamification = gamification   # optional: XP / streak tracker
##   engine.voice = voice_service         # optional narrator (lesson_voice.gd)
##   engine.step_changed.connect(_on_step)
##   engine.start()
##   engine.submit(response)              # response depends on checkpoint kind
##   engine.advance()                     # info / board / freebuild steps
##
## INFO PANELS NEVER TOUCH THE MODELS. Only checkpoints do, and each one records
## exactly ONE observation for its skill.

signal step_changed(step: Dictionary, index: int, total: int)
## Fired when a GRADED step becomes current, so the UI can notify the learner
## ("CHECKPOINT 3 / 9 - trace the string").
signal checkpoint_reached(step: Dictionary, number: int, total: int)
signal checkpoint_graded(result: Dictionary)
signal checkpoint_solved(checkpoint_id: String, first_try: bool, xp: int)
signal checkpoint_failed(checkpoint_id: String, misses: int, hint: String)
signal remediation_injected(info_step: Dictionary, attempt: int)
signal practice_injected(step: Dictionary, round_number: int, remaining: int)
signal mastery_changed(skill_id: String, mastered: bool, mastery_pct: float)
signal level_up(event: Dictionary)
signal module_finished(summary: Dictionary)

const Checkpoint = preload("res://Testing/Lessons/checkpoint.gd")
const Library = preload("res://Testing/Lessons/lesson_library.gd")

## Misses allowed on one checkpoint before the remedy panel is injected.
const MISSES_BEFORE_REMEDY := 2
## Upper bound on remedy panels so a struggling learner always reaches the end.
const MAX_REMEDIES := 2
## Upper bound on extra practice rounds appended when a skill is not mastered.
const MAX_PRACTICE_ROUNDS := 3

# --- Content ---------------------------------------------------------------
var module: Dictionary = {}
var skill: String = ""
var queue: Array = []
var position := 0

# --- Injected collaborators (all optional) ---------------------------------
var tracer = null
var gamification = null
var voice = null
## Optional Callable(skill) -> bool; defaults to tracer.is_learned when present.
var mastery_check: Callable = Callable()

# --- Live state ------------------------------------------------------------
var attempts: Dictionary = {}      # checkpoint id -> misses so far
var solved: Dictionary = {}        # checkpoint id -> true once graded correct
var first_try_ids: Array = []      # checkpoints solved with zero misses
var remedies_used := 0
var practice_rounds := 0
var checkpoint_total := 0
var checkpoint_seen := 0
var current_result: Dictionary = {}
var finished_module := false
## Checkpoints already announced, so re-visiting one after a remedy panel does
## not inflate the "checkpoint n / m" counter.
var seen_ids: Array = []

func _init(source: Variant = null) -> void:
	if source is Dictionary and source.has("steps"):
		set_module(source)
	elif source is Array:
		set_steps(source)

func set_steps(source_steps: Array, skill_id := "") -> void:
	set_module({"skill": skill_id, "steps": source_steps, "title": "LESSON"})

## Load a lesson module (see Testing/Lessons/lesson_library.gd for the shape).
func set_module(source_module: Dictionary) -> void:
	module = source_module.duplicate(true)
	skill = str(module.get("skill", ""))
	queue = (module.get("steps", []) as Array).duplicate(true)
	position = 0
	attempts.clear()
	solved.clear()
	first_try_ids.clear()
	remedies_used = 0
	practice_rounds = 0
	checkpoint_total = _count_checkpoints(queue)
	checkpoint_seen = 0
	current_result = {}
	finished_module = false

func module_title() -> String:
	return str(module.get("title", "LESSON"))

func module_subtitle() -> String:
	return str(module.get("subtitle", ""))

func accent_color() -> Color:
	return Color.from_string(str(module.get("accent", "#78b4ff")), Color(0.47, 0.71, 1.0))

func intro_step() -> Dictionary:
	return module.get("intro", {})

# ===== Navigation =========================================================

func start() -> void:
	position = 0
	finished_module = false
	_announce_current()

func current() -> Dictionary:
	if finished() or queue.is_empty():
		return {}
	return queue[position]

func advance() -> bool:
	if finished():
		return false
	_reward_step_exit(current())
	position += 1
	if position >= queue.size():
		return _attempt_module_close()
	_announce_current()
	return true

func finished() -> bool:
	return finished_module or position >= queue.size()

func step_count() -> int:
	return queue.size()

func progress_text() -> String:
	if queue.is_empty():
		return "0 / 0"
	return "%d / %d" % [clampi(position + 1, 1, queue.size()), queue.size()]

func checkpoint_progress_text() -> String:
	if checkpoint_total <= 0:
		return "practice"
	return "checkpoint %d / %d" % [checkpoint_seen, maxi(checkpoint_total, checkpoint_seen)]

func current_is_checkpoint() -> bool:
	return str(current().get("kind", "")) == "checkpoint"

func current_checkpoint() -> Dictionary:
	if not current_is_checkpoint():
		return {}
	return current().get("checkpoint", {})

func needs_board() -> bool:
	return current_is_checkpoint() and Checkpoint.needs_board(current_checkpoint())

func needs_maze() -> bool:
	return current_is_checkpoint() and Checkpoint.needs_maze(current_checkpoint())

## Hint text for the current checkpoint (empty when there is none).
func current_hint() -> String:
	return Checkpoint.hint_of(current_checkpoint()) if current_is_checkpoint() else ""

func current_explain() -> String:
	return Checkpoint.explain_of(current_checkpoint()) if current_is_checkpoint() else ""

func current_prompt() -> String:
	var step := current()
	if step.is_empty():
		return ""
	if current_is_checkpoint():
		return Checkpoint.prompt_of(current_checkpoint())
	return str(step.get("title", ""))

## Quiet notification + narrator line whenever a step becomes current.
func _announce_current() -> void:
	var step := current()
	if step.is_empty():
		return
	if current_is_checkpoint():
		checkpoint_seen += 1
		var total := maxi(checkpoint_total, checkpoint_seen)
		checkpoint_reached.emit(step, checkpoint_seen, total)
		_speak("Checkpoint %d of %d. %s" % [checkpoint_seen, total, Checkpoint.prompt_of(current_checkpoint())])
	elif str(step.get("kind", "")) == "info":
		_speak(str(step.get("title", "")))
	step_changed.emit(step, position, queue.size())

func _speak(text: String) -> void:
	if voice != null and voice.has_method("speak"):
		voice.speak(text)

func _count_checkpoints(steps: Array) -> int:
	var total := 0
	for step in steps:
		if str(step.get("kind", "")) == "checkpoint":
			total += 1
	return total

# ===== Grading =============================================================

## Grade a response for the current checkpoint and apply every side effect:
## knowledge-tracer observation, XP/streak reward, remedy injection.
## The returned dictionary is what the UI should display.
func submit(response) -> Dictionary:
	if not current_is_checkpoint():
		return {}
	var cp := Checkpoint.normalize(current_checkpoint())
	var id := Checkpoint.id_of(cp)
	var result := Checkpoint.grade(cp, response)
	var correct := bool(result.get("correct", false))
	var misses := int(attempts.get(id, 0))
	if correct:
		var first_try := misses == 0
		if not first_try_ids.has(id):
			first_try_ids.append(id)
		solved[id] = true
		result["first_try"] = first_try
		result["resolved"] = true
		result["explain"] = Checkpoint.explain_of(cp)
		result["xp"] = _reward(correct, first_try, cp)
		_record(correct)
		_speak("Correct. %s" % Checkpoint.explain_of(cp))
		current_result = result
		checkpoint_graded.emit(result)
		checkpoint_solved.emit(id, first_try, int(result["xp"]))
		return result
	misses += 1
	attempts[id] = misses
	result["resolved"] = false
	result["first_try"] = false
	result["misses"] = misses
	result["hint"] = Checkpoint.hint_of(cp)
	result["xp"] = _reward(false, false, cp)
	# A long bad streak should not poison the model: record the first two misses
	# of a checkpoint, then stop counting until the learner gets it right.
	if misses <= 2:
		_record(false)
	_speak(str(result.get("message", "")))
	current_result = result
	checkpoint_graded.emit(result)
	checkpoint_failed.emit(id, misses, str(result["hint"]))
	_maybe_inject_remedy(cp)
	return result

## Show the answer without earning XP. Counted as a miss, then the learner
## advances themselves. Used by the "Reveal answer" button.
func reveal() -> Dictionary:
	if not current_is_checkpoint():
		return {}
	var cp := Checkpoint.normalize(current_checkpoint())
	var id := Checkpoint.id_of(cp)
	attempts[id] = int(attempts.get(id, 0)) + 1
	var result := {
		"correct": false,
		"revealed": true,
		"resolved": false,
		"first_try": false,
		"misses": int(attempts[id]),
		"message": "Answer revealed: %s" % Checkpoint.explain_of(cp),
		"explain": Checkpoint.explain_of(cp),
		"hint": Checkpoint.hint_of(cp),
		"xp": 0,
	}
	_record(false)
	current_result = result
	checkpoint_graded.emit(result)
	return result

## Feed exactly ONE graded observation to the knowledge tracer.
func _record(correct: bool) -> void:
	if tracer == null or skill == "":
		return
	if tracer.has_method("record_learning_observation"):
		tracer.record_learning_observation(skill, correct)
	elif tracer.has_method("record_observation"):
		tracer.record_observation(skill, correct)

## XP / streak reward. Whiteboard builds pay more than a choice question.
func _reward(correct: bool, first_try: bool, cp: Dictionary) -> int:
	if gamification == null:
		return 0
	var before_level := int(gamification.get_level())
	var event := {}
	if not correct:
		event = gamification.award_wrong()
	elif Checkpoint.kind_of(cp) == Checkpoint.KIND_BUILD:
		event = gamification.award_build()
	else:
		event = gamification.award_correct(mastery_pct())
	if correct and not first_try and event.has("xp_gain"):
		# Persistence still pays, but a solved-after-misses answer is worth half.
		var gain := int(event["xp_gain"])
		var halved := int(ceil(float(gain) * 0.5))
		gamification.total_xp += halved - gain
		event["xp_gain"] = halved
	if correct and int(gamification.get_level()) > before_level:
		level_up.emit({
			"level": gamification.get_level(),
			"title": gamification.get_level_title(),
			"streak": gamification.streak,
		})
	return int(event.get("xp_gain", 0))

## Insert the module's remedy panel in FRONT of the checkpoint the learner keeps
## missing, so the next step explains the idea and then re-asks the question.
func _maybe_inject_remedy(cp: Dictionary) -> bool:
	if remedies_used >= MAX_REMEDIES:
		return false
	var pool: Array = module.get("remedy", [])
	if pool.is_empty():
		return false
	var id := Checkpoint.id_of(cp)
	if int(attempts.get(id, 0)) < MISSES_BEFORE_REMEDY:
		return false
	var info_step: Dictionary = (pool[remedies_used % pool.size()] as Dictionary).duplicate(true)
	info_step["injected"] = true
	queue.insert(position, info_step)
	remedies_used += 1
	remediation_injected.emit(info_step, remedies_used)
	_speak("Let's take this slowly before trying again.")
	return true

## Sandbox time pays a little XP the moment the learner leaves it. Board tasks
## with a real task are graded (and rewarded) by the whiteboard instead, so they
## are intentionally NOT rewarded here.
func _reward_step_exit(step: Dictionary) -> void:
	if gamification == null or step.is_empty():
		return
	if str(step.get("kind", "")) == "freebuild":
		gamification.award_free_build()

# ===== Mastery, module close and reporting =================================

## Current mastery of the module's skill, as reported by the active model.
func mastery_pct() -> float:
	if tracer == null or skill == "":
		return 0.0
	if tracer.has_method("get_mastery_percentage"):
		return float(tracer.get_mastery_percentage(skill))
	if tracer.has_method("get_knowledge_probability"):
		return float(tracer.get_knowledge_probability(skill)) * 100.0
	return 0.0

## Mastery gate: an injected Callable wins, otherwise the tracer decides.
func is_mastered() -> bool:
	if not mastery_check.is_null() and mastery_check.is_valid():
		return bool(mastery_check.call(skill))
	if tracer != null and skill != "" and tracer.has_method("is_learned"):
		return bool(tracer.is_learned(skill))
	return false

## Called when the authored steps run out: either close the module or append one
## more round of practice checkpoints because the skill is not mastered yet.
func _attempt_module_close() -> bool:
	var pool: Array = module.get("practice", [])
	if pool.is_empty() or practice_rounds >= MAX_PRACTICE_ROUNDS or is_mastered():
		return _close_module()
	var count := mini(3, pool.size())
	var first_appended := queue.size()
	for index in count:
		var step: Dictionary = (pool[index % pool.size()] as Dictionary).duplicate(true)
		step["injected_practice"] = true
		var id := Checkpoint.id_of(step.get("checkpoint", {}))
		attempts.erase(id)
		queue.append(step)
	practice_rounds += 1
	position = first_appended
	practice_injected.emit(queue[position], practice_rounds, count)
	_speak("Not mastered yet - here is practice round %d." % practice_rounds)
	_announce_current()
	return true

func _close_module() -> bool:
	finished_module = true
	var summary := summary()
	if gamification != null:
		if gamification.has_method("award_challenge_finished"):
			var event: Dictionary = gamification.award_challenge_finished(float(summary["score"]))
			summary["xp"] = int(event.get("xp_gain", 0))
		if gamification.has_method("set_mastery") and skill != "":
			gamification.set_mastery(skill, mastery_pct())
		summary["level"] = gamification.get_level()
		summary["level_title"] = gamification.get_level_title()
		summary["streak"] = gamification.streak
	summary["mastery_pct"] = mastery_pct()
	summary["mastered"] = is_mastered()
	summary["headline"] = str(summary.get("headline", ""))
	module_finished.emit(summary)
	_speak("Module complete. %s" % summary["headline"])
	return false

## Gamified module score: first-try solves are worth 100%, retried solves 70%.
func score() -> float:
	if checkpoint_total <= 0:
		return 100.0
	var retried := maxi(solved.size() - first_try_ids.size(), 0)
	var points := float(first_try_ids.size()) * 100.0 + float(retried) * 70.0
	return clampf(points / float(checkpoint_total), 0.0, 100.0)

func total_misses() -> int:
	var misses := 0
	for id in attempts:
		misses += int(attempts[id])
	return misses

func summary() -> Dictionary:
	var score_value := score()
	var mastered := is_mastered()
	var headline := ""
	if mastered and score_value >= 95.0:
		headline = "FLAWLESS - skill mastered on the first pass!"
	elif mastered:
		headline = "Skill mastered!"
	elif score_value >= 70.0:
		headline = "Nearly there - one more practice round will lock it in."
	else:
		headline = "Keep going: the practice pool stays open."
	return {
		"skill": skill,
		"title": module_title(),
		"order": int(module.get("order", 0)),
		"checkpoints": checkpoint_total,
		"solved": solved.size(),
		"first_try": first_try_ids.size(),
		"misses": total_misses(),
		"remedies": remedies_used,
		"practice_rounds": practice_rounds,
		"score": score_value,
		"mastery_pct": mastery_pct(),
		"mastered": mastered,
		"headline": headline,
		"stars": stars_for(score_value, mastered),
	}

## 0..3 stars for the HUD: mastery first, then first-try quality.
static func stars_for(score_value: float, mastered: bool) -> int:
	if not mastered:
		return 1 if score_value >= 50.0 else 0
	if score_value >= 95.0:
		return 3
	return 2

static func stars_text(stars: int) -> String:
	return "*".repeat(clampi(stars, 0, 3)) + "-".repeat(clampi(3 - stars, 0, 3))
