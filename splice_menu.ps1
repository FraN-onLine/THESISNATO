# Splice the new _show_main_menu body into testing_grounds.gd
$path = 'c:\Autolab\auto-lab\Testing\testing_grounds.gd'
$c = Get-Content $path

$startIdx = -1
$endIdx = -1
for ($i = 0; $i -lt $c.Count; $i++) {
    if ($c[$i] -match '^func _show_main_menu\(\) -> void:') { $startIdx = $i }
    if ($startIdx -ge 0 -and $c[$i] -match '^func _create_algorithm_buttons\(\) -> void:') { $endIdx = $i; break }
}
if ($startIdx -lt 0 -or $endIdx -lt 0) { Write-Output "REGION NOT FOUND ($startIdx,$endIdx)"; exit 1 }

$newLines = [System.Collections.Generic.List[string]]::new()
$T = [char]9
$newLines.Add('func _show_main_menu() -> void:')
$newLines.Add($T + 'title_label.text = "TESTING GROUNDS"')
$newLines.Add($T + '_clear_content()')
$newLines.Add('')
$newLines.Add($T + 'var algo_type: int = session.selected_algorithm if session.selected_algorithm >= 0 else AlgorithmCatalog.TYPE_HMM')
$newLines.Add($T + 'var info: Dictionary = AlgorithmCatalog.fetch_info(algo_type)')
$newLines.Add($T + 'var flavor: String = AlgorithmCatalog.fetch_how_learns_flavor(algo_type)')
$newLines.Add($T + 'question_label.text = "Welcome to the DFA Testing Grounds!\\n\\nActive algorithm: %s\\n%s\\n\\nThis adaptive system walks you through:\\n1. Pretest - your answers are the ONLY input/starting elements for the algorithm.\\n2. Knowledge Analysis - the algorithm reads your pretest and builds its starting model.\\n3. Interactive Learning - every practice answer is analysed live; each topic TERMINATES the moment the algorithm decides you have learnt it. During any topic you can FREE-BUILD and simulate your own automata on the whiteboard (custom states, transitions, and your own test strings).\\n4. Post Test - a no-feedback test that proves (or disproves) the algorithm\'s theory.\\n\\nThe driver for this session: %s" % [info["name"], info["tagline"], session.get_algorithm_callout()]')
$newLines.Add($T + 'question_label.visible = true')
$newLines.Add($T + '_clear_options()')
$newLines.Add('')
$newLines.Add($T + 'var start_btn := Button.new()')
$newLines.Add($T + 'start_btn.text = "Start Session (Pretest first)"')
$newLines.Add($T + 'start_btn.custom_minimum_size = Vector2(1100, 56)')
$newLines.Add($T + 'start_btn.add_theme_font_size_override("font_size", 20)')
$newLines.Add($T + 'start_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))')
$newLines.Add($T + 'start_btn.add_theme_stylebox_override("normal", _create_button_style(Color(0.1, 0.55, 0.35, 1)))')
$newLines.Add($T + 'start_btn.add_theme_stylebox_override("hover", _create_button_style(Color(0.2, 0.75, 0.45, 1)))')
$newLines.Add($T + 'start_btn.add_theme_stylebox_override("pressed", _create_button_style(Color(0.07, 0.4, 0.25, 1)))')
$newLines.Add($T + 'start_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())')
$newLines.Add($T + 'start_btn.pressed.connect(_on_start_session)')
$newLines.Add($T + 'options_box.add_child(start_btn)')
$newLines.Add('')
$newLines.Add($T + 'var library_btn := Button.new()')
$newLines.Add($T + 'library_btn.text = "How %s learns - Algorithm Library" % info["callout"]')
$newLines.Add($T + 'library_btn.custom_minimum_size = Vector2(1100, 52)')
$newLines.Add($T + 'library_btn.add_theme_font_size_override("font_size", 18)')
$newLines.Add($T + 'library_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))')
$newLines.Add($T + 'library_btn.add_theme_stylebox_override("normal", _create_button_style(Color(0.16, 0.28, 0.62, 1)))')
$newLines.Add($T + 'library_btn.add_theme_stylebox_override("hover", _create_button_style(Color(0.3, 0.48, 0.95, 1)))')
$newLines.Add($T + 'library_btn.add_theme_stylebox_override("pressed", _create_button_style(Color(0.1, 0.19, 0.45, 1)))')
$newLines.Add($T + 'library_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())')
$newLines.Add($T + 'library_btn.pressed.connect(_show_algorithm_library)')
$newLines.Add($T + 'options_box.add_child(library_btn)')
$newLines.Add('')
$newLines.Add($T + 'var change_btn := Button.new()')
$newLines.Add($T + 'change_btn.text = "Choose a different algorithm"'  )
$newLines.Add($T + 'change_btn.custom_minimum_size = Vector2(1100, 52)')
$newLines.Add($T + 'change_btn.add_theme_font_size_override("font_size", 18)')
$newLines.Add($T + 'change_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))')
$newLines.Add($T + 'change_btn.add_theme_stylebox_override("normal", _create_button_style(Color(0.4, 0.3, 0.55, 1)))')
$newLines.Add($T + 'change_btn.add_theme_stylebox_override("hover", _create_button_style(Color(0.55, 0.42, 0.75, 1)))')
$newLines.Add($T + 'change_btn.add_theme_stylebox_override("pressed", _create_button_style(Color(0.28, 0.2, 0.4, 1)))')
$newLines.Add($T + 'change_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())')
$newLines.Add($T + 'change_btn.pressed.connect(_change_algorithm)')
$newLines.Add($T + 'options_box.add_child(change_btn)')
$newLines.Add('')
$newLines.Add($T + 'feedback_label.text = ""')
$newLines.Add($T + 'progress_label.text = "XP: %d  |  Level %d %s  |  Best streak: %d" % [session.gamification.total_xp, session.gamification.get_level(), session.gamification.get_level_title(), session.gamification.best_streak]')
$newLines.Add($T + 'back_button.visible = true')
$newLines.Add($T + 'back_button.text = "Back to Lab"')
$newLines.Add($T + 'next_button.visible = false')

$result = [System.Collections.Generic.List[string]]::new()
for ($i = 0; $i -lt $startIdx; $i++) { $result.Add($c[$i]) }
foreach ($l in $newLines) { $result.Add($l) }
for ($i = $endIdx; $i -lt $c.Count; $i++) { $result.Add($c[$i]) }
Set-Content -Path $path -Value $result -Encoding UTF8
Write-Output "spliced $startIdx..$endIdx -> $($newLines.Count) lines"