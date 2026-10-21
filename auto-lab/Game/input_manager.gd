extends Node
## InputMode manager (registered as the global autoload "InputMode").
##
## XR startup is deliberately kept OFF this script's critical path: raising
## OpenXR means a blocking handshake with whatever runtime is installed (Oculus
## / Meta Horizon Link), which is the single most expensive thing that happens
## during boot. So:
##   - The game always boots in Keyboard+Mouse mode and draws its first frames
##     immediately; nothing here blocks the autoload's _ready().
##   - Headset detection is deferred to a short boot probe. When a headset
##     answers, the whole game switches into VR mode (joystick + controller
##     ray-casting) via [signal mode_changed].
##   - The expensive [method XRInterface.initialize] call is budgeted: only every
##     other probe may attempt it and only a few times in total; the probes in
##     between just re-check the cheap [method XRInterface.is_initialized] flag.
##     Without that budget a machine whose headset never answers pays the full
##     runtime handshake once a second for the whole boot window.
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

## Seconds between boot probes.
const PROBE_INTERVAL_SEC := 1.0
## How many probes run before the game gives up on auto-detecting a headset.
## Long enough that a Meta Link / Quest runtime still waking up gets picked up.
const PROBE_MAX := 8
## How many of those probes may pay for a blocking XRInterface.initialize(), and
## only every OTHER probe is allowed to (see _probe). The cheap probes in between
## just re-read is_initialized(), so a PC whose headset never answers stops
## hitching instead of repeating a multi-hundred-millisecond runtime handshake
## once a second for the whole boot window.
const INIT_ATTEMPT_MAX := 4
## Delay before the very first probe: keeps the XR handshake off the boot frame
## so the main menu is on screen before anything blocking happens.
const FIRST_PROBE_DELAY_SEC := 0.4

func _ready() -> void:
	_load_preference()
	if mode_pref == Pref.PC or _is_headless():
		# The user explicitly chose PC mode - or there is no display at all
		# (headless test/CI runs). Stay on desktop: skip the probe so OpenXR is
		# never raised, which would otherwise crash or alert inside such runs.
		_set_running_mode(Mode.DESKTOP)
		return
	# Desktop for the first frames; the probe picks a headset up moments later.
	_start_probe(FIRST_PROBE_DELAY_SEC)

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
		# spent its budget while no headset was attached.
		_xr_init_attempted = false
		_init_attempts = 0
		_detect_vr(true)
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
## - Otherwise, only attempt the (blocking) initialization when [param allow_init]
##   is true: an explicit user request always may, the background boot probe may
##   until it runs out of budget. When no headset answers the game simply keeps
##   running in keyboard/mouse mode.
## - Never in a headless run: there is no XR display, so requesting OpenXR
##   would only crash the process or pop the "OpenXR failed to start" alert.
func _detect_vr(allow_init: bool) -> void:
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
	if allow_init and not _xr_init_attempted:
		_init_attempts += 1
		if xr.initialize():
			_xr_init_attempted = true
			_set_running_mode(Mode.VR)
			return
	_set_running_mode(Mode.DESKTOP)

func _set_running_mode(new_mode: int) -> void:
	if mode == new_mode:
		return
	mode = new_mode
	mode_changed.emit(is_vr())

## True when the engine runs without any display (`--headless` test runs).
func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"

## Keep probing after launch — PC stays the fallback until a headset answers.
func _start_probe(delay: float = PROBE_INTERVAL_SEC) -> void:
	var timer := get_tree().create_timer(delay)
	timer.timeout.connect(_probe)

var _probe_count := 0
var _init_attempts := 0

func _probe() -> void:
	_probe_count += 1
	if mode_pref == Pref.PC:
		return
	# Meta Link / Quest often wake a few seconds after the app starts, so keep
	# looking for the whole probe window — but the blocking initialize() is only
	# allowed on every other probe and only until its budget is spent. The probes
	# in between are free: they just re-read is_initialized().
	var may_initialize := _init_attempts < INIT_ATTEMPT_MAX and _probe_count % 2 == 1
	_detect_vr(may_initialize)
	if _probe_count < PROBE_MAX and is_desktop():
		_start_probe()


## Restore the user's explicit VR/PC choice, if one was ever saved (the
## Settings popup writes it to user://settings.cfg as [options] vr_mode).
func _load_preference() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	if not cfg.has_section_key("options", "vr_mode"):
		return
	mode_pref = Pref.VR if bool(cfg.get_value("options", "vr_mode", false)) else Pref.PC
