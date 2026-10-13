extends SceneTree
## Headless self-test for the VR / PC mode toggle in Settings (World/ui_panel.gd)
## and the InputMode autoload it drives (Game/input_manager.gd).
## Run:
##   Godot_v4.7-stable_win64_console.exe --path <project> --headless \
##     --script res://DevTests/selftest_input_mode.gd
##
## It verifies the contract the Settings switch relies on:
##   1. FRESH BOOT   - without a saved choice the preference is AUTO, so the
##                     original headset auto-detection still happens.
##   2. PC MODE      - set_mode(false) always lands on DESKTOP and remembers
##                     PC; a later VR request that finds no headset must NOT
##                     drop that explicit choice.
##   3. VR MODE      - only a VR request that really brings OpenXR up is
##                     remembered as VR, and toggle_mode stays in sync.
##   4. PERSISTENCE  - [options] vr_mode in user://settings.cfg round-trips:
##                     true -> Pref.VR, false -> Pref.PC + desktop lock,
##                     removing the key restores AUTO.
##   5. CLEANUP      - the developer's real settings.cfg is backed up and
##                     restored, so running the test changes nothing on disk.
## Prints REPORT lines and exits with code 0 (ok) or 1 (failures).

const InputModeScript = preload("res://Game/input_manager.gd")

const SETTINGS_PATH := "user://settings.cfg"

var _failures: Array[String] = []
var _backup := PackedByteArray()
var _backup_existed := false
var _managers: Array[Node] = []
var _frames := 0
var _started := false


func _initialize() -> void:
	# Managers are created from _process, not here: during _initialize the root
	# window has not entered the tree yet, so their _ready (which restores the
	# saved preference) would never fire - same reason selftest_builder.gd
	# defers its work to _process.
	_backup_settings()


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 2 or _started:
		return false
	_started = true
	_check_fresh_boot()
	_check_pc_and_vr_requests()
	_check_persistence()
	_restore_settings()
	_report()
	return false


# ===== 1: a boot without a saved choice stays AUTO ===========================

func _check_fresh_boot() -> void:
	_delete_settings()
	var im := _new_manager()
	_note(im.mode_pref == InputModeScript.Pref.AUTO,
		"no_saved_choice_means_auto", "pref=%d" % im.mode_pref)
	_note(im.is_vr() or im.is_desktop(),
		"mode_valid_after_boot", im.get_mode_name())


# ===== 2 + 3: explicit PC / VR requests =====================================

func _check_pc_and_vr_requests() -> void:
	var im := _new_manager()

	# PC mode: always succeeds and is remembered.
	im.set_mode(false)
	_note(im.is_desktop() and im.mode_pref == InputModeScript.Pref.PC,
		"set_mode_pc_locks_desktop", "mode=%s pref=%d" % [im.get_mode_name(), im.mode_pref])

	# A VR request must only be remembered when a headset really answered.
	im.set_mode(true)
	if im.is_vr():
		_note(im.mode_pref == InputModeScript.Pref.VR,
			"successful_vr_request_remembers_vr", "pref=%d" % im.mode_pref)
	else:
		_note(im.is_desktop() and im.mode_pref == InputModeScript.Pref.PC,
			"failed_vr_request_keeps_pc_choice", "mode=%s pref=%d" % [im.get_mode_name(), im.mode_pref])

	# toggle_mode() (main-menu Controls button) ends with pref == running mode.
	im.set_mode(false)
	im.toggle_mode()
	_note(im.is_vr() == (im.mode_pref == InputModeScript.Pref.VR),
		"toggle_mode_keeps_pref_in_sync", "mode=%s pref=%d" % [im.get_mode_name(), im.mode_pref])


# ===== 4: user://settings.cfg round-trip ====================================

func _check_persistence() -> void:
	_write_vr_mode(true)
	var vr := _new_manager()
	_note(vr.mode_pref == InputModeScript.Pref.VR,
		"saved_vr_preference_loaded", "pref=%d" % vr.mode_pref)

	_write_vr_mode(false)
	var pc := _new_manager()
	_note(pc.mode_pref == InputModeScript.Pref.PC and pc.is_desktop(),
		"saved_pc_preference_loaded_and_respected", "mode=%s pref=%d" % [pc.get_mode_name(), pc.mode_pref])

	# The PC lock must survive a VR request that finds no headset.
	pc.set_mode(true)
	if not pc.is_vr():
		_note(pc.mode_pref == InputModeScript.Pref.PC,
			"pc_lock_survives_failed_vr_request", "pref=%d" % pc.mode_pref)

	# Deleting the key restores headset auto-detection (AUTO).
	_delete_settings()
	var auto := _new_manager()
	_note(auto.mode_pref == InputModeScript.Pref.AUTO,
		"removing_key_restores_auto", "pref=%d" % auto.mode_pref)


# ===== helpers ===============================================================

func _new_manager() -> InputModeScript:
	var im: InputModeScript = InputModeScript.new()
	root.add_child(im)
	_managers.append(im)
	return im


func _backup_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return
	_backup = file.get_buffer(file.get_length())
	file.close()
	_backup_existed = true


func _restore_settings() -> void:
	if _backup_existed:
		var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
		if file != null:
			file.store_buffer(_backup)
			file.close()
	elif FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))


func _delete_settings() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))


func _write_vr_mode(value: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("options", "vr_mode", value)
	cfg.save(SETTINGS_PATH)


func _note(ok: bool, label: String, detail: String) -> void:
	if ok:
		print("REPORT  PASS  %-44s %s" % [label, detail])
	else:
		print("REPORT  FAIL  %-44s %s" % [label, detail])
		_failures.append(label)


func _report() -> void:
	print("REPORT ---- failures=%d ----" % _failures.size())
	for failure in _failures:
		print("REPORT  !! %s" % failure)
	print("REPORT DONE")
	quit(1 if not _failures.is_empty() else 0)