extends Control
## Checkpoint / reward notifications.
##
## A stack of animated banners pinned to the top of a panel. Everything that
## happens in a lesson announces itself here: a checkpoint was reached, XP was
## earned, a streak doubled, a level was unlocked, a remedy panel was injected,
## a skill was mastered. Purely cosmetic - nothing in the lesson depends on it.
##
## The banners fade themselves out and free themselves, so callers only have to
## call announce_* - no bookkeeping.

const COLORS := {
	"checkpoint": Color(0.25, 0.55, 0.95, 0.95),
	"reward": Color(0.2, 0.62, 0.4, 0.95),
	"streak": Color(0.85, 0.45, 0.15, 0.95),
	"remedy": Color(0.55, 0.4, 0.85, 0.95),
	"mastery": Color(0.85, 0.7, 0.2, 0.95),
	"info": Color(0.2, 0.28, 0.45, 0.92),
}

const WIDTH := 980.0

var _stack: VBoxContainer
var _history: Array[String] = []

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack = VBoxContainer.new()
	_stack.add_theme_constant_override("separation", 6)
	_stack.alignment = BoxContainer.ALIGNMENT_BEGIN
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_stack.offset_left = 20.0
	_stack.offset_right = -20.0
	_stack.offset_top = 12.0
	add_child(_stack)

## One-off banner. `kind` picks the colour; unknown kinds fall back to "info".
func announce(text: String, kind := "info", seconds := 3.2) -> void:
	if text.strip_edges() == "":
		return
	_history.append("%s: %s" % [kind, text])
	if _history.size() > 40:
		_history.remove_at(0)
	if _stack == null:
		return
	var banner := _make_banner(text, kind)
	_stack.add_child(banner)
	if _stack.get_child_count() > 4:
		_stack.get_child(0).queue_free()
	var tween := banner.create_tween()
	banner.modulate.a = 0.0
	banner.scale = Vector2(0.94, 0.94)
	banner.pivot_offset = Vector2(WIDTH * 0.5, 22.0)
	tween.tween_property(banner, "modulate:a", 1.0, 0.18)
	tween.parallel().tween_property(banner, "scale", Vector2.ONE, 0.18)
	tween.tween_interval(seconds)
	tween.tween_property(banner, "modulate:a", 0.0, 0.35)
	tween.tween_callback(banner.queue_free)

## "CHECKPOINT 3 / 9 - trace the string ..." plus a nudge when it is a big one.
func announce_checkpoint(number: int, total: int, prompt: String) -> void:
	var trimmed := prompt.strip_edges()
	if trimmed.length() > 90:
		trimmed = trimmed.substr(0, 87) + "..."
	announce("CHECKPOINT %d / %d   %s" % [number, total, trimmed], "checkpoint")

func announce_reward(xp: int, streak: int, first_try: bool, level_event: Dictionary) -> void:
	var parts: Array[String] = []
	if first_try:
		parts.append("FIRST TRY!")
	if xp > 0:
		parts.append("+%d XP" % xp)
	if streak >= 2:
		parts.append("STREAK x%d" % streak)
	var kind := "reward"
	if streak >= 3:
		kind = "streak"
	if not parts.is_empty():
		announce("   ".join(parts), kind, 2.4)
	if not level_event.is_empty():
		announce("LEVEL %d - %s" % [int(level_event.get("level", 1)), str(level_event.get("title", ""))], "mastery", 3.6)

func announce_remedy(attempt: int, title: String) -> void:
	announce("LET'S SLOW DOWN  (help %d)  -  %s" % [attempt, title], "remedy", 3.4)

func announce_practice(round_number: int, count: int, skill_name: String) -> void:
	announce("PRACTICE ROUND %d  -  %d more %s items" % [round_number, count, skill_name], "checkpoint", 3.2)

func announce_mastery(skill_name: String, mastered: bool, mastery_pct: float) -> void:
	if mastered:
		announce("SKILL MASTERED: %s (%.0f%%)" % [skill_name, mastery_pct], "mastery", 4.0)

func announce_module(summary: Dictionary) -> void:
	announce("%s  -  %s   score %.0f%%   xp %d" % [
		str(summary.get("title", "MODULE")),
		str(summary.get("headline", "")),
		float(summary.get("score", 0.0)),
		int(summary.get("xp", 0)),
	], "mastery", 5.0)

func get_history() -> Array[String]:
	return _history.duplicate()

func _make_banner(text: String, kind: String) -> PanelContainer:
	var colour: Color = COLORS.get(kind, COLORS["info"])
	var banner := PanelContainer.new()
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.custom_minimum_size = Vector2(0, 52)
	var style := StyleBoxFlat.new()
	style.bg_color = colour
	style.set_corner_radius_all(12)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	banner.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(label)
	return banner
