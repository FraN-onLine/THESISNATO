extends Control
## Reusable DFA builder challenge for the interactive lesson room.

signal evaluated(correct: bool, message: String)

enum EditMode { SELECT, CONNECT, MOVE }

@export_multiline var task_instruction: String = "Build a DFA that ACCEPTS abuc and REJECTS accc."
@export var accepted_test_string: String = "abuc"
@export var rejected_test_string: String = "accc"
@export var seed_demo_graph: bool = true
@export var show_back_to_lab: bool = false

var states: Dictionary = {}
var transitions: Array[Dictionary] = []
var selected_state: String = "q0"
var next_state_id: int = 5
var active_symbol: String = "a"
var dragging_state: String = ""
var drag_offset := Vector2.ZERO
var edit_mode: EditMode = EditMode.SELECT
var connect_source: String = ""
var graph: Control
var status_label: Label
var input_line: LineEdit
var mode_group: ButtonGroup
var connection_status: Label
var simulation_keyboard_active := false
var undo_stack: Array[Dictionary] = []
var last_transition_from := ""
var last_transition_to := ""

# --- Task progress / analytics (consumed by the knowledge-tracing algorithms) ---
var attempt_count := 0
var wrong_attempt_count := 0
var connection_edits := 0
var task_done := false
var task_started_msec := 0
var active_seconds := 0.0
var _last_time := 0
var last_attempt_stats: Dictionary = {
	"attempts": 0,
	"wrong_attempts": 0,
	"connections_made": 0,
	"time_seconds": 0.0,
	"correct": false,
	"message": "",
}

func _process(delta: float) -> void:
	# Walk the stopwatch only while the learner is actually working on a task.
	if not task_done and get_viewport() != null and is_visible_in_tree():
		active_seconds += delta

func _timer_start() -> void:
	task_started_msec = Time.get_ticks_msec()
	_last_time = task_started_msec
	active_seconds = 0.0

func _timer_stop() -> void:
	if task_started_msec > 0:
		active_seconds = float(Time.get_ticks_msec() - task_started_msec) / 1000.0

## Configure a brand-new challenge on the whiteboard. Wipes the previous graph,
## keeps only the required start state, and restarts the attempt/"speed" timer.
func reset_for_task(new_instruction: String, accepted: String, rejected: String) -> void:
	task_instruction = new_instruction
	accepted_test_string = accepted
	rejected_test_string = rejected
	states.clear()
	transitions.clear()
	next_state_id = 1
	selected_state = "q0"
	active_symbol = "a"
	states["q0"] = {"position": Vector2(360, 210), "accepting": false}
	attempt_count = 0
	wrong_attempt_count = 0
	connection_edits = 0
	undo_stack.clear()
	last_transition_from = ""
	last_transition_to = ""
	task_done = false
	last_attempt_stats = {
		"attempts": 0,
		"wrong_attempts": 0,
		"connections_made": 0,
		"time_seconds": 0.0,
		"correct": false,
		"message": "",
	}
	_timer_start()
	_apply_instruction_text()
	if input_line:
		input_line.text = ""
	_refresh()

func _apply_instruction_text() -> void:
	# Push the (possibly new) instruction into the on-screen heading label.
	var heading := get_node_or_null("VBoxContainer/InstructionLabel") as Label
	if heading:
		heading.text = task_instruction + "\nConnect mode: click the source node first, then the destination node. The arrow points from the first click to the second."

## Snapshot of the attempt analytics for the host lesson / algorithms.
func get_attempt_stats() -> Dictionary:
	return last_attempt_stats.duplicate()

func _record_attempt(correct: bool, message: String) -> void:
	attempt_count += 1
	if not correct:
		wrong_attempt_count += 1
	last_attempt_stats = {
		"attempts": attempt_count,
		"wrong_attempts": wrong_attempt_count,
		"connections_made": connection_edits,
		"time_seconds": active_seconds,
		"correct": correct,
		"message": message,
	}

func cancel_pointer_interaction() -> void:
	dragging_state = ""
	connect_source = ""
	_refresh()

func _ready() -> void:
	custom_minimum_size = Vector2(1400, 760)
	_build_ui()
	_seed_task_graph()
	_refresh()
	_timer_start()

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.name = "VBoxContainer"
	root.add_theme_constant_override("separation", 12)
	add_child(root)
	var heading := Label.new()
	heading.text = "AUTOMATA WORKSHOP"
	heading.add_theme_font_size_override("font_size", 30)
	root.add_child(heading)
	if show_back_to_lab:
		var back_button := Button.new()
		back_button.text = "Back to Lab"
		back_button.custom_minimum_size = Vector2(180, 42)
		back_button.pressed.connect(func(): get_tree().change_scene_to_file("res://World/World.tscn"))
		root.add_child(back_button)
	var instruction := Label.new()
	instruction.name = "InstructionLabel"
	instruction.text = task_instruction + "\nConnect mode: click the source node first, then the destination node. The arrow points from the first click to the second."
	instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instruction.add_theme_font_size_override("font_size", 18)
	root.add_child(instruction)

	var workspace := HBoxContainer.new()
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_theme_constant_override("separation", 16)
	root.add_child(workspace)
	var graph_panel := PanelContainer.new()
	graph_panel.custom_minimum_size = Vector2(1080, 430)
	graph_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.add_child(graph_panel)
	graph = GraphCanvas.new()
	graph.custom_minimum_size = Vector2(1080, 430)
	graph.set_builder(self)
	graph_panel.add_child(graph)

	var mode_frame := PanelContainer.new()
	mode_frame.custom_minimum_size = Vector2(260, 430)
	mode_frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	mode_frame.add_theme_stylebox_override("panel", _create_panel_style())
	workspace.add_child(mode_frame)
	var mode_panel := VBoxContainer.new()
	mode_panel.add_theme_constant_override("separation", 8)
	mode_frame.add_child(mode_panel)
	var mode_title := Label.new()
	mode_title.text = "EDIT MODE"
	mode_title.add_theme_font_size_override("font_size", 22)
	mode_panel.add_child(mode_title)
	var mode_help := Label.new()
	mode_help.text = "Select a node\nConnect: source -> destination\nMove nodes by dragging"
	mode_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mode_panel.add_child(mode_help)
	mode_group = ButtonGroup.new()
	_add_mode_button(mode_panel, "Select", EditMode.SELECT, true)
	_add_mode_button(mode_panel, "Connect", EditMode.CONNECT)
	_add_mode_button(mode_panel, "Move", EditMode.MOVE)
	var node_actions := Label.new()
	node_actions.text = "NODE TOOLS"
	node_actions.add_theme_font_size_override("font_size", 16)
	mode_panel.add_child(node_actions)
	_add_action_button(mode_panel, "Add node", _add_state)
	_add_action_button(mode_panel, "Toggle accepting", _toggle_accepting)
	_add_action_button(mode_panel, "Delete selected", _delete_selected)
	_add_action_button(mode_panel, "Undo transition", _undo_transition)
	_add_action_button(mode_panel, "Remove active symbol", _remove_active_transition)
	connection_status = Label.new()
	connection_status.text = "Source: none\nTarget: none"
	mode_panel.add_child(connection_status)

	var keyboard_panel := VBoxContainer.new()
	keyboard_panel.add_theme_constant_override("separation", 4)
	keyboard_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	root.add_child(keyboard_panel)
	var keyboard_title := Label.new()
	keyboard_title.text = "TRANSITION KEYBOARD  |  ACTIVE SYMBOL: %s" % active_symbol
	keyboard_title.name = "KeyboardTitle"
	keyboard_title.add_theme_font_size_override("font_size", 18)
	keyboard_panel.add_child(keyboard_title)
	var keyboard := GridContainer.new()
	keyboard.columns = 13
	keyboard.add_theme_constant_override("h_separation", 3)
	keyboard.add_theme_constant_override("v_separation", 3)
	keyboard_panel.add_child(keyboard)
	for symbol in ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]:
		var key := _make_keyboard_key(symbol)
		key.pressed.connect(_on_virtual_key.bind(symbol))
		keyboard.add_child(key)
	var clear_key := _make_keyboard_key("Clear")
	clear_key.custom_minimum_size = Vector2(90, 36)
	clear_key.pressed.connect(_on_virtual_clear)
	keyboard.add_child(clear_key)
	var delete_key := _make_keyboard_key("del")
	delete_key.custom_minimum_size = Vector2(70, 36)
	delete_key.pressed.connect(_on_virtual_delete)
	keyboard.add_child(delete_key)
	var space_key := _make_keyboard_key("space")
	space_key.custom_minimum_size = Vector2(90, 36)
	space_key.pressed.connect(_on_virtual_space)
	keyboard.add_child(space_key)

	var simulate := HBoxContainer.new()
	simulate.add_theme_constant_override("separation", 8)
	root.add_child(simulate)
	var label := Label.new()
	label.text = "Simulate:"
	simulate.add_child(label)
	input_line = LineEdit.new()
	input_line.placeholder_text = "any string"
	input_line.custom_minimum_size = Vector2(220, 42)
	input_line.focus_entered.connect(func(): simulation_keyboard_active = true)
	simulate.add_child(input_line)
	var simulate_button := Button.new()
	simulate_button.text = "Simulate"
	simulate_button.pressed.connect(_simulate_input)
	simulate.add_child(simulate_button)
	var check_button := Button.new()
	check_button.text = "Check task"
	check_button.pressed.connect(_check_task)
	simulate.add_child(check_button)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 18)
	root.add_child(status_label)

func _seed_task_graph() -> void:
	# Every workshop starts with only the required initial state. Learners build
	# the remaining graph themselves with Add node and Connect mode.
	next_state_id = 1
	transitions.clear()
	states["q0"] = {"position": Vector2(360, 210), "accepting": false}

func _refresh() -> void:
	if graph:
		graph.queue_redraw()
	status_label.text = "Selected: %s | Symbol: %s | Nodes: %d" % [selected_state, active_symbol, states.size()]
	var keyboard_title := get_node_or_null("VBoxContainer/KeyboardTitle")
	if keyboard_title:
		keyboard_title.text = "TRANSITION KEYBOARD  |  ACTIVE SYMBOL: %s" % active_symbol
	if connection_status:
		connection_status.text = "Source: %s\nTarget: %s" % [connect_source if connect_source != "" else "none", selected_state]

func _add_mode_button(parent: VBoxContainer, label: String, mode: EditMode, selected := false) -> void:
	var button := Button.new()
	button.text = label
	button.toggle_mode = true
	button.button_group = mode_group
	button.button_pressed = selected
	button.custom_minimum_size = Vector2(220, 56)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_stylebox_override("normal", _create_button_style(Color(0.12, 0.2, 0.38, 1)))
	button.add_theme_stylebox_override("hover", _create_button_style(Color(0.2, 0.4, 0.7, 1)))
	button.add_theme_stylebox_override("pressed", _create_button_style(Color(0.12, 0.55, 0.48, 1)))
	button.add_theme_color_override("font_color", Color(0.95, 0.98, 1, 1))
	button.pressed.connect(_set_edit_mode.bind(mode))
	parent.add_child(button)

func _add_action_button(parent: VBoxContainer, label: String, action: Callable) -> void:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(220, 48)
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_stylebox_override("normal", _create_button_style(Color(0.16, 0.28, 0.5, 1)))
	button.add_theme_stylebox_override("hover", _create_button_style(Color(0.25, 0.45, 0.75, 1)))
	button.add_theme_stylebox_override("pressed", _create_button_style(Color(0.12, 0.5, 0.42, 1)))
	button.pressed.connect(action)
	parent.add_child(button)

func _make_keyboard_key(symbol: String) -> Button:
	var button := Button.new()
	button.text = symbol
	button.custom_minimum_size = Vector2(48, 32)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_stylebox_override("normal", _create_button_style(Color(0.1, 0.16, 0.3, 1)))
	button.add_theme_stylebox_override("hover", _create_button_style(Color(0.25, 0.42, 0.72, 1)))
	button.add_theme_stylebox_override("pressed", _create_button_style(Color(0.1, 0.55, 0.45, 1)))
	return button

func _clear_symbol() -> void:
	active_symbol = ""
	_refresh()

func _on_virtual_key(symbol: String) -> void:
	if input_line and (input_line.has_focus() or simulation_keyboard_active):
		input_line.text += symbol
	else:
		_set_symbol(symbol)

func _on_virtual_clear() -> void:
	if input_line and (input_line.has_focus() or simulation_keyboard_active):
		input_line.text = ""
	else:
		_clear_symbol()

func _on_virtual_delete() -> void:
	if input_line and (input_line.has_focus() or simulation_keyboard_active) and not input_line.text.is_empty():
		input_line.text = input_line.text.substr(0, input_line.text.length() - 1)

func _on_virtual_space() -> void:
	if input_line and (input_line.has_focus() or simulation_keyboard_active):
		input_line.text += " "

func _create_button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(8)
	style.content_margin_left = 10.0
	style.content_margin_top = 5.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 5.0
	return style

func _create_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.16, 0.96)
	style.border_color = Color(0.25, 0.55, 0.75, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 14.0
	style.content_margin_top = 14.0
	style.content_margin_right = 14.0
	style.content_margin_bottom = 14.0
	return style

func _set_edit_mode(mode: EditMode) -> void:
	edit_mode = mode
	dragging_state = ""
	connect_source = ""
	_refresh()

func _set_symbol(symbol: String) -> void:
	active_symbol = symbol
	if graph:
		graph.queue_redraw()
	_refresh()

func _add_state() -> void:
	_save_undo_state()
	var state_name := "q%d" % next_state_id
	next_state_id += 1
	states[state_name] = {"position": Vector2(180 + (states.size() % 4) * 260, 330), "accepting": false}
	selected_state = state_name
	_refresh()

func _toggle_accepting() -> void:
	if states.has(selected_state):
		_save_undo_state()
		states[selected_state]["accepting"] = not states[selected_state]["accepting"]
		_refresh()

func _delete_selected() -> void:
	if selected_state == "q0" or not states.has(selected_state):
		return
	_save_undo_state()
	states.erase(selected_state)
	for index in range(transitions.size() - 1, -1, -1):
		if transitions[index]["from"] == selected_state or transitions[index]["to"] == selected_state:
			transitions.remove_at(index)
	selected_state = "q0"
	_refresh()

func select_state(state_name: String) -> void:
	if states.has(state_name):
		selected_state = state_name
		_refresh()

func move_state(state_name: String, state_position: Vector2) -> void:
	if states.has(state_name):
		states[state_name]["position"] = state_position
		_refresh()

func connect_selected(target: String) -> void:
	if target == selected_state or not states.has(target) or active_symbol.is_empty():
		return
	_save_undo_state()
	for transition in transitions:
		if transition["from"] == selected_state and transition["to"] == target:
			if active_symbol not in transition["symbols"]:
				transition["symbols"].append(active_symbol)
				connection_edits += 1
			last_transition_from = selected_state
			last_transition_to = target
			_refresh()
			return
	connection_edits += 1
	transitions.append({"from": selected_state, "to": target, "symbols": [active_symbol]})
	last_transition_from = selected_state
	last_transition_to = target
	_refresh()

func _save_undo_state() -> void:
	undo_stack.append({"states": states.duplicate(true), "transitions": transitions.duplicate(true), "connection_edits": connection_edits})
	if undo_stack.size() > 30:
		undo_stack.pop_front()

func _undo_transition() -> void:
	if undo_stack.is_empty():
		return
	var snapshot: Dictionary = undo_stack.pop_back()
	states = snapshot["states"]
	transitions = snapshot["transitions"]
	connection_edits = snapshot["connection_edits"]
	_refresh()

func _remove_active_transition() -> void:
	if last_transition_from.is_empty() or active_symbol.is_empty():
		return
	for index in range(transitions.size() - 1, -1, -1):
		var transition: Dictionary = transitions[index]
		if transition["from"] == last_transition_from and transition["to"] == last_transition_to and active_symbol in transition["symbols"]:
			_save_undo_state()
			transition["symbols"].erase(active_symbol)
			if transition["symbols"].is_empty():
				transitions.remove_at(index)
			_refresh()
			return

func _append_string(symbol: String) -> void:
	if input_line:
		input_line.text += symbol
		input_line.call_deferred("grab_focus")

func _string_backspace() -> void:
	if input_line and input_line.text.length() > 0:
		input_line.text = input_line.text.substr(0, input_line.text.length() - 1)

func _string_clear() -> void:
	if input_line:
		input_line.text = ""

func _simulate_input() -> void:
	var result := _simulate(input_line.text)
	status_label.text = "Simulation: %s" % ("ACCEPTED" if result else "REJECTED")

func _simulate(value: String) -> bool:
	var current := "q0"
	for character in value:
		var found := false
		for transition in transitions:
			var symbols: Array = transition.get("symbols", [transition.get("symbol", "")])
			if transition["from"] == current and character in symbols:
				current = transition["to"]
				found = true
				break
		if not found:
			return false
	return states.get(current, {}).get("accepting", false)

func _check_task() -> void:
	var accepted := _simulate(accepted_test_string)
	var rejected := not _simulate(rejected_test_string)
	var correct := accepted and rejected
	var message := "Task passed: %s is accepted and %s is rejected." % [accepted_test_string, rejected_test_string] if correct else "Keep building: %s must be accepted and %s must be rejected." % [accepted_test_string, rejected_test_string]
	status_label.text = message
	if correct:
		task_done = true
		_timer_stop()
	_record_attempt(correct, message)
	evaluated.emit(correct, message)

class GraphCanvas extends Control:
	var builder: Control
	var node_radius := 46.0
	var hit_radius := 96.0

	func set_builder(value: Control) -> void:
		builder = value
		mouse_default_cursor_shape = Control.CURSOR_CROSS

	func _draw() -> void:
		if builder == null:
			return
		for transition in builder.transitions:
			if not builder.states.has(transition["from"]) or not builder.states.has(transition["to"]):
				continue
			var start: Vector2 = builder.states[transition["from"]]["position"]
			var end: Vector2 = builder.states[transition["to"]]["position"]
			var direction := (end - start).normalized()
			var edge_offset := _edge_offset(builder, transition)
			var edge_start := start + edge_offset
			var edge_end := end + edge_offset
			var line_end := edge_end - direction * node_radius
			draw_line(edge_start + direction * node_radius, line_end, Color(0.35, 0.75, 1.0), 4.0)
			var side := Vector2(-direction.y, direction.x)
			var arrow := PackedVector2Array([line_end, line_end - direction * 18.0 + side * 9.0, line_end - direction * 18.0 - side * 9.0])
			draw_colored_polygon(arrow, Color(0.35, 0.75, 1.0))
			var symbols: Array = transition.get("symbols", [transition.get("symbol", "")])
			draw_string(ThemeDB.fallback_font, (edge_start + edge_end) * 0.5 + side * 10.0, ",".join(symbols), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
		for state_name in builder.states:
			var state: Dictionary = builder.states[state_name]
			var state_position: Vector2 = state["position"]
			var color := Color(0.2, 0.75, 0.55) if state["accepting"] else Color(0.16, 0.3, 0.7)
			if state_name == builder.selected_state or state_name == builder.connect_source:
				draw_circle(state_position, hit_radius, Color(1.0, 0.8, 0.25, 0.18))
			if state_name == builder.selected_state:
				draw_circle(state_position, node_radius + 7.0, Color(1.0, 0.8, 0.25))
			draw_circle(state_position, node_radius, color)
			if state["accepting"]:
				draw_arc(state_position, node_radius - 7.0, 0.0, TAU, 32, Color.WHITE, 3.0)
			draw_string(ThemeDB.fallback_font, state_position - Vector2(15, -8), state_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)

	func _edge_offset(model: Control, transition: Dictionary) -> Vector2:
		for other in model.transitions:
			if other["from"] == transition["to"] and other["to"] == transition["from"]:
				var start: Vector2 = model.states[transition["from"]]["position"]
				var end: Vector2 = model.states[transition["to"]]["position"]
				var direction := (end - start).normalized()
				var side := Vector2(-direction.y, direction.x)
				return side * (18.0 if transition["from"] < transition["to"] else -18.0)
		return Vector2.ZERO

	func _gui_input(event: InputEvent) -> void:
		if builder == null:
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			for state_name in builder.states:
				if builder.states[state_name]["position"].distance_to(event.position) <= hit_radius:
					if builder.edit_mode == builder.EditMode.CONNECT:
						if builder.connect_source == "":
							builder.connect_source = state_name
							builder.select_state(state_name)
						else:
							builder.select_state(builder.connect_source)
							builder.connect_selected(state_name)
							builder.connect_source = ""
					elif builder.edit_mode == builder.EditMode.SELECT:
						builder.select_state(state_name)
						builder.dragging_state = state_name
						builder.drag_offset = builder.states[state_name]["position"] - event.position
					elif builder.edit_mode == builder.EditMode.MOVE:
						builder.select_state(state_name)
						builder.dragging_state = state_name
						builder.drag_offset = builder.states[state_name]["position"] - event.position
					accept_event()
					return
		if event is InputEventMouseMotion and builder.dragging_state != "":
			builder.move_state(builder.dragging_state, event.position + builder.drag_offset)
			accept_event()
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			builder.dragging_state = ""
			accept_event()
