extends Control
## Walkable maze rendering of a DFA checkpoint.
##
## Rooms are states, doors are transitions, and the exit room is an accepting
## state - so walking the maze IS simulating the machine. The panel never grades
## on its own: it hands {escaped, path, final} to lesson_engine.gd, which scores
## the walk with dfa_model.trace exactly like a typed answer.
##
## Every door is a real Button at least 52 px tall, so a mouse cursor and a VR
## laser pointer are equally usable.

signal responded(response: Dictionary)
signal walk_changed(path: String, state: String)

const DfaModel = preload("res://Testing/Lessons/dfa_model.gd")

const MIN_TAP_PX := 52.0

var spec: Dictionary = {}
var required_escapes := 1
var escapes_done := 0
var current_state := ""
var walk := ""
var finished_run := false

var _objective_label: Label
var _status_label: Label
var _rooms_grid: GridContainer
var _walk_label: Label
var _reset_button: Button
var _undo_button: Button
var _submit_button: Button

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build()

func _build() -> void:
	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.add_theme_stylebox_override("panel", _panel_style(Color(0.05, 0.08, 0.15, 0.98), 18))
	add_child(card)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	card.add_child(column)

	_objective_label = Label.new()
	_objective_label.add_theme_font_size_override("font_size", 24)
	_objective_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_objective_label)

	_walk_label = Label.new()
	_walk_label.add_theme_font_size_override("font_size", 22)
	_walk_label.add_theme_color_override("font_color", Color(0.6, 0.88, 1, 1))
	column.add_child(_walk_label)

	_rooms_grid = GridContainer.new()
	_rooms_grid.columns = 3
	_rooms_grid.add_theme_constant_override("h_separation", 10)
	_rooms_grid.add_theme_constant_override("v_separation", 10)
	_rooms_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_rooms_grid)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	column.add_child(footer)

	_reset_button = _make_button("Reset walk", Color(0.22, 0.26, 0.44))
	_reset_button.pressed.connect(reset_walk)
	footer.add_child(_reset_button)

	_undo_button = _make_button("Undo step", Color(0.22, 0.26, 0.44))
	_undo_button.pressed.connect(undo_step)
	footer.add_child(_undo_button)

	_submit_button = _make_button("Submit run", Color(0.16, 0.42, 0.32))
	_submit_button.pressed.connect(_on_submit)
	footer.add_child(_submit_button)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 20)
	_status_label.add_theme_color_override("font_color", Color(0.85, 0.9, 1, 1))
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(0, 52)
	column.add_child(_status_label)

# ===== Public API ==========================================================

## Load a maze checkpoint. `objective` overrides the checkpoint prompt when set.
func show_maze(maze_spec: Dictionary, objective: String, escapes: int) -> void:
	spec = maze_spec.duplicate(true)
	required_escapes = maxi(escapes, 1)
	escapes_done = 0
	_objective_label.text = "MAZE RUN  -  %s" % objective
	_fit_columns()
	reset_walk()

## Paint the graded result from the engine.
func set_feedback(result: Dictionary) -> void:
	if result.is_empty():
		return
	var correct := bool(result.get("correct", false))
	_status_label.add_theme_color_override("font_color",
		Color(0.55, 0.95, 0.65, 1) if correct else Color(1, 0.75, 0.6, 1))
	_status_label.text = str(result.get("message", ""))
	if correct and escapes_done < required_escapes:
		_status_label.text += "\nEscape again to finish this checkpoint (%d / %d)." % [escapes_done, required_escapes]

func reset_walk() -> void:
	current_state = DfaModel.start_of(spec)
	walk = ""
	finished_run = false
	_rebuild_rooms()
	_refresh_status()
	walk_changed.emit(walk, current_state)

func undo_step() -> void:
	if walk.is_empty():
		return
	walk = walk.substr(0, walk.length() - 1)
	var traced := DfaModel.trace(spec, walk)
	current_state = str(traced.get("final", DfaModel.start_of(spec)))
	finished_run = false
	_rebuild_rooms()
	_refresh_status()
	walk_changed.emit(walk, current_state)

func is_escaped() -> bool:
	var traced := DfaModel.trace(spec, walk)
	return bool(traced.get("accepted", false)) and escapes_done >= required_escapes

# ===== Rendering ===========================================================

func _fit_columns() -> void:
	var count := DfaModel.states_of(spec).size()
	_rooms_grid.columns = 3 if count > 2 else maxi(count, 1)

func _rebuild_rooms() -> void:
	for child in _rooms_grid.get_children():
		_rooms_grid.remove_child(child)
		child.queue_free()
	var alphabet := DfaModel.alphabet_of(spec)
	for state in DfaModel.states_of(spec):
		_rooms_grid.add_child(_room_card(str(state), alphabet))

func _room_card(state: String, alphabet: Array) -> PanelContainer:
	var here := state == current_state
	var is_exit := DfaModel.is_accepting(spec, state)
	var colour := Color(0.12, 0.15, 0.3, 1)
	if is_exit:
		colour = Color(0.1, 0.28, 0.2, 1)
	if here:
		colour = colour.lightened(0.25)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _panel_style(colour, 14))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	card.add_child(column)

	var title := Label.new()
	var tags: Array[String] = []
	if state == DfaModel.start_of(spec):
		tags.append("START")
	if is_exit:
		tags.append("EXIT")
	if here:
		tags.append("YOU ARE HERE")
	title.text = "%s   %s" % [state, " ".join(tags)]
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 1) if here else Color(0.85, 0.88, 1, 1))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(title)

	for symbol in alphabet:
		var target := DfaModel.delta(spec, state, str(symbol))
		var label := ""
		if target == "":
			label = "no door for '%s' (dead end)" % str(symbol)
		else:
			label = "walk '%s'  ->  %s" % [str(symbol), target]
		var button := _make_button(label, Color(0.2, 0.32, 0.62) if here else Color(0.14, 0.16, 0.26))
		button.disabled = not here or target == ""
		if here and target != "":
			button.pressed.connect(_walk_through.bind(str(symbol)))
		column.add_child(button)

	if not here:
		var hint := Label.new()
		hint.text = "(walk back to this room to use its doors)"
		hint.add_theme_font_size_override("font_size", 16)
		hint.add_theme_color_override("font_color", Color(0.6, 0.63, 0.78, 1))
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(hint)
	return card

func _refresh_status() -> void:
	var shown := walk if walk != "" else "(empty string)"
	_walk_label.text = "String collected so far: %s     |     current room: %s     |     exits reached: %d / %d" % [
		shown, current_state, escapes_done, required_escapes]
	var traced := DfaModel.trace(spec, walk)
	if bool(traced.get("ok", false)):
		if bool(traced.get("accepted", false)):
			_status_label.add_theme_color_override("font_color", Color(0.6, 0.95, 0.7, 1))
			_status_label.text = "The exit room accepts '%s'. Press Submit run to lock it in." % shown
		else:
			_status_label.add_theme_color_override("font_color", Color(0.9, 0.9, 1, 1))
			_status_label.text = "Not accepted yet: the run stops in %s, which is not an exit." % str(traced.get("final", "?"))
	else:
		_status_label.text = "This machine cannot be walked: %s" % str(traced.get("error", ""))

func _walk_through(symbol: String) -> void:
	if finished_run:
		return
	walk += symbol
	var traced := DfaModel.trace(spec, walk)
	current_state = str(traced.get("final", current_state))
	_rebuild_rooms()
	_refresh_status()
	walk_changed.emit(walk, current_state)

func _on_submit() -> void:
	var traced := DfaModel.trace(spec, walk)
	var accepted := bool(traced.get("accepted", false))
	if accepted:
		escapes_done += 1
	finished_run = true
	var escaped := accepted and escapes_done >= required_escapes
	responded.emit({
		"escaped": escaped,
		"path": walk,
		"final": str(traced.get("final", "")),
		"escapes_done": escapes_done,
	})
	if accepted and not escaped:
		reset_walk()

# ===== Small helpers =======================================================

func _make_button(text: String, color: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, MIN_TAP_PX)
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	button.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	button.add_theme_stylebox_override("normal", _panel_style(color, 10))
	button.add_theme_stylebox_override("hover", _panel_style(color.lightened(0.18), 10))
	button.add_theme_stylebox_override("pressed", _panel_style(color.darkened(0.25), 10))
	button.add_theme_stylebox_override("disabled", _panel_style(Color(0.1, 0.11, 0.18, 0.75), 10))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return button

func _panel_style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style

