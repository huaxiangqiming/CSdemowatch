extends PanelContainer
var camera: Node3D
var map_manager: Node3D
var controller: Node3D
var mode: OptionButton
var opacity: OptionButton
var projection_button: Button
var info: Label
var cutaway: CheckButton
var height_slider: HSlider
var height_label: Label
var cutaway_map := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -304
	offset_right = -20
	offset_top = 110
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)
	var title := Label.new()
	title.text = "TACTICAL VIEW"
	column.add_child(title)
	mode = OptionButton.new()
	for value in ["Normal", "X-Ray", "Tactical"]:
		mode.add_item(value)
	mode.select(1)
	mode.item_selected.connect(func(_i): apply_mode())
	column.add_child(mode)
	opacity = OptionButton.new()
	for value in ["Map opacity: 100%", "Map opacity: 75%", "Map opacity: 50%", "Map opacity: 25%"]:
		opacity.add_item(value)
	opacity.item_selected.connect(func(i): map_manager.set_opacity([1.0, 0.75, 0.5, 0.25][i]))
	column.add_child(opacity)
	cutaway = CheckButton.new()
	cutaway.text = "Height cutaway"
	cutaway.tooltip_text = "Hide geometry above the chosen height to inspect lower floors. Map data is preserved."
	column.add_child(cutaway)
	height_label = Label.new()
	height_label.add_theme_font_size_override("font_size", 12)
	column.add_child(height_label)
	height_slider = HSlider.new()
	height_slider.step = 0.1
	column.add_child(height_slider)
	cutaway.toggled.connect(func(_enabled): _apply_cutaway())
	height_slider.value_changed.connect(func(_value): _apply_cutaway())
	var row := HBoxContainer.new()
	column.add_child(row)
	for i in 3:
		var button := Button.new()
		button.text = ["1 Top", "2 45°", "3 Free"][i]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func(): camera.set_preset(i + 1))
		row.add_child(button)
	projection_button = Button.new()
	projection_button.focus_mode = Control.FOCUS_NONE
	projection_button.pressed.connect(func(): camera.toggle_projection())
	column.add_child(projection_button)
	var help := Label.new()
	help.text = "Wheel: zoom  ·  Right drag: pan\nMiddle / Alt + Left drag: orbit\nHome: reset  ·  P: projection"
	help.add_theme_font_size_override("font_size", 13)
	column.add_child(help)
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.x = 275
	info.add_theme_font_size_override("font_size", 12)
	column.add_child(info)

func bind_view(rig: Node3D, manager: Node3D, replay_controller: Node3D) -> void:
	camera = rig
	map_manager = manager
	controller = replay_controller

func apply_mode() -> void:
	if controller == null:
		return
	map_manager.set_view_mode(mode.selected)
	for player in controller.player_views.values():
		player.set_view_mode(mode.selected)

func _apply_cutaway() -> void:
	if map_manager == null: return
	map_manager.set_cutaway(cutaway.button_pressed, height_slider.value)
	height_slider.visible = cutaway.button_pressed
	height_label.visible = cutaway.button_pressed
	height_label.text = "Cut height: %.1f" % height_slider.value

func _process(_delta: float) -> void:
	if camera == null:
		return
	var map_key: String = map_manager.loaded_map + ("/ready" if map_manager.model != null else "/fallback")
	if cutaway_map != map_key:
		cutaway_map = map_key
		height_slider.set_block_signals(true)
		height_slider.min_value = minf(map_manager.map_bounds.position.y, map_manager.cutaway_height)
		height_slider.max_value = maxf(map_manager.map_bounds.end.y + 1.0, map_manager.cutaway_height)
		height_slider.value = map_manager.cutaway_height
		height_slider.set_block_signals(false)
		cutaway.set_pressed_no_signal(map_manager.cutaway_enabled)
		height_slider.visible = cutaway.button_pressed
		height_label.visible = cutaway.button_pressed
		height_label.text = "Cut height: %.1f" % height_slider.value
	projection_button.text = ("Perspective" if camera.perspective else "Orthographic") + "  [P]"
	info.text = map_manager.status + ("\nTactical caps map opacity at 50%." if mode.selected == 2 else "")
