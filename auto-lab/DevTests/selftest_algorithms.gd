extends SceneTree
## Headless self-test for the knowledge-tracing ALGORITHMS and the tracer facade.
## Run:
##   Godot_v4.7-stable_win64_console.exe --path <project> --headless \
##     --script res://DevTests/selftest_algorithms.gd
##
## It verifies the behaviour the rest of the game relies on, for all three models:
##   1. BOUNDS      - every probability stays inside (0, 1) no matter the answers.
##   2. LEARNING    - repeated correct answers raise knowledge, wrong ones lower it,
##                    and the movement is monotonic (no flip-flopping).
##   3. PREDICTION  - each model scores its OWN pre-answer predictions and never
##                    reports more hits than observations.
##   4. SERIALIZE   - to_dict / from_dict round-trips the model state.
##   5. STRUCTURE   - KST only: the prerequisite closure lifts prerequisites, the
##                    readiness bonus needs mastered prerequisites, and the skip
##                    penalty is NOT undone by the closure.
##   6. ACTIVE-MODEL DISCIPLINE - the tracer feeds ONLY the selected algorithm
##                    (so two runs can be compared fairly on the stats board).
##   7. PRETEST PRIORS - the pretest seeds HMM, BKT and KST together.
##   8. MASTERY GATE  - is_learned: probability over the threshold with MIN_EVIDENCE
##      answers seen, OR a flawless run of the last RECENT_WINDOW adaptive answers.
##   9. SKIP PENALTY  - a skipped board task costs a LOT at low mastery and almost
##                    nothing at high mastery, never raises knowledge, and is
##                    counted per skill.
##  10. STATS BOARD   - every active algorithm has a short parameter legend.
## Prints REPORT lines and exits with code 0 (ok) or 1 (failures).

const KnowledgeTracer = preload("res://Testing/Algorithms/knowledge_tracer.gd")
const Bkt = preload("res://Testing/Algorithms/bkt.gd")
const Hmm = preload("res://Testing/Algorithms/hmm.gd")
const Kst = preload("res://Testing/Algorithms/kst.gd")
const Catalog = preload("res://Testing/Algorithms/algorithm_catalog.gd")

const EPS := 0.000001

var _failures: Array[String] = []


func _initialize() -> void:
	_check_bkt()
	_check_hmm()
	_check_kst()
	_check_tracer_dispatch()
	_check_pretest_priors()
	_check_mastery_gate()
	_check_skip_penalty()
	_check_stats_board_legend()
	_check_serialization()
	_report()


func _note(ok: bool, label: String, detail: String) -> void:
	if ok:
		print("REPORT  PASS  %-44s %s" % [label, detail])
	else:
		print("REPORT  FAIL  %-44s %s" % [label, detail])
		_failures.append(label)


func _near(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps



# ===== 1-4. BKT ============================================================

func _check_bkt() -> void:
	var model = Bkt.new(0.3, 0.1, 0.25, 0.1)
	var rising := true
	var previous: float = model.get_knowledge_probability()
	for i in range(5):
		model.update(true, "learning")
		var now: float = model.get_knowledge_probability()
		if now <= previous:
			rising = false
		previous = now
	_note(rising, "bkt_correct_answers_raise_knowledge",
		"p=%.3f after 5 corrects" % previous)
	_note(previous > 0.7, "bkt_reaches_mastery_on_correct_evidence",
		"p=%.3f threshold=0.70" % previous)

	model = Bkt.new(0.6, 0.1, 0.25, 0.1)
	var falling := true
	previous = model.get_knowledge_probability()
	for i in range(5):
		model.update(false, "learning")
		var now2: float = model.get_knowledge_probability()
		if now2 >= previous:
			falling = false
		previous = now2
	_note(falling and previous < 0.2, "bkt_wrong_answers_lower_knowledge",
		"p=%.3f after 5 wrongs" % previous)

	# BOUNDS: 200 alternating answers must never leave (0, 1).
	var wild = Bkt.new(0.5, 0.9, 0.9, 0.9)
	var bounded := true
	for i in range(200):
		wild.update(i % 2 == 0, "learning")
		if not _in_unit_interval(wild.get_knowledge_probability()):
			bounded = false
	_note(bounded, "bkt_probability_stays_in_0_1",
		"p=%.6f" % wild.get_knowledge_probability())

	var stats: Dictionary = model.get_prediction_stats()
	_note(int(stats["total"]) == 5, "bkt_scores_every_prediction",
		"total=%d hits=%d" % [int(stats["total"]), int(stats["hits"])])
	_note(int(stats["hits"]) <= int(stats["total"]) and float(stats["accuracy"]) <= 100.0,
		"bkt_prediction_stats_are_sane", "accuracy=%.1f%%" % float(stats["accuracy"]))

	model.reset()
	_note(_near(model.get_knowledge_probability(), 0.6), "bkt_reset_restores_initial_p",
		"p=%.3f L0=%.3f" % [model.get_knowledge_probability(), model.p_L0])


# ===== 1-4. HMM ============================================================

func _check_hmm() -> void:
	var model = Hmm.new(0.3)
	var rising := true
	var previous: float = model.get_knowledge_probability()
	for i in range(5):
		model.update(true, "learning")
		var now: float = model.get_knowledge_probability()
		if now <= previous:
			rising = false
		previous = now
	_note(rising and previous > 0.7, "hmm_correct_answers_raise_knowledge",
		"p=%.3f after 5 corrects" % previous)

	model = Hmm.new(0.7)
	var falling := true
	previous = model.get_knowledge_probability()
	for i in range(5):
		model.update(false, "learning")
		var now2: float = model.get_knowledge_probability()
		if now2 >= previous:
			falling = false
		previous = now2
	_note(falling and previous < 0.3, "hmm_wrong_answers_lower_knowledge",
		"p=%.3f after 5 wrongs" % previous)

	var wild = Hmm.new(0.5, 0.9, 0.9, 0.9, 0.9)
	var bounded := true
	for i in range(200):
		wild.update(i % 2 == 0, "learning")
		if not _in_unit_interval(wild.get_knowledge_probability()):
			bounded = false
	_note(bounded, "hmm_probability_stays_in_0_1",
		"p=%.6f" % wild.get_knowledge_probability())

	# The HMM state view is what the stats board prints: the two hidden beliefs
	# must stay a probability pair and the visible output must follow the answer.
	var view: Dictionary = model.get_state_view()
	var hidden: Dictionary = view.get("hidden_states", {})
	_note(_near(float(hidden.get("knows", 0.0)) + float(hidden.get("does_not_know", 0.0)), 1.0),
		"hmm_hidden_states_sum_to_one",
		"knows=%.3f not=%.3f" % [float(hidden.get("knows", 0.0)), float(hidden.get("does_not_know", 0.0))])
	model.update(false, "learning")
	_note(str(model.get_state_view().get("visible_output", "")) == "wrong",
		"hmm_state_view_tracks_last_answer", str(model.get_state_view().get("visible_output", "")))

	# Regression: reset() used to hard-code 0.3, throwing away a pretest-seeded start.
	var seeded = Hmm.new(0.62)
	seeded.update(true, "learning")
	seeded.reset()
	_note(_near(seeded.get_knowledge_probability(), 0.62), "hmm_reset_restores_initial_p",
		"p=%.3f expected=0.62" % seeded.get_knowledge_probability())
	_note(str(seeded.get_state_view().get("visible_output", "")) == "",
		"hmm_reset_clears_last_answer",
		"last='%s'" % str(seeded.get_state_view().get("visible_output", "")))


# ===== 1-5. KST ============================================================

func _check_kst() -> void:
	var space = Kst.new(0.3)
	var rising := true
	var previous: float = space.get_knowledge_probability("building")
	for i in range(5):
		space.update("building", true, "learning")
		var now: float = space.get_knowledge_probability("building")
		if now <= previous:
			rising = false
		previous = now
	_note(rising and previous > 0.7, "kst_correct_answers_raise_the_skill",
		"building=%.3f after 5 corrects" % previous)

	# Downward closure: mastering a higher skill lifts the skills it rests on.
	var definition_after: float = space.get_knowledge_probability("definition")
	_note(definition_after > 0.3, "kst_closure_lifts_prerequisites",
		"definition=%.3f (started 0.30) from building=%.3f" % [definition_after, previous])

	# The readiness bonus only fires once EVERY prerequisite is mastered.
	var areas: Dictionary = space.get_possible_areas()
	_note(bool(areas["definition"]["ready"]), "kst_definition_is_always_ready", "ready=true")
	var fresh = Kst.new(0.1)
	_note(not bool(fresh.get_possible_areas()["building"]["ready"]),
		"kst_building_not_ready_below_prerequisites", "ready=false")
	fresh.knowledge_state["definition"] = 0.9
	fresh.knowledge_state["simulation"] = 0.9
	_note(bool(fresh.get_possible_areas()["building"]["ready"]),
		"kst_building_ready_once_prerequisites_met", "ready=true")

	var wild = Kst.new(0.5)
	var bounded := true
	for i in range(200):
		for skill in Kst.PREREQUISITES.keys():
			wild.update(str(skill), i % 2 == 0, "learning")
		for skill in Kst.PREREQUISITES.keys():
			if not _in_unit_interval(wild.get_knowledge_probability(str(skill))):
				bounded = false
	_note(bounded, "kst_probabilities_stay_in_0_1", "skills=%d" % Kst.PREREQUISITES.size())

	_note(_near(space.get_expected_accuracy("building"), space.get_knowledge_probability("building")),
		"kst_expected_accuracy_follows_mastery", "E=%.3f" % space.get_expected_accuracy("building"))

	# seed_from_pretest must clamp wild priors into a usable range.
	var seeded = Kst.new(0.3)
	seeded.seed_from_pretest({"building": 4.0, "list": -3.0})
	var ok := true
	for skill in Kst.PREREQUISITES.keys():
		var p: float = seeded.get_knowledge_probability(str(skill))
		if p < 0.05 - EPS or p > 0.95 + EPS:
			ok = false
	_note(ok, "kst_pretest_seed_is_clamped",
		"building=%.2f list=%.2f" % [seeded.get_knowledge_probability("building"),
			seeded.get_knowledge_probability("list")])

	# A skip must survive the closure: set_builder (a dependant) is high, so the
	# closure would immediately lift building back if it were re-applied.
	var skip_space = Kst.new(0.2)
	for i in range(8):
		skip_space.update("set_builder", true, "learning")
	var building_before: float = skip_space.get_knowledge_probability("building")
	var removed: float = skip_space.penalize_skip("building", 0.5)
	var building_after: float = skip_space.get_knowledge_probability("building")
	_note(removed > 0.0 and building_after < building_before,
		"kst_skip_penalty_is_not_undone_by_closure",
		"before=%.3f after=%.3f removed=%.3f" % [building_before, building_after, removed])


# ===== 6. Which model does the tracer actually feed? =======================

func _check_tracer_dispatch() -> void:
	var tracer = KnowledgeTracer.new(KnowledgeTracer.AlgorithmType.HMM)
	var models_ready: bool = tracer.hmm_models.size() == 6 and tracer.bkt_models.size() == 6 \
		and tracer.kst_model != null
	_note(models_ready, "tracer_builds_all_six_skill_models",
		"hmm=%d bkt=%d kst=%s" % [tracer.hmm_models.size(), tracer.bkt_models.size(), str(tracer.kst_model != null)])

	var hmm_before: float = tracer.hmm_models["building"].get_knowledge_probability()
	var bkt_before: float = tracer.bkt_models["building"].get_knowledge_probability()
	tracer.record_learning_observation("building", true)
	var hmm_moved: bool = not _near(tracer.hmm_models["building"].get_knowledge_probability(), hmm_before)
	var bkt_moved: bool = not _near(tracer.bkt_models["building"].get_knowledge_probability(), bkt_before)
	_note(hmm_moved and not bkt_moved, "tracer_updates_only_the_active_model",
		"hmm_moved=%s bkt_moved=%s" % [str(hmm_moved), str(bkt_moved)])

	# Switching the active algorithm switches which models receive evidence.
	var bkt_before2: float = tracer.bkt_models["list"].get_knowledge_probability()
	tracer.set_algorithm_type(KnowledgeTracer.AlgorithmType.BKT)
	tracer.record_learning_observation("list", true)
	_note(not _near(tracer.bkt_models["list"].get_knowledge_probability(), bkt_before2),
		"tracer_switches_the_active_model",
		"BKT list p=%.3f" % tracer.bkt_models["list"].get_knowledge_probability())

	var comparison: Dictionary = tracer.get_algorithm_comparison()
	_note(comparison.has("HMM") and comparison.has("BKT") and comparison.has("KST"),
		"tracer_reports_every_algorithm_comparison", "keys=%s" % str(comparison.keys()))


# ===== 7. Pretest priors ===================================================

func _check_pretest_priors() -> void:
	var tracer = KnowledgeTracer.new(KnowledgeTracer.AlgorithmType.HMM)
	var answers: Array = []
	for skill in tracer.SKILL_ORDER:
		answers.append({"skill": skill, "correct": true})
		answers.append({"skill": skill, "correct": true})
		answers.append({"skill": skill, "correct": false})
	tracer.apply_pretest_priors(answers)
	# (2 correct + 1) / (3 + 2) = 0.6 for every skill.
	var hmm_ok := _near(tracer.hmm_models["list"].p_knows, 0.6, 0.001)
	var bkt_ok := _near(tracer.bkt_models["list"].p_learned, 0.6, 0.001)
	var kst_ok := _near(tracer.kst_model.get_knowledge_probability("list"), 0.6, 0.03)
	_note(hmm_ok and bkt_ok and kst_ok, "pretest_seeds_all_three_models",
		"hmm=%.3f bkt=%.3f kst=%.3f" % [tracer.hmm_models["list"].p_knows,
			tracer.bkt_models["list"].p_learned, tracer.kst_model.get_knowledge_probability("list")])
	# An empty pretest must still produce a usable, non-zero start.
	var empty = KnowledgeTracer.new(KnowledgeTracer.AlgorithmType.HMM)
	empty.apply_pretest_priors([])
	_note(empty.get_knowledge_probability("list") > 0.0, "pretest_priors_default_safely",
		"p=%.3f" % empty.get_knowledge_probability("list"))


# ===== 8. Mastery gate =====================================================

func _check_mastery_gate() -> void:
	var tracer = KnowledgeTracer.new(KnowledgeTracer.AlgorithmType.BKT)
	tracer.bkt_models["building"].p_learned = 0.95
	tracer.learning_stats["building"] = {"correct": 0, "total": 1, "recent": [true]}
	_note(not tracer.is_learned("building"), "mastery_needs_two_observations",
		"total=1 p=0.95 -> learned=false")
	tracer.learning_stats["building"] = {"correct": 2, "total": 2, "recent": [true, true]}
	_note(tracer.is_learned("building"), "mastery_unlocks_with_enough_evidence",
		"total=2 p=0.95 -> learned=true")
	# Below the probability target AND no clean streak -> still not learned.
	tracer.bkt_models["building"].p_learned = 0.4
	tracer.learning_stats["building"] = {"correct": 1, "total": 2, "recent": [false, true]}
	_note(not tracer.is_learned("building"), "mastery_needs_the_probability_or_a_streak",
		"total=2 p=0.40 recent=[false,true] -> learned=false")
	# Recent-performance road: the model lags below the threshold but the learner
	# just answered the last RECENT_WINDOW adaptive questions correctly.
	tracer.learning_stats["building"] = {"correct": 3, "total": 4, "recent": [true, true]}
	_note(tracer.is_learned("building"), "mastery_via_recent_streak",
		"total=4 p=0.40 recent all correct -> learned=true")
	tracer.learning_stats["building"] = {"correct": 3, "total": 5, "recent": [true, false]}
	_note(not tracer.is_learned("building"), "streak_broken_by_a_wrong_answer",
		"total=5 p=0.40 recent ends wrong -> learned=false")
	# The learner-facing report names the target, the deciding road and the verdict.
	var report: String = tracer.get_mastery_report("building")
	_note(report.contains("verdict") and report.contains("50%"), "mastery_report_is_human_readable",
		report)
	tracer.learning_stats["building"] = {"correct": 4, "total": 4, "recent": [true, true]}
	var learned_report: String = tracer.get_mastery_report("building")
	_note(learned_report.contains("LEARNED"), "mastery_report_names_the_pass",
		learned_report)


# ===== 9. Skip penalty =====================================================

## Skips are the escape hatch from a board task the learner cannot build, so the
## penalty MUST be asymmetric: heavy while the skill is weak, negligible once it is
## strong, and never a reward.
func _check_skip_penalty() -> void:
	for algo_type in [KnowledgeTracer.AlgorithmType.HMM, KnowledgeTracer.AlgorithmType.BKT,
			KnowledgeTracer.AlgorithmType.KST]:
		var tracer = KnowledgeTracer.new(algo_type)
		_set_knowledge(tracer, "building", 0.30)
		var low: Dictionary = tracer.apply_skip_penalty("building")
		_set_knowledge(tracer, "building", 0.90)
		var high: Dictionary = tracer.apply_skip_penalty("building")

		var low_drop := float(low["before"]) - float(low["after"])
		var high_drop := float(high["before"]) - float(high["after"])
		var algo := tracer.get_algorithm_callout().to_lower()
		_note(low_drop > high_drop * 2.0, "%s_skip_hurts_the_weak_much_more" % algo,
			"drop@30pct=%.3f vs drop@90pct=%.3f" % [low_drop, high_drop])
		_note(high_drop < 0.08, "%s_skip_barely_punishes_the_strong" % algo,
			"drop@90pct=%.3f after=%.3f" % [high_drop, float(high["after"])])
		_note(float(low["after"]) < 0.06, "%s_skip_heavily_reduces_low_knowledge" % algo,
			"after=%.3f" % float(low["after"]))
		_note(float(high["after"]) < float(high["before"]), "%s_skip_never_rewards" % algo,
			"before=%.3f after=%.3f" % [float(high["before"]), float(high["after"])])
		_note(tracer.get_skip_count("building") == 2, "%s_skip_count_is_per_skill" % algo,
			"count=%d" % tracer.get_skip_count("building"))
		# A skip must NOT pollute the answer statistics or the mastery evidence.
		var answers := int(tracer.get_skill_stats("building")["total"])
		var adaptive := int(tracer.learning_stats.get("building", {"total": 0})["total"])
		_note(answers == 0 and adaptive == 0, "%s_skip_is_not_counted_as_an_answer" % algo,
			"answers=%d adaptive=%d" % [answers, adaptive])

	# A skip naming an unknown skill must not crash, and must not touch knowledge.
	var odd = KnowledgeTracer.new(KnowledgeTracer.AlgorithmType.HMM)
	var unknown_penalty: Dictionary = odd.apply_skip_penalty("not_a_skill")
	_note(not unknown_penalty.is_empty() and odd.get_skip_count("not_a_skill") == 1,
		"skip_penalty_tolerates_unknown_skill", "count=%d" % odd.get_skip_count("not_a_skill"))


## Force a model's knowledge to an exact value so the two skip cases are comparable.
func _set_knowledge(tracer, skill: String, value: float) -> void:
	match tracer.algorithm_type:
		KnowledgeTracer.AlgorithmType.HMM:
			tracer.hmm_models[skill].p_knows = value
		KnowledgeTracer.AlgorithmType.BKT:
			tracer.bkt_models[skill].p_learned = value
		KnowledgeTracer.AlgorithmType.KST:
			tracer.kst_model.knowledge_state[skill] = value



# ===== 10. Stats-board parameter legend ====================================

func _check_stats_board_legend() -> void:
	var missing: Array[String] = []
	for algo_type in [KnowledgeTracer.AlgorithmType.HMM, KnowledgeTracer.AlgorithmType.BKT,
			KnowledgeTracer.AlgorithmType.KST]:
		var tracer = KnowledgeTracer.new(algo_type)
		var lines: Array = tracer.get_param_lines()
		if lines.is_empty():
			missing.append(tracer.get_algorithm_callout())
			continue
		for line in lines:
			if not str(line).contains("="):
				missing.append("%s:%s" % [tracer.get_algorithm_callout(), str(line)])
	_note(missing.is_empty(), "stats_board_has_a_param_legend_per_algorithm",
		"problems=%s" % str(missing))
	# The select screen prints the same short "SYMBOL = meaning" parameter block.
	var catalog_lines: Array = Catalog.catalog_param_lines(Catalog.TYPE_BKT)
	_note(not catalog_lines.is_empty() and str(catalog_lines[0]).contains("="),
		"algorithm_select_param_summary_is_short",
		"lines=%d first=%s" % [catalog_lines.size(), str(catalog_lines[0])])
	_note(Catalog.catalog_param_lines(Catalog.TYPE_HMM).size() >= 3
		and Catalog.catalog_param_lines(Catalog.TYPE_KST).size() >= 3,
		"every_algorithm_documents_its_parameters",
		"hmm=%d kst=%d" % [Catalog.catalog_param_lines(Catalog.TYPE_HMM).size(),
			Catalog.catalog_param_lines(Catalog.TYPE_KST).size()])


# ===== 4. Serialization ===================================================

func _check_serialization() -> void:
	for algo_type in [KnowledgeTracer.AlgorithmType.HMM, KnowledgeTracer.AlgorithmType.BKT,
			KnowledgeTracer.AlgorithmType.KST]:
		var source = KnowledgeTracer.new(algo_type)
		source.record_learning_observation("definition", true)
		source.record_learning_observation("definition", false)
		source.apply_skip_penalty("list")
		var rebuilt = KnowledgeTracer.new(algo_type)
		rebuilt.from_dict(source.to_dict())
		var same := true
		for skill in source.SKILL_ORDER:
			if not _near(source.get_knowledge_probability(str(skill)),
					rebuilt.get_knowledge_probability(str(skill)), 0.001):
				same = false
		var skips_kept: bool = rebuilt.get_skip_count("list") == source.get_skip_count("list")
		var algo := source.get_algorithm_callout().to_lower()
		_note(same, "%s_state_round_trips_through_save_data" % algo,
			"skills=%d" % source.SKILL_ORDER.size())
		_note(skips_kept, "%s_skip_counts_round_trip" % algo,
			"skips=%d" % rebuilt.get_skip_count("list"))
		# A save written by an older build (no skip_stats / p_knows0) must still load.
		var legacy: Dictionary = source.to_dict()
		legacy.erase("skip_stats")
		var legacy_models: Dictionary = legacy.get("hmm_models", {})
		for skill in legacy_models:
			(legacy_models[skill] as Dictionary).erase("p_knows0")
		var upgraded = KnowledgeTracer.new(algo_type)
		upgraded.from_dict(legacy)
		_note(upgraded.get_skip_count("list") == 0
			and _in_unit_interval(upgraded.get_knowledge_probability("definition")),
			"%s_old_save_files_still_load" % algo,
			"p=%.3f" % upgraded.get_knowledge_probability("definition"))


func _report() -> void:
	print("REPORT ---- failures=%d ----" % _failures.size())
	for failure in _failures:
		print("REPORT  !! %s" % failure)
	print("REPORT DONE")
	quit(1 if not _failures.is_empty() else 0)


func _in_unit_interval(value: float) -> bool:
	return value > 0.0 and value < 1.0
