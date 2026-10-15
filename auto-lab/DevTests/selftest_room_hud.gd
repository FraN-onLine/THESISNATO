extends SceneTree
## Headless self-test for the in-room VR status billboard (Testing/room_hud.gd).
## The panel only spawns in VR, so a headset-less machine can never exercise it
## through the rooms; this test builds it exactly like _ready does and verifies
## the phase mapping and the stopwatch text.
##
## Run:
##   Godot_v4.7-stable_win64_console.exe --path <project> --headless \ 
##     --xr-mode off --script res://DevTests/selftest_room_hud.gd
##
## Prints REPORT lines and exits with code 0 (ok) or 1 (failures).

const SessionManager = preload("res://Testing/session_manager.gd")

var _failures: Array[String] = []
var _frames := 0
var _started := false
var _hud: Node3D


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 2 or _started:
		return false
	_started = true
	_check_build()
	_check_phase_mapping()
	_check_stopwatch()
	_report()
	return false


## The panel must come up as a real billboard: a SubViewport whose texture is
## shown on a Sprite3D (same contract as every board in the room).
func _check_build() -> void:
	# Runtime load, not preload: room_hud.gd references the SessionBridge
	# autoload, which a --script run can only resolve once the autoloads exist.
	var room_hud_script: GDScript = load("res://Testing/room_hud.gd")
	_hud = room_hud_script.new()
	root.add_child(_hud)
	var viewport: SubViewport = null
	var sprite: Sprite3D = null
	for child in _hud.get_children():
		if child is SubViewport:
			viewport = child
		elif child is Sprite3D:
			sprite = child
	_note(viewport != null, "room_hud_has_subviewport", "children=%d" % _hud.get_child_count())
	_note(sprite != null and sprite.texture != null,
		"room_hud_sprite_shows_viewport", "texture=%s" % str(sprite.texture if sprite else null))
	_note(_hud.visible, "room_hud_visible_with_session", "visible=%s" % str(_hud.visible))


## The 4-phase strip must map the session state exactly like phase_hud.gd.
func _check_phase_mapping() -> void:
	_note(int(_hud.call("_phase_index", null)) == -1,
		"no_session_hides_the_hud", "idx=%d" % int(_hud.call("_phase_index", null)))
	var cases := {
		SessionManager.SessionState.PROFILE_SETUP: 0,
		SessionManager.SessionState.PRETEST: 0,
		SessionManager.SessionState.ANALYSIS: 1,
		SessionManager.SessionState.ADAPTIVE_LEARNING: 2,
		SessionManager.SessionState.POST_TEST: 3,
		SessionManager.SessionState.COMPLETE: 3,
	}
	var bad: Array[String] = []
	for state in cases:
		var s := SessionManager.new()
		s.state = state
		var got: int = int(_hud.call("_phase_index", s))
		if got != cases[state]:
			bad.append("state %d -> %d (want %d)" % [state, got, cases[state]])
	_note(bad.is_empty(), "phase_mapping_matches_phase_hud", "bad=%s" % str(bad))


## The stopwatch must show the same clocks counting_timer_overlay.gd shows:
## adaptive completion time while learning, post-test time during the test.
func _check_stopwatch() -> void:
	var learning := SessionManager.new()
	learning.start_adaptive_learning("definition")
	_hud.call("_sync_timer", learning)
	var adaptive_text: String = _hud.get("_timer").text
	_note(adaptive_text.begins_with("Adaptive Learning  "),
		"timer_shows_adaptive_clock", "text='%s'" % adaptive_text)

	learning.start_posttest()
	_hud.call("_sync_timer", learning)
	var post_text: String = _hud.get("_timer").text
	_note(post_text.begins_with("Post Test  "),
		"timer_switches_to_posttest_clock", "text='%s'" % post_text)

	var idle := SessionManager.new()
	_hud.call("_sync_timer", idle)
	_note(not _hud.get("_timer").visible,
		"timer_hidden_outside_the_two_timed_phases", "text='%s'" % _hud.get("_timer").text)


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
