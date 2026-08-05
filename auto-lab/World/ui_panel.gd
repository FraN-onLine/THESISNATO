extends Node3D
## Wires the SubViewport render texture to the billboard Sprite3D.

@onready var viewport: SubViewport = $SubViewport
@onready var sprite: Sprite3D = $Billboard

func _ready() -> void:
	if viewport and sprite:
		sprite.texture = viewport.get_texture()
