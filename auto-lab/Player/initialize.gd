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
	# Find the OpenXR interface (may be null if the module is unavailable).
	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface == null:
		# No OpenXR module loaded → definitely desktop mode.
		return

	# Raise the interface now if InputMode wants VR but it isn't initialized yet
	# (InputMode only marks VR mode when a headset was detected).
	if InputMode.is_vr() and not xr_interface.is_initialized():
		xr_interface.initialize()

	# Only hand the viewport to XR when VR mode is active AND the interface is
	# actually running. Otherwise the normal Camera3D drives the view.
	if InputMode.is_vr() and xr_interface.is_initialized():
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		get_viewport().use_xr = true
		
