extends SceneTree
## Final integration check: billboard wrapper + builder + new UI/simulation.

func _initialize() -> void:
	print("START")
	var scene: PackedScene = load("res://Testing/AutomataWorkshopBillboard.tscn")
	var wrapper: Node = scene.instantiate()
	root.add_child(wrapper)
	await process_frame
	await process_frame
	var builder: Node = wrapper.get("builder")
	print("wrapper_ok=", wrapper != null, " builder_ok=", builder != null)

	# Keyboard rows should now be on-screen after compaction.
	var kb_title: Control = builder.get_node_or_null("SubViewport/Root/VBoxContainer/KeyboardTitle")
	if kb_title == null:
		kb_title = builder.get_node_or_null("VBoxContainer/KeyboardTitle")
	if kb_title:
		print("KEYBOARD_TITLE vis=", kb_title.is_visible_in_tree(), " rect=", kb_title.get_global_rect())
	else:
		print("NO KeyboardTitle node found")

	var sim_kb: Control = builder.get_node_or_null("SubViewport/Root/VBoxContainer/SimKeyboardTitle")
	if sim_kb == null:
		sim_kb = builder.get_node_or_null("SimKeyboardTitle")
	if sim_kb:
		print("SIM_KB_TITLE vis=", sim_kb.is_visible_in_tree(), " rect=", sim_kb.get_global_rect())

	# Click "Add node" via wrapper pointer pipeline.
	var add_btn: Button = _find_button(builder, "Add node")
	if add_btn:
		var center: Vector2 = add_btn.get_global_rect().get_center()
		var before: int = builder.states.size()
		wrapper._send_pointer(center, true, true)
		wrapper._send_pointer(center, true, false)
		await process_frame
		print("CLICK added=", builder.states.size() > before)

	# Run a simulation and force a redraw (draw functions touched).
	builder.reset_for_task_lists("Build", ["ab"], ["aa"])
	builder._add_state()
	var q1: String = builder.selected_state
	builder.states[q1]["accepting"] = true
	builder.selected_state = "q0"
	builder.active_symbol = "a"
	builder.connect_selected(q1)
	builder.start_simulation("ab")
	builder._advance_simulation()
	builder._advance_simulation()
	await process_frame
	print("sim_finished=", builder.sim_finished, " accepted=", builder.sim_accepted, " flash=", builder.sim_flash)

	print("VALIDATION COMPLETE")
	quit()

func _find_button(node: Node, label: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text == label:
			return child
		var found := _find_button(child, label)
		if found:
			return found
	return null