extends SceneTree
## Run with Godot --headless --path app --script res://tests/run_tests.gd.
## -- --visual additionally verifies the real renderer and writes screenshots.
const Loader = preload("res://scripts/core/ReplayLoader.gd")
const Clock = preload("res://scripts/core/ReplayClock.gd")
const Sampler = preload("res://scripts/core/TrackSampler.gd")
const MainScene = preload("res://scenes/Main.tscn")
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001


func _run() -> void:
	_test_loader()
	_test_clock()
	_test_interpolation()
	await _test_scene()
	if failures.is_empty():
		print("PASS: %d checks (loader, clock, interpolation, scene, UI input, camera)." % checks)
	else:
		printerr("FAILED: %d / %d checks" % [failures.size(), checks])
	quit(0 if failures.is_empty() else 1)


func _test_loader() -> void:
	var loader = Loader.new()
	var result: Dictionary = loader.load_replay("res://data/mock_replay.json")
	_check(result.ok, "Valid mock JSON loads")
	if not result.ok:
		return
	_check(result.data.players.size() == 2, "Two players load")
	_check(result.data.metadata.duration == 20, "Duration is 20 seconds")
	_check(result.data.tracks.player_t[0].position is Vector3, "JSON positions become Vector3")
	_check(not loader.load_replay("res://data/missing.json").ok, "Missing file reports failure")
	_check(not loader.parse_text("{broken").ok, "Malformed JSON reports failure")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/mock_replay.json"))
	var cases: Array = []
	var copy: Dictionary = raw.duplicate(true)
	copy.version = 2
	cases.append(copy)
	copy = raw.duplicate(true)
	copy.players[1].id = copy.players[0].id
	cases.append(copy)
	copy = raw.duplicate(true)
	copy.tracks[0].frames[1].time = 0
	cases.append(copy)
	copy = raw.duplicate(true)
	copy.tracks[0].frames[1].position = [0, "bad", 0]
	cases.append(copy)
	copy = raw.duplicate(true)
	copy.tracks[1].player_id = "unknown"
	cases.append(copy)
	copy = raw.duplicate(true)
	copy.tracks[0].frames[-1].time = 19
	cases.append(copy)
	copy = raw.duplicate(true)
	copy.metadata.duration = -2
	cases.append(copy)
	copy = raw.duplicate(true)
	copy.tracks[0].frames[0].yaw = INF
	cases.append(copy)
	copy = raw.duplicate(true)
	copy.metadata.coordinate_system = "cs2"
	cases.append(copy)
	copy = raw.duplicate(true)
	copy.metadata.map = ""
	cases.append(copy)
	copy = raw.duplicate(true)
	copy.players = []
	cases.append(copy)
	copy = raw.duplicate(true)
	copy.tracks = []
	cases.append(copy)
	copy = raw.duplicate(true)
	copy.metadata.source_tick_rate = 0
	cases.append(copy)
	copy = raw.duplicate(true)
	copy.metadata.sample_rate = -1
	cases.append(copy)
	copy = raw.duplicate(true)
	copy.tracks[0].frames[1].position.x = INF
	cases.append(copy)
	copy = raw.duplicate(true)
	copy.tracks[0].frames[1].health = -1
	cases.append(copy)
	copy = raw.duplicate(true)
	copy.tracks[0].frames[1].alive = "true"
	cases.append(copy)
	copy = raw.duplicate(true)
	copy.tracks[0].frames[1].available = false
	cases.append(copy)
	copy = raw.duplicate(true)
	copy.tracks[0].frames[1].tick = 0
	cases.append(copy)
	for index in cases.size():
		_check(not loader.validate(cases[index]).ok, "Invalid replay case %d rejected" % index)
	_check(not loader.validate([]).ok, "Non-object root rejected")


func _test_clock() -> void:
	var clock = Clock.new()
	clock.configure(20)
	clock.advance(1)
	_check(clock.current_time == 0, "Starts paused")
	for speed in [0.5, 1.0, 2.0]:
		clock.seek(0)
		clock.set_speed(speed)
		clock.play()
		clock.advance(2)
		_check(_near(clock.current_time, 2 * speed), "Elapsed time at %sx speed" % speed)
	clock.pause()
	var paused_time: float = clock.current_time
	clock.advance(10)
	_check(clock.current_time == paused_time, "Pause freezes time")
	clock.seek(12.5)
	_check(clock.current_time == 12.5 and not clock.is_playing, "Seek while paused")
	clock.seek(-5)
	_check(clock.current_time == 0, "Negative seek clamps")
	clock.seek(100)
	_check(clock.current_time == 20 and not clock.is_playing, "Past-end seek clamps and pauses")
	clock.play()
	_check(clock.current_time == 0 and clock.is_playing, "Play at end restarts")
	clock.seek(19.9)
	clock.advance(1)
	_check(clock.current_time == 20 and not clock.is_playing, "Playback stops exactly at duration")
	clock.set_speed(-1)
	_check(clock.playback_speed == 2, "Unsupported speed ignored")
	clock.seek(NAN)
	_check(clock.current_time == 20, "Nonfinite seek ignored")
	clock.configure(0)
	clock.play()
	_check(not clock.is_playing, "Zero-duration clock cannot play")


func _test_interpolation() -> void:
	var frames: Array = [
		{"time": 0.0, "position": Vector3.ZERO, "yaw": deg_to_rad(350.0)},
		{"time": 4.0, "position": Vector3(4, 2, -6), "yaw": deg_to_rad(10.0)}]
	var mid: Dictionary = Sampler.sample(frames, 2)
	_check(mid.position.is_equal_approx(Vector3(2, 1, -3)), "XYZ midpoint interpolates")
	_check(absf(wrapf(mid.yaw, -PI, PI)) < 0.0001, "350 to 10 degrees crosses zero along shortest arc")
	_check(Sampler.sample(frames, -1).position == Vector3.ZERO, "Before-start sample clamps")
	_check(Sampler.sample(frames, 50).position == Vector3(4, 2, -6), "After-end sample clamps")
	frames[0].yaw = deg_to_rad(10.0)
	frames[1].yaw = deg_to_rad(350.0)
	_check(absf(wrapf(Sampler.sample(frames, 2).yaw, -PI, PI)) < 0.0001, "Reverse yaw wrap uses shortest arc")
	var replay: Dictionary = Loader.new().load_replay("res://data/mock_replay.json").data
	for time in [20.0, 3.0, 16.0, 0.0, 8.0, 2.0]:
		var state: Dictionary = Sampler.sample(replay.tracks.player_t, time)
		_check(state.position.is_finite(), "Random/backward seek at %s is finite" % time)
	_check(Sampler.sample(replay.tracks.player_t, 8).position == Vector3(800, 300, 0), "Exact RAW keyframe is preserved")
	var a := {"time": 0.0, "tick": 0, "position": Vector3.ZERO, "yaw": 0.0, "health": 100, "alive": true, "available": true, "team": "T"}
	var b := {"time": 0.0625, "tick": 4, "position": Vector3(10, 0, 0), "yaw": 0.5, "health": 50, "alive": true, "available": true, "team": "T"}
	_check(Sampler.sample([a, b], 0.03125).health == 100, "Health is left-held instead of interpolated")
	b.alive = false
	_check(Sampler.sample([a, b], 0.03125).position == Vector3.ZERO, "No interpolation across death/respawn")
	_check(not Sampler.sample([a, b], 0.0625).alive, "Death state changes at its sample")
	b.alive = true
	a.available = false
	_check(not Sampler.sample([a, b], 0.03125).available, "Late join stays hidden before its sample")
	a.available = true
	b.position = Vector3(1000, 0, 0)
	_check(Sampler.sample([a, b], 0.03125).position == Vector3.ZERO, "Large teleport does not sweep across plane")


func _test_scene() -> void:
	var main = MainScene.instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	await process_frame
	var controller = main.controller
	controller.set_process(false)
	var clock = controller.clock
	var ui = main.timeline
	var camera = main.get_node("TacticalCamera")
	controller.set_process(true)
	clock.play()
	await create_timer(0.1).timeout
	clock.pause()
	_check(clock.current_time > 0, "Scene process advances the clock in real frames")
	# Slider has millisecond precision; the clock retains sub-millisecond time.
	_check(absf(ui.slider.value - clock.current_time) <= 0.00051, "Real frame loop synchronizes slider")
	controller.set_process(false)
	_check(controller.player_views.size() == 2, "Main scene displays two player nodes")
	_check(main.get_node("TestPlane").mesh is PlaneMesh, "Test map is a PlaneMesh")
	_check(controller.player_views.player_t.get_node("Body").mesh is CapsuleMesh, "Player is a CapsuleMesh")
	var t_color: Color = controller.player_views.player_t.get_node("Body").material_override.albedo_color
	var ct_color: Color = controller.player_views.player_ct.get_node("Body").material_override.albedo_color
	_check(t_color != ct_color, "T and CT colors differ")
	clock.seek(2)
	_check(controller.player_views.player_t.position.is_equal_approx(Vector3(2, 0, -1.5)), "Seek applies player position synchronously")
	_check(absf(wrapf(controller.player_views.player_t.get_node("Facing").rotation.y, -PI, PI)) < 0.0001, "Seek applies interpolated yaw")
	_check(_near(ui.slider.value, 2), "Seek updates slider")
	clock.play()
	clock.advance(1)
	_check(_near(ui.slider.value, 3), "Playing advances slider")
	# Drive the actual HSlider with viewport input, not just direct clock calls.
	var rect: Rect2 = ui.slider.get_global_rect()
	var start := Vector2(rect.position.x + rect.size.x * 0.4, rect.get_center().y)
	_mouse_button(start, MOUSE_BUTTON_LEFT, true)
	_check(not clock.is_playing and ui._dragging, "Actual slider press pauses during playback")
	var destination := Vector2(rect.position.x + rect.size.x * 0.75, start.y)
	_mouse_motion(destination, destination - start, MOUSE_BUTTON_MASK_LEFT)
	_check(clock.current_time > 14 and clock.current_time < 16, "Dragging slider seeks immediately")
	var sampled: Dictionary = Sampler.sample(controller.replay.tracks.player_t, clock.current_time)
	_check(controller.player_views.player_t.position.is_equal_approx(controller.map_transform.position_to_godot(sampled.position)), "Dragging updates player before release")
	_mouse_button(destination, MOUSE_BUTTON_LEFT, false)
	_check(clock.is_playing and not ui._dragging, "Releasing slider resumes prior playing state")
	clock.pause()
	_mouse_button(start, MOUSE_BUTTON_LEFT, true)
	_mouse_button(start, MOUSE_BUTTON_LEFT, false)
	_check(not clock.is_playing, "Paused scrubbing remains paused")
	clock.play()
	_mouse_button(start, MOUSE_BUTTON_LEFT, true)
	var end := Vector2(rect.end.x - 1, start.y)
	_mouse_motion(end, end - start, MOUSE_BUTTON_MASK_LEFT)
	_mouse_button(end, MOUSE_BUTTON_LEFT, false)
	_check(_near(clock.current_time, 20) and not clock.is_playing, "Dragging to end stays finished")
	for i in 3:
		var button: Button = ui.speed_buttons[i]
		_click(button.get_global_rect().get_center())
		_check(clock.playback_speed == [0.5, 1.0, 2.0][i], "Speed button %d works via input" % i)
	_click(ui.play_button.get_global_rect().get_center())
	_check(clock.is_playing and clock.current_time == 0, "Play button restarts finished replay")
	_click(ui.pause_button.get_global_rect().get_center())
	_check(not clock.is_playing, "Pause button works via input")
	var camera_size: float = camera.size
	var center := Vector2(650, 360)
	_mouse_button(center, MOUSE_BUTTON_WHEEL_UP, true)
	_mouse_button(center, MOUSE_BUTTON_WHEEL_UP, false)
	_check(camera.size < camera_size, "Wheel input zooms camera")
	var before: Vector3 = camera.position
	_mouse_button(center, MOUSE_BUTTON_RIGHT, true)
	_mouse_motion(center + Vector2(80, 30), Vector2(80, 30), MOUSE_BUTTON_MASK_RIGHT)
	_mouse_button(center + Vector2(80, 30), MOUSE_BUTTON_RIGHT, false)
	_check(not camera.position.is_equal_approx(before), "Right drag pans camera")
	_check(not camera._panning, "Right release ends pan")
	var after_pan: Vector3 = camera.position
	_mouse_button(ui.play_button.get_global_rect().get_center(), MOUSE_BUTTON_RIGHT, true)
	_mouse_motion(ui.pause_button.get_global_rect().get_center(), Vector2(50, 0), MOUSE_BUTTON_MASK_RIGHT)
	_mouse_button(ui.pause_button.get_global_rect().get_center(), MOUSE_BUTTON_RIGHT, false)
	_check(camera.position.is_equal_approx(after_pan), "UI controls do not pan camera")
	var home := InputEventKey.new()
	home.keycode = KEY_HOME
	home.pressed = true
	root.push_input(home)
	_check(camera.target.is_equal_approx(Vector3.ZERO) and camera.size == camera.DEFAULT_SIZE, "Home input resets camera")
	camera.zoom(100)
	_check(camera.size == camera.MIN_SIZE, "Zoom-in is bounded")
	camera.zoom(-100)
	_check(camera.size == camera.MAX_SIZE, "Zoom-out is bounded")
	camera.reset_view()
	clock.seek(6)
	clock.pause()
	if "--visual" in OS.get_cmdline_user_args():
		await _screenshot("viewer-1280.png")
		DisplayServer.window_set_size(Vector2i(960, 640))
		await create_timer(0.2).timeout
		var small_image_size: Vector2i = await _screenshot("viewer-960.png")
		_check(ui.slider.get_global_rect().end.x <= root.get_visible_rect().size.x, "Timeline fits minimum window width")
		_check(small_image_size == Vector2i(960, 640), "Minimum-window render is 960 by 640")
	main.queue_free()
	await process_frame


func _mouse_button(point: Vector2, button: int, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button
	event.pressed = pressed
	root.push_input(event, true)


func _mouse_motion(point: Vector2, relative: Vector2, mask: int) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = relative
	event.button_mask = mask
	root.push_input(event, true)


func _click(point: Vector2) -> void:
	_mouse_button(point, MOUSE_BUTTON_LEFT, true)
	_mouse_button(point, MOUSE_BUTTON_LEFT, false)


func _screenshot(filename: String) -> Vector2i:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://../artifacts/" + filename)
	_check(image.save_png(path) == OK, "Renderer screenshot saved: " + filename)
	return image.get_size()
