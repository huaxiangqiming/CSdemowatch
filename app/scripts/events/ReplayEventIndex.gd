extends RefCounted
## One-second interval buckets + binary search, independent of playback history.
var events: Array = []
var shots: Array = []
var kills: Array = []
var smoke_buckets := {}
var fire_buckets := {}
var pulse_buckets := {}
var projectile_buckets := {}
var total_projectiles := 0

func build(replay: Dictionary) -> void:
	events = replay.get("events", [])
	shots.clear(); kills.clear()
	smoke_buckets.clear(); fire_buckets.clear(); pulse_buckets.clear(); projectile_buckets.clear()
	for event in events:
		match event.type:
			"smoke": _insert(smoke_buckets, event, event.time, event.expire_time)
			"fire": _insert(fire_buckets, event, event.time, event.expire_time)
			"he", "flash": _insert(pulse_buckets, event, event.time, event.expire_time)
			"shot": shots.append(event)
			"kill": kills.append(event)
	total_projectiles = replay.get("projectiles", []).size()
	for projectile in replay.get("projectiles", []):
		_insert(projectile_buckets, projectile, projectile.throw_time, projectile.end_time)

func _insert(buckets: Dictionary, item: RefCounted, start: float, end: float) -> void:
	for second in range(int(floor(start)), int(floor(end)) + 1):
		if not buckets.has(second): buckets[second] = []
		buckets[second].append(item)

func _active(buckets: Dictionary, time: float, projectile := false) -> Array:
	var result: Array = []
	for item in buckets.get(int(floor(time)), []):
		var start: float = item.throw_time if projectile else item.time
		var end: float = item.end_time if projectile else item.expire_time
		if time >= start and time < end: result.append(item)
	return result

func _upper(items: Array, time: float) -> int:
	var lo := 0
	var hi := items.size()
	while lo < hi:
		var mid := (lo + hi) / 2
		if items[mid].time <= time: lo = mid + 1
		else: hi = mid
	return lo

func get_active_smoke(time: float) -> Array: return _active(smoke_buckets, time)
func get_active_fire(time: float) -> Array: return _active(fire_buckets, time)
func get_active_pulses(time: float) -> Array: return _active(pulse_buckets, time)
func get_active_projectiles(time: float) -> Array: return _active(projectile_buckets, time, true)
func get_recent_shots(time: float, window := 0.12) -> Array:
	return shots.slice(_upper(shots, time - window), _upper(shots, time))
func get_recent_kills(time: float, count := 8) -> Array:
	var end := _upper(kills, time)
	var result := kills.slice(maxi(0, end - count), end)
	result.reverse()
	return result
func get_events_around(time: float, window := 0.5) -> Array:
	return events.slice(_upper(events, time - window), _upper(events, time + window))
