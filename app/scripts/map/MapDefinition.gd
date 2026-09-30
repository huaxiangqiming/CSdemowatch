extends RefCounted
var map_name := ""
var model_path := ""
var scale := 0.01
var rotation := 0.0
var offset := Vector3.ZERO
var error := ""
var file_path := ""
var source_identifier := ""
var cache_version := 0
var bounds := {}
var default_camera := {"yaw": 38.0, "pitch": 45.0}

func load_file(path: String) -> bool:
	file_path = path
	var json := JSON.new()
	if not FileAccess.file_exists(path) or json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		error = "Missing or invalid map definition: " + path
		return false
	var data: Dictionary = json.data
	for key in ["map", "model_path", "scale", "rotation", "offset"]:
		if not data.has(key):
			error = "Map definition missing " + key
			return false
	if not data.map is String or not data.model_path is String or not (data.scale is float or data.scale is int) or not (data.rotation is float or data.rotation is int) or not data.offset is Array:
		error = "Invalid map definition types"
		return false
	if data.offset.size() != 3 or not is_finite(float(data.scale)) or float(data.scale) <= 0 or not is_finite(float(data.rotation)):
		error = "Invalid map transform"
		return false
	for value in data.offset:
		if not (value is float or value is int) or not is_finite(float(value)):
			error = "Invalid map offset"
			return false
	map_name = data.map
	source_identifier = str(data.get("source_identifier", "local-prepared-v1"))
	cache_version = int(data.get("cache_version", 0))
	bounds = data.get("bounds", {}) if data.get("bounds", {}) is Dictionary else {}
	if data.has("default_camera"):
		if not data.default_camera is Dictionary: return false
		for key in ["yaw", "pitch"]:
			var value = data.default_camera.get(key)
			if not (value is float or value is int) or not is_finite(float(value)): return false
		default_camera = data.default_camera
	model_path = path.get_base_dir().path_join(data.model_path)
	scale = data.scale
	rotation = data.rotation
	offset = Vector3(data.offset[0], data.offset[1], data.offset[2])
	return true

func create_transform() -> RefCounted:
	var result = preload("res://scripts/map/MapTransform.gd").new()
	result.scale_factor = scale
	result.rotation_degrees = rotation
	result.offset = offset
	return result
