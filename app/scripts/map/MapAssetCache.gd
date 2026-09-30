extends RefCounted
## Versioned map storage and integrity checks, independent of Replay files.
const CACHE_VERSION := 1
const CONVERTER_VERSION := "0.8.1"
const CLASSIFIER_VERSION := "2"
var root := ""
var last_error := ""
func _init(cache_root := "") -> void:
	var local := OS.get_environment("LOCALAPPDATA")
	if cache_root.is_empty(): cache_root=OS.get_environment("CS2_MAP_CACHE_ROOT")
	root = cache_root if not cache_root.is_empty() else (local.path_join("CS2TacticalReplay/maps") if not local.is_empty() else ProjectSettings.globalize_path("user://maps"))
func _json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var value = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}
func _safe(name: String) -> bool:
	return name.is_valid_filename() and name != "." and name != ".." and name.begins_with("de_")
func definition_path(name: String) -> String: return root.path_join(name).path_join("map.json")
func is_map_ready(name: String) -> bool:
	if not _safe(name): return false
	var folder := root.path_join(name)
	var cache := _json(folder.path_join("cache.json"))
	var source := _json("res://maps/%s/source.json" % name)
	if cache.get("cache_version") != CACHE_VERSION or cache.get("map") != name: return false
	# Legacy assets also need the visibility classifier; otherwise Ancient silently
	# bypasses roof cleanup forever. Replay caches are independent.
	if cache.get("converter_version", "") != CONVERTER_VERSION or str(cache.get("classifier_version", "")) != CLASSIFIER_VERSION: return false
	for stamp in cache.get("source_files", []):
		# A prepared asset remains usable offline if CS2 was uninstalled.
		if FileAccess.file_exists(str(stamp.path)):
			if FileAccess.get_modified_time(str(stamp.path)) != int(stamp.mtime):return false
			var source_file:=FileAccess.open(str(stamp.path),FileAccess.READ)
			if source_file==null or source_file.get_length()!=int(stamp.size):return false
	if not cache.has("converter_version") and not source.is_empty() and str(cache.get("source_identifier", "")).to_lower() != str(source.get("source_sha256", "")).to_lower(): return false
	var definition = preload("res://scripts/map/MapDefinition.gd").new()
	if not definition.load_file(definition_path(name)) or definition.map_name != name: return false
	if definition.model_path.simplify_path() != folder.path_join("map.glb").simplify_path(): return false
	return FileAccess.file_exists(definition.model_path) and FileAccess.get_sha256(definition.model_path) == cache.get("mesh_sha256", "")
func get_map_definition(name: String) -> RefCounted:
	var definition = preload("res://scripts/map/MapDefinition.gd").new()
	return definition if definition.load_file(definition_path(name)) else null
func load_map(name: String) -> Dictionary:
	if not is_map_ready(name): return {"ok": false, "error": "Tactical map unavailable: cache missing or invalid"}
	return {"ok": true, "path": definition_path(name), "cache_hit": true}

func delete_map(name: String) -> bool:
	if not _safe(name):return false
	var directory:=DirAccess.open(root)
	if directory==null:return true
	if directory.is_link(name):return false
	var folder:=root.path_join(name)
	# Delete only our generated files. Never recursively delete arbitrary content.
	for file in ["cache.json","map.json","map.glb","map.glb.classification.json","map.glb.roofs.glb"]:
		var path:=folder.path_join(file)
		if FileAccess.file_exists(path) and DirAccess.remove_absolute(path)!=OK:return false
	DirAccess.remove_absolute(folder)
	return true
