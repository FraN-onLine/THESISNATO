extends RefCounted
## Profile Manager for storing and loading user profiles.
## Stores name, gender, age, and automata familiarity.

const PROFILE_PATH := "user://profiles/"
const PROFILE_FILE := "user://profiles/current_profile.json"

var current_profile: Dictionary = {}

func _init() -> void:
	_load_profile()

## Create a new profile
func create_profile(name: String, gender: String, age: int, familiar_with_automata: bool) -> void:
	current_profile = {
		"name": name,
		"gender": gender,
		"age": age,
		"familiar_with_automata": familiar_with_automata,
		"created_at": Time.get_datetime_string_from_system(),
		"last_updated": Time.get_datetime_string_from_system()
	}
	_save_profile()

## Update profile fields
func update_profile(data: Dictionary) -> void:
	for key in data:
		current_profile[key] = data[key]
	current_profile["last_updated"] = Time.get_datetime_string_from_system()
	_save_profile()

## Get the current profile
func get_profile() -> Dictionary:
	return current_profile.duplicate()

## Check if a profile exists
func has_profile() -> bool:
	return not current_profile.is_empty()

## Get profile name
func get_name() -> String:
	return current_profile.get("name", "")

## Get profile gender
func get_gender() -> String:
	return current_profile.get("gender", "")

## Get profile age
func get_age() -> int:
	return current_profile.get("age", 0)

## Is familiar with automata
func is_familiar_with_automata() -> bool:
	return current_profile.get("familiar_with_automata", false)

## Save the profile to disk
func _save_profile() -> void:
	var dir := DirAccess.open("user://")
	if dir:
		if not dir.dir_exists("profiles"):
			dir.make_dir("profiles")
	
	var file := FileAccess.open(PROFILE_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(current_profile, "\t"))
		file.close()

## Load the profile from disk
func _load_profile() -> void:
	if not FileAccess.file_exists(PROFILE_FILE):
		return
	
	var file := FileAccess.open(PROFILE_FILE, FileAccess.READ)
	if file:
		var text := file.get_as_text()
		file.close()
		var json := JSON.new()
		var err := json.parse(text)
		if err == OK and json.data is Dictionary:
			current_profile = json.data

## Clear the current profile
func clear_profile() -> void:
	current_profile = {}
	if FileAccess.file_exists(PROFILE_FILE):
		DirAccess.remove_absolute(PROFILE_FILE)