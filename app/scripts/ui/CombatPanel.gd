extends TabContainer
signal inspect_player_requested(id: String)
const Palette = preload("res://scripts/config/TeamVisualConfig.gd")
var combat: Node3D
var player_names := {}
var toggles := {}
var stats: Label
var bomb_status: Label
var smoke_visibility: OptionButton
var kill_panel: VBoxContainer
var kill_rows: Array[Button] = []
var shown_kills: Array = []
var type_filter: OptionButton
var event_selector: OptionButton
var event_details: Label
var filtered_events: Array = []
var _last_kill_ids := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -320; offset_right = -20; offset_top = 110; offset_bottom = 596

func setup(view_controls: Control, controller: Node3D) -> void:
	combat = controller
	var view_scroll := ScrollContainer.new(); view_scroll.name="View"; view_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; add_child(view_scroll)
	view_controls.reparent(view_scroll)
	view_controls.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.name = "Layers"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var layers := VBoxContainer.new()
	layers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(layers)
	var grid := GridContainer.new()
	grid.columns = 2
	layers.add_child(grid)
	var titles := {"player_status": "Player Status", "burning": "Burning", "he_hit": "HE Hit", "in_smoke": "In Smoke", "bomb_carrier": "Carrier Red Name", "players": "Players", "names": "Player Names", "smoke": "Smoke", "smoke_tint": "Smoke Team Tint", "smoke_marker": "Smoke Marker", "fire": "Fire", "flash_effects": "Flash Effects", "flashed_players": "Flashed Players", "he_effects": "HE Effects", "grenades": "Grenades", "trajectories": "Trajectories", "shots": "Shots", "kill_feed": "Kill Feed", "bomb": "Bomb"}
	for key in combat.layers:
		var toggle := CheckBox.new()
		toggle.text = titles[key]
		toggle.button_pressed = combat.layers[key]
		toggle.add_theme_font_size_override("font_size", 12)
		toggle.toggled.connect(func(enabled): combat.set_layer(key, enabled))
		grid.add_child(toggle)
		toggles[key] = toggle
	smoke_visibility = OptionButton.new()
	for title in ["Smoke: Low", "Smoke: Tactical", "Smoke: Strong"]: smoke_visibility.add_item(title)
	smoke_visibility.select(1)
	smoke_visibility.item_selected.connect(func(index): combat.smoke_opacity = index; combat.refresh(combat.replay_controller.clock.current_time))
	layers.add_child(smoke_visibility)
	bomb_status = Label.new(); bomb_status.add_theme_color_override("font_color", Palette.BOMB); bomb_status.add_theme_font_size_override("font_size", 13); layers.add_child(bomb_status)
	stats = Label.new()
	stats.add_theme_font_size_override("font_size", 12)
	layers.add_child(stats)
	kill_panel = VBoxContainer.new()
	layers.add_child(kill_panel)
	var heading := Label.new()
	heading.text = "KILLS — latest 8 (click to seek)"
	heading.add_theme_font_size_override("font_size", 13)
	kill_panel.add_child(heading)
	for i in 8:
		var row := Button.new()
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.flat = true; row.clip_text = true
		row.focus_mode = Control.FOCUS_NONE
		row.custom_minimum_size.y = 32
		row.add_theme_font_size_override("font_size", 12)
		row.pressed.connect(func():
			if i < shown_kills.size(): combat.replay_controller.clock.seek(maxf(0, shown_kills[i].time - 2.5)))
		kill_panel.add_child(row); kill_rows.append(row)
	var inspect := VBoxContainer.new()
	inspect.name = "Events"
	add_child(inspect)
	type_filter = OptionButton.new()
	for type in ["smoke", "fire", "he", "flash", "shot", "kill", "player_hurt", "bomb_pickup", "bomb_drop", "bomb_plant", "bomb_defuse", "bomb_explode"]: type_filter.add_item(type)
	type_filter.item_selected.connect(func(_index): _filter_events())
	inspect.add_child(type_filter)
	event_selector = OptionButton.new()
	event_selector.fit_to_longest_item = false
	event_selector.item_selected.connect(func(_index): _show_event())
	inspect.add_child(event_selector)
	event_details = Label.new()
	event_details.add_theme_font_size_override("font_size", 13)
	event_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspect.add_child(event_details)
	var seek := Button.new()
	seek.text = "Seek to selected event"
	seek.pressed.connect(func():
		if not filtered_events.is_empty(): combat.replay_controller.clock.seek(filtered_events[event_selector.selected].time))
	inspect.add_child(seek)
	var inspect_damage:=Button.new();inspect_damage.text="Inspect victim at +0.2s"
	inspect_damage.pressed.connect(func():
		if filtered_events.is_empty():return
		var event=filtered_events[event_selector.selected]
		if event.type=="player_hurt":combat.replay_controller.clock.pause();combat.replay_controller.clock.seek(event.time+0.2);inspect_player_requested.emit(event.victim_player_id))
	inspect.add_child(inspect_damage)
	combat.refreshed.connect(refresh)
	current_tab = 1

func bind_replay() -> void:
	player_names.clear()
	for player in combat.replay_controller.replay.players: player_names[player.id] = player.name
	_last_kill_ids = "!"
	_filter_events()
	refresh()

func _filter_events() -> void:
	filtered_events.clear(); event_selector.clear()
	var type := type_filter.get_item_text(type_filter.selected)
	for event in combat.index.events:
		if event.type == type:
			filtered_events.append(event)
			event_selector.add_item("%s  %s" % [_time(event.time), event.id])
	_show_event()

func _show_event() -> void:
	if filtered_events.is_empty():
		event_details.text = "No events in this layer (V1 remains supported)."
		return
	var event = filtered_events[event_selector.selected]
	var point: Vector3 = event.origin if event.type == "shot" else event.position
	event_details.text = "ID: %s\nType: %s / %s\nActor: %s\nTeam at event/throw: %s\nTime: %.3f s\nRaw XYZ: %.2f, %.2f, %.2f\nActive: %.3f → %.3f\nProjectile: %s" % [event.id, event.type, event.grenade_type, player_names.get(event.actor_player_id, "World / Unknown"), event.actor_team, event.time, point.x, point.y, point.z, event.activate_time, event.expire_time, event.projectile_id]

	if event.type == "player_hurt":
		event_details.text = "Player Hurt\nVictim: %s\nSource: %s\nDamage: %d  Remaining HP: %d\nTime: %.5f s" % [player_names.get(event.victim_player_id,"Unknown"),event.damage_source,event.damage,event.health_remaining,event.time]

func refresh() -> void:
	if combat.replay_controller == null: return
	var count: Dictionary = combat.counts
	var bomb: Dictionary = combat.bomb.state
	bomb_status.visible = combat.layers.bomb
	bomb_status.text = "BOMB · " + bomb.get("state", "Unknown")
	if bomb.get("remaining", -1) >= 0: bomb_status.text += "\n%.1fs to recorded %s" % [bomb.remaining, bomb.outcome]
	elif bomb.get("state") == "Planted": bomb_status.text += "\nEnd time unavailable"
	stats.text = "Events: %d | Kills: %d\nActive smoke/fire: %d / %d\nProjectiles: %d | Shots: %d" % [combat.index.events.size(), count.kills, count.smoke, count.fire, count.projectiles, count.shots]
	kill_panel.visible = combat.layers.kill_feed
	var ids := ""
	for event in combat.recent_kills: ids += event.id + ";"
	if ids == _last_kill_ids: return
	_last_kill_ids = ids
	shown_kills = combat.recent_kills.duplicate()
	for i in kill_rows.size():
		var row := kill_rows[i]
		row.visible = i < shown_kills.size()
		if not row.visible: continue
		var event = shown_kills[i]
		row.text = "%s  %s → %s\n%s%s" % [_time(event.time), player_names.get(event.actor_player_id, "World"), player_names.get(event.victim_player_id, "Unknown"), event.weapon, "  [HS]" if event.headshot else ""]
		row.tooltip_text = row.text
		row.add_theme_color_override("font_color", Palette.team_color(event.actor_team))

func _time(time: float) -> String:
	return "%02d:%02d" % [int(time) / 60, int(time) % 60]
