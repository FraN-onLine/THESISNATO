extends Node
## InputMode manager (registered as the global autoload "InputMode").
##
## The system no longer REQUESTS XR at engine startup (project.godot sets
## xr/openxr/enabled=false). Instead:
##   - On a normal desktop (no headset) the game boots in Keyboard+Mouse mode
##     with zero OpenXR warnings/errors.
##   - When an AR/VR headset IS connected, this manager lazily finds and
##     initializes the OpenXR interface a moment after launch, then switches
##     the whole game into VR mode (joystick + controller ray-casting).
##   - The user can also force the mode from the main-menu Controls button.

enum Mode { DESKTOP, VR }

## Current input mode. Starts as DESKTOP and switches to VR automatically when
## a headset is detected (or manually via the main-menu Controls toggle).
var mode: int = Mode.DESKTOP

## Guard so we only attempt the (potentially heavy) OpenXR init once per run.
var _xr_init_attempted := false

func _ready() -> void:
	# Desktop by default; probe for a headset shortly after boot.
	_detect_vr()
	_start_probe()

func is_vr() -> bool:
	return mode == Mode.VR

func is_desktop() -> bool:
	return mode == Mode.DESKTOP

## Toggle between keyboard/mouse and AR/VR control modes.
func toggle_mode() -> void:
	if is_vr():
		# Leaving VR: fall back to plain desktop (Keyboard + Mouse).
		mode = Mode.DESKTOP
	else:
		# Entering VR: try to initialize OpenXR; if it fails we stay desktop.
		_detect_vr()

func get_mode_name() -> String:
	return "AR / VR" if is_vr() else "Keyboard + Mouse"

## Returns true when a usable OpenXR interface currently exists.
func get_xr_interface() -> XRInterface:
	return XRServer.find_interface("OpenXR")

## Detect a connected headset.
## - If OpenXR is already initialized, switch to VR immediately.
## - If an interface exists but is not initialized yet, try ONE gentle
##   initialization. When no headset is attached this fails silently and the
##   game simply keeps running in keyboard/mouse mode.
func _detect_vr() -> void:
	var xr := get_xr_interface()
	if xr == null:
		mode = Mode.DESKTOP
		return
	if xr.is_initialized():
		mode = Mode.VR
		return
	if not _xr_init_attempted:
		_xr_init_attempted = true
		# This initializes the OpenXR runtime. With no headset it returns false
		# quickly; with a headset it succeeds and get_is_active() becomes true.
		if xr.initialize():
			mode = Mode.VR
		else:
			mode = Mode.DESKTOP

## Keep probing for a few seconds after launch — a headset may be slow to wake.
func _start_probe() -> void:
	var timer := get_tree().create_timer(1.0)
	timer.timeout.connect(_probe)

var _probe_count := 0

func _probe() -> void:
	_probe_count += 1
	_detect_vr()
	# Only keep probing while nothing is initialized yet and few attempts remain.
	if _probe_count < 4 and is_desktop():
		var timer := get_tree().create_timer(1.0)
		timer.timeout.connect(_probe)