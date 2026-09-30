extends RefCounted
## A single-owner worker. Never accesses the scene tree or creates Nodes.
var thread := Thread.new()
var mutex := Mutex.new()
var status := "Loading Replay"
var result := {}
var elapsed_ms := 0
var status_callback: Callable
func _status(value: String) -> void:
	mutex.lock(); status = value; mutex.unlock()
	if status_callback.is_valid(): status_callback.call(value)
func get_status() -> String:
	mutex.lock(); var value := status; mutex.unlock(); return value
func start(path: String) -> Error:
	return thread.start(_work.bind(path))
func _work(path: String) -> void:
	var started := Time.get_ticks_msec()
	result = preload("res://scripts/core/ReplayLoader.gd").new().load_replay(path)
	if result.ok:
		var name: String = result.data.metadata.map
		if name != "test_plane":
			var assets = preload("res://scripts/map/MapAssetManager.gd").new()
			_status("Checking Tactical Map")
			result.map_asset = assets.prepare_map(name)
		_status("Preparing Scene")
		# Cache replay bounds on this immutable decoded object. Transform remains
		# the sole coordinate boundary; renderer nodes are created on main thread.
		var transform = preload("res://scripts/map/MapTransform.gd").new()
		result.data.prepared_bounds = transform.replay_bounds(result.data)
		result.data.prepared_transform = [transform.scale_factor, transform.rotation_degrees, transform.offset]
	elapsed_ms = Time.get_ticks_msec() - started
func done() -> bool: return thread.is_started() and not thread.is_alive()
func finish() -> Dictionary:
	if thread.is_started(): thread.wait_to_finish()
	return result
