extends RefCounted
## Pure-data Deterministic Finite Automaton (DFA) used by lesson checkpoints.
##
## AUTHORING FORMAT (a "spec" is a plain Dictionary, so lessons stay editable):
##   {
##       "states":    ["q0", "q1"],
##       "alphabet":  ["a", "b"],
##       "start":     "q0",
##       "accepting": ["q1"],
##       "transitions": {"q0|a": "q1", "q0|b": "q0", "q1|a": "q1", "q1|b": "q0"},
##   }
##
## Transitions are keyed "<state>|<symbol>" so a spec stays short and readable.
## A DFA has no epsilon moves by definition, so EPSILON is rejected by validate().
##
## Everything here is static and side-effect free: checkpoints, the maze panel
## and the grader all trace strings through the same code path.

const EPSILON := "ε"
const KEY_SEPARATOR := "|"

# ===== Construction =====

## Builds a spec from parts. Useful for generated machines in checkpoints.
static func make(states: Array, alphabet: Array, start: String, accepting: Array, transitions: Dictionary) -> Dictionary:
	return {
		"states": states.duplicate(),
		"alphabet": alphabet.duplicate(),
		"start": start,
		"accepting": accepting.duplicate(),
		"transitions": transitions.duplicate(),
	}

## Transition-table key for one state/symbol pair.
static func key(state: String, symbol: String) -> String:
	return state + KEY_SEPARATOR + symbol

# ===== Reading a spec =====

static func states_of(spec: Dictionary) -> Array:
	return spec.get("states", [])

static func alphabet_of(spec: Dictionary) -> Array:
	return spec.get("alphabet", [])

static func start_of(spec: Dictionary) -> String:
	return str(spec.get("start", ""))

static func accepting_of(spec: Dictionary) -> Array:
	return spec.get("accepting", [])

static func transitions_of(spec: Dictionary) -> Dictionary:
	return spec.get("transitions", {})

static func is_accepting(spec: Dictionary, state: String) -> bool:
	return accepting_of(spec).has(state)

## Next state for `symbol` at `state`, or "" when the machine is stuck.
static func delta(spec: Dictionary, state: String, symbol: String) -> String:
	var table: Dictionary = transitions_of(spec)
	var target = table.get(key(state, symbol), "")
	return str(target)

## Outcome of running `input_value` through the machine.
## Returns {ok, accepted, final, path, error}. `path` includes the start state,
## so a 3-symbol walk yields 4 entries - exactly what a learner would write down.
static func trace(spec: Dictionary, input_value: String) -> Dictionary:
	var state := start_of(spec)
	if state == "":
		return {"ok": false, "accepted": false, "final": "", "path": [], "error": "This machine has no start state."}
	var path: Array[String] = [state]
	for symbol in input_value.split("", false):
		var next := delta(spec, state, symbol)
		if next == "":
			return {
				"ok": true,
				"accepted": false,
				"final": state,
				"path": path,
				"error": "No transition from %s on '%s' - the machine stops, so the string is rejected." % [state, symbol],
			}
		state = next
		path.append(state)
	return {"ok": true, "accepted": is_accepting(spec, state), "final": state, "path": path, "error": ""}

## Convenience wrapper: does this machine accept `input_value`?
static func accepts(spec: Dictionary, input_value: String) -> bool:
	var result := trace(spec, input_value)
	return bool(result.get("accepted", false))


# ===== Well-formedness (this is what "is this a valid DFA?" questions test) =====

## State/symbol pairs that have no transition (a complete DFA has none).
static func missing_transitions(spec: Dictionary) -> Array[String]:
	var missing: Array[String] = []
	var table: Dictionary = transitions_of(spec)
	for state in states_of(spec):
		for symbol in alphabet_of(spec):
			var lookup := key(str(state), str(symbol))
			if not table.has(lookup):
				missing.append(lookup)
	return missing

static func is_total(spec: Dictionary) -> bool:
	return missing_transitions(spec).is_empty()

## Checks a spec against the definition of a DFA.
## Returns {ok, errors: Array[String], warnings: Array[String]}.
static func validate(spec: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var states: Array = states_of(spec)
	var alphabet: Array = alphabet_of(spec)
	var start := start_of(spec)
	var accepting: Array = accepting_of(spec)
	var table: Dictionary = transitions_of(spec)

	if states.is_empty():
		errors.append("Q (the set of states) is empty.")
	if alphabet.is_empty():
		errors.append("Sigma (the input alphabet) is empty.")
	if start == "":
		errors.append("There is no start state q0.")
	elif not states.has(start):
		errors.append("Start state '%s' is not part of Q." % start)
	for state in accepting:
		if not states.has(state):
			errors.append("Accepting state '%s' is not part of Q." % str(state))
	if accepting.is_empty():
		warnings.append("F is empty: the machine accepts nothing. Legal, but rarely intended.")

	# Determinism: one target per (state, symbol) pair, and every symbol in Sigma.
	for raw_key in table.keys():
		var parts := str(raw_key).split(KEY_SEPARATOR, false)
		if parts.size() != 2:
			errors.append("Transition key '%s' must be written as state|symbol." % str(raw_key))
			continue
		if not states.has(parts[0]):
			errors.append("Transition '%s' starts at a state that is not in Q." % str(raw_key))
		if not alphabet.has(parts[1]):
			errors.append("Transition '%s' uses a symbol outside Sigma." % str(raw_key))
		var target := str(table[raw_key])
		if not states.has(target):
			errors.append("Transition '%s' points to '%s', which is not in Q." % [str(raw_key), target])
	for missing in missing_transitions(spec):
		warnings.append("Missing transition %s (not a complete DFA)." % missing)
	return {"ok": errors.is_empty(), "errors": errors, "warnings": warnings}

# ===== Teaching helpers =====

## Short strings split into accepted / rejected sets, used to show learners why a
## machine matches a language. `max_length` keeps the sample list readable.
static func sample_strings(spec: Dictionary, max_length: int = 3, limit: int = 6) -> Dictionary:
	var accepted: Array[String] = []
	var rejected: Array[String] = []
	var alphabet: Array = alphabet_of(spec)
	var frontier: Array[String] = [""]
	for _depth in range(max_length):
		var next_frontier: Array[String] = []
		for prefix in frontier:
			for symbol in alphabet:
				var candidate: String = prefix + str(symbol)
				next_frontier.append(candidate)
				if accepts(spec, candidate):
					if accepted.size() < limit:
						accepted.append(candidate)
				elif rejected.size() < limit:
					rejected.append(candidate)
		frontier = next_frontier
	return {"accept": accepted, "reject": rejected}

## The 5-tuple of a spec as lesson-ready text.
static func describe(spec: Dictionary) -> String:
	return "Q = {%s}\nSigma = {%s}\nq0 = %s\nF = {%s}\nDelta = %d transitions" % [
		", ".join(_as_strings(states_of(spec))),
		", ".join(_as_strings(alphabet_of(spec))),
		start_of(spec),
		", ".join(_as_strings(accepting_of(spec))),
		transitions_of(spec).size(),
	]

## Pretty multi-line trace, e.g. "q0 --a--> q1 --b--> q1 | Result: ACCEPTED".
static func format_trace(result: Dictionary, input_value: String) -> String:
	var path: Array = result.get("path", [])
	if path.is_empty():
		return "No trace available."
	var symbols: Array = input_value.split("", false)
	var pieces: Array[String] = []
	for index in range(path.size()):
		if index == 0:
			pieces.append(str(path[index]))
		else:
			pieces.append("--%s--> %s" % [str(symbols[index - 1]), str(path[index])])
	var verdict := "ACCEPTED" if bool(result.get("accepted", false)) else "REJECTED"
	return "%s\nResult: %s" % [" ".join(pieces), verdict]

static func _as_strings(values: Array) -> Array[String]:
	var out: Array[String] = []
	for value in values:
		out.append(str(value))
	return out
