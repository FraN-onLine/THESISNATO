extends RefCounted
## Question bank for the DFA pretest and post test.
## Segmented across 6 DFA skill domains.

const SKILLS := {
	"simulation": {
		"name": "Simulation",
		"description": "Simulate and derive correct possible outcomes from a DFA"
	},
	"identification": {
		"name": "Identification of Diagram",
		"description": "Identify DFAs from NFAs and E-NFAs"
	},
	"definition": {
		"name": "DFA Definition and Parts",
		"description": "Know what a DFA is, its 5-tuple, its parts and elements"
	},
	"building": {
		"name": "DFA Building",
		"description": "Build a DFA without errors (in general)"
	},
	"set_builder": {
		"name": "DFA from Set Builder",
		"description": "Identify and create DFAs from Set Builder Notations"
	},
	"list": {
		"name": "DFA from List",
		"description": "Identify and create automatas from a List of all possible elements"
	}
}

const QUESTIONS := [
	{"id": 1, "skills": ["simulation"],
	 "question": "Given a DFA, what is the purpose of simulating an input string?",
	 "options": ["To change the DFA's states", "To determine the state reached after processing the input", "To add new transitions", "To remove final states"],
	 "correct": 1,
	 "explanation": "Simulating a string traces which state the machine reaches after consuming each symbol, so you can decide accept/reject."},
	{"id": 2, "skills": ["simulation"], "type": "image", "image": "res://Images/q2.png",
	 "question": "Given this DFA, what state does 1101 lead you to?",
	 "options": ["q0", "q2", "q1", "none"], "correct": 1,
	 "explanation": "Trace 1-1-0-1 from the start state of the diagram; the machine lands in q2."},
	{"id": 3, "skills": ["simulation"], "type": "image", "image": "res://Images/q3.png",
	 "question": "Given this DFA, what state does 00110 lead you to?",
	 "options": ["q0", "q2", "q1", "none"], "correct": 2,
	 "explanation": "Trace 0-0-1-1-0 from the start state of the diagram; the machine lands in q1."},
	{"id": 4, "skills": ["simulation"], "type": "image", "image": "res://Images/q4.png",
	 "question": "Given this DFA, what state does 1010 lead you to?",
	 "options": ["q1", "q3", "q2", "q0"], "correct": 0,
	 "explanation": "Trace 1-0-1-0 from the start state of the diagram; the machine lands in q1."},
	{"id": 5, "skills": ["identification", "set_builder"], "type": "image", "image": "res://Images/q5.png",
	 "question": "What is the rule of this language considering this diagram?",
	 "options": ["Language of {1,0} where the string ends with a double digit", "Language of {1,0} where the string ends with an even amount of the same digit", "Language of {1,0} where the string ends with 10", "Language of {1,0} where the string ends with 01"],
	 "correct": 1,
	 "explanation": "The diagram's paired states track repeating pairs, so the accepted strings end with an even number of the same digit."},
	{"id": 6, "skills": ["simulation", "set_builder"],
	 "question": "Given this List Notation L = { strings that contain an equal amount of a and b }, which of these is a valid string?",
	 "options": ["abbb", "bbba", "babaaabb", "abababbbaaa"], "correct": 2,
	 "explanation": "'babaaabb' has four a's and four b's - equal amounts - so it belongs to L."},
	{"id": 7, "skills": ["definition"],
	 "question": "Which of the following represents the five components of a finite automaton?",
	 "options": ["(Q, \u03a3, \u03b4, q\u2080, F)", "(Q, \u03b4, F, \u03a3, q)", "(\u03a3, q\u2080, F, S, \u03b4)", "(Q, \u03a3, S, \u03b4, q1)"],
	 "correct": 0,
	 "explanation": "The 5-tuple is (Q, \u03a3, \u03b4, q\u2080, F): states, alphabet, transition function, start state, accepting states."},
	{"id": 8, "skills": ["definition"],
	 "question": "What does Q represent in a finite automaton?",
	 "options": ["Input alphabet", "Set of states", "Transition function", "Set of final states"],
	 "correct": 1,
	 "explanation": "Q is the (finite) set of states of the machine."},
	{"id": 9, "skills": ["definition"],
	 "question": "What does F represent, commonly shown with a double circle?",
	 "options": ["Input symbols", "Transition function", "Starting state", "Set of final states"],
	 "correct": 3,
	 "explanation": "F is the set of accepting (final) states, drawn with a double circle."},
	{"id": 10, "skills": ["definition"],
	 "question": "What is the purpose of the transition function \u03b4?",
	 "options": ["It determines how the automaton moves between states", "It identifies the final states", "It defines the alphabet", "It selects the starting state"],
	 "correct": 0,
	 "explanation": "\u03b4 maps (state, symbol) to the next state - it is how the machine moves."},
	{"id": 11, "skills": ["identification", "definition"], "type": "image", "image": "res://Images/q11.png",
	 "question": "Is the diagram below a valid DFA, why or why not?",
	 "options": ["No, there should not be more than ONE accepting state (F)", "Yes, because DFAs should have more than ONE accepting state (F)", "No, because there is no non-accepting state; states in F should not equal the set of states Q", "Yes, because DFAs can have any number of states F from the set of states Q"],
	 "correct": 3,
	 "explanation": "A DFA may have zero, one, or many accepting states - F is any subset of Q, so the diagram is valid."},
	{"id": 12, "skills": ["identification", "set_builder"], "type": "image", "image": "res://Images/q12.png",
	 "question": "What is the rule of this diagram?",
	 "options": ["String X of {0,1} such that X ends with 01", "String X of {0,1} such that X ends in 10", "String X of {0,1} such that X ends in 1", "String X of {0,1} such that X ends in 0"],
	 "correct": 2,
	 "explanation": "The accepting state is reached exactly when the last symbol read is 1."},
	{"id": 13, "skills": ["list", "set_builder", "building"],
	 "question": "Which of these rules apply for this language L1, L1 = {00, 01, 10, 11}?",
	 "options": ["String X of {0,1} such that the length of X is less than 3", "String X of {0,1} such that the length of X is exactly 2", "String X of {0,1} such that X consists of only 0 and 1", "String X of {0,1} such that X starts or ends with 0"],
	 "correct": 2,
	 "explanation": "L1 lists every string over {0,1}; the rule 'X consists of only 0 and 1' describes exactly that set."},
	{"id": 14, "skills": ["list", "building"],
	 "question": "What should the transition x be for this language L1 to be true? L1 = {1, 01, 001, 0001, 00001, ...}",
	 "options": ["1", "0", "epsilon", "01"], "correct": 0,
	 "explanation": "Every string in the list ends with a single 1 preceded by zero or more 0s, so the accepting transition consumes 1."},
	{"id": 15, "skills": ["building", "simulation"], "type": "image", "image": "res://Images/q15.png",
	 "question": "In this DFA, what are the transition symbols for x, y, z to describe the language that ends with 001?",
	 "options": ["0, 1, 1", "0, 0, 1", "1, 1, 1", "1, 0, 1"], "correct": 0,
	 "explanation": "Reading the arrows on the path that ends in the accepting state gives x=0, y=1, z=1."},
]
## POST TEST = the same 15 pretest items PLUS these 5 hands-on board builds,
## appended by start_posttest().
const POSTTEST_QUESTIONS := [
	{"id": 101, "skills": ["building"], "type": "handson",
	 "question": "Build a DFA on the automata board that ACCEPTS strings ending in 'ab' over {a, b} and REJECTS everything else.",
	 "task": {"instruction": "Build a DFA over {a,b} that ACCEPTS strings ending in 'ab' and REJECTS others.",
			  "accept": ["ab", "aab", "bab"], "reject": ["a", "aa", "ba"]},
	 "explanation": "Three states: q0 (start), q1 (saw trailing 'a'), q2 (accepting, saw 'ab')."},
	{"id": 102, "skills": ["building"], "type": "handson",
	 "question": "Build a DFA over {a,b} that ACCEPTS strings with an EVEN number of 'a's (the empty string is accepted).",
	 "task": {"instruction": "Build a DFA over {a,b} that ACCEPTS strings with an even number of 'a's.",
			  "accept": ["", "aa", "baab"], "reject": ["a", "aba", "aaa"]},
	 "explanation": "Two states tracking even/odd 'a' count; 'b' loops in place, 'a' flips between them."},
	{"id": 103, "skills": ["building", "set_builder"], "type": "handson",
	 "question": "Build a DFA over {0,1} that ACCEPTS strings ending in '01'.",
	 "task": {"instruction": "Build a DFA over {0,1} that ACCEPTS strings ending in '01'.",
			  "accept": ["01", "001", "1101"], "reject": ["0", "1", "10", "010"]},
	 "explanation": "Track the last two symbols; only the pair 0-then-1 lands in the accepting state."},
	{"id": 104, "skills": ["building", "list"], "type": "handson",
	 "question": "Build a DFA over {a,b} that ACCEPTS exactly the strings in the list L = {a, aa} (every other string is rejected).",
	 "task": {"instruction": "Build a DFA over {a,b} that accepts ONLY 'a' and 'aa'.",
			  "accept": ["a", "aa"], "reject": ["", "b", "ab", "aaa", "ba"]},
	 "explanation": "A counting chain q0 -a-> q1 -a-> q2 with everything else sent to a rejecting trap state."},
	{"id": 105, "skills": ["building", "simulation"], "type": "handson",
	 "question": "Build a DFA over {0,1} that ACCEPTS strings containing '11' as a substring.",
	 "task": {"instruction": "Build a DFA over {0,1} that ACCEPTS strings containing '11'.",
			  "accept": ["11", "011", "1101", "1011"], "reject": ["", "0", "1", "01", "10", "0101"]},
	 "explanation": "Two states before seeing '11' and one accepting sink state after it."},
]

## Every skill a question exercises (questions may tag several).
static func get_question_skills(question: Dictionary) -> Array:
	if question.has("skills"):
		return question["skills"]
	if question.has("skill"):
		return [question["skill"]]
	return []

static func get_questions_for_skill(skill: String) -> Array:
	var result := []
	for q in QUESTIONS:
		if q["skill"] == skill:
			result.append(q)
	return result

static func get_skill_name(skill: String) -> String:
	return SKILLS[skill]["name"]

static func get_skill_description(skill: String) -> String:
	return SKILLS[skill]["description"]

static func get_all_skills() -> Array:
	return SKILLS.keys()

static func get_question_count() -> int:
	return QUESTIONS.size()
