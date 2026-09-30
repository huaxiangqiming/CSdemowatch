extends RefCounted
const INK := Color("101722")
const PANEL := Color("172331")
const ACCENT := Color("63d6c7")
static func theme() -> Theme:
	var t := Theme.new(); t.default_font_size = 16
	var bg := StyleBoxFlat.new(); bg.bg_color = PANEL; bg.set_corner_radius_all(10); bg.set_content_margin_all(18)
	t.set_stylebox("panel","PanelContainer",bg)
	for state in ["normal","hover","pressed","focus"]:
		var b := StyleBoxFlat.new(); b.bg_color = Color("24384b") if state == "normal" else Color("31516a"); b.set_corner_radius_all(6); b.set_content_margin_all(12)
		t.set_stylebox(state,"Button",b)
	t.set_color("font_color","Label",Color("e3edf5")); t.set_color("font_color","Button",Color("e3edf5"))
	return t
static func label(text: String, size := 16) -> Label:
	var node := Label.new(); node.text=text;node.add_theme_font_size_override("font_size",size);return node
static func button(text: String, callback: Callable) -> Button:
	var b := Button.new(); b.text=text;b.pressed.connect(callback);return b
static func content(parent: Control) -> VBoxContainer:
	var margin := MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,32)
	parent.add_child(margin)
	var center := CenterContainer.new();margin.add_child(center)
	var column := VBoxContainer.new();column.custom_minimum_size.x=720;column.add_theme_constant_override("separation",16);center.add_child(column)
	return column
