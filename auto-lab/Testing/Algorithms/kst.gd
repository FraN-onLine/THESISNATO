extends RefCounted
## Knowledge Space Tracing (KST) algorithm.
## FULLY SELF-CONTAINED: owns its knowledge state, observation history,
## prediction history, and its own accuracy metrics. One instance tracks
## ALL 6 skills at once (they share one knowledge space).
##
## Based on Knowledge Space Theory (Doignon & Falmagne): a learner's
## knowledge is a STATE — the set of skills they have mastered. Skills are
## linked by PREREQUISITE edges. Demonstrating a skill lifts its
## prerequisites (downward closure of the state); a skill whose
## prerequisites are all mastered gets a readiness bonus on its learning
## transition. This is what lets KST discover cross-skill structure that
## fixed-parameter models cannot.

# ---- Learning space -------------------------------------------------
## Prerequisite lattice over the 6 DFA skills: skill X requires the skills
## listed for X. The knowledge state is closed downward: mastering X
## implies (with high confidence) mastering everything X requires.
const PREREQUISITES := {
	"simulation": ["definition"],
	"identification": ["definition"],
	"building": ["definition", "simulation"],
	"set_builder": ["building"],
	"list": ["building"],
	"definition": [],
}

## Learning-transition bonus when all prerequisites of a skill are mastered.
const READINESS_BONUS := 0.25
## Implication strength used in the downward closure of the state.
const IMPLICATION := 0.95

# ---- Response parameters (KST-side observation model) ----
var p_guess: float = 0.2
var p_slip: float = 0.1
var p_learn: float = 0.15

# ---- Knowledge state: skill -> P(mastered) ----
var knowledge_state: Dictionary = {}

# ---- History ----
var observations: Array = []          # {skill: String, correct: bool}
var observation_count: int = 0
var prediction_log: Array = []        # {skill, predicted, correct, phase}

func _init(initial_state: float = 0.3) -> void:
	_reset_state(initial_state)

func _reset_state(initial_state: float = 0.3) -> void:
	knowledge_state.clear()
	for skill in PREREQUISITES.keys():
		knowledge_state[skill] = initial_state

## Seed every skill's starting mastery from PRETEST performance.
## Called once after the pretest, before any learning updates. This is the
## KST "initial knowledge state" estimate.
func seed_from_pretest(priors: Dictionary) -> void:
	for skill in knowledge_state.keys():
		knowledge_state[skill] = clampf(float(priors.get(skill, 0.3)), 0.05, 0.95)
	_apply_closure()

## Update the model with a new observation. Records the prediction the
## space made BEFORE seeing the answer so it can score its own accuracy.
func update(skill: String, correct: bool, phase: String = "learning") -> void:
	prediction_log.append({
		"skill": skill,
		"predicted": get_expected_accuracy(skill),
		"correct": correct,
		"phase": phase,
	})
	if prediction_log.size() > 4000:
		prediction_log.pop_front()
	observations.append({"skill": skill, "correct": correct})
	observation_count += 1
	_update_skill(skill, correct)
	_apply_closure()

## Bayesian update on ONE skill, with the readiness bonus from its
## prerequisite fringe (KST's cross-skill effect).
func _update_skill(skill: String, correct: bool) -> void:
	var p: float = knowledge_state.get(skill, 0.3)
	var learn_eff := p_learn
	if _prerequisites_mastered(skill):
		learn_eff = minf(p_learn + READINESS_BONUS, 0.9)
	var p_after: float = p * (1.0 - p_slip) + (1.0 - p) * learn_eff
	var p_correct: float = p_after * (1.0 - p_slip) + (1.0 - p_after) * p_guess
	if correct:
		p = (p_after * (1.0 - p_slip)) / p_correct
	else:
		p = (p_after * p_slip) / (1.0 - p_correct)
	knowledge_state[skill] = clampf(p, 0.001, 0.999)

func _prerequisites_mastered(skill: String, threshold: float = 0.7) -> bool:
	for prereq in PREREQUISITES.get(skill, []):
		if knowledge_state.get(prereq, 0.0) < threshold:
			return false
	return true

## Downward closure: knowing a skill implies knowing its prerequisites.
## Two passes so chains (list -> building -> definition) propagate fully.
func _apply_closure() -> void:
	for _pass in range(2):
		for skill in knowledge_state.keys():
			var p_skill: float = knowledge_state[skill]
			for prereq in PREREQUISITES.get(skill, []):
				var floor_p: float = p_skill * IMPLICATION
				if knowledge_state[prereq] < floor_p:
					knowledge_state[prereq] = floor_p
## ---- Public accessors (the knowledge_tracer facade uses these) ----

## Current P(mastered) for one skill.
func get_knowledge_probability(skill: String) -> float:
	return knowledge_state.get(skill, 0.3)

## Current mastery level (0-100) for a specific skill.
func get_mastery_percentage(skill: String) -> float:
	return get_knowledge_probability(skill) * 100.0

## Check if a skill is considered "learned" (mastered).
func is_learned(skill: String, threshold: float = 0.7) -> bool:
	return get_knowledge_probability(skill) >= threshold

## Expected probability of answering correctly for a skill.
func get_expected_accuracy(skill: String) -> float:
	return get_knowledge_probability(skill)

## All knowledge probabilities.
func get_all_knowledge() -> Dictionary:
	return knowledge_state.duplicate()

## How well did the space's predictions match reality? {hits, total, accuracy}
func get_prediction_stats() -> Dictionary:
	var hits := 0
	for entry in prediction_log:
		if (entry["predicted"] > 0.5) == entry["correct"]:
			hits += 1
	return {
		"hits": hits,
		"total": prediction_log.size(),
		"accuracy": (float(hits) / float(prediction_log.size()) * 100.0) if prediction_log.size() > 0 else 0.0,
	}

## Reset the model.
func reset() -> void:
	_reset_state(0.3)
	observations.clear()
	observation_count = 0
	prediction_log.clear()

## Summary of the model state.
func get_summary() -> Dictionary:
	return {
		"knowledge_state": knowledge_state.duplicate(),
		"prerequisites": PREREQUISITES.duplicate(),
		"observations": observations.duplicate(),
		"observation_count": observation_count,
		"prediction_stats": get_prediction_stats(),
	}

## Serialize to dictionary for saving.
func to_dict() -> Dictionary:
	return {
		"knowledge_state": knowledge_state.duplicate(),
		"observations": observations.duplicate(),
		"observation_count": observation_count,
		"prediction_log": prediction_log.duplicate(true)
	}

## Load from dictionary.
func from_dict(data: Dictionary) -> void:
	knowledge_state = data.get("knowledge_state", {}).duplicate()
	observations = data.get("observations", []).duplicate()
	observation_count = data.get("observation_count", observations.size())
	prediction_log = data.get("prediction_log", []).duplicate(true)
	if knowledge_state.is_empty():
		_reset_state(0.3)
