extends RefCounted
## Read-only Windows Steam discovery/validation runs outside the UI thread.
var thread: Thread
static func tool_path() -> String:
	if OS.has_feature("standalone"): return OS.get_executable_path().get_base_dir().path_join("cs2maptool.exe")
	return ProjectSettings.globalize_path("res://../parser/bin/cs2maptool.exe")
static func inspect(path: String) -> Dictionary:
	if not FileAccess.file_exists(tool_path()): return {"valid":false,"path":"","message":"Map preparation tool is missing."}
	var output := []
	var code := OS.execute(tool_path(), PackedStringArray(["discover",path]), output, true, false)
	if code == 0:
		var result = JSON.parse_string("\n".join(output))
		if result is Dictionary: return result
	return {"valid":false,"path":"","message":"Could not inspect the CS2 installation."}
func start(path: String) -> Error:
	thread = Thread.new()
	return thread.start(func():return inspect(path))
func done() -> bool: return thread != null and not thread.is_alive()
func finish() -> Dictionary:
	var result: Dictionary = thread.wait_to_finish(); thread = null; return result
