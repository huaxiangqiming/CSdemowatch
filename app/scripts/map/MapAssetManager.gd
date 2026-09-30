extends "res://scripts/map/MapAssetCache.gd"
## Installs prepared local assets on a cache miss; never extracts per Replay.
func _init(cache_root := "") -> void:
	super(cache_root)

func prepare_map(name: String) -> Dictionary:
	if not _safe(name): return {"ok": false, "error": "Unsupported map name"}
	if is_map_ready(name): return load_map(name)
	if not _json(root.path_join(name).path_join("cache.json")).is_empty():
		return {"ok":false,"error":"Tactical map cache is stale. Using fallback while preparing."}
	var bundled := "res://maps/" + name
	var definition := _json(bundled.path_join("map.json"))
	if definition.get("converter_version", "") != CONVERTER_VERSION or str(definition.get("classifier_version", "")) != CLASSIFIER_VERSION:
		return {"ok": false, "error": "Tactical map needs preparation with current visibility classifier."}
	var source := _json(bundled.path_join("source.json"))
	if definition.is_empty() or not FileAccess.file_exists(bundled.path_join("map.glb")):
		return {"ok": false, "error": "Tactical map unavailable. Prepare local assets first; use Debug Plane. Ancient: tools/import-ancient.ps1"}
	var folder := root.path_join(name)
	if DirAccess.make_dir_recursive_absolute(folder) != OK: return {"ok": false, "error": "Cannot create map cache"}
	var mesh := folder.path_join("map.glb")
	var temp := folder.path_join("map.glb.tmp")
	if DirAccess.copy_absolute(ProjectSettings.globalize_path(bundled.path_join("map.glb")), temp) != OK: return {"ok": false, "error": "Cannot copy prepared tactical mesh"}
	var hash := FileAccess.get_sha256(temp)
	if hash.is_empty() or DirAccess.rename_absolute(temp, mesh) != OK: return {"ok": false, "error": "Cannot commit tactical mesh"}
	definition.model_path = "map.glb"
	definition.source_identifier = source.get("source_sha256", "local-prepared-v1")
	definition.cache_version = CACHE_VERSION
	definition.default_camera = definition.get("default_camera", {"yaw": 38, "pitch": 45})
	var manifest := {"cache_version": CACHE_VERSION, "map": name, "source_identifier": definition.source_identifier, "mesh_sha256": hash, "prepared_unix": Time.get_unix_time_from_system()}
	for pair in [["map.json", definition], ["cache.json", manifest]]:
		var file := FileAccess.open(folder.path_join(pair[0]), FileAccess.WRITE)
		if file == null: return {"ok": false, "error": "Cannot write map cache metadata"}
		file.store_string(JSON.stringify(pair[1], "  ")); file.close()
	return {"ok": true, "path": definition_path(name), "cache_hit": false}
