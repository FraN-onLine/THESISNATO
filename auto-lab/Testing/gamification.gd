extends RefCounted
## Gamification tracker for the interactive learning phase.
## Gameful elements the learner earns while building automata and answering
## challenges: XP, levelling titles, correct-answer streaks, badges, and
## per-skill mastery stars. Lives on the session so it survives scene changes.

# Level thresholds and celebrated titles.
const LEVELS := [
	{"xp": 0,    "title": "Symbol Novice"},
	{"xp": 150,  "title": "State Explorer"},
	{"xp": 400,  "title": "Transition Tracer"},
	{"xp": 800,  "title": "Movement Analyst"},
	{"xp": 1400, "title": "Regex Reader"},
	{"xp": 2200, "title": "DFA Architect"},
	{"xp": 3200, "title": "Automata Master"},
]

var total_xp: int = 0
var streak: int = 0
var best_streak: int = 0
var correct_answers: int = 0
var wrong_answers: int = 0
var builds_verified: int = 0
var free_build_sessions: int = 0
var challenges_finished: int = 0
var badges: Array[String] = []
var mastery_stars: Dictionary = {}   # skill -> 0..3 stars
var last_gain: int = 0               # most recent XP gain (shown on HUD)
var last_event := ""

func get_level() -> int:
	var level := 1
	for i in range(LEVELS.size()):
		if total_xp >= LEVELS[i]["xp"]:
			level = i + 1
	return level

func get_level_title() -> String:
	return LEVELS[clampi(get_level() - 1, 0, LEVELS.size() - 1)]["title"]

## XP needed to reach the NEXT level; -1 when maxed.
func get_xp_to_next_level() -> int:
	var idx := clampi(get_level(), 0, LEVELS.size() - 1)
	if idx >= LEVELS.size() - 1:
		return -1
	return LEVELS[idx]["xp"]

func get_level_progress() -> float:
	var idx := clampi(get_level() - 1, 0, LEVELS.size() - 2)
	var base := LEVELS[idx]["xp"]
	var next := LEVELS[idx + 1]["xp"]
	return clampf(float(total_xp - base) / float(maxi(next - base, 1)), 0.0, 1.0)

## A correct answer: 10 XP x streak multiplier; every 3-streak grants a bonus.
## Returns a summary dictionary the UI can render immediately.
func award_correct(mastery_pct: float = 0.0) -> Dictionary:
	var prev_level: int = get_level()
	streak += 1
	best_streak = maxi(best_streak, streak)
	correct_answers += 1
	var multiplier := 1 + (streak - 1) * 0.1
	var gain := int(round(10.0 * multiplier))
	var bonus := 0
	if streak > 0 and streak % 3 == 0:
		bonus = 15
		last_event = "STREAK x%d BONUS!" % streak
	gain += bonus
	total_xp += gain
	last_gain = gain
	_check_streak_badges()
	var new_level: int = get_level()
	return {
		"xp_gain": gain,
		"streak": streak,
		"multiplier": multiplier,
		"levelled_up": new_level != prev_level,
		"level": new_level,
		"level_title": get_level_title(),
		"badges_unlocked": _badges_unlocked_since(prev_level, new_level),
	}

func award_wrong() -> Dictionary:
	streak = 0
	wrong_answers += 1
	total_xp += 2
	last_gain = 2
	return {"xp_gain": 2, "streak": 0, "levelled_up": false}

func award_build() -> Dictionary:
	builds_verified += 1
	total_xp += 25
	last_gain = 25
	_check_build_badges()
	return {"xp_gain": 25, "badges_unlocked": _new_badges_since()}

func award_free_build() -> Dictionary:
	free_build_sessions += 1
	total_xp += 15
	last_gain = 15
	_check_explorer_badges()
	return {"xp_gain": 15, "badges_unlocked": _new_badges_since()}
func award_challenge_finished(percentage: float) -> Dictionary:
	challenges_finished += 1
	var gain := int(round(percentage * 0.5))
	total_xp += gain
	last_gain = gain
	return {"xp_gain": gain, "badges_unlocked": _new_badges_since()}

func award_posttest(percentage: float) -> Dictionary:
	var gain := int(round(percentage * 0.75))
	total_xp += gain
	last_gain = gain
	if percentage >= 80.0:
		_unlock_badge("Post-Test Champion")
	_check_mastery_badges()
	return {"xp_gain": gain, "badges_unlocked": _new_badges_since()}

## Associate the model's current P(knows) with a star rating for a skill.
func set_mastery(skill: String, pct: float) -> void:
	var stars := 0
	if pct >= 90.0:
		stars = 3
	elif pct >= 75.0:
		stars = 2
	elif pct >= 60.0:
		stars = 1
	mastery_stars[skill] = stars
	_check_mastery_badges()

func get_stars(skill: String) -> int:
	return int(mastery_stars.get(skill, 0))

static func stars_to_string(stars: int) -> String:
	return "★".repeat(clampi(stars, 0, 3)) + "☆".repeat(clampi(3 - stars, 0, 3))

func has_badge(name: String) -> bool:
	return badges.has(name)

func _unlock_badge(name: String) -> void:
	if not has_badge(name):
		badges.append(name)

## These helpers simply return the current badge delta; badge changes are
## detected by comparing the list before/after an award in the UI layer.
func _new_badges_since() -> Array:
	return []

func _badges_unlocked_since(_a: int, _b: int) -> Array:
	return []

func _check_streak_badges() -> void:
	if correct_answers == 1:
		_unlock_badge("First Correct Answer")
	if streak >= 3:
		_unlock_badge("On Fire x3")
	if streak >= 5:
		_unlock_badge("Perfect Streak x5")
	if best_streak >= 8:
		_unlock_badge("Speed of Thought (x8)")

func _check_build_badges() -> void:
	if builds_verified >= 3:
		_unlock_badge("Build Master (3 builds)")

func _check_explorer_badges() -> void:
	if free_build_sessions >= 3:
		_unlock_badge("Sandbox Explorer (3 free-builds)")

func _check_mastery_badges() -> void:
	var stars_total := 0
	for skill in mastery_stars:
		stars_total += int(mastery_stars[skill])
	if stars_total >= 14:
		_unlock_badge("DFA Star Collector")
	var mastered_count := 0
	for skill in mastery_stars:
		if int(mastery_stars[skill]) >= 2:
			mastered_count += 1
	if mastered_count >= 7:
		_unlock_badge("All Skills Mastered")

func get_summary() -> Dictionary:
	return {
		"total_xp": total_xp,
		"level": get_level(),
		"level_title": get_level_title(),
		"level_progress": get_level_progress(),
		"streak": streak,
		"best_streak": best_streak,
		"correct_answers": correct_answers,
		"wrong_answers": wrong_answers,
		"builds_verified": builds_verified,
		"free_build_sessions": free_build_sessions,
		"challenges_finished": challenges_finished,
		"badges": badges.duplicate(),
		"mastery_stars": mastery_stars.duplicate(),
	}

func to_dict() -> Dictionary:
	return get_summary()

func from_dict(data: Dictionary) -> void:
	total_xp = int(data.get("total_xp", 0))
	streak = int(data.get("streak", 0))
	best_streak = int(data.get("best_streak", 0))
	correct_answers = int(data.get("correct_answers", 0))
	wrong_answers = int(data.get("wrong_answers", 0))
	builds_verified = int(data.get("builds_verified", 0))
	free_build_sessions = int(data.get("free_build_sessions", 0))
	challenges_finished = int(data.get("challenges_finished", 0))
	badges = (data.get("badges", []) as Array).duplicate()
	var stars: Variant = data.get("mastery_stars", {})
	if stars is Dictionary:
		mastery_stars = (stars as Dictionary).duplicate()