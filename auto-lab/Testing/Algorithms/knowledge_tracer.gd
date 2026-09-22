extends RefCounted
## Knowledge Tracer Manager (thin FACADE).
## Owns the per-skill HMM/BKT model maps + the single KST model, and simply
## ORCHESTRATES them. Each algorithm is a self-contained module (hmm.gd / bkt.gd
## / kst.gd) that records its OWN prediction history and scores itself — this
## file no longer computes predictions centrally.
##
## All three run in parallel on every observation so the driver can compare
## which model predicts best (used to pick the best one for the POC).

const SKILL_ORDER := ["simulation", "identification", "definition", "building", "set_builder", "list"]

# Algorithm type selection (the one that DRIVES the lesson's mastery decisions)
enum AlgorithmType { HMM, BKT, KST }

var algorithm_type: int = AlgorithmType.HMM

# Per-skill models
var hmm_models: Dictionary = {}  # skill -> HMM instance (self-contained)
var bkt_models: Dictionary = {}  # skill -> BKT instance (self-contained)
var kst_model = null              # single KST model (self-contained)

# Per-skill question statistics
var skill_stats: Dictionary = {}  # skill -> {correct: int, total: int}
var learning_stats: Dictionary = {}  # skill -> {correct: int, total: int}

## Phase hint ("pretest" / "learning" / "posttest") passed to every model on
## update; each model stores it in its own prediction_log.
var state_hint: String = "learning"

## Live count of observations fed to the models per phase. Shows how the
## algorithm is learning through the 3 stages: pretest (only input),
## learning (interactive analysis), posttest (proof).
var phase_counts: Dictionary = {"pretest": 0, "learning": 0, "posttest": 0}

func get_phase_observation_counts() -> Dictionary:
	return phase_counts.duplicate()

func get_algorithm_name() -> String:
	match algorithm_type:
		AlgorithmType.HMM:
			return "HMM (Hidden Markov Model)"
		AlgorithmType.BKT:
			return "BKT (Bayesian Knowledge Tracing)"
		AlgorithmType.KST:
			return "KST (Knowledge Space Tracing)"
	return "HMM"

func get_algorithm_callout() -> String:
	match algorithm_type:
		AlgorithmType.HMM:
			return "HMM"
		AlgorithmType.BKT:
			return "BKT"
		AlgorithmType.KST:
			return "KST"
	return "HMM"

func set_state_hint(value: String) -> void:
	state_hint = value

## Aggregate the self-scored prediction accuracy of each algorithm. Returns
## per-model {hits, total, accuracy} by asking each model for its own stats.
func get_algorithm_comparison() -> Dictionary:
	var hmm_stats := {"hits": 0, "total": 0, "accuracy": 0.0}
	var bkt_stats := {"hits": 0, "total": 0, "accuracy": 0.0}
	var kst_stats := {"hits": 0, "total": 0, "accuracy": 0.0}
	for skill in SKILL_ORDER:
		if hmm_models.has(skill):
			var hs: Dictionary = hmm_models[skill].get_prediction_stats()
			hmm_stats["hits"] += hs["hits"]
			hmm_stats["total"] += hs["total"]
		if bkt_models.has(skill):
			var bs: Dictionary = bkt_models[skill].get_prediction_stats()
			bkt_stats["hits"] += bs["hits"]
			bkt_stats["total"] += bs["total"]
	if kst_model:
		var ds: Dictionary = kst_model.get_prediction_stats()
		kst_stats["hits"] = ds["hits"]
		kst_stats["total"] = ds["total"]
	hmm_stats["accuracy"] = (float(hmm_stats["hits"]) / float(hmm_stats["total"]) * 100.0) if hmm_stats["total"] > 0 else 0.0
	bkt_stats["accuracy"] = (float(bkt_stats["hits"]) / float(bkt_stats["total"]) * 100.0) if bkt_stats["total"] > 0 else 0.0
	kst_stats["accuracy"] = (float(kst_stats["hits"]) / float(kst_stats["total"]) * 100.0) if kst_stats["total"] > 0 else 0.0
	return {
		"HMM": hmm_stats,
		"BKT": bkt_stats,
		"KST": kst_stats,
	}

func _init(algo_type: int = AlgorithmType.HMM) -> void:
	algorithm_type = algo_type
	_initialize_models()

func _initialize_models() -> void:
	hmm_models.clear()
	bkt_models.clear()
	skill_stats.clear()
	learning_stats.clear()
	phase_counts = {"pretest": 0, "learning": 0, "posttest": 0}
	
	for skill in SKILL_ORDER:
		hmm_models[skill] = load("res://Testing/Algorithms/hmm.gd").new()
		bkt_models[skill] = load("res://Testing/Algorithms/bkt.gd").new()
		skill_stats[skill] = {"correct": 0, "total": 0}
		learning_stats[skill] = {"correct": 0, "total": 0}
	
	kst_model = load("res://Testing/Algorithms/kst.gd").new()

## Set the algorithm type
func set_algorithm_type(algo_type: int) -> void:
	algorithm_type = algo_type

## Record an observation for a skill
func record_observation(skill: String, correct: bool) -> void:
	if not skill_stats.has(skill):
		skill_stats[skill] = {"correct": 0, "total": 0}
	
	skill_stats[skill]["total"] += 1

	# Track which phase this observation belongs to: pretest-only input,
	# interactive learning, or post-test proof.
	if phase_counts.has(state_hint):
		phase_counts[state_hint] += 1
	else:
		phase_counts[state_hint] = 1
	if correct:
		skill_stats[skill]["correct"] += 1
	
	# Delegate to each SELF-CONTAINED model. Each model records its own
	# pre-answer prediction + the outcome into its own prediction_log, then
	# updates its internal state. (All three run in parallel for the POC; the
	# active algorithm type only drives mastery decisions, not the updates.)
	if hmm_models.has(skill):
		hmm_models[skill].update(correct, state_hint)
	if bkt_models.has(skill):
		bkt_models[skill].update(correct, state_hint)
	if kst_model:
		kst_model.update(skill, correct, state_hint)

## Mark the start of adaptive evidence for a skill without discarding its pretest model.
func begin_learning(skill: String) -> void:
	learning_stats[skill] = {"correct": 0, "total": 0}

## Record an adaptive observation separately from the pretest baseline.
func record_learning_observation(skill: String, correct: bool) -> void:
	state_hint = "learning"
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
		AlgorithmType.KST:
			if kst_model:
				return kst_model.get_knowledge_probability(skill)
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
		AlgorithmType.KST:
			if kst_model:
				return kst_model.get_expected_accuracy(skill)
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

## Seed every model from the PRETEST results. The pretest IS the starting
## estimate: P(L0) for BKT, the initial distribution Pi for HMM, and the
## starting knowledge state for KST. Called once when the pretest ends.
func apply_pretest_priors(pretest_answers: Array) -> void:
	var priors := {}
	for skill in SKILL_ORDER:
		var correct := 0
		var total := 0
		for answer in pretest_answers:
			if answer.get("skill", "") == skill:
				total += 1
				if answer.get("correct", false):
					correct += 1
		# Laplace-smoothed starting accuracy: (correct + 1) / (total + 2)
		priors[skill] = clampf(float(correct + 1) / float(total + 2), 0.05, 0.95)
	for skill in SKILL_ORDER:
		if hmm_models.has(skill):
			hmm_models[skill].p_knows = priors[skill]
		if bkt_models.has(skill):
			bkt_models[skill].p_L0 = priors[skill]
			bkt_models[skill].p_learned = priors[skill]
	if kst_model:
		kst_model.seed_from_pretest(priors)

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
		AlgorithmType.KST:
			return kst_model
	return null

## Stable UI/reporting contract for algorithm visualizations.
## HMM exposes hidden beliefs and its latest right/wrong observation; BKT exposes
## its four probabilities; KST exposes the current prerequisite knowledge space.
func get_algorithm_snapshot(skill: String) -> Dictionary:
	var snapshot := {"algorithm": get_algorithm_callout(), "skill": skill}
	if hmm_models.has(skill):
		snapshot["HMM"] = hmm_models[skill].get_state_view()
	if bkt_models.has(skill):
		snapshot["BKT"] = bkt_models[skill].get_summary()
	if kst_model:
		snapshot["KST"] = {
			"possible_areas": kst_model.get_possible_areas(),
			"knowledge_state": kst_model.get_all_knowledge(),
		}
	return snapshot

## Serialize to dictionary for saving
func to_dict() -> Dictionary:
	var data := {
		"algorithm_type": algorithm_type,
		"skill_stats": skill_stats,
		"phase_counts": phase_counts,
			"learning_stats": learning_stats,
		"hmm_models": {},
		"bkt_models": {},
		"kst_model": null
	}
	
	for skill in SKILL_ORDER:
		if hmm_models.has(skill):
			data["hmm_models"][skill] = hmm_models[skill].to_dict()
		if bkt_models.has(skill):
			data["bkt_models"][skill] = bkt_models[skill].to_dict()
	
	if kst_model:
		data["kst_model"] = kst_model.to_dict()
	
	return data

## Load from dictionary
func from_dict(data: Dictionary) -> void:
	algorithm_type = data.get("algorithm_type", AlgorithmType.HMM)
	skill_stats = data.get("skill_stats", {})
	phase_counts = data.get("phase_counts", {"pretest": 0, "learning": 0, "posttest": 0})
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
	
	# Load KST model
	var kst_data = data.get("kst_model")
	if kst_data is Dictionary and kst_model:
		kst_model.from_dict(kst_data)

## Reset all models
func reset() -> void:
	_initialize_models()
