extends RefCounted
const Info = preload("res://scripts/application/AppInfo.gd")
var root := Info.data_root().path_join("replays")
func folder(hash: String) -> String: return root.path_join(hash)
func safe_hash(hash: String) -> bool:
	if hash.length() != 64: return false
	for c in hash:
		if not c in "0123456789abcdef": return false
	return true
func manifest(hash: String) -> Dictionary:
	var file := folder(hash).path_join("cache.json")
	if not FileAccess.file_exists(file): return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(file)) != OK: return {}
	return json.data if json.data is Dictionary else {}
func binary_path(hash: String) -> String: return folder(hash).path_join("replay.replay")
func path(hash: String) -> String:
	var name: String = str(manifest(hash).get("file_name", "replay.json"))
	# A cache manifest cannot redirect reads outside its own cache folder.
	return folder(hash).path_join(name if name in ["replay.json", "replay.replay"] else "replay.json")
func valid(hash: String) -> bool:
	if not safe_hash(hash): return false
	var m := manifest(hash)
	if m.get("file_name", "replay.json") not in ["replay.json", "replay.replay"]: return false
	if m.get("file_name") == "replay.replay" and m.get("storage_version") != 1: return false
	return FileAccess.file_exists(path(hash)) and m.get("demo_hash") == hash and (m.get("parser_version") == Info.PARSER_VERSION or (m.get("parser_version") == "0.6.0" and m.get("file_name", "replay.json") == "replay.json")) and m.get("replay_version") == 2 and m.get("replay_sha256", "") == FileAccess.get_sha256(path(hash))
func commit(hash: String, demo: String, replay_file := "") -> bool:
	if not safe_hash(hash): return false
	if replay_file.is_empty(): replay_file = path(hash)
	if replay_file not in [folder(hash).path_join("replay.json"), binary_path(hash)]: return false
	var f := FileAccess.open(demo, FileAccess.READ)
	if f == null: return false
	var data := {"demo_hash":hash,"demo_size":f.get_length(),"demo_last_modified":FileAccess.get_modified_time(demo),"parser_version":Info.PARSER_VERSION,"replay_version":2,"created_at":Time.get_datetime_string_from_system(),"source_demo_path":demo,"replay_sha256":FileAccess.get_sha256(replay_file),"file_name":replay_file.get_file(),"storage_version":1 if replay_file.get_extension() == "replay" else 0}
	f.close()
	if data.replay_sha256.is_empty(): return false
	var out := FileAccess.open(folder(hash).path_join("cache.json.tmp"), FileAccess.WRITE)
	if out == null: return false
	out.store_string(JSON.stringify(data,"  "));out.close()
	return DirAccess.rename_absolute(folder(hash).path_join("cache.json.tmp"),folder(hash).path_join("cache.json")) == OK
