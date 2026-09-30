extends SceneTree
const MainScene = preload("res://scenes/Main.tscn")
const Sampler = preload("res://scripts/core/TrackSampler.gd")
const Transform = preload("res://scripts/map/DebugMapTransform.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.find("--replay") < 0:
		printerr("Real tests require -- --replay <parser-output.json>")
		quit(2)
		return
	var started := Time.get_ticks_msec()
	var main = MainScene.instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	var load_ms := Time.get_ticks_msec() - started
	var controller = main.controller
	if controller.replay.is_empty():
		printerr("FAIL: real replay did not load: ", controller.load_error)
		quit(1)
		return
	controller.set_process(false)
	var clock = controller.clock
	var ui = main.timeline
	var debug = main.debug_overlay
	var count: int = controller.replay.players.size()
	_check(controller.player_views.size() == count, "Dynamic player count matches parser output")
	_check(controller.replay.tracks.size() == count, "Every source player has a track")
	_check(controller.replay.metadata.sample_rate == 16, "Real output is sampled at 16 Hz")
	_check(main.get_node("TestPlane").mesh is PlaneMesh, "Real replay still uses only a Plane")
	_check(main.get_node("TestPlane").position.y <= controller.bounds.position.y, "Debug floor does not hide negative source heights")
	var transform = Transform.new()
	_check(transform.position_to_godot(Vector3(100, 200, 300)).is_equal_approx(Vector3(1, 3, -2)), "CS2 axes and scale conversion")
	_check(is_equal_approx(transform.yaw_to_godot(0), -PI / 2), "CS2 +X direction maps correctly")
	_check(is_zero_approx(transform.yaw_to_godot(PI / 2)), "CS2 +Y direction maps to Godot -Z")
	for time in [0.0, 60.0, 120.0, 600.0, clock.duration * 0.75, 0.5, clock.duration, 2.0]:
		clock.seek(minf(time, clock.duration))
		_check(absf(ui.slider.value - clock.current_time) <= 0.00051, "Seek updates real timeline")
		for id in controller.player_views:
			var raw: Dictionary = Sampler.sample(controller.replay.tracks[id], clock.current_time)
			var view = controller.player_views[id]
			_check(view.position.is_equal_approx(transform.position_to_godot(raw.position)), "Real XYZ matches transformed source sample")
			_check(absf(wrapf(view.get_node("Facing").rotation.y - transform.yaw_to_godot(raw.yaw), -PI, PI)) < 0.0001, "Real yaw matches source sample")
			_check(view.visible == raw.available, "Availability controls visibility")
			_check(view.get_node("Facing").visible == raw.alive, "Alive state controls facing marker")
	# Arbitrary seek into midpoints of actual moving segments, including Y height.
	var movement_found := false
	var death_checked := false
	var side_checked := false
	for id in controller.replay.tracks:
		var frames: Array = controller.replay.tracks[id]
		for i in range(1, frames.size()):
			var a: Dictionary = frames[i - 1]
			var b: Dictionary = frames[i]
			if not movement_found and a.available and b.available and a.alive and b.alive and a.team == b.team and b.time - a.time <= 0.1 and a.position.distance_to(b.position) > 1 and a.position.distance_to(b.position) < 100:
				clock.seek((a.time + b.time) * 0.5)
				var expected: Vector3 = transform.position_to_godot(a.position.lerp(b.position, 0.5))
				_check(controller.player_views[id].position.is_equal_approx(expected), "Real moving segment interpolates at midpoint")
				movement_found = true
			if not death_checked and a.alive and not b.alive and a.available and b.available:
				clock.seek(b.time)
				_check(not controller.current_states[id].alive and controller.player_views[id].get_node("Body").scale.y < 1, "Death sample renders a gray flattened capsule")
				clock.seek(a.time)
				_check(controller.current_states[id].alive and controller.player_views[id].get_node("Body").scale.y == 1, "Backward seek restores alive appearance")
				death_checked = true
			if not side_checked and a.team != b.team and b.available and b.alive:
				clock.seek(b.time)
				var expected_color := Color("ffb454") if b.team == "T" else Color("66b9ff")
				_check(controller.player_views[id].get_node("Body").material_override.albedo_color == expected_color, "Side swap changes actual player color")
				side_checked = true
			if movement_found and death_checked and side_checked:
				break
		if movement_found and death_checked and side_checked:
			break
	_check(movement_found, "Demo contains verifiable actual movement")
	for i in 3:
		clock.seek(60)
		_click(ui.speed_buttons[i].get_global_rect().get_center())
		_click(ui.play_button.get_global_rect().get_center())
		clock.advance(2)
		_check(absf(clock.current_time - (60 + 2 * [0.5, 1.0, 2.0][i])) < 0.0001, "Real playback speed via UI")
		_click(ui.pause_button.get_global_rect().get_center())
		var paused_time: float = clock.current_time
		clock.advance(2)
		_check(clock.current_time == paused_time, "Real Pause freezes clock")
	var rect: Rect2 = ui.slider.get_global_rect()
	var point := Vector2(rect.position.x + rect.size.x * 0.37, rect.get_center().y)
	_click(point)
	_check(clock.current_time > clock.duration * 0.35 and clock.current_time < clock.duration * 0.39, "Real timeline input seeks entire demo duration")
	_check(not clock.is_playing, "Real paused scrubbing remains paused")
	clock.seek(120)
	clock.set_speed(1)
	controller.set_process(true)
	clock.play()
	await create_timer(0.2).timeout
	clock.pause()
	controller.set_process(false)
	_check(clock.current_time > 120, "Real scene frame loop plays the demo")
	clock.seek(120)
	debug.selector.select(1)
	debug.refresh()
	_check(debug.details.text.contains("Raw CS2 XYZ") and debug.details.text.contains("Health:"), "Selected-player overlay includes raw and converted state")
	_check(ui.tick_labels[-1].text == ui._format_time(clock.duration).split(".")[0], "Timeline labels reflect real duration")
	if "--visual" in args:
		# Let FPS counters settle after the synchronous JSON loading stall.
		await create_timer(1.2).timeout
		debug.refresh()
		await _screenshot("real-replay-120s.png")
		clock.seek(600)
		debug.refresh()
		await _screenshot("real-replay-600s.png")
		DisplayServer.window_set_size(Vector2i(960, 640))
		await create_timer(0.2).timeout
		await _screenshot("real-replay-960.png")
	# Preserve the real report before exercising file switching and recovery.
	var report := {"checks": checks, "failures": failures, "map": controller.replay.metadata.map,
		"duration": clock.duration, "players": count, "tracks": controller.replay.tracks.size(),
		"load_ms": load_ms, "movement_verified": movement_found, "death_verified": death_checked,
		"side_swap_verified": side_checked, "render_fps": Engine.get_frames_per_second(),
		"godot_static_memory_bytes": OS.get_static_memory_usage()}
	_check(main.open_replay("res://data/mock_replay.json"), "Real -> Mock reload succeeds")
	_check(controller.player_views.size() == 2 and ui.slider.max_value == 20, "Reload rebuilds dynamic players and timeline range")
	_check(not main.open_replay("res://data/missing.json"), "Missing replay shows an error")
	_check(ui.error_label.visible and not ui.slider.editable, "Failed load disables playback clearly")
	_check(main.open_replay("res://data/mock_replay.json"), "Valid replay recovers after failed load")
	_check(not ui.error_label.visible and ui.slider.editable, "Recovery reenables playback")
	clock.seek(2)
	_check(controller.player_views.player_t.position.is_equal_approx(Vector3(2, 0, -1.5)), "Reload keeps original Mock movement")
	report.checks = checks
	report.failures = failures
	var file := FileAccess.open("res://../artifacts/real-viewer-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("REAL REPORT: ", JSON.stringify(report))
	print("PASS: %d real replay checks" % checks if failures.is_empty() else "FAILED real replay checks")
	main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _click(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)

func _screenshot(filename: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image.save_png(ProjectSettings.globalize_path("res://../artifacts/" + filename)) == OK, "Real screenshot saved")
