extends RefCounted
## Hidden Markov Model (HMM) for knowledge tracing.
## FULLY SELF-CONTAINED: owns its parameters, observation history, prediction
## history, and its own accuracy metrics. One instance per skill.
##
## Hidden states: "knows" / "doesn't know". Visible states: answer right/wrong.

# --- Model parameters ---
var p_learn: float = 0.1      # P("doesn't know" -> "knows")  (learning rate)
var p_forget: float = 0.05    # P("knows" -> "doesn't know")   (forgetting rate)
var p_guess: float = 0.2      # P(correct  | doesn't know)     (guessing)
var p_slip: float = 0.1       # P(wrong    | knows)            (slipping)

# --- Hidden state ---
var p_knows: float = 0.3      # P(learner knows the skill)

# --- History ---
var observations: Array = []     # bool per answer (true = correct)
var observation_count: int = 0
var prediction_log: Array = []   # {predicted: float, correct: bool, phase: String}

func _init(initial_p_knows: float = 0.3, learn_rate: float = 0.1, forget_rate: float = 0.05, guess_rate: float = 0.2, slip_rate: float = 0.1) -> void:
	p_knows = initial_p_knows
	p_learn = learn_rate
	p_forget = forget_rate
	p_guess = guess_rate
	p_slip = slip_rate

## Update the model with a new observation (true = correct, false = incorrect)
func update(correct: bool) -> void:
	observations.append(correct)
	observation_count += 1
	
	# Forward algorithm for HMM filtering
	# First, apply the transition (learning/forgetting)
	var p_knows_after_transition: float = p_knows * (1.0 - p_forget) + (1.0 - p_knows) * p_learn
	
	# Then apply the observation likelihood
	var likelihood_correct: float = p_knows_after_transition * (1.0 - p_slip) + (1.0 - p_knows_after_transition) * p_guess
	var likelihood_wrong: float = p_knows_after_transition * p_slip + (1.0 - p_knows_after_transition) * (1.0 - p_guess)
	
	var likelihood: float = likelihood_correct if correct else likelihood_wrong
	
	# Bayes update
	if correct:
		p_knows = (p_knows_after_transition * (1.0 - p_slip)) / likelihood
	else:
		p_knows = (p_knows_after_transition * p_slip) / likelihood
	
	# Clamp to avoid numerical issues
	p_knows = clampf(p_knows, 0.001, 0.999)

## Get the current probability the learner knows this skill
func get_knowledge_probability() -> float:
	return p_knows

## Get the current mastery level (0-100)
func get_mastery_percentage() -> float:
	return p_knows * 100.0

## Check if the skill is considered "learned" (mastered)
func is_learned(threshold: float = 0.7) -> bool:
	return p_knows >= threshold

## Get the expected probability of answering correctly on the next question
func get_expected_accuracy() -> float:
	return p_knows * (1.0 - p_slip) + (1.0 - p_knows) * p_guess

## Reset the model to initial state
func reset() -> void:
	p_knows = 0.3
	observations.clear()
	observation_count = 0

## Get a summary of the model state
func get_summary() -> Dictionary:
	return {
		"p_knows": p_knows,
		"p_learn": p_learn,
		"p_forget": p_forget,
		"p_guess": p_guess,
		"p_slip": p_slip,
		"observations": observations.duplicate(),
		"observation_count": observation_count,
		"mastery_percentage": get_mastery_percentage(),
		"is_learned": is_learned()
	}

## Serialize to dictionary for saving
func to_dict() -> Dictionary:
	return {
		"p_knows": p_knows,
		"p_learn": p_learn,
		"p_forget": p_forget,
		"p_guess": p_guess,
		"p_slip": p_slip,
		"observations": observations.duplicate(),
		"observation_count": observation_count
	}

## Load from dictionary
func from_dict(data: Dictionary) -> void:
	p_knows = data.get("p_knows", 0.3)
	p_learn = data.get("p_learn", 0.1)
	p_forget = data.get("p_forget", 0.05)
	p_guess = data.get("p_guess", 0.2)
	p_slip = data.get("p_slip", 0.1)
	observations = data.get("observations", []).duplicate()
	observation_count = data.get("observation_count", observations.size())
