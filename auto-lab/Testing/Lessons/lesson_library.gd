extends RefCounted
## Lesson registry — the ONE entry point the rest of the app reads lessons
## through. It holds no content itself: the authored DFA course lives in its
## own file, Testing/Lessons/dfa_lesson.gd, which is the DEFAULT (and currently
## only) topic of the adaptive system.
##
## WHY THIS SPLIT
##   * dfa_lesson.gd  = the DFA curriculum (machines, panels, checkpoints).
##     Edit that file to change lesson text, tasks or questions.
##   * lesson_library.gd (this file) = the stable API the engine, the rooms and
##     the tests call. Flow code never depends on WHICH topic answers.
##
## Adding a second topic later: write another <topic>_lesson.gd exposing the
## same static API, add it to topic_files(), and the registry loops below pick
## it up — no other file has to change.

const DfaLesson = preload("res://Testing/Lessons/dfa_lesson.gd")

## The authored topic files, in teaching order. DFA first: the thesis POC topic.
static func topic_files() -> Array:
	return [DfaLesson]

# ===== Modules and skills ===================================================

## All lesson modules across every topic, in teaching order.
static func modules() -> Array:
	var out: Array = []
	for topic in topic_files():
		out.append_array(topic.modules())
	return out

static func skills() -> Array[String]:
	var out: Array[String] = []
	for module in modules():
		out.append(str(module["skill"]))
	return out

## Module for one skill, or {} when the skill has no lesson yet.
static func get_module(skill: String) -> Dictionary:
	for topic in topic_files():
		var module: Dictionary = topic.get_module(skill)
		if not module.is_empty():
			return module
	return {}

static func get_title(skill: String) -> String:
	var module := get_module(skill)
	return str(module.get("title", skill.capitalize()))

## Lesson text uses the words Sigma and delta only in the first introduction.
## All later presentation surfaces use the standard Greek notation.
static func format_text(text: String, first_introduction := false) -> String:
	return DfaLesson.format_text(text, first_introduction)

# ===== Adaptive presentation (per skill) ====================================

## One field of the authored lesson text (objective / definition / example /
## application / guided), used by the adaptive lecture panels.
static func adaptive_text(skill: String, field: String) -> String:
	for topic in topic_files():
		var text: String = topic.adaptive_text(skill, field)
		if text != "":
			return text
	return ""

## The MULTIPLE-CHOICE practice items of one skill, as plain questions. An item
## may carry a "board" key: the machine the whiteboard should display while the
## learner answers it ("refer to the DFA on the board").
static func adaptive_questions(skill: String) -> Array:
	for topic in topic_files():
		var questions: Array = topic.adaptive_questions(skill)
		if not questions.is_empty():
			return questions
	return []

## A short, plain recap of one skill for the remediation screen.
static func recap(skill: String) -> String:
	return DfaLesson.recap(skill)

# ===== Guided course projection =============================================

## Course shape used by the Testing Grounds room: the authored lesson projected
## into content / demo / freebuild / practice steps, numbered with a one-line
## preview of what comes next.
static func course_steps() -> Array:
	var out: Array = []
	for topic in topic_files():
		out.append_array(topic.course_steps())
	return out

# ===== Challenge rounds (adaptive review) ===================================

## Every choice checkpoint a skill offers (practice pool first), as plain
## questions - the set a challenge round draws from. Items may carry a "board"
## key, same as adaptive_questions().
static func review_questions(skill: String) -> Array:
	for topic in topic_files():
		var questions: Array = topic.review_questions(skill)
		if not questions.is_empty():
			return questions
	return []

## The order a skill's questions should be asked in one round: missed items
## first; `targeted_only` keeps ONLY the missed items.
static func review_order(wrong: Array, total: int, targeted_only := false) -> Array:
	return DfaLesson.review_order(wrong, total, targeted_only)
 
# ===== Whiteboard tasks =====================================================

## Build tasks authored in the library, shared by every presentation.
static func workshop_tasks(skill: String) -> Array:
	for topic in topic_files():
		var tasks: Array = topic.workshop_tasks(skill)
		if not tasks.is_empty():
			return tasks
	return []
