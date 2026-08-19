extends RefCounted
## Adaptive learning content for each DFA skill.
## Follows the 7-step learning flow:
## 1. Learning Objective
## 2. Definition
## 3. Example
## 3.1 Application Example
## 4. Guided Demonstration
## 5. Interactive Challenge
## 6. Feedback
## 7. End

const CONTENT := {
	"simulation": {
		"objective": "By the end of this activity, you will be able to simulate a DFA by tracing input strings through states and determining whether strings are accepted or rejected.",
		"definition": "DFA Simulation is the process of tracing an input string through a Deterministic Finite Automaton. Starting from the initial state q0, each input symbol is consumed one at a time, following the transition function δ to move from state to state. After processing the entire string, if the final state is an accepting state (in F), the string is accepted; otherwise, it is rejected.",
		"example": "Consider a DFA with states {q0, q1}, start q0, accepting {q1}, and transitions: δ(q0, 'a') = q1, δ(q1, 'a') = q0. To simulate the string 'aa':\n\nStep 1: Start at q0\nStep 2: Read 'a' → move to q1\nStep 3: Read 'a' → move to q0\nFinal state: q0 (not accepting)\nResult: 'aa' is REJECTED",
		"application": "DFA simulation is used in real-world systems like network packet filtering. A firewall can be modeled as a DFA where each state represents a stage of packet inspection, and each input symbol represents a packet attribute. The firewall accepts (forwards) or rejects (drops) packets based on the final state after processing all packet attributes.",
		"guided": "Let's simulate together. Consider a DFA that accepts strings ending in 'b':\n\nStates: {q0, q1}\nStart: q0\nAccepting: {q1}\nTransitions: δ(q0,'a')=q0, δ(q0,'b')=q1, δ(q1,'a')=q0, δ(q1,'b')=q1\n\nLet's trace 'abab':\nq0 --a--> q0 --b--> q1 --a--> q0 --b--> q1\nFinal state: q1 (accepting)\n'abab' is ACCEPTED\n\nNow try tracing 'abba' yourself:\nq0 --a--> q0 --b--> q1 --b--> q1 --a--> ?\n\nAnswer: q0. Since δ(q1,'a')=q0, the final state is q0, which is not accepting, so 'abba' is REJECTED.",
		"challenge_questions": [
			{
				"question": "A DFA has states {A, B}, start A, accepting {B}, with δ(A, '0') = A, δ(A, '1') = B, δ(B, '0') = B, δ(B, '1') = A. Trace the string '101'. What is the final state?",
				"options": ["A", "B", "Undefined", "Both A and B"],
				"correct": 0,
				"explanation": "A --1--> B --0--> B --1--> A. Final state is A. Since A is not accepting, '101' is rejected."
			},
			{
				"question": "A DFA accepts strings ending in '01'. States: q0 (start), q1, q2 (accepting). Transitions: δ(q0,'0')=q1, δ(q0,'1')=q0, δ(q1,'0')=q1, δ(q1,'1')=q2, δ(q2,'0')=q1, δ(q2,'1')=q0. Trace '001'. What is the result?",
				"options": ["Accepted (ends in q2)", "Rejected (ends in q0)", "Rejected (ends in q1)", "Accepted (ends in q1)"],
				"correct": 0,
				"explanation": "q0 --0--> q1 --0--> q1 --1--> q2. Final state q2 is accepting, so '001' is ACCEPTED."
			},
			{
				"question": "Given a DFA with δ(q0,'x')=q1, δ(q1,'x')=q2, δ(q2,'x')=q2, start q0, accepting {q2}. Trace 'xx'. What is the result?",
				"options": ["Accepted (ends in q2)", "Rejected (ends in q1)", "Rejected (ends in q0)", "Accepted (ends in q1)"],
				"correct": 0,
				"explanation": "q0 --x--> q1 --x--> q2. Final state q2 is accepting, so 'xx' is ACCEPTED."
			}
		]
	},
	"identification": {
		"objective": "By the end of this activity, you will be able to identify DFAs and distinguish them from NFAs and ε-NFAs based on their structural characteristics.",
		"definition": "A Deterministic Finite Automaton (DFA) is a finite state machine where each state has exactly one transition for each input symbol. In contrast, an NFA (Nondeterministic Finite Automaton) can have multiple transitions on the same symbol from a single state, and an ε-NFA additionally allows transitions that consume no input (ε-transitions). Identifying a DFA means recognizing these structural differences.",
		"example": "Look at these two diagrams:\n\nDiagram A: State q0 has δ(q0, 'a') = q1 and δ(q0, 'b') = q0. Every state has exactly one transition per symbol.\n→ This is a DFA.\n\nDiagram B: State q0 has δ(q0, 'a') = {q1, q2}. Multiple transitions on 'a' from q0.\n→ This is an NFA, not a DFA.",
		"application": "In compiler design, lexical analyzers use DFAs to recognize tokens. The reason DFAs are preferred is their determinism - for any input, there is exactly one path to follow, making the recognition process efficient and predictable. NFAs are often used as intermediate representations before conversion to DFAs.",
		"guided": "Let's identify together:\n\nMachine 1: States {q0, q1}, δ(q0,'0')=q1, δ(q0,'1')=q0, δ(q1,'0')=q0, δ(q1,'1')=q1. No ε-transitions.\n→ Each state has exactly one transition per symbol. This is a DFA.\n\nMachine 2: States {q0, q1}, δ(q0,'0')={q0,q1}, δ(q0,'1')=q1, δ(q1,'0')=q0, δ(q1,'1')=q1.\n→ q0 has two transitions on '0'. This is an NFA.\n\nMachine 3: States {q0, q1}, δ(q0,'0')=q1, δ(q0,'ε')=q1, δ(q1,'0')=q0.\n→ Has an ε-transition. This is an ε-NFA.",
		"challenge_questions": [
			{
				"question": "A machine has states {q0, q1, q2}, with δ(q0, 'a') = q1, δ(q0, 'b') = q2, δ(q1, 'a') = q0, δ(q1, 'b') = q1, δ(q2, 'a') = q2, δ(q2, 'b') = q0. No ε-transitions. What is this?",
				"options": ["DFA", "NFA", "ε-NFA", "Cannot be determined"],
				"correct": 0,
				"explanation": "Every state has exactly one transition per input symbol ('a' and 'b'), and there are no ε-transitions. This is a DFA."
			},
			{
				"question": "A machine has δ(q0, '0') = {q0, q1} and δ(q0, '1') = q1. What type of automaton is this?",
				"options": ["DFA", "NFA", "ε-NFA", "Turing Machine"],
				"correct": 1,
				"explanation": "δ(q0, '0') returns a set {q0, q1} with multiple possible next states. This is a characteristic of an NFA."
			},
			{
				"question": "A machine has δ(q0, 'ε') = q1 and δ(q1, 'a') = q2. What type of automaton is this?",
				"options": ["DFA", "NFA", "ε-NFA", "Both A and B"],
				"correct": 2,
				"explanation": "The presence of an ε-transition (δ(q0, 'ε') = q1) makes this an ε-NFA. DFAs cannot have ε-transitions."
			}
		]
	},
	"definition": {
		"objective": "By the end of this activity, you will be able to define a DFA using its formal 5-tuple notation and explain each component.",
		"definition": "A Deterministic Finite Automaton (DFA) is formally defined as a 5-tuple (Q, Σ, δ, q0, F) where:\n\n• Q is a finite set of states\n• Σ is a finite set of input symbols (the alphabet)\n• δ: Q × Σ → Q is the transition function\n• q0 ∈ Q is the start (initial) state\n• F ⊆ Q is the set of accepting (final) states\n\nThe DFA processes input strings by starting at q0 and applying δ for each symbol. A string is accepted if the final state is in F.",
		"example": "Consider a DFA that accepts strings ending in 'a' over {a, b}:\n\nQ = {q0, q1}\nΣ = {a, b}\nδ(q0, a) = q1, δ(q0, b) = q0, δ(q1, a) = q1, δ(q1, b) = q0\nq0 = q0 (start state)\nF = {q1} (accepting state)\n\nThis 5-tuple completely defines the DFA.",
		"application": "The 5-tuple formalization is used in formal verification of hardware circuits. Each state in Q represents a possible configuration of circuit registers, Σ represents input signals, and δ defines how the circuit transitions between configurations. This allows engineers to mathematically verify that a circuit behaves correctly for all possible inputs.",
		"guided": "Let's break down the 5-tuple together:\n\nFor a DFA that accepts strings with an even number of '0's over {0, 1}:\n\nQ = {q_even, q_odd} - two states tracking parity\nΣ = {0, 1} - the input alphabet\nδ(q_even, 0) = q_odd, δ(q_even, 1) = q_even, δ(q_odd, 0) = q_even, δ(q_odd, 1) = q_odd\nq0 = q_even - we start with zero 0s (even)\nF = {q_even} - even count means accepting\n\nEach component serves a specific purpose in defining the automaton's behavior.",
		"challenge_questions": [
			{
				"question": "In the 5-tuple (Q, Σ, δ, q0, F), what does Q represent?",
				"options": ["The input alphabet", "The set of states", "The transition function", "The accepting states"],
				"correct": 1,
				"explanation": "Q is the finite set of states in the DFA."
			},
			{
				"question": "What is the domain and range of the transition function δ in a DFA?",
				"options": ["δ: Q × Σ → Q", "δ: Σ × Q → F", "δ: Q → Σ", "δ: F × Q → Q"],
				"correct": 0,
				"explanation": "δ maps a (state, input symbol) pair to a single next state: δ: Q × Σ → Q."
			},
			{
				"question": "If F = {q2} in a DFA, what does this mean?",
				"options": ["q2 is the start state", "q2 is the only accepting state", "q2 is the only state", "q2 is the transition function"],
				"correct": 1,
				"explanation": "F is the set of accepting states. F = {q2} means q2 is the only accepting state."
			}
		]
	},
	"building": {
		"objective": "By the end of this activity, you will be able to construct DFAs for given languages, including designing states, transitions, and identifying accepting states.",
		"definition": "DFA Building is the process of designing a Deterministic Finite Automaton that recognizes a specific language. This involves determining the minimum set of states needed, defining the transition function for each state and input symbol, and identifying which states are accepting. The key is to track the essential information needed to determine acceptance at each point in the input.",
		"example": "Let's build a DFA that accepts strings ending in 'ab' over {a, b}:\n\nStep 1: Identify what we need to track - the last 1-2 characters seen\nStep 2: States:\n  q0: no progress (start)\n  q1: just saw 'a'\n  q2: just saw 'ab' (accepting)\nStep 3: Transitions:\n  δ(q0, a) = q1, δ(q0, b) = q0\n  δ(q1, a) = q1, δ(q1, b) = q2\n  δ(q2, a) = q1, δ(q2, b) = q0\nStep 4: F = {q2}",
		"application": "DFA construction is used in text processing tools like regular expression engines. When you type a search pattern in a text editor, the engine converts the regex to an NFA and then to a DFA. The DFA is then used to efficiently scan through the text, checking each position for a match.",
		"guided": "Let's build a DFA together for strings containing 'aa' over {a, b}:\n\nStep 1: What do we need to track? Whether we've seen 0, 1, or 2+ consecutive 'a's.\n\nStep 2: States:\n  q0: no 'a' seen yet (start)\n  q1: just saw one 'a'\n  q2: saw 'aa' (accepting, stays here)\n\nStep 3: Transitions:\n  δ(q0, a) = q1, δ(q0, b) = q0\n  δ(q1, a) = q2, δ(q1, b) = q0\n  δ(q2, a) = q2, δ(q2, b) = q2\n\nStep 4: F = {q2}\n\nTest: 'aba' → q0 --a--> q1 --b--> q0 --a--> q1. Not accepted (correct, no 'aa').\nTest: 'baab' → q0 --b--> q0 --a--> q1 --a--> q2 --b--> q2. Accepted (correct, contains 'aa').",
		"challenge_questions": [
			{
				"question": "To build a DFA that accepts strings with an odd number of '1's over {0, 1}, how many states are needed?",
				"options": ["1 state", "2 states", "3 states", "4 states"],
				"correct": 1,
				"explanation": "2 states: q0 (even number of 1s, start, not accepting) and q1 (odd number of 1s, accepting). Each '1' toggles between them. '0' keeps the current state."
			},
			{
				"question": "For a DFA that accepts strings starting with 'a' over {a, b}, what is the correct design?",
				"options": [
					"q0 (start): on 'a' → q1 (accepting), on 'b' → q2 (trap). q1: on any → q1. q2: on any → q2",
					"q0 (start, accepting): on 'a' → q1, on 'b' → q0",
					"Single state with self-loops on both symbols",
					"q0 (start): on 'a' → q1, on 'b' → q1. q1 (accepting): on any → q1"
				],
				"correct": 0,
				"explanation": "q0 is the start. If the first symbol is 'a', go to accepting state q1. If it's 'b', go to trap state q2. Once in q1, stay there (all strings starting with 'a' are accepted). Once in q2, stay there (rejected)."
			},
			{
				"question": "What is the minimum number of states for a DFA that accepts the language {w | w contains at least one 'b'} over {a, b}?",
				"options": ["1 state", "2 states", "3 states", "4 states"],
				"correct": 1,
				"explanation": "2 states: q0 (no 'b' seen yet, start, not accepting) and q1 (at least one 'b' seen, accepting). On 'a', q0 stays at q0 and q1 stays at q1. On 'b', both go to q1."
			}
		]
	},
	"regex": {
		"objective": "By the end of this activity, you will be able to interpret regular expressions and convert them into equivalent DFAs.",
		"definition": "Regular expressions (regex) are a notation for describing regular languages. Key operators include: concatenation (ab means 'a' followed by 'b'), union (a|b means 'a' or 'b'), Kleene star (a* means zero or more 'a's), and plus (a+ means one or more 'a's). Converting a regex to a DFA involves understanding the language it describes and then designing a DFA that recognizes exactly that language.",
		"example": "Convert the regex a*b to a DFA:\n\nLanguage: zero or more 'a's followed by exactly one 'b'\n\nStates:\n  q0: start, haven't seen 'b' yet\n  q1: accepting, just saw the 'b'\n\nTransitions:\n  δ(q0, a) = q0 (stay, more 'a's)\n  δ(q0, b) = q1 (saw the 'b')\n  δ(q1, a) = q2 (trap - no more 'a's allowed)\n  δ(q1, b) = q2 (trap - only one 'b' allowed)\n  δ(q2, a) = q2, δ(q2, b) = q2 (trap state)\n\nF = {q1}",
		"application": "Regular expressions are used in programming languages for pattern matching. For example, validating email addresses uses a regex pattern. The regex engine internally converts the pattern to a DFA to efficiently check if input strings match the pattern. Understanding this conversion helps in writing efficient regex patterns.",
		"guided": "Let's convert (a|b)*a to a DFA together:\n\nLanguage: any string over {a, b} that ends with 'a'\n\nStep 1: What do we need to track? The last character seen.\n\nStep 2: States:\n  q0: start, no characters seen yet\n  q1: last character was 'a' (accepting)\n  q2: last character was 'b' (not accepting)\n\nStep 3: Transitions:\n  δ(q0, a) = q1, δ(q0, b) = q2\n  δ(q1, a) = q1, δ(q1, b) = q2\n  δ(q2, a) = q1, δ(q2, b) = q2\n\nStep 4: F = {q1}\n\nTest: 'aba' → q0 --a--> q1 --b--> q2 --a--> q1. Accepted (ends in 'a'). ✓\nTest: 'ab' → q0 --a--> q1 --b--> q2. Rejected (ends in 'b'). ✓",
		"challenge_questions": [
			{
				"question": "The regex (ab)* represents which language?",
				"options": [
					"Zero or more repetitions of 'ab'",
					"One or more repetitions of 'ab'",
					"All strings with 'a' and 'b'",
					"Only the string 'ab'"
				],
				"correct": 0,
				"explanation": "(ab)* means zero or more repetitions of the string 'ab': ε, ab, abab, ababab, etc."
			},
			{
				"question": "To convert the regex a(a|b)* to a DFA, the language is:",
				"options": [
					"All strings starting with 'a'",
					"All strings ending with 'a'",
					"All strings containing 'a'",
					"Only the string 'a'"
				],
				"correct": 0,
				"explanation": "a(a|b)* means one 'a' followed by zero or more of either 'a' or 'b'. This is all strings over {a,b} that start with 'a'."
			},
			{
				"question": "The regex 0*1* represents:",
				"options": [
					"Zero or more 0s followed by zero or more 1s",
					"Strings with alternating 0s and 1s",
					"Strings with at least one 0 and one 1",
					"Only the empty string"
				],
				"correct": 0,
				"explanation": "0*1* means zero or more 0s, then zero or more 1s. The language includes ε, 0, 1, 00, 01, 001, 011, 000111, etc."
			}
		]
	},
	"set_builder": {
		"objective": "By the end of this activity, you will be able to interpret set builder notation and construct DFAs that recognize the described languages.",
		"definition": "Set builder notation describes a language as {w ∈ Σ* | condition(w)}, meaning 'the set of all strings w over alphabet Σ such that condition(w) is true'. To build a DFA from set builder notation, you must understand the condition and design states that track the necessary information to determine if the condition is satisfied.",
		"example": "Build a DFA for {w ∈ {0,1}* | w contains '00'}:\n\nCondition: The string contains the substring '00'.\n\nStates:\n  q0: no '00' seen, last char wasn't '0' (start)\n  q1: no '00' seen, last char was '0'\n  q2: '00' seen (accepting)\n\nTransitions:\n  δ(q0, 0) = q1, δ(q0, 1) = q0\n  δ(q1, 0) = q2, δ(q1, 1) = q0\n  δ(q2, 0) = q2, δ(q2, 1) = q2\n\nF = {q2}",
		"application": "Set builder notation is used in database query languages. For example, SQL queries can be expressed as set builder notation: {row ∈ Table | row.age > 18}. Understanding how to translate set conditions into state machines helps in designing efficient data processing pipelines.",
		"guided": "Let's build a DFA for {w ∈ {a,b}* | w has exactly two 'a's}:\n\nStep 1: What do we need to track? The count of 'a's seen (0, 1, 2, or more than 2).\n\nStep 2: States:\n  q0: 0 'a's seen (start)\n  q1: 1 'a' seen\n  q2: 2 'a's seen (accepting)\n  q3: 3+ 'a's seen (trap, not accepting)\n\nStep 3: Transitions:\n  δ(q0, a) = q1, δ(q0, b) = q0\n  δ(q1, a) = q2, δ(q1, b) = q1\n  δ(q2, a) = q3, δ(q2, b) = q2\n  δ(q3, a) = q3, δ(q3, b) = q3\n\nStep 4: F = {q2}\n\nTest: 'aba' → q0 --a--> q1 --b--> q1 --a--> q2. Accepted (exactly 2 'a's). ✓\nTest: 'aaa' → q0 --a--> q1 --a--> q2 --a--> q3. Rejected (3 'a's). ✓",
		"challenge_questions": [
			{
				"question": "For the set {w ∈ {0,1}* | w starts with '1'}, what is the correct DFA design?",
				"options": [
					"q0 (start): on '1' → q1 (accepting), on '0' → q2 (trap). q1: on any → q1. q2: on any → q2",
					"q0 (start, accepting): on '1' → q1, on '0' → q0",
					"Single state with self-loops",
					"q0 (start): on '1' → q1, on '0' → q1. q1 (accepting): on any → q1"
				],
				"correct": 0,
				"explanation": "q0 is the start. If the first symbol is '1', go to accepting state q1. If it's '0', go to trap state q2. Once in q1, stay there (all strings starting with '1' are accepted)."
			},
			{
				"question": "The set {w ∈ {a,b}* | |w| ≥ 2} represents:",
				"options": [
					"All strings of length 2 or more",
					"All strings of exactly length 2",
					"All strings of length at most 2",
					"All strings containing 'a' and 'b'"
				],
				"correct": 0,
				"explanation": "|w| ≥ 2 means the length of w is 2 or more. This includes all strings with 2 or more characters."
			},
			{
				"question": "For {w ∈ {0,1}* | w ends with '1'}, how many states are needed?",
				"options": ["1 state", "2 states", "3 states", "4 states"],
				"correct": 1,
				"explanation": "2 states: q0 (last char wasn't '1', start) and q1 (last char was '1', accepting). On '0', both go to q0. On '1', both go to q1."
			}
		]
	},
	"list": {
		"objective": "By the end of this activity, you will be able to identify patterns from lists of strings and construct DFAs that recognize the described languages.",
		"definition": "When given a list of strings that a DFA should accept, you must identify the pattern or language that the list represents. The list may show a finite set or suggest an infinite pattern (e.g., {ε, a, aa, aaa, ...} represents a*). Once the pattern is identified, you can design a DFA that recognizes exactly that language.",
		"example": "Given the list {ε, ab, abab, ababab, ...}:\n\nPattern: Zero or more repetitions of 'ab'\nLanguage: (ab)*\n\nDFA design:\n  q0: start, expecting 'a' (accepting - zero repetitions is valid)\n  q1: just saw 'a', expecting 'b'\n  q2: trap state\n\nTransitions:\n  δ(q0, a) = q1, δ(q0, b) = q2\n  δ(q1, a) = q2, δ(q1, b) = q0\n  δ(q2, a) = q2, δ(q2, b) = q2\n\nF = {q0}",
		"application": "Pattern recognition from lists is used in data validation. For example, when validating a list of acceptable file extensions or MIME types, you can identify the pattern and build a DFA to efficiently check if a given input matches any of the accepted patterns.",
		"guided": "Let's analyze the list {a, aa, aaa, aaaa, ...}:\n\nStep 1: Identify the pattern - one or more 'a's, no 'b's.\n\nStep 2: Language: a+ (one or more 'a's)\n\nStep 3: DFA design:\n  q0: start, no 'a' seen yet (not accepting)\n  q1: saw at least one 'a' (accepting)\n  q2: trap state (saw a 'b')\n\nStep 4: Transitions:\n  δ(q0, a) = q1, δ(q0, b) = q2\n  δ(q1, a) = q1, δ(q1, b) = q2\n  δ(q2, a) = q2, δ(q2, b) = q2\n\nStep 5: F = {q1}\n\nTest: 'aaa' → q0 --a--> q1 --a--> q1 --a--> q1. Accepted. ✓\nTest: 'ab' → q0 --a--> q1 --b--> q2. Rejected. ✓",
		"challenge_questions": [
			{
				"question": "The list {01, 001, 0001, 00001, ...} represents which language?",
				"options": [
					"One or more 0s followed by a 1",
					"One 0 followed by one or more 1s",
					"Strings with alternating 0s and 1s",
					"Strings ending in 01"
				],
				"correct": 0,
				"explanation": "The pattern is one or more 0s followed by exactly one 1: 0+1. Each string has at least one 0 before the final 1."
			},
			{
				"question": "Given the list {b, ab, aab, aaab, ...}, what is the language?",
				"options": [
					"Zero or more 'a's followed by one 'b' (a*b)",
					"One or more 'a's followed by one 'b' (a+b)",
					"Strings ending in 'b'",
					"Strings starting with 'b'"
				],
				"correct": 0,
				"explanation": "The list includes 'b' (zero 'a's), 'ab' (one 'a'), 'aab' (two 'a's), etc. This is a*b: zero or more 'a's followed by one 'b'."
			},
			{
				"question": "The list {ε, 0, 1, 00, 01, 10, 11, 000, ...} represents:",
				"options": [
					"All binary strings (0|1)*",
					"Only strings of length 2 or less",
					"Strings with only 0s",
					"Strings with only 1s"
				],
				"correct": 0,
				"explanation": "The list includes the empty string, all single characters, all 2-character strings, and continues with all possible binary strings. This is (0|1)*, the set of all binary strings."
			}
		]
	}
}

static func get_content_for_skill(skill: String) -> Dictionary:
	return CONTENT.get(skill, {})

static func get_objective(skill: String) -> String:
	return CONTENT.get(skill, {}).get("objective", "")

static func get_definition(skill: String) -> String:
	return CONTENT.get(skill, {}).get("definition", "")

static func get_example(skill: String) -> String:
	return CONTENT.get(skill, {}).get("example", "")

static func get_application(skill: String) -> String:
	return CONTENT.get(skill, {}).get("application", "")

static func get_guided(skill: String) -> String:
	return CONTENT.get(skill, {}).get("guided", "")

static func get_challenge_questions(skill: String) -> Array:
	return CONTENT.get(skill, {}).get("challenge_questions", [])