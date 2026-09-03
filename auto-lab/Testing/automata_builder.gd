extends Control
## Reusable DFA builder challenge for the interactive lesson room.

signal evaluated(correct: bool, message: String)

enum EditMode { SELECT, CONNECT, MOVE }

## Visual radius of every state circle (shared by the builder and canvas).
const NODE_RADIUS := 46.0

@export_multiline var task_instruction: String = "Build a DFA that ACCEPTS abuc and REJECTS accc."
@export var accepted_test_string: String = "abuc"
@export var rejected_test_string: String = "accc"
## Flexible task validation: the built DFA is correct if it accepts EVERY string
## in accept_strings and rejects EVERY string in reject_strings. This lets a task
## such as "01* is true" accept ANY automaton recognising that language, not just
## one specific construction.
var accept_strings: Array = []
var reject_strings: Array = []
@export var seed_demo_graph: bool = true
@export var show_back_to_lab: bool = false

var states: Dictionary = {}
var transitions: Array[Dictionary] = []
var selected_state: String = "q0"
## The single initial state. Learners can switch it with "Set as Start"; there
## is always exactly one start state, and simulation always begins there.
var start_state: String = "q0"
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
var mode_buttons: Dictionary = {}
var connection_status: Label
var simulate_button: Button
var sim_keyboard_title: Label
var simulation_keyboard_active := false

# --- Step-by-step simulation animation state ---
var simulation_running := false
var sim_input := ""
var sim_pos := 0
var sim_current := ""
var sim_active_transition := {}
var sim_finished := false
var sim_accepted := false
var sim_message := ""
var sim_timer := 0.0
var sim_flash := 0.0
var sim_step_duration := 1.0
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
	# Drive the step-by-step simulation: one transition every second.
	if simulation_running:
		sim_timer += delta
		if sim_timer >= sim_step_duration:
			sim_timer = 0.0
			_advance_simulation()
	# Decay the accept/reject board flash.
	if sim_flash > 0.0:
		sim_flash = maxf(0.0, sim_flash - delta * 0.9)
		if graph:
			graph.queue_redraw()
	if (simulation_running or sim_finished) and graph:
		graph.queue_redraw()

func _timer_start() -> void:
	task_started_msec = Time.get_ticks_msec()
	_last_time = task_started_msec
	active_seconds = 0.0

func _timer_stop() -> void:
	if task_started_msec > 0:
		active_seconds = float(Time.get_ticks_msec() - task_started_msec) / 1000.0

## Configure a brand-new challenge on the whiteboard. Wipes the previous graph,
## keeps only the required start state, and restarts the attempt/"speed" timer.
## Accepted / rejected are single convenience strings; use reset_for_task_lists()
## when full language coverage is desired.
func reset_for_task(new_instruction: String, accepted: String, rejected: String) -> void:
	task_instruction = new_instruction
	accepted_test_string = accepted
	rejected_test_string = rejected
	accept_strings = [accepted]
	reject_strings = [rejected]
	_wipe_graph()
	_timer_start()
	_apply_instruction_text()
	if input_line:
		input_line.text = ""
	_refresh()

## Same as reset_for_task() but with list-based validation: the built DFA passes
## if it accepts EVERY string in `accepted` and rejects EVERY string in
## `rejected`.  So "make any automata for 01*" accepts ANY correct construction.
func reset_for_task_lists(new_instruction: String, accepted: Array, rejected: Array) -> void:
	task_instruction = new_instruction
	accept_strings = accepted.duplicate()
	reject_strings = rejected.duplicate()
	accepted_test_string = accepted[0] if not accepted.is_empty() else ""
	rejected_test_string = rejected[0] if not rejected.is_empty() else ""
	_wipe_graph()
	_timer_start()
	_apply_instruction_text()
	if input_line:
		input_line.text = ""
	_refresh()

func _wipe_graph() -> void:
	states.clear()
	transitions.clear()
	next_state_id = 1
	selected_state = "q0"
	start_state = "q0"
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

func _apply_instruction_text() -> void:
	# Push the (possibly new) instruction into the on-screen heading label.
	var heading := get_node_or_null("VBoxContainer/InstructionLabel") as Label
	if heading:
		heading.text = task_instruction + "\nDrag a node to move it — nodes space themselves apart so they never overlap. Pick a symbol, then click source -> target to draw arrows. Use \"Set as Start\" to choose the single start state. Incoming and outgoing arrows between two nodes are drawn in separate lanes."

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
	instruction.text = task_instruction + "\nDrag nodes to move them. Pick a symbol, then click source -> target to draw arrows. \"Set as Start\" fixes the one start state; in/out arrows between a pair use separate lanes."
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
	mode_frame.custom_minimum_size = Vector2(280, 430)
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
	mode_help.text = "Select / Move: click or drag nodes\nConnect: pick a symbol, then source -> target\n\"Set as Start\" picks the one start state"
	mode_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mode_panel.add_child(mode_help)
	mode_group = ButtonGroup.new()
	mode_group.allow_unpress = true
	_add_mode_button(mode_panel, "Select", EditMode.SELECT, true)
	_add_mode_button(mode_panel, "Connect", EditMode.CONNECT)
	_add_mode_button(mode_panel, "Move", EditMode.MOVE)
	var node_actions := Label.new()
	node_actions.text = "NODE TOOLS"
	node_actions.add_theme_font_size_override("font_size", 16)
	mode_panel.add_child(node_actions)
	_add_action_button(mode_panel, "Add node", _add_state)
	_add_action_button(mode_panel, "Toggle accepting", _toggle_accepting)
	_add_action_button(mode_panel, "Set as Start", _make_start_selected)
	_add_action_button(mode_panel, "Delete selected", _delete_selected)
	_add_action_button(mode_panel, "Undo transition", _undo_transition)
	_add_action_button(mode_panel, "Remove active symbol", _remove_active_transition)

	var keyboard_panel := VBoxContainer.new()
	keyboard_panel.add_theme_constant_override("separation", 4)
	keyboard_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	root.add_child(keyboard_panel)
	var keyboard_title := Label.new()
	keyboard_title.text = "SYMBOL KEYS | ACTIVE SYMBOL: %s" % active_symbol
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
	clear_key.custom_minimum_size = Vector2(110, 48)
	clear_key.pressed.connect(_on_virtual_clear)
	keyboard.add_child(clear_key)
	var delete_key := _make_keyboard_key("del")
	delete_key.custom_minimum_size = Vector2(90, 48)
	delete_key.pressed.connect(_on_virtual_delete)
	keyboard.add_child(delete_key)
	var space_key := _make_keyboard_key("space")
	space_key.custom_minimum_size = Vector2(110, 48)
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
	input_line.custom_minimum_size = Vector2(280, 48)
	input_line.focus_entered.connect(func(): simulation_keyboard_active = true)
	input_line.focus_exited.connect(func(): simulation_keyboard_active = false)
	simulate.add_child(input_line)
	simulate_button = Button.new()
	simulate_button.text = "Simulate"
	simulate_button.custom_minimum_size = Vector2(180, 48)
	simulate_button.add_theme_font_size_override("font_size", 18)
	simulate_button.add_theme_stylebox_override("normal", _create_button_style(Color(0.16, 0.28, 0.5, 1)))
	simulate_button.add_theme_stylebox_override("hover", _create_button_style(Color(0.25, 0.45, 0.75, 1)))
	simulate_button.add_theme_stylebox_override("pressed", _create_button_style(Color(0.12, 0.5, 0.42, 1)))
	simulate_button.pressed.connect(_simulate_input)
	simulate.add_child(simulate_button)
	var check_button := Button.new()
	check_button.text = "Check task"
	check_button.custom_minimum_size = Vector2(200, 48)
	check_button.add_theme_font_size_override("font_size", 18)
	check_button.add_theme_stylebox_override("normal", _create_button_style(Color(0.16, 0.28, 0.5, 1)))
	check_button.add_theme_stylebox_override("hover", _create_button_style(Color(0.25, 0.45, 0.75, 1)))
	check_button.add_theme_stylebox_override("pressed", _create_button_style(Color(0.12, 0.5, 0.42, 1)))
	check_button.pressed.connect(_check_task)
	simulate.add_child(check_button)

	# On-screen keyboard for typing test strings (PC and VR alike).
	var sim_kb_row := VBoxContainer.new()
	sim_kb_row.add_theme_constant_override("separation", 4)
	sim_keyboard_title = Label.new()
	sim_keyboard_title.name = "SimKeyboardTitle"
	sim_keyboard_title.add_theme_font_size_override("font_size", 16)
	sim_kb_row.add_child(sim_keyboard_title)
	var sim_grid := GridContainer.new()
	sim_grid.columns = 13
	sim_grid.add_theme_constant_override("h_separation", 3)
	sim_grid.add_theme_constant_override("v_separation", 3)
	for symbol in ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]:
		var key := _make_keyboard_key(symbol)
		key.pressed.connect(_on_simulation_key.bind(symbol))
		sim_grid.add_child(key)
	var sim_space := _make_keyboard_key("space")
	sim_space.custom_minimum_size = Vector2(160, 44)
	sim_space.pressed.connect(_on_simulation_space)
	sim_grid.add_child(sim_space)
	var sim_del := _make_keyboard_key("del")
	sim_del.custom_minimum_size = Vector2(70, 44)
	sim_del.pressed.connect(_on_simulation_backspace)
	sim_grid.add_child(sim_del)
	var sim_clear := _make_keyboard_key("Clear")
	sim_clear.custom_minimum_size = Vector2(110, 44)
	sim_clear.pressed.connect(_on_simulation_clear)
	sim_grid.add_child(sim_clear)
	sim_kb_row.add_child(sim_grid)
	root.add_child(sim_kb_row)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 18)
	root.add_child(status_label)

func _seed_task_graph() -> void:
	# Every workshop starts with only the required initial state. Learners build
	# the remaining graph themselves with Add node and Connect mode.
	next_state_id = 1
	transitions.clear()
	selected_state = "q0"
	start_state = "q0"
	states["q0"] = {"position": Vector2(360, 210), "accepting": false}
	accept_strings = [accepted_test_string]
	reject_strings = [rejected_test_string]

## Seeds a small reference DFA (accepts strings ending in 'a') so the demonstration
## step can show learners what a complete, correct machine looks like.
func seed_reference_graph() -> void:
	states.clear()
	transitions.clear()
	next_state_id = 2
	selected_state = "q0"
	start_state = "q0"
	active_symbol = "a"
	states["q0"] = {"position": Vector2(300, 220), "accepting": false}
	states["q1"] = {"position": Vector2(560, 220), "accepting": true}
	transitions = [
		{"from": "q0", "to": "q0", "symbols": ["b"]},
		{"from": "q0", "to": "q1", "symbols": ["a"]},
		{"from": "q1", "to": "q0", "symbols": ["b"]},
		{"from": "q1", "to": "q1", "symbols": ["a"]},
	]
	_apply_instruction_text()
	_refresh()

func _refresh() -> void:
	if graph:
		graph.queue_redraw()
	if status_label:
		if simulation_running and not sim_finished:
			status_label.text = "Step %d/%d — at %s | remaining: '%s'" % [sim_pos, sim_input.length(), sim_current, sim_input.substr(sim_pos)]
		else:
			status_label.text = "Start: %s | Selected: %s | Symbol: %s | Nodes: %d" % [start_state, selected_state, active_symbol, states.size()]
	if sim_keyboard_title:
		sim_keyboard_title.text = "SIMULATION KEYBOARD | INPUT: '%s'" % (input_line.text if input_line else "")
	var keyboard_title := get_node_or_null("VBoxContainer/KeyboardTitle")
	if keyboard_title:
		keyboard_title.text = "SYMBOL KEYS | ACTIVE SYMBOL: %s" % active_symbol
	if connection_status:
		if edit_mode == EditMode.CONNECT:
			connection_status.text = "Source: %s\nTarget: %s" % [connect_source if connect_source != "" else "none", selected_state if selected_state != connect_source else "click target"]
		else:
			connection_status.text = "Selected: %s\nStart: %s" % [selected_state, start_state]

func _add_mode_button(parent: VBoxContainer, label: String, mode: EditMode, selected := false) -> void:
	var button := Button.new()
	button.text = label
	button.toggle_mode = true
	button.button_group = mode_group
	button.custom_minimum_size = Vector2(240, 44)
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_stylebox_override("normal", _create_button_style(Color(0.12, 0.2, 0.38, 1)))
	button.add_theme_stylebox_override("hover", _create_button_style(Color(0.2, 0.4, 0.7, 1)))
	button.add_theme_stylebox_override("pressed", _create_button_style(Color(0.12, 0.55, 0.48, 1)))
	button.add_theme_color_override("font_color", Color(0.95, 0.98, 1, 1))
	# Connect "toggled" (not "pressed") AFTER the initial state is set, so the
	# initial button_pressed doesn't re-fire the handler during construction.
	button.button_pressed = selected
	button.toggled.connect(_on_mode_toggled.bind(mode))
	mode_buttons[mode] = button
	parent.add_child(button)

func _on_mode_toggled(toggled_on: bool, mode: EditMode) -> void:
	if toggled_on:
		_set_edit_mode(mode)
	else:
		# allow_unpress lets a cursor/controller click on the active mode switch
		# it OFF; fall back to Select so a usable interaction mode always exists.
		_set_edit_mode(EditMode.SELECT)
		var select_button: Button = mode_buttons.get(EditMode.SELECT)
		if select_button:
			select_button.button_pressed = true

func _add_action_button(parent: VBoxContainer, label: String, action: Callable) -> void:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(240, 36)
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_stylebox_override("normal", _create_button_style(Color(0.16, 0.28, 0.5, 1)))
	button.add_theme_stylebox_override("hover", _create_button_style(Color(0.25, 0.45, 0.75, 1)))
	button.add_theme_stylebox_override("pressed", _create_button_style(Color(0.12, 0.5, 0.42, 1)))
	button.pressed.connect(action)
	parent.add_child(button)

func _make_keyboard_key(symbol: String) -> Button:
	var button := Button.new()
	button.text = symbol
	button.custom_minimum_size = Vector2(52, 44)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 18)
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
	if graph:
		graph._update_cursor()
	_refresh()

func _set_symbol(symbol: String) -> void:
	_cancel_simulation()
	active_symbol = symbol
	if graph:
		graph.queue_redraw()
	_refresh()

func _add_state() -> void:
	_cancel_simulation()
	_save_undo_state()
	var state_name := "q%d" % next_state_id
	next_state_id += 1
	var base := Vector2(400, 215)
	if states.has(selected_state):
		base = states[selected_state]["position"] + Vector2(230, 40)
	states[state_name] = {"position": _find_free_position(base), "accepting": false}
	selected_state = state_name
	_refresh()

## Picks a spot near `base` with at least one node-width of clearance from
## every existing node, so freshly added nodes never overlap their neighbours.
func _find_free_position(base: Vector2) -> Vector2:
	var min_separation: float = (NODE_RADIUS * 2.0 + 30.0) if graph else 130.0
	for radius_step in [1.0, 1.6, 2.2]:
		for angle_index in 8:
			var candidate: Vector2 = base + Vector2.from_angle(TAU * float(angle_index) / 8.0) * (230.0 * float(radius_step))
			var free := true
			for other_name in states:
				if states[other_name]["position"].distance_to(candidate) < min_separation:
					free = false
					break
			if free:
				return candidate
	return base + Vector2(230.0, 0.0)

func _toggle_accepting() -> void:
	_cancel_simulation()
	if states.has(selected_state):
		_save_undo_state()
		states[selected_state]["accepting"] = not states[selected_state]["accepting"]
		_refresh()

## Makes the currently selected node the ONE start state, replacing any other.
func _make_start_selected() -> void:
	_cancel_simulation()
	if not states.has(selected_state):
		return
	if selected_state == start_state:
		status_label.text = "%s is already the start state (only one start allowed)." % selected_state
		_refresh()
		return
	_save_undo_state()
	start_state = selected_state
	status_label.text = "Start state set to %s — previous start removed." % selected_state
	_refresh()

func _delete_selected() -> void:
	_cancel_simulation()
	if not states.has(selected_state):
		return
	if selected_state == start_state:
		status_label.text = "Switch the start state first — the single start state cannot be deleted."
		return
	_save_undo_state()
	states.erase(selected_state)
	for index in range(transitions.size() - 1, -1, -1):
		if transitions[index]["from"] == selected_state or transitions[index]["to"] == selected_state:
			transitions.remove_at(index)
	selected_state = start_state
	_refresh()

func select_state(state_name: String) -> void:
	if states.has(state_name):
		selected_state = state_name
		# Interacting with the graph means the Simulate field is idle again —
		# stop capturing typed keys so they don't sneak into the text box.
		simulation_keyboard_active = false
		if input_line and input_line.has_focus():
			input_line.release_focus()
		_refresh()

func move_state(state_name: String, state_position: Vector2) -> void:
	_cancel_simulation()
	if not states.has(state_name):
		return
	var position := state_position
	var bounds := graph.size if graph else Vector2(1080, 430)
	# Keep the node inside the canvas.
	position.x = clampf(position.x, 56.0, bounds.x - 56.0)
	position.y = clampf(position.y, 56.0, bounds.y - 56.0)
	# Push apart from every other node so the circles can never overlap.
	var min_separation: float = (NODE_RADIUS * 2.0 + 24.0) if graph else 118.0
	for _pass in 4:
		var pushed := false
		for other_name in states:
			if other_name == state_name:
				continue
			var other_pos: Vector2 = states[other_name]["position"]
			var delta := position - other_pos
			var distance := delta.length()
			if distance > 0.001 and distance < min_separation:
				position = other_pos + delta / distance * min_separation
				pushed = true
		if not pushed:
			break
	position.x = clampf(position.x, 56.0, bounds.x - 56.0)
	position.y = clampf(position.y, 56.0, bounds.y - 56.0)
	states[state_name]["position"] = position
	_refresh()

func connect_selected(target: String) -> void:
	if target == selected_state or not states.has(target):
		return
	if active_symbol.is_empty():
		_refresh()
		status_label.text = "Pick a transition symbol first (e.g. 'a', 'b', '0', '1' ...) and try again."
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
	undo_stack.append({"states": states.duplicate(true), "transitions": transitions.duplicate(true), "start_state": start_state, "connection_edits": connection_edits})
	if undo_stack.size() > 30:
		undo_stack.pop_front()

func _undo_transition() -> void:
	_cancel_simulation()
	if undo_stack.is_empty():
		return
	var snapshot: Dictionary = undo_stack.pop_back()
	states = snapshot["states"]
	transitions = snapshot["transitions"]
	start_state = snapshot.get("start_state", "q0")
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
	if simulation_running:
		_cancel_simulation()
		return
	var value := input_line.text if input_line else ""
	if value.is_empty():
		status_label.text = "Type a string in the box (or use the simulation keyboard), then press Simulate."
		return
	start_simulation(value)

## Kicks off the step-by-step animated simulation: every second one symbol is
## consumed, the active transition and current node are highlighted and, at the
## end, the board flashes green (accepted) or red (rejected).
func start_simulation(value: String) -> void:
	sim_input = value
	sim_pos = 0
	sim_current = start_state if states.has(start_state) else (states.keys()[0] if not states.is_empty() else "")
	sim_active_transition = {}
	sim_finished = false
	sim_accepted = false
	sim_message = ""
	sim_timer = 0.0
	sim_flash = 0.0
	if sim_current == "":
		status_label.text = "No nodes to simulate."
		return
	simulation_running = true
	if simulate_button:
		simulate_button.text = "Stop"
	_refresh()

func _advance_simulation() -> void:
	if not simulation_running or sim_finished:
		return
	if sim_pos >= sim_input.length():
		var accepted: bool = states.get(sim_current, {}).get("accepting", false)
		_finish_simulation(accepted, "Input read — ended in %s (%s)" % [sim_current, "ACCEPTING" if accepted else "NOT accepting"])
		return
	var remaining := sim_input.substr(sim_pos)
	var best_len := -1
	var best_to := ""
	var best_symbol := ""
	for transition in transitions:
		if transition["from"] != sim_current:
			continue
		for symbol in transition.get("symbols", [transition.get("symbol", "")]):
			if symbol.is_empty():
				continue
			var sl: int = symbol.length()
			if sl > best_len and remaining.begins_with(symbol):
				best_len = sl
				best_to = transition["to"]
				best_symbol = symbol
	if best_len < 0:
		var shown := remaining.substr(0, 1)
		_finish_simulation(false, "No '%s' transition from %s — string rejected." % [shown, sim_current])
		return
	sim_active_transition = {"from": sim_current, "to": best_to, "symbol": best_symbol}
	sim_pos += best_len
	sim_current = best_to
	if sim_pos >= sim_input.length():
		var accepted: bool = states.get(best_to, {}).get("accepting", false)
		_finish_simulation(accepted, "Input read — ended in %s (%s)" % [best_to, "ACCEPTING" if accepted else "NOT accepting"])
		return
	_refresh()

func _finish_simulation(accepted: bool, reason: String) -> void:
	simulation_running = false
	sim_finished = true
	sim_accepted = accepted
	sim_message = reason
	sim_flash = 1.0
	if simulate_button:
		simulate_button.text = "Simulate"
	status_label.text = ("ACCEPTED — " if accepted else "REJECTED — ") + reason
	_refresh()

func _cancel_simulation() -> void:
	if not (simulation_running or sim_finished or sim_flash > 0.0):
		return
	simulation_running = false
	sim_finished = false
	sim_active_transition = {}
	sim_message = ""
	sim_flash = 0.0
	if simulate_button:
		simulate_button.text = "Simulate"
	_refresh()

func _on_simulation_key(symbol: String) -> void:
	if input_line == null:
		return
	input_line.grab_focus()
	input_line.text += symbol
	simulation_keyboard_active = true
	_refresh()

func _on_simulation_backspace() -> void:
	if input_line == null or input_line.text.is_empty():
		return
	input_line.text = input_line.text.substr(0, input_line.text.length() - 1)
	_refresh()

func _on_simulation_clear() -> void:
	if input_line == null:
		return
	input_line.text = ""
	_refresh()

func _on_simulation_space() -> void:
	if input_line == null:
		return
	input_line.grab_focus()
	input_line.text += " "
	simulation_keyboard_active = true
	_refresh()

func _simulate(value: String) -> bool:
	# Simulation starts at the single, changeable start state, so ANY correct
	# automaton the learner builds is evaluated properly — not a fixed "q0".
	var current := start_state
	if not states.has(current):
		var keys := states.keys()
		current = keys[0] if not keys.is_empty() else ""
		if current == "":
			return false
	var pos := 0
	while pos < value.length():
		# Longest-match: consume multi-character transition labels (e.g. "ab")
		# whole, while still handling ordinary single-symbol DFAs correctly.
		var best_length := -1
		var best_next := ""
		for transition in transitions:
			if transition["from"] != current:
				continue
			for symbol in transition.get("symbols", [transition.get("symbol", "")]):
				if symbol.is_empty():
					continue
				var symbol_len: int = symbol.length()
				if symbol_len > best_length and value.substr(pos, symbol_len) == symbol:
					best_length = symbol_len
					best_next = transition["to"]
		if best_length < 0:
			return false
		current = best_next
		pos += best_length
	return states.get(current, {}).get("accepting", false)

func _check_task() -> void:
	_cancel_simulation()
	var acc := accept_strings.duplicate()
	if acc.is_empty():
		acc = [accepted_test_string]
	var rej := reject_strings.duplicate()
	if rej.is_empty():
		rej = [rejected_test_string]
	var correct := true
	var failure := ""
	for s in acc:
		if not _simulate(s):
			correct = false
			failure = s
			break
	if correct:
		for s in rej:
			if _simulate(s):
				correct = false
				failure = s
				break
	var message := ""
	if correct:
		message = "Task passed! The DFA accepts ALL required strings (%d) and rejects ALL required strings (%d)." % [acc.size(), rej.size()]
	else:
		message = "Not yet. Your DFA mishandles \"%s\" — check its accepting states and transitions, then press Check task again." % failure
	status_label.text = message
	if correct:
		task_done = true
		_timer_stop()
	_record_attempt(correct, message)
	evaluated.emit(correct, message)

class GraphCanvas extends Control:
	## Light-blue line palette for arrows, self-loop arcs and arrowheads.
	const EDGE_COLOR := Color(0.35, 0.75, 1.0)
	const EDGE_WIDTH := 4.0
	const ARROW_LENGTH := 16.0
	const ARROW_HALF_WIDTH := 8.0
	## Lateral offset that puts "forward" arrows in one lane and their matching
	## "return" arrows in a second lane, so in/out arrows never overlap.
	const PAIR_LANE := 15.0
	## Extra lateral offset between parallel arrows travelling the same way.
	const PAIR_STEP := 16.0
	## Self-loop radius measured beyond the node edge.
	const LOOP_EXTRA := 46.0
	## Radial gap between stacked self-loops on the same node.
	const LOOP_STACK := 48.0
	const LABEL_FONT_SIZE := 22

	var builder: Control
	var node_radius := 46.0
	var hit_radius := 96.0
	var hovered_state := ""
	var preview_mouse := Vector2(-1e6, -1e6)

	func set_builder(value: Control) -> void:
		builder = value
		mouse_exited.connect(_on_mouse_exited)
		_update_cursor()

	func _on_mouse_exited() -> void:
		hovered_state = ""
		queue_redraw()

	func _update_cursor() -> void:
		mouse_default_cursor_shape = Control.CURSOR_CROSS if (builder != null and builder.edit_mode == builder.EditMode.CONNECT) else Control.CURSOR_POINTING_HAND

	func _draw() -> void:
		if builder == null:
			return
		_draw_simulation_overlay()
		_draw_transitions()
		_draw_connect_preview()
		_draw_states()

	## Full-board flash when a simulation finishes: green = accepted, red =
	## rejected. The overlay is drawn behind everything and fades out.
	func _draw_simulation_overlay() -> void:
		if builder.sim_flash <= 0.0:
			return
		var flash_color := Color(0.2, 0.9, 0.45, 0.25) if builder.sim_accepted else Color(0.95, 0.25, 0.25, 0.28)
		flash_color.a *= builder.sim_flash
		draw_rect(Rect2(Vector2.ZERO, size), flash_color)
		var banner := "ACCEPTED" if builder.sim_accepted else "REJECTED"
		var banner_color := Color(0.15, 0.7, 0.4, 1.0) if builder.sim_accepted else Color(0.95, 0.3, 0.3, 1.0)
		var font := ThemeDB.fallback_font
		var banner_font_size := 44
		var w := font.get_string_size(banner, HORIZONTAL_ALIGNMENT_CENTER, -1, banner_font_size)
		var center := Vector2(size.x * 0.5, size.y * 0.42)
		# Dark backing card so the banner always reads over the graph.
		draw_rect(Rect2(center.x - w.x * 0.5 - 24.0, center.y - 34.0, w.x + 48.0, 76.0), Color(0.02, 0.04, 0.08, 0.85))
		draw_string(font, center + Vector2(-w.x * 0.5, 0.0), banner, HORIZONTAL_ALIGNMENT_LEFT, -1, banner_font_size, banner_color)

	# --------------------------------------------------------- transitions
	func _draw_transitions() -> void:
		# Self loops first (behind everything else): they are drawn as arcs on
		# the "empty" side of their node, stacked outward when several loops
		# share one node.
		var drawn_loops := {}
		for transition in builder.transitions:
			if transition["from"] != transition["to"]:
				continue
			var node_name: String = transition["from"]
			var index: int = drawn_loops.get(node_name, 0)
			_draw_self_loop(transition, index)
			drawn_loops[node_name] = index + 1

		# Ordinary arrows. Each arrow between a pair of nodes is pushed off the
		# centre line: forward arrows live in one lane, return arrows in the
		# opposite lane and parallel arrows stack beside one another.
		var groups := _group_pair_edges()
		for key in groups:
			var group: Dictionary = groups[key]
			var forward: Array = group["forward"]
			var backward: Array = group["backward"]
			if backward.is_empty():
				var total := forward.size()
				for index in total:
					_draw_paired_edge(forward[index], group["A"], group["B"], (float(index) - (total - 1) / 2.0) * PAIR_STEP)
			else:
				for index in forward.size():
					_draw_paired_edge(forward[index], group["A"], group["B"], PAIR_LANE + index * PAIR_STEP)
				for index in backward.size():
					_draw_paired_edge(backward[index], group["B"], group["A"], PAIR_LANE + index * PAIR_STEP)

	## Groups every non-loop transition by the unordered pair of nodes it
	## connects, keeping the two travel directions in separate lists.
	func _group_pair_edges() -> Dictionary:
		var groups := {}
		for transition in builder.transitions:
			var from_node: String = transition["from"]
			var to_node: String = transition["to"]
			if from_node == to_node:
				continue
			var a := from_node if from_node < to_node else to_node
			var b := to_node if from_node < to_node else from_node
			var key: Array = [a, b]
			if not groups.has(key):
				groups[key] = {"A": a, "B": b, "forward": [], "backward": []}
			if from_node == a:
				groups[key]["forward"].append(transition)
			else:
				groups[key]["backward"].append(transition)
		return groups

	## Draws one arrow that leaves `from_node` and enters `to_node`, shifted
	## `lane` pixels to the side of the direct centre line so the forward and
	## return arrows between the same two nodes are visually separated.
	func _is_active_transition(transition: Dictionary) -> bool:
		var active: Dictionary = builder.sim_active_transition
		if active.is_empty():
			return false
		return transition.get("from", "") == active.get("from", "") and transition.get("to", "") == active.get("to", "")

	func _draw_paired_edge(transition: Dictionary, from_node: String, to_node: String, lane: float) -> void:
		var states: Dictionary = builder.states
		if not states.has(from_node) or not states.has(to_node):
			return
		var center_a: Vector2 = states[from_node]["position"]
		var center_b: Vector2 = states[to_node]["position"]
		var delta := center_b - center_a
		var length := delta.length()
		if length < 1.0:
			return
		var direction := delta / length
		var side := Vector2(-direction.y, direction.x)
		var offset := side * lane
		# Exact contact points where the shifted travel line meets each circle.
		var reach := sqrt(maxf(node_radius * node_radius - lane * lane, 0.0))
		var start := center_a + offset + direction * reach
		var tip := center_b + offset - direction * reach

		# During step-by-step simulation, the transition being consumed is
		# highlighted in a bright travelling-arrow color instead of the default.
		var active: bool = _is_active_transition(transition) and (builder.simulation_running or builder.sim_finished)
		var edge_color := Color(1.0, 0.85, 0.3, 1.0) if active else EDGE_COLOR
		var edge_width := EDGE_WIDTH + 3.0 if active else EDGE_WIDTH

		draw_line(start, tip, edge_color, edge_width)
		var arrow_base := tip - direction * ARROW_LENGTH
		var head := PackedVector2Array([tip, arrow_base + side * ARROW_HALF_WIDTH, arrow_base - side * ARROW_HALF_WIDTH])
		draw_colored_polygon(head, edge_color)
		# Animated dot travelling along the active edge.
		if active:
			var t := fmod(Time.get_ticks_msec() * 0.0005, 1.0)
			draw_circle(start.lerp(tip, t), 7.0, Color(1.0, 1.0, 0.7, 0.95))

		var symbols: Array = transition.get("symbols", [transition.get("symbol", "")])
		if not symbols.is_empty():
			var label_side := 15.0 if absf(lane) < 0.5 else (absf(lane) + 15.0) * signf(lane)
			_draw_label(", ".join(symbols), (start + tip) * 0.5 + side * label_side)

	## Self-loop drawn as an arc: it leaves the node, bulges outward and then
	## re-enters, with the arrowhead sitting at the re-entry point. Several
	## loops on one node stack outward at growing radii.
	func _draw_self_loop(transition: Dictionary, index: int) -> void:
		var states: Dictionary = builder.states
		var node_name: String = transition["from"]
		if not states.has(node_name):
			return
		var center: Vector2 = states[node_name]["position"]
		var loop_angle := _loop_angle_for(node_name)
		var sweep := 1.2
		var loop_radius := node_radius + LOOP_EXTRA + index * LOOP_STACK
		var p0 := center + Vector2.from_angle(loop_angle - sweep) * node_radius
		var p1 := center + Vector2.from_angle(loop_angle + sweep) * node_radius
		var control := center + Vector2.from_angle(loop_angle) * loop_radius

		var points := PackedVector2Array()
		for step in 25:
			points.append(_quad_bezier(p0, control, p1, float(step) / 24.0))
		var active: bool = _is_active_transition(transition) and (builder.simulation_running or builder.sim_finished)
		var edge_color := Color(1.0, 0.85, 0.3, 1.0) if active else EDGE_COLOR
		var edge_width := EDGE_WIDTH + 3.0 if active else EDGE_WIDTH
		draw_polyline(points, edge_color, edge_width, true)

		# Arrowhead on the re-entering end of the loop.
		var incoming := (p1 - control).normalized()
		var arrow_base := p1 - incoming * ARROW_LENGTH
		var arrow_side := Vector2(-incoming.y, incoming.x)
		var head := PackedVector2Array([p1, arrow_base + arrow_side * ARROW_HALF_WIDTH, arrow_base - arrow_side * ARROW_HALF_WIDTH])
		draw_colored_polygon(head, edge_color)
		# Animated dot travelling along the active loop.
		if active:
			var t := fmod(Time.get_ticks_msec() * 0.0005, 1.0)
			draw_circle(_quad_bezier(p0, control, p1, t), 7.0, Color(1.0, 1.0, 0.7, 0.95))

		var symbols: Array = transition.get("symbols", [transition.get("symbol", "")])
		if not symbols.is_empty():
			var mid := (p0 + 2.0 * control + p1) / 4.0
			var outward := (mid - center).normalized() if (mid - center).length() > 0.001 else Vector2.UP
			_draw_label(", ".join(symbols), mid + outward * (18.0 + index * LOOP_STACK))

	## Picks the side of the node that has no external arrows (the "empty"
	## side) for the self-loop arc, so the loop never crosses the in/out arrows.
	func _loop_angle_for(node_name: String) -> float:
		var states: Dictionary = builder.states
		var center: Vector2 = states[node_name]["position"]
		var direction_sum := Vector2.ZERO
		for transition in builder.transitions:
			var from_node: String = transition["from"]
			var to_node: String = transition["to"]
			if from_node == node_name and to_node == node_name:
				continue
			if from_node == node_name:
				direction_sum += (states[to_node]["position"] - center).normalized()
			elif to_node == node_name:
				direction_sum += (center - states[from_node]["position"]).normalized()
		if direction_sum.length() < 0.02:
			return -PI / 2.0  # default: arc over the top of the node
		return direction_sum.angle() + PI

	func _quad_bezier(p0: Vector2, control: Vector2, p1: Vector2, t: float) -> Vector2:
		var s := 1.0 - t
		return s * s * p0 + 2.0 * s * t * control + t * t * p1

	## Symbol label inside a small dark box, so labels on parallel lanes stay
	## readable instead of smudging together.
	func _draw_label(text_value: String, pos: Vector2) -> void:
		if text_value.is_empty():
			return
		var font := ThemeDB.fallback_font
		var text_size := font.get_string_size(text_value, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE)
		var box := Rect2(pos.x - text_size.x * 0.5 - 7.0, pos.y - 15.0, text_size.x + 14.0, 30.0)
		draw_rect(box, Color(0.02, 0.05, 0.1, 0.85))
		draw_rect(box, Color(0.3, 0.6, 0.9, 0.4), false, 1.5)
		draw_string(font, Vector2(pos.x - text_size.x * 0.5, pos.y + 11.0), text_value, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, Color.WHITE)

	# --------------------------------------------------------------- states
	func _draw_states() -> void:
		for state_name in builder.states:
			var state: Dictionary = builder.states[state_name]
			var state_position: Vector2 = state["position"]
			var color := Color(0.2, 0.75, 0.55) if state["accepting"] else Color(0.16, 0.3, 0.7)

			if state_name == builder.selected_state or state_name == builder.connect_source:
				draw_circle(state_position, hit_radius, Color(1.0, 0.8, 0.25, 0.15))
			if state_name == builder.selected_state:
				draw_circle(state_position, node_radius + 7.0, Color(1.0, 0.8, 0.25))
			elif state_name == hovered_state and state_name != builder.dragging_state:
				draw_circle(state_position, node_radius + 6.0, Color(1.0, 1.0, 1.0, 0.45))
			if builder.edit_mode == builder.EditMode.CONNECT and state_name == builder.connect_source:
				draw_arc(state_position, node_radius + 15.0, 0.0, TAU, 40, Color(1.0, 0.6, 0.2), 3.0)

			draw_circle(state_position, node_radius, color)
			draw_arc(state_position, node_radius, 0.0, TAU, 40, Color(0, 0, 0, 0.3), 2.0)
			if state["accepting"]:
				draw_arc(state_position, node_radius - 8.0, 0.0, TAU, 40, Color.WHITE, 3.0)
			# Step-by-step simulation highlight: the node being consumed right now
			# glows bright cyan + white, so the learner can follow the parse.
			if builder.simulation_running or builder.sim_finished:
				if state_name == builder.sim_current:
					var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
					draw_circle(state_position, node_radius + 12.0 + pulse * 5.0, Color(0.3, 0.95, 1.0, 0.4))
					draw_arc(state_position, node_radius + 10.0, 0.0, TAU, 48, Color(0.4, 1.0, 1.0, 0.9), 5.0)
			if builder.sim_finished and builder.sim_accepted and state_name == builder.sim_current:
				draw_arc(state_position, node_radius + 16.0, 0.0, TAU, 48, Color(0.4, 1.0, 0.5, 0.8), 3.0)

			# Centred state name just below the circle centre.
			var font := ThemeDB.fallback_font
			var name_size := font.get_string_size(state_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
			draw_string(font, state_position + Vector2(-name_size.x * 0.5, 24.0), state_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)

			# Mark the single start state with a small wedge + an "S" tag.
			if state_name == builder.start_state:
				var start_triangle := PackedVector2Array([
					state_position + Vector2(-node_radius - 16.0, -8.0),
					state_position + Vector2(-node_radius - 16.0, 8.0),
					state_position + Vector2(-node_radius, 0.0),
				])
				draw_colored_polygon(start_triangle, Color(0.65, 1.0, 0.75))
				draw_string(ThemeDB.fallback_font, state_position + Vector2(-node_radius - 34.0, -node_radius - 6.0), "S", HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0.7, 1.0, 0.8))

	## Live preview while connecting: a ghost arrow from the source node to the
	## cursor (or to the hovered target node) so the user sees exactly which
	## connection they are about to create.
	func _draw_connect_preview() -> void:
		if builder == null or builder.edit_mode != builder.EditMode.CONNECT:
			return
		if builder.connect_source.is_empty() or not builder.states.has(builder.connect_source):
			return
		var source_pos: Vector2 = builder.states[builder.connect_source]["position"]
		var target := preview_mouse
		if hovered_state != "" and builder.states.has(hovered_state):
			target = builder.states[hovered_state]["position"]
		var delta := target - source_pos
		if delta.length() < 2.0:
			return
		var direction := delta.normalized()
		var side := Vector2(-direction.y, direction.x)
		var start := source_pos + direction * (node_radius + 4.0)
		var line_end := target - direction * (node_radius + 4.0) if hovered_state != "" else target
		draw_line(start, line_end, Color(1.0, 0.85, 0.4, 0.55), 3.0)
		var arrow_base := line_end - direction * ARROW_LENGTH
		var head := PackedVector2Array([line_end, arrow_base + side * ARROW_HALF_WIDTH, arrow_base - side * ARROW_HALF_WIDTH])
		draw_colored_polygon(head, Color(1.0, 0.85, 0.4, 0.5))

	func _node_at(pos: Vector2) -> String:
		for state_name in builder.states:
			if builder.states[state_name]["position"].distance_to(pos) <= hit_radius:
				return state_name
		return ""

	func _gui_input(event: InputEvent) -> void:
		if builder == null:
			return
		if event is InputEventMouseMotion:
			preview_mouse = event.position
			var new_hover := _node_at(event.position)
			if new_hover != hovered_state:
				hovered_state = new_hover
				queue_redraw()
			if builder.edit_mode == builder.EditMode.CONNECT and builder.connect_source != "":
				queue_redraw()
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var hit := _node_at(event.position)
			if hit == "":
				# Empty-canvas click cancels a pending connection.
				if builder.edit_mode == builder.EditMode.CONNECT and builder.connect_source != "":
					builder.connect_source = ""
					builder._refresh()
					accept_event()
				return
			if builder.edit_mode == builder.EditMode.CONNECT:
				if builder.connect_source == "":
					builder.connect_source = hit
					builder.select_state(hit)
				elif builder.connect_source == hit:
					builder.connect_source = ""  # clicking the source again cancels
					builder._refresh()
				else:
					builder.select_state(builder.connect_source)
					builder.connect_selected(hit)
					builder.connect_source = ""
				accept_event()
			else:
				# Select AND Move in one gesture: click and drag a node to move it.
				builder.select_state(hit)
				builder.dragging_state = hit
				builder.drag_offset = builder.states[hit]["position"] - event.position
				accept_event()
		if event is InputEventMouseMotion and builder.dragging_state != "":
			builder.move_state(builder.dragging_state, event.position + builder.drag_offset)
			accept_event()
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			builder.dragging_state = ""
			accept_event()
