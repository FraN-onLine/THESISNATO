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

## Active-algorithm entry point. The host builds the text; the board only paints.
func set_active_stats(data: Dictionary) -> void:
	var algo := str(data.get("algorithm", "HMM"))
	var lines: Array = data.get("lines", [])
	var phase := str(data.get("phase", ""))
	var out: Array[String] = []
	out.append("SESSION STATS | %s" % phase if phase != "" else "SESSION STATS")
	out.append("ACTIVE: %s" % algo)
	for line in lines:
		out.append(str(line))
	if lines.is_empty():
		out.append("No observations yet")
	set_stats_text("\n".join(out))
