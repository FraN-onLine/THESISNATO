extends SceneTree
## Headless self-test for the Automata Workshop board.
## Run:
##   Godot_v4.7-stable_win64_console.exe --path <project> --headless --script res://Testing/_selftest_builder.gd
## It lays the board out at the real billboard size (1800x1100), then checks that
## every control is on screen / reachable and that add-node, connect and simulate
## behave. Prints REPORT lines and exits with code 0 (ok) or 1 (failures).

const BOARD_W := 1800.0
const BOARD_H := 1100.0
## Minimum side length a tappable control must have to stay comfortable with a
## mouse cursor AND a wobbly VR laser pointer.
const MIN_TAP_PX := 44.0

var _failures: Array[String] = []
var _builder: Control
var _frames := 0


func _initialize() -> void:
	var scene: PackedScene = load("res://Testing/AutomataWorkshop.tscn")
	_builder = scene.instantiate()
	root.add_child(_builder)
	_builder.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_builder.size = Vector2(BOARD_W, BOARD_H)
	print("REPORT scene_loaded=ok")


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 4:
		return false

	_builder.size = Vector2(BOARD_W, BOARD_H)
	if _frames < 10:
		return false

	_run_layout_checks()
	_run_behaviour_checks()
	_run_interaction_checks()
	_report()
	return true


func _note(ok: bool, label: String, detail: String) -> void:
	if ok:
		print("REPORT  PASS  %-34s %s" % [label, detail])
	else:
		print("REPORT  FAIL  %-34s %s" % [label, detail])
		_failures.append(label)


func _inside_board(rect: Rect2) -> bool:
	return rect.position.x >= -1.0 and rect.position.y >= -1.0 \
		and rect.end.x <= BOARD_W + 1.0 and rect.end.y <= BOARD_H + 1.0


## Converts a control's screen-space rect into BOARD-LOCAL coordinates. The
## headless SceneTree puts the board somewhere in the middle of the root
## viewport, so global_position alone would produce false "off-board" failures.
func _board_rect_of(node: Control) -> Rect2:
	var origin: Vector2 = _builder.global_position
	return Rect2(node.global_position - origin, node.size)


func _dump_tree() -> void:
	var queue: Array = [[_builder, 0]]
	while not queue.is_empty():
		var entry: Array = queue.pop_front()
		var node: Control = entry[0]
		var depth: int = entry[1]
		var rect := Rect2(node.global_position, node.size)
		var minsize := node.custom_minimum_size
		print("TREE %-46s vis=%-5s pos=%-16s size=%-14s min=%s" % [
			"  ".repeat(depth) + str(node.name), str(node.visible),
			str(rect.position.round()), str(rect.size.round()), str(minsize.round())])
		for child in node.get_children():
			if child is Control:
				queue.append([child, depth + 1])


func _run_layout_checks() -> void:
	var graph: Control = _builder.get("graph")
	_note(graph != null, "graph_exists", "graph=%s" % graph)
	if graph == null:
		return

	# 1. The canvas must have a real drawing area.
	_note(graph.size.x > 400.0 and graph.size.y > 200.0,
		"canvas_has_area", "canvas size=%s" % str(graph.size))

	# 2. Dump the whole Control tree so any row pushed off the board is visible.
	_dump_tree()

	# 2. Every key control must sit INSIDE the board rectangle (nothing cut off).
	var key_nodes := {
		"simulate_button": _builder.get("simulate_button"),
		"input_line": _builder.get("input_line"),
		"status_label": _builder.get("status_label"),
	}
	for label in key_nodes:
		var node: Control = key_nodes[label]
		if node == null:
			_note(false, "control_present:" + label, "missing")
			continue
		var rect := _board_rect_of(node)
		_note(_inside_board(rect), "control_on_screen:" + label,
			"pos=%s size=%s" % [str(rect.position.round()), str(rect.size)])

	# 3. Every button on the board must be a comfortably tappable size, because
	#    the same board is used with a mouse AND a VR laser pointer.
	var too_small: Array[String] = []
	for node in _collect_controls(_builder):
		if node is Button:
			var smallest: float = minf(node.size.x, node.size.y)
			if smallest < MIN_TAP_PX - 0.5:
				too_small.append("%s(%d)" % [str(node.name), int(smallest)])
	_note(too_small.is_empty(), "buttons_tappable_min_%dpx" % int(MIN_TAP_PX),
		"offenders=%s" % str(too_small))


func _collect_controls(node: Node) -> Array[Control]:
	var found: Array[Control] = []
	for child in node.get_children():
		if child is Control:
			found.append(child)
			found.append_array(_collect_controls(child))
	return found


## Resets the board and returns the two node names it now holds (the seeded start
## state plus one added node), so every behaviour check starts from a known graph.
func _fresh_pair() -> Array:
	_builder.call("reset_for_free_build")
	_builder.call("_add_state")
	var states: Dictionary = _builder.get("states")
	return states.keys()


func _count_nodes_outside_board() -> int:
	var graph: Control = _builder.get("graph")
	var board := Rect2(Vector2.ZERO, graph.size)
	var states: Dictionary = _builder.get("states")
	var outside := 0
	for state_name in states:
		var pos: Vector2 = states[state_name]["position"]
		if not board.has_point(pos):
			outside += 1
	return outside


## Interactive paths exercised the way a learner uses them: the real Add node
## button and real mouse taps on the canvas. These are the checks that catch the
## "a new state spawns half off the board" and "the tap lands outside the canvas"
## kinds of bug.
func _run_interaction_checks() -> void:
	var graph: Control = _builder.get("graph")
	if graph == null:
		_note(false, "interaction_graph", "graph missing")
		return

	# 1. The Add node button must create a state INSIDE the board rectangle.
	_builder.call("reset_for_free_build")
	var before: int = (_builder.get("states") as Dictionary).size()
	var add_button := _find_button("add node")
	if add_button != null:
		_click(add_button)
		var after: int = (_builder.get("states") as Dictionary).size()
		_note(after > before, "add_node_button_creates_state", "before=%d after=%d" % [before, after])
		_note(_count_nodes_outside_board() == 0, "add_node_button_inside_board",
			"outside=%d" % _count_nodes_outside_board())
	else:
		_note(false, "add_node_button_found", "no button labelled 'Add node'")

	# 2. Tapping the empty canvas must never place a state off the board.
	_tap_graph(graph, Vector2(graph.size.x * 0.5, graph.size.y * 0.4))
	_note(_count_nodes_outside_board() == 0, "canvas_tap_inside_board",
		"outside=%d" % _count_nodes_outside_board())

	# 3. A tap that misses the canvas must be ignored, not turned into an
	#    off-board node (this is what made nodes appear outside the board).
	var count_before: int = (_builder.get("states") as Dictionary).size()
	_tap_graph(graph, Vector2(-40, -40))
	var count_after: int = (_builder.get("states") as Dictionary).size()
	_note(count_after == count_before, "off_canvas_tap_ignored",
		"before=%d after=%d" % [count_before, count_after])


func _run_behaviour_checks() -> void:
	var graph: Control = _builder.get("graph")
	var board := Rect2(Vector2.ZERO, graph.size)

	# --- nodes are always created INSIDE the board ---------------------------
	_builder.call("reset_for_free_build")
	for i in 4:
		_builder.call("_add_state")
	var states: Dictionary = _builder.get("states")
	_note(_count_nodes_outside_board() == 0, "nodes_spawn_inside_board",
		"nodes=%d board=%s" % [states.size(), str(board.size)])

	# --- clicking 2 nodes in Connect mode must create a transition ----------
	var names := _fresh_pair()
	_builder.call("_set_symbol", "a")
	_builder.set("connect_source", names[0])
	_builder.call("select_state", names[0])
	_builder.call("connect_selected", names[1])
	var transitions: Array = _builder.get("transitions")
	_note(transitions.size() == 1, "connect_creates_transition",
		"transitions=%d from=%s to=%s" % [transitions.size(), names[0], names[1]])

	# --- simulator follows transitions and reports acceptance ---------------
	names = _fresh_pair()
	_builder.call("_set_symbol", "a")
	_builder.set("connect_source", names[0])
	_builder.call("select_state", names[0])
	_builder.call("connect_selected", names[1])
	_builder.call("select_state", names[1])
	_builder.call("_toggle_accepting")
	var accepted: bool = _builder.call("test_string", "a")
	var rejected: bool = _builder.call("test_string", "b")
	_note(accepted and not rejected, "simulate_follows_graph",
		"accept('a')=%s accept('b')=%s" % [str(accepted), str(rejected)])


## Finds a Button in the board whose label matches `needle`. With `exact` the
## whole label must match, which is how the mode row (Select / Connect / Move)
## is picked out from action buttons such as "Delete selected".
func _find_button(needle: String, exact := false) -> Button:
	for node in _collect_controls(_builder):
		if not node is Button:
			continue
		var label := str(node.text).strip_edges().to_lower()
		var wanted := needle.strip_edges().to_lower()
		if (exact and label == wanted) or (not exact and wanted in label):
			return node
	return null


## Presses a button the way a learner does. Toggle buttons also have their
## toggle state flipped, so both `pressed` and `toggled` handlers run.
func _click(button: Button) -> void:
	if button == null:
		return
	if button.toggle_mode:
		button.button_pressed = true
	button.emit_signal("pressed")


func _mouse_button(pressed: bool, at: Vector2, double_click := false) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	event.double_click = double_click
	return event


func _mouse_motion(at: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = at
	return event


## Press+release ON the graph canvas, exactly like a mouse click or a VR laser
## tap that lands on the board surface.
func _tap_graph(graph: Control, at: Vector2) -> void:
	graph.call("_gui_input", _mouse_button(true, at))
	graph.call("_gui_input", _mouse_button(false, at))


func _state_position(state_name: String) -> Vector2:
	var states: Dictionary = _builder.get("states")
	if states.has(state_name):
		return states[state_name]["position"]
	return Vector2.ZERO


func _report() -> void:
	print("REPORT ---- failures=%d ----" % _failures.size())
	for f in _failures:
		print("REPORT  !! %s" % f)
	print("REPORT DONE")
