extends SceneTree
## DEV-ONLY integrity check for the whole project. Nothing in the game loads
## this file - it lives in DevTests/ with the other headless checks.
##
## Run:
##   Godot_v4.7-stable_win64_console.exe --path <project> --headless ^
##     --script res://DevTests/validate_scripts.gd
##
## Two layers, failures printed as "FAILED <file>  ->  <what>" lines:
##   1. SCRIPTS    - every .gd outside DevTests/ must compile.
##   2. REFERENCES - every res:// file path written in a .gd / .tscn / .tres
##                   must exist. A deleted scene or a renamed asset shows up
##                   here instead of at run time.
## Missing media (images / audio) is only reported as OPTIONAL: the game is
## built to keep working without it (see Images/README.md and Audio/Voice).
##
## Exits 1 when something failed, 0 when the project is clean.

## Files whose text is scanned for res:// references.
const SCAN_EXTENSIONS := ["gd", "tscn", "tres"]
## Extensions that must exist when referenced (code / scene data).
const REQUIRED_EXTENSIONS := ["gd", "tscn", "tres"]
## Extensions that are nice to have; missing ones are reported as OPTIONAL.
const OPTIONAL_EXTENSIONS := ["svg", "png", "jpg", "jpeg", "webp", "ogg", "wav", "mp3"]

var _ref_regex := RegEx.new()


func _collect(dir_path: String, found: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var full := dir_path.path_join(entry)
			if dir.current_is_dir():
				_collect(full, found)
			else:
				found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()


func _initialize() -> void:
	var extensions := "|".join(REQUIRED_EXTENSIONS + OPTIONAL_EXTENSIONS)
	_ref_regex.compile("res://[A-Za-z0-9_./%-]+\\.(" + extensions + ")")
	var found: Array = []
	_collect("res://", found)
	found.sort()

	var failures: Array = []
	var optional: Array = []
	for path in found:
		var extension := str(path).get_extension()
		if not SCAN_EXTENSIONS.has(extension):
			continue
		if extension == "gd":
			_check_script(str(path), failures)
		_check_references(str(path), failures, optional)

	for line in failures:
		print("FAILED ", line)
	for line in optional:
		print("OPTIONAL ", line)
	print("FAILED_COUNT ", failures.size())
	print("DONE")
	quit(1 if not failures.is_empty() else 0)


## A script must compile: GDScript returns null when it does not.
func _check_script(path: String, failures: Array) -> void:
	if not _is_game_file(path):
		return
	var probe: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if probe == null:
		failures.append(path)


## Every res:// path written in the file must point at something that exists.
func _check_references(path: String, failures: Array, optional: Array) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		failures.append("%s  (unreadable)" % path)
		return
	var text := file.get_as_text()
	file.close()
	var seen: Array = []
	for hit in _ref_regex.search_all(text):
		var target := hit.get_string()
		if seen.has(target):
			continue
		seen.append(target)
		if ResourceLoader.exists(target) or FileAccess.file_exists(target):
			continue
		if REQUIRED_EXTENSIONS.has(target.get_extension()):
			failures.append("%s  ->  %s" % [path, target])
		else:
			optional.append("%s  ->  %s" % [path, target])


## DevTests/ and the "_"-prefixed scratch files test themselves, never the game.
func _is_game_file(path: String) -> bool:
	return not path.begins_with("res://DevTests/") and not path.begins_with("res://_")
