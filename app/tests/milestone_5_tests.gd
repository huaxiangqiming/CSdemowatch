extends SceneTree
var checks := 0
var failures: Array[String] = []
var report := {}
var main: Node3D
func _initialize() -> void: run.call_deferred()
func check(value: bool, text: String) -> void:
	checks += 1
	if not value: failures.append(text); printerr("FAIL: ", text)
func snapshot(name: String) -> void:
	if not "--visual" in OS.get_cmdline_user_args(): return
	await create_timer(0.12).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/m5-" + name + ".png"))
func view(event: RefCounted, offset := 0.08) -> void:
	main.controller.clock.seek(event.time + offset)
	var camera = main.get_node("TacticalCamera")
	camera.size = 18
	camera.target = main.controller.map_transform.position_to_godot(event.position)
	camera._update_pose()
func run() -> void:
	main = preload("res://scenes/Main.tscn").instantiate(); root.add_child(main); current_scene = main
	await process_frame
	var controller = main.controller
	controller.set_process(false)
	var combat = main.combat
	var clock = controller.clock
	check(combat.index.events.size() == 3500, "Real M5 replay loaded")
	if combat.index.events.size() != 3500: quit(1); return
	var count := {}; var first := {}; var smoke := {}
	for event in combat.index.events:
		count[event.type] = count.get(event.type, 0) + 1
		if not first.has(event.type): first[event.type] = event
		if event.type == "smoke" and not smoke.has(event.actor_team): smoke[event.actor_team] = event
	check(count.get("bomb_pickup") == 32 and count.get("bomb_drop") == 21 and count.get("bomb_plant") == 11 and count.get("bomb_defuse") == 5 and count.get("bomb_explode", 0) == 0, "Real bomb counts, no invented explosion")
	var names := {"bomb_reset": "Unknown", "bomb_pickup": "Carried", "bomb_drop": "Dropped", "bomb_plant": "Planted", "bomb_defuse": "Defused", "bomb_explode": "Exploded"}
	for i in 160:
		var time: float = fmod(i * 317.271, clock.duration)
		var expected := "Unknown"
		for event in combat.bomb.state_model.events:
			if event.time > time: break
			expected = names[event.type]
		clock.seek(time)
		check(combat.bomb.state.state == expected, "Bomb arbitrary seek")
	for event in combat.bomb.state_model.events:
		clock.seek(event.time + 0.001)
		var last = event
		for same in combat.bomb.state_model.events:
			if same.time == event.time: last = same
		check(combat.bomb.state.state == names[last.type], "Bomb exact event boundary")
	var planted: RefCounted
	for event in combat.bomb.state_model.events:
		if event.type == "bomb_plant" and combat.bomb.state_model.endings.has(event.id): planted = event; break
	check(planted != null, "Fixture has completed planted interval")
	view(planted, 1)
	check(combat.bomb.visible and combat.bomb.state.remaining > 0, "Planted mesh and real outcome timer")
	await snapshot("bomb-planted-timer")
	view(first.bomb_drop, 0.01)
	check(combat.bomb.state.state == "Dropped", "Drop seek state")
	await snapshot("bomb-dropped")
	for team in ["T", "CT"]:
		view(smoke[team], 1)
		for item in combat.utility.pool:
			if item.visible and item.event_id == smoke[team].id:
				check(item.outline_material.albedo_color == preload("res://scripts/config/TeamVisualConfig.gd").team_color(team), "Smoke actual ring uses historical team")
		await snapshot("smoke-" + team.to_lower())
		for mode in [0, 1, 2]:
			combat.smoke_opacity = mode; combat.refresh(clock.current_time)
			for item in combat.utility.pool:
				if item.visible and item.event_id == smoke[team].id:
					check(is_equal_approx(item.material.albedo_color.a, [0.35, 0.55, 0.75][mode]), "Smoke opacity mode")
			if team == "T" and mode > 0: await snapshot("smoke-" + ["low", "tactical", "strong"][mode])
	combat.smoke_opacity = 1
	view(first.flash)
	await snapshot("flash-detonation")
	view(first.he)
	await snapshot("he-shockwave")
	for team in ["T", "CT"]:
		for event in combat.index.events:
			if event.type == "fire" and event.actor_team == team:
				view(event, 1); await snapshot("fire-" + team.to_lower()); break
	for projectile in controller.replay.projectiles:
		if projectile.type != "flash": continue
		var time: float = (projectile.throw_time + projectile.end_time) * 0.5
		clock.seek(time)
		var camera = main.get_node("TacticalCamera")
		camera.size = 12; camera.target = controller.map_transform.position_to_godot(projectile.position_at(time)); camera._update_pose()
		check(combat.projectiles.pool[0].body.mesh != null, "Distinct projectile geometry exists")
		await snapshot("flash-projectile"); break
	for event in combat.index.events:
		if event.type != "flash" or event.affected_players.is_empty(): continue
		var duration: float = event.affected_players[0].flash_duration
		if duration <= 0.01: continue
		view(event, minf(duration / 2, 0.1))
		check(combat.flashed.active_count > 0, "Real flashed player indicator")
		await snapshot("flashed-players")
		combat.set_layer("flashed_players", false)
		check(combat.flashed.active_count == 0, "Hide flashed-player layer")
		combat.set_layer("flashed_players", true); break
	view(first.flash)
	combat.set_layer("flash_effects", false)
	check(not combat.utility.active_ids.has(first.flash.id), "Flash layer independent")
	combat.set_layer("flash_effects", true)
	view(first.he); combat.set_layer("he_effects", false)
	check(not combat.utility.active_ids.has(first.he.id), "HE layer independent")
	combat.set_layer("he_effects", true)
	view(planted, 1); combat.set_layer("bomb", false)
	check(not combat.bomb.visible and not main.bomb_markers.visible, "Bomb layer and markers")
	combat.set_layer("bomb", true)
	# Cache integrity tests use an isolated cache, never the real user cache.
	var cache_root := ProjectSettings.globalize_path("res://../artifacts/cache-test-%d" % Time.get_ticks_usec())
	var assets = preload("res://scripts/map/MapAssetManager.gd").new(cache_root)
	check(not assets.is_map_ready("de_ancient"), "Cache initially absent")
	var prepared: Dictionary = assets.prepare_map("de_ancient")
	check(prepared.ok and not prepared.cache_hit, "Prepare local Ancient once")
	var stamp := FileAccess.get_modified_time(cache_root.path_join("de_ancient/map.glb"))
	check(assets.load_map("de_ancient").ok and assets.prepare_map("de_ancient").cache_hit, "Repeated Ancient cache hit")
	check(stamp == FileAccess.get_modified_time(cache_root.path_join("de_ancient/map.glb")), "Cache hit never rewrites GLB")
	var file := FileAccess.open(cache_root.path_join("de_ancient/map.json"), FileAccess.WRITE); file.store_string("{}"); file.close()
	check(not assets.is_map_ready("de_ancient"), "Invalid map definition rejected")
	check(assets.prepare_map("de_ancient").ok, "Repair invalid definition")
	file = FileAccess.open(cache_root.path_join("de_ancient/map.glb"), FileAccess.WRITE); file.store_string("broken"); file.close()
	check(not assets.is_map_ready("de_ancient"), "Corrupt mesh checksum rejected")
	check(assets.prepare_map("de_ancient").ok, "Repair corrupted GLB")
	check(not assets.prepare_map("../escape").ok and not assets.prepare_map("de_unsupported").ok, "Unsafe and unsupported maps rejected")
	var unsupported: Dictionary = controller.replay.duplicate()
	unsupported.metadata = controller.replay.metadata.duplicate()
	unsupported.metadata.map = "de_unsupported"
	main.map_manager.configure("de_unsupported", unsupported, main.get_node("TestPlane"))
	check(main.map_manager.model == null and main.get_node("TestPlane").visible and main.map_manager.triangles == 0, "Unsupported map renders Debug Plane")
	clock.seek(first.flash.time + 0.08)
	check(combat.utility.active_ids.has(first.flash.id), "Effects remain usable without map")
	await snapshot("unsupported-map-plane")
	main.map_manager.configure(controller.replay.metadata.map, controller.replay, main.get_node("TestPlane"))
	unsupported.clear() # Release the test's copy before measuring reload memory.
	# Actual UI thread keeps ticking throughout a large asynchronous load.
	var path: String = main.current_path
	var old_model: Node3D = main.map_manager.model
	main.request_replay(path)
	var ui_frames := 0; var gap_max := 0; var previous := Time.get_ticks_usec(); var started := previous
	while main.load_job != null and Time.get_ticks_usec() - started < 20000000:
		await process_frame
		var now := Time.get_ticks_usec(); gap_max = maxi(gap_max, now - previous); previous = now; ui_frames += 1
	check(main.load_job == null and main.current_path == path, "Background load completes")
	check(ui_frames > 20, "Main UI continues rendering during decode")
	check(main.map_manager.model == old_model, "Same-map replay reuses resident map")
	report.async_loading = {"milliseconds": main.replay_loading_ms, "ui_frames": ui_frames, "max_frame_gap_ms": gap_max / 1000.0, "memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC)}
	controller.set_process(false)
	main.request_replay("res://missing-replay.json")
	while main.load_job != null: await process_frame
	check(main.current_path == path and controller.replay.events.size() == 3500, "Failed async load preserves active replay")
	main.timeline.error_label.hide()
	if "--visual" in OS.get_cmdline_user_args():
		DisplayServer.window_set_size(Vector2i(1920, 1080)); await process_frame
		main.view_controls.mode.select(2); main.view_controls.apply_mode()
		main.get_node("TacticalCamera").reset_view()
		clock.seek(1608); clock.set_speed(1); clock.play(); controller.set_process(true)
		started = Time.get_ticks_usec(); var frames := 0
		while (Time.get_ticks_usec() - started < 5000000 or clock.current_time < 1613) and Time.get_ticks_usec() - started < 15000000:
			await process_frame; frames += 1
		clock.pause(); controller.set_process(false)
		report.performance = {"fps": frames * 1000000.0 / (Time.get_ticks_usec() - started), "resolution": str(root.size), "gpu": RenderingServer.get_video_adapter_name(), "triangles": main.map_manager.triangles}
		check(clock.current_time >= 1613, "Heavy gunfire actual playback")
		await snapshot("gunfire-kills-1080")
		if "--full-round" in OS.get_cmdline_user_args():
			clock.seek(14311.0 / 64); clock.set_speed(2); clock.play(); controller.set_process(true)
			started = Time.get_ticks_usec()
			while clock.current_time < 21010.0 / 64 and Time.get_ticks_usec() - started < 90000000: await process_frame
			clock.pause(); controller.set_process(false)
			check(clock.current_time >= 21010.0 / 64, "Full real round plays with M5 visuals")
			report.full_round_seconds = (Time.get_ticks_usec() - started) / 1000000.0
		for opacity in [1.0, 0.75, 0.5, 0.25]:
			main.map_manager.set_opacity(opacity); await snapshot("map-opacity-%d" % int(opacity * 100))
	report.counts = count; report.checks = checks; report.failures = failures
	report.cache = {"root": main.map_manager.assets.root, "hit": main.map_manager.cache_hit}
	file = FileAccess.open("res://../artifacts/milestone-5-report.json", FileAccess.WRITE); file.store_string(JSON.stringify(report, "  ")); file.close()
	print("M5 REPORT: ", JSON.stringify(report))
	main.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
