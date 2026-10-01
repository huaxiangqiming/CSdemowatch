extends Control
signal back_requested
signal map_requested(name: String, rebuild: bool)
signal map_delete_requested(name: String)
signal log_requested
const Style = preload("res://scripts/application/ShellStyle.gd")
const Info = preload("res://scripts/application/AppInfo.gd")
var store: RefCounted
var grid: GridContainer
var scroll: ScrollContainer
var controls := {}
var discovery: RefCounted
var location_status: Label
var prepared_status: Label
var maps_list: VBoxContainer
var map_status_labels := {}
var browse: FileDialog
var check_delay := -1.0
var discovery_path := ""
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := Style.content(self)
	var header := HBoxContainer.new();box.add_child(header)
	var title:=Style.label("Settings",30);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(title)
	header.add_child(Style.button("Back",func():back_requested.emit()))
	scroll = ScrollContainer.new();scroll.custom_minimum_size.y=420;box.add_child(scroll)
	grid=GridContainer.new();grid.columns=2;grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL;grid.add_theme_constant_override("h_separation",36);grid.add_theme_constant_override("v_separation",9);scroll.add_child(grid)
	var tabs := {"MAPS":["cs2_path","auto_prepare_maps"],"VISUAL":["background_tone","name_size","player_scale","smoke_visibility","map_opacity","t_color","ct_color","player_status"],"CAMERA":["pan_speed","zoom_speed","orbit_sensitivity"],"DEFAULT LAYERS":["players","names","smoke","fire","grenades","trajectories","shots","kill_feed","bomb"]}
	var titles := {"background_tone":"Map & Background","cs2_path":"CS2 Installation Path","auto_prepare_maps":"Auto Prepare Maps","name_size":"Player Name Size","player_scale":"Player Scale","smoke_visibility":"Smoke Visibility","map_opacity":"Map Opacity","t_color":"T Accent","ct_color":"CT Accent","player_status":"Player Status Indicators","pan_speed":"Pan Speed","zoom_speed":"Zoom Speed","orbit_sensitivity":"Orbit Sensitivity","names":"Player Names","kill_feed":"Kill Feed"}
	for section in ["VISUAL", "CAMERA", "DEFAULT LAYERS", "MAPS"]:
		grid.add_child(Style.label(section,14));grid.add_child(Control.new())
		for key in tabs[section]:
			grid.add_child(Style.label(titles.get(key,key.capitalize())))
			var value = store.values[key]
			var control: Control
			if value is bool:
				var c:=CheckBox.new();c.button_pressed=value;c.toggled.connect(func(v):store.set_value(key,v));control=c
			elif key in ["t_color","ct_color"]:
				var c:=ColorPickerButton.new();c.color=Color(value);c.edit_alpha=false;c.text="#"+value;c.add_theme_color_override("font_color",Color(value));c.color_changed.connect(func(v):c.text="#"+v.to_html(false);c.add_theme_color_override("font_color",v);store.set_value(key,v.to_html(false)));control=c
			elif value is String:
				var c:=LineEdit.new();c.text=value;c.placeholder_text="Optional local installation folder";c.text_changed.connect(func(v):store.set_value(key,v);check_delay=0.5);control=c
			elif key in ["smoke_visibility","auto_prepare_maps","background_tone"]:
				var c:=OptionButton.new()
				for text in (["Ask","Auto","Never"] if key=="auto_prepare_maps" else (["Stone - soft neutral","Mist - cool gray","Slate - dim"] if key=="background_tone" else ["Low","Tactical","Strong"])):c.add_item(text)
				c.select(int(value));c.item_selected.connect(func(v):store.set_value(key,v));control=c
			else:
				var c:=SpinBox.new();var bounds:Array={"name_size":[10,24,1],"player_scale":[0.5,2,0.1],"map_opacity":[0.25,1,0.25]}.get(key,[0.25,3,0.25]);c.min_value=bounds[0];c.max_value=bounds[1];c.step=bounds[2];c.value=value;c.value_changed.connect(func(v):store.set_value(key,v));control=c
			control.custom_minimum_size.x=300;grid.add_child(control);controls[key]=control
		if section=="MAPS":
			grid.add_child(Style.label("Installation Status"));location_status=Style.label("Checking…",12);location_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;location_status.custom_minimum_size.x=300;grid.add_child(location_status)
			grid.add_child(Style.label("CS2 Folder"));grid.add_child(Style.button("Browse…",func():browse.popup_centered_ratio(0.7)))
			grid.add_child(Style.label("Prepared Maps"));prepared_status=Style.label("",12);grid.add_child(prepared_status)
			grid.add_child(Style.label("Map Library"));maps_list=VBoxContainer.new();grid.add_child(maps_list)
			grid.add_child(Style.label("Preparation Log"));grid.add_child(Style.button("View Log",func():log_requested.emit()))
			for kind in ["replays","maps"]:
				grid.add_child(Style.label("Replay Cache" if kind=="replays" else "Map Cache"))
				var folder:String=Info.data_root().path_join(kind) if kind == "replays" else preload("res://scripts/map/MapAssetCache.gd").new().root
				var b:=Style.button("Open Folder",func():DirAccess.make_dir_recursive_absolute(folder);OS.shell_open(folder));b.tooltip_text=folder;grid.add_child(b)
	box.add_child(Style.button("Reset to Default",func():store.reset_defaults();sync();check_delay=0.1))
	browse=FileDialog.new();browse.access=FileDialog.ACCESS_FILESYSTEM;browse.file_mode=FileDialog.FILE_MODE_OPEN_DIR;add_child(browse)
	browse.dir_selected.connect(func(path):store.set_value("cs2_path",path);sync();check_delay=0.1)
	check_delay=0.1
func sync() -> void:
	check_delay=0.1
	scroll.set_deferred("scroll_vertical",0)
	for key in controls:
		var c=controls[key];var value=store.values[key]
		c.set_block_signals(true)
		if c is CheckBox:c.button_pressed=value
		elif c is ColorPickerButton:c.color=Color(value);c.text="#"+value;c.add_theme_color_override("font_color",Color(value))
		elif c is LineEdit:c.text=value
		elif c is OptionButton:c.select(int(value))
		else:c.value=value
		c.set_block_signals(false)

func _process(delta: float) -> void:
	if discovery != null and discovery.done():
		var result:Dictionary=discovery.finish();discovery=null
		if discovery_path!=store.values.cs2_path:check_delay=0.1
		location_status.text=("Valid / " + result.get("source","Detected") + "\n" + result.path) if result.valid else "Invalid / " + result.message
		if result.valid and store.values.cs2_path.is_empty():
			store.set_value("cs2_path",result.path);controls.cs2_path.text=result.path
	if check_delay < 0: return
	check_delay-=delta
	if check_delay<=0 and discovery==null:
		check_delay=-1;discovery=preload("res://scripts/map/CS2InstallationDiscovery.gd").new()
		discovery_path=store.values.cs2_path
		if discovery.start(discovery_path)!=OK:discovery=null;location_status.text="Could not start path validation."
		var cache=preload("res://scripts/map/MapAssetCache.gd").new()
		var ready:=[]
		var folders:=DirAccess.get_directories_at(cache.root) if DirAccess.dir_exists_absolute(cache.root) else PackedStringArray()
		for folder in folders:
			if not folder.begins_with("."):ready.append(folder + (" — Ready" if cache.is_map_ready(folder) else " — Not prepared"))
		prepared_status.text="\n".join(ready) if not ready.is_empty() else "None — fallback remains available"
		refresh_maps()
func refresh_maps() -> void:
	if maps_list==null:return
	for child in maps_list.get_children():maps_list.remove_child(child);child.queue_free()
	map_status_labels.clear()
	var catalog=JSON.parse_string(FileAccess.get_file_as_string("res://maps/catalog.json"))
	var cache=preload("res://scripts/map/MapAssetCache.gd").new()
	for entry in catalog:
		var name:String=entry.map
		var label:=Style.label(name+" — "+("Ready" if cache.is_map_ready(name) else "Not Prepared")+"\n"+str(entry.get("status", "Verified" if entry.verified else "Fallback supported — Automatic preparation")),12)
		maps_list.add_child(label);map_status_labels[name]=label
		var row:=HBoxContainer.new();maps_list.add_child(row)
		row.add_child(Style.button("Prepare",func():map_requested.emit(name,false)))
		row.add_child(Style.button("Rebuild",func():map_requested.emit(name,true)))
		row.add_child(Style.button("Delete Cache",func():map_delete_requested.emit(name)))
func _exit_tree() -> void:
	if discovery!=null:discovery.finish()
