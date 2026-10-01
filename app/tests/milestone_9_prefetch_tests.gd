extends SceneTree
var checks := 0
var failures := []
const Stream = preload("res://scripts/core/BinaryReplayStream.gd")
const SOURCE := "res://../artifacts/m9/ancient.replay"
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr(label)
func _initialize() -> void: run.call_deferred()
func completed(stream) -> bool:
	var deadline := Time.get_ticks_msec() + 5000
	while stream.prefetch_thread != null and stream.prefetch_thread.is_alive() and Time.get_ticks_msec() < deadline:
		await create_timer(0.01).timeout
	return stream.prefetch_thread != null and not stream.prefetch_thread.is_alive()
func run() -> void:
	var stream = Stream.new()
	var loaded: Dictionary = stream.load_replay(SOURCE)
	check(loaded.ok, "Streaming fixture loads")
	if not loaded.ok: quit(1); return
	var reference = Stream.new()
	reference.prefetch_enabled = false
	var baseline: Dictionary = reference.load_replay(SOURCE)
	check(baseline.ok, "Synchronous reference loads")
	var max_hit_ms := 0.0
	for index in range(1, 7):
		check(await completed(stream), "Read ahead finishes " + str(index))
		var before: int = stream.prefetch_hits
		var start := Time.get_ticks_usec()
		var actual: Dictionary = stream.tracks_at(index * 10.0)
		max_hit_ms = maxf(max_hit_ms, (Time.get_ticks_usec()-start)/1000.0)
		check(stream.prefetch_hits == before + 1, "Boundary uses prefetched window")
		check(actual == reference.tracks_at(index * 10.0), "Prefetched facts equal synchronous facts")
		check(stream.cache.size() <= 3, "Decoded cache is bounded")
	check(await completed(stream), "Pending window ready before far seek")
	check(stream.tracks_at(1500) == reference.tracks_at(1500), "Far seek discards unrelated prefetch")
	for time in [10.0,900.0,20.0,1700.0,0.0,loaded.data.metadata.duration]:
		check(stream.tracks_at(time) == reference.tracks_at(time), "Rapid seek remains coherent")
		check(stream.cache.size() <= 3, "Rapid seeks retain cache bound")
	# Damage the immediate next block. Speculation must not invalidate the
	# healthy current frame; demanding the bad block must report failure.
	var bytes := FileAccess.get_file_as_bytes(SOURCE)
	var chunk: Dictionary = stream.track_chunks[1]
	bytes[stream.payload_start + int(chunk.offset) + 5] ^= 1
	var path := "res://../artifacts/m9/prefetch-corrupt.replay"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes); file.close()
	var broken = Stream.new()
	var corrupt: Dictionary = broken.load_replay(path)
	check(corrupt.ok, "Future corruption permits initial window")
	check(await completed(broken), "Damaged read ahead finishes")
	check(not broken.tracks_at(1).is_empty() and broken.error.is_empty(), "Future failure does not poison current time")
	check(broken.tracks_at(10).is_empty() and not broken.error.is_empty(), "Demanding corrupt prefetch fails")
	check(broken.tracks_at(0).is_empty(), "Failure stays latched until reload")
	# Releasing the stream must join its worker even if it has just started.
	for i in 5:
		var closing = Stream.new()
		var result: Dictionary = closing.load_replay(SOURCE)
		check(result.ok, "Lifecycle fixture loads")
		var owner_ref: WeakRef = weakref(closing)
		var worker_ref: WeakRef = weakref(closing.prefetch_worker)
		result.clear()
		closing = null
		check(owner_ref.get_ref() == null and worker_ref.get_ref() == null, "Close releases reader and worker")
	file = FileAccess.open("res://../artifacts/m9/prefetch-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"max_prefetched_boundary_ms":max_hit_ms,"prefetch_hits":stream.prefetch_hits},"  "))
	print("M9 prefetch ",checks," failures=",failures.size()," max boundary ms=",max_hit_ms)
	quit(0 if failures.is_empty() else 1)
