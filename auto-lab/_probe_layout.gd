extends SceneTree
## Temporary layout probe: instantiates the workshop at several viewport sizes and
## prints, for every Control, its rect versus the viewport rect. Anything that
## falls outside is unreachable/unseeable by the player.

var _sizes := [Vector2i(1800, 1100), Vector2i(1400, 760), Vector2i(1280, 720), Vector2i(1024, 600)]
var _idx := -1
var _vp: SubViewport = null
var _inst: Control = null
var _frames := 0

func _initialize() -> void:
	_advance()

func _advance() -> void:
	_idx += 1
	if _idx >= _sizes.size():
		quit()
		return
	if _vp != null:
		_vp.queue_free()
	var s: Vector2i = _sizes[_idx]
	_vp = SubViewport.new()
	_vp.size = s
	root.add_child(_vp)
	var scene: PackedScene = load("res://Testing/AutomataWorkshop.tscn")
	_inst = scene.instantiate()
	_vp.add_child(_inst)
	_frames = 0

func _process(_delta: float) -> bool:
	if _inst == null:
		return false
	_frames += 1
	if _frames < 6:
		return false
	var s: Vector2i = _sizes[_idx]
	print("")
	print("======== VIEWPORT %dx%d ========" % [s.x, s.y])
	_report(_inst, Rect2(Vector2.ZERO, Vector2(s)), 0)
	_advance()
	return false

func _report(node: Node, view: Rect2, depth: int) -> void:
	var pad := "  ".repeat(depth)
	for child in node.get_children():
		if child is Control:
			var c: Control = child
			var r := c.get_global_rect()
			var ok: bool = view.encloses(r)
			var overlap: bool = view.intersects(r)
			print("%s%-20s rect=(%.0f,%.0f %.0fx%.0f) min=(%.0fx%.0f) full=%s part=%s vis=%s" % [
				pad, c.name, r.position.x, r.position.y, r.size.x, r.size.y,
				c.get_combined_minimum_size().x, c.get_combined_minimum_size().y,
				"YES" if ok else "no", "yes" if overlap else "NO", c.visible])
			if depth < 3:
				_report(c, view, depth + 1)
