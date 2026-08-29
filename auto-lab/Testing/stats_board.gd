extends Node3D
## A self-contained 3D "stats blackboard" that always faces the player (billboard)
## and renders a live text report of the current session: per-skill mastery from
## EACH algorithm (HMM / BKT / DKT), whiteboard attempt analytics, and progress.

@onready var viewport: SubViewport = $SubViewport
@onready var sprite: Sprite3D = $Billboard
@onready var label: Label = $SubViewport/Root/Margin/Panel/Scroll/Label

func _ready() -> void:
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sprite.texture = viewport.get_texture()
	# Face the player at all times.
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	set_stats_text("Session stats will appear here.\n\nHMM / BKT / DKT are all running\nin parallel for comparison.")

## Update the report shown on the board.
func set_stats_text(content: String) -> void:
	if label:
		label.text = content