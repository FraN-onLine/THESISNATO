extends Control
## Renders ONE checkpoint as a roomy card that works with a mouse cursor and
## with a wobbly VR laser pointer: every tappable control is at least 52 px tall
## and options wrap their text instead of clipping.
##
## The card is presentation only - grading lives in Testing/Lessons/checkpoint.gd
## and the flow in lesson_engine.gd. Kinds it renders directly:
##   mc / identify : option buttons, one tap answers
##   trace         : a text field for the state the run stops in
##   build         : the task text + the string lists the whiteboard will test,
##                   with a reminder to press "Check task" on the board
##   maze          : the objective, while maze_panel.gd hosts the walkable board
##
## Signals
##   responded(response)   the UI answer, ready to hand to engine.submit()
##   reveal_requested      the learner asked for the answer (engine.reveal())

signal responded(response)
signal reveal_requested

const Checkpoint = preload("res://Testing/Lessons/checkpoint.gd")

const MIN_TAP_PX := 52.0
const OPTION_LETTERS := ["A", "B", "C", "D", "E", "F"]

var checkpoint: Dictionary = {}
var _locked := false

var _card: PanelContainer
var _kind_chip: Label
var _prompt_label: Label
var _image_rect: TextureRect
var _points_label: Label
var _options_box: VBoxContainer
var _answer_row: HBoxContainer
var _answer_input: LineEdit
var _submit_button: Button
var _hint_button: Button
var _reveal_button: Button
var _footer: HBoxContainer
var _feedback_label: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build()

# ===== Layout ==============================================================

func _build() -> void:
	_card = PanelContainer.new()
	_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card.add_theme_stylebox_override("panel", _panel_style(Color(0.07, 0.09, 0.18, 0.97), 18))
	add_child(_card)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_card.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(header)

	_kind_chip = Label.new()
	_kind_chip.text = "CHECKPOINT"
	_kind_chip.add_theme_font_size_override("font_size", 18)
	_kind_chip.add_theme_color_override("font_color", Color(0.06, 0.09, 0.18, 1))
	_kind_chip.add_theme_stylebox_override("normal", _panel_style(Color(0.55, 0.83, 1.0, 1), 10))
	_kind_chip.custom_minimum_size = Vector2(200, 34)
	_kind_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_kind_chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_kind_chip)

	_hint_button = _make_button("Hint", Color(0.24, 0.32, 0.58))
	_hint_button.pressed.connect(_on_hint)
	header.add_child(_hint_button)

	_reveal_button = _make_button("Reveal answer", Color(0.36, 0.24, 0.30))
	_reveal_button.pressed.connect(func(): reveal_requested.emit())
	header.add_child(_reveal_button)

	_prompt_label = Label.new()
	_prompt_label.add_theme_font_size_override("font_size", 26)
	_prompt_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt_label.custom_minimum_size = Vector2(0, 60)
	column.add_child(_prompt_label)

	_image_rect = TextureRect.new()
	_image_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_image_rect.custom_minimum_size = Vector2(0, 260)
	_image_rect.visible = false
	column.add_child(_image_rect)

	_points_label = Label.new()
	_points_label.add_theme_font_size_override("font_size", 20)
	_points_label.add_theme_color_override("font_color", Color(0.82, 0.88, 1.0, 1))
	_points_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_points_label.visible = false
	column.add_child(_points_label)

	_options_box = VBoxContainer.new()
	_options_box.add_theme_constant_override("separation", 10)
	column.add_child(_options_box)

	_answer_row = HBoxContainer.new()
	_answer_row.add_theme_constant_override("separation", 10)
	_answer_row.visible = false
	column.add_child(_answer_row)

	_answer_input = LineEdit.new()
	_answer_input.placeholder_text = "Type the state the run stops in, e.g. q2"
	_answer_input.custom_minimum_size = Vector2(420, MIN_TAP_PX)
	_answer_input.add_theme_font_size_override("font_size", 22)
	_answer_input.add_theme_stylebox_override("normal", _panel_style(Color(0.11, 0.12, 0.24, 1), 10))
	_answer_input.text_submitted.connect(func(_text): _on_submit_answer())
	_answer_row.add_child(_answer_input)

	_submit_button = _make_button("Submit", Color(0.16, 0.42, 0.32))
	_submit_button.pressed.connect(_on_submit_answer)
	_answer_row.add_child(_submit_button)

	_footer = HBoxContainer.new()
	_footer.add_theme_constant_override("separation", 10)
	column.add_child(_footer)

	_feedback_label = Label.new()
	_feedback_label.add_theme_font_size_override("font_size", 21)
	_feedback_label.add_theme_color_override("font_color", Color(0.75, 0.9, 0.8, 1))
	_feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback_label.custom_minimum_size = Vector2(0, 56)
	column.add_child(_feedback_label)

# ===== Presentation ========================================================

## Show (or refresh) a checkpoint. Safe to call repeatedly: the answer controls
## are rebuilt every time, so a remedy panel followed by the same checkpoint
## always starts from a clean slate.
func show_checkpoint(source: Dictionary) -> void:
	checkpoint = Checkpoint.normalize(source)
	_locked = false
	_feedback_label.text = ""
	_answer_input.text = ""
	_clear_options()
	var kind := Checkpoint.kind_of(checkpoint)
	_kind_chip.text = "CHECKPOINT - %s" % _kind_name(kind)
	_prompt_label.text = Checkpoint.prompt_of(checkpoint)
	var image_path := str(checkpoint.get("image", ""))
	_image_rect.visible = image_path != "" and ResourceLoader.exists(image_path)
	if _image_rect.visible:
		_image_rect.texture = load(image_path)
	_hint_button.visible = Checkpoint.hint_of(checkpoint) != ""
	_reveal_button.visible = true
	_points_label.visible = true
	match kind:
		Checkpoint.KIND_MC, Checkpoint.KIND_IDENTIFY:
			_options_box.visible = true
			_answer_row.visible = false
			_points_label.visible = false
			_build_options(Checkpoint.options_of(checkpoint))
		Checkpoint.KIND_TRACE:
			_options_box.visible = false
			_answer_row.visible = true
			_points_label.text = "States: %s   Start: %s   F = %s   |   string to trace: %s" % [
				", ".join(_string_list(checkpoint.get("spec", {}).get("states", []))),
				str(checkpoint.get("spec", {}).get("start", "?")),
				", ".join(_string_list(checkpoint.get("spec", {}).get("accepting", []))),
				str(checkpoint.get("input", "")),
			]
			_answer_input.grab_focus()
		Checkpoint.KIND_MAZE:
			_options_box.visible = false
			_answer_row.visible = false
			_points_label.text = "Walk the maze on the board: reach the exit room with a string the machine ACCEPTS."
		Checkpoint.KIND_BUILD:
			_options_box.visible = false
			_answer_row.visible = false
			var task: Dictionary = checkpoint.get("task", {})
			_points_label.text = "%s\nMust be ACCEPTED: %s\nMust be REJECTED: %s\n\nBuild it on the whiteboard, then press \"Check task\" there." % [
				str(task.get("instruction", "Build the machine on the board.")),
				", ".join(_string_list(task.get("accept", []))),
				", ".join(_string_list(task.get("reject", []))),
			]
		_:
			_options_box.visible = false
			_answer_row.visible = false
			_points_label.text = ""

## Paint the graded result returned by the engine.
func set_feedback(result: Dictionary) -> void:
	if result.is_empty():
		return
	var correct := bool(result.get("correct", false))
	_feedback_label.add_theme_color_override("font_color",
		Color(0.55, 0.95, 0.65, 1) if correct else Color(1, 0.72, 0.55, 1))
	_feedback_label.text = str(result.get("message", ""))
	if correct and not str(result.get("explain", "")).is_empty():
		_feedback_label.text += "\n%s" % str(result["explain"])
	if int(result.get("xp", 0)) > 0:
		_feedback_label.text += "\n+%d XP" % int(result["xp"])
	if bool(result.get("first_try", false)):
		_feedback_label.text += "   (first-try bonus)"
	if not correct and int(result.get("misses", 0)) > 0:
		_feedback_label.text += "\nTry again - the Hint button is free."

func lock() -> void:
	_locked = true
	for child in _options_box.get_children():
		if child is Button:
			child.disabled = true
	if _answer_input != null:
		_answer_input.editable = false
	if _submit_button != null:
		_submit_button.disabled = true

func _on_hint() -> void:
	var hint := Checkpoint.hint_of(checkpoint)
	if hint != "":
		_feedback_label.add_theme_color_override("font_color", Color(1, 0.9, 0.6, 1))
		_feedback_label.text = "HINT: %s" % hint

func _build_options(options: Array) -> void:
	for index in options.size():
		var letter: String = OPTION_LETTERS[index] if index < OPTION_LETTERS.size() else str(index + 1)
		var button := _make_button("%s.  %s" % [letter, str(options[index])], Color(0.13, 0.16, 0.32))
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_option_chosen.bind(index))
		_options_box.add_child(button)

func _on_option_chosen(index: int) -> void:
	if _locked:
		return
	_locked = true
	var buttons := _options_box.get_children()
	for child_index in buttons.size():
		var button: Button = buttons[child_index]
		if child_index == index:
			button.add_theme_stylebox_override("normal", _panel_style(Color(0.2, 0.45, 0.9, 1), 10))
		else:
			button.disabled = true
	responded.emit(index)

func _on_submit_answer() -> void:
	if _locked:
		return
	var answer := _answer_input.text.strip_edges()
	if answer == "":
		_feedback_label.text = "Type the state first, for example q2."
		return
	_locked = true
	responded.emit(answer)

func _clear_options() -> void:
	for child in _options_box.get_children():
		_options_box.remove_child(child)
		child.queue_free()

func _kind_name(kind: String) -> String:
	match kind:
		Checkpoint.KIND_MC, Checkpoint.KIND_IDENTIFY:
			return "MULTIPLE CHOICE"
		Checkpoint.KIND_TRACE:
			return "TRACE THE STRING"
		Checkpoint.KIND_MAZE:
			return "MAZE RUN"
		Checkpoint.KIND_BUILD:
			return "BUILD ON THE BOARD"
	return kind.to_upper()

func _string_list(values: Array) -> Array:
	var out: Array = []
	for value in values:
		out.append(str(value) if str(value) != "" else "(empty string)")
	return out

func _make_button(text: String, color: Color) -> Button:
	var button := Button.new()
	button.text = text
	# Tappable with mouse AND VR laser: keep the full 52px height even before
	# layout runs (DevTests measure size right after show_checkpoint).
	button.custom_minimum_size = Vector2(200, MIN_TAP_PX)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 21)
	button.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	button.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	button.add_theme_stylebox_override("normal", _panel_style(color, 10))
	button.add_theme_stylebox_override("hover", _panel_style(color.lightened(0.18), 10))
	button.add_theme_stylebox_override("pressed", _panel_style(color.darkened(0.2), 10))
	button.add_theme_stylebox_override("disabled", _panel_style(Color(0.12, 0.13, 0.2, 0.7), 10))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return button

func _panel_style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


