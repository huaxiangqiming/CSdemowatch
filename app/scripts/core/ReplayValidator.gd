extends RefCounted
## V1/V2 validation and in-memory decoding; no coordinate conversion here.

func validate(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return _error("Replay root must be an object.")
	if not _number(raw.get("version")) or (raw.version != 1 and raw.version != 2):
		return _error("Unsupported replay version; expected version 1 or 2.")
	var metadata: Variant = raw.get("metadata")
	if not metadata is Dictionary:
		return _error("Missing metadata.")
	if not metadata.get("map") is String or metadata.map.strip_edges().is_empty():
		return _error("metadata.map is required.")
	if not _number(metadata.get("duration")) or metadata.duration <= 0:
		return _error("Duration must be a positive finite number.")
	for key in ["source_tick_rate", "sample_rate"]:
		if not _number(metadata.get(key)) or metadata[key] <= 0:
			return _error(key + " must be positive and finite.")
	if metadata.sample_rate > metadata.source_tick_rate:
		return _error("sample_rate cannot exceed source_tick_rate.")
	if metadata.get("coordinate_system") != "cs2_raw":
		return _error("V1 requires cs2_raw coordinates.")
	if not _integer(metadata.get("source_start_tick")) or not _integer(metadata.get("source_end_tick")):
		return _error("Source tick range must contain integers.")
	if metadata.source_start_tick < 0 or metadata.source_end_tick <= metadata.source_start_tick:
		return _error("Invalid source tick range.")
	if absf((metadata.source_end_tick - metadata.source_start_tick) / metadata.source_tick_rate - metadata.duration) > 0.000001:
		return _error("Source tick range does not match duration.")
	var players: Variant = raw.get("players")
	var tracks: Variant = raw.get("tracks")
	if not players is Array or players.is_empty():
		return _error("Replay must contain players.")
	if not tracks is Array or tracks.size() != players.size():
		return _error("Each player must have exactly one track.")
	var ids := {}
	for player in players:
		if not player is Dictionary:
			return _error("Player must be an object.")
		if not player.get("id") is String or player.id.is_empty() or ids.has(player.id):
			return _error("Player IDs must be nonempty unique strings.")
		if not player.get("name") is String or player.name.strip_edges().is_empty() or not player.get("steam_id") is String:
			return _error("Player name and string steam_id are required.")
		if player.get("team") not in ["T", "CT"]:
			return _error("Player team must be T or CT.")
		ids[player.id] = true
	var parsed_tracks := {}
	for track in tracks:
		if not track is Dictionary:
			return _error("Track must be an object.")
		var id: Variant = track.get("player_id")
		if not id is String or not ids.has(id) or parsed_tracks.has(id):
			return _error("Track references an unknown or duplicate player ID.")
		var frames: Variant = track.get("frames")
		if not frames is Array or frames.size() < 2:
			return _error("Track needs at least two frames.")
		var result_frames: Array = []
		var previous_time := -1.0
		var previous_tick := int(metadata.source_start_tick) - 1
		for frame in frames:
			if not frame is Dictionary:
				return _error("Frame must be an object.")
			var time: Variant = frame.get("time")
			if not _number(time) or time < 0 or time > metadata.duration + 0.000001 or time <= previous_time:
				return _error("Frame times must strictly increase within replay duration.")
			if not _integer(frame.get("tick")) or frame.tick <= previous_tick or frame.tick > metadata.source_end_tick:
				return _error("Frame ticks must strictly increase within the source range.")
			if absf((frame.tick - metadata.source_start_tick) / metadata.source_tick_rate - time) > 0.000001:
				return _error("Frame tick/time mismatch.")
			var point: Variant = frame.get("position")
			if not point is Dictionary or not _number(point.get("x")) or not _number(point.get("y")) or not _number(point.get("z")):
				return _error("Frame position requires finite x, y, z numbers.")
			if not _number(frame.get("yaw")):
				return _error("Frame yaw must be finite degrees.")
			if not _integer(frame.get("health")) or frame.health < 0 or not frame.get("alive") is bool:
				return _error("Frame requires nonnegative integer health and boolean alive.")
			if frame.get("team") not in ["T", "CT"] or not frame.get("available") is bool:
				return _error("Frame requires team and boolean available.")
			if frame.alive and not frame.available:
				return _error("An unavailable player cannot be alive.")
			previous_time = float(time)
			previous_tick = int(frame.tick)
			result_frames.append({"time": float(time), "tick": int(frame.tick),
				"position": Vector3(point.x, point.y, point.z), "yaw": deg_to_rad(float(frame.yaw)),
				"health": int(frame.health), "alive": frame.alive, "team": frame.team, "available": frame.available})
		if frames[0].time != 0 or absf(frames[-1].time - metadata.duration) > 0.000001:
			return _error("Every track must cover time 0 through duration.")
		parsed_tracks[id] = result_frames
	var extension := {"events": [], "projectiles": []}
	if raw.version == 2:
		extension = preload("res://scripts/events/ReplayV2Validator.gd").new().decode(raw, ids)
		if not extension.ok: return _error(extension.error)
	return {"ok": true, "error": "", "data": {
		"version": int(raw.version), "metadata": metadata.duplicate(true), "players": players.duplicate(true), "tracks": parsed_tracks,
		"events": extension.events, "projectiles": extension.projectiles}}


func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))


func _integer(value: Variant) -> bool:
	return _number(value) and float(value) == floor(float(value))


func _error(message: String) -> Dictionary:
	return {"ok": false, "data": {}, "error": message}
