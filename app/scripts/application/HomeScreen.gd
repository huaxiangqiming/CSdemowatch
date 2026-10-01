extends Control
signal open_requested
signal settings_requested
signal recent_requested(entry: Dictionary)
const Style = preload("res://scripts/application/ShellStyle.gd")
const Info = preload("res://scripts/application/AppInfo.gd")
var list: VBoxContainer
var hint: Label
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := Style.content(self)
	var brand := HBoxContainer.new();column.add_child(brand)
	var title := Style.label(Info.TITLE,32);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;brand.add_child(title)
	brand.add_child(Style.label("v"+Info.VERSION,14))
	column.add_child(Style.label(Info.SUBTITLE,18))
	var panel := PanelContainer.new();column.add_child(panel)
	var drop := VBoxContainer.new();drop.add_theme_constant_override("separation",15);panel.add_child(drop)
	var heading := Style.label("Your match. A clearer perspective.",26);heading.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;drop.add_child(heading)
	var detail := Style.label("Drop a CS2 .dem here to explore movement, utility and every engagement.");detail.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;drop.add_child(detail)
	var button := Style.button("Open Demo",func():open_requested.emit());button.custom_minimum_size.y=54;drop.add_child(button)
	hint=Style.label(".dem files  •  Local processing  •  No account required",14);hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;drop.add_child(hint)
	column.add_child(Style.label("Recent Replays",20))
	var scroll := ScrollContainer.new();scroll.custom_minimum_size.y=160;column.add_child(scroll)
	list=VBoxContainer.new();list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(list)
	var footer := HBoxContainer.new();column.add_child(footer)
	footer.add_child(Style.button("Settings",func():settings_requested.emit()))
	var note := Style.label("Offline tactical workspace",14);note.size_flags_horizontal=Control.SIZE_EXPAND_FILL;note.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;footer.add_child(note)
func refresh(entries: Array) -> void:
	for child in list.get_children(): list.remove_child(child);child.queue_free()
	if entries.is_empty(): list.add_child(Style.label("Your recently opened matches will appear here.",14))
	var map_ready:={}
	var cache=preload("res://scripts/map/MapAssetCache.gd").new()
	for entry in entries:
		var missing := not FileAccess.file_exists(entry.demo_path)
		var seconds := int(entry.duration)
		var text := "%s   %02d:%02d   %s   %s%s" % [entry.map,seconds/60,seconds%60,entry.get("file_name","Demo"),entry.get("last_opened","").replace("T"," "),"  • Source missing; try cache" if missing else ""]
		if not map_ready.has(entry.map):map_ready[entry.map]=cache.is_map_ready(entry.map)
		text += "  • " + ("Map Ready" if map_ready[entry.map] else "Map Missing")
		var b := Style.button(text,func():recent_requested.emit(entry));b.alignment=HORIZONTAL_ALIGNMENT_LEFT;b.clip_text=true;b.tooltip_text=text;list.add_child(b)
