extends CanvasLayer
## Screen-overlay progress HUD for the 4-phase adaptive-learning flow:
##   Pretest -> Initial Learning -> Adaptive Learning -> Post Test.
##
## It is a pure screen-space overlay (a CanvasLayer), so it floats over the
## in-room billboard UI in VR and over the window on desktop. It self-syncs from
## the shared SessionBridge session, so the SAME scene works in both the Testing
## Grounds and the separate Pretest / Post-test room. Every control uses
## MOUSE_FILTER_IGNORE, so the HUD never steals pointer or laser input.

const SM = preload("res://Testing/session_manager.gd")

const PHASES: Array[String] = ["Pretest", "Initial Learning", "Adaptive Learning", "Post Test"]

# --- Palette ---------------------------------------------------------------
const COL_DONE := Color(0.18, 0.62, 0.36, 0.92)
const COL_CURRENT := Color(0.30, 0.72, 1.0, 0.96)
const COL_TODO := Color(0.13, 0.16, 0.26, 0.82)
const COL_TEXT := Color(0.93, 0.97, 1.0, 1.0)
const COL_TEXT_DIM := Color(0.62, 0.70, 0.82, 1.0)
const COL_TEXT_ON_CURRENT := Color(0.03, 0.09, 0.18, 1.0)

var _segments: Array[PanelContainer] = []
var _seg_styles: Array[StyleBoxFlat] = []
var _seg_labels: Array[Label] = []
var _bar: ProgressBar
var _status: Label
var _last_index := -2

func _ready() -> void:
	layer = 128
	_build()
	_sync()

func _process(_delta: float) -> void:
	_sync()

## Map the shared session state onto the 4 user-facing phases.
func _phase_index() -> int:
	var s = SessionBridge.get_session()
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
	var idx := _phase_index()
	if idx < 0:
		visible = false
		return
	visible = true
	if idx == _last_index:
		return
	_last_index = idx
	_apply_phase(idx)

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
			lbl.text = "%s" % PHASES[i]
		else:
			style.bg_color = COL_TODO
			lbl.add_theme_color_override("font_color", COL_TEXT_DIM)
			lbl.text = "%s" % PHASES[i]
	if _bar:
		_bar.value = float(idx + 1) / float(PHASES.size()) * 100.0
	if _status:
		_status.text = "Final phase" if idx >= PHASES.size() - 1 else "Up next: %s" % PHASES[idx + 1]

func _build() -> void:
	# Anchored to the BOTTOM-LEFT corner and shrunk to its content so it stays
	# out of the way of the main panel.
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	margin.grow_horizontal = Control.GROW_DIRECTION_END
	margin.grow_vertical = Control.GROW_DIRECTION_BEGIN
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	add_child(margin)

	var panel := PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.04, 0.05, 0.10, 0.36)
	panel_style.corner_radius_top_left = 10
	panel_style.corner_radius_top_right = 10
	panel_style.corner_radius_bottom_right = 10
	panel_style.corner_radius_bottom_left = 10
	panel_style.content_margin_left = 12
	panel_style.content_margin_right = 12
	panel_style.content_margin_top = 8
	panel_style.content_margin_bottom = 9
	panel.add_theme_stylebox_override("panel", panel_style)
	margin.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	vbox.add_child(row)

	for i in range(PHASES.size()):
		var seg := PanelContainer.new()
		var st := StyleBoxFlat.new()
		st.bg_color = COL_TODO
		st.corner_radius_top_left = 7
		st.corner_radius_top_right = 7
		st.corner_radius_bottom_right = 7
		st.corner_radius_bottom_left = 7
		st.content_margin_left = 6
		st.content_margin_right = 6
		st.content_margin_top = 3
		st.content_margin_bottom = 3
		seg.add_theme_stylebox_override("panel", st)
		seg.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		seg.custom_minimum_size = Vector2(0, 22)
		row.add_child(seg)

		var lbl := Label.new()
		lbl.text = PHASES[i]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", COL_TEXT_DIM)
		seg.add_child(lbl)

		_segments.append(seg)
		_seg_styles.append(st)
		_seg_labels.append(lbl)

		if i < PHASES.size() - 1:
			var chev := Label.new()
			chev.text = ">"
			chev.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			chev.add_theme_font_size_override("font_size", 11)
			chev.add_theme_color_override("font_color", COL_TEXT_DIM)
			chev.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			chev.custom_minimum_size = Vector2(8, 0)
			row.add_child(chev)

	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(180, 6)
	_bar.max_value = 100.0
	_bar.value = 25.0
	_bar.show_percentage = false
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.10, 0.13, 0.22, 0.9)
	bar_bg.corner_radius_top_left = 4
	bar_bg.corner_radius_top_right = 4
	bar_bg.corner_radius_bottom_left = 4
	bar_bg.corner_radius_bottom_right = 4
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = COL_CURRENT
	bar_fill.corner_radius_top_left = 4
	bar_fill.corner_radius_top_right = 4
	bar_fill.corner_radius_bottom_left = 4
	bar_fill.corner_radius_bottom_right = 4
	_bar.add_theme_stylebox_override("background", bar_bg)
	_bar.add_theme_stylebox_override("fill", bar_fill)
	vbox.add_child(_bar)

	_status = Label.new()
	_status.text = ""
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 10)
	_status.add_theme_color_override("font_color", COL_TEXT_DIM)
	vbox.add_child(_status)

	_set_ignore_recursive(self)

## Make the whole HUD transparent to pointer / laser input.
func _set_ignore_recursive(node: Node) -> void:
	for c in node.get_children():
		if c is Control:
			(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_ignore_recursive(c)

