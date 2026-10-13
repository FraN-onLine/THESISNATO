extends Node
## Player XR initialization node.
##
## XR is NO LONGER force-enabled at engine startup (project.godot sets
## xr/openxr/enabled=false). This script tries to bring the OpenXR interface up
## at runtime only when a headset is available (InputMode.is_vr() becomes true),
## then hands the main viewport over to the XR camera. On a plain desktop this
## entire block is skipped so the game runs normally with the mouse-camera.

var xr_interface: XRInterface

func _ready() -> void:
	if not InputMode.mode_changed.is_connected(_apply_xr_viewport):
		InputMode.mode_changed.connect(_apply_xr_viewport)
	_apply_xr_viewport(InputMode.is_vr())

func _apply_xr_viewport(_is_vr: bool = InputMode.is_vr()) -> void:
	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface == null:
		get_viewport().use_xr = false
		return
	if InputMode.is_vr():
		if not xr_interface.is_initialized():
			xr_interface.initialize()
		if xr_interface.is_initialized():
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			get_viewport().use_xr = true
			return
	get_viewport().use_xr = false
