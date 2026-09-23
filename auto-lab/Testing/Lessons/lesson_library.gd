extends RefCounted
## Authored lesson library for the Adaptive Learning Room (DFA topic).
##
## HOW TO EDIT (this file is meant to be edited by hand):
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
	return _cache

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

## Legacy course shape used by Testing Grounds' panel controller. The lesson
## data remains authored here; the controller only consumes the projected view.
static func course_steps() -> Array:
	var out: Array = []
	for module in modules():
		var skill := str(module.get("skill", ""))
		for source_step in module.get("steps", []):
			var kind := str(source_step.get("kind", ""))
			if kind == "info":
				var body := str(source_step.get("body", ""))
				var points: Array = source_step.get("points", [])
				if not points.is_empty():
					body += "\n\n" + "\n".join(points)
				if str(source_step.get("callout", "")) != "":
					body += "\n\n" + str(source_step["callout"])
				out.append({
					"m": "content", "skill": skill, "field": "library",
					"title": str(source_step.get("title", module.get("title", skill))),
					"subtitle": str(module.get("subtitle", "")), "body": body,
				})
			elif kind == "board":
				out.append({
					"m": "demo", "skill": skill,
					"title": str(source_step.get("title", "WHITEBOARD")),
					"explain": str(source_step.get("explain", "")),
					"task": source_step.get("task", {}),
				})
			elif kind == "freebuild":
				out.append({
					"m": "freebuild", "skill": skill,
					"title": str(source_step.get("title", "FREE BUILD")),
					"subtitle": str(source_step.get("subtitle", "")),
				})
		out.append({
			"m": "practice", "skill": skill,
			"title": "PRACTICE | %s" % str(module.get("title", skill)),
		})
	return out

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
		"THE PARTS OF A DFA",
		"A DFA is described completely by five pieces, called the 5-tuple (Q, Sigma, delta, q0, F). Nothing else is needed - if you know these five, you know the machine.",
		[
			"Q - the finite set of states.",
			"Sigma - the input alphabet (the symbols the machine may read).",
			"delta - the transition function: delta(state, symbol) -> state.",
			"q0 - the start state, where the run begins.",
			"F - the set of accepting (final) states, drawn as double circles.",
		],
		"F is a SUBSET of Q. It may be empty, it may hold one state, or even all of them - any subset is legal."
	))
	steps.append(_info(
		"THE 5-TUPLE IN PRACTICE",
		"Here is a real machine written out formally. It accepts strings over {a,b} that end with 'a'.",
		[
			"Q = {q0, q1}",
			"Sigma = {a, b}",
			"q0 = q0",
			"F = {q1}",
			"delta(q0,a)=q1   delta(q0,b)=q0   delta(q1,a)=q1   delta(q1,b)=q0",
		],
		"A double circle in a diagram means exactly 'this state is in F'."
	))
	steps.append(_info(
		"THREE WAYS TO WRITE THE SAME MACHINE",
		"A DFA can be represented as a transition table, as a transition diagram, or as a formal 5-tuple. All three describe the same machine, so you can move between them freely.",
		[
			"Table: rows are states, columns are symbols, cells are next states.",
			"Diagram: circles are states, arrows are transitions; the arrow with no source marks q0.",
			"5-tuple: the compact mathematical description.",
		],
		"Exam questions usually give one representation and ask for another."
	))
	steps.append(_mc("def_parts_1", "Which of the following represents the five components of a finite automaton?",
		["(Q, Sigma, delta, q0, F)", "(Q, delta, F, Sigma, q)", "(Sigma, q0, F, S, delta)", "(Q, Sigma, S, delta, q1)"],
		0,
		"A finite automaton is the 5-tuple (Q, Sigma, delta, q0, F): states, alphabet, transition function, start state, accepting states.",
		"Alphabet comes second, delta third, start state fourth, final states last."))
	steps.append(_mc("def_parts_2", "What does Q represent in a finite automaton?",
		["Input alphabet", "Set of states", "Transition function", "Set of final states"],
		1,
		"Q is the finite set of states the machine may occupy.",
		"Sigma is the alphabet, delta the transition function, F the final states - so Q is what is left."))
	steps.append(_mc("def_parts_3", "What does F represent, and how is it usually drawn?",
		["Input symbols, drawn as arrows", "Transition function, drawn as a table", "Starting state, drawn with an incoming arrow", "Set of final states, drawn with a double circle"],
		3,
		"F is the set of final (accepting) states and is drawn with a double circle.",
		"Think of a bullseye: double ring means accepting."))
	steps.append(_mc("def_parts_4", "What is the purpose of the transition function delta?",
		["It determines how the automaton moves between states", "It identifies the final states", "It defines the alphabet", "It selects the starting state"],
		0,
		"delta(state, symbol) returns the state the machine enters when it reads that symbol.",
		"delta is the wiring between the circles."))
	return _finish_definition(steps)

## Second half of module 1: the whiteboard demo, real-life panel and the
## reusable remedy / practice pools.
static func _finish_definition(steps: Array) -> Dictionary:
	steps.append(_board(
		"SEE A DFA AT THE WHITEBOARD",
		"This reference machine is already built for you. It accepts strings ending in 'a' and rejects strings ending in 'b'. Read the arrows: q0 is the start state, q1 carries the double ring so it belongs to F, and every state has exactly one arrow per symbol - that is what makes it deterministic.",
		{"instruction": "A reference DFA is loaded. Press Check task to confirm you can read it, then change a transition and check again.", "seed": true, "accept": ["a", "ba", "aba", "bba"], "reject": ["b", "ab", "bb", "aab"]}
	))
	steps.append(_info(
		"DFAs IN REAL LIFE",
		"Finite automata are not only exam material - they run inside the software you use every day.",
		[
			"Lexical analysers: a compiler's scanner recognises identifiers, numbers and keywords with DFAs.",
			"Regular expressions: engines translate a pattern into a DFA and then simulate it.",
			"Network filters: firewall rules compile into machines that accept or drop traffic.",
			"Elevators, traffic lights and vending machines: controllers whose behaviour depends only on the current state.",
		],
		"Whenever a rule depends only on the current situation, a DFA is the natural model."
	))
	steps.append(_mc("def_real_1", "A compiler's scanner decides whether a sequence of letters is a keyword, an identifier or a number. Which model does it use?",
		["A Turing Machine for each token", "A finite automaton per token pattern", "A context-free grammar walker", "No machine, just regular expressions"],
		1,
		"Compilers recognise tokens with finite automata, usually a DFA built from a regular expression.",
		"Token rules depend only on the characters read so far - the definition of a finite-state rule."))

	return {
		"skill": "definition",
		"order": 1,
		"title": "DFA DEFINITION & PARTS",
		"subtitle": "What a DFA is, the 5-tuple, and how machines are written down.",
		"accent": "#78b4ff",
		"intro": _info(
			"TOPIC 1 - DFA DEFINITION & PARTS",
			"A Deterministic Finite Automaton (DFA) is the simplest machine model in Automata Theory: it reads a string one symbol at a time and, after the last symbol, either accepts or rejects it. It has no memory beyond the state it currently stands in.",
			[
				"Deterministic: for each state and symbol there is exactly ONE next state.",
				"Finite: the number of states is fixed and small.",
				"No epsilon moves: every move consumes exactly one symbol.",
			],
			"Everything else you learn about automata builds on this one idea."
		),
		"steps": steps,
		"remedy": [
			_info(
				"LET'S GO SLOWLY",
				"Read the 5-tuple in order and say each part out loud: Q (states) - Sigma (alphabet) - delta (moves) - q0 (start) - F (finals). Then read the diagram: circles are Q, the arrow with no source is q0, double circles are members of F, labelled arrows are delta.",
				[
					"Q: list every state you can see.",
					"Sigma: list every label used on the arrows.",
					"q0: find the arrow that comes from nowhere.",
					"F: find every double circle.",
					"delta: read each arrow as delta(from, symbol) = to.",
				],
				"Use the whiteboard to test yourself: add a state, make it accepting, and watch the double ring appear."
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
		"DFA OR NFA? READ THE STRUCTURE",
		"The three machine types look similar in a diagram. The difference is only in how the arrows behave, so you can classify any machine by checking the arrows - you never have to run it.",
		[
			"DFA: exactly one arrow per symbol from every state. No epsilon arrows.",
			"NFA: a state may have several arrows on the same symbol, or none at all.",
			"epsilon-NFA: it also has arrows labelled epsilon that consume no input.",
		],
		"Two 'a' arrows leaving the same circle is the fastest give-away that you are looking at an NFA."
	))
	steps.append(_info(
		"THE THREE REPRESENTATIONS OF A DFA",
		"A diagram, a transition table and a 5-tuple can describe the exact same machine. Being able to switch between them is what 'identifying a DFA' really means in practice.",
		[
			"Diagram -> table: read every labelled arrow into a cell.",
			"Table -> 5-tuple: collect the state names, the column labels, the start row and the rows whose final column is marked.",
			"5-tuple -> diagram: draw one circle per state, then one arrow per delta entry.",
		],
		"Check completeness: in a complete DFA every state/symbol cell in the table is filled."
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
	steps.append(_mc("idn_incomplete_1", "A complete DFA over Sigma = {0,1} has three states. How many transitions must its delta contain?",
		["3", "6", "9", "It depends on the accepting states"],
		1,
		"Every state needs one transition per symbol: 3 states x 2 symbols = 6 transitions.",
		"Multiply the number of states by the size of the alphabet."))
	return _finish_identification(steps)

# ===== 3. SIMULATION =======================================================

static func _module_simulation() -> Dictionary:
	var steps: Array = []
	steps.append(_info(
		"WHAT SIMULATION MEANS",
		"Simulating a DFA means running a string through it. You start at q0, read the string one symbol at a time, take the arrow labelled with that symbol, and when the string runs out you look at the state you stopped in. In F means accepted; outside F means rejected.",
		[
			"Write the run as a chain: q0 --a--> q1 --b--> q0 ...",
			"One symbol, one arrow, no skipping and no guessing.",
			"Decision rule: final state in F = ACCEPTED, otherwise REJECTED.",
		],
		"Simulation is the only way to prove that a machine really accepts the language you designed it for."
	))
	steps.append(_info(
		"WATCH A FULL TRACE",
		"Machine: over {a,b}, accepts strings ending in 'b'. Transitions: delta(q0,a)=q0, delta(q0,b)=q1, delta(q1,a)=q0, delta(q1,b)=q1. Start q0, accepting {q1}.",
		[
			"Trace 'abab': q0 --a--> q0 --b--> q1 --a--> q0 --b--> q1",
			"Final state q1 is accepting -> 'abab' is ACCEPTED.",
			"Trace 'abba': q0 --a--> q0 --b--> q1 --b--> q1 --a--> q0",
			"Final state q0 is not accepting -> 'abba' is REJECTED.",
		],
		"Say each step out loud: state, symbol, next state. That habit prevents almost every simulation mistake."
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
	steps.append(_info(
		"WHY THE MAZE IS A DFA",
		"Rooms are states, corridors are transitions, and the exit is an accepting state. Walking the maze and simulating a string are the very same activity - that is why automata are such a good model for search, navigation and control problems.",
		[
			"Each corridor label is one symbol of the input.",
			"A dead end means delta is undefined for that symbol: the machine stalls and rejects.",
			"The exit door is F: reaching it means the string is accepted.",
		],
		"If you can walk the maze, you can simulate the machine on paper."
	))
	steps.append(_board(
		"SIMULATE ON THE WHITEBOARD",
		"Now it is your turn. Build a machine for the language 'strings over {0,1} that end in 01', then use the simulate box on the board to test strings. Watch the board highlight each step as it consumes one symbol at a time.",
		{"instruction": "Build a DFA over {0,1} that ACCEPTS strings ending in '01' and REJECTS all others, then simulate '1101' and '00110'.", "accept": ["01", "1101", "00110", "101"], "reject": ["1", "0", "10", "110"]}
	))
	return _finish_simulation(steps)

# ===== 4. BUILDING =========================================================

static func _module_building() -> Dictionary:
	var steps: Array = []
	steps.append(_info(
		"THE DESIGN RECIPE",
		"Building a DFA is not guessing: it is a four-step procedure. Follow it and the machine falls out of the language description.",
		[
			"1. Write down the language in words: 'strings over {a,b} that end in ab'.",
			"2. Decide what the machine must REMEMBER after reading a prefix. Memory = states.",
			"3. One state per distinct memory; mark the memory that means 'accepted so far' as accepting.",
			"4. Complete delta: give every state one arrow per symbol, adding a trap state if you need to forget.",
		],
		"Finally test your design with strings you are sure about: one accepted, one rejected, and one tricky case."
	))
	steps.append(_info(
		"THE TRAP (DEAD) STATE",
		"Some languages reject a prefix forever - once you see 'b', no continuation can ever be valid. Such a machine needs a TRAP state: a non-accepting state whose arrows all point back to itself.",
		[
			"For a+: q0 reads 'a' into q1 (accepting); any 'b' goes to the trap state.",
			"The trap state is where the machine 'gives up' but keeps running, which keeps the DFA complete.",
			"A DFA without a trap state is still valid as long as delta is defined for every pair.",
		],
		"Trap state = a parking place for hopeless input."
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
	steps.append(_build("bld_build_2",
		"BUILD: even number of 'a's",
		"Build a DFA over {a,b} that ACCEPTS strings with an EVEN number of 'a's (the empty string counts as even) and REJECTS odd ones.",
		["", "aa", "abba", "baab"],
		["a", "aba", "aaa", "abb"],
		"Two states are enough: 'even so far' and 'odd so far'. Both need an arrow for each symbol, including the self-loop on 'b'.",
		"'b' never changes the parity, so every 'b' arrow should stay in the same state."))
	return _finish_building(steps)

# ===== 5. SET BUILDER ======================================================

static func _module_set_builder() -> Dictionary:
	var steps: Array = []
	steps.append(_info(
		"SET-BUILDER NOTATION",
		"Set-builder notation describes a language by a CONDITION instead of by a pattern: {w in Sigma* : condition}. Read it as 'the set of all strings w in Sigma* such that the condition is true'.",
		[
			"{w in {0,1}* : w contains '00'} - the substring 00 appears somewhere.",
			"{w in {0,1}* : the number of 1s in w is even} - a counting condition.",
			"{w in {a,b}* : |w| is even} - a length condition (|w| means the length of w).",
		],
		"Everything before the colon says which strings are candidates; everything after says which ones survive."
	))
	steps.append(_info(
		"COUNTING BECOMES MEMORY",
		"Conditions about counting look impossible for a machine with no memory - until you notice that you only need to remember the part of the count that changes the answer.",
		[
			"Parity of the number of 1s: two states (even, odd). Counting to a million would be impossible; counting 'odd or even' needs one bit.",
			"Contains '00': remember 'how much of the pattern I have matched so far' - nothing, one 0, or matched.",
			"Length is even: two states, toggled by every symbol.",
		],
		"The art of set-builder DFAs is choosing the smallest memory that still answers the condition."
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
	steps.append(_build("set_build_2",
		"BUILD: no two consecutive 1s",
		"Build a DFA over {0,1} that ACCEPTS strings with NO two consecutive 1s (the empty string counts) and REJECTS strings that contain '11'.",
		["", "1", "01", "1010", "0101"],
		["11", "011", "110", "111"],
		"q0 = the last symbol was not 1, q1 = the last symbol was 1, dead = '11' has appeared (rejecting, with self-loops).",
		"Every '0' returns you to the safe state; only a '1' right after a '1' is fatal."))
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
			"TOPIC 5 - SET-BUILDER NOTATION",
			"A set-builder description is the most mathematical way to give a language, and also the most compact. Your job is to find the memory that answers the condition - often much smaller than the condition suggests.",
			[
				"Sigma* means any string over the alphabet, including the empty string.",
				"Counting conditions usually reduce to parity or to 'have I seen it yet'.",
				"Substring conditions reduce to 'how much of the pattern matches so far'.",
			],
			"Ask 'what is the least I must remember to answer the condition for every continuation?' and the states appear."
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
			_build("set_practice_1",
				"BUILD: even number of 1s",
				"Build a DFA over {0,1} that ACCEPTS strings containing an EVEN number of 1s (including the empty string) and REJECTS odd ones.",
				["", "0", "11", "1010"],
				["1", "10", "111", "010"],
				"Two states: 'even so far' (accepting) and 'odd so far'. '0' loops in place, '1' swaps between them.",
				"Only the 1s change the parity, so every 0 arrow stays put."),
			_trace("set_practice_2", "Machine over {0,1} accepting strings with an even number of 1s. Where does '1010' stop?",
				DFA_EVEN_ONES, "1010", "even",
				"even --1--> odd --0--> odd --1--> even --0--> even. It stops in the accepting state, so '1010' is accepted (two 1s).",
				"Count the 1s: the 0s never move you."),
			_mc("set_practice_3", "Which of these languages is NOT regular (needs memory that grows with the input)?",
				["Strings ending in '01'", "Strings with an even number of 1s", "Strings of the form a^n b^n (equal numbers of a's and b's)", "Strings containing '00'"],
				2,
				"a^n b^n needs to count the a's and compare - that memory grows without bound, so no finite automaton can do it. The other three need only fixed memories.",
				"Which condition forces the machine to remember how many a's it saw?"),
		],
	}

# ===== 6. DFA FROM LISTS ===================================================

static func _module_list() -> Dictionary:
	var steps: Array = []
	steps.append(_info(
		"LANGUAGES HIDDEN IN A LIST",
		"A list of accepted strings hides a language: your job is to find the rule that generates ALL of them, then build a machine for that rule - not just for the strings shown.",
		[
			"{a, aa, aaa, ...} -> one or more a's -> a+ (the dots mean the pattern continues forever).",
			"{ab, aab, aaab, ...} -> some a's followed by one b -> a+b.",
			"{b, ab, aab, ...} -> zero or more a's then a b -> a*b.",
		],
		"Always read the shortest string first: it usually reveals whether the pattern allows 'nothing' (the empty string)."
	))
	steps.append(_info(
		"THE FOUR QUESTIONS",
		"Run this checklist on any list before you draw a single circle.",
		[
			"1. Shortest string: is the empty string or a single symbol included? That tells you if q0 is accepting.",
			"2. Length: does only the LENGTH matter (odd/even), or the symbols?",
			"3. Repetition: which symbol may repeat, and how often (zero times, one or more)?",
			"4. Termination: must the string END with a particular symbol?",
		],
		"If your answer to all four matches the list, the machine design is almost automatic."
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
	steps.append(_build("lst_build_1",
		"BUILD: infer a+b",
		"Infer the language from the list {ab, aab, aaab, ...} and build a DFA over {a,b} for it. Strings that do not fit the pattern must be rejected - including 'ba', 'a' and 'abb'.",
		["ab", "aab", "aaab"],
		["", "a", "b", "ba", "abb", "abab"],
		"q0 = no a yet (not accepting), q1 = one or more a's seen, ok = the final b arrived (accepting), dead = anything after that.",
		"One state counts the a's, one state means 'finished', and anything after the b is fatal."))
	steps.append(_mc("lst_read_2", "What language does the list {b, ab, aab, aaab, ...} describe?",
		["One or more a's then exactly one b", "Zero or more a's then exactly one b", "Strings ending in b of any shape", "Strings with equal a's and b's"],
		1,
		"Here even the empty prefix is allowed, so the language is a*b: zero or more a's followed by one b.",
		"Compare with the previous list: the only difference is the string 'b'."))
	steps.append(_build("lst_build_2",
		"BUILD: infer a*b",
		"Build a DFA over {a,b} for the list {b, ab, aab, aaab, ...} - zero or more a's followed by exactly one b.",
		["b", "ab", "aab", "aaab"],
		["", "a", "aa", "ba", "abb"],
		"q0 is the start (accepting only through the b arrow), q1 = 'a's seen', ok = the b arrived (accepting), dead = anything afterwards.",
		"Note that the empty string is REJECTED here, because a b is still required."))
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
			"TOPIC 6 - FROM A LIST TO A MACHINE",
			"A list shows finitely many accepted strings, but the language behind it is infinite. Inferring the RULE is the skill: once you know the rule, the machine follows from the memory it needs.",
			[
				"Read the shortest string first - it reveals whether 'nothing' is allowed.",
				"Look for repetition: 'one or more', 'zero or more', or 'exactly once'.",
				"Look for a required ending symbol.",
				"Then test your machine against strings OUTSIDE the list, including near-misses.",
			],
			"Too few states and the machine accepts the wrong strings; too many and you have lost track of the rule."
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
			_build("lst_practice_1",
				"BUILD: infer a*b from its list",
				"Build a DFA over {a,b} accepting exactly the strings in the list {b, ab, aab, aaab, ...} - zero or more a's followed by one b.",
				["b", "ab", "aab", "aaab"],
				["", "a", "aa", "bb", "abb"],
				"Remember: the empty string is rejected, and no symbol may follow the b.",
				"Where does 'b' from the start state go? That arrow is the whole difference from a+b."),
			_trace("lst_practice_2", "Machine for a*b (zero or more a's then one b). Where does the run for 'b' stop?",
				DFA_A_STAR_B, "b", "ok",
				"q0 --b--> ok. With zero a's the very first symbol already finishes the string, and the run stops in the accepting state.",
				"Zero a's is allowed, so the first symbol may be the b itself."),
			_mc("lst_practice_3", "Why can a list never be copied literally into a DFA?",
				["Because lists are unordered", "Because a list is finite while the language it describes is usually infinite", "Because DFAs cannot store strings", "Because lists use commas"],
				1,
				"A DFA accepts an infinite language; a list has finitely many entries. Only the RULE behind the list can be mechanised.",
				"Compare the size of the list with the size of the language."),
		],
	}




static func _finish_building(steps: Array) -> Dictionary:
	steps.append(_freebuild(
		"SANDBOX: BUILD ANYTHING",
		"No task, no marking: add states, wire arrows, toggle accepting states and simulate any string you invent. Try to build a machine that accepts only strings with two 1s, or a machine for your own pattern."
	))
	steps.append(_board(
		"WHITEBOARD CHALLENGE: TARGET 'ab' AT THE END",
		"Last check on the board. Rebuild the 'ends in ab' language (or keep your earlier design) and use the simulate box to try 'ab', 'aab', 'abab' and then a near-miss such as 'aba'. A correct machine accepts the first three and rejects the last one.",
		{"instruction": "Build a DFA over {a,b} accepting strings ending in 'ab', then simulate 'ab', 'aab', 'abab' and 'aba'.", "accept": ["ab", "aab", "abab"], "reject": ["a", "aba", "abb"]}
	))

	return {
		"skill": "building",
		"order": 4,
		"title": "DFA BUILDING",
		"subtitle": "Design machines from a language description and prove them correct.",
		"accent": "#ff9f7a",
		"intro": _info(
			"TOPIC 4 - BUILDING DFAs",
			"Now you design the machine instead of reading it. The trick is to think in terms of MEMORY: a DFA state records everything the machine must remember about the input so far. If two prefixes need the same decision for every possible continuation, they share a state.",
			[
				"States = distinct pieces of memory",
				"Accepting states = memories where the string seen so far is in the language",
				"Trap state = a memory from which nothing is ever accepted",
				"Every build is judged by testing strings, not by how it looks",
			],
			"The whiteboard accepts ANY correct construction - your machine does not have to match the reference one."
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
			_build("bld_practice_1",
				"BUILD: at least one 'a'",
				"Build a DFA over {a,b} that ACCEPTS every string containing at least one 'a' and REJECTS only the empty string and all-b strings.",
				["a", "ab", "ba", "bab"],
				["", "b", "bb", "bbb"],
				"q0 = 'no a yet' (not accepting), q1 = 'saw an a' (accepting, and every symbol keeps you there).",
				"Once an 'a' has been seen the verdict can never change, so q1 needs self-loops on both symbols."),
			_mc("bld_practice_2", "For the language 'strings over {a,b} ending in ab', why are three states enough?",
				["Because the alphabet has two symbols", "Because only three different memories matter: not-ending-in-a, ending-in-a, and ending-in-ab", "Because every DFA needs three states", "Because three test strings are used"],
				1,
				"Each state stores one distinct memory about the input seen so far; the 'ends in ab' language needs exactly those three memories.",
				"Count the distinct things the machine must remember."),
			_trace("bld_practice_3", "Using the machine over {a,b} that accepts one or more a's then a b (a+b), where does the run for 'aaab' stop?",
				DFA_A_PLUS_B, "aaab", "ok",
				"q0 --a--> q1 --a--> q1 --a--> q1 --b--> ok. It stops in the accepting state, so 'aaab' is accepted.",
				"q1 counts the a's; only the final 'b' moves to the accepting state."),
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
			"TOPIC 3 - SIMULATING A DFA",
			"Simulation is the skill examiners test most, because it proves you can read a machine. The good news: it is completely mechanical. Start at q0, consume one symbol per arrow, and check the final state against F.",
			[
				"Write the chain of states; do not jump ahead.",
				"One symbol = one arrow. Never skip, never reuse the same arrow twice for two symbols.",
				"Final state in F -> ACCEPT, otherwise REJECT.",
			],
			"The maze checkpoint in this topic is the same computation with your feet: rooms are states, corridors are symbols."
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
		],
	}



static func _finish_identification(steps: Array) -> Dictionary:
	steps.append(_board(
		"MAKE AN INCOMPLETE MACHINE INTO A COMPLETE DFA",
		"A DFA over {0,1} is only complete when EVERY state has an arrow for '0' and for '1'. On this board, check each state: if a symbol has no arrow, the machine is not a valid DFA yet. Add the missing arrows and give every symbol somewhere to go.",
		{"instruction": "Build a complete DFA over {0,1} that ACCEPTS strings ending in '1' (every state needs an arrow for 0 and for 1).", "accept": ["1", "01", "011", "1001"], "reject": ["0", "10", "110", "000"]}
	))
	steps.append(_mc("idn_rep_1", "Which representation below always shows every transition of a DFA in one place, making missing arrows obvious?",
		["The 5-tuple", "The transition table", "The accepting-state list", "The alphabet"],
		1,
		"The transition table has one cell per (state, symbol) pair, so a missing arrow shows up as an empty cell.",
		"Think of which form has a row for each state and a column for each symbol."))
	steps.append(_mc("idn_rep_2", "A transition table for Sigma = {0,1} has an empty cell in row q2, column 0. What does that mean?",
		["delta(q2,0) is undefined, so the machine is not a complete DFA", "q2 is an accepting state", "0 is not part of the alphabet", "The machine is an epsilon-NFA"],
		0,
		"An empty cell means no transition for that state/symbol pair: the machine is incomplete and stalls on that input.",
		"Every cell must be filled for a complete DFA."))

	return {
		"skill": "identification",
		"order": 2,
		"title": "IDENTIFICATION OF DIAGRAM",
		"subtitle": "Tell DFAs from NFAs and epsilon-NFAs, and read any representation.",
		"accent": "#8ce0b0",
		"intro": _info(
			"TOPIC 2 - IDENTIFYING DFAs FROM DIAGRAMS",
			"Before you can simulate or build a machine you must be sure it really is a DFA. Identification is a fifteen-second visual check: count the arrows leaving each state for each symbol, and look for epsilon labels.",
			[
				"One arrow per symbol, from every state: DFA.",
				"Several arrows on the same symbol, or missing arrows: NFA (or incomplete).",
				"An arrow labelled epsilon: epsilon-NFA by definition.",
			],
			"A machine with all states accepting is still a valid DFA - F may equal Q."
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
			_mc("idn_practice_2", "The transition table for Sigma = {a,b} has 4 states and every cell filled. Is it a DFA?",
				["Yes - 4 states x 2 symbols = 8 defined transitions", "No, tables cannot describe DFAs", "Only if F is empty", "Only if one state is accepting"],
				0,
				"A complete table with exactly one entry per state/symbol pair describes a DFA.",
				"A filled table means exactly one next state per pair."),
			_mc("idn_practice_3", "Why is the number of transitions in a complete DFA always |Q| x |Sigma|?",
				["Because delta is defined for every state/symbol pair", "Because F is a subset of Q", "Because q0 is fixed", "Because DFAs are finite"],
				0,
				"delta must be defined for every state and every input symbol, giving |Q| x |Sigma| transitions.",
				"One transition per pair, and there are |Q| x |Sigma| pairs."),
		],
	}
