extends RefCounted
## Strict JSON boundary. Returns {ok, data, error}; no partial replay on failure.

func load_replay(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _error("Cannot open replay: %s (error %s)" % [path, FileAccess.get_open_error()])
	return parse_text(file.get_as_text())


func parse_text(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		return _error("Invalid JSON on line %d: %s" % [json.get_error_line(), json.get_error_message()])
	return validate(json.data)


func validate(raw: Variant) -> Dictionary:
	return preload("res://scripts/core/ReplayValidator.gd").new().validate(raw)


func _error(message: String) -> Dictionary:
	return {"ok": false, "data": {}, "error": message}
