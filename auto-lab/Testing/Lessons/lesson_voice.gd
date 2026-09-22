extends RefCounted
## Narrator / voice-over hook for the lesson panels.
##
## WHY THIS EXISTS
## The lesson panel can talk to the learner (checkpoint announcements, feedback,
## levels). Nothing here is required for the lesson to work: the UI always shows
## CAPTIONS, this service only decides whether anything is spoken out loud.
##
## THREE WAYS TO GET A VOICE, in order of preference:
##   1. RECORDED CLIPS - drop files named after the line id into
##      res://Audio/Voice/<line_id>.ogg and call set_clip_root("res://Audio/Voice").
##      Nothing else has to change: the line ids are stable strings.
##   2. SYSTEM TTS - set enabled = true and system_tts = true (uses
##      DisplayServer.tts_*). Works with the OS voices, no assets needed.
##   3. SILENT - default. Everything is still logged in `spoken_lines`, so the
##      exact script of a recorded voice can be exported later.
##
## The panel connects to `captions_changed` and paints the subtitle, so the
## learner is never blocked by audio.

signal spoke(line_id: String, text: String, kind: String)
signal captions_changed(text: String, kind: String)

## Master switch: false = silent (captions only).
var enabled := false
## Use the operating system's text-to-speech voices when `enabled` is true.
var system_tts := false
var volume := 90          # 0..100
var pitch := 1.0
var rate := 1.0
var language := "en"
var voice_id := ""        # empty = let the OS pick a voice for `language`
var captions := true      # the panel shows the last line as a subtitle
var clip_root := ""       # e.g. "res://Audio/Voice"

var last_line_id := ""
var last_text := ""
var spoken_lines: Array[String] = []
var _player: AudioStreamPlayer = null
var _host: Node = null

const MAX_LOG := 60

func _init(host: Node = null) -> void:
	if host != null:
		attach(host)

## Give the service a node to hang an AudioStreamPlayer on. Without a host only
## captions / system TTS are available.
func attach(host: Node) -> void:
	_host = host
	if _player == null and host != null and host.is_inside_tree():
		_player = AudioStreamPlayer.new()
		_player.name = "LessonVoicePlayer"
		_player.bus = "Master"
		host.add_child(_player)

func is_available() -> bool:
	if not enabled:
		return false
	if _has_clip("") or _player != null:
		return true
	return _tts_available()

func _tts_available() -> bool:
	return DisplayServer.has_method("tts_speak") \
		and DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH)

## Speak one line. `line_id` is what a recorded clip would be named after; pass
## "" when the text itself is the payload (feedback sentences and the like).
func speak(text: String, kind := "narration", line_id := "") -> void:
	var clean := str(text).strip_edges()
	if clean == "":
		return
	last_text = clean
	last_line_id = line_id if line_id != "" else _slug(clean)
	spoken_lines.append("%s|%s" % [kind, clean])
	if spoken_lines.size() > MAX_LOG:
		spoken_lines.remove_at(0)
	spoke.emit(last_line_id, clean, kind)
	if captions:
		captions_changed.emit(clean, kind)
	if not enabled:
		return
	if _play_clip(last_line_id):
		return
	if system_tts and _tts_available():
		var voice := voice_id
		if voice == "":
			var voices := DisplayServer.tts_get_voices()
			for entry in voices:
				if str(entry.get("language", "")).begins_with(language):
					voice = str(entry.get("id", ""))
					break
		DisplayServer.tts_speak(clean, voice, volume, pitch, rate, 0, true)

func announce_checkpoint(number: int, total: int, prompt: String, checkpoint_id := "") -> void:
	speak("Checkpoint %d of %d. %s" % [number, total, prompt], "checkpoint", checkpoint_id)

func announce_reward(xp: int, streak: int, event := "") -> void:
	var parts: Array[String] = []
	if xp > 0:
		parts.append("plus %d experience" % xp)
	if streak >= 3:
		parts.append("streak %d" % streak)
	if event != "":
		parts.append(event)
	if parts.is_empty():
		return
	speak("Correct. %s." % ", ".join(parts), "reward")

func announce_level(level: int, title: String) -> void:
	speak("Level %d! You are now a %s." % [level, title], "level")

func stop() -> void:
	if _player != null and _player.playing:
		_player.stop()
	if _tts_available():
		DisplayServer.tts_stop()

## The script of everything spoken so far - useful to record a human voice later.
func get_script_log() -> Array[String]:
	return spoken_lines.duplicate()

func clear_log() -> void:
	spoken_lines.clear()

func _play_clip(line_id: String) -> bool:
	if _player == null or clip_root == "":
		return false
	var path := clip_path_for(line_id)
	if path == "" or not ResourceLoader.exists(path):
		return false
	var stream := load(path)
	if stream is AudioStream:
		_player.stream = stream
		_player.play()
		return true
	return false

## Absolute path of the recorded clip for a line, or "" when the root is unset.
func clip_path_for(line_id: String) -> String:
	if clip_root == "" or line_id == "":
		return ""
	return "%s/%s.ogg" % [clip_root.trim_suffix("/"), line_id]

func _has_clip(line_id: String) -> bool:
	var path := clip_path_for(line_id)
	return path != "" and ResourceLoader.exists(path)

## Stable, filesystem-safe id for a spoken line (used as the clip file name).
func _slug(text: String) -> String:
	var out := ""
	var previous_underscore := false
	for index in text.length():
		var character := text.substr(index, 1).to_lower()
		if character.to_upper() != character.to_lower():
			out += character
			previous_underscore = false
		elif character >= "0" and character <= "9":
			out += character
			previous_underscore = false
		elif not previous_underscore and out != "":
			out += "_"
			previous_underscore = true
	return out.strip_edges().trim_suffix("_").substr(0, 60)
