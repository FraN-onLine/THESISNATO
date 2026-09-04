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

## Reserved for future return-routing (kept for symmetric API).
var pending_return := ""

func get_session():
	if session == null:
		session = SessionManager.new()
	return session

## Start a fresh session (used when the learner begins a brand-new flow).
func reset_session() -> void:
	session = SessionManager.new()
	test_mode = ""
	pending_return = ""