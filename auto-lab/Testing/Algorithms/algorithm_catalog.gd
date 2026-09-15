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
const TYPE_DKT := 2

const ALGORITHMS := {
	TYPE_HMM: {
		"type": TYPE_HMM,
		"name": "HMM (Hidden Markov Model)",
		"callout": "HMM",
		"tagline": "Bayesian filtering over a hidden 'knows / doesn't know' state per skill.",
		"accent": Color(0.35, 0.8, 1.0, 1.0),
		"how_works": """Each DFA skill is its own small Hidden Markov Model with two HIDDEN states: "knows" and "doesn't know". The learner's answers (right / wrong) are the only VISIBLE states. Every answer runs one step of the forward algorithm:
  1. TRANSITION — a small learning probability P(T) can flip "doesn't know -> knows" and a forgetting probability P(F) can flip "knows -> doesn't know".
  2. LIKELIHOOD — the answer is explained by P(slip) when the learner knows and P(guess) when they do not.
  3. BAYES UPDATE — the posterior P(knows | answer) is computed with Bayes' rule, so a correct answer raises the estimate and a wrong one lowers it.
The hidden state is never observed directly - the model can only infer it from answers, which is exactly what a real "is the user learning?" tracker must do.""",
		"formula": """P(knows_t) = P(knows_{t-1})*(1 - P_forget) + (1 - P(knows_{t-1})) * P_learn
P(answer=correct) = P(knows_t)*(1 - P_slip) + (1 - P(knows_t))*P_guess
P(knows_t | answer) = ( P(answer | knows_t) * P(knows_t) ) / P(answer)""",
		"params": [
			{"symbol": "P(learn)", "name": "Learning rate", "meaning": "Chance a 'doesn't know' hidden state becomes 'knows' after one practice."},
			{"symbol": "P(forget)", "name": "Forgetting rate", "meaning": "Chance a 'knows' hidden state slips back to 'doesn't know'."},
			{"symbol": "P(guess)", "name": "Guessing", "meaning": "Chance of a correct answer despite not knowing."},
			{"symbol": "P(slip)", "name": "Slipping", "meaning": "Chance of a wrong answer despite knowing."},
		],
		"best_for": "Explainable, per-skill probability estimates that behave smoothly even with very little data (an ideal fit for a 7-skill DFA pretest).",
		"limit": "Assumes each skill is independent: it cannot learn that building skill also improves regex skill unless observations for both are seen.",
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
		"how_works": """BKT is the classic knowledge-tracing model from intelligent tutoring systems (Corbett & Anderson, 1995). Each skill keeps four parameters:
  P(L0) — the learner's chance of already knowing the skill before the first practice.
  P(T)  — the chance the learner LEARNS the skill after one more practice opportunity.
  P(G)  — the chance of GUESSING a correct answer while still not knowing.
  P(S)  — the chance of SLIPPING (a careless wrong answer) while actually knowing.
Every answer re-weights P(Learned) using Bayes: first apply P(T) (learning opportunity), then scale by the likelihood of the observed answer. Mastery requires repeated evidence — several consecutive updates pushed past the threshold — so it is intentionally conservative and easy to explain in a thesis.""",
		"formula": """P(L_t) = P(L_{t-1})*(1 - P(S)) + (1 - P(L_{t-1})) * P(T)
P(correct) = P(L_t)*(1 - P(S)) + (1 - P(L_t)) * P(G)
answer correct : P(L_t|correct) = P(L_t)*(1 - P(S)) / P(correct)
answer wrong   : P(L_t|wrong)   = P(L_t)*P(S) / (1 - P(correct))""",
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
	TYPE_DKT: {
		"type": TYPE_DKT,
		"name": "DKT (Deep Knowledge Tracing)",
		"callout": "DKT",
		"tagline": "A small neural network that learns cross-skill transfer from the answer stream.",
		"accent": Color(0.65, 1.0, 0.55, 1.0),
		"how_works": """DKT replaces hand-chosen parameters with a small neural network. The input is a one-hot encoding of (skill, correctness) for the last answer — 7 skills x 2 = 14 inputs. A hidden layer (16 tanh neurons) feeds a sigmoid output per skill that predicts each skill's next-answer probability. After every answer the network is trained by back-propagation, so it discovers patterns the fixed-parameter models cannot: e.g. that doing well at regex often predicts set-builder skill. In this prototype one shared network tracks all seven skills at once, which is what lets it learn cross-skill transfer.""",
		"formula": """input   = one-hot(skill, correct)          (14 units)
hidden  = tanh(W1 * input + b1)              (16 units)
output  = sigmoid(W2 * hidden + b2)          (1 unit per skill)
loss    = cross_entropy(output[skill], target)  -> back-propagate""",
		"params": [
			{"symbol": "W1 / W2", "name": "Weights", "meaning": "Xavier-initialised network weights learned from every answer."},
			{"symbol": "b1 / b2", "name": "Biases", "meaning": "Per-layer additive biases."},
			{"symbol": "lr", "name": "Learning rate", "meaning": "Step size for gradient descent after each answer (0.1)."},
			{"symbol": "14-16-7", "name": "Architecture", "meaning": "14 inputs -> 16 hidden tanh -> 7 sigmoid skill outputs."},
		],
		"best_for": "Capturing correlations between skills (transfer learning) and detecting subtle answer patterns across the whole pretest stream.",
		"limit": "Needs more data to stabilise; a single 30-question pretest gives the network only a tiny training set, so its early predictions are noisy.",
		"needs": {
			"inputs": "PRETEST answers ONLY. The answer stream (skill, right/wrong) is the entire training set the network starts from.",
			"learning": "Each interactive answer is a fresh training example: forward pass, back-propagation, and the skill's knowledge output is updated.",
			"termination": "A skill's output sigmoid >= 70% after >= 3 interactive examples means the network believes the user has learnt it; that topic ends there.",
			"proof": "The post test is a held-out sequence the network never back-propagated on, so its predictions there prove whether the learned theory generalised.",
		},
		"pipeline": [
			{"stage": 1, "name": "PRETEST — only input", "icon": "1",
			 "text": "The pretest answer stream is the ONLY training data. The network is initialised and fitted from it - no other features."},
			{"stage": 2, "name": "INTERACTIVE LEARNING — analyse & terminate", "icon": "2",
			 "text": "Live examples are back-propagated every answer. When the sigmoid output for a skill exceeds 70% the topic is terminated as learnt."},
			{"stage": 3, "name": "POST TEST — prove the theory", "icon": "3",
			 "text": "Post-test answers are held out from training; scoring the network's predictions on them proves (or refutes) the learned representation."},
		],
		"needs_summary": "Needs: pretest stream as training data, live back-prop from practice, hold-out post test to prove generalisation.",
	},
}

static func catalog_info(algo_type: int) -> Dictionary:
	return ALGORITHMS.get(algo_type, ALGORITHMS[TYPE_HMM])

static func catalog_name(algo_type: int) -> String:
	return str(catalog_info(algo_type).get("name", "HMM"))

static func catalog_tagline(algo_type: int) -> String:
	return str(catalog_info(algo_type).get("tagline", ""))

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
	return [TYPE_HMM, TYPE_BKT, TYPE_DKT]

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
	return """HOW THIS ALGORITHM LEARNS THROUGH THE 3 PHASES
1. INPUT (pretest only)
%s

2. LEARNING (analyse + terminate)
%s
%s

3. POST TEST (prove the theory)
%s""" % [
	n.get("inputs", ""),
	n.get("learning", ""),
	n.get("termination", ""),
	n.get("proof", ""),
]
