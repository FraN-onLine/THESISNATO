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

## Checkpoint with a diagram attached (images live in res://Images/).
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
	steps.append(_mc_img("idn_diagram_1", "Is the diagram below a valid DFA? Why, or why not?", "res://Images/q11.png",
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

