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

## Preloaded only for its mastery-gate CONSTANTS: the learner-facing briefing
## quotes the gate the room really applies, so the two can never drift apart.
const Tracer = preload("res://Testing/Algorithms/knowledge_tracer.gd")

const ALGORITHMS := {
	TYPE_HMM: {
		"type": TYPE_HMM,
		"name": "HMM (Hidden Markov Model)",
		"callout": "HMM",
		"tagline": "Bayesian filtering over hidden mastery states (Beginner / Developing / Mastered) per skill.",
		"accent": Color(0.35, 0.8, 1.0, 1.0),
		"how_works": "Each DFA skill is its own small Hidden Markov Model with three HIDDEN mastery states: Beginner, Developing, Mastered. The learner's answers (right / wrong) are the only VISIBLE states. Every answer runs one vector step of the forward algorithm:\n  1. TRANSITION — the 3x3 transition matrix A shifts belief between Beginner, Developing and Mastered (a learning step lifts it, a small forgetting step lowers it).\n  2. LIKELIHOOD — the answer is scored by the emission matrix B: the chance of a correct or wrong answer from each of the three states.\n  3. BAYES UPDATE — the belief vector is re-weighted by that likelihood and normalized, so a correct answer pushes mass toward Mastered and a wrong one pulls it back toward Beginner.\nThe hidden state is never observed directly - the model can only infer it from answers, which is exactly what a real 'is the user learning?' tracker must do.",
		"formula": "alpha(j) = sum_i alpha(i) * A(i->j)   [predict with 3x3 transition matrix A]\nB_j(obs) = P(obs | state j)   [3x2 emission matrix, obs = correct/wrong]\nalpha_new(j) = alpha'(j) * B_j(obs) / sum_k alpha'(k) * B_k(obs)   [Bayes reweight + normalize]",
		"params": [
			{"symbol": "P(learn)", "name": "Learning rate", "short": "chance belief steps UP a state (Beginner->Developing, Developing->Mastered)",
			 "meaning": "Chance a 'doesn't know' hidden state becomes 'knows' after one practice."},
			{"symbol": "P(forget)", "name": "Forgetting rate", "short": "chance belief steps DOWN a state (Mastered->Developing, Developing->Beginner)",
			 "meaning": "Chance a 'knows' hidden state slips back to 'doesn't know'."},
			{"symbol": "P(guess)", "name": "Guessing", "value": 0.25, "short": "chance of a correct answer from the Beginner state (emission matrix)",
			 "meaning": "Default chance of a correct answer despite not knowing; configurable per model."},
			{"symbol": "P(slip)", "name": "Slipping", "short": "chance of a wrong answer from the Mastered state (emission matrix)",
			 "meaning": "Chance of a wrong answer despite knowing."},
			{"symbol": "Skip", "name": "Skip penalty", "short": "cost of skipping a board task = part of what is still unknown",
			 "meaning": "Using 'Skip task' removes P(strength) x (1 - mastery) of the skill, so skipping while weak hurts far more than skipping while strong."},
		],
		"best_for": "Explainable per-skill mastery STATES (Beginner / Developing / Mastered) that behave smoothly even with very little data (an ideal fit for a 6-skill DFA pretest).",
		"limit": "Assumes each skill is independent: it cannot learn that building skill also improves the set_builder skill unless observations for both are seen.",
		"states": "Beginner 0-25% / Developing 25-85% / Mastered 85-100% (from posterior mastery; inferred state shown on the board).",
		"needs": {
			"inputs": "PRETEST answers ONLY. Each pretest answer is a single observation (skill, right/wrong) and seeds the initial state distribution PI per skill (Laplace-smoothed).",
			"learning": "Interactive learning answers run vector forward-filtering per skill: predict with the 3x3 transition matrix A, then reweight by the emission matrix B. Correct answers shift belief toward Mastered, wrong answers shift it back toward Beginner.",
			"termination": "The topic terminates the moment the gate below calls it LEARNED — the posterior belief has moved into the Mastered band and practice on that skill stops immediately.",
			"proof": "The post test runs WITHOUT feedback. HMM state predictions and expected accuracy are logged per observation, so accuracy on unseen answers is the proof of the trace.",
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
			{"symbol": "P(L0)", "name": "Prior knowledge", "short": "chance the skill is already known at the start",
			 "meaning": "Initial chance the learner already knows the skill before practice."},
			{"symbol": "P(T)", "name": "Transition / learning", "short": "chance of learning it after one practice",
			 "meaning": "Chance of acquiring the skill after one practice opportunity."},
			{"symbol": "P(G)", "name": "Guess", "short": "right answer without knowing it",
			 "meaning": "Chance of a correct answer without knowledge."},
			{"symbol": "P(S)", "name": "Slip", "short": "wrong answer while knowing it",
			 "meaning": "Chance of a wrong answer with knowledge."},
			{"symbol": "Skip", "name": "Skip penalty", "short": "cost of skipping a board task = part of what is still unknown",
			 "meaning": "Using 'Skip task' removes P(strength) x (1 - mastery) of the skill, so skipping while weak hurts far more than skipping while strong."},
		],
		"best_for": "A small, explainable model with only 4 parameters per skill; its parameters are already the language of education research.",
		"limit": "Parameters are fixed up front (no per-learner fit in this prototype) and it treats guesses/slips as constant per skill.",
		"states": "Beginner while P(learned) is low, Mastered once the gate below is met — the band shown on the board is the model's own posterior, not the gate.",
		"needs": {
			"inputs": "PRETEST answers ONLY. P(L0) is the pretest-informed start and every pretest answer is folded into the posterior as starting evidence.",
			"learning": "Each interactive practice answer is one more Bayesian update — the posteriors after the pretest continue to be refined live.",
			"termination": "The topic terminates the instant the gate below calls it LEARNED; P(Learned) is the number that gate reads.",
			"proof": "The post test is a hold-out: its answers were never tuned on, so matching post-test behaviour verifies the BKT theory of the learner.",
		},
		"pipeline": [
			{"stage": 1, "name": "PRETEST — only input", "icon": "1",
			 "text": "BKT seeds P(L0) and consumes every pretest answer as starting posterior evidence. Nothing else initialises the model."},
			{"stage": 2, "name": "INTERACTIVE LEARNING — analyse & terminate", "icon": "2",
			 "text": "Every practice observation reweights P(Learned). As soon as the mastery gate is met the topic terminates and the room moves on."},
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
			{"symbol": "P(learn)", "name": "Learning rate", "short": "how hard one answer pushes a skill toward mastery",
			 "meaning": "How strongly one answer moves a skill toward mastery."},
			{"symbol": "Readiness", "name": "Fringe bonus", "short": "extra learning when all prerequisites are mastered",
			 "meaning": "Extra learning strength when every prerequisite is already mastered."},
			{"symbol": "Closure", "name": "Implication strength", "short": "mastering a skill lifts its prerequisites",
			 "meaning": "Mastering a skill implies its prerequisites are mastered too."},
			{"symbol": "Skip", "name": "Skip penalty", "short": "cost of skipping a board task = part of what is still unknown",
			 "meaning": "Using 'Skip task' removes P(strength) x (1 - mastery) of the skill, so skipping while weak hurts far more than skipping while strong."},
		],
		"best_for": "Modelling the DFA curriculum as a STRUCTURE: one correct board build lifts an entire neighbourhood of skills at once, mirroring how automata topics build on each other.",
		"limit": "Quality depends on the prerequisite lattice being right; if two DFA skills are truly independent, KST propagates evidence that is not really there.",
		"states": "A skill is 'ready' once every prerequisite is mastered; closure lifts prerequisites toward Mastered as dependants are answered correctly.",
		"needs": {
			"inputs": "PRETEST answers ONLY. Per-skill pretest accuracy becomes the starting knowledge state (the KST prior).",
			"learning": "Each interactive answer updates the observed skill, then the closure pass re-derives the whole space.",
			"termination": "A skill terminates as learnt the moment the gate below says so — after the closure pass has had its chance to lift the prerequisites that answer implies.",
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

## VERY short "SYMBOL = what it means" lines, one per parameter. Used by the
## parameter block on the Algorithm Select screen; the in-room Stats Board prints
## its own letter legend (see KnowledgeTracer.PARAM_LEGEND) next to the live
## numbers. Falls back to the longer `meaning` when a `short` text is missing.
static func catalog_param_lines(algo_type: int) -> Array[String]:
	var lines: Array[String] = []
	for param in catalog_params(algo_type):
		var symbol := str(param.get("symbol", ""))
		var text := str(param.get("short", param.get("meaning", "")))
		if symbol == "" or text == "":
			continue
		lines.append("%s = %s" % [symbol, text])
	return lines

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

## The room's real "you are knowledgeable" rule in learner-facing words, built
## from KnowledgeTracer's constants. Both roads are quoted because the models
## converge slower than a learner improves: the recent-streak road is what stops
## someone who has clearly got the topic from being held back by a lagging
## estimate (most visible with KST, whose wrong answers pull the estimate down
## hard).
static func mastery_gate_text() -> String:
	return "GATE (same for all three algorithms): a topic counts as LEARNED once %s puts its knowledge at %.0f%% or better with at least %d interactive answers seen — or as soon as the last %d answers on it are all correct. The live mastery report under each question names the road that decided it." % [
		"the active model",
		Tracer.MASTERY_THRESHOLD * 100.0,
		Tracer.MIN_EVIDENCE,
		Tracer.RECENT_WINDOW]

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
	return "HOW THIS ALGORITHM LEARNS THROUGH THE 3 PHASES\n1. INPUT (pretest only)\n%s\n\n2. LEARNING (analyse + terminate)\n%s\n%s\n%s\n\n3. POST TEST (prove the theory)\n%s" % [
	n.get("inputs", ""),
	n.get("learning", ""),
	n.get("termination", ""),
	mastery_gate_text(),
	n.get("proof", ""),
]

## NEW FORMAT briefing shared by EVERY screen (Testing Grounds briefing-first
## flow, Algorithm Select, and the confirm panel). One block per algorithm:
##   NAME - tagline
##   HOW IT LEARNS (3 phases: INPUT / LEARNING / PROVE)
##   PARAMS | BEST FOR | LIMIT | STATES
static func catalog_briefing(algo_type: int) -> String:
	var info: Dictionary = catalog_info(algo_type)
	var n: Dictionary = catalog_needs(algo_type)
	var out: Array[String] = []
	out.append("%s - %s" % [str(info.get("name", "")), str(info.get("tagline", ""))])
	out.append("HOW IT LEARNS (3 phases):")
	out.append("  1. INPUT (pretest only): %s" % str(n.get("inputs", "")))
	out.append("  2. LEARNING (analyse + terminate): %s %s" % [str(n.get("learning", "")), str(n.get("termination", ""))])
	out.append("     %s" % mastery_gate_text())
	out.append("  3. PROVE (post test): %s" % str(n.get("proof", "")))
	var param_lines: Array[String] = catalog_param_lines(algo_type)
	if not param_lines.is_empty():
		out.append("PARAMS: %s" % "  |  ".join(param_lines))
	out.append("BEST FOR: %s" % str(info.get("best_for", "")))
	out.append("LIMIT: %s" % str(info.get("limit", "")))
	var states := str(info.get("states", ""))
	if states != "":
		out.append("STATES: %s" % states)
	return "\n".join(out)
