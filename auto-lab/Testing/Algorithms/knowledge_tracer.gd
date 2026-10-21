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

## How much of the still-UNKNOWN probability mass a skipped whiteboard task
## removes: p_new = p - SKIP_PENALTY * (1 - p). Restated for the stats board:
## skipping when you already know the skill costs almost nothing, skipping a
## skill you have not learnt costs a lot.
const SKIP_PENALTY := 0.5

## Mastery policy. A skill is LEARNED when EITHER
##   * the ACTIVE model's probability clears MASTERY_THRESHOLD after at least
##     MIN_EVIDENCE adaptive answers, OR
##   * the learner just answered the last RECENT_WINDOW adaptive questions on
##     that skill correctly.
## The second path exists because the models converge SLOWER than a learner
## improves: someone who misses the pretest and then answers everything
## correctly can sit just under the threshold forever, which used to lock them
## out of the post test (most visible with KST, whose wrong answers pull the
## estimate down hard).
##
## The numbers are deliberately generous — the study measures how the three
## tracers PREDICT, not how hard the gate is, and a learner who answers two
## questions correctly on a topic has demonstrated it well enough to move on.
## The models' own parameters are untouched so the algorithm comparison stays
## valid; leniency lives entirely here.
const MASTERY_THRESHOLD := 0.5
const MIN_EVIDENCE := 2
const RECENT_WINDOW := 2

## How many of the six skills must be LEARNED before the post test unlocks. Lives
## here with the rest of the criteria so every record of a run can quote the exact
## gate that was in force, and the Testing Grounds only aliases it.
const MASTERY_GATE_SKILLS := 4

## Short, learner-facing description of every parameter the ACTIVE algorithm
## shows on the stats board. Kept next to the models so the board legend and the
## Algorithm Catalog can never drift apart.
const PARAM_LEGEND := {
	AlgorithmType.HMM: [
		"B = P(Beginner)   D = P(Developing)   M = P(Mastered)",
		"[STATE] = inferred mastery state (Beginner / Developing / Mastered)",
		"E = P(next answer correct)",
		"last = the last answer seen",
	],
	AlgorithmType.BKT: [
		"L = P(learnt)   L0 = P(learnt at start)",
		"T = P(learn per practice)",
		"G = P(guess right)   S = P(slip while knowing)",
		"n = answers seen",
	],
	AlgorithmType.KST: [
		"K = P(mastered)",
		"E = P(next answer correct)",
		"req = prerequisite skills",
	],
}

var algorithm_type: int = AlgorithmType.HMM

# Per-skill models
var hmm_models: Dictionary = {}  # skill -> HMM instance (self-contained)
var bkt_models: Dictionary = {}  # skill -> BKT instance (self-contained)
var kst_model = null              # single KST model (self-contained)

# Per-skill question statistics
var skill_stats: Dictionary = {}  # skill -> {correct: int, total: int}
var learning_stats: Dictionary = {}  # skill -> {correct: int, total: int}
## Per-skill count of SKIPPED whiteboard tasks (the board's Skip option). A skip
## is not an answer, so it is tracked separately from skill_stats.
var skip_stats: Dictionary = {}  # skill -> int

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

## Per-algorithm probability views for the ACTIVE model's stats board.
## Each returns ready-to-print lines; only the active algorithm is ever
## updated (see record_observation), so only it has live numbers.
func get_active_stats_lines() -> Array[String]:
	var out: Array[String] = []
	match algorithm_type:
		AlgorithmType.HMM:
			for skill in SKILL_ORDER:
				var m = hmm_models.get(skill)
				if m == null:
					continue
				var v: Dictionary = m.get_state_view()
				var hs: Dictionary = v.get("hidden_states", {})
				var st: Dictionary = v.get("state", {})
				# head carries the mastery % (the board draws its bar from it) and
				# the inferred STATE; tail carries the raw 3-state beliefs + accuracy.
				out.append("%s [%s] %.0f%% | B %.0f%% D %.0f%% M %.0f%% | E %.0f%% | last %s" % [
					skill, str(st.get("label", "-")), float(m.get_mastery_percentage()),
					float(hs.get("beginner", 0.0)) * 100.0,
					float(hs.get("developing", 0.0)) * 100.0,
					float(hs.get("mastered", 0.0)) * 100.0,
					float(v.get("expected_accuracy", 0.0)) * 100.0,
					str(v.get("visible_output", "-"))])
		AlgorithmType.BKT:
			for skill in SKILL_ORDER:
				var b = bkt_models.get(skill)
				if b == null:
					continue
				var s: Dictionary = b.get_summary()
				out.append("%s | L %.0f%% | L0 %.0f%% | T %.0f%% | G %.0f%% | S %.0f%% | n %d" % [
					skill, float(s.get("p_learned", 0.0)) * 100.0,
					float(s.get("p_L0", 0.0)) * 100.0, float(s.get("p_T", 0.0)) * 100.0,
					float(s.get("p_G", 0.0)) * 100.0, float(s.get("p_S", 0.0)) * 100.0,
					int(s.get("observation_count", 0))])
		AlgorithmType.KST:
			if kst_model:
				for skill in SKILL_ORDER:
					var p := float(kst_model.get_knowledge_probability(skill)) * 100.0
					var prereqs: Array = kst_model.PREREQUISITES.get(skill, [])
					out.append("%s | K %.0f%% | E %.0f%% | req %s" % [
						skill, p, float(kst_model.get_expected_accuracy(skill)) * 100.0,
						", ".join(prereqs)])
	return out

## Aggregate the self-scored prediction accuracy of each algorithm. Returns
## per-model {hits, total, accuracy} by asking each model for its own stats.
## NOTE: with ONE ACTIVE algorithm, only the active entry accumulates hits —
## the others stay at 0 until that algorithm is selected in another run.
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
	skip_stats.clear()
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
	
## Delegate to the ACTIVE model only. ONE ALGORITHM is active at a time
	## (chosen on AlgorithmSelect) so runs can be compared fairly for the
	## full project. Each model still records its own pre-answer prediction
	## + the outcome into its own prediction_log when it IS the active one.
	match algorithm_type:
		AlgorithmType.HMM:
			if hmm_models.has(skill):
				hmm_models[skill].update(correct, state_hint)
		AlgorithmType.BKT:
			if bkt_models.has(skill):
				bkt_models[skill].update(correct, state_hint)
		AlgorithmType.KST:
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
		learning_stats[skill] = {"correct": 0, "total": 0, "recent": []}
	learning_stats[skill]["total"] += 1
	if correct:
		learning_stats[skill]["correct"] += 1
	# Keep only the last RECENT_WINDOW outcomes: the recent-performance mastery
	# path asks exactly "were the last RECENT_WINDOW answers on this skill all
	# correct?".
	var recent: Array = learning_stats[skill].get("recent", [])
	recent.append(correct)
	while recent.size() > RECENT_WINDOW:
		recent.pop_front()
	learning_stats[skill]["recent"] = recent

## Record a SKIPPED whiteboard task on one skill. Used by the automata board's
## Skip option: the learner chose not to build the machine, which is a real
## "I don't know how" signal but NOT an answer, so it never touches the answer
## statistics or the models' prediction accuracy.
##
## The knowledge penalty is deliberately asymmetric: it removes only part of the
## still-UNKNOWN mass, so a learner who already knows the skill barely loses
## anything, while skipping a skill they have not learnt is heavily punished.
## Dispatched to whichever algorithm is ACTIVE, exactly like a normal answer.
## Returns {"skill", "before", "after", "drop"} (all probabilities in 0..1).
func apply_skip_penalty(skill: String, strength: float = SKIP_PENALTY) -> Dictionary:
	var before: float = get_knowledge_probability(skill)
	match algorithm_type:
		AlgorithmType.HMM:
			if hmm_models.has(skill):
				hmm_models[skill].penalize_skip(strength)
		AlgorithmType.BKT:
			if bkt_models.has(skill):
				bkt_models[skill].penalize_skip(strength)
		AlgorithmType.KST:
			if kst_model:
				kst_model.penalize_skip(skill, strength)
	skip_stats[skill] = int(skip_stats.get(skill, 0)) + 1
	var after: float = get_knowledge_probability(skill)
	return {"skill": skill, "before": before, "after": after, "drop": after - before, "skipped": true}

## How many whiteboard tasks were skipped for one skill.
func get_skip_count(skill: String) -> int:
	return int(skip_stats.get(skill, 0))

## Every skipped-task count, keyed by skill (skips happen at most rarely, so an
## empty dictionary simply means "no skips this session").
func get_skip_stats() -> Dictionary:
	return skip_stats.duplicate()

## The short parameter legend the stats board prints under the live numbers, so a
## reader can tell what K / L / G / S / E / n actually mean for the ACTIVE model.
func get_param_lines() -> Array[String]:
	var out: Array[String] = []
	for line in PARAM_LEGEND.get(algorithm_type, []):
		out.append(str(line))
	return out

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

## Check if a skill is learned. Two roads to "learned" (see MASTERY_THRESHOLD):
## the model's probability clearing the threshold with enough evidence, or a
## flawless run of the most recent answers — model convergence lags behind a
## learner who has clearly got it.
func is_learned(skill: String, threshold: float = MASTERY_THRESHOLD) -> bool:
	var evidence: Dictionary = learning_stats.get(skill, {"total": 0})
	if int(evidence.get("total", 0)) < MIN_EVIDENCE:
		return false
	if get_knowledge_probability(skill) >= threshold:
		return true
	var recent: Array = evidence.get("recent", [])
	return recent.size() >= RECENT_WINDOW and not recent.has(false)

## One line the learning screens print so the learner can always see HOW the
## "am I knowledgeable?" decision is made for the current skill: the active
## model's probability against the target, the evidence count, the recent
## streak, the verdict, and WHICH of the two roads produced that verdict.
func get_mastery_report(skill: String) -> String:
	var evidence: Dictionary = learning_stats.get(skill, {"total": 0})
	var recent: Array = evidence.get("recent", [])
	var streak := 0
	for i in range(recent.size() - 1, -1, -1):
		if bool(recent[i]):
			streak += 1
		else:
			break
	var total := int(evidence.get("total", 0))
	var learned := is_learned(skill)
	var reason := "needs %d answers first" % MIN_EVIDENCE if total < MIN_EVIDENCE else "below target and streak broken"
	if learned:
		reason = "knowledge target met" if get_knowledge_probability(skill) >= MASTERY_THRESHOLD \
			else "last %d answers all correct" % RECENT_WINDOW
	return "%s mastery check — knowledge %.0f%% of the %.0f%% target · answers seen %d · current streak %d correct · verdict: %s (%s)" % [
		get_algorithm_callout(),
		get_knowledge_probability(skill) * 100.0,
		MASTERY_THRESHOLD * 100.0,
		total,
		streak,
		"LEARNED" if learned else "not learned yet",
		reason]

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
		"skip_stats": skip_stats,
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
	skip_stats = data.get("skip_stats", {})
	
	# Ensure all skills have stats
	for skill in SKILL_ORDER:
		if not skill_stats.has(skill):
			skill_stats[skill] = {"correct": 0, "total": 0}
		if not learning_stats.has(skill):
			learning_stats[skill] = {"correct": 0, "total": 0}
	
	# Load HMM models
	var hmm_data: Dictionary = data.get("hmm_models", {})
	for skill in SKILL_ORDER:
		if hmm_data.has(skill) and hmm_models.has(skill):
			hmm_models[skill].from_dict(hmm_data[skill])
	
	# Load BKT models
	var bkt_data: Dictionary = data.get("bkt_models", {})
	for skill in SKILL_ORDER:
		if bkt_data.has(skill) and bkt_models.has(skill):
			bkt_models[skill].from_dict(bkt_data[skill])
	
	# Load KST model
	var kst_data = data.get("kst_model")
	if kst_data is Dictionary and kst_model:
		kst_model.from_dict(kst_data)

## Reset all models
func reset() -> void:
	_initialize_models()
