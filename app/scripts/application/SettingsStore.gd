extends RefCounted
signal changed
const Info = preload("res://scripts/application/AppInfo.gd")
const DEFAULTS := {"cs2_path":"", "auto_prepare_maps":1, "name_size":14.0, "player_scale":1.0, "smoke_visibility":1, "map_opacity":1.0, "t_color":"ffb454", "ct_color":"66b9ff", "pan_speed":1.0, "zoom_speed":1.0, "orbit_sensitivity":1.0, "players":true, "names":true, "player_status":true, "smoke":true, "fire":true, "grenades":true, "trajectories":true, "shots":true, "kill_feed":true, "bomb":true}
var values := DEFAULTS.duplicate(true)
var error := ""
var path := Info.data_root().path_join("settings.json")
func load_settings() -> void:
	values = DEFAULTS.duplicate(true)
	if FileAccess.file_exists(path):
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary:
			for key in DEFAULTS:
				if data.has(key): _assign(key,data[key])
func _assign(key: String, value: Variant) -> void:
	if not DEFAULTS.has(key): return
	var d = DEFAULTS[key]
	if d is bool and value is bool: values[key] = value
	elif d is String and value is String:
		if key in ["t_color","ct_color"] and not Color.html_is_valid(value): return
		values[key] = value
	elif (d is float or d is int) and (value is float or value is int) and is_finite(value):
		var bounds: Array = {"name_size":[10,24],"player_scale":[0.5,2],"smoke_visibility":[0,2],"auto_prepare_maps":[0,2],"map_opacity":[0.25,1],"pan_speed":[0.25,3],"zoom_speed":[0.25,3],"orbit_sensitivity":[0.25,3]}.get(key,[0,1])
		values[key] = clampf(value,bounds[0],bounds[1])
func set_value(key: String, value: Variant) -> void:
	_assign(key,value); save(); changed.emit()
func save() -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path+".tmp", FileAccess.WRITE)
	if file == null: error = "Cannot save settings."; return false
	file.store_string(JSON.stringify(values,"  ")); file.close()
	var ok := DirAccess.rename_absolute(path+".tmp",path) == OK
	error = "" if ok else "Cannot replace settings file."
	return ok
func reset_defaults() -> void:
	values = DEFAULTS.duplicate(true); save(); changed.emit()
