extends RefCounted
## Knowledge Tracer Manager.
## Manages HMM, BKT, and DKT models for all 7 DFA skills.
## Each skill has its own HMM and BKT model. DKT is a single network.

const SKILL_ORDER := ["simulation", "identification", "definition", "building", "regex", "set_builder", "list"]

# Algorithm type selection
enum AlgorithmType { HMM, BKT, DKT }

var algorithm_type: int = AlgorithmType.HMM

# Per-skill models
var hmm_models: Dictionary = {}  # skill -> HMM
var bkt_models: Dictionary = {}  # skill -> BKT
var dkt_model = null              # single DKT network

# Per-skill question statistics
var skill_stats: Dictionary = {}  # skill -> {correct: int, total: int}
var learning_stats: Dictionary = {}  # skill -> {correct: int, total: int}

func _init(algo_type: int = AlgorithmType.HMM) -> void:
	algorithm_type = algo_type
	_initialize_models()

func _initialize_models() -> void:
	hmm_models.clear()
	bkt_models.clear()
	skill_stats.clear()
	learning_stats.clear()
	
	for skill in SKILL_ORDER:
		hmm_models[skill] = load("res://Testing/Algorithms/hmm.gd").new()
		bkt_models[skill] = load("res://Testing/Algorithms/bkt.gd").new()
		skill_stats[skill] = {"correct": 0, "total": 0}
		learning_stats[skill] = {"correct": 0, "total": 0}
	
	dkt_model = load("res://Testing/Algorithms/dkt.gd").new()

## Set the algorithm type
func set_algorithm_type(algo_type: int) -> void:
	algorithm_type = algo_type

## Record an observation for a skill
func record_observation(skill: String, correct: bool) -> void:
	if not skill_stats.has(skill):
		skill_stats[skill] = {"correct": 0, "total": 0}
	
	skill_stats[skill]["total"] += 1
	if correct:
		skill_stats[skill]["correct"] += 1
	
	# Update all models
	if hmm_models.has(skill):
		hmm_models[skill].update(correct)
	if bkt_models.has(skill):
		bkt_models[skill].update(correct)
	if dkt_model:
		dkt_model.update(skill, correct)

## Mark the start of adaptive evidence for a skill without discarding its pretest model.
func begin_learning(skill: String) -> void:
	learning_stats[skill] = {"correct": 0, "total": 0}

## Record an adaptive observation separately from the pretest baseline.
func record_learning_observation(skill: String, correct: bool) -> void:
	record_observation(skill, correct)
	if not learning_stats.has(skill):
		learning_stats[skill] = {"correct": 0, "total": 0}
	learning_stats[skill]["total"] += 1
	if correct:
		learning_stats[skill]["correct"] += 1

## Get the knowledge probability for a skill using the active algorithm
func get_knowledge_probability(skill: String) -> float:
	match algorithm_type:
		AlgorithmType.HMM:
			if hmm_models.has(skill):
				return hmm_models[skill].get_knowledge_probability()
		AlgorithmType.BKT:
			if bkt_models.has(skill):
				return bkt_models[skill].get_knowledge_probability()
		AlgorithmType.DKT:
			if dkt_model:
				return dkt_model.get_knowledge_probability(skill)
	return 0.3

## Get the mastery percentage for a skill
func get_mastery_percentage(skill: String) -> float:
	return get_knowledge_probability(skill) * 100.0

## Check if a skill is learned
func is_learned(skill: String, threshold: float = 0.7) -> bool:
	# A correct response alone is not mastery. Require repeated adaptive evidence
	# while still using the pretest observations as the model's starting point.
	var evidence: Dictionary = learning_stats.get(skill, {"total": 0})
	return evidence.get("total", 0) >= 3 and get_knowledge_probability(skill) >= threshold

## Get the expected accuracy for a skill
func get_expected_accuracy(skill: String) -> float:
	match algorithm_type:
		AlgorithmType.HMM:
			if hmm_models.has(skill):
				return hmm_models[skill].get_expected_accuracy()
		AlgorithmType.BKT:
			if bkt_models.has(skill):
				return bkt_models[skill].get_expected_accuracy()
		AlgorithmType.DKT:
			if dkt_model:
				return dkt_model.get_expected_accuracy(skill)
	return 0.3

## Get the skill with the lowest knowledge (weakest skill)
func get_weakest_skill() -> String:
	var weakest := SKILL_ORDER[0]
	var lowest := 1.0
	for skill in SKILL_ORDER:
		var prob := get_knowledge_probability(skill)
		if prob < lowest:
			lowest = prob
			weakest = skill
	return weakest

## Get all skills sorted by knowledge (weakest first)
func get_skills_by_weakness() -> Array:
	var skills := SKILL_ORDER.duplicate()
	skills.sort_custom(func(a, b):
		return get_knowledge_probability(a) < get_knowledge_probability(b)
	)
	return skills

## Get the skill statistics
func get_skill_stats(skill: String) -> Dictionary:
	return skill_stats.get(skill, {"correct": 0, "total": 0})

## Get all skill statistics
func get_all_skill_stats() -> Dictionary:
	return skill_stats.duplicate()

## Get a full summary of all skills
func get_full_summary() -> Dictionary:
	var summary := {}
	for skill in SKILL_ORDER:
		var stats: Dictionary = skill_stats[skill]
		var total: int = stats["total"]
		var correct: int = stats["correct"]
		var percentage := 0.0
		if total > 0:
			percentage = float(correct) / float(total) * 100.0
		
		summary[skill] = {
			"name": load("res://Testing/Data/question_bank.gd").get_skill_name(skill),
			"correct": correct,
			"total": total,
			"accuracy_percentage": percentage,
			"knowledge_probability": get_knowledge_probability(skill),
			"mastery_percentage": get_mastery_percentage(skill),
			"is_learned": is_learned(skill)
		}
	return summary

## Get the algorithm-specific model for a skill
func get_model(skill: String):
	match algorithm_type:
		AlgorithmType.HMM:
			return hmm_models.get(skill)
		AlgorithmType.BKT:
			return bkt_models.get(skill)
		AlgorithmType.DKT:
			return dkt_model
	return null

## Serialize to dictionary for saving
func to_dict() -> Dictionary:
	var data := {
		"algorithm_type": algorithm_type,
		"skill_stats": skill_stats,
			"learning_stats": learning_stats,
		"hmm_models": {},
		"bkt_models": {},
		"dkt_model": null
	}
	
	for skill in SKILL_ORDER:
		if hmm_models.has(skill):
			data["hmm_models"][skill] = hmm_models[skill].to_dict()
		if bkt_models.has(skill):
			data["bkt_models"][skill] = bkt_models[skill].to_dict()
	
	if dkt_model:
		data["dkt_model"] = dkt_model.to_dict()
	
	return data

## Load from dictionary
func from_dict(data: Dictionary) -> void:
	algorithm_type = data.get("algorithm_type", AlgorithmType.HMM)
	skill_stats = data.get("skill_stats", {})
	learning_stats = data.get("learning_stats", {})
	
	# Ensure all skills have stats
	for skill in SKILL_ORDER:
		if not skill_stats.has(skill):
			skill_stats[skill] = {"correct": 0, "total": 0}
		if not learning_stats.has(skill):
			learning_stats[skill] = {"correct": 0, "total": 0}
	
	# Load HMM models
	var hmm_data: Dictionary = data.get("hmm_models", {})
	for skill in SKILL_ORDER:
		if hmm_data.has(skill):
			hmm_models[skill].from_dict(hmm_data[skill])
	
	# Load BKT models
	var bkt_data: Dictionary = data.get("bkt_models", {})
	for skill in SKILL_ORDER:
		if bkt_data.has(skill):
			bkt_models[skill].from_dict(bkt_data[skill])
	
	# Load DKT model
	var dkt_data = data.get("dkt_model")
	if dkt_data is Dictionary and dkt_model:
		dkt_model.from_dict(dkt_data)

## Reset all models
func reset() -> void:
	_initialize_models()
