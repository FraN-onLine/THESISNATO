extends RefCounted
## Algorithm Catalog — the "somewhere" where the knowledge-tracing algorithms are
## fully described so a learner (and a thesis panel) can read how each one works,
## what data it needs, and exactly how it learns through the three phases:
##
##   1. PRETEST  -> pretest answers are the ONLY input / starting elements.
##   2. LEARNING -> interactive answers are analysed to detect mastery and
##                  learning terminates the moment the model says the user knows.
##   3. POST TEST-> a no-feedback test that proves (or disproves) the model's
##                  picture of the learner.
##
## The catalog is read by the Algorithm Select screen (before the Testing Grounds)
## and by the in-game Algorithm Library / stats boards.

const TYPE_HMM := 0
const TYPE_BKT := 1
const TYPE_KST := 2

const ALGORITHMS := {
	TYPE_HMM: {
		"type": TYPE_HMM,
		"name": "HMM (Hidden Markov Model)",
		"callout": "HMM",
		"tagline": "Bayesian filtering over a hidden 'knows / doesn't know' state per skill.",
		"accent": Color(0.35, 0.8, 1.0, 1.0),
		"how_works": "Each DFA skill is its own small Hidden Markov Model with two HIDDEN states: 'knows' and 'doesn't know'. The learner's answers (right / wrong) are the only VISIBLE states. Every answer runs one step of the forward algorithm:\n  1. TRANSITION — a small learning probability P(T) can flip 'doesn't know -> knows' and a forgetting probability P(F) can flip 'knows -> doesn't know'.\n  2. LIKELIHOOD — the answer is explained by P(slip) when the learner knows and P(guess) when they do not.\n  3. BAYES UPDATE — the posterior P(knows | answer) is computed with Bayes' rule, so a correct answer raises the estimate and a wrong one lowers it.\nThe hidden state is never observed directly - the model can only infer it from answers, which is exactly what a real 'is the user learning?' tracker must do.",
		"formula": "P(knows_t) = P(knows_{t-1})*(1 - P_forget) + (1 - P(knows_{t-1})) * P_learn\nP(answer=correct) = P(knows_t)*(1 - P_slip) + (1 - P(knows_t))*P_guess\nP(knows_t | answer) = ( P(answer | knows_t) * P(knows_t) ) / P(answer)",
		"params": [
			{"symbol": "P(learn)", "name": "Learning rate", "meaning": "Chance a 'doesn't know' hidden state becomes 'knows' after one practice."},
			{"symbol": "P(forget)", "name": "Forgetting rate", "meaning": "Chance a 'knows' hidden state slips back to 'doesn't know'."},
			{"symbol": "P(guess)", "name": "Guessing", "value": 0.25, "meaning": "Default chance of a correct answer despite not knowing; configurable per model."},
			{"symbol": "P(slip)", "name": "Slipping", "meaning": "Chance of a wrong answer despite knowing."},
		],
		"best_for": "Explainable, per-skill probability estimates that behave smoothly even with very little data (an ideal fit for a 6-skill DFA pretest).",
		"limit": "Assumes each skill is independent: it cannot learn that building skill also improves the set_builder skill unless observations for both are seen.",
		"needs": {
			"inputs": "PRETEST answers ONLY. Each pretest answer is a single observation (skill, right/wrong) and is the ONLY starting input given to the model.",
			"learning": "Interactive learning answers are analysed one by one; every new answer re-filters the hidden state.",
			"termination": "The skill is judged mastered when P(knows) >= 70% after at least 3 learning observations. Learning for that skill terminates immediately.",
			"proof": "The post test runs WITHOUT feedback. If the post-test behaviour matches what the model predicted, the model's theory of the learner is confirmed.",
		},
		"pipeline": [
			{"stage": 1, "name": "PRETEST — only input", "icon": "1",
			 "text": "All pretest answers are fed in as the model's starting evidence. The algorithm begins from the pretest and nothing else."},
			{"stage": 2, "name": "INTERACTIVE LEARNING — analyse & terminate", "icon": "2",
			 "text": "Each practice answer updates P(knows) with Bayes. The moment the model decides the skill is mastered it TERMINATES that topic's learning."},
			{"stage": 3, "name": "POST TEST — prove the theory", "icon": "3",
			 "text": "A fresh, no-feedback test is run. The model's earlier predictions are scored against real post-test answers to prove the theory."},
		],
		"needs_summary": "Needs: pretest answers as seeds, interactive answers to update, and a post test to verify.",
	},
	TYPE_BKT: {
		"type": TYPE_BKT,
		"name": "BKT (Bayesian Knowledge Tracing)",
		"callout": "BKT",
		"tagline": "The classic 4-parameter per-skill model used in intelligent tutoring systems.",
		"accent": Color(0.95, 0.75, 0.3, 1.0),
		"how_works": "BKT is the classic knowledge-tracing model from intelligent tutoring systems (Corbett & Anderson, 1995). Each skill keeps four parameters:\n  P(L0) — the learner's chance of already knowing the skill before the first practice.\n  P(T)  — the chance the learner LEARNS the skill after one more practice opportunity.\n  P(G)  — the chance of GUESSING a correct answer while still not knowing.\n  P(S)  — the chance of SLIPPING (a careless wrong answer) while actually knowing.\nEvery answer re-weights P(Learned) using Bayes: first apply P(T) (learning opportunity), then scale by the likelihood of the observed answer. Mastery requires repeated evidence — several consecutive updates pushed past the threshold — so it is intentionally conservative and easy to explain in a thesis.",
		"formula": "P(L_t) = P(L_{t-1})*(1 - P(S)) + (1 - P(L_{t-1})) * P(T)\nP(correct) = P(L_t)*(1 - P(S)) + (1 - P(L_t)) * P(G)\nanswer correct : P(L_t|correct) = P(L_t)*(1 - P(S)) / P(correct)\nanswer wrong   : P(L_t|wrong)   = P(L_t)*P(S) / (1 - P(correct))",
		"params": [
			{"symbol": "P(L0)", "name": "Prior knowledge", "meaning": "Initial chance the learner already knows the skill before practice."},
			{"symbol": "P(T)", "name": "Transition / learning", "meaning": "Chance of acquiring the skill after one practice opportunity."},
			{"symbol": "P(G)", "name": "Guess", "meaning": "Chance of a correct answer without knowledge."},
			{"symbol": "P(S)", "name": "Slip", "meaning": "Chance of a wrong answer with knowledge."},
		],
		"best_for": "A small, explainable model with only 4 parameters per skill; its parameters are already the language of education research.",
		"limit": "Parameters are fixed up front (no per-learner fit in this prototype) and it treats guesses/slips as constant per skill.",
		"needs": {
			"inputs": "PRETEST answers ONLY. P(L0) is the pretest-informed start and every pretest answer is folded into the posterior as starting evidence.",
			"learning": "Each interactive practice answer is one more Bayesian update — the posteriors after the pretest continue to be refined live.",
			"termination": "Mastery means P(Learned) >= 70% sustained over at least 3 interactive observations; the topic terminates the instant that holds.",
			"proof": "The post test is a hold-out: its answers were never tuned on, so matching post-test behaviour verifies the BKT theory of the learner.",
		},
		"pipeline": [
			{"stage": 1, "name": "PRETEST — only input", "icon": "1",
			 "text": "BKT seeds P(L0) and consumes every pretest answer as starting posterior evidence. Nothing else initialises the model."},
			{"stage": 2, "name": "INTERACTIVE LEARNING — analyse & terminate", "icon": "2",
			 "text": "Every practice observation reweights P(Learned). When the model sees >= 3 observations and P(Learned) >= 70% it terminates the topic."},
			{"stage": 3, "name": "POST TEST — prove the theory", "icon": "3",
			 "text": "Post-test answers, never used for fitting, are predicted before being seen and scored to confirm the model."},
		],
		"needs_summary": "Needs: pretest answers as P(L0) seeds, interactive updates, post-test verification.",
	},
	TYPE_KST: {
		"type": TYPE_KST,
		"name": "KST (Knowledge Space Tracing)",
		"callout": "KST",
		"tagline": "A knowledge-space model: mastering one DFA skill lights up its prerequisites.",
		"accent": Color(0.65, 1.0, 0.55, 1.0),
		"how_works": "KST models the learner knowledge as a SPACE of skill states connected by PREREQUISITE edges: definition -> identification/simulation -> building -> set_builder/list. Every skill carries a mastery probability SEEDED from the pretest, and every answer updates the observed skill with Bayes rule. The KST twist is propagation: mastering a higher skill lifts its prerequisites (downward closure of the knowledge state), and a skill whose prerequisites are all mastered gets a readiness bonus on its learning transition. One knowledge space covers all six DFA skills at once, so the model explains both what the learner knows and what has just come within reach.",
		"formula": "P(master | answer) via Bayes, with P(answer | master) = 1 - P(slip) and P(answer | not master) = P(guess\nreadiness: if all prerequisites >= 70%, the learning transition gains +0.25\nclosure: P(prerequisite) >= 0.95 * P(mastered child)",
		"params": [
			{"symbol": "P(learn)", "name": "Learning rate", "meaning": "How strongly one answer moves a skill toward mastery."},
			{"symbol": "Readiness", "name": "Fringe bonus", "meaning": "Extra learning strength when every prerequisite is already mastered."},
			{"symbol": "Closure", "name": "Implication strength", "meaning": "Mastering a skill implies its prerequisites are mastered too."},
		],
		"best_for": "Modelling the DFA curriculum as a STRUCTURE: one correct board build lifts an entire neighbourhood of skills at once, mirroring how automata topics build on each other.",
		"limit": "Quality depends on the prerequisite lattice being right; if two DFA skills are truly independent, KST propagates evidence that is not really there.",
		"needs": {
			"inputs": "PRETEST answers ONLY. Per-skill pretest accuracy becomes the starting knowledge state (the KST prior).",
			"learning": "Each interactive answer updates the observed skill, then the closure pass re-derives the whole space.",
			"termination": "A skill is terminated as learnt when its mastery probability >= 70% after >= 3 learning observations.",
			"proof": "The post test runs WITHOUT feedback; matching the model state predictions proves the space captured the learner.",
		},
		"pipeline": [
			{"stage": 1, "name": "PRETEST - only input", "icon": "1",
			 "text": "Pretest accuracy per skill seeds the knowledge state - the model starting picture of the learner."},
			{"stage": 2, "name": "INTERACTIVE LEARNING - analyse & terminate", "icon": "2",
			 "text": "Every practice answer updates the space and propagates through prerequisites; a skill ends the moment it is mastered."},
			{"stage": 3, "name": "POST TEST - prove the theory", "icon": "3",
			 "text": "A no-feedback post test checks whether the inferred knowledge state predicted real behaviour."},
		],
		"needs_summary": "Needs: pretest-derived starting state, prerequisite lattice, live updates with closure, hold-out post test.",
	},
}

## The full description dictionary for one algorithm type. Every screen and the
## thesis write-up read the model through these small, single-purpose getters, so
## a missing key can never crash the UI.
static func catalog_info(algo_type: int) -> Dictionary:
	if ALGORITHMS.has(algo_type):
		return ALGORITHMS[algo_type]
	return ALGORITHMS[TYPE_HMM]

static func catalog_name(algo_type: int) -> String:
	return str(catalog_info(algo_type).get("name", "HMM (Hidden Markov Model)"))

static func catalog_tagline(algo_type: int) -> String:
	return str(catalog_info(algo_type).get("tagline", ""))

static func catalog_best_for(algo_type: int) -> String:
	return str(catalog_info(algo_type).get("best_for", ""))

static func catalog_limit(algo_type: int) -> String:
	return str(catalog_info(algo_type).get("limit", ""))

static func catalog_params(algo_type: int) -> Array:
	return catalog_info(algo_type).get("params", [])

static func catalog_needs_summary(algo_type: int) -> String:
	return str(catalog_info(algo_type).get("needs_summary", ""))

static func catalog_how_works(algo_type: int) -> String:
	return str(catalog_info(algo_type).get("how_works", ""))

static func catalog_formula(algo_type: int) -> String:
	return str(catalog_info(algo_type).get("formula", ""))

static func catalog_callout(algo_type: int) -> String:
	return str(catalog_info(algo_type).get("callout", "HMM"))

static func catalog_accent(algo_type: int) -> Color:
	return catalog_info(algo_type).get("accent", Color(1, 1, 1, 1))

static func catalog_pipeline(algo_type: int) -> Array:
	return catalog_info(algo_type).get("pipeline", [])

static func catalog_needs(algo_type: int) -> Dictionary:
	return catalog_info(algo_type).get("needs", {})

static func catalog_all_types() -> Array:
	return [TYPE_HMM, TYPE_BKT, TYPE_KST]

## The three-phase flow the user asked to "track and show":
##  1. Pretest data ONLY as input/starting elements
##  2. Interactive learning to analyse learning, terminate when learnt
##  3. Post test to prove the theory
static func catalog_pipeline_summary(algo_type: int) -> String:
	var lines: Array[String] = []
	for step in catalog_pipeline(algo_type):
		lines.append("  [%s] %s — %s" % [step["icon"], step["name"], step["text"]])
	return "\n".join(lines)

static func catalog_how_learns_flavor(algo_type: int) -> String:
	var n: Dictionary = catalog_needs(algo_type)
	return "HOW THIS ALGORITHM LEARNS THROUGH THE 3 PHASES\n1. INPUT (pretest only)\n%s\n\n2. LEARNING (analyse + terminate)\n%s\n%s\n\n3. POST TEST (prove the theory)\n%s" % [
	n.get("inputs", ""),
	n.get("learning", ""),
	n.get("termination", ""),
	n.get("proof", ""),
]
