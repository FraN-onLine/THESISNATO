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
##   - The user can also force the mode from the main-menu Controls button or
##     the Settings popup; an explicit choice is saved to user://settings.cfg
##     ([options] vr_mode) and respected on later boots.
##   - Headless runs (tests / CI) always stay in Keyboard+Mouse mode: with no
##     display there is nothing for XR to render into.

enum Mode { DESKTOP, VR }

## Explicit mode preference, persisted as [options] vr_mode in user://settings.cfg.
##   AUTO - nothing saved yet: a connected headset is auto-detected at boot.
##   PC   - the user chose PC mode: OpenXR is never raised and the boot probe
##          that would flip the game into VR is suppressed.
##   VR   - the user chose VR mode: OpenXR is raised whenever possible.
enum Pref { AUTO, PC, VR }

## The settings file shared with the main-menu Settings popup.
const SETTINGS_PATH := "user://settings.cfg"

## Current input mode. Starts as DESKTOP and switches to VR automatically when
## a headset is detected (or manually via the Settings toggle / Controls button).
var mode: int = Mode.DESKTOP

## The user's explicit mode choice; Pref.AUTO until they pick one.
var mode_pref: int = Pref.AUTO

## Emitted whenever [member mode] switches between desktop and VR (including
## when a headset connects after boot). Player XR setup and movement listen.
signal mode_changed(is_vr: bool)

## Set after a successful OpenXR [method XRInterface.initialize]; cleared when
## the user explicitly requests VR again via [method set_mode].
var _xr_init_attempted := false

const PROBE_INTERVAL_SEC := 1.0
const PROBE_MAX := 15

func _ready() -> void:
	_load_preference()
	if mode_pref == Pref.PC or _is_headless():
		# The user explicitly chose PC mode - or there is no display at all
		# (headless test/CI runs). Stay on desktop: skip the probe so OpenXR is
		# never raised, which would otherwise crash or alert inside such runs.
		_set_running_mode(Mode.DESKTOP)
		return
	# Desktop by default; probe for a headset shortly after boot.
	_detect_vr()
	_start_probe()

func is_vr() -> bool:
	return mode == Mode.VR

func is_desktop() -> bool:
	return mode == Mode.DESKTOP

## Toggle between keyboard/mouse and AR/VR control modes.
func toggle_mode() -> void:
	set_mode(not is_vr())

## Explicitly request a mode (Settings popup / main-menu Controls button).
## Switching to PC always works and is remembered. Switching to VR re-tries
## OpenXR: when a headset answers the choice is remembered as VR, when none
## does the current preference stays untouched (AUTO keeps auto-detecting on
## later boots and an explicit PC is never silently dropped). Callers should
## check is_vr() afterwards to see what actually happened.
func set_mode(want_vr: bool) -> void:
	if want_vr:
		# Allow a fresh initialization attempt even if the boot probe already
		# spent tries while no headset was attached.
		_xr_init_attempted = false
		_detect_vr()
		if is_vr():
			mode_pref = Pref.VR
	else:
		mode_pref = Pref.PC
		_set_running_mode(Mode.DESKTOP)

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
## - Never in a headless run: there is no XR display, so requesting OpenXR
##   would only crash the process or pop the "OpenXR failed to start" alert.
func _detect_vr() -> void:
	if mode_pref == Pref.PC or _is_headless():
		_set_running_mode(Mode.DESKTOP)
		return
	var xr := get_xr_interface()
	if xr == null:
		_set_running_mode(Mode.DESKTOP)
		return
	if xr.is_initialized():
		_xr_init_attempted = true
		_set_running_mode(Mode.VR)
		return
	# Meta Link / Quest often wake a few seconds after the app starts — retry
	# during the boot probe instead of giving up after a single failed init.
	if _boot_probe_active() or not _xr_init_attempted:
		if xr.initialize():
			_xr_init_attempted = true
			_set_running_mode(Mode.VR)
		else:
			_set_running_mode(Mode.DESKTOP)
	else:
		_set_running_mode(Mode.DESKTOP)

func _set_running_mode(new_mode: int) -> void:
	if mode == new_mode:
		return
	mode = new_mode
	mode_changed.emit(is_vr())

## True when the engine runs without any display (`--headless` test runs).
func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"

func _boot_probe_active() -> bool:
	return _probe_count < PROBE_MAX

## Keep probing after launch — PC stays the fallback until a headset answers.
func _start_probe() -> void:
	var timer := get_tree().create_timer(PROBE_INTERVAL_SEC)
	timer.timeout.connect(_probe)

var _probe_count := 0

func _probe() -> void:
	_probe_count += 1
	if mode_pref == Pref.PC:
		return
	_detect_vr()
	if _probe_count < PROBE_MAX and is_desktop():
		var timer := get_tree().create_timer(PROBE_INTERVAL_SEC)
		timer.timeout.connect(_probe)


## Restore the user's explicit VR/PC choice, if one was ever saved (the
## Settings popup writes it to user://settings.cfg as [options] vr_mode).
func _load_preference() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	if not cfg.has_section_key("options", "vr_mode"):
		return
	mode_pref = Pref.VR if bool(cfg.get_value("options", "vr_mode", false)) else Pref.PC
