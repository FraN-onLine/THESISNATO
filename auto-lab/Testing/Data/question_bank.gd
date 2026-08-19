extends RefCounted
## Question bank for the DFA pretest and post test.
## 30 questions segmented across 7 DFA skill domains.

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
	"regex": {
		"name": "DFA from Regex",
		"description": "Identify Regex and convert them to a DFA"
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
	# ===== SIMULATION (5 questions) =====
	{
		"id": 1,
		"skill": "simulation",
		"question": "Given a DFA with states {q0, q1}, start state q0, accepting state q1, and transitions: δ(q0, 'a') = q1, δ(q1, 'a') = q0, what is the result of processing the string 'aaa'?",
		"options": [
			"q0 (rejected)",
			"q1 (accepted)",
			"q0 (accepted)",
			"q1 (rejected)"
		],
		"correct": 1,
		"explanation": "Starting at q0: 'a' → q1, 'a' → q0, 'a' → q1. Final state q1 is accepting, so the string 'aaa' is accepted."
	},
	{
		"id": 2,
		"skill": "simulation",
		"question": "A DFA has states {A, B, C}, start A, accepting {C}, with δ(A, '0') = A, δ(A, '1') = B, δ(B, '0') = C, δ(B, '1') = B, δ(C, '0') = C, δ(C, '1') = C. Which of the following strings is ACCEPTED?",
		"options": [
			"'01'",
			"'10'",
			"'00'",
			"'11'"
		],
		"correct": 1,
		"explanation": "'10': A --1--> B --0--> C. Final state C is accepting, so '10' is accepted. '01': A --0--> A --1--> B (rejected). '00': A --0--> A --0--> A (rejected). '11': A --1--> B --1--> B (rejected)."
	},
	{
		"id": 3,
		"skill": "simulation",
		"question": "Consider a DFA with start state q0, accepting state q2, and transitions: δ(q0, 'x') = q1, δ(q1, 'x') = q2, δ(q2, 'x') = q2. What happens when the string 'xxx' is processed?",
		"options": [
			"Ends in q2, accepted",
			"Ends in q1, rejected",
			"Ends in q0, rejected",
			"Ends in q2, rejected"
		],
		"correct": 0,
		"explanation": "q0 --x--> q1 --x--> q2 --x--> q2. Final state q2 is accepting, so 'xxx' is accepted."
	},
	{
		"id": 4,
		"skill": "simulation",
		"question": "A DFA recognizes strings ending in 'ab'. States: q0 (start), q1, q2 (accepting). Transitions: δ(q0,'a')=q1, δ(q0,'b')=q0, δ(q1,'a')=q1, δ(q1,'b')=q2, δ(q2,'a')=q1, δ(q2,'b')=q0. Which string is REJECTED?",
		"options": [
			"'ab'",
			"'aab'",
			"'ba'",
			"'bab'"
		],
		"correct": 2,
		"explanation": "'ba': q0 --b--> q0 --a--> q1. Final state q1 is not accepting, so 'ba' is rejected. 'ab': q0--a-->q1--b-->q2 (accepted). 'aab': q0--a-->q1--a-->q1--b-->q2 (accepted). 'bab': q0--b-->q0--a-->q1--b-->q2 (accepted)."
	},
	{
		"id": 5,
		"skill": "simulation",
		"question": "Given a DFA with δ(q0, '0') = q0, δ(q0, '1') = q1, δ(q1, '0') = q2, δ(q1, '1') = q1, δ(q2, '0') = q2, δ(q2, '1') = q2, start q0, accepting {q2}. The string '101' is processed. What is the final state?",
		"options": [
			"q0",
			"q1",
			"q2",
			"Undefined"
		],
		"correct": 2,
		"explanation": "q0 --1--> q1 --0--> q2 --1--> q2. Final state is q2."
	},

	# ===== IDENTIFICATION OF DIAGRAM (4 questions) =====
	{
		"id": 6,
		"skill": "identification",
		"question": "A diagram shows a machine with multiple transitions from a single state on the same input symbol, and includes ε-transitions. This diagram represents a(n):",
		"options": [
			"DFA",
			"NFA",
			"ε-NFA",
			"Both B and C"
		],
		"correct": 3,
		"explanation": "Multiple transitions on the same symbol indicates an NFA. ε-transitions indicate an ε-NFA. Since it has both, it's an ε-NFA, which is a type of NFA, so 'Both B and C' is correct."
	},
	{
		"id": 7,
		"skill": "identification",
		"question": "A state diagram has exactly one transition per input symbol from every state, and no ε-transitions. This is a:",
		"options": [
			"DFA",
			"NFA",
			"ε-NFA",
			"Turing Machine"
		],
		"correct": 0,
		"explanation": "A DFA has exactly one transition per input symbol from each state, with no ε-transitions. This is the defining characteristic of a DFA."
	},
	{
		"id": 8,
		"skill": "identification",
		"question": "You see a diagram where state q0 has δ(q0, 'a') = {q1, q2}. This is NOT a DFA because:",
		"options": [
			"It has multiple accepting states",
			"It has multiple transitions on the same symbol from one state",
			"It has no start state",
			"It has too few states"
		],
		"correct": 1,
		"explanation": "A DFA requires exactly one transition per input symbol from each state. Having δ(q0, 'a') = {q1, q2} means multiple possible next states, which is a characteristic of an NFA, not a DFA."
	},
	{
		"id": 9,
		"skill": "identification",
		"question": "Which of the following is a valid DFA diagram characteristic?",
		"options": [
			"Multiple start states",
			"ε-transitions between states",
			"Exactly one transition per input symbol from each state",
			"Transitions that consume no input"
		],
		"correct": 2,
		"explanation": "A DFA has exactly one transition per input symbol from each state. It has a single start state, no ε-transitions, and every transition consumes exactly one input symbol."
	},

	# ===== DFA DEFINITION AND PARTS (5 questions) =====
	{
		"id": 10,
		"skill": "definition",
		"question": "What is the formal 5-tuple definition of a DFA?",
		"options": [
			"(Q, Σ, δ, q0, F)",
			"(Q, Σ, δ, F, q0)",
			"(Σ, Q, δ, q0, F)",
			"(Q, δ, Σ, q0, F)"
		],
		"correct": 0,
		"explanation": "A DFA is formally defined as a 5-tuple (Q, Σ, δ, q0, F) where Q is the set of states, Σ is the input alphabet, δ is the transition function, q0 is the start state, and F is the set of accepting states."
	},
	{
		"id": 11,
		"skill": "definition",
		"question": "In the DFA 5-tuple (Q, Σ, δ, q0, F), what does 'δ' represent?",
		"options": [
			"The set of accepting states",
			"The transition function",
			"The input alphabet",
			"The start state"
		],
		"correct": 1,
		"explanation": "δ (delta) is the transition function that maps (state, input symbol) pairs to a next state: δ: Q × Σ → Q."
	},
	{
		"id": 12,
		"skill": "definition",
		"question": "What does 'F' represent in the DFA 5-tuple?",
		"options": [
			"The set of all states",
			"The input alphabet",
			"The set of accepting (final) states",
			"The transition function"
		],
		"correct": 2,
		"explanation": "F is the set of accepting (or final) states, a subset of Q. A string is accepted by the DFA if processing it ends in a state that is in F."
	},
	{
		"id": 13,
		"skill": "definition",
		"question": "What is the role of q0 in a DFA?",
		"options": [
			"It is the only accepting state",
			"It is the start (initial) state",
			"It is the state that processes the last symbol",
			"It is the transition function"
		],
		"correct": 1,
		"explanation": "q0 is the start (initial) state. All processing of input strings begins at q0. It is a single, unique state in Q."
	},
	{
		"id": 14,
		"skill": "definition",
		"question": "Which of the following is TRUE about the transition function δ in a DFA?",
		"options": [
			"It can be undefined for some inputs",
			"It can return multiple states",
			"It must be defined for every state and every input symbol",
			"It can include ε-transitions"
		],
		"correct": 2,
		"explanation": "In a DFA, δ must be a total function: defined for every state in Q and every symbol in Σ. It returns exactly one next state, and there are no ε-transitions."
	},

	# ===== DFA BUILDING (5 questions) =====
	{
		"id": 15,
		"skill": "building",
		"question": "To build a DFA that accepts strings ending with '01', what is the minimum number of states needed?",
		"options": [
			"2 states",
			"3 states",
			"4 states",
			"5 states"
		],
		"correct": 1,
		"explanation": "A DFA for strings ending in '01' needs 3 states: one to track 'no progress', one to track 'just saw 0', and one accepting state for 'just saw 01'."
	},
	{
		"id": 16,
		"skill": "building",
		"question": "When building a DFA that accepts strings with an even number of 'a's, what is the key design consideration?",
		"options": [
			"Use one state to track parity (even/odd)",
			"Use one state per character in the alphabet",
			"Use a state for each possible string length",
			"Use ε-transitions to skip characters"
		],
		"correct": 0,
		"explanation": "For parity tracking, you need 2 states: one for 'even count so far' and one for 'odd count so far'. Each 'a' toggles between them. This is the minimal DFA design."
	},
	{
		"id": 17,
		"skill": "building",
		"question": "You need to build a DFA for the language {w | w contains the substring 'aba'}. What is the correct approach?",
		"options": [
			"Track the longest suffix of 'aba' seen so far",
			"Create a state for every possible string",
			"Use a single state with self-loops",
			"Use ε-transitions to handle the substring"
		],
		"correct": 0,
		"explanation": "The standard approach is to track how much of 'aba' has been matched as a suffix. States represent: no match, matched 'a', matched 'ab', and matched 'aba' (accepting, with self-loop)."
	},
	{
		"id": 18,
		"skill": "building",
		"question": "When constructing a DFA, what must be true about the start state?",
		"options": [
			"It must also be an accepting state",
			"There must be exactly one start state",
			"It must have no incoming transitions",
			"It must be labeled q0"
		],
		"correct": 1,
		"explanation": "A DFA has exactly one start state. It may or may not be accepting, may have incoming transitions, and can be labeled with any name (q0 is conventional but not required)."
	},
	{
		"id": 19,
		"skill": "building",
		"question": "To build a DFA that accepts strings over {0,1} with at least one '1', the minimal DFA has:",
		"options": [
			"1 state",
			"2 states",
			"3 states",
			"4 states"
		],
		"correct": 1,
		"explanation": "2 states: q0 (start, no '1' seen yet, non-accepting) and q1 (at least one '1' seen, accepting). On '0', q0 stays at q0 and q1 stays at q1. On '1', both go to q1."
	},

	# ===== DFA FROM REGEX (4 questions) =====
	{
		"id": 20,
		"skill": "regex",
		"question": "The regular expression a*b represents which language?",
		"options": [
			"Strings with one or more 'a's followed by one 'b'",
			"Strings with zero or more 'a's followed by one 'b'",
			"Strings with 'a' and 'b' in any order",
			"Strings ending with 'ab'"
		],
		"correct": 1,
		"explanation": "The '*' (Kleene star) means zero or more. So a*b means zero or more 'a's followed by exactly one 'b'."
	},
	{
		"id": 21,
		"skill": "regex",
		"question": "To convert the regex (a|b)* to a DFA, the language is:",
		"options": [
			"All strings over {a, b}",
			"Only the empty string",
			"Strings with only 'a's",
			"Strings with only 'b's"
		],
		"correct": 0,
		"explanation": "(a|b)* means zero or more of either 'a' or 'b', which is all possible strings over the alphabet {a, b}. The DFA needs just 1 state (accepting) with self-loops on both 'a' and 'b'."
	},
	{
		"id": 22,
		"skill": "regex",
		"question": "The regex (ab)+ represents:",
		"options": [
			"Zero or more repetitions of 'ab'",
			"One or more repetitions of 'ab'",
			"Exactly one 'ab'",
			"Strings containing 'a' and 'b' separately"
		],
		"correct": 1,
		"explanation": "The '+' operator means one or more. So (ab)+ means one or more repetitions of the string 'ab': ab, abab, ababab, etc."
	},
	{
		"id": 23,
		"skill": "regex",
		"question": "Which DFA would accept the language defined by the regex 0*10*?",
		"options": [
			"A DFA that accepts strings with exactly one '1'",
			"A DFA that accepts strings with at least one '1'",
			"A DFA that accepts strings ending in '1'",
			"A DFA that accepts only the string '10'"
		],
		"correct": 0,
		"explanation": "0*10* means zero or more 0s, then exactly one 1, then zero or more 0s. So the language is all strings over {0,1} with exactly one '1'."
	},

	# ===== DFA FROM SET BUILDER (4 questions) =====
	{
		"id": 24,
		"skill": "set_builder",
		"question": "The set builder notation {w ∈ {a,b}* | w ends with 'a'} defines:",
		"options": [
			"All strings ending with 'a'",
			"All strings starting with 'a'",
			"All strings containing 'a'",
			"All strings of length 1"
		],
		"correct": 0,
		"explanation": "The notation reads: 'the set of all strings w over alphabet {a,b} such that w ends with the character a'. This is the language of all strings ending in 'a'."
	},
	{
		"id": 25,
		"skill": "set_builder",
		"question": "For the set {w ∈ {0,1}* | |w| is even}, what DFA design is needed?",
		"options": [
			"2 states tracking even/odd length",
			"1 state with self-loops",
			"3 states for length tracking",
			"A state for each possible length"
		],
		"correct": 0,
		"explanation": "Track parity of string length: q0 (even length, accepting) and q1 (odd length, non-accepting). Each input symbol toggles between them."
	},
	{
		"id": 26,
		"skill": "set_builder",
		"question": "The set {w ∈ {a,b}* | w contains at least two 'a's} requires a DFA with:",
		"options": [
			"2 states",
			"3 states",
			"4 states",
			"5 states"
		],
		"correct": 1,
		"explanation": "3 states: q0 (0 'a's seen), q1 (1 'a' seen), q2 (2+ 'a's seen, accepting). On 'a', move to the next state. On 'b', stay in the current state."
	},
	{
		"id": 27,
		"skill": "set_builder",
		"question": "The set builder {w ∈ {0,1}* | w does NOT contain '00'} represents:",
		"options": [
			"All strings without consecutive zeros",
			"All strings without any zeros",
			"All strings with at least one zero",
			"All strings ending in zero"
		],
		"correct": 0,
		"explanation": "The condition 'does NOT contain 00' means no two consecutive zeros appear anywhere in the string. This is the language of strings without the substring '00'."
	},

	# ===== DFA FROM LIST (3 questions) =====
	{
		"id": 28,
		"skill": "list",
		"question": "Given the list of accepted strings {ε, a, aa, aaa, ...} (all strings of only 'a's), the DFA should:",
		"options": [
			"Accept all strings of 'a's, reject any string with 'b'",
			"Accept only 'a' and 'aa'",
			"Accept strings with both 'a' and 'b'",
			"Reject the empty string"
		],
		"correct": 0,
		"explanation": "The list represents the language a* (all strings of 'a's including empty). The DFA needs 2 states: q0 (accepting, start) and q1 (trap state for any 'b'). On 'a', stay at q0. On 'b', go to q1."
	},
	{
		"id": 29,
		"skill": "list",
		"question": "The list of strings {ab, aab, aaab, ...} represents the language:",
		"options": [
			"a+b (one or more 'a's followed by one 'b')",
			"ab* (one 'a' followed by zero or more 'b's)",
			"(ab)* (zero or more repetitions of 'ab')",
			"a*b (zero or more 'a's followed by one 'b')"
		],
		"correct": 0,
		"explanation": "The pattern is one or more 'a's followed by exactly one 'b'. This is a+b in regex notation. The DFA needs 3 states: q0 (start), q1 (saw at least one 'a'), q2 (accepting, saw the 'b')."
	},
	{
		"id": 30,
		"skill": "list",
		"question": "Given the list {01, 001, 0001, ...} (strings with one or more 0s followed by a 1), what is the minimal DFA design?",
		"options": [
			"3 states: track 'no 0s yet', 'saw 0s', 'saw the 1' (accepting)",
			"2 states: one for 0s, one for 1s",
			"4 states: one per character position",
			"1 state with self-loops"
		],
		"correct": 0,
		"explanation": "3 states: q0 (start, no 0s yet), q1 (saw one or more 0s), q2 (accepting, saw the final 1). On '0' at q0, go to q1. On '0' at q1, stay at q1. On '1' at q1, go to q2. Any other transition goes to a trap state."
	}
]

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