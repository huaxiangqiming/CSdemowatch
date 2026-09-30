extends RefCounted
## Source -> asset only. Existing MapAssetManager still owns readiness and loading.
const Discovery = preload("res://scripts/map/CS2InstallationDiscovery.gd")
var thread: Thread
var mutex := Mutex.new()
var cancelled := false
var status := ""
var map_name := ""
var output := ""
func can_prepare(name: String) -> bool:
	return name.begins_with("de_") and name.is_valid_filename() and FileAccess.file_exists(Discovery.tool_path())
func prepare(name: String, installation: String) -> Error:
	if thread != null or not can_prepare(name): return ERR_UNAVAILABLE
	map_name = name; cancelled = false; _status("Checking CS2 Installation")
	thread = Thread.new()
	return thread.start(_work.bind(name,installation))
func _status(value: String) -> void:
	mutex.lock();status=value;mutex.unlock()
func get_status() -> String:
	mutex.lock();var value:=status;mutex.unlock()
	var cache_root := OS.get_environment("CS2_MAP_CACHE_ROOT")
	if cache_root.is_empty(): cache_root = OS.get_environment("LOCALAPPDATA").path_join("CS2TacticalReplay/maps")
	var progress_path := cache_root.path_join(".status-"+map_name+".json")
	if value.begins_with("Preparing") and FileAccess.file_exists(progress_path):
		var parser:=JSON.new()
		if parser.parse(FileAccess.get_file_as_string(progress_path))==OK and parser.data is Dictionary and parser.data.has("stage"):return str(parser.data.stage)+" — "+map_name
	return value
func cancel_request() -> void:
	mutex.lock();cancelled=true;mutex.unlock()
func _cancelled() -> bool:
	mutex.lock();var value:=cancelled;mutex.unlock();return value
func _work(name: String, installation: String) -> Dictionary:
	var location:=Discovery.inspect(installation)
	if _cancelled():return {"ok":false,"cancelled":true}
	if not location.valid:return {"ok":false,"error":"CS2 installation not found. Tactical map unavailable.","error_code":"MAP_SOURCE_NOT_FOUND","details":location.message}
	_status("Preparing Tactical Map — " + name)
	var lines:=[]
	var code:=OS.execute(Discovery.tool_path(),PackedStringArray(["prepare",name,location.path]),lines,true,false)
	output="\n".join(lines)
	if _cancelled():return {"ok":false,"cancelled":true}
	var result:Dictionary={"ok":false,"error":"Map converter failed (%d). Continue using fallback plane." % code}
	for line in output.split("\n"):
		if line.strip_edges().is_empty():continue
		var parser:=JSON.new()
		if parser.parse(line)==OK and parser.data is Dictionary and parser.data.has("ok"):result=parser.data
	if code != 0:result.ok=false
	return result
func done() -> bool:return thread!=null and not thread.is_alive()
func finish() -> Dictionary:
	var result:Dictionary=thread.wait_to_finish();thread=null;return result
