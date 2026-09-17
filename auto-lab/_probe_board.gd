extends SceneTree
## Deep probe: dumps the whole control tree with rects, then tests the mode
## buttons, symbol palette, connect flow and drag with CORRECT event ordering.

var _vp: SubViewport = null
var _inst: Control = null
var _frames := 0
var _step := 0
var _log: PackedStringArray = []
var _connect_btn: Button = null
var _select_btn: Button = null


func _initialize() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(1800, 1100)
	_vp.handle_input_locally = false
	root.add_child(_vp)
	_inst = (load("res://Testing/AutomataWorkshop.tscn") as PackedScene).instantiate()
	_vp.add_child(_inst)


func _process(_delta: float) -> bool:
	if _inst == null:
		return false
	_frames += 1
	if _frames < 8:
		return false
	match _step:
		0:
			_dump_tree()
		1:
			_dump_mode_buttons()
		2:
			_click_mode_button()
		3:
			_log.append("  AFTER click: edit_mode=%s  connect.pressed=%s  select.pressed=%s" % [
				str(_inst.get("edit_mode")),
				str(_connect_btn.button_pressed) if _connect_btn else "n/a",
				str(_select_btn.button_pressed) if _select_btn else "n/a"])
		4:
			_test_connect_forced()
		5:
			_test_drag()
		6:
			_test_double_tap()
		7:
			_test_simulate()
		8:
			print("\n".join(_log))
			quit()
	_step += 1
	_frames = 0
	return false


func _walk(node: Node, depth: int = 0) -> void:
	for child in node.get_children():
		if child is Control:
			var c: Control = child
			var r: Rect2 = c.get_global_rect()
			var extra := ""
			if c is Button:
				var b: Button = c
				extra = " text='%s' toggle=%s pressed=%s" % [b.text, str(b.toggle_mode), str(b.button_pressed)]
			_log.append("  %s%s [%s] (%.0f,%.0f %.0fx%.0f) vis=%s%s" % [
				"  ".repeat(depth), c.name, c.get_class(), r.position.x, r.position.y,
				r.size.x, r.size.y, str(c.visible), extra])
		_walk(child, depth + 1)


func _dump_tree() -> void:
	_log.append("======== CONTROL TREE (1800x1100) ========")
	_walk(_inst)


func _dump_mode_buttons() -> void:
	_log.append("======== MODE BUTTONS ========")
	for key in [0, 1, 2, 3]:
		var b: Button = _inst.get("mode_buttons").get(key)
		if b == null:
			continue
		_log.append("  mode %d '%s' rect=%s pressed=%s" % [key, b.text, str(b.get_global_rect()), str(b.button_pressed)])
		if key == 1:
			_connect_btn = b
		if key == 0:
			_select_btn = b


func _click_mode_button() -> void:
	var r: Rect2 = _connect_btn.get_global_rect()
	_log.append("  clicking Connect at %s" % str(r.get_center()))
	_press_at(r.get_center())


func _down_at(pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	ev.global_position = pos
	_vp.push_input(ev, true)


func _up_at(pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = pos
	ev.global_position = pos
	_vp.push_input(ev, true)


func _press_at(pos: Vector2) -> void:
	_down_at(pos)
	_up_at(pos)


func _motion(pos: Vector2, held: bool = false) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	_vp.push_input(ev, true)


func _test_connect_forced() -> void:
	_log.append("======== CONNECT (forced edit_mode=CONNECT) ========")
	_inst.call("cancel_pointer_interaction")
	_inst.set("edit_mode", 1)
	_inst.set("active_symbol", "b")
	var states: Dictionary = _inst.get("states")
	var names: Array = states.keys()
	if names.size() < 2:
		_log.append("  [SKIP] fewer than 2 nodes")
		return
	var a: Vector2 = states[names[0]]["position"]
	var b: Vector2 = states[names[1]]["position"]
	_log.append("  tap %s@%s then %s@%s" % [names[0], str(a), names[1], str(b)])
	_press_at(a)
	_log.append("  after 1st tap: source=%s" % str(_inst.get("connect_source")))
	_press_at(b)
	_log.append("  after 2nd tap: transitions=%s" % str(_inst.get("transitions")))


func _test_drag() -> void:
	_log.append("======== DRAG (press, move, release) ========")
	_inst.set("edit_mode", 0)
	var states: Dictionary = _inst.get("states")
	var names: Array = states.keys()
	var before: Vector2 = states[names[0]]["position"]
	_motion(before)
	_down_at(before)
	_motion(before + Vector2(60, 40), true)
	_motion(before + Vector2(140, 100), true)
	_up_at(before + Vector2(140, 100))
	_log.append("  %s before=%s after=%s" % [names[0], str(before), str((_inst.get("states")[names[0]])["position"])])


func _test_double_tap() -> void:
	_log.append("======== DOUBLE-TAP EMPTY BOARD (spawn node) ========")
	_inst.set("edit_mode", 0)
	var before: int = (_inst.get("states") as Dictionary).size()
	var spot := Vector2(900.0, 500.0)
	_press_at(spot)
	_press_at(spot + Vector2(6, 4))
	var after: int = (_inst.get("states") as Dictionary).size()
	_log.append("  states %d -> %d (expect +1)" % [before, after])


func _test_simulate() -> void:
	_log.append("======== SIMULATE ========")
	_inst.call("reset_for_free_build")
	var line = _inst.get("input_line")
	line.text = "aab"
	_inst.call("_simulate_input")
	_log.append("  input='%s' running=%s finished=%s accepted=%s msg=%s" % [line.text,
		str(_inst.get("simulation_running")), str(_inst.get("sim_finished")),
		str(_inst.get("sim_accepted")), str(_inst.get("sim_message"))])
