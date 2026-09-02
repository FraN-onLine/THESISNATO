extends SceneTree
## Diagnostics for workshop click + keyboard visibility.

func _initialize() -> void:
	print("START")
	var scene: PackedScene = load("res://Testing/AutomataWorkshopBillboard.tscn")
	var wrapper: Node = scene.instantiate()
	root.add_child(wrapper)
	await process_frame
	await process_frame
	var builder: Node = wrapper.get("builder")
	print("wrapper_ok=", wrapper != null, " builder_ok=", builder != null)

	# Enumerate all Buttons: names, rects, visibility.
	var buttons := []
	_collect_buttons(builder, buttons)
	for b in buttons:
		var rect: Rect2 = b.get_global_rect()
		print("BTN '", b.text, "' rect=", rect, " vis=", b.is_visible_in_tree())

	# Find "Add node" and click it through the wrapper pointer pipeline.
	var add_btn: Button = null
	for b in buttons:
		if b.text == "Add node":
			add_btn = b
			break
	if add_btn:
		var center: Vector2 = add_btn.get_global_rect().get_center()
		var before: int = builder.states.size()
		wrapper._send_pointer(center, true, true)
		wrapper._send_pointer(center, true, false)
		await process_frame
		var after: int = builder.states.size()
		print("CLICK added=", after > before, " before=", before, " after=", after)

	# Keyboard visibility.
	var kb_title: Control = builder.get_node_or_null("VBoxContainer/KeyboardTitle")
	if kb_title:
		print("KEYBOARD_TITLE vis=", kb_title.is_visible_in_tree(), " rect=", kb_title.get_global_rect())

	print("DIAGNOSIS COMPLETE")
	quit()

func _collect_buttons(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is Button:
			out.append(child)
		_collect_buttons(child, out)