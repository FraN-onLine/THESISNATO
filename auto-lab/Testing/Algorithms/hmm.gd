extends RefCounted
## Hidden Markov Model (HMM) for knowledge tracing.
## FULLY SELF-CONTAINED: owns its parameters, observation history, prediction
## history, and its own accuracy metrics. One instance per skill.
##
## Hidden states: Beginner / Developing / Mastered (a 3-state mastery ladder).
## Visible states: answer right/wrong. Belief is a probability VECTOR
## [P(Beginner), P(Developing), P(Mastered)] that always sums to 1.

# --- Model parameters (kept for compatibility / reporting) ---
var p_learn: float = 0.1      # learning magnitude baked into the transition matrix
var p_forget: float = 0.05    # forgetting magnitude baked into the transition matrix
var p_guess: float = 0.2      # P(correct | Beginner)
var p_slip: float = 0.1       # P(wrong   | Mastered)

# --- 3-state transition matrix A (rows = from, cols = to: B, D, M) ---
const TRANSITION := [
	[0.75, 0.23, 0.02],
	[0.05, 0.75, 0.20],
	[0.01, 0.04, 0.95],
]
# --- Emission matrix B (rows = state B/D/M, cols = [P(correct), P(wrong)]) ---
const EMISSION := [
	[0.25, 0.75],
	[0.60, 0.40],
	[0.92, 0.08],
]
const STATE_NAMES := ["Beginner", "Developing", "Mastered"]

# --- Hidden state: the belief vector is the single source of truth ---
var _belief: Array = [0.25, 0.50, 0.25]
## The initial mastery, remembered so reset() restores THIS model instead of a
## hard-coded default (a model seeded by the pretest priors resets to its start).
var p_knows0: float = 0.3

## p_knows is a COMPATIBILITY view over the belief vector: reading it returns the
## scalar mastery (0.5*P(Developing) + 1.0*P(Mastered)); writing it re-derives the
## belief vector from that mastery (this is how the pretest priors seed the model).
var p_knows: float = 0.3:
	set(value):
		p_knows0 = clampf(value, 0.0, 1.0)
		_belief = _belief_from_mastery(p_knows0)
	get():
		return _mastery()

# --- History ---
var observations: Array = []     # bool per answer (true = correct)
var observation_count: int = 0
var prediction_log: Array = []   # {predicted: float, correct: bool, phase: String}
var last_visible_output := ""

func _init(initial_p_knows: float = 0.3, learn_rate: float = 0.1, forget_rate: float = 0.05, guess_rate: float = 0.2, slip_rate: float = 0.1) -> void:
	p_learn = learn_rate
	p_forget = forget_rate
	p_guess = guess_rate
	p_slip = slip_rate
	p_knows0 = clampf(initial_p_knows, 0.0, 1.0)
	_belief = _belief_from_mastery(p_knows0)

## Scalar mastery (0-1) implied by the belief vector.
func _mastery() -> float:
	return clampf(0.5 * float(_belief[1]) + 1.0 * float(_belief[2]), 0.0, 1.0)

## Derive an initial belief vector from a mastery scalar (the pretest PI seed):
##   P(Mastered)   = m^2,  P(Beginner) = (1-m)^2,  P(Developing) = remainder.
func _belief_from_mastery(m: float) -> Array:
	var pm := clampf(m, 0.0, 1.0)
	var pi_m := pm * pm
	var pi_b := (1.0 - pm) * (1.0 - pm)
	var pi_d := clampf(1.0 - pi_m - pi_b, 0.0, 1.0)
	return [pi_b, pi_d, pi_m]

## Update the model with a new observation (true = correct, false = incorrect).
## Records the prediction this model would have made BEFORE seeing the answer,
## so the model can score its own accuracy.
func update(correct: bool, phase: String = "learning") -> void:
	last_visible_output = "correct" if correct else "wrong"
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
	
	# Forward algorithm for HMM FILTERING over the 3-state belief vector.
	# Step 1 - PREDICT: alpha'(j) = sum_i alpha(i) * A(i -> j)
	var pred := [0.0, 0.0, 0.0]
	for i in range(3):
		var ai: float = float(_belief[i])
		for j in range(3):
			pred[j] += ai * float(TRANSITION[i][j])
	# Step 2 - UPDATE: alpha_new(j) proportional to alpha'(j) * B_j(obs), then normalize
	var col: int = 0 if correct else 1
	var post := [0.0, 0.0, 0.0]
	var total := 0.0
	for j in range(3):
		post[j] = pred[j] * float(EMISSION[j][col])
		total += post[j]
	if total <= 0.0:
		# Numerically degenerate: fall back to the predicted distribution.
		_belief = pred
	else:
		for j in range(3):
			post[j] = clampf(post[j] / total, 0.0005, 0.999)
		# Re-normalize after clamping so the vector still sums to 1.
		var s: float = float(post[0]) + float(post[1]) + float(post[2])
		_belief = [float(post[0]) / s, float(post[1]) / s, float(post[2]) / s]

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

## Get the current probability the learner knows this skill (compat scalar).
func get_knowledge_probability() -> float:
	return _mastery()

## Get the current mastery level (0-100).
func get_mastery_percentage() -> float:
	return _mastery() * 100.0

## Check if the skill is considered "learned" (mastered).
func is_learned(threshold: float = 0.7) -> bool:
	return _mastery() >= threshold

## Get the expected probability of answering correctly on the next question:
##   sum_i P(state_i) * P(correct | state_i).
func get_expected_accuracy() -> float:
	var acc := 0.0
	for i in range(3):
		acc += float(_belief[i]) * float(EMISSION[i][0])
	return clampf(acc, 0.0, 1.0)

## The inferred mastery STATE for the board: Beginner / Developing / Mastered,
## using the bands Beginner 0-25% / Developing 25-85% / Mastered 85-100%.
func get_state() -> Dictionary:
	var m := _mastery()
	var label := STATE_NAMES[0]
	if m >= 0.85:
		label = STATE_NAMES[2]
	elif m >= 0.25:
		label = STATE_NAMES[1]
	return {
		"label": label,
		"mastery": m,
		"beliefs": _belief.duplicate(),
	}

## HMM view data: the 3 hidden-state beliefs plus the latest visible observation.
## (knows / does_not_know are kept for backward compatibility with older readers.)
func get_state_view() -> Dictionary:
	var b: float = float(_belief[0])
	var d: float = float(_belief[1])
	var m: float = float(_belief[2])
	return {
		"hidden_states": {"beginner": b, "developing": d, "mastered": m,
			"knows": d + m, "does_not_know": b},
		"state": get_state(),
		"visible_output": last_visible_output,
		"expected_accuracy": get_expected_accuracy(),
	}

## Reset the model to initial state
func reset() -> void:
	_belief = _belief_from_mastery(p_knows0)
	observations.clear()
	observation_count = 0
	prediction_log.clear()
	last_visible_output = ""

## A skipped task (the learner used the board's Skip option) is NOT an answer, so
## it never enters the observation history. It is a "give up" signal, and it costs
## in proportion to how much of the skill is still UNKNOWN:
##   p_new = p - strength * (1 - p)
## so skipping a skill the learner has not learnt is heavily punished, while
## skipping a skill already close to mastered costs almost nothing.
## Returns the probability that was removed.
func penalize_skip(strength: float = 0.5) -> float:
	var before: float = _mastery()
	var after: float = clampf(before - strength * (1.0 - before), 0.0, 1.0)
	_belief = _belief_from_mastery(after)
	return before - after

## Get a summary of the model state
func get_summary() -> Dictionary:
	var st: Dictionary = get_state()
	return {
		"p_knows": _mastery(),
		"belief": _belief.duplicate(),
		"state": st["label"],
		"p_learn": p_learn,
		"p_forget": p_forget,
		"p_guess": p_guess,
		"p_slip": p_slip,
		"observations": observations.duplicate(),
		"observation_count": observation_count,
		"prediction_stats": get_prediction_stats(),
		"mastery_percentage": get_mastery_percentage(),
		"is_learned": is_learned()
		,"last_visible_output": last_visible_output
	}

## Serialize to dictionary for saving
func to_dict() -> Dictionary:
	return {
		"belief": _belief.duplicate(),
		"p_knows": _mastery(),
		"p_knows0": p_knows0,
		"p_learn": p_learn,
		"p_forget": p_forget,
		"p_guess": p_guess,
		"p_slip": p_slip,
		"observations": observations.duplicate(),
		"observation_count": observation_count,
		"prediction_log": prediction_log.duplicate(true)
		,"last_visible_output": last_visible_output
	}

## Load from dictionary (supports both 3-state saves and legacy scalar saves).
func from_dict(data: Dictionary) -> void:
	p_learn = data.get("p_learn", 0.1)
	p_forget = data.get("p_forget", 0.05)
	p_guess = data.get("p_guess", 0.2)
	p_slip = data.get("p_slip", 0.1)
	var raw_belief = data.get("belief")
	if raw_belief is Array and (raw_belief as Array).size() == 3:
		var b: Array = (raw_belief as Array).duplicate()
		var s: float = float(b[0]) + float(b[1]) + float(b[2])
		_belief = [float(b[0]) / s, float(b[1]) / s, float(b[2]) / s] if s > 0.0 else [0.25, 0.5, 0.25]
		p_knows0 = float(data.get("p_knows0", _mastery()))
	else:
		# Legacy save with only the scalar: re-derive the belief from it.
		p_knows0 = float(data.get("p_knows0", data.get("p_knows", 0.3)))
		_belief = _belief_from_mastery(p_knows0)
	observations = data.get("observations", []).duplicate()
	observation_count = data.get("observation_count", observations.size())
	prediction_log = data.get("prediction_log", []).duplicate(true)
	last_visible_output = str(data.get("last_visible_output", ""))
