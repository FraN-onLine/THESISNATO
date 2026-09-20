extends RefCounted
## One CHECKPOINT = one moment where the system evaluates the learner.
##
## This file is the single source of truth for checkpoint shape and grading, so
## new checkpoint kinds only have to be added here. Info panels never touch the
## knowledge-tracing probabilities - only graded checkpoints do.
##
## SCHEMA (every key is optional except the ones named per kind)
## {
##   "id":       "def_5tuple",        # unique inside a lesson module
##   "kind":     "mc" | "identify" | "trace" | "maze" | "build" | "composite",
##   "skill":    "definition",        # the skill that receives the update
##   "prompt":   "Which line shows ...",     # question / task text
##   "hint":     "Look for the order ...",   # offered after a miss
##   "explain":  "Q, Sigma, delta, q0, F ...",  # revealed once solved / after help
##   "attempts": 3,                   # misses before remediation is injected
##   "remediation": [ ...info steps... ],  # optional per-checkpoint help steps
##
##   mc / identify:  "options": ["A", "B"], "correct": 1
##   trace:          "spec": {DFA}, "input": "1010", "answer": "q2"
##   maze:           "spec": {DFA}, "escapes": 1, "objective": "Escape the maze"
##   build:          "task": {instruction, accept:[], reject:[]}
##   composite:      "parts": [ ...sub-checkpoints... ]   # all parts must pass
## }

const DfaModel = preload("res://Testing/Lessons/dfa_model.gd")

const KIND_MC := "mc"
const KIND_IDENTIFY := "identify"
const KIND_TRACE := "trace"
const KIND_MAZE := "maze"
const KIND_BUILD := "build"
const KIND_COMPOSITE := "composite"

const DEFAULT_ATTEMPTS := 3

# ===== Normalization =====

## Fills in defaults so the rest of the system never has to null-check.
static func normalize(checkpoint: Dictionary) -> Dictionary:
	var result := checkpoint.duplicate(true)
	if not result.has("kind"):
		result["kind"] = KIND_MC
	if not result.has("id"):
		result["id"] = "cp_%s" % str(result["kind"])
	if not result.has("skill"):
		result["skill"] = "definition"
	if not result.has("attempts"):
		result["attempts"] = DEFAULT_ATTEMPTS
	if not result.has("prompt"):
		result["prompt"] = ""
	if result["kind"] == KIND_COMPOSITE and result.has("parts"):
		var parts: Array = []
		for part in result["parts"]:
			parts.append(normalize(part))
		result["parts"] = parts
	return result

static func kind_of(checkpoint: Dictionary) -> String:
	return str(checkpoint.get("kind", KIND_MC))

static func skill_of(checkpoint: Dictionary) -> String:
	return str(checkpoint.get("skill", "definition"))

static func id_of(checkpoint: Dictionary) -> String:
	return str(checkpoint.get("id", "cp"))

static func prompt_of(checkpoint: Dictionary) -> String:
	return str(checkpoint.get("prompt", ""))

## True when answering requires the automata board (build / composite with build).
static func needs_board(checkpoint: Dictionary) -> bool:
	if kind_of(checkpoint) == KIND_BUILD:
		return true
	if kind_of(checkpoint) == KIND_COMPOSITE:
		for part in checkpoint.get("parts", []):
			if needs_board(part):
				return true
	return false

## True when the maze billboard must be shown for this checkpoint.
static func needs_maze(checkpoint: Dictionary) -> bool:
	if kind_of(checkpoint) == KIND_MAZE:
		return true
	if kind_of(checkpoint) == KIND_COMPOSITE:
		for part in checkpoint.get("parts", []):
			if needs_maze(part):
				return true
	return false

static func options_of(checkpoint: Dictionary) -> Array:
	return checkpoint.get("options", [])

static func correct_index_of(checkpoint: Dictionary) -> int:
	return int(checkpoint.get("correct", -1))

static func hint_of(checkpoint: Dictionary) -> String:
	return str(checkpoint.get("hint", ""))

static func explain_of(checkpoint: Dictionary) -> String:
	return str(checkpoint.get("explain", ""))

## Steps injected when the learner keeps missing this checkpoint.
static func remediation_of(checkpoint: Dictionary) -> Array:
	return checkpoint.get("remediation", [])

# ===== Grading =====
#
# grade() is pure: it never mutates the checkpoint and never touches the
# knowledge tracer. The lesson engine owns the side effects (recording the
# observation, deciding about remediation). `response` is whatever the UI sent:
#   mc / identify -> int (chosen option index)
#   trace         -> String (state the learner believes the machine ends in)
#   maze          -> {"escaped": bool, "path": String, "final": String}
#   build         -> {"correct": bool, "message": String} straight from the board
#   composite     -> Array of responses, index-aligned with "parts"

static func grade(checkpoint: Dictionary, response) -> Dictionary:
	var cp := normalize(checkpoint)
	match kind_of(cp):
		KIND_MC, KIND_IDENTIFY:
			return _grade_choice(cp, response)
		KIND_TRACE:
			return _grade_trace(cp, response)
		KIND_MAZE:
			return _grade_maze(cp, response)
		KIND_BUILD:
			return _grade_board(cp, response)
		KIND_COMPOSITE:
			return _grade_composite(cp, response)
	return {"correct": false, "message": "Unknown checkpoint kind '%s'." % kind_of(cp), "detail": {}}

static func _grade_choice(cp: Dictionary, response) -> Dictionary:
	var chosen := int(response)
	var correct := chosen == correct_index_of(cp)
	var detail := {"chosen": chosen, "expected": correct_index_of(cp)}
	if chosen < 0:
		return {"correct": false, "message": "Pick one of the options first.", "detail": detail}
	if correct:
		return {"correct": true, "message": "Correct.", "detail": detail}
	return {"correct": false, "message": "That is not the one. Re-read the options and try again.", "detail": detail}

static func _grade_trace(cp: Dictionary, response) -> Dictionary:
	var spec: Dictionary = cp.get("spec", {})
	var input_value := str(cp.get("input", ""))
	var expected := str(cp.get("answer", ""))
	var result := DfaModel.trace(spec, input_value)
	if expected == "":
		expected = str(result.get("final", ""))
	var given := str(response).strip_edges()
	var correct := given.to_lower() == expected.to_lower()
	var detail := {"expected": expected, "given": given, "trace": result}
	if correct:
		return {"correct": true, "message": DfaModel.format_trace(result, input_value), "detail": detail}
	var reached: Array = result.get("path", [])
	var partial := "Start -> %s" % str(reached[0]) if not reached.is_empty() else "Start"
	return {
		"correct": false,
		"message": "Not there yet. Walk it one symbol at a time: %s ... where does it stop?" % partial,
		"detail": detail,
	}

static func _grade_maze(cp: Dictionary, response) -> Dictionary:
	if not response is Dictionary:
		return {"correct": false, "message": "Walk the maze to answer this one.", "detail": {}}
	var escaped := bool(response.get("escaped", false))
	var path := str(response.get("path", ""))
	var spec: Dictionary = cp.get("spec", {})
	var traversed := DfaModel.trace(spec, path)
	var correct := escaped and bool(traversed.get("accepted", false))
	var detail := {"path": path, "escaped": escaped, "final": str(traversed.get("final", ""))}
	if correct:
		return {"correct": true, "message": "Escaped with '%s' - that string is accepted." % path, "detail": detail}
	return {
		"correct": false,
		"message": "You did not reach the exit with an accepted string. Try a different route.",
		"detail": detail,
	}

static func _grade_board(cp: Dictionary, response) -> Dictionary:
	if not response is Dictionary:
		return {"correct": false, "message": "Build the machine on the board, then press Check task.", "detail": {}}
	var correct := bool(response.get("correct", false))
	return {
		"correct": correct,
		"message": str(response.get("message", "Checked on the board.")),
		"detail": {"board": response},
	}

static func _grade_composite(cp: Dictionary, response) -> Dictionary:
	var parts: Array = cp.get("parts", [])
	if not response is Array or response.size() < parts.size():
		return {"correct": false, "message": "Answer every part of this checkpoint.", "detail": {}}
	var messages: Array[String] = []
	var all_correct := true
	for index in range(parts.size()):
		var part_result := grade(parts[index], response[index])
		if not bool(part_result.get("correct", false)):
			all_correct = false
		messages.append("Part %d: %s" % [index + 1, str(part_result.get("message", ""))])
	return {"correct": all_correct, "message": "\n".join(messages), "detail": {}}

# ===== Authoring helpers =====

## Human-readable explanation of the schema, shown in the lesson editor view.
static func schema_help() -> String:
	return "Checkpoint kinds: mc, identify, trace, maze, build, composite.\n" + \
		"mc/identify need options + correct. trace needs spec + input (+ optional answer).\n" + \
		"maze needs spec (+ escapes). build needs task {instruction, accept, reject}.\n" + \
		"composite needs parts (all must pass). Every checkpoint updates ONE skill."

