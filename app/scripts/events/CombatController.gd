extends Node3D
signal refreshed
const Palette = preload("res://scripts/config/TeamVisualConfig.gd")
var index = preload("res://scripts/events/ReplayEventIndex.gd").new()
var replay_controller: Node3D
var utility: Node3D
var projectiles: Node3D
var shots: Node3D
var bomb: Node3D
var flashed: Node3D
var smoke_opacity := 1
var layers := {"player_status": true, "burning": true, "he_hit": true, "in_smoke": true, "bomb_carrier": true, "players": true, "names": true, "dead_names": false, "smoke": true, "smoke_tint": true, "smoke_marker": true, "fire": true, "flash_effects": true, "flashed_players": true, "he_effects": true, "grenades": true, "trajectories": true, "shots": true, "kill_feed": true, "bomb": true}
var counts := {"smoke": 0, "fire": 0, "projectiles": 0, "shots": 0, "kills": 0}
var recent_kills: Array = []

func _ready() -> void:
	utility = preload("res://scripts/rendering/UtilityRenderer.gd").new()
	projectiles = preload("res://scripts/rendering/ProjectileRenderer.gd").new()
	shots = preload("res://scripts/rendering/ShotRenderer.gd").new()
	add_child(utility); add_child(projectiles); add_child(shots)
	bomb = preload("res://scripts/rendering/BombRenderer.gd").new(); add_child(bomb)
	flashed = preload("res://scripts/status/PlayerStatusRenderer.gd").new(); add_child(flashed)

func bind_controller(controller: Node3D) -> void:
	if replay_controller == null:
		replay_controller = controller
		controller.clock.time_changed.connect(refresh)
	index.build(controller.replay)
	bomb.state_model.build(index.events)
	flashed.build(index.events)
	flashed.resolver.build(index, bomb.state_model)
	refresh(controller.clock.current_time)

func set_layer(key: String, enabled: bool) -> void:
	layers[key] = enabled
	if replay_controller != null: refresh(replay_controller.clock.current_time)

func refresh(time: float) -> void:
	if replay_controller == null: return
	if not replay_controller.load_error.is_empty():
		hide()
		return
	show()
	var transform = replay_controller.map_transform
	var smoke: Array = index.get_active_smoke(time)
	var fire: Array = index.get_active_fire(time)
	var flying: Array = index.get_active_projectiles(time)
	var recent_shots: Array = index.get_recent_shots(time, Palette.SHOT_LIFETIME)
	counts = {"smoke": smoke.size(), "fire": fire.size(), "projectiles": flying.size(), "shots": recent_shots.size(), "kills": index.kills.size()}
	var effects: Array = []
	if layers.smoke: effects.append_array(smoke)
	if layers.fire: effects.append_array(fire)
	for pulse in index.get_active_pulses(time):
		if (pulse.type == "flash" and layers.flash_effects) or (pulse.type == "he" and layers.he_effects): effects.append(pulse)
	counts.flash_visuals = 0
	for effect in effects:
		if effect.type == "flash": counts.flash_visuals += 1
	utility.options = {"smoke_tint": layers.smoke_tint, "smoke_marker": layers.smoke_marker, "smoke_opacity": smoke_opacity}
	utility.update_effects(effects, time, transform)
	projectiles.update_projectiles(flying if layers.grenades or layers.trajectories else [], time, transform, layers.grenades, layers.trajectories)
	shots.update_shots(recent_shots if layers.shots else [], time, transform)
	bomb.update_state(time, replay_controller, layers.bomb)
	flashed.update_statuses(time, replay_controller, layers)
	recent_kills = index.get_recent_kills(time) if layers.kill_feed else []
	for id in replay_controller.player_views:
		var view = replay_controller.player_views[id]
		view.visible = layers.players and replay_controller.current_states.get(id, {}).get("available", false)
		view.get_node("Name").visible = layers.names and (view._alive or layers.dead_names)
	refreshed.emit()
