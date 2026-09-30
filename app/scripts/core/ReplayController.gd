extends Node3D

const Loader = preload("res://scripts/core/ReplayLoader.gd")
const Clock = preload("res://scripts/core/ReplayClock.gd")
const Sampler = preload("res://scripts/core/TrackSampler.gd")
const PlayerScene = preload("res://scenes/replay/Player.tscn")
const MapTransform = preload("res://scripts/map/MapTransform.gd")

var clock = Clock.new()
var replay: Dictionary = {}
var player_views: Dictionary = {}
var load_error: String = ""
var map_transform = MapTransform.new()
var current_states: Dictionary = {}
var bounds := AABB()


func _ready() -> void:
	clock.time_changed.connect(_apply_time)


func load_replay(path: String) -> bool:
	var result: Dictionary = Loader.new().load_replay(path)
	if not result.ok:
		load_error = result.error
		return false
	return accept_replay(result.data)

func accept_replay(data: Dictionary) -> bool:
	for view in player_views.values():
		remove_child(view)
		view.queue_free()
	player_views.clear()
	current_states.clear()
	replay = data
	bounds = map_transform.replay_bounds(replay)
	load_error = ""
	for player in replay.players:
		var view = PlayerScene.instantiate()
		add_child(view)
		view.configure(player)
		player_views[player.id] = view
	clock.configure(replay.metadata.duration)
	return true


func _process(delta: float) -> void:
	clock.advance(delta)

func set_map_transform(value: RefCounted) -> void:
	map_transform = value
	bounds = map_transform.replay_bounds(replay)
	_apply_time(clock.current_time)


func _apply_time(seconds: float) -> void:
	for id in player_views:
		var raw: Dictionary = Sampler.sample(replay.tracks[id], seconds)
		current_states[id] = raw
		player_views[id].apply_state(map_transform.state_to_godot(raw))
