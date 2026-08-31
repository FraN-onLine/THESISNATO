extends RefCounted
## Bayesian Knowledge Tracing (BKT) algorithm.
## FULLY SELF-CONTAINED: owns its parameters, observation history, prediction
## history, and its own accuracy metrics. One instance per skill.
## Classic BKT model with 4 parameters per skill.

# BKT parameters
var p_L0: float = 0.3       # Initial probability of knowing the skill
var p_T: float = 0.1        # Probability of learning the skill after one opportunity (transition)
var p_G: float = 0.2        # Probability of guessing correctly when not knowing
var p_S: float = 0.1        # Probability of slipping (answering wrong when knowing)

# Current knowledge state
var p_learned: float = 0.3

# --- History ---
var observations: Array = []     # bool per answer (true = correct)
var observation_count: int = 0
var prediction_log: Array = []   # {predicted: float, correct: bool, phase: String}

func _init(initial_p_learned: float = 0.3, transition_p: float = 0.1, guess_p: float = 0.2, slip_p: float = 0.1) -> void:
	p_L0 = initial_p_learned
	p_T = transition_p
	p_G = guess_p
	p_S = slip_p
	p_learned = initial_p_learned

## Update the model with a new observation (true = correct, false = incorrect).
## Records the prediction this model would have made BEFORE seeing the answer,
## so the model can score its own accuracy.
func update(correct: bool, phase: String = "learning") -> void:
	# Self-record: what did we predict the learner would answer, before the outcome?
	prediction_log.append({
		"predicted": get_expected_accuracy(),
		"correct": correct,
		"phase": phase,
	})
	if prediction_log.size() > 4000:
		prediction_log.pop_front()
	observations.append(correct)
	observation_count += 1
	
	# BKT update formula:
	# P(L_t | evidence) = P(evidence | L_t) * P(L_t) / P(evidence)
	# where P(L_t) = P(L_{t-1}) * (1 - P_S) + (1 - P(L_{t-1})) * P_T
	
	# Step 1: Apply transition (learning opportunity)
	var p_learned_before: float = p_learned
	var p_learned_after_transition: float = p_learned_before * (1.0 - p_S) + (1.0 - p_learned_before) * p_T
	
	# Step 2: Apply observation likelihood
	var p_correct: float = p_learned_after_transition * (1.0 - p_S) + (1.0 - p_learned_after_transition) * p_G
	
	if correct:
		# P(L_t | correct) = P(L_t) * (1 - P_S) / P(correct)
		p_learned = (p_learned_after_transition * (1.0 - p_S)) / p_correct
	else:
		# P(L_t | wrong) = P(L_t) * P_S / (1 - P(correct))
		p_learned = (p_learned_after_transition * p_S) / (1.0 - p_correct)
	
	# Clamp to avoid numerical issues
	p_learned = clampf(p_learned, 0.001, 0.999)

## How well did THIS model's predictions match reality?
## A prediction is a "hit" when it points the right way (pred > 0.5 and correct,
## or pred <= 0.5 and wrong). Returns {hits, total, accuracy}.
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

## Get the current probability the learner knows this skill
func get_knowledge_probability() -> float:
	return p_learned

## Get the current mastery level (0-100)
func get_mastery_percentage() -> float:
	return p_learned * 100.0

## Check if the skill is considered "learned" (mastered)
func is_learned(threshold: float = 0.7) -> bool:
	return p_learned >= threshold

## Get the expected probability of answering correctly on the next question
func get_expected_accuracy() -> float:
	return p_learned * (1.0 - p_S) + (1.0 - p_learned) * p_G

## Reset the model to initial state
func reset() -> void:
	p_learned = p_L0
	observations.clear()
	observation_count = 0
	prediction_log.clear()

## Get a summary of the model state
func get_summary() -> Dictionary:
	return {
		"p_learned": p_learned,
		"p_L0": p_L0,
		"p_T": p_T,
		"p_G": p_G,
		"p_S": p_S,
		"observations": observations.duplicate(),
		"observation_count": observation_count,
		"prediction_stats": get_prediction_stats(),
		"mastery_percentage": get_mastery_percentage(),
		"is_learned": is_learned()
	}

## Serialize to dictionary for saving
func to_dict() -> Dictionary:
	return {
		"p_learned": p_learned,
		"p_L0": p_L0,
		"p_T": p_T,
		"p_G": p_G,
		"p_S": p_S,
		"observations": observations.duplicate(),
		"observation_count": observation_count,
		"prediction_log": prediction_log.duplicate(true)
	}

## Load from dictionary
func from_dict(data: Dictionary) -> void:
	p_learned = data.get("p_learned", 0.3)
	p_L0 = data.get("p_L0", 0.3)
	p_T = data.get("p_T", 0.1)
	p_G = data.get("p_G", 0.2)
	p_S = data.get("p_S", 0.1)
	observations = data.get("observations", []).duplicate()
	observation_count = data.get("observation_count", observations.size())
	prediction_log = data.get("prediction_log", []).duplicate(true)
