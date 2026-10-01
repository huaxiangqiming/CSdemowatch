extends SceneTree
var checks := 0
var failures := []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); printerr(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var prefix := OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "ancient"
	var loader = load("res://scripts/core/ReplayLoader.gd").new()
	var baseline: Dictionary = loader.load_replay("res://../artifacts/m9/"+prefix+".json")
	var binary: Dictionary = loader.load_replay("res://../artifacts/m9/"+prefix+".replay")
	check(baseline.ok and binary.ok, "Both formats load")
	if not baseline.ok or not binary.ok: print(binary.error); quit(1); return
	var data: Dictionary = binary.data
	var stream = data.stream
	check(baseline.data.metadata == data.metadata and baseline.data.players == data.players, "Metadata and players unchanged")
	check(baseline.data.events.size() == data.events.size(), "Event counts unchanged")
	for i in data.events.size():
		var a = baseline.data.events[i]
		var b = data.events[i]
		for property in a.get_property_list():
			if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				check(a.get(property.name) == b.get(property.name), "Event property " + property.name + " / " + a.id)
	check(baseline.data.projectiles.size() == data.projectiles.size(), "Projectile counts unchanged")
	var sampler = load("res://scripts/core/TrackSampler.gd")
	var times := [0.0, 9.9999, 10.0, 10.0001, 20.0, 19.9999, data.metadata.duration]
	for i in 160: times.append(fmod(i * 791.791, data.metadata.duration))
	var maximum := 0.0
	for time in times:
		var start := Time.get_ticks_usec()
		var tracks: Dictionary = stream.tracks_at(time)
		maximum = maxf(maximum, (Time.get_ticks_usec()-start)/1000.0)
		check(not tracks.is_empty(), "Random seek loads")
		if tracks.is_empty(): print(stream.error); break
		for id in tracks:
			var a: Dictionary = sampler.sample(baseline.data.tracks[id], time)
			var b: Dictionary = sampler.sample(tracks[id], time)
			check(a.position.distance_to(b.position) < 0.04, "Quantized position within tolerance")
			check(absf(angle_difference(a.yaw,b.yaw)) < 0.00001, "Yaw within tolerance")
			for key in ["time","tick","health","alive","available","team"]: check(a[key] == b[key], "Exact discrete state: " + key)
		check(stream.cache.size() <= 3, "Bounded window cache")
	var file := FileAccess.open("res://../artifacts/m9/"+prefix+"-consistency-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"max_seek_ms":maximum,"resident_frames":stream.resident_frames,"total_chunks":stream.track_chunks.size()},"  "))
	print("M9 consistency ",checks," failures=",failures.size()," max_seek_ms=",maximum)
	quit(0 if failures.is_empty() else 1)
