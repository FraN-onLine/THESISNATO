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

func _ready() -> void:
	custom_minimum_size = Vector2(1400, 760)
	_build_ui()
	if seed_demo_graph:
		_seed_task_graph()
	_refresh()

func _build_ui() -> void:
	var root := VBoxContainer.new()
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

	var mode_panel := VBoxContainer.new()
	mode_panel.custom_minimum_size = Vector2(240, 430)
	mode_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	mode_panel.add_theme_constant_override("separation", 8)
	workspace.add_child(mode_panel)
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
	connection_status = Label.new()
	connection_status.text = "Source: none\nTarget: none"
	mode_panel.add_child(connection_status)

	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 8)
	root.add_child(tools)
	var add_button := Button.new()
	add_button.text = "Add node"
	add_button.pressed.connect(_add_state)
	tools.add_child(add_button)
	var accept_button := Button.new()
	accept_button.text = "Toggle accepting"
	accept_button.pressed.connect(_toggle_accepting)
	tools.add_child(accept_button)
	var delete_button := Button.new()
	delete_button.text = "Delete selected"
	delete_button.pressed.connect(_delete_selected)
	tools.add_child(delete_button)
	for symbol in ["a", "b", "c", "u", "0", "1"]:
		var key := Button.new()
		key.text = symbol
		key.custom_minimum_size = Vector2(52, 42)
		key.pressed.connect(_set_symbol.bind(symbol))
		tools.add_child(key)

	var simulate := HBoxContainer.new()
	simulate.add_theme_constant_override("separation", 8)
	root.add_child(simulate)
	var label := Label.new()
	label.text = "Simulate:"
	simulate.add_child(label)
	input_line = LineEdit.new()
	input_line.placeholder_text = "any string"
	input_line.custom_minimum_size = Vector2(220, 42)
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
	for index in range(5):
		var state_name := "q%d" % index
		states[state_name] = {"position": Vector2(130 + index * 260, 190), "accepting": index == 4}
	for index in range(4):
		transitions.append({"from": "q%d" % index, "to": "q%d" % (index + 1), "symbol": ["a", "b", "u", "c"][index]})

func _refresh() -> void:
	if graph:
		graph.queue_redraw()
	status_label.text = "Selected: %s | Symbol: %s | Nodes: %d" % [selected_state, active_symbol, states.size()]
	if connection_status:
		connection_status.text = "Source: %s\nTarget: %s" % [connect_source if connect_source != "" else "none", selected_state]

func _add_mode_button(parent: VBoxContainer, label: String, mode: EditMode, selected := false) -> void:
	var button := Button.new()
	button.text = label
	button.toggle_mode = true
	button.button_group = mode_group
	button.button_pressed = selected
	button.custom_minimum_size = Vector2(220, 48)
	button.pressed.connect(_set_edit_mode.bind(mode))
	parent.add_child(button)

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
	var state_name := "q%d" % next_state_id
	next_state_id += 1
	states[state_name] = {"position": Vector2(180 + (states.size() % 4) * 260, 330), "accepting": false}
	selected_state = state_name
	_refresh()

func _toggle_accepting() -> void:
	if states.has(selected_state):
		states[selected_state]["accepting"] = not states[selected_state]["accepting"]
		_refresh()

func _delete_selected() -> void:
	if selected_state == "q0" or not states.has(selected_state):
		return
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
	if target == selected_state or not states.has(target):
		return
	for transition in transitions:
		if transition["from"] == selected_state and transition["symbol"] == active_symbol:
			transition["to"] = target
			_refresh()
			return
	transitions.append({"from": selected_state, "to": target, "symbol": active_symbol})
	_refresh()

func _simulate_input() -> void:
	var result := _simulate(input_line.text)
	status_label.text = "Simulation: %s" % ("ACCEPTED" if result else "REJECTED")

func _simulate(value: String) -> bool:
	var current := "q0"
	for character in value:
		var found := false
		for transition in transitions:
			if transition["from"] == current and transition["symbol"] == character:
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
	evaluated.emit(correct, message)

class GraphCanvas extends Control:
	var builder: Control
	var node_radius := 38.0

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
			var line_end := end - direction * node_radius
			draw_line(start + direction * node_radius, line_end, Color(0.35, 0.75, 1.0), 4.0)
			var side := Vector2(-direction.y, direction.x)
			var arrow := PackedVector2Array([line_end, line_end - direction * 18.0 + side * 9.0, line_end - direction * 18.0 - side * 9.0])
			draw_colored_polygon(arrow, Color(0.35, 0.75, 1.0))
			draw_string(ThemeDB.fallback_font, (start + end) * 0.5, transition["symbol"], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
		for state_name in builder.states:
			var state: Dictionary = builder.states[state_name]
			var state_position: Vector2 = state["position"]
			var color := Color(0.2, 0.75, 0.55) if state["accepting"] else Color(0.16, 0.3, 0.7)
			if state_name == builder.selected_state:
				draw_circle(state_position, node_radius + 6.0, Color(1.0, 0.8, 0.25))
			draw_circle(state_position, node_radius, color)
			if state["accepting"]:
				draw_arc(state_position, node_radius - 7.0, 0.0, TAU, 32, Color.WHITE, 3.0)
			draw_string(ThemeDB.fallback_font, state_position - Vector2(15, -8), state_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)

	func _gui_input(event: InputEvent) -> void:
		if builder == null:
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			for state_name in builder.states:
				if builder.states[state_name]["position"].distance_to(event.position) <= node_radius:
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
					elif builder.edit_mode == builder.EditMode.MOVE:
						builder.select_state(state_name)
						builder.dragging_state = state_name
						builder.drag_offset = builder.states[state_name]["position"] - event.position
					accept_event()
					return
		if event is InputEventMouseMotion and builder.edit_mode == builder.EditMode.MOVE and builder.dragging_state != "":
			builder.move_state(builder.dragging_state, event.position + builder.drag_offset)
			accept_event()
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			builder.dragging_state = ""
			accept_event()
