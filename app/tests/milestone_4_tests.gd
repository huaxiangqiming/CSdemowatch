extends SceneTree
const MainScene = preload("res://scenes/Main.tscn")
const Palette = preload("res://scripts/config/TeamVisualConfig.gd")
var checks := 0
var failures: Array[String] = []
var report := {}
func _initialize() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL: ", message)
func ids(events: Array) -> Array:
	var result: Array = []
	for event in events: result.append(event.id)
	result.sort()
	return result
func click(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT; event.position = point; event.global_position = point; event.pressed = pressed
		root.push_input(event, true)
func screenshot(name: String) -> void:
	await create_timer(0.15).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/" + name))
func validate_inputs() -> void:
	var validator = preload("res://scripts/core/ReplayValidator.gd").new()
	var seed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/mock_replay.json"))
	seed.version = 2; seed.projectiles = []
	seed.events = [{"id": "smoke_validation", "type": "smoke", "time": 0.25, "tick": 16, "actor_player_id": seed.players[0].id, "actor_team": "T", "position": {"x": 0, "y": 0, "z": 0}, "throw_time": 0, "activate_time": 0.25, "expire_time": 1}]
	check(validator.validate(seed).ok, "Valid V2 schema at loader boundary")
	for kind in ["reference", "position", "time", "tick", "duplicate", "missing_array", "version"]:
		var bad: Dictionary = seed.duplicate(true)
		match kind:
			"reference": bad.events[0].actor_player_id = "absent"
			"position": bad.events[0].position.x = INF
			"time": bad.events[0].expire_time = 0.1
			"tick": bad.events[0].tick = 4
			"duplicate": bad.events.append(bad.events[0])
			"missing_array": bad.erase("projectiles")
			"version": bad.version = 99
		check(not validator.validate(bad).ok, "Reject malformed V2 " + kind)
func _run() -> void:
	validate_inputs()
	var main = MainScene.instantiate()
	root.add_child(main); current_scene = main
	await process_frame
	var controller = main.controller
	controller.set_process(false)
	if controller.replay.is_empty() or controller.replay.get("version") != 2:
		printerr("V2 replay required: ", controller.load_error); quit(1); return
	var clock = controller.clock
	var combat = main.combat
	var index = combat.index
	check(index.events.size() == 3410, "Real V2 event count")
	check(controller.player_views.size() == 10, "V2 keeps ten real players")
	var counts := {}
	var first := {}
	for event in index.events:
		counts[event.type] = counts.get(event.type, 0) + 1
		if not first.has(event.type): first[event.type] = event
	check(counts == {"smoke": 48, "fire": 41, "he": 67, "flash": 68, "shot": 3023, "kill": 163}, "All real event types present")
	for type in ["smoke", "fire", "he", "flash"]:
		var event = first[type]
		clock.seek(event.time - 0.001)
		check(not combat.utility.active_ids.has(event.id), type + " absent before activation")
		clock.seek((event.time + event.expire_time) * 0.5)
		check(combat.utility.active_ids.has(event.id), type + " reconstructed by direct seek")
		clock.seek(event.expire_time)
		check(not combat.utility.active_ids.has(event.id), type + " absent at expiry")
		clock.seek(event.time + 0.001)
		check(combat.utility.active_ids.has(event.id), type + " restored by backward seek")
	# Compare the index with an independent full scan over discontinuous seeks.
	var seek_max_us := 0
	for i in 120:
		var time: float = fmod(i * 673.159, clock.duration)
		var expected_smoke: Array = []
		var expected_fire: Array = []
		var expected_shots: Array = []
		var expected_kills: Array = []
		for event in index.events:
			if event.type == "smoke" and event.time <= time and time < event.expire_time: expected_smoke.append(event)
			if event.type == "fire" and event.time <= time and time < event.expire_time: expected_fire.append(event)
			if event.type == "shot" and event.time <= time and time < event.time + Palette.SHOT_LIFETIME: expected_shots.append(event)
			if event.type == "kill" and event.time <= time: expected_kills.append(event)
		expected_kills = expected_kills.slice(maxi(0, expected_kills.size() - 8))
		var started := Time.get_ticks_usec()
		clock.seek(time)
		seek_max_us = maxi(seek_max_us, Time.get_ticks_usec() - started)
		check(ids(index.get_active_smoke(time)) == ids(expected_smoke), "Random seek smoke index")
		check(ids(index.get_active_fire(time)) == ids(expected_fire), "Random seek fire index")
		check(ids(index.get_recent_shots(time)) == ids(expected_shots), "Random seek shot lifetime")
		check(ids(combat.recent_kills) == ids(expected_kills), "Kill feed replaces previous seek history")
		var expected_projectiles: Array = []
		for item in controller.replay.projectiles:
			if item.throw_time <= time and time < item.end_time: expected_projectiles.append(item)
		check(ids(index.get_active_projectiles(time)) == ids(expected_projectiles), "Random seek projectile index")
	var smoke = first.smoke
	clock.seek(smoke.time + 1)
	main.combat_panel.current_tab = 1
	await process_frame
	click(main.combat_panel.toggles.smoke.get_global_rect().get_center())
	check(not combat.layers.smoke and not combat.utility.active_ids.has(smoke.id), "Actual Smoke checkbox hides effects")
	click(main.combat_panel.toggles.smoke.get_global_rect().get_center())
	check(combat.layers.smoke and combat.utility.active_ids.has(smoke.id), "Smoke checkbox restores effect while paused")
	for layer in ["smoke", "fire", "grenades", "trajectories", "shots", "kill_feed", "players", "names"]:
		combat.set_layer(layer, false)
	check(combat.projectiles.render_count == 0 and combat.shots.shot_count == 0 and not main.combat_panel.kill_panel.visible, "Disabled renderers and kill panel are empty")
	check(not controller.player_views.values()[0].visible and not controller.player_views.values()[0].get_node("Name").visible, "Player and name layers")
	var allocated: int = combat.shots.get_child_count() + combat.projectiles.get_child_count() + combat.utility.get_child_count()
	for time in [1609.4, 1609.48, 1609.52, 1609.6, 1609.8]: clock.seek(time)
	check(allocated == combat.shots.get_child_count() + combat.projectiles.get_child_count() + combat.utility.get_child_count(), "Disabled shot/grenade layers allocate no nodes during gunfire")
	for layer in combat.layers: combat.set_layer(layer, true)
	var shot = first.shot
	clock.seek(shot.time + 0.01)
	check(combat.shots.shot_count > 0 and combat.shots.lines.line_count > 0, "Real shooting draws batch tracer")
	check(not ids(index.get_recent_shots(shot.time + 0.121)).has(shot.id), "Shot expires after 120 ms")
	var shot_nodes: int = combat.shots.get_child_count()
	for event in index.shots.slice(0, 100): clock.seek(event.time)
	check(combat.shots.get_child_count() == shot_nodes, "No node per shot")
	var projectile = controller.replay.projectiles[0]
	var mid: float = (projectile.throw_time + projectile.end_time) * 0.5
	clock.seek(mid)
	check(ids(index.get_active_projectiles(mid)).has(projectile.id), "Seek restores in-flight grenade")
	check(combat.projectiles.trajectory_count > 0, "Active trajectory shown")
	check(not ids(index.get_active_projectiles(projectile.end_time)).has(projectile.id), "Trajectory disappears at flight end")
	# Freeze a real pre-switch smoke's team and return after late-game seek.
	clock.seek(clock.duration - 1)
	for event in index.events:
		if event.type == "smoke" and controller.current_states.has(event.actor_player_id) and controller.current_states[event.actor_player_id].team != event.actor_team:
			smoke = event
			break
	var late_team: String = controller.current_states[smoke.actor_player_id].team
	check(late_team != smoke.actor_team, "Fixture includes real side switch")
	clock.seek(smoke.time + 1)
	for view in combat.utility.pool:
		if view.visible and view.event_id == smoke.id:
			check(Palette.team_color(smoke.actor_team) != Palette.team_color(late_team), "Historical smoke retains throw-time color after side switch")
	check(Palette.team_color("T") != Palette.team_color("CT"), "Unified T / CT palette differs")
	clock.seek(600)
	var kill_time: float = combat.recent_kills[0].time
	main.combat_panel.kill_rows[0].pressed.emit()
	check(absf(clock.current_time - maxf(0, kill_time - 2.5)) < 0.00001, "Click kill seeks 2.5 seconds before it")
	# A complete source round: round_start tick 14311, round_end tick 21010.
	var round_start := 14311.0 / 64.0
	var round_end := 21010.0 / 64.0
	var started := Time.get_ticks_usec()
	var round_steps := 0
	clock.seek(round_start)
	clock.set_speed(1)
	clock.play()
	while clock.current_time < round_end:
		clock.advance(1.0 / 16.0)
		round_steps += 1
	clock.pause()
	report.round_replay = {"from": round_start, "to": round_end, "steps": round_steps, "cpu_ms": (Time.get_ticks_usec() - started) / 1000.0}
	check(clock.current_time >= round_end, "Complete real-round interval advances with effects")
	for speed in [0.5, 1.0, 2.0]:
		clock.seek(60); clock.set_speed(speed); clock.play(); clock.advance(2)
		check(is_equal_approx(clock.current_time, 60 + 2 * speed), "V2 speed %.1f" % speed)
		clock.pause(); clock.advance(3)
		check(is_equal_approx(clock.current_time, 60 + 2 * speed), "V2 pause freezes effects")
	if "--visual" in OS.get_cmdline_user_args():
		var camera = main.get_node("TacticalCamera")
		main.view_controls.mode.select(2); main.view_controls.apply_mode()
		camera.size = 36
		camera.target = controller.map_transform.position_to_godot(first.fire.position)
		camera._update_pose()
		clock.seek(first.fire.time + 2)
		await screenshot("m4-fire.png")
		camera.target = controller.map_transform.position_to_godot(smoke.position); camera._update_pose()
		clock.seek(smoke.time + 1)
		await screenshot("m4-smoke.png")
		for type in ["he", "flash"]:
			var event = first[type]
			camera.target = controller.map_transform.position_to_godot(event.position); camera._update_pose()
			clock.seek(event.time + 0.1)
			await screenshot("m4-" + type + ".png")
		clock.seek(mid)
		camera.target = controller.map_transform.position_to_godot(projectile.position_at(mid)); camera._update_pose()
		await screenshot("m4-trajectory.png")
		clock.seek(1609.484375)
		var active: Array = index.get_recent_shots(clock.current_time)
		if not active.is_empty(): camera.target = controller.map_transform.position_to_godot(active[0].origin)
		camera._update_pose()
		await screenshot("m4-shots.png")
		# Real frame loop benchmark in heavy gunfire, no artificial time advance.
		clock.seek(1608); clock.set_speed(1); clock.play(); controller.set_process(true)
		started = Time.get_ticks_usec()
		var frames := 0
		var accumulated_delta := 0.0
		# Complete five replay seconds as well as five wall seconds. Engine delta
		# can be clamped after an OS scheduling stall; allow a bounded recovery.
		while (Time.get_ticks_usec() - started < 5000000 or clock.current_time < 1613) and Time.get_ticks_usec() - started < 15000000:
			await process_frame
			frames += 1
			accumulated_delta += main.get_process_delta_time()
		clock.pause(); controller.set_process(false)
		report.fps = {"frames": frames, "seconds": (Time.get_ticks_usec() - started) / 1000000.0, "average": frames * 1000000.0 / (Time.get_ticks_usec() - started), "gpu": RenderingServer.get_video_adapter_name(), "resolution": str(root.size)}
		report.fps.replay_seconds = clock.current_time - 1608.0
		report.fps.engine_delta_seconds = accumulated_delta
		check(clock.current_time >= 1613, "Real frame loop plays through gunfire")
		check(absf(report.fps.replay_seconds - accumulated_delta) < 0.2, "ReplayClock follows engine frame delta")
		if "--full-round" in OS.get_cmdline_user_args():
			clock.seek(round_start); clock.set_speed(2); clock.play(); controller.set_process(true)
			camera.reset_view()
			started = Time.get_ticks_usec()
			var round_frames := 0
			var seen_types := {}
			while clock.current_time < round_end and Time.get_ticks_usec() - started < 90000000:
				await process_frame
				round_frames += 1
				for event in index.get_events_around(clock.current_time, 0.04): seen_types[event.type] = true
			clock.pause(); controller.set_process(false)
			report.rendered_round = {"source_start_tick": 14311, "source_end_tick": 21010, "speed": 2, "seconds": (Time.get_ticks_usec() - started) / 1000000.0, "frames": round_frames, "seen_types": seen_types.keys()}
			check(seen_types.size() == 6, "Complete round renders all six real event types")
			check(clock.current_time >= round_end, "Complete round reaches source round_end")
			await screenshot("m4-complete-round.png")
		DisplayServer.window_set_size(Vector2i(960, 640))
		await screenshot("m4-960.png")
	report.counts = counts
	report.max_seek_cpu_ms = seek_max_us / 1000.0
	report.pools = {"utility": combat.utility.pool.size(), "grenades": combat.projectiles.pool.size(), "shot_nodes": combat.shots.get_child_count()}
	check(main.open_replay("res://data/mock_replay.json"), "V2 → V1 reload")
	check(combat.index.events.is_empty() and combat.utility.active_ids.is_empty() and combat.shots.shot_count == 0, "V1 clears all V2 effects")
	report.checks = checks; report.failures = failures
	var file := FileAccess.open("res://../artifacts/milestone-4-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("M4 REPORT: ", JSON.stringify(report))
	main.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
