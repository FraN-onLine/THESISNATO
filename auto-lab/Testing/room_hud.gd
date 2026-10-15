extends Node3D
## In-room status billboard: the 4-phase progress strip (Pretest -> Initial
## Learning -> Adaptive Learning -> Post Test) plus the live study stopwatch.
##
## The desktop build draws this readout as two flat screen overlays
## (phase_hud.gd and counting_timer_overlay.gd). A CanvasLayer does not render
## inside a headset, so in VR the SAME readout is built here as a SubViewport
## shown on a billboard Sprite3D and floated above the main panel - exactly the
## pattern every other board in the room uses. Display-only: no pointer input.
##
## Mapping mirrors phase_hud.gd (phase index) and counting_timer_overlay.gd
## (which clock is shown); keep the three in sync.

const SM := preload("res://Testing/session_manager.gd")
const PanelSurface := preload("res://Testing/Lessons/panel_surface.gd")

const PHASES: Array[String] = ["Pretest", "Initial Learning", "Adaptive Learning", "Post Test"]

# Palette shared with the desktop overlays so both look like one product.
const COL_DONE := Color(0.18, 0.62, 0.36, 0.92)
const COL_CURRENT := Color(0.30, 0.72, 1.0, 0.96)
const COL_TODO := Color(0.13, 0.16, 0.26, 0.82)
const COL_TEXT := Color(0.93, 0.97, 1.0, 1.0)
const COL_TEXT_DIM := Color(0.62, 0.70, 0.82, 1.0)
const COL_TEXT_ON_CURRENT := Color(0.03, 0.09, 0.18, 1.0)
const COL_TIMER := Color(0.55, 0.95, 0.70, 1.0)

var _sprite: Sprite3D
var _segments: Array[PanelContainer] = []
var _seg_styles: Array[StyleBoxFlat] = []
var _seg_labels: Array[Label] = []
var _status: Label
var _timer: Label
var _last_index := -2
var _last_timer := ""

func _ready() -> void:
	_build()
	_sync()

func _process(_delta: float) -> void:
	_sync()

# ===== Presentation ========================================================

func _build() -> void:
	var viewport := SubViewport.new()
	viewport.transparent_bg = true
	viewport.handle_input_locally = false
	viewport.size = Vector2i(1500, 380)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.add_child(root)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	root.add_child(margin)

	var panel := PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.04, 0.05, 0.10, 0.88)
	panel_style.set_corner_radius_all(16)
	panel_style.content_margin_left = 22.0
	panel_style.content_margin_right = 22.0
	panel_style.content_margin_top = 12.0
	panel_style.content_margin_bottom = 14.0
	panel.add_theme_stylebox_override("panel", panel_style)
	margin.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)

	for i in range(PHASES.size()):
		var seg := PanelContainer.new()
		var st := StyleBoxFlat.new()
		st.bg_color = COL_TODO
		st.set_corner_radius_all(10)
		st.content_margin_left = 14.0
		st.content_margin_right = 14.0
		st.content_margin_top = 6.0
		st.content_margin_bottom = 6.0
		seg.add_theme_stylebox_override("panel", st)
		seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(seg)

		var lbl := Label.new()
		lbl.text = PHASES[i]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 26)
		lbl.add_theme_color_override("font_color", COL_TEXT_DIM)
		seg.add_child(lbl)

		_segments.append(seg)
		_seg_styles.append(st)
		_seg_labels.append(lbl)

		if i < PHASES.size() - 1:
			var chev := Label.new()
			chev.text = ">"
			chev.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			chev.add_theme_font_size_override("font_size", 26)
			chev.add_theme_color_override("font_color", COL_TEXT_DIM)
			chev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(chev)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 14)
	vbox.add_child(bottom)

	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.add_theme_font_size_override("font_size", 22)
	_status.add_theme_color_override("font_color", COL_TEXT_DIM)
	bottom.add_child(_status)

	_timer = Label.new()
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_timer.add_theme_font_size_override("font_size", 26)
	_timer.add_theme_color_override("font_color", COL_TIMER)
	bottom.add_child(_timer)

	_sprite = Sprite3D.new()
	_sprite.texture = viewport.get_texture()
	_sprite.pixel_size = 0.002
	add_child(_sprite)
	PanelSurface.face_player(_sprite)

# ===== Sync ================================================================

## Map the shared session state onto the 4 user-facing phases (same mapping as
## phase_hud.gd).
func _phase_index(s) -> int:
	if s == null:
		return -1
	match int(s.state):
		SM.SessionState.PROFILE_SETUP, SM.SessionState.PRETEST:
			return 0
		SM.SessionState.ANALYSIS:
			return 1
		SM.SessionState.ADAPTIVE_LEARNING:
			return 2
		SM.SessionState.POST_TEST, SM.SessionState.COMPLETE:
			return 3
	return -1

func _sync() -> void:
	var s = SessionBridge.get_session()
	var idx := _phase_index(s)
	visible = idx >= 0
	if idx < 0:
		return
	if idx != _last_index:
		_last_index = idx
		_apply_phase(idx)
	_sync_timer(s)

func _apply_phase(idx: int) -> void:
	for i in range(_segments.size()):
		var style := _seg_styles[i]
		var lbl := _seg_labels[i]
		if i < idx:
			style.bg_color = COL_DONE
			lbl.add_theme_color_override("font_color", COL_TEXT)
			lbl.text = "v  %s" % PHASES[i]
		elif i == idx:
			style.bg_color = COL_CURRENT
			lbl.add_theme_color_override("font_color", COL_TEXT_ON_CURRENT)
			lbl.text = PHASES[i]
		else:
			style.bg_color = COL_TODO
			lbl.add_theme_color_override("font_color", COL_TEXT_DIM)
			lbl.text = PHASES[i]
	_status.text = "Final phase" if idx >= PHASES.size() - 1 else "Up next: %s" % PHASES[idx + 1]

## Show the clock counting_timer_overlay.gd would show on screen: adaptive
## completion time while learning adaptively, post-test time during the test.
func _sync_timer(s) -> void:
	var text := ""
	if s != null:
		match int(s.state):
			SM.SessionState.ADAPTIVE_LEARNING:
				text = _format_clock("Adaptive Learning", s.get_adaptive_completion_seconds())
			SM.SessionState.POST_TEST, SM.SessionState.COMPLETE:
				text = _format_clock("Post Test", s.get_posttest_seconds())
	if text == _last_timer:
		return
	_last_timer = text
	_timer.text = text
	_timer.visible = text != ""

func _format_clock(caption: String, secs: float) -> String:
	return "%s  %02d:%02d" % [caption, int(secs) / 60, int(secs) % 60]
