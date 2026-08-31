extends RefCounted
## Deep Knowledge Tracing (DKT) algorithm.
## FULLY SELF-CONTAINED: owns its weights, observation history, prediction
## history, and its own accuracy metrics. A single network tracks all skills.
## Simplified neural network: one hidden layer (tanh) + sigmoid output per skill.

# Network architecture
const INPUT_SIZE := 14  # 7 skills × 2 (correct/wrong one-hot)
const HIDDEN_SIZE := 16
const OUTPUT_SIZE := 7  # One output per skill (knowledge probability)

# Network weights
var w1: Array = []  # INPUT_SIZE × HIDDEN_SIZE
var b1: Array = []  # HIDDEN_SIZE
var w2: Array = []  # HIDDEN_SIZE × OUTPUT_SIZE
var b2: Array = []  # OUTPUT_SIZE

# Learning rate
var learning_rate: float = 0.1

# Skill order (must match question_bank.gd SKILLS keys)
const SKILL_ORDER := ["simulation", "identification", "definition", "building", "regex", "set_builder", "list"]

# --- History ---
var observations: Array = []          # {skill: String, correct: bool}
var observation_count: int = 0
var prediction_log: Array = []        # {skill, predicted, correct, phase}

# Current knowledge state per skill
var knowledge_state: Dictionary = {}

func _init(lr: float = 0.1) -> void:
	learning_rate = lr
	_initialize_weights()
	_reset_knowledge_state()

func _initialize_weights() -> void:
	# Xavier/Glorot initialization
	var fan_in := float(INPUT_SIZE)
	var fan_out := float(HIDDEN_SIZE)
	var limit1 := sqrt(6.0 / (fan_in + fan_out))
	
	w1.clear()
	b1.clear()
	for i in range(INPUT_SIZE):
		var row := []
		for j in range(HIDDEN_SIZE):
			row.append(randf_range(-limit1, limit1))
		w1.append(row)
	for j in range(HIDDEN_SIZE):
		b1.append(0.0)
	
	fan_in = float(HIDDEN_SIZE)
	fan_out = float(OUTPUT_SIZE)
	var limit2 := sqrt(6.0 / (fan_in + fan_out))
	
	w2.clear()
	b2.clear()
	for i in range(HIDDEN_SIZE):
		var row := []
		for j in range(OUTPUT_SIZE):
			row.append(randf_range(-limit2, limit2))
		w2.append(row)
	for j in range(OUTPUT_SIZE):
		b2.append(0.0)

func _reset_knowledge_state() -> void:
	knowledge_state.clear()
	for skill in SKILL_ORDER:
		knowledge_state[skill] = 0.3

## Update the model with a new observation. Records the prediction the network
## made BEFORE seeing the answer so the model can score its own accuracy.
func update(skill: String, correct: bool, phase: String = "learning") -> void:
	# Self-record: what would the net have predicted for this skill, pre-outcome?
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
	
	# Build input vector (one-hot for the skill + correct/wrong)
	var input_vec := _build_input(skill, correct)
	
	# Forward pass
	var hidden := _forward_hidden(input_vec)
	var output := _forward_output(hidden)
	
	# Target: 1.0 for the observed skill if correct, 0.0 if wrong
	var target := 0.0
	if correct:
		target = 1.0
	
	var skill_idx := SKILL_ORDER.find(skill)
	
	# Backpropagation
	_backpropagate(input_vec, hidden, output, skill_idx, target)
	
	# Update knowledge state for the observed skill
	knowledge_state[skill] = output[skill_idx]

## How well did THIS network's predictions match reality? (per-skill and overall)
## A prediction is a "hit" when it points the right way (pred > 0.5 and correct,
## or pred <= 0.5 and wrong).
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

## Build the input vector for the network
func _build_input(skill: String, correct: bool) -> Array:
	var input_vec := []
	input_vec.resize(INPUT_SIZE)
	input_vec.fill(0.0)
	
	var skill_idx := SKILL_ORDER.find(skill)
	if skill_idx >= 0:
		var base := skill_idx * 2
		input_vec[base] = 1.0 if correct else 0.0
		input_vec[base + 1] = 1.0 if not correct else 0.0
	
	return input_vec

## Forward pass through hidden layer (tanh activation)
func _forward_hidden(input_vec: Array) -> Array:
	var hidden := []
	hidden.resize(HIDDEN_SIZE)
	for j in range(HIDDEN_SIZE):
		var sum: float = float(b1[j])
		for i in range(INPUT_SIZE):
			sum += float(input_vec[i]) * float(w1[i][j])
		hidden[j] = tanh(sum)
	return hidden

## Forward pass through output layer (sigmoid activation)
func _forward_output(hidden: Array) -> Array:
	var output := []
	output.resize(OUTPUT_SIZE)
	for j in range(OUTPUT_SIZE):
		var sum: float = float(b2[j])
		for i in range(HIDDEN_SIZE):
			sum += float(hidden[i]) * float(w2[i][j])
		output[j] = 1.0 / (1.0 + exp(-sum))
	return output

## Backpropagation to update weights
func _backpropagate(input_vec: Array, hidden: Array, output: Array, skill_idx: int, target: float) -> void:
	# Output layer error
	var output_error := []
	output_error.resize(OUTPUT_SIZE)
	output_error.fill(0.0)
	
	for j in range(OUTPUT_SIZE):
		var expected := 0.0
		if j == skill_idx:
			expected = target
		# Cross-entropy derivative: (output - target)
		output_error[j] = output[j] - expected
	
	# Hidden layer error
	var hidden_error := []
	hidden_error.resize(HIDDEN_SIZE)
	hidden_error.fill(0.0)
	
	for i in range(HIDDEN_SIZE):
		var sum := 0.0
		for j in range(OUTPUT_SIZE):
			sum += output_error[j] * w2[i][j]
		# tanh derivative: 1 - tanh^2
		hidden_error[i] = sum * (1.0 - hidden[i] * hidden[i])
	
	# Update output layer weights
	for i in range(HIDDEN_SIZE):
		for j in range(OUTPUT_SIZE):
			w2[i][j] -= learning_rate * output_error[j] * hidden[i]
	for j in range(OUTPUT_SIZE):
		b2[j] -= learning_rate * output_error[j]
	
	# Update hidden layer weights
	for i in range(INPUT_SIZE):
		for j in range(HIDDEN_SIZE):
			w1[i][j] -= learning_rate * hidden_error[j] * input_vec[i]
	for j in range(HIDDEN_SIZE):
		b1[j] -= learning_rate * hidden_error[j]

## Get the current knowledge probability for a specific skill
func get_knowledge_probability(skill: String) -> float:
	return knowledge_state.get(skill, 0.3)

## Get the current mastery level (0-100) for a specific skill
func get_mastery_percentage(skill: String) -> float:
	return get_knowledge_probability(skill) * 100.0

## Check if a skill is considered "learned" (mastered)
func is_learned(skill: String, threshold: float = 0.7) -> bool:
	return get_knowledge_probability(skill) >= threshold

## Get the expected probability of answering correctly for a skill
func get_expected_accuracy(skill: String) -> float:
	return get_knowledge_probability(skill)

## Get all knowledge probabilities
func get_all_knowledge() -> Dictionary:
	return knowledge_state.duplicate()

## Reset the model
func reset() -> void:
	_initialize_weights()
	_reset_knowledge_state()
	observations.clear()
	observation_count = 0
	prediction_log.clear()

## Get a summary of the model state
func get_summary() -> Dictionary:
	return {
		"knowledge_state": knowledge_state.duplicate(),
		"observations": observations.duplicate(),
		"observation_count": observation_count,
		"prediction_stats": get_prediction_stats(),
		"learning_rate": learning_rate
	}

## Serialize to dictionary for saving
func to_dict() -> Dictionary:
	return {
		"w1": w1,
		"b1": b1,
		"w2": w2,
		"b2": b2,
		"learning_rate": learning_rate,
		"knowledge_state": knowledge_state,
		"observations": observations.duplicate(),
		"observation_count": observation_count,
		"prediction_log": prediction_log.duplicate(true)
	}

## Load from dictionary
func from_dict(data: Dictionary) -> void:
	w1 = data.get("w1", [])
	b1 = data.get("b1", [])
	w2 = data.get("w2", [])
	b2 = data.get("b2", [])
	learning_rate = data.get("learning_rate", 0.1)
	knowledge_state = data.get("knowledge_state", {})
	observations = data.get("observations", []).duplicate()
	observation_count = data.get("observation_count", observations.size())
	prediction_log = data.get("prediction_log", []).duplicate(true)
	
	# Ensure weights are initialized if not present
	if w1.is_empty() or w2.is_empty():
		_initialize_weights()
	if knowledge_state.is_empty():
		_reset_knowledge_state()
