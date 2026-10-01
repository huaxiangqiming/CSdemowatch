extends SceneTree
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path := args[0]
	var before := OS.get_static_memory_usage()
	var start := Time.get_ticks_usec()
	var result = load("res://scripts/core/ReplayLoader.gd").new().load_replay(path)
	var elapsed := (Time.get_ticks_usec() - start) / 1000.0
	if not result.ok: printerr(result.error); quit(1); return
	var frames := 0
	for track in result.data.tracks.values(): frames += track.size()
	var report := {"path":path.get_file(),"load_ms":elapsed,"static_memory_delta_bytes":OS.get_static_memory_usage()-before,"static_peak_bytes":OS.get_static_memory_peak_usage(),"initial_resident_frames":frames,"event_count":result.data.events.size()}
	var file := FileAccess.open(args[1],FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")); print(JSON.stringify(report))
	quit()
