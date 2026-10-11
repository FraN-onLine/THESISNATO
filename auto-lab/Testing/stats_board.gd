extends Node3D
## A static 3D "stats blackboard": it NEVER auto-faces the player (stays flat
## where the room placed it) and renders the ACTIVE algorithm's probabilities.
##
## ONE ALGORITHM is active at a time (chosen on AlgorithmSelect). Only that
## algorithm receives observations and only it is shown here — this is how we
## compare algorithms across runs for the full project.
##
## Expected host wiring (TestingGrounds passes a Dictionary each frame):
##   set_active_stats({"algorithm": "HMM"|"BKT"|"KST", "lines": [...], "phase": ...})
## `lines` are pre-formatted "Skill: 62% ..." strings from the active model.

@onready var viewport: SubViewport = $SubViewport
@onready var sprite: Sprite3D = $Billboard
@onready var label: Label = $SubViewport/Root/Margin/Panel/Label

func _ready() -> void:
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sprite.texture = viewport.get_texture()
	# STATIC: bolted to the wall, never turns to face the player.
	sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	set_stats_text("Session stats will appear here.\n\nOnly the ACTIVE algorithm\n(HMM / BKT / KST) is tracked.")

## Update the report shown on the board.
func set_stats_text(content: String) -> void:
	if label:
		label.text = content

## Mastery bar the host can reuse: e.g. "####------ 40%".
static func mastery_bar(pct: float, width: int = 12) -> String:
	var filled := int(round(clampf(pct, 0.0, 100.0) / 100.0 * float(width)))
	var out := ""
	for i in range(width):
		out += "#" if i < filled else "-"
	return out

## Active-algorithm entry point. The host builds the text; the board only paints.
##
## `data` keys: "algorithm" (HMM|BKT|KST), "phase", "lines" (the live per-skill
## numbers), "params" (one short "K = P(knows)" description per parameter shown,
## so nobody has to guess what the letters mean), "params_full" (the longer
## "SYMBOL - meaning" statements), "skips" (skill -> count of
## whiteboard tasks the learner chose to skip instead of building),
## "verbose" (false = minimal %-only skill rows), "accuracy" (overall
## prediction accuracy of the ACTIVE model, 0-100), "phase_counts" (how many
## observations each phase fed the model: pretest / learning / posttest),
## "mastery_gate" (text such as "MASTERED 3/5 — 2 more to unlock Post Test").
func set_active_stats(data: Dictionary) -> void:
	var algo := str(data.get("algorithm", "HMM"))
	var lines: Array = data.get("lines", [])
	var params: Array = data.get("params", [])
	var params_full: Array = data.get("params_full", [])
	var skips: Dictionary = data.get("skips", {})
	var phase := str(data.get("phase", ""))
	var verbose := bool(data.get("verbose", true))
	var accuracy := float(data.get("accuracy", -1.0))
	var phase_counts: Dictionary = data.get("phase_counts", {})
	var mastery_gate := str(data.get("mastery_gate", ""))
	var out: Array[String] = []
	# -- Header -----------------------------
	var header := "SESSION STATS"
	if phase != "":
		header += "  |  %s" % phase.to_upper()
	out.append(header)
	out.append("ACTIVE: %s" % algo.to_upper())
	if accuracy >= 0.0:
		out.append("MODEL ACCURACY: %.1f%%  (%s predictions match reality)" % [accuracy, algo.to_upper()])
	out.append("----------------------------------------")
	# -- Per-skill block --------------------
	if lines.is_empty():
		out.append("No observations yet.")
		out.append("Answer the pretest - its answers are the model's only starting input.")
	else:
		out.append("SKILLS")
		for line in lines:
			var parts := str(line).split("|")
			var head := parts[0].strip_edges() if parts.size() > 0 else str(line)
			var tail := parts[1].strip_edges() if parts.size() > 1 else ""
			var pct := 0.0
			for token in head.split(" "):
				if token.ends_with("%"):
					pct = float(token.trim_suffix("%"))
			var bar := mastery_bar(pct)
			out.append("  %s" % head)
			out.append("    [%s]" % bar)
			if verbose and tail != "":
				out.append("    %s" % tail)
	# -- Phase tracker ----------------------
	if not phase_counts.is_empty():
		out.append("")
		out.append("LEARNING THROUGH THE 3 PHASES")
		var pre := int(phase_counts.get("pretest", 0))
		var lea := int(phase_counts.get("learning", 0))
		var post := int(phase_counts.get("posttest", 0))
		out.append("  [INPUT]    pretest answers fed: %d" % pre)
		out.append("  [LEARN]    learning answers analysed: %d" % lea)
		out.append("  [PROVE]    posttest answers fed: %d" % post)
		if mastery_gate != "":
			out.append("  %s" % mastery_gate)
	# -- Parameter legend -------------------
	if not params.is_empty():
		out.append("")
		out.append("LEGEND - what the letters mean")
		for i in range(params.size()):
			var short := str(params[i])
			var full := str(params_full[i]) if i < params_full.size() else ""
			if verbose and full != "" and full != short:
				out.append("  %s" % short)
				out.append("      %s" % full)
			else:
				out.append("  %s" % short)
	var skipped: Array[String] = []
	for skill in skips:
		var count := int(skips[skill])
		if count > 0:
			skipped.append("%s x%d" % [str(skill), count])
	if not skipped.is_empty():
		out.append("")
		out.append("SKIPPED TASKS: %s" % ", ".join(skipped))
		out.append("(a Skip is not an answer - it only lowers that skill)")
	set_stats_text("\n".join(out))
