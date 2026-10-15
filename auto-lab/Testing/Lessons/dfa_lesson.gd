extends RefCounted
## THE DFA LESSON — the whole authored DFA course, separated from the engine.
##
## This file is the DEFAULT topic of the adaptive system and is meant to be
## edited by hand. Navigation, grading and presentation never live here; the
## rest of the app reads this content through Testing/Lessons/lesson_library.gd
## (the thin registry that forwards to this file), so lesson text can change
## without touching any flow code.
##
## HOW TO EDIT:
##   * Each entry of modules() is ONE skill module: an intro panel, a list of
##     steps, plus two reusable pools:
##         "remedy"   -> info panels injected when the learner keeps missing
##         "practice" -> extra checkpoints appended until the skill is mastered
##   * A step is either
##         {"kind": "info",      ...}      a text/information panel,
##         {"kind": "board",     ...}      the automata whiteboard with a task,
##         {"kind": "freebuild", ...}      the whiteboard with no task at all,
##         {"kind": "checkpoint", ...}     something the system GRADES.
##   * Only graded checkpoints update the knowledge-tracing probabilities
##     (BKT P(L0) / HMM Pi / KST state). Info panels never do.
##   * Checkpoint shapes live in Testing/Lessons/checkpoint.gd.
##   * A multiple-choice checkpoint may carry a "board" spec (one of the
##     reusable machines below): the question then shows that machine on the
##     whiteboard and asks the learner to read it (see _mc's `board` argument).

const DfaModel = preload("res://Testing/Lessons/dfa_model.gd")

# ===== Reusable machines (referenced by checkpoints and the maze) ============

## Accepts strings over {a,b} that END with 'a'.
const DFA_ENDS_A := {
	"states": ["q0", "q1"], "alphabet": ["a", "b"], "start": "q0", "accepting": ["q1"],
	"transitions": {"q0|a": "q1", "q0|b": "q0", "q1|a": "q1", "q1|b": "q0"},
}

## Accepts strings over {0,1} that END with '01'.
const DFA_ENDS_01 := {
	"states": ["q0", "q1", "q2"], "alphabet": ["0", "1"], "start": "q0", "accepting": ["q2"],
	"transitions": {
		"q0|0": "q1", "q0|1": "q0",
		"q1|0": "q1", "q1|1": "q2",
		"q2|0": "q1", "q2|1": "q0",
	},
}

## Accepts strings over {0,1} that CONTAIN '00'.
const DFA_CONTAINS_00 := {
	"states": ["q0", "q1", "q2"], "alphabet": ["0", "1"], "start": "q0", "accepting": ["q2"],
	"transitions": {
		"q0|0": "q1", "q0|1": "q0",
		"q1|0": "q2", "q1|1": "q0",
		"q2|0": "q2", "q2|1": "q2",
	},
}

## Accepts strings over {0,1} with an EVEN number of 1s (includes the empty string).
const DFA_EVEN_ONES := {
	"states": ["even", "odd"], "alphabet": ["0", "1"], "start": "even", "accepting": ["even"],
	"transitions": {"even|0": "even", "even|1": "odd", "odd|0": "odd", "odd|1": "even"},
}

## Accepts one or more a's over {a,b}.
const DFA_A_PLUS := {
	"states": ["q0", "q1", "dead"], "alphabet": ["a", "b"], "start": "q0", "accepting": ["q1"],
	"transitions": {
		"q0|a": "q1", "q0|b": "dead",
		"q1|a": "q1", "q1|b": "dead",
		"dead|a": "dead", "dead|b": "dead",
	},
}

## Accepts the list {ab, aab, aaab, ...} = one or more a's then one b.
const DFA_A_PLUS_B := {
	"states": ["q0", "q1", "ok", "dead"], "alphabet": ["a", "b"], "start": "q0", "accepting": ["ok"],
	"transitions": {
		"q0|a": "q1", "q0|b": "dead",
		"q1|a": "q1", "q1|b": "ok",
		"ok|a": "dead", "ok|b": "dead",
		"dead|a": "dead", "dead|b": "dead",
	},
}

## Accepts the list {b, ab, aab, ...} = zero or more a's then exactly one b.
const DFA_A_STAR_B := {
	"states": ["q0", "q1", "ok", "dead"], "alphabet": ["a", "b"], "start": "q0", "accepting": ["ok"],
	"transitions": {
		"q0|a": "q1", "q0|b": "ok",
		"q1|a": "q1", "q1|b": "ok",
		"ok|a": "dead", "ok|b": "dead",
		"dead|a": "dead", "dead|b": "dead",
	},
}

## The examples give '00' and '01' only: an NFA, used to teach identification.
const NFA_NOT_A_DFA := {
	"states": ["q0", "q1", "q2"], "alphabet": ["0", "1"], "start": "q0", "accepting": ["q2"],
	"transitions": {"q0|0": "q1", "q0|0->q2": "q2", "q1|1": "q2"},
	"note": "q0 has TWO transitions on '0' (to q1 and to q2) and no transition on '1'.",
}

# ===== Step builders (keep the curriculum below short and readable) =========

## A text / information panel. `points` become bullet lines.
static func _info(title: String, body: String, points: Array = [], callout := "") -> Dictionary:
	return {"kind": "info", "title": title, "body": body, "points": points, "callout": callout}

## The automata whiteboard with a build task. `seed` shows a ready-made machine.
static func _board(title: String, explain: String, task: Dictionary) -> Dictionary:
	return {"kind": "board", "title": title, "explain": explain, "task": task}

## The automata whiteboard with no task: pure sandbox time.
static func _freebuild(title: String, subtitle: String) -> Dictionary:
	return {"kind": "freebuild", "title": title, "subtitle": subtitle}

static func _checkpoint(checkpoint: Dictionary) -> Dictionary:
	return {"kind": "checkpoint", "checkpoint": checkpoint}

## Multiple choice (also used for "identify this diagram" style items).
static func _mc(id: String, prompt: String, options: Array, correct: int, explain := "", hint := "") -> Dictionary:
	return _checkpoint({
		"id": id, "kind": "mc", "prompt": prompt, "options": options,
		"correct": correct, "explain": explain, "hint": hint,
	})

## WHITEBOARD-REFERENCED multiple choice: the given machine spec is loaded on
## the whiteboard (display-only) and the prompt tells the learner to READ it -
## "Refer to the DFA on the whiteboard: which state is accepting?". The room
## only shows the board when a question carries this "board" key.
static func _mc_board(id: String, prompt: String, board: Dictionary, options: Array, correct: int, explain := "", hint := "") -> Dictionary:
	var step := _mc(id, prompt, options, correct, explain, hint)
	step["checkpoint"]["board"] = board
	return step

## Trace a string through a machine and answer with the state it stops in.
static func _trace(id: String, prompt: String, spec: Dictionary, input_value: String, answer: String, explain := "", hint := "") -> Dictionary:
	return _checkpoint({
		"id": id, "kind": "trace", "prompt": prompt, "spec": spec,
		"input": input_value, "answer": answer, "explain": explain, "hint": hint,
	})

## Hand-held visual task: walk the machine like a maze and escape.
static func _maze(id: String, objective: String, spec: Dictionary, escapes: int = 1, explain := "", hint := "") -> Dictionary:
	return _checkpoint({
		"id": id, "kind": "maze", "prompt": objective, "objective": objective,
		"spec": spec, "escapes": escapes, "explain": explain, "hint": hint,
	})

## Board task graded by the whiteboard itself (accept/reject string lists).
static func _build(id: String, prompt: String, instruction: String, accept: Array, reject: Array, explain := "", hint := "", seed := false) -> Dictionary:
	return _checkpoint({
		"id": id, "kind": "build", "prompt": prompt, "explain": explain, "hint": hint,
		"task": {"instruction": instruction, "accept": accept, "reject": reject, "seed": seed},
	})

# ===== Module registry ======================================================

static var _cache: Array = []

## All lesson modules in teaching order. Cached because the builders are pure.
static func modules() -> Array:
	if _cache.is_empty():
		_cache = [
			_module_definition(),
			_module_identification(),
			_module_simulation(),
			_module_building(),
			_module_set_builder(),
			_module_list(),
		]
		for module_index in _cache.size():
			var module: Dictionary = _cache[module_index]
			var first_step: Dictionary = {}
			var steps: Array = module.get("steps", [])
			if module_index == 0 and not steps.is_empty():
				first_step = steps[0].duplicate(true)
			module = _normalize_text_tree(module)
			if not first_step.is_empty():
				module["steps"][0] = first_step
			_cache[module_index] = module
	return _cache

static func _normalize_text_tree(value):
	if value is String:
		return format_text(value)
	if value is Dictionary:
		var normalized: Dictionary = {}
		for key in value:
			normalized[key] = _normalize_text_tree(value[key])
		return normalized
	if value is Array:
		var normalized_array: Array = []
		for item in value:
			normalized_array.append(_normalize_text_tree(item))
		return normalized_array
	return value

static func skills() -> Array[String]:
	var out: Array[String] = []
	for module in modules():
		out.append(str(module["skill"]))
	return out

## Module for one skill, or {} when the skill has no lesson yet.
static func get_module(skill: String) -> Dictionary:
	for module in modules():
		if str(module["skill"]) == skill:
			return module
	return {}

static func get_title(skill: String) -> String:
	var module := get_module(skill)
	return str(module.get("title", skill.capitalize()))

## Lesson text uses the words Sigma and delta only in the first introduction.
## All later presentation surfaces use the standard Greek notation.
static func format_text(text: String, first_introduction := false) -> String:
	if first_introduction:
		return text
	return text.replace("Sigma", "Σ").replace("sigma", "σ").replace("delta", "δ")

static func _info_steps(skill: String) -> Array:
	var result: Array = []
	for step in get_module(skill).get("steps", []):
		if str(step.get("kind", "")) == "info":
			result.append(step)
	return result

static func adaptive_text(skill: String, field: String) -> String:
	var module := get_module(skill)
	var info_steps: Array = _info_steps(skill)
	if field == "objective":
		return format_text(str(module.get("intro", {}).get("body", "")), true)
	if info_steps.is_empty():
		return ""
	var index := 0
	match field:
		"definition":
			index = 0
		"example":
			index = mini(1, info_steps.size() - 1)
		"application":
			for i in info_steps.size():
				if "REAL LIFE" in str(info_steps[i].get("title", "")):
					index = i
					break
		"guided":
			index = mini(2, info_steps.size() - 1)
	var step: Dictionary = info_steps[index]
	var body := str(step.get("body", ""))
	var points: Array = step.get("points", [])
	if not points.is_empty():
		body += "\n\n" + "\n".join(points)
	if str(step.get("callout", "")) != "":
		body += "\n\n" + str(step["callout"])
	return format_text(body)

static func adaptive_questions(skill: String) -> Array:
	var result: Array = []
	for step in get_module(skill).get("practice", []):
		var checkpoint: Dictionary = step.get("checkpoint", {})
		if str(checkpoint.get("kind", "")) != "mc":
			continue
		result.append({
			"question": format_text(str(checkpoint.get("prompt", ""))),
			"options": checkpoint.get("options", []).duplicate(),
			"correct": int(checkpoint.get("correct", 0)),
			"explanation": format_text(str(checkpoint.get("explain", ""))),
			# Empty when the question is not board-referenced; the room then
			# behaves exactly as before.
			"board": checkpoint.get("board", {}),
		})
	return result

## Legacy course shape used by Testing Grounds' panel controller. The lesson
## data remains authored here; the controller only consumes the projected view.
##
## EASY TO FOLLOW BY CONSTRUCTION: a "content" step is projected as SEPARATE
## parts (lead paragraph / key points / callout) plus the step number and a
## one-line preview of what comes next, so the panel can lay it out in labelled
## sections instead of one wall of text. `body` is still filled in (same parts,
## joined) for any consumer that wants the flat string.
static func course_steps() -> Array:
	var out: Array = []
	for module in modules():
		var skill := str(module.get("skill", ""))
		var topic := str(module.get("title", skill))
		for source_step in module.get("steps", []):
			var kind := str(source_step.get("kind", ""))
			if kind == "info":
				# Sigma/delta stay spelled out only in the very first panel; every
				# later surface uses the standard Greek notation.
				var first_introduction := skill == "definition" and out.is_empty()
				var lead := format_text(str(source_step.get("body", "")), first_introduction)
				var points: Array = []
				for point in source_step.get("points", []):
					points.append("•  " + format_text(str(point), first_introduction))
				var callout := format_text(str(source_step.get("callout", "")), first_introduction)
				out.append({
					"m": "content", "skill": skill, "field": "library",
					"topic": topic,
					"title": str(source_step.get("title", topic)),
					"subtitle": str(module.get("subtitle", "")),
					"lead": lead,
					"points": points,
					"callout": callout,
					"body": _join_content(lead, points, callout),
				})
			elif kind == "board":
				out.append({
					"m": "demo", "skill": skill, "topic": topic,
					"title": str(source_step.get("title", "WHITEBOARD")),
					"explain": str(source_step.get("explain", "")),
					"task": source_step.get("task", {}),
				})
			elif kind == "freebuild":
				out.append({
					"m": "freebuild", "skill": skill, "topic": topic,
					"title": str(source_step.get("title", "FREE BUILD")),
					"subtitle": str(source_step.get("subtitle", "")),
				})
		out.append({
			"m": "practice", "skill": skill, "topic": topic,
			"title": "PRACTICE | %s" % str(module.get("title", skill)),
		})
	# Second pass: number every step and pre-announce the next one, so the panel
	# can always answer "where am I?" and "what is coming?".
	for index in out.size():
		var entry: Dictionary = out[index]
		entry["step_no"] = index + 1
		entry["step_total"] = out.size()
		var next_title := ""
		if index + 1 < out.size():
			next_title = str((out[index + 1] as Dictionary).get("title", ""))
		entry["next_title"] = next_title
		out[index] = entry
	return out

## Flat text of a content step: the lead paragraph, then the key points, then
## the callout. Used both for the projected `body` and by the adaptive screens.
static func _join_content(lead: String, points: Array, callout: String) -> String:
	var parts: Array[String] = []
	if lead != "":
		parts.append(lead)
	if not points.is_empty():
		parts.append("\n".join(points))
	if callout != "":
		parts.append(callout)
	return "\n\n".join(parts)

## A short, plain recap of one skill, used by the adaptive remediation screen.
## Pulls the module's own intro + remedy bullets so the re-explanation always
## matches the authored lesson instead of a hard-coded string.
static func recap(skill: String) -> String:
	var module := get_module(skill)
	if module.is_empty():
		return ""
	var lines: Array[String] = []
	var intro: Dictionary = module.get("intro", {})
	var intro_body := str(intro.get("body", ""))
	if intro_body != "":
		lines.append(intro_body)
	for remedy_step in module.get("remedy", []):
		for point in (remedy_step as Dictionary).get("points", []):
			lines.append("•  " + str(point))
	return "\n\n".join(lines)

## Every MULTIPLE-CHOICE checkpoint a module offers, as plain questions.
##
## `adaptive_questions` reads only the practice pool, which for some skills is a
## single item. The adaptive remediation needs a wider set of "areas" to re-ask,
## so this also collects the choice checkpoints authored inside the lesson steps
## (traps, rejection rules, notation reading...). Practice-pool items come first
## so the normal round is unchanged, and ids are de-duplicated.
static func review_questions(skill: String) -> Array:
	var out: Array = []
	var seen: Array = []
	var module := get_module(skill)
	if module.is_empty():
		return out
	for pool_key in ["practice", "steps"]:
		for step in module.get(pool_key, []):
			var checkpoint: Dictionary = step.get("checkpoint", {})
			if str(checkpoint.get("kind", "")) != "mc":
				continue
			var id := str(checkpoint.get("id", ""))
			if id != "" and seen.has(id):
				continue
			seen.append(id)
			out.append({
				"id": id,
				"question": format_text(str(checkpoint.get("prompt", ""))),
				"options": (checkpoint.get("options", []) as Array).duplicate(),
				"correct": int(checkpoint.get("correct", 0)),
				"explanation": format_text(str(checkpoint.get("explain", ""))),
				# Machine to display on the whiteboard while this question is
				# asked ({} = no board; the question works like before).
				"board": checkpoint.get("board", {}),
			})
	return out

## The order a skill's questions should be asked in one round.
##
## Missed items always come first - that is the whole point of the adaptive
## re-ask. `targeted_only` keeps ONLY the missed items, so a re-ask round spends
## its time on the areas the learner actually failed. With nothing missed yet,
## the full set comes back in its natural order.
static func review_order(wrong: Array, total: int, targeted_only := false) -> Array:
	var order: Array = []
	for entry in wrong:
		var index := int(entry)
		if index >= 0 and index < total and not order.has(index):
			order.append(index)
	if targeted_only and not order.is_empty():
		return order
	for index in total:
		if not order.has(index):
			order.append(index)
	return order

## Build tasks are authored in the library and shared by every presentation.
static func workshop_tasks(skill: String) -> Array:
	var out: Array = []
	var module := get_module(skill)
	for step in module.get("steps", []):
		if str(step.get("kind", "")) != "checkpoint":
			continue
		var checkpoint: Dictionary = step.get("checkpoint", {})
		if str(checkpoint.get("kind", "")) == "build":
			var task: Dictionary = checkpoint.get("task", {}).duplicate(true)
			task["title"] = str(checkpoint.get("prompt", "BUILD"))
			out.append(task)
	return out

# ===== 1. DFA DEFINITION AND PARTS =========================================

static func _module_definition() -> Dictionary:
	var steps: Array = []
	steps.append(_info(
		"WHAT IS A DFA?",
		"A Deterministic Finite Automaton reads one symbol at a time, moves along labelled arrows, and accepts or rejects when the string ends.",
		[
			"States (Q) — circles; start has an incoming arrow; accepting states use a double circle (F).",
			"Alphabet (Sigma) — symbols on the arrows.",
			"Deterministic — exactly one arrow per symbol from each state.",
		],
		"Formal name: 5-tuple (Q, Sigma, delta, q0, F). On the diagram you mainly read states, start, accept, and arrows."
	))
	steps.append(_mc("def_parts_1", "Which tuple lists the five standard parts of a finite automaton?",
		["(Q, Σ, δ, q0, F)", "(Q, delta, F, Sigma, q)", "(Sigma, q0, F, S, delta)", "(Q, Sigma, S, delta, q1)"],
		0,
		"(Q, Sigma, delta, q0, F): states, alphabet, moves, start, accepting states.",
		"Alphabet second, moves third, start fourth, finals last."))
	steps.append(_mc("def_parts_2", "What does a double circle on a state mean?",
		["It is the start state", "It is in the accepting set F", "It is a trap state", "The alphabet is empty"],
		1,
		"Double circle = accepting (final) state.",
		"Start uses an arrow from nowhere, not a double ring."))
	steps.append(_mc("def_parts_3", "Two arrows labelled 'a' leave the same state to different targets. What is wrong for a DFA?",
		["Nothing — that is normal", "The machine is not deterministic", "F must be empty", "Sigma must be {a}"],
		1,
		"A DFA allows only one next state per (state, symbol).",
		"Deterministic = one outcome per symbol."))
	return _finish_definition(steps)

## Second half of module 1: the whiteboard demo, real-life panel and the
## reusable remedy / practice pools.
static func _finish_definition(steps: Array) -> Dictionary:

	return {
		"skill": "definition",
		"order": 1,
		"title": "DFA BASICS",
		"subtitle": "States, alphabet, start, accept — read a diagram.",
		"accent": "#78b4ff",
		"intro": _info(
			"TOPIC 1 — DFA BASICS",
			"A DFA accepts or rejects a whole string by walking one symbol at a time. All it remembers is which state it is in now.",
			[
				"One arrow per (state, symbol).",
				"Accept iff you stop in an accepting state.",
			],
			"Learn to read the picture first; formal notation comes later."
		),
		"steps": steps,
		"remedy": [
			_info(
				"READ THE DIAGRAM",
				"Circle = state. Arrow from nowhere = start. Double circle = accept. Label on arrow = symbol read.",
				[
					"List states and which are accepting.",
					"From each state, count arrows per symbol — must be exactly one for a DFA.",
				],
				"Use the whiteboard: toggle accepting on a state and watch the double ring."
			),
		],
		"practice": [
			_mc("def_practice_1", "In the 5-tuple (Q, Sigma, delta, q0, F), which part may legally be empty?",
				["Q", "Sigma", "F", "q0"],
				2,
				"F may be empty: such a DFA simply accepts nothing. Q, Sigma and q0 must exist.",
				"Which one is a subset that could have zero members?"),
			_mc("def_practice_2", "A diagram shows state q1 with two arrows labelled 'a' to different states. What is wrong?",
				["Nothing - that is normal for a DFA", "delta is not deterministic", "F is missing a state", "The alphabet is empty"],
				1,
				"A DFA allows only one transition per (state, symbol) pair. Two 'a' arrows from q1 make it non-deterministic.",
				"Deterministic means exactly one outcome per symbol."),
			_trace("def_practice_3", "Using the machine over {a,b} that accepts strings ending in 'a', where does the run for 'abba' stop?",
				DFA_ENDS_A, "abba", "q1",
				"q0 --a--> q1 --b--> q0 --b--> q0 --a--> q1. The run ends in q1, which is in F, so 'abba' is accepted.",
				"One arrow per symbol, never skip a symbol."),
			_mc_board("def_board_1", "Refer to the DFA on the whiteboard. Which state is the ACCEPTING (final) state?",
				DFA_ENDS_A,
				["q0", "q1", "Both q0 and q1", "Neither — there is no accepting state"],
				1,
				"On the board, q1 is drawn with the double circle, so q1 is in F. A run that stops in q1 accepts the string.",
				"Accepting states are drawn with a double circle — find the double ring."),
		],
	}

# ===== 2. IDENTIFICATION OF DIAGRAM ========================================

## Checkpoint with a diagram attached (images live under the topic folder, e.g. res://Images/dfa/).
static func _mc_img(id: String, prompt: String, image: String, options: Array, correct: int, explain := "", hint := "") -> Dictionary:
	var step := _mc(id, prompt, options, correct, explain, hint)
	step["checkpoint"]["image"] = image
	return step

static func _module_identification() -> Dictionary:
	var steps: Array = []
	steps.append(_info(
		"IS IT A DFA?",
		"Classify from the drawing only — check arrows, do not run the string yet.",
		[
			"DFA: exactly one outgoing arrow per symbol from each state; no epsilon arrows.",
			"NFA: duplicate labels or missing symbols from a state.",
			"epsilon-NFA: arrows labelled epsilon (no input consumed).",
		],
		"Two arrows with the same label from one state ⇒ not a DFA."
	))
	steps.append(_mc("idn_basic_1", "A machine has states {q0, q1, q2} with delta(q0,a)=q1, delta(q0,b)=q2, delta(q1,a)=q0, delta(q1,b)=q1, delta(q2,a)=q2, delta(q2,b)=q0 and no epsilon arrows. What is it?",
		["A DFA", "An NFA", "An epsilon-NFA", "Cannot be determined"],
		0,
		"Every state has exactly one transition per symbol and there are no epsilon moves, so this is a DFA.",
		"Check both rules: one arrow per symbol, and no epsilon."))
	steps.append(_mc("idn_basic_2", "A machine has delta(q0,0) = {q0, q1} and delta(q0,1) = q1. What type of automaton is this?",
		["A DFA", "An NFA", "An epsilon-NFA", "A Turing Machine"],
		1,
		"delta(q0,0) returns a SET of two states, so there are two possible next states - the machine is non-deterministic.",
		"A set of targets instead of one target means NFA."))
	steps.append(_mc("idn_basic_3", "A machine has delta(q0, epsilon) = q1 and delta(q1, a) = q2. What type of automaton is this?",
		["A DFA", "An NFA", "An epsilon-NFA", "Not an automaton at all"],
		2,
		"An epsilon transition consumes no input symbol, which only epsilon-NFAs may have.",
		"Which kind of move lets the machine advance without reading anything?"))
	steps.append(_mc_img("idn_diagram_1", "Is the diagram below a valid DFA? Why, or why not?", "res://Images/dfa/q11.png",
		["No: there should not be more than one accepting state in F",
		"Yes, because DFAs must have more than one accepting state",
		"No: there is no non-accepting state, since F should not equal Q",
		"Yes, because F can be any subset of Q"],
		3,
		"F is a subset of Q and may contain one state, several states, or even all of them. Having several accepting states - or all states accepting - is completely legal for a DFA.",
		"Nothing in the definition limits how many states are in F."))
	return _finish_identification(steps)

# ===== 3. SIMULATION =======================================================

static func _module_simulation() -> Dictionary:
	var steps: Array = []
	steps.append(_info(
		"SIMULATE A STRING",
		"Start at q0. For each symbol, follow the matching arrow once. When the string ends, accept iff you are in F.",
		[
			"Trace: q0 --a--> q1 --b--> ...",
			"No skipping symbols; missing arrow ⇒ reject.",
		],
		"Maze rooms = states, corridors = symbols, exit = accepting state."
	))
	steps.append(_mc("sim_purpose", "Given a DFA, what is the purpose of simulating an input string?",
		["To change the DFA's states permanently", "To determine the state reached after processing the input", "To add new transitions", "To remove final states"],
		1,
		"Simulating shows which state the machine ends in, and therefore whether the string is accepted or rejected.",
		"Simulation answers 'where do we end up?', not 'how do we rebuild the machine?'."))
	steps.append(_trace("sim_trace_1", "Machine over {0,1} accepting strings that end in '01'. Where does the run for '1101' stop?",
		DFA_ENDS_01, "1101", "q2",
		"q0 --1--> q0 --1--> q0 --0--> q1 --1--> q2. The run stops in q2, which is accepting, so '1101' is accepted.",
		"Process the symbols in order: 1, 1, 0, 1 - never reorder them."))
	steps.append(_maze("sim_maze_1",
		"ESCAPE ROOM: reach the exit room with a string that ends in '01'",
		DFA_ENDS_01, 1,
		"Every corridor carries one symbol, so a walk through the maze IS a simulation. The exit room is an accepting state, so you only escape if the string you collected is accepted.",
		"Watch the string you are building as you move: the last two symbols must be 0 then 1."))
	return _finish_simulation(steps)

# ===== 4. BUILDING =========================================================

static func _module_building() -> Dictionary:
	var steps: Array = []
	steps.append(_info(
		"BUILD FROM THE LANGUAGE",
		"Turn the English rule into states = what you must remember, then wire one arrow per symbol.",
		[
			"Name each state by its memory (e.g. 'ends in a', 'even count').",
			"Mark accepting where the rule is already satisfied.",
			"Add a trap state when a bad prefix can never recover.",
		],
		"Test: one accept, one reject, one near-miss."
	))
	steps.append(_mc("bld_trap_1", "A DFA has states q0, q1, q2 where q2 is accepting, and delta(q2, 'b') is missing. What must be added to make this a complete DFA?",
		["Remove q2 from F so it has no missing arrows", "Add a new start state", "Change the alphabet to {a}", "Add a transition from the accepting state on 'b'"],
		3,
		"Completeness means every state/symbol pair has exactly one transition, so the missing arrow from the accepting state must be added.",
		"Find the (state, symbol) pair with no arrow and give it one."))
	steps.append(_build("bld_build_1",
		"BUILD: strings that end in 'ab'",
		"Build a DFA over {a,b} that ACCEPTS any string ending in 'ab' (like 'ab', 'aab', 'bab') and REJECTS everything else. The board tests the strings below - any correct construction passes.",
		["ab", "aab", "bab", "abab"],
		["", "a", "b", "ba", "aba", "abb"],
		"q0 means 'the last symbol was not a', q1 means 'the last symbol was a', q2 means 'the last two were ab' (accepting).",
		"Two states are enough to remember 'ends in a'; the third remembers the full 'ab'."))
	steps.append(_mc("bld_howto_test", "You built a DFA and think it is right. Which set of test strings gives the strongest check?",
		["Only strings you know should be accepted",
			"Only the empty string",
			"Strings that should be accepted, strings that should be rejected, and tricky edge cases",
			"Random strings with no expectation"],
		2,
		"A machine is correct when it accepts what it should AND rejects what it should. Testing tempting near-misses is what catches bugs.",
		"A test that only confirms success proves nothing about rejection."))
	return _finish_building(steps)

# ===== 5. SET BUILDER ======================================================

static func _module_set_builder() -> Dictionary:
	var steps: Array = []
	steps.append(_info(
		"LANGUAGES AS CONDITIONS",
		"Set-builder form: {w in Sigma* : condition}. Pick the smallest memory that decides the condition.",
		[
			"'contains 00' → track how much of 00 you have seen.",
			"'even number of 1s' → two states: even / odd.",
			"'|w| even' → toggle length parity each symbol.",
		],
		"States = memories, not individual strings."
	))
	steps.append(_mc("set_read_1", "Which strings belong to {w in {0,1}* : w contains '00'}?",
		["Only '00' itself", "'00', '100', '1001' and '000' - any string with two consecutive 0s", "Only strings that start with 00", "Any string with at least two 0s anywhere"],
		1,
		"'Contains' means the substring appears anywhere, so '1001' qualifies even though it starts and ends with 1.",
		"Compare '1001' (accepted) with '101' (rejected): what is the difference?"))
	steps.append(_build("set_build_1",
		"BUILD: contains '00'",
		"Build a DFA over {0,1} that ACCEPTS exactly the strings containing the substring '00' and REJECTS all others.",
		["00", "100", "1001", "000"],
		["0", "1", "10", "101"],
		"q0 = no 0 seen recently, q1 = the last symbol was 0, q2 = '00' has been seen (accepting, with self-loops on both symbols).",
		"Once the pattern is found you can never lose it, so the accepting state loops on both symbols."))
	steps.append(_trace("set_trace_1", "Same machine (accepts strings containing '00'). Where does the run for '1001' stop?",
		DFA_CONTAINS_00, "1001", "q2",
		"q0 --1--> q0 --0--> q1 --0--> q2 --1--> q2. The run stops in q2, which is accepting, so '1001' is accepted.",
		"Watch the second symbol: q1 means 'the last symbol was 0', so the next 0 completes the pattern."))
	return _finish_set_builder(steps)

static func _finish_set_builder(steps: Array) -> Dictionary:
	steps.append(_mc("set_len_1", "How many states does a DFA need for {w in {a,b}* : |w| is even}?",
		["1", "2", "3", "One per symbol in the alphabet"],
		1,
		"Two states are enough: 'length even so far' and 'length odd so far'. Every symbol toggles between them.",
		"Does the exact length matter, or only its parity?"))
	steps.append(_mc("set_combine_1", "Which of these describes the same language as the list {'', 'aa', 'aaaa', ...}?",
		["{w in {a}* : |w| is even}", "{w in {a}* : |w| >= 2}", "{w in {a}* : w starts with a}", "{w in {a,b}* : w has no b}"],
		0,
		"The list contains the empty string and then even-length runs of a's, so the condition is 'an even number of a symbols'.",
		"Check which option allows the empty string."))

	return {
		"skill": "set_builder",
		"order": 5,
		"title": "DFA FROM SET BUILDER",
		"subtitle": "Turn a condition {w : ...} into a machine by choosing the right memory.",
		"accent": "#c39bff",
		"intro": _info(
			"TOPIC 5 — CONDITIONS",
			"Read {w : condition} and choose states that track just enough to decide.",
			[
				"Parity and substring checks need small memories.",
			],
			"Condition → memory → diagram."
		),
		"steps": steps,
		"remedy": [
			_info(
				"TRANSLATE, THEN COUNT",
				"First translate the condition into plain English, then list what changes the answer.",
				[
					"'contains 00' -> the answer can never go back to 'no' once two 0s are seen: a one-way memory.",
					"'even number of 1s' -> only the parity matters: two states.",
					"'|w| even' -> every symbol toggles: two states.",
					"'no 11' -> remember whether the previous symbol was 1, plus a dead state for the moment '11' appears.",
				],
				"Write the memory of each state as a sentence. If you cannot, you have too many or too few states."
			),
		],
		"practice": [
			_trace("set_practice_2", "Machine over {0,1} accepting strings with an even number of 1s. Where does '1010' stop?",
				DFA_EVEN_ONES, "1010", "even",
				"even --1--> odd --0--> odd --1--> even --0--> even. It stops in the accepting state, so '1010' is accepted (two 1s).",
				"Count the 1s: the 0s never move you."),
			_mc("set_practice_3", "Which of these languages is NOT regular (needs memory that grows with the input)?",
				["Strings ending in '01'", "Strings with an even number of 1s", "Strings of the form a^n b^n (equal numbers of a's and b's)", "Strings containing '00'"],
				2,
				"a^n b^n needs to count the a's and compare - that memory grows without bound, so no finite automaton can do it. The other three need only fixed memories.",
				"Which condition forces the machine to remember how many a's it saw?"),
			_mc_board("set_board_1", "Refer to the DFA on the whiteboard. Is the string '1001' ACCEPTED by this machine?",
				DFA_CONTAINS_00,
				["Yes — the run reaches q2, the accepting state",
				 "No — it ends back in q0",
				 "No — the machine stalls on the final '1'",
				 "Yes — but only because the string starts with '1'"],
				0,
				"Follow the run: q0 --1--> q0 (no 0 seen), q0 --0--> q1 (last symbol was 0), q1 --0--> q2 ('00' found), q2 --1--> q2 (the pattern can never be lost). The run ends in q2, so '1001' is accepted.",
				"Once the machine reaches the '00 found' state it can never leave it."),
		],
	}

# ===== 6. DFA FROM LISTS ===================================================

static func _module_list() -> Dictionary:
	var steps: Array = []
	steps.append(_info(
		"INFER THE RULE FROM EXAMPLES",
		"A finite list hints at an infinite language. Find the pattern, then build one DFA for the rule.",
		[
			"{ab, aab, aaab, ...} → one or more a's, then one b (a+b).",
			"{b, ab, aab, ...} → zero or more a's, then one b (a*b).",
			"Check the shortest example first (empty string? single symbol?).",
		],
		"Reject strings that look like the list but break the rule."
	))
	steps.append(_mc("lst_read_1", "What language does the list {ab, aab, aaab, ...} describe?",
		["All strings containing at least one ab", "One or more a's followed by exactly one b", "Any number of a's, then any number of b's", "Strings with more a's than b's"],
		1,
		"The pattern is a^n b for n >= 1: at least one a, then a single b at the end.",
		"Try a string that fits the list but ends with two b's - it is not in the list."))
	steps.append(_trace("lst_trace_1", "The machine for a+b is given. Where does the run for 'aab' stop?",
		DFA_A_PLUS_B, "aab", "ok",
		"q0 --a--> q1 --a--> q1 --b--> ok. It stops in the accepting state, so 'aab' is accepted.",
		"q1 keeps absorbing a's; the b is what finishes the job."))
	steps.append(_mc("lst_read_2", "What language does the list {b, ab, aab, aaab, ...} describe?",
		["One or more a's then exactly one b", "Zero or more a's then exactly one b", "Strings ending in b of any shape", "Strings with equal a's and b's"],
		1,
		"Here even the empty prefix is allowed, so the language is a*b: zero or more a's followed by one b.",
		"Compare with the previous list: the only difference is the string 'b'."))
	return _finish_list(steps)

static func _finish_list(steps: Array) -> Dictionary:
	steps.append(_mc("lst_edge_1", "The list is {'aa', 'aaaa', 'aaaaaa', ...}. Which design detail matters most?",
		["The states must be named by their length", "The parity of the length: start in the accepting 'even' state", "The list has an infinite number of strings", "A trap state is impossible here"],
		1,
		"Only even lengths appear, so the machine tracks parity and starts accepting (the empty string is excluded only because the list itself starts at 2, which is an authoring detail - 'length is even' is the rule).",
		"Compare the lengths in the list: 2, 4, 6 - all even."))
	steps.append(_mc("lst_generalise_1", "A list shows {'abc', 'aabc', 'aaabc', ...}. What is the correct first step?",
		["Build a separate machine for each string in the list", "Find the generating rule: one or more a's followed by bc", "Count the letters in the longest string", "Assume the language allows any string with two b's"],
		1,
		"From a list you infer the general rule (a^+bc), then build one machine for that rule - never one machine per example.",
		"A machine must accept infinitely many strings, so it can never be built from examples alone."))
	steps.append(_mc("lst_reject_1", "For the list {ab, aab, aaab, ...}, which string must the machine REJECT to prove it learned the rule?",
		["aab", "aaab", "abb", "ab"],
		2,
		"'abb' contains a double b, which the rule a+b forbids, so a correct machine must reject it - that test is what separates the rule from the examples.",
		"Pick a string that looks similar to the list but breaks the pattern."))

	return {
		"skill": "list",
		"order": 6,
		"title": "DFA FROM LISTS",
		"subtitle": "Infer the hidden rule behind a list of accepted strings.",
		"accent": "#7fe0dc",
		"intro": _info(
			"TOPIC 6 — FROM LISTS",
			"Examples suggest a rule; build one machine for that rule, not for the list alone.",
			[
				"Shortest string tells you about empty / single-symbol cases.",
				"Test near-miss strings outside the list.",
			],
			"Rule first, then states."
		),
		"steps": steps,
		"remedy": [
			_info(
				"FROM LIST TO RULE",
				"Write the list in a column, then draw attention to what changes from one line to the next.",
				[
					"ab -> aab -> aaab: the number of a's grows, the b stays exactly one.",
					"b -> ab -> aab: an extra a is inserted at the front; b alone is legal.",
					"{aa, aaaa}: the lengths jump by two - parity, not counting.",
				],
				"Say the rule out loud in words, then ask how many memories it needs. That number is your state count."
			),
		],
		"practice": [
			_trace("lst_practice_2", "Machine for a*b (zero or more a's then one b). Where does the run for 'b' stop?",
				DFA_A_STAR_B, "b", "ok",
				"q0 --b--> ok. With zero a's the very first symbol already finishes the string, and the run stops in the accepting state.",
				"Zero a's is allowed, so the first symbol may be the b itself."),
			_mc("lst_practice_3", "Why can a list never be copied literally into a DFA?",
				["Because lists are unordered", "Because a list is finite while the language it describes is usually infinite", "Because DFAs cannot store strings", "Because lists use commas"],
				1,
				"A DFA accepts an infinite language; a list has finitely many entries. Only the RULE behind the list can be mechanised.",
				"Compare the size of the list with the size of the language."),
			_mc_board("lst_board_1", "Refer to the DFA on the whiteboard. Which list of accepted strings does this machine describe?",
				DFA_A_STAR_B,
				["{ab, aab, aaab, ...}", "{b, ab, aab, aaab, ...}", "{ba, baa, baaa, ...}", "{a, b, ab, ...}"],
				1,
				"From the start state the machine may take any number of a's (including none) and finishes with exactly one b - that is zero or more a's then one b, the list {b, ab, aab, aaab, ...}.",
				"Try the shortest string first: is plain 'b' accepted? What about the empty string?"),
		],
	}




static func _finish_building(steps: Array) -> Dictionary:
	steps.append(_freebuild(
		"SANDBOX: BUILD ANYTHING",
		"No task, no marking: add states, wire arrows, toggle accepting states and simulate any string you invent. Try to build a machine that accepts only strings with two 1s, or a machine for your own pattern."
	))

	return {
		"skill": "building",
		"order": 4,
		"title": "DFA BUILDING",
		"subtitle": "Design machines from a language description and prove them correct.",
		"accent": "#ff9f7a",
		"intro": _info(
			"TOPIC 4 — BUILD",
			"Design states as memories, wire arrows, test with accept/reject strings.",
			[
				"Any correct diagram passes the whiteboard.",
				"Trap state when a prefix is hopeless.",
			],
			"Memory-first, not picture-first."
		),
		"steps": steps,
		"remedy": [
			_info(
				"DESIGN FROM EXAMPLES",
				"Write your target language as a list of accepted and rejected strings, then ask after each prefix: 'what must I still remember?'",
				[
					"For 'ends in ab': after 'a' remember 'last was a'; after 'ab' remember 'done'; otherwise forget.",
					"For 'even a's': remember only the parity - two memories, two states.",
					"Add the trap state whenever a prefix can never be repaired.",
					"Give every state an arrow for every symbol, even if it points back to itself.",
				],
				"Test with three strings: one accepted, one rejected, one that nearly works."
			),
		],
		"practice": [
			_mc("bld_practice_2", "For the language 'strings over {a,b} ending in ab', why are three states enough?",
				["Because the alphabet has two symbols", "Because only three different memories matter: not-ending-in-a, ending-in-a, and ending-in-ab", "Because every DFA needs three states", "Because three test strings are used"],
				1,
				"Each state stores one distinct memory about the input seen so far; the 'ends in ab' language needs exactly those three memories.",
				"Count the distinct things the machine must remember."),
			_trace("bld_practice_3", "Using the machine over {a,b} that accepts one or more a's then a b (a+b), where does the run for 'aaab' stop?",
				DFA_A_PLUS_B, "aaab", "ok",
				"q0 --a--> q1 --a--> q1 --a--> q1 --b--> ok. It stops in the accepting state, so 'aaab' is accepted.",
				"q1 counts the a's; only the final 'b' moves to the accepting state."),
			_mc_board("bld_board_1", "Refer to the DFA on the whiteboard. Which language does this machine ACCEPT?",
				DFA_A_PLUS_B,
				["Any string that contains at least one 'b'",
				 "One or more a's followed by exactly one b, like 'ab' or 'aaab'",
				 "Any string over {a,b}",
				 "Only the single symbol 'b'"],
				1,
				"From q0 only an 'a' is safe; q1 keeps absorbing a's and the first b moves to the accepting state 'ok' - after that everything is rejected. That is exactly a+b.",
				"Try to describe in words what each state remembers about the input seen so far."),
		],
	}



static func _finish_simulation(steps: Array) -> Dictionary:
	steps.append(_mc("sim_trace_2", "Same machine over {0,1} accepting strings that end in '01'. Where does the run for '00110' stop?",
		["q0", "q1", "q2", "Nowhere - it stalls"],
		1,
		"q0 --0--> q1 --0--> q1 --1--> q2 --1--> q0 --0--> q1. The run stops in q1, so '00110' is rejected (q1 is not accepting).",
		"Take the symbols one at a time: 0, 0, 1, 1, 0."))
	steps.append(_mc("sim_reject_rule", "A run on string w ends in state q3, and q3 is NOT in F. What is the verdict?",
		["w is accepted", "w is rejected", "w is undecided", "The machine is invalid"],
		1,
		"The verdict depends only on whether the final state is in F. Ending outside F means rejected.",
		"Acceptance is decided by the final state alone, not by the states visited on the way."))
	steps.append(_mc("sim_empty", "A DFA over {0,1} has q0 in F. What does it do with the empty string?",
		["Accepts it, because the run ends in q0 immediately", "Rejects it, because nothing was read", "Stalls", "It depends on Sigma"],
		0,
		"The run for the empty string consumes no symbols, so it ends in the start state. q0 in F means accepted.",
		"A zero-length string still has a run, and it stops at q0."))

	return {
		"skill": "simulation",
		"order": 3,
		"title": "SIMULATION",
		"subtitle": "Walk strings through a machine and decide accept or reject - on paper and in the maze.",
		"accent": "#ffd479",
		"intro": _info(
			"TOPIC 3 — SIMULATE",
			"Walk the string: start at q0, one arrow per symbol, then check F.",
			[
				"Final state in F ⇒ accept.",
				"Maze = same walk in 3D.",
			],
			"Mechanical tracing — no guessing."
		),
		"steps": steps,
		"remedy": [
			_info(
				"TRACE LIKE A MACHINE",
				"Put your finger on the start state, then move it once per symbol. Say the symbol out loud before you move; this stops the two most common mistakes - skipping a symbol and reading the string backwards.",
				[
					"Cover the string with your hand and reveal one symbol at a time.",
					"After each move, ask: which circle am I on now?",
					"Only when the string is gone do you look at F.",
					"If a symbol has no arrow from where you are, the run stops: the string is rejected.",
				]
			),
		],
		"practice": [
			_trace("sim_practice_1", "Machine over {0,1} accepting strings that end in '01'. Where does '1010' stop?",
				DFA_ENDS_01, "1010", "q1",
				"q0 --1--> q0 --0--> q1 --1--> q2 --0--> q1. It stops in q1, which is not accepting, so '1010' is rejected.",
				"Four symbols: 1, 0, 1, 0."),
			_mc("sim_practice_2", "Machine over {0,1} with two states (even, odd), start = even, F = {even}, accepting strings with an EVEN number of 1s. Is '101' accepted?",
				["Yes: even -1-> odd -0-> odd -1-> even, so it ends in even", "No: it ends in odd",
					"Only if the empty string counts", "The machine stalls on the second '1'"],
				0,
				"Track the parity: even -1-> odd, odd -0-> odd, odd -1-> even. The run ends in an accepting state, so '101' is accepted (two 1s is even).",
				"Count the 1s as you walk: 1 (odd), still 1 (odd), 2 (even)."),
			_maze("sim_practice_3", "MAZE PRACTICE: escape with a string that contains '00'",
				DFA_CONTAINS_00, 1,
				"Once you have seen '00' the machine is trapped in the accepting room: every further symbol keeps you there.",
				"You only need two consecutive 0s - try walking 0, 0 first, then the exit."),
			_mc_board("sim_board_1", "Refer to the DFA on the whiteboard. This machine accepts strings over {0,1} that END in '01'. Where does the run for the string '1101' stop?",
				DFA_ENDS_01,
				["q0", "q1", "q2", "The machine gets stuck on the last '1'"],
				2,
				"Start at q0 and move once per symbol: 1 keeps you in q0, the 0 moves to q1, and the final 1 lands in q2 - the accepting state, so '1101' is accepted.",
				"Move one arrow per symbol, in order: 1, 1, 0, 1."),
		],
	}



static func _finish_identification(steps: Array) -> Dictionary:

	return {
		"skill": "identification",
		"order": 2,
		"title": "SPOT A DFA",
		"subtitle": "Tell a DFA from an NFA using the diagram only.",
		"accent": "#8ce0b0",
		"intro": _info(
			"TOPIC 2 — SPOT A DFA",
			"Quick check: from each state, at most one arrow per symbol; no epsilon arrows.",
			[
				"Duplicate labels from one state ⇒ NFA.",
				"All states accepting is still allowed.",
			],
			"You do not need to simulate to classify the picture."
		),
		"steps": steps,
		"remedy": [
			_info(
				"THE ARROW TEST",
				"Work state by state and symbol by symbol. For each circle on the diagram, count how many outgoing arrows carry each symbol in Sigma.",
				[
					"Exactly one arrow for each symbol in Sigma -> that state is deterministic.",
					"Two arrows with the same label -> the machine is an NFA.",
					"An arrow labelled epsilon -> the machine is an epsilon-NFA.",
					"A missing symbol -> the machine is incomplete.",
				]
			),
		],
		"practice": [
			_mc("idn_practice_1", "A diagram shows every state with exactly one arrow per symbol, but one state has an extra arrow labelled epsilon. What type of automaton is it?",
				["A DFA", "An NFA without epsilon", "An epsilon-NFA", "A complete DFA with a typo"],
				2,
				"Only epsilon-NFAs may have epsilon transitions, so the machine is an epsilon-NFA.",
				"Any epsilon arrow automatically changes the classification."),
			_mc("idn_practice_2", "Every state has exactly one 'a' and one 'b' arrow, and there are no epsilon moves. What is it?",
				["A DFA", "An NFA", "An epsilon-NFA", "Not an automaton"],
				0,
				"One arrow per symbol from each state and no epsilon ⇒ DFA.",
				"Count arrows per label from each circle."),
			_mc_board("idn_board_1", "Refer to the machine on the whiteboard. Why is it NOT a DFA?",
				NFA_NOT_A_DFA,
				["q0 has two arrows labelled '0' and no arrow labelled '1'",
				 "It has three states, which is too many for a DFA",
				 "It has exactly one accepting state",
				 "The alphabet {0,1} is empty"],
				0,
				"From q0 the machine offers TWO choices on symbol '0' and is missing the '1' arrow entirely - that is exactly what makes a machine non-deterministic and incomplete.",
				"Look at the arrows leaving q0: count them per symbol."),
		],
	}
