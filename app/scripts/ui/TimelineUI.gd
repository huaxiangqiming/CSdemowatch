extends Control
## Sends clock commands only. Never accesses player meshes or track data.
signal reset_camera_requested

var clock: RefCounted
var slider: HSlider
var play_button: Button
var pause_button: Button
var rewind_button: Button
var speed_buttons: Array[Button] = []
var time_label: Label
var status_label: Label
var error_label: Label
var _dragging := false
var _resume_after_drag := false
var subtitle: Label
var tick_labels: Array[Label] = []


func _ready() -> void:
	_build_ui()
	_set_enabled(false)


func bind_clock(value: RefCounted) -> void:
	if clock != null:
		clock.time_changed.disconnect(_on_time_changed)
		clock.state_changed.disconnect(_refresh_state)
	clock = value
	_dragging = false
	_resume_after_drag = false
	error_label.hide()
	slider.max_value = clock.duration
	clock.time_changed.connect(_on_time_changed)
	clock.state_changed.connect(_refresh_state)
	_set_enabled(true)
	_on_time_changed(clock.current_time)
	_refresh_state()
	for i in tick_labels.size():
		tick_labels[i].text = _format_time(clock.duration * i / 4.0).split(".")[0]

func describe_replay(metadata: Dictionary, filename: String) -> void:
	subtitle.text = "%s  /  %s  /  Debug plane" % [filename, metadata.map]


func show_error(message: String) -> void:
	error_label.text = "Unable to read replay\n" + message
	error_label.show()
	status_label.text = "LOAD ERROR"
	_set_enabled(false)


func _set_enabled(enabled: bool) -> void:
	slider.editable = enabled
	for button in [play_button, pause_button, rewind_button] + speed_buttons:
		button.disabled = not enabled


func _on_time_changed(seconds: float) -> void:
	# Clock updates must not emit value_changed and recursively seek.
	slider.set_value_no_signal(seconds)
	time_label.text = "%s  /  %s" % [_format_time(seconds), _format_time(clock.duration)]


func _refresh_state() -> void:
	play_button.disabled = clock.is_playing or _dragging
	pause_button.disabled = not clock.is_playing or _dragging
	play_button.text = "Replay" if clock.current_time >= clock.duration else "Play"
	status_label.text = "SCRUBBING" if _dragging else (
		"PLAYING" if clock.is_playing else ("FINISHED" if clock.current_time >= clock.duration else "PAUSED"))
	for i in speed_buttons.size():
		speed_buttons[i].set_pressed_no_signal(is_equal_approx(clock.playback_speed, [0.5, 1.0, 2.0][i]))


func _on_slider_changed(value: float) -> void:
	if clock != null:
		clock.seek(value)


func _on_drag_started() -> void:
	if clock == null:
		return
	_dragging = true
	_resume_after_drag = clock.is_playing
	clock.pause()


func _on_drag_ended(_value_changed: bool) -> void:
	if clock == null:
		return
	_dragging = false
	if _resume_after_drag and clock.current_time < clock.duration:
		clock.play()
	_resume_after_drag = false
	_refresh_state()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and _dragging:
		_dragging = false
		_resume_after_drag = false
		_refresh_state()


func _unhandled_key_input(event: InputEvent) -> void:
	if clock != null and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		if not _dragging:
			if clock.is_playing:
				clock.pause()
			else:
				clock.play()
		get_viewport().set_input_as_handled()


func _format_time(seconds: float) -> String:
	var millis := roundi(seconds * 1000.0)
	return "%02d:%02d.%03d" % [millis / 60000, (millis / 1000) % 60, millis % 1000]


func _build_ui() -> void:
	theme = preload("res://scripts/application/ShellStyle.gd").theme()

	var header := PanelContainer.new()
	add_child(header)
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_bottom = 92
	header.add_theme_stylebox_override("panel", _box(Color("ffffff"), 0, 24, 14))
	var header_row := HBoxContainer.new()
	header.add_child(header_row)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(heading)
	var title := _label("TACTICAL REPLAY", 24)
	heading.add_child(title)
	subtitle = _label("Loading replay...", 14, Color("52677c"))
	heading.add_child(subtitle)
	var badge := _label("LOCAL • OFFLINE", 14, Color("087e8b"))
	header_row.add_child(badge)

	var footer := PanelContainer.new()
	add_child(footer)
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top = -166
	footer.add_theme_stylebox_override("panel", _box(Color("ffffff"), 0, 24, 10))
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	footer.add_child(rows)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)
	rows.add_child(controls)
	rewind_button = _button("Restart", controls)
	rewind_button.pressed.connect(func(): clock.seek(0.0))
	play_button = _button("Play", controls)
	play_button.custom_minimum_size.x = 86
	play_button.pressed.connect(func(): clock.play())
	pause_button = _button("Pause", controls)
	pause_button.pressed.connect(func(): clock.pause())
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(gap)
	status_label = _label("LOADING", 12, Color("087e8b"))
	controls.add_child(status_label)
	time_label = _label("00:00.000  /  00:20.000", 17)
	time_label.custom_minimum_size.x = 225
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls.add_child(time_label)
	for speed in [0.5, 1.0, 2.0]:
		var button := _button(str(speed).trim_suffix(".0") + "x", controls)
		button.toggle_mode = true
		button.custom_minimum_size.x = 58
		button.pressed.connect(func(): clock.set_speed(speed))
		speed_buttons.append(button)
	slider = HSlider.new()
	slider.name = "TimelineSlider"
	slider.custom_minimum_size.y = 28
	slider.min_value = 0.0
	slider.max_value = 20.0
	slider.step = 0.001
	slider.scrollable = false
	slider.value_changed.connect(_on_slider_changed)
	slider.drag_started.connect(_on_drag_started)
	slider.drag_ended.connect(_on_drag_ended)
	rows.add_child(slider)
	var ticks := Control.new()
	ticks.custom_minimum_size.y = 20
	rows.add_child(ticks)
	var marks := ["00:00", "00:05", "00:10", "00:15", "00:20"]
	for i in marks.size():
		var mark: String = marks[i]
		var label := _label(mark, 12, Color("52677c"))
		tick_labels.append(label)
		ticks.add_child(label)
		label.anchor_left = i / 4.0
		label.anchor_right = i / 4.0
		label.offset_left = -30
		label.offset_right = 30
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if mark == "00:00":
			label.offset_left = 0
			label.offset_right = 60
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		elif mark == "00:20":
			label.offset_left = -60
			label.offset_right = 0
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var hint_row := HBoxContainer.new()
	rows.add_child(hint_row)
	var hint := _label("SPACE  Play / pause     ·     WHEEL  Zoom     ·     RIGHT DRAG  Pan", 13, Color("52677c"))
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_row.add_child(hint)
	var reset := _button("Reset camera  [Home]", hint_row)
	reset.pressed.connect(func(): reset_camera_requested.emit())

	error_label = _label("", 20, Color("b42338"))
	add_child(error_label)
	error_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	error_label.offset_left = -400
	error_label.offset_right = 400
	error_label.offset_top = -60
	error_label.offset_bottom = 60
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	error_label.hide()


func _label(text: String, font_size: int, color: Color = Color("23364a")) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String, parent: Node) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	parent.add_child(button)
	return button


func _box(color: Color, radius: int, horizontal: int, vertical: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.content_margin_left = horizontal
	style.content_margin_right = horizontal
	style.content_margin_top = vertical
	style.content_margin_bottom = vertical
	return style
