extends PanelContainer
## Small inspection panel; observes the same sampled state as PlayerView.
signal open_replay_requested
var controller: Node3D
var summary: Label
var details: Label
var status_details: Label
var selector: OptionButton
var _ids: Array[String] = []
var _elapsed := 0.0
var camera: Node3D
var map_manager: Node3D
var combat: Node3D
var transform_details: Label

func _ready() -> void:
	position = Vector2(20, 110)
	custom_minimum_size = Vector2(280, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.96, 0.98, 1.0, 0.97)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(252, 450)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll); scroll.add_child(column)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var open_button := Button.new()
	open_button.text = "Open Replay File"
	open_button.focus_mode = Control.FOCUS_NONE
	open_button.pressed.connect(func(): open_replay_requested.emit())
	column.add_child(open_button)
	status_details=Label.new();status_details.add_theme_font_size_override("font_size",12);column.add_child(status_details)
	summary = Label.new()
	summary.add_theme_font_size_override("font_size", 13)
	column.add_child(summary)
	selector = OptionButton.new()
	selector.custom_minimum_size.x = 252
	selector.fit_to_longest_item = false
	selector.clip_text = true
	selector.item_selected.connect(func(_index): refresh())
	column.add_child(selector)
	var focus_button:=Button.new();focus_button.text="Focus selected player";focus_button.pressed.connect(focus_selected);column.add_child(focus_button)
	details = Label.new()
	details.add_theme_font_size_override("font_size", 13)
	column.add_child(details)
	transform_details = Label.new()
	transform_details.add_theme_font_size_override("font_size", 12)
	column.add_child(transform_details)

func bind_controller(value: Node3D) -> void:
	controller = value
	_ids.clear()
	selector.clear()
	selector.add_item("Inspect player...")
	for player in controller.replay.players:
		_ids.append(player.id)
		selector.add_item(player.name)
	refresh()

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= 0.1:
		_elapsed = 0.0
		refresh()

func refresh() -> void:
	if controller == null or controller.replay.is_empty():
		return
	var alive_t := 0
	var alive_ct := 0
	for state in controller.current_states.values():
		if state.available and state.alive:
			if state.team == "T":
				alive_t += 1
			else:
				alive_ct += 1
	var metadata: Dictionary = controller.replay.metadata
	summary.text = "Map: %s\nTime: %.3f / %.3f s\nPlayers: %d   Alive T: %d   CT: %d\nSource: %.0f Hz   Sample: %.0f Hz\nRender FPS: %d" % [
		metadata.map, controller.clock.current_time, controller.clock.duration,
		controller.player_views.size(), alive_t, alive_ct, metadata.source_tick_rate,
		metadata.sample_rate, Engine.get_frames_per_second()]
	details.text = "Select a player to inspect coordinates."
	status_details.text="Select a player for tactical status diagnostics."
	if combat != null:
		if combat.flashed.resolver.damage_count == 0: summary.text += "\nDamage events unavailable"
		summary.text += "\nEvents: %d  Smoke/Fire: %d/%d\nActive grenades/shots: %d/%d\nRendered: %d/%d  Kills: %d" % [combat.index.events.size(), combat.counts.smoke, combat.counts.fire, combat.counts.projectiles, combat.counts.shots, combat.projectiles.render_count, combat.shots.shot_count, combat.counts.kills]
	if camera != null and map_manager != null:
		summary.text += "\nMap triangles: %d\nFire patches: %d  Utility: %d\nShot lines: %d  Flashed: %d\nFlash visuals: %d\nLoad replay/map: %d/%d ms\nGodot memory: %.1f MiB" % [map_manager.triangles, combat.utility.patch_count, combat.utility.active_ids.size() + combat.projectiles.render_count, combat.shots.lines.line_count, combat.flashed.active_count, combat.counts.get("flash_visuals", 0), get_parent().get_parent().replay_loading_ms, map_manager.loading_ms, Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0]
		if Performance.get_monitor(Performance.MEMORY_STATIC)<=0:summary.text=summary.text.replace("Godot memory: 0.0 MiB","Godot memory: unavailable (Release)")
		var transform = map_manager.map_transform
		transform_details.text = "Map scale: %.4f   Rotation: %.1f°\nOffset: %s\nCamera: %s\nPivot: %s\nYaw: %.1f°   Pitch: %.1f°" % [transform.scale_factor, transform.rotation_degrees, _vec(transform.offset), _vec(camera.lens.global_position), _vec(camera.target), camera.yaw, camera.pitch]
		transform_details.text += "\nBounds: %s → %s\nWorld origin: 0, 0, 0\nGLB: %.2f MiB" % [_vec(map_manager.map_bounds.position), _vec(map_manager.map_bounds.end),map_manager.glb_bytes / 1048576.0]
		transform_details.text += "\nRoof removed: %d triangles" % map_manager.roof_removed
		var source_info:Dictionary=map_manager.source_metadata.get("source_resource",{})
		transform_details.text += "\nMap cache: %s\nPreparation: %s\nSource status: %s\nSource resource: %s\nConverter: %s / Classifier: %s" % ["Ready" if map_manager.model!=null else "Missing / Stale",map_manager.preparation_state,source_info.get("reason","Legacy / unavailable"),source_info.get("physics_resource","—"),map_manager.source_metadata.get("converter_version","Legacy"),map_manager.source_metadata.get("classifier_version","—")]
	if selector.selected <= 0:
		return
	var id := _ids[selector.selected - 1]
	var raw: Dictionary = controller.current_states[id]
	var converted: Vector3 = controller.map_transform.position_to_godot(raw.position)
	var player: Dictionary = controller.replay.players[selector.selected - 1]
	details.text = "Player: %s\nRaw CS2 XYZ: %.2f, %.2f, %.2f\nGodot XYZ: %.2f, %.2f, %.2f\nYaw: %.2f deg   Tick: %d\nHealth: %d   Alive: %s\nTeam: %s   Data: %s" % [
		player.name, raw.position.x, raw.position.y, raw.position.z,
		converted.x, converted.y, converted.z, rad_to_deg(raw.yaw), raw.tick,
		raw.health, str(raw.alive), raw.team, "available" if raw.available else "unavailable"]

	if combat != null:
		var active: Array = combat.flashed.resolver.resolve(controller.clock.current_time, id, raw)
		var labels := {"he_hit":"HE_HIT","burning":"BURNING","flashed_players":"FLASHED","in_smoke":"IN_SMOKE","bomb_carrier":"BOMB_CARRIER"}
		var names: Array = active.map(func(kind):return labels.get(kind,kind))
		status_details.text = "Selected: " + player.name + "\nActive Statuses: " + (", ".join(names) if not names.is_empty() else "None")
		status_details.text += "\nRecent Damage (5s):"
		var damage: Array = combat.flashed.resolver.recent_damage(id,controller.clock.current_time)
		for event in damage: status_details.text += "\n%.5f  %s  %d dmg" % [event.time,event.damage_source,event.damage]
		if damage.is_empty(): status_details.text += "\nNone" if combat.flashed.resolver.damage_count > 0 else "\nDamage events unavailable"

func _vec(value: Vector3) -> String:
	return "%.2f, %.2f, %.2f" % [value.x, value.y, value.z]

func select_player(id: String) -> void:
	var index:=_ids.find(id)
	if index>=0:selector.select(index+1);refresh()
func focus_selected() -> void:
	if selector.selected<=0 or controller==null or camera==null:return
	var id:=_ids[selector.selected-1]
	camera.target=controller.player_views[id].position;camera.size=20;camera._update_pose()
