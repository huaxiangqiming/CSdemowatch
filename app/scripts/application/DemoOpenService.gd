extends RefCounted
## Worker owns hashing, hidden child process, validation and map preparation.
## Cancel is cooperative at phase boundaries; never kill a Thread.
const Info = preload("res://scripts/application/AppInfo.gd")
var cache = preload("res://scripts/application/ReplayCache.gd").new()
var thread := Thread.new()
var mutex := Mutex.new()
var status := "Checking Replay Cache"
var cancelled := false
var result := {}
var parser_output := ""
var parser_exit := -1
var cache_hit := false
var demo_hash := ""
var replay_path := ""
var log_lines: Array = []
var parser_override := ""
func stage(value: String) -> void:
	mutex.lock(); status = value; mutex.unlock(); log_lines.append(value)
func get_status() -> String:
	mutex.lock(); var value := status; mutex.unlock(); return value
func cancel() -> void:
	mutex.lock(); cancelled = true; mutex.unlock()
func is_cancelled() -> bool:
	mutex.lock(); var value := cancelled; mutex.unlock(); return value
func start(path: String, recent_hash := "") -> Error: return thread.start(_work.bind(path,recent_hash))
func done() -> bool: return thread.is_started() and not thread.is_alive()
func finish() -> Dictionary:
	if thread.is_started(): thread.wait_to_finish()
	return result
func fail(code: String, text: String, details := "") -> void:
	result = {"ok":false,"error":preload("res://scripts/application/AppError.gd").new(code,text,details)}
func _work(demo: String, recent_hash: String) -> void:
	if demo.get_extension().to_lower() != "dem": fail("INVALID_FILE","Please choose a CS2 .dem file."); return
	stage("Checking Replay Cache")
	var exists := FileAccess.file_exists(demo)
	demo_hash = FileAccess.get_sha256(demo) if exists else recent_hash
	if not cache.safe_hash(demo_hash): fail("MISSING_FILE","This demo is missing or cannot be read. Please locate it again."); return
	log_lines.append("Demo hash: " + demo_hash)
	cache_hit = cache.valid(demo_hash)
	log_lines.append("Cache hit" if cache_hit else "Cache miss / invalid")
	replay_path = cache.path(demo_hash)
	for attempt in 2:
		if is_cancelled(): result = {"ok":false,"cancelled":true}; return
		if not cache_hit or attempt == 1:
			if not exists: fail("MISSING_FILE","The original demo is missing and no valid cached replay is available."); return
			var parser := parser_override if not parser_override.is_empty() else Info.parser_path()
			if not FileAccess.file_exists(parser): fail("PARSER_MISSING","Parser component unavailable. Restore the application files.",parser); return
			if DirAccess.make_dir_recursive_absolute(cache.folder(demo_hash)) != OK: fail("CACHE_WRITE","Cannot create the replay cache folder."); return
			stage("Parsing Demo" if attempt == 0 else "Cache invalid. Rebuilding Demo")
			var output: Array = []
			log_lines.append("Parser start")
			# read_stderr combines both streams; open_console=false suppresses a window.
			parser_exit = OS.execute(parser, PackedStringArray([demo,replay_path]),output,true,false)
			parser_output = "\n".join(output)
			log_lines.append("Parser end: %d\n%s" % [parser_exit,parser_output])
			if parser_exit != 0: fail("PARSER_FAILED","This demo could not be parsed. It may be damaged or use an unsupported version.",parser_output); return
		if is_cancelled(): result = {"ok":false,"cancelled":true}; return
		stage("Loading Replay")
		var loader = preload("res://scripts/core/ReplayLoadJob.gd").new()
		# Run its pure worker body in this worker, avoiding nested scene-tree access.
		loader.status_callback = stage
		loader._work(replay_path)
		result = loader.result
		if result.ok:
			if not cache_hit or attempt == 1:
				if not cache.commit(demo_hash,demo): fail("CACHE_WRITE","Replay parsed, but its cache could not be saved."); return
			result.replay_path = replay_path; result.demo_hash = demo_hash
			return
		cache_hit = false
	fail("REPLAY_INVALID","The parsed replay is not valid.",str(result.get("error","")))
