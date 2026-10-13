extends SceneTree

func _initialize() -> void:
	print("PROBE ---- project xr settings ----")
	for p in ProjectSettings.get_property_list():
		var n := String(p.name)
		if n.begins_with("xr/"):
			print("PROBE ", n, " = ", ProjectSettings.get_setting(n))
	print("PROBE ---- XRServer interfaces ----")
	var any := false
	for i in XRServer.get_interfaces():
		any = true
		print("PROBE iface ", i)
	if not any:
		print("PROBE iface <none registered>")
	var xr := XRServer.find_interface("OpenXR")
	print("PROBE find_interface(OpenXR) = ", xr)
	if xr != null:
		print("PROBE   initialized=", xr.is_initialized())
		var ok := xr.initialize()
		print("PROBE   initialize() -> ", ok, " now=", xr.is_initialized())
		if ok:
			xr.shutdown()
	quit(0)
