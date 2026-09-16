extends SceneTree


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
			elif entry.ends_with(".gd"):
				found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()


func _initialize() -> void:
	var found: Array = []
	_collect("res://", found)
	found.sort()
	var failed: Array = []
	for script_path in found:
		if script_path.ends_with("validate_scripts.gd") or script_path.begins_with("res://_"):
			continue
		var probe: Resource = ResourceLoader.load(script_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if probe == null:
			failed.append(script_path)
	for bad in failed:
		print("FAILED ", bad)
	print("DONE")
	quit(0)
