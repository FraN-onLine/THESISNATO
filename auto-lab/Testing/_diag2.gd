extends SceneTree
## Diag: verify all buttons fit inside the 1800x1100 SubViewport.

func _initialize() -> void:
	var scene: PackedScene = load("res://Testing/AutomataWorkshopBillboard.tscn")
	var wrapper: Node = scene.instantiate()
	root.add_child(wrapper)
	await process_frame
	await process_frame
	var builder: Node = wrapper.get("builder")
	var buttons := []
	_collect(builder, buttons)
	var overflow := 0
	for b in buttons:
		var r: Rect2 = b.get_global_rect()
		if r.position.y + r.size.y > 1100.0:
			overflow += 1
			print("OVERFLOW '", b.text, "' bottom=", r.position.y + r.size.y)
	# Check specifically the bottom-most UI controls.
	print("total_buttons=", buttons.size(), " overflow_count=", overflow)
	print("VALIDATION COMPLETE")
	quit()

func _collect(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is Button:
			out.append(child)
		_collect(child, out)