extends SceneTree

## Headless interaction probe for the Automata whiteboard.
## Verifies, without a human, that: the palette below the board is on-screen and
## clickable, mode switching works (Connect/Move), node dragging works, and the
## double-tap node stamp works. Writes a report next to the project.

const OUT_PATH := "C:/Autolab/_probe3_out.txt"
const VW := 1800
const VH := 1100

var log_lines: Array[String] = []
var viewport: SubViewport
var builder: Control


func _initialize() -> void:
	await _run()
	_write_report()
	quit()


func _log(text: String) -> void:
	log_lines.append(text)


func _write_report() -> void:
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string("\n".join(log_lines))
	f.close()


func _run() -> void:
	var packed: PackedScene = load("res://Testing/AutomataWorkshop.tscn")
	viewport = SubViewport.new()
	viewport.size = Vector2i(VW, VH)
	viewport.handle_input_locally = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	builder = packed.instantiate()
	viewport.add_child(builder)
	await process_frame
	await process_frame

	_log("=== BUILDER READY ===")
	_log("builder size = %s" % str(builder.size))

	var controls := _all_controls(builder)
	_log("=== CONTROL COUNT: %d ===" % controls.size())
	_report_layout(controls)
	await _test_modes(controls)
	await _test_symbol(controls)
	await _test_drag()
	await _test_double_tap()
	await _test_simulate_and_check(controls)


# ---------------------------------------------------------------- layout
func _all_controls(node: Node, out: Array = []) -> Array:
	for child in node.get_children():
		if child is Button or child is LineEdit:
			out.append(child)
		_all_controls(child, out)
	return out


func _report_layout(controls: Array) -> void:
	var off_screen: Array[String] = []
	for control in controls:
		var rect: Rect2 = control.get_global_rect()
		var text := "<LineEdit>"
		if control is Button:
			text = control.text
			_log("BTN %-24s rect=%s visible=%s" % [text.substr(0, 24), str(rect), str(control.visible)])
		var inside := rect.position.x >= -1.0 and rect.position.y >= -1.0 \
			and rect.end.x <= float(VW) + 1.0 and rect.end.y <= float(VH) + 1.0
		if not inside:
			off_screen.append("%s at %s" % [text, str(rect)])
	_log("OFF-SCREEN CONTROLS: %d" % off_screen.size())
	for entry in off_screen:
		_log("   OFFSCREEN %s" % entry)


func _find_button(controls: Array, text: String) -> Button:
	for control in controls:
		if control is Button and control.text == text:
			return control
	return null


# ---------------------------------------------------------------- clicks
func _click(control: Control) -> void:
	await _click_at(control.get_global_rect().get_center())


func _click_at(pos: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pos
	viewport.push_input(down, true)
	await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pos
	viewport.push_input(up, true)
	await process_frame
	await process_frame


# ---------------------------------------------------------------- tests
func _test_modes(controls: Array) -> void:
	_log("=== TEST: MODE SWITCHING ===")
	for label in ["Connect", "Move", "Select"]:
		var btn: Button = _find_button(controls, label)
		if btn == null:
			_log("MISSING MODE BUTTON: %s" % label)
			continue
		await _click(btn)
		_log("clicked %-8s -> edit_mode=%d (0=SELECT 1=CONNECT 2=MOVE) pressed=%s" % [
			label, builder.edit_mode, str(btn.button_pressed)])


func _test_symbol(controls: Array) -> void:
	_log("=== TEST: SYMBOL PALETTE ===")
	for label in ["1", "0", "a"]:
		var btn: Button = _find_button(controls, label)
		if btn == null:
			_log("MISSING SYMBOL KEY: %s" % label)
			continue
		await _click(btn)
		_log("clicked symbol '%s' -> active_symbol=%s" % [label, builder.active_symbol])


func _graph() -> Control:
	return builder.get("graph")


func _drag(from_pos: Vector2, to_pos: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = from_pos
	viewport.push_input(down, true)
	await process_frame
	# Several intermediate motion events, exactly like a real drag.
	for step in range(1, 6):
		var motion := InputEventMouseMotion.new()
		motion.position = from_pos.lerp(to_pos, float(step) / 5.0)
		viewport.push_input(motion, true)
		await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = to_pos
	viewport.push_input(up, true)
	await process_frame
	await process_frame


func _test_drag() -> void:
	_log("=== TEST: DRAG A NODE ===")
	var graph: Control = _graph()
	if graph == null:
		_log("FAIL: no graph canvas found on builder")
		return
	# Force SELECT mode through the public mode entry point.
	var states: Dictionary = builder.get("states")
	var names: Array = states.keys()
	if names.is_empty():
		_log("FAIL: no states to drag")
		return
	var node_name: String = names[0]
	var before: Vector2 = states[node_name]["position"]
	var origin: Vector2 = graph.get_global_rect().position
	await _drag(origin + before, origin + before + Vector2(120, 90))
	var after: Vector2 = builder.get("states")[node_name]["position"]
	var moved: float = before.distance_to(after)
	_log("drag %s: before=%s after=%s moved=%.1f px -> %s" % [
		node_name, str(before), str(after), moved,
		"PASS" if moved > 10.0 else "FAIL"])


func _test_double_tap() -> void:
	_log("=== TEST: DOUBLE-TAP EMPTY BOARD ===")
	var graph: Control = _graph()
	if graph == null:
		_log("FAIL: no graph canvas")
		return
	var origin: Vector2 = graph.get_global_rect().position
	var size: Vector2 = graph.size
	# Leave CONNECT mode if active so the tap stamps a node.
	builder.call("_set_edit_mode", 0)
	await process_frame
	var before_count: int = (builder.get("states") as Dictionary).size()
	var spot := Vector2(-1, -1)
	for row in range(1, 8):
		for col in range(1, 8):
			var candidate := Vector2(size.x * float(col) / 8.0, size.y * float(row) / 8.0)
			if graph.call("_node_at", candidate) == "":
				spot = candidate
				break
		if spot.x >= 0.0:
			break
	if spot.x < 0.0:
		_log("FAIL: no empty spot found")
		return
	await _click_at(origin + spot)
	await _click_at(origin + spot)
	var after_count: int = (builder.get("states") as Dictionary).size()
	_log("tap at %s : states %d -> %d -> %s" % [
		str(spot), before_count, after_count,
		"PASS" if after_count > before_count else "FAIL"])


func _test_simulate_and_check(controls: Array) -> void:
	_log("=== TEST: SIMULATE + CHECK TASK BUTTONS ===")
	var simulate: Button = _find_button(controls, "Simulate")
	var check: Button = _find_button(controls, "Check task")
	_log("Simulate button found=%s | Check task button found=%s" % [
		str(simulate != null), str(check != null)])
	if simulate != null:
		_log("Simulate rect=%s visible=%s" % [str(simulate.get_global_rect()), str(simulate.visible)])
	if check != null:
		_log("Check rect=%s visible=%s" % [str(check.get_global_rect()), str(check.visible)])
	var input_control: LineEdit = builder.get("input_line")
	if input_control == null:
		_log("FAIL: simulation input LineEdit missing")
	else:
		_log("input_line rect=%s visible=%s" % [
			str(input_control.get_global_rect()), str(input_control.visible)])
		input_control.text = "1010"
	if simulate != null:
		await _click(simulate)
		_log("after Simulate click: running=%s current=%s" % [
			str(builder.get("simulation_running")), str(builder.get("sim_current"))])
	if check != null:
		await _click(check)
		var status: Label = builder.get("status_label")
		_log("after Check click: status='%s'" % (status.text if status else "<none>"))