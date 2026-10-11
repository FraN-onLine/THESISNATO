extends Node
## SessionBridge autoload.
##
## Holds the single live SessionManager instance so the session survives scene
## changes between the main Testing Grounds flow and the separate Pretest /
## Post-test room. `test_mode` tells the TestRoom which test to run, and
## `pending_return` lets the room signal what the Grounds should show next.

const SessionManager = preload("res://Testing/session_manager.gd")

## The shared session (created lazily on first access).
var session = null

## Which test the TestRoom should run: "pretest" or "posttest".
var test_mode := ""

## Dev / privacy toggle (set from the Options popup on the main menu).
## When true, the Testing Grounds skips the Profile Setup screen entirely
## (no name / age / gender collection, nothing written to user://profiles)
## so the flow becomes: Algorithm Select -> Pretest.
## Default is TRUE for development so you don't have to type a profile on
## every run; flip it back on in Options when you need real data collection.
var skip_profile_collection := true

## Reserved for future return-routing (kept for symmetric API).
var pending_return := ""

## Dev / Options menu flags (toggled from the main-menu Settings popup).
## When `skip_profile_collection` is true the Testing Grounds bypasses the
## PROFILE SETUP screen entirely (no name / age / gender keypads, nothing
## written to user://profiles) and flows straight from algorithm select to
## the pretest intro. Temporary dev switch so playtests don't need PII.
var skip_profile_collection := false

## Verbose per-skill detail on the in-room Stats Board (K/E/n numbers).
## Turn off in Options for a minimal %-only board.
var verbose_board := true

func get_session():
	if session == null:
		session = SessionManager.new()
	return session

## Start a fresh session (used when the learner begins a brand-new flow).
func reset_session() -> void:
	session = SessionManager.new()
	test_mode = ""
	pending_return = ""