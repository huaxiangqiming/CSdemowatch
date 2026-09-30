extends RefCounted
const Info = preload("res://scripts/application/AppInfo.gd")
var root := Info.data_root().path_join("replays")
func folder(hash: String) -> String: return root.path_join(hash)
func safe_hash(hash: String) -> bool:
	if hash.length() != 64: return false
	for c in hash:
		if not c in "0123456789abcdef": return false
	return true
func path(hash: String) -> String: return folder(hash).path_join("replay.json")
func valid(hash: String) -> bool:
	if not safe_hash(hash): return false
	var file := folder(hash).path_join("cache.json")
	if not FileAccess.file_exists(file) or not FileAccess.file_exists(path(hash)): return false
	var m = JSON.parse_string(FileAccess.get_file_as_string(file))
	return m is Dictionary and m.get("demo_hash") == hash and m.get("parser_version") == Info.PARSER_VERSION and m.get("replay_version") == 2 and m.get("replay_sha256", "") == FileAccess.get_sha256(path(hash))
func commit(hash: String, demo: String) -> bool:
	var f := FileAccess.open(demo,FileAccess.READ)
	if f == null: return false
	var manifest := {"demo_hash":hash,"demo_size":f.get_length(),"demo_last_modified":FileAccess.get_modified_time(demo),"parser_version":Info.PARSER_VERSION,"replay_version":2,"created_at":Time.get_datetime_string_from_system(),"source_demo_path":demo,"replay_sha256":FileAccess.get_sha256(path(hash))}
	f.close()
	var out := FileAccess.open(folder(hash).path_join("cache.json.tmp"),FileAccess.WRITE)
	if out == null: return false
	out.store_string(JSON.stringify(manifest,"  "));out.close()
	return DirAccess.rename_absolute(folder(hash).path_join("cache.json.tmp"),folder(hash).path_join("cache.json")) == OK
