extends RefCounted
const BACKGROUND := Color("e7ebe7")
const PANEL := Color("f3f5f2")
const INK := Color("23364a")
const MUTED := Color("52677c")
const ACCENT := Color("087e8b")
static func box(color: Color, margin := 12, radius := 8) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = color
	b.set_corner_radius_all(radius)
	b.set_content_margin_all(margin)
	return b
static func icon(svg: String) -> Texture2D:
	var image := Image.new()
	image.load_svg_from_string(svg)
	return ImageTexture.create_from_image(image)
static func theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15
	t.set_stylebox("panel", "PanelContainer", box(PANEL, 16))
	for kind in ["Label", "Button", "CheckBox", "CheckButton", "OptionButton", "LineEdit", "TextEdit", "PopupMenu", "TabBar", "Tree", "ItemList"]:
		for key in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color", "font_selected_color"]:
			t.set_color(key, kind, INK)
		t.set_color("font_disabled_color", kind, Color("748496"))
	for kind in ["Button", "OptionButton"]:
		for state in ["normal", "hover", "pressed", "disabled"]:
			var fill: Color = {"normal":Color("e3e9e7"),"hover":Color("d5e2de"),"pressed":Color("b8dfe3"),"disabled":Color("f0f3f7")}[state]
			t.set_stylebox(state, kind, box(fill, 10))
		var focus := box(Color(0,0,0,0), 10)
		focus.border_color = ACCENT; focus.set_border_width_all(2)
		t.set_stylebox("focus", kind, focus)
	for kind in ["CheckBox", "CheckButton"]:
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var fill := Color("e5f2f4") if state in ["pressed", "hover_pressed"] else Color(0,0,0,0)
			t.set_stylebox(state,kind,box(fill,4,4))
	for kind in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal",kind,box(Color("e3e9e7"),10))
		t.set_color("caret_color",kind,INK)
		t.set_color("font_placeholder_color",kind,MUTED)
		t.set_color("selection_color",kind,Color("b8dfe3"))
	t.set_stylebox("panel","PopupMenu",box(PANEL,8))
	t.set_stylebox("hover","PopupMenu",box(Color("d5e2de"),6))
	t.set_stylebox("panel","TabContainer",box(PANEL,10))
	for kind in ["TabContainer", "TabBar"]:
		t.set_stylebox("tab_selected",kind,box(PANEL,12))
		t.set_stylebox("tab_unselected",kind,box(Color("dce6ef"),12))
		t.set_stylebox("tab_hovered",kind,box(Color("e7f3f5"),12))
		t.set_color("font_selected_color",kind,INK)
		t.set_color("font_unselected_color",kind,MUTED)
		t.set_color("font_hovered_color",kind,INK)
	var unchecked := icon('<svg width="22" height="22" xmlns="http://www.w3.org/2000/svg"><rect x="3" y="3" width="16" height="16" rx="4" fill="#ffffff" stroke="#637a90" stroke-width="2"/></svg>')
	var checked := icon('<svg width="22" height="22" xmlns="http://www.w3.org/2000/svg"><rect x="2" y="2" width="18" height="18" rx="4" fill="#087e8b"/><path d="M6 11l3 3 7-7" fill="none" stroke="white" stroke-width="2"/></svg>')
	for key in ["unchecked", "unchecked_disabled"]: t.set_icon(key,"CheckBox",unchecked)
	for key in ["checked", "checked_disabled"]: t.set_icon(key,"CheckBox",checked)
	t.set_icon("off","CheckButton",unchecked);t.set_icon("on","CheckButton",checked)
	t.set_icon("arrow","OptionButton",icon('<svg width="18" height="18" xmlns="http://www.w3.org/2000/svg"><path d="M4 7l5 5 5-5" fill="none" stroke="#23364a" stroke-width="2"/></svg>'))
	t.set_stylebox("background","ProgressBar",box(Color("dce6ef"),0))
	t.set_stylebox("fill","ProgressBar",box(ACCENT,0))
	var slider := box(Color("c6d4e1"),0,3);slider.content_margin_top=3;slider.content_margin_bottom=3
	t.set_stylebox("slider","HSlider",slider)
	t.set_stylebox("grabber_area","HSlider",box(ACCENT,0,3))
	t.set_stylebox("grabber_area_highlight","HSlider",box(ACCENT,0,3))
	# Dialogs and file lists must not inherit Godot's dark fallback surfaces.
	for kind in ["AcceptDialog", "FileDialog", "Tree", "ItemList"]:
		var surface := box(Color("fafbf9"), 10, 6)
		surface.border_color = Color("bdc9c5"); surface.set_border_width_all(1)
		t.set_stylebox("panel", kind, surface)
	for kind in ["Tree", "ItemList"]:
		for key in ["selected", "selected_focus"]:
			t.set_stylebox(key, kind, box(Color("c5e5e7"), 4, 4))
		t.set_stylebox("hovered", kind, box(Color("e5efec"), 4, 4))
		t.set_color("font_outline_color", kind, Color.TRANSPARENT)
		t.set_color("guide_color", kind, Color("dce3df"))
		t.set_constant("v_separation", kind, 10)
	for key in ["embedded_border", "embedded_unfocused_border"]:
		var frame := box(PANEL, 12, 10)
		frame.expand_margin_top = 38
		frame.border_color = Color("aabbb6"); frame.set_border_width_all(1)
		t.set_stylebox(key, "Window", frame)
	t.set_color("title_color", "Window", INK)
	t.set_color("title_outline_modulate", "Window", Color.TRANSPARENT)
	t.set_constant("title_height", "Window", 38)
	t.set_font_size("title_font_size", "Window", 17)
	var close := icon('<svg width="20" height="20" xmlns="http://www.w3.org/2000/svg"><path d="M5 5l10 10M15 5L5 15" stroke="#23364a" stroke-width="2"/></svg>')
	t.set_icon("close", "Window", close); t.set_icon("close_pressed", "Window", close)
	t.set_color("folder_icon_color", "FileDialog", Color("527e90"))
	t.set_color("file_icon_color", "FileDialog", INK)
	t.set_color("file_disabled_color", "FileDialog", MUTED)
	return t
static func configure_file_dialog(dialog: FileDialog, title: String) -> void:
	dialog.theme = theme()
	dialog.title = title
	dialog.display_mode = FileDialog.DISPLAY_LIST
	dialog.get_ok_button().text = "选择"
	dialog.get_cancel_button().text = "取消"
	dialog.min_size = Vector2i(720, 460)
static func label(text: String, size := 16) -> Label:
	var node := Label.new(); node.text=text;node.add_theme_font_size_override("font_size",size);return node
static func button(text: String, callback: Callable) -> Button:
	var b := Button.new(); b.text=text;b.pressed.connect(callback);return b
static func content(parent: Control) -> VBoxContainer:
	var margin := MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,28)
	parent.add_child(margin)
	var center := CenterContainer.new();margin.add_child(center)
	var column := VBoxContainer.new();column.custom_minimum_size.x=740;column.add_theme_constant_override("separation",16);center.add_child(column)
	return column
