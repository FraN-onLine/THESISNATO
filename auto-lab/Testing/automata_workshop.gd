extends Node3D
## Presentation wrapper for the reusable AutomataWorkshop Control.
##
## This node only owns the WORKSHOP-specific concerns:
##   * persistent-overlay visibility so the board can stay on screen beside a
##     lesson panel,
##   * forwarding physical key presses into the board's text field,
##   * telling the builder to drop its drag/hover highlight when the pointer
##     leaves the board,
##   * re-emitting the builder's `evaluated` signal for the room controller.
##
## ALL pointer math (desktop exact-cursor ray-cast, VR lasers + haptics, the
## click-slop release fix) lives in the shared Lessons/panel_surface.gd, so a
## tap always lands exactly where the cursor/laser points and there is a single
## place to fix pointer behaviour for every board in the project.

signal evaluated(correct: bool, message: String)

const PanelSurface = preload("res://Testing/Lessons/panel_surface.gd")

@onready var viewport: SubViewport = $SubViewport
@onready var sprite: Sprite3D = $Billboard
@onready var builder: Control = $SubViewport/Builder

var _surface := PanelSurface.new()
var _persistent_overlay := false

## Keep the board hovering while lesson panels change. Input remains available
## in both desktop ray-cast mode and VR laser mode.
func set_persistent_overlay(enabled: bool) -> void:
	_persistent_overlay = enabled
	visible = enabled or visible
	set_process(enabled or visible)

func set_active(active: bool) -> void:
	visible = active or _persistent_overlay
	set_process(active or _persistent_overlay)
	_surface.set_active(active or _persistent_overlay)

func _ready() -> void:
	if InputMode.is_desktop():
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sprite.texture = viewport.get_texture()
	# STATIC board: it is fixed on its stand and never turns to face the player.
	PanelSurface.make_flat(sprite)
	builder.evaluated.connect(_on_builder_evaluated)
	_surface.setup(self, sprite, viewport)
	_surface.keyboard_filter = _forward_keyboard
	_surface.pointer_lost = _on_pointer_lost
	set_active(visible)

func _on_builder_evaluated(correct: bool, message: String) -> void:
	evaluated.emit(correct, message)
	builder.set_meta("last_evaluation", {"correct": correct, "message": message})

func _input(event: InputEvent) -> void:
	_surface.handle_input(event)

func _process(_delta: float) -> void:
	if InputMode.is_desktop():
		Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	_surface.process_pointer()

## On PC the workshop controls live inside a SubViewport, so physical keyboard
## presses must be forwarded while the simulate field is focused.
func _forward_keyboard(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null:
		return
	var line: LineEdit = builder.get("input_line") if builder else null
	var keyboard_active: bool = builder.get("simulation_keyboard_active") if builder else false
	if line == null or not (line.has_focus() or keyboard_active):
		return
	if key_event.pressed and (key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER):
		builder.call("_simulate_input")
		get_viewport().set_input_as_handled()
		return
	viewport.push_input(key_event)

func _on_pointer_lost() -> void:
	if builder.has_method("cancel_pointer_interaction"):
		builder.cancel_pointer_interaction()
