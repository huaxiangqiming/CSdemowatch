extends RefCounted
## Versioned, bounded random-access reader. Each compressed chunk is checked for integrity
## before decompression. Only three ten-second player-track windows are retained.
const MAGIC := [67,83,50,82,80,76,89,0]
const MAX_RAW := 32 * 1024 * 1024
var file: FileAccess
var header: Dictionary = {}
var track_chunks: Array = []
var cache: Dictionary = {}
var recent: Array = []
var payload_start := 0
var error := ""
var chunk_reads := 0
var resident_frames := 0
# Worker owns a separate reader/file handle. Only the playback thread touches
# this reader's cache; at most one extra decoded window can be in flight.
var prefetch_enabled := true
var prefetch_thread: Thread
var prefetch_worker: RefCounted
var prefetch_hits := 0
var prefetch_reads := 0
var prefetched_indices: Dictionary = {}
var pending_failure: Dictionary = {}
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and prefetch_thread != null:
		prefetch_thread.wait_to_finish()
func _read_ahead(path: String, index: int) -> Dictionary:
	file = FileAccess.open(path, FileAccess.READ)
	if file == null: return {"index":index,"tracks":{},"error":"cannot open prefetch source","reads":0}
	var tracks := tracks_at(index * 10.0)
	file = null
	return {"index":index,"tracks":tracks,"error":error,"reads":chunk_reads}
func _collect_prefetch(index: int) -> void:
	if prefetch_thread == null or prefetch_thread.is_alive(): return
	var result: Dictionary = prefetch_thread.wait_to_finish()
	prefetch_worker = null
	prefetch_thread = null
	chunk_reads += result.reads
	prefetch_reads += result.reads
	# A seek can make a completed read irrelevant. Never let it evict the
	# requested window or surface errors from a window we no longer need.
	if result.index != index and result.index != index + 1: return
	if not result.error.is_empty():
		pending_failure = result
	elif not cache.has(result.index):
		_store_window(result.index, result.tracks)
		prefetched_indices[result.index] = true
func _schedule_prefetch(index: int) -> void:
	if not prefetch_enabled or prefetch_thread != null: return
	var target := index + 1
	if target >= track_chunks.size() or cache.has(target): return
	if pending_failure.get("index", -1) == target: return
	var worker = get_script().new()
	worker.prefetch_enabled = false
	worker.header = header.duplicate(true)
	worker.track_chunks = track_chunks.duplicate(true)
	worker.payload_start = payload_start
	prefetch_worker = worker
	prefetch_thread = Thread.new()
	if prefetch_thread.start(worker._read_ahead.bind(file.get_path_absolute(), target)) != OK:
		prefetch_thread = null # Synchronous reads remain available.
		prefetch_worker = null
func _store_window(index: int, tracks: Dictionary) -> void:
	cache[index] = tracks
	recent.erase(index)
	recent.append(index)
	while recent.size() > 3:
		var removed = recent.pop_front()
		cache.erase(removed)
		prefetched_indices.erase(removed)
	resident_frames = 0
	for window in cache.values():
		for frames in window.values(): resident_frames += frames.size()
func fail(message: String) -> Dictionary:
	error = "Binary Replay: " + message
	return {"ok": false, "data": {}, "error": error}
func integer(v: Variant) -> bool:
	return (v is int or v is float) and is_finite(float(v)) and float(v) == floor(float(v))
func number(v: Variant) -> bool:
	return (v is int or v is float) and is_finite(float(v))
func load_replay(path: String) -> Dictionary:
	file = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 16: return fail("missing or truncated header")
	if file.get_buffer(8) != PackedByteArray(MAGIC) or file.get_32() != 1: return fail("unsupported container version")
	var length := file.get_32()
	if length < 2 or length > 4 * 1024 * 1024 or length > file.get_length() - 16: return fail("invalid header length")
	var parser := JSON.new()
	if parser.parse(file.get_buffer(length).get_string_from_utf8()) != OK or not parser.data is Dictionary: return fail("invalid header JSON")
	header = parser.data
	payload_start = file.get_position()
	if not header.get("metadata") is Dictionary or not header.get("players") is Array or not header.get("chunks") is Array: return fail("missing index/metadata/players")
	if header.get("chunk_seconds") != 10 or header.chunks.size() > 100000: return fail("unsupported window size or excessive index")
	var m: Dictionary = header.metadata
	if not number(m.get("duration")) or m.duration <= 0 or not integer(m.get("source_start_tick")) or not integer(m.get("source_end_tick")): return fail("invalid timeline")
	if not header.get("bounds") is Array or header.bounds.size() != 2: return fail("missing bounds")
	for point in header.bounds:
		if not point is Array or point.size() != 3: return fail("invalid bounds")
		for v in point:
			if not number(v): return fail("nonfinite bounds")
	for axis in 3:
		if header.bounds[0][axis] > header.bounds[1][axis]: return fail("inverted bounds")
	# Reuse the established validator for roster, timing and event facts using
	# synthetic endpoint-only tracks. These are discarded, never used to render.
	var raw := {"version": header.get("replay_version"), "metadata": m, "players": header.players, "tracks": [], "events": [], "projectiles": []}
	for player in header.players:
		if not player is Dictionary: return fail("invalid player")
		var frames := []
		for endpoint in 2:
			frames.append({"time": 0 if endpoint == 0 else m.duration, "tick": m.source_start_tick if endpoint == 0 else m.source_end_tick, "position": {"x":0,"y":0,"z":0}, "yaw":0,"health":0,"alive":false,"available":false,"team":player.get("team")})
		raw.tracks.append({"player_id":player.get("id"),"frames":frames})
	var offset := 0
	var next_time := 0.0
	var families := {}
	for chunk in header.chunks:
		if not chunk is Dictionary: return fail("invalid chunk entry")
		for key in ["offset", "size", "raw_size"]:
			if not integer(chunk.get(key)) or chunk[key] < 0: return fail("invalid chunk extent")
		if chunk.offset != offset or chunk.size <= 0 or chunk.size > MAX_RAW or chunk.raw_size <= 0 or chunk.raw_size > MAX_RAW or chunk.size > file.get_length() - payload_start - offset: return fail("overlapping, oversized or truncated chunk")
		if not chunk.get("sha256") is String or chunk.sha256.length() != 64: return fail("missing chunk checksum")
		offset += int(chunk.size)
		if chunk.get("kind") == "tracks":
			if not number(chunk.get("start")) or not number(chunk.get("end")) or chunk.start != next_time or chunk.end != minf(next_time + 10, m.duration) or chunk.end <= chunk.start: return fail("invalid time index")
			track_chunks.append(chunk)
			next_time = chunk.end
		elif chunk.get("kind") in ["events", "damage", "bomb", "projectiles", "rounds"]:
			if families.has(chunk.kind): return fail("duplicate fact chunk")
			families[chunk.kind] = chunk
		else: return fail("unknown chunk type")
	if offset != file.get_length() - payload_start or next_time != m.duration or families.size() != 5: return fail("incomplete index")
	for kind in ["events", "damage", "bomb", "projectiles", "rounds"]:
		var bytes := read_chunk(families[kind])
		if not error.is_empty(): return fail(error)
		var json := JSON.new()
		if json.parse(bytes.get_string_from_utf8()) != OK or not json.data is Array: return fail("invalid fact chunk")
		if kind == "projectiles": raw.projectiles = json.data
		elif kind == "rounds":
			if not json.data.is_empty(): return fail("unsupported round facts")
		else: raw.events.append_array(json.data)
	for event in raw.events:
		if not event is Dictionary or not integer(event.get("_order")): return fail("invalid event order")
	if raw.version == 1 and (not raw.events.is_empty() or not raw.projectiles.is_empty()): return fail("V1 cannot contain events")
	raw.events.sort_custom(func(a, b): return a._order < b._order)
	for i in raw.events.size():
		if raw.events[i]._order != i: return fail("duplicate or missing event order")
	var validated: Dictionary = preload("res://scripts/core/ReplayValidator.gd").new().validate(raw)
	if not validated.ok: return fail(validated.error)
	var tracks := tracks_at(0)
	if not error.is_empty(): return fail(error)
	validated.data.tracks = tracks
	validated.data.stream = self
	validated.data.raw_bounds = header.bounds
	return validated
func read_chunk(chunk: Dictionary) -> PackedByteArray:
	file.seek(payload_start + int(chunk.offset))
	var bytes := file.get_buffer(int(chunk.size))
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256); hash.update(bytes)
	if bytes.size() != int(chunk.size) or hash.finish().hex_encode() != chunk.sha256:
		error = "chunk integrity check failed"; return PackedByteArray()
	var raw := bytes.decompress(int(chunk.raw_size), FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != int(chunk.raw_size): error = "invalid compressed chunk"; return PackedByteArray()
	chunk_reads += 1
	return raw
func tracks_at(seconds: float) -> Dictionary:
	if not error.is_empty(): return {}
	var index := mini(int(maxf(seconds, 0) / 10), track_chunks.size() - 1)
	if prefetch_enabled: _collect_prefetch(index)
	if pending_failure.get("index", -1) == index:
		error = pending_failure.error
		return {}
	if cache.has(index):
		recent.erase(index); recent.append(index)
		if prefetched_indices.has(index):
			prefetch_hits += 1
			prefetched_indices.erase(index)
		_schedule_prefetch(index)
		return cache[index]
	var chunk: Dictionary = track_chunks[index]
	var bytes := read_chunk(chunk)
	if not error.is_empty(): return {}
	var reader := StreamPeerBuffer.new()
	reader.data_array = bytes
	if bytes.size() < 4 or reader.get_u32() != header.players.size(): error = "invalid track count"; return {}
	var result := {}
	for player_index in header.players.size():
		if reader.get_available_bytes() < 8 or reader.get_u32() != player_index: error = "invalid track roster"; return {}
		var count := reader.get_u32()
		if count < 2 or count > reader.get_available_bytes() / 28: error = "invalid frame count"; return {}
		var tick := 0
		var xyz: Array[int] = [0,0,0]
		var frames := []
		var last := -1.0
		for i in count:
			tick += reader.get_32()
			for axis in 3:
				xyz[axis] += reader.get_32()
				if xyz[axis] < -2147483648 or xyz[axis] > 2147483647: error = "coordinate accumulator overflow"; return {}
			var yaw := reader.get_float()
			var health := reader.get_32()
			var flags := reader.get_u32()
			var time: float = (tick - header.metadata.source_start_tick) / float(header.metadata.source_tick_rate)
			if not is_finite(yaw) or health < 0 or flags > 7 or (flags & 1 and not flags & 2) or time < 0 or time > header.metadata.duration + 0.000001 or time <= last:
				error = "invalid track frame"; return {}
			last = time
			frames.append({"time":time,"tick":tick,"position":Vector3(xyz[0],xyz[1],xyz[2])/32.0,"yaw":deg_to_rad(yaw),"health":health,"alive":bool(flags & 1),"available":bool(flags & 2),"team":"CT" if flags & 4 else "T"})
		if frames[0].time > chunk.start or frames[-1].time < chunk.end: error = "track does not bracket window"; return {}
		result[header.players[player_index].id] = frames
	if reader.get_available_bytes() != 0: error = "unexpected track bytes"; return {}
	_store_window(index, result)
	_schedule_prefetch(index)
	return result
