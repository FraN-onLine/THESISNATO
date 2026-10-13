class_name CountingTimerOverlay
extends CanvasLayer
## Live count-up stopwatch rendered as a screen-space overlay.
##
## Two modes:
##   "adaptive"  - counts from the start of adaptive learning and freezes the
##                 moment the algorithm deems the learner knowledgeable
##                 (Adaptive Learning Completion Time).
##   "posttest"  - counts the time spent proving mastery on the post test.
##
## The session owns the numbers (SessionManager.adaptive_* / timer_*);
## this node only renders them, so the overlay can never disagree with what
## the comparative-study JSON records. Every control uses MOUSE_FILTER_IGNORE,
## so it never steals pointer or laser input.

const SM = preload("res://Testing/session_manager.gd")

@export_enum("adaptive", "posttest") var mode := "adaptive"

var _caption: Label
var _time_label: Label
var _last_text := ""

func _ready() -> void:
	layer = 129
	_build()
	_sync()

func _process(_delta: float) -> void:
	_sync()

## Map the shared session state onto "should this mode be visible right now".
func _sync() -> void:
	var s = SessionBridge.get_session()
	if s == null:
		visible = false
		return
	var should_show := false
	var caption := "Adaptive Learning"
	var secs := 0.0
	match mode:
		"posttest":
			should_show = int(s.state) == SM.SessionState.POST_TEST \
				or int(s.state) == SM.SessionState.COMPLETE
			caption = "Post Test"
			secs = s.get_posttest_seconds()
		_:
			should_show = int(s.state) == SM.SessionState.ADAPTIVE_LEARNING
			caption = "Adaptive Learning"
			secs = s.get_adaptive_completion_seconds()
	visible = should_show
	if not should_show:
		return
	var text := "%02d:%02d" % [int(secs) / 60, int(secs) % 60]
	if text != _last_text:
		_last_text = text
		if _time_label:
			_time_label.text = text
		if _caption:
			_caption.text = caption

## Top-right stopwatch panel: CAPTION  mm:ss.
func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	margin.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	margin.grow_vertical = Control.GROW_DIRECTION_END
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)

	var panel := PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.04, 0.06, 0.12, 0.85)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.content_margin_left = 12
	panel_style.content_margin_right = 12
	panel_style.content_margin_top = 6
	panel_style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", panel_style)
	margin.add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	_caption = Label.new()
	_caption.text = "Adaptive Learning"
	_caption.add_theme_font_size_override("font_size", 13)
	_caption.add_theme_color_override("font_color", Color(0.62, 0.70, 0.82, 1.0))
	row.add_child(_caption)

	_time_label = Label.new()
	_time_label.text = "00:00"
	_time_label.add_theme_font_size_override("font_size", 16)
	_time_label.add_theme_color_override("font_color", Color(0.55, 0.95, 0.70, 1.0))
	row.add_child(_time_label)

	_set_ignore_recursive(self)

## Make the whole overlay transparent to pointer / laser input.
func _set_ignore_recursive(node: Node) -> void:
	for c in node.get_children():
		if c is Control:
			(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_ignore_recursive(c)
