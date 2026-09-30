extends RefCounted
const Info = preload("res://scripts/application/AppInfo.gd")
var entries: Array = []
var path := Info.data_root().path_join("recent_replays.json")
func load_entries() -> void:
	entries.clear()
	if not FileAccess.file_exists(path): return
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or data.get("version") != 1 or not data.get("replays") is Array: return
	for e in data.replays:
		if e is Dictionary and e.get("demo_path") is String and e.get("demo_hash") is String and e.get("map") is String and (e.get("duration") is float or e.get("duration") is int): entries.append(e)
	entries = entries.slice(0,15)
func opened(demo: String, hash: String, metadata: Dictionary) -> void:
	entries = entries.filter(func(e): return e.demo_hash != hash)
	entries.push_front({"demo_path":demo,"demo_hash":hash,"file_name":demo.get_file(),"map":metadata.map,"duration":metadata.duration,"last_opened":Time.get_datetime_string_from_system(),"replay_cache_key":hash})
	entries = entries.slice(0,15)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"version":1,"replays":entries},"  ")); file.close(); DirAccess.rename_absolute(path+".tmp",path)
