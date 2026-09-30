extends SceneTree
const MainScene = preload("res://scenes/Main.tscn")
var checks := 0
var failures: Array[String] = []
var report := {}

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event)

func button(point: Vector2, index: MouseButton, pressed: bool, alt := false) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = index
	event.pressed = pressed
	event.alt_pressed = alt
	root.push_input(event, true)

func motion(point: Vector2, relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.relative = relative
	root.push_input(event, true)

func screenshot(path: String) -> Image:
	await create_timer(0.15).timeout
	current_scene.debug_overlay.refresh()
	await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image()
	result.save_png(ProjectSettings.globalize_path("res://../artifacts/" + path))
	return result

func _run() -> void:
	var main = MainScene.instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	var controller = main.controller
	controller.set_process(false)
	var manager = main.map_manager
	var camera = main.get_node("TacticalCamera")
	check(manager.model != null, "Ancient GLB loads")
	if manager.model == null:
		printerr("Pass -- --replay test_data/public-s2.replay.json")
		quit(1)
		return
	check(controller.player_views.size() == 10, "Ten real players on Ancient")
	check(not main.get_node("TestPlane").visible, "Real geometry replaces Plane")
	check(camera.lens.get_parent() == camera.pivot and camera.pivot.get_parent() == camera, "Camera Rig / Pivot / Camera3D hierarchy")
	var transform = preload("res://scripts/map/MapTransform.gd").new()
	transform.scale_factor = 0.02
	transform.rotation_degrees = 90
	transform.offset = Vector3(1, 2, 3)
	check(transform.position_to_godot(Vector3(100, 200, 300)).is_equal_approx(Vector3(-3, 8, 1)), "Configured scale, rotation and offset use one transform")
	check(is_zero_approx(transform.yaw_to_godot(0)), "Map rotation also rotates player yaw")
	key(KEY_1)
	check(camera.pitch == camera.MAX_PITCH and not camera.perspective, "Top preset")
	key(KEY_2)
	check(camera.pitch == 45 and not camera.perspective, "45 degree preset")
	key(KEY_3)
	check(camera.perspective, "Free perspective preset")
	key(KEY_P)
	check(not camera.perspective, "Projection shortcut")
	var point := Vector2(650, 380)
	var yaw: float = camera.yaw
	button(point, MOUSE_BUTTON_MIDDLE, true)
	motion(point + Vector2(60, 20), Vector2(60, 20))
	button(point, MOUSE_BUTTON_MIDDLE, false)
	check(camera.yaw != yaw and not camera._orbiting, "Middle drag orbits")
	yaw = camera.yaw
	button(point, MOUSE_BUTTON_LEFT, true, true)
	motion(point + Vector2(-30, -10), Vector2(-30, -10))
	button(point, MOUSE_BUTTON_LEFT, false, true)
	check(camera.yaw != yaw and not camera._orbiting, "Alt left drag orbits")
	var pivot_before: Vector3 = camera.target
	camera.orbit_pixels(Vector2(1200, 100000))
	check(camera.pitch == camera.MAX_PITCH and camera.target == pivot_before, "Orbit preserves pivot and upper pitch limit")
	camera.orbit_pixels(Vector2(1200, -100000))
	check(camera.pitch == camera.MIN_PITCH, "Lower pitch limit")
	camera.zoom(100)
	check(camera.size == camera.MIN_SIZE, "Minimum zoom")
	check(camera.lens.global_position.y >= camera.clearance_height - 0.001, "Camera remains above geometry ceiling")
	camera.zoom(-100)
	check(camera.size == camera._max_size, "Maximum zoom")
	key(KEY_HOME)
	check(camera.size == camera._home_size and camera.target == camera._home_target, "Home restores framing")
	for mode in 3:
		main.view_controls.mode.select(mode)
		main.view_controls.apply_mode()
		for player in controller.player_views.values():
			check(player.get_node("XRay").visible == (mode != 0), "View mode toggles X-Ray pass")
			check(player.get_node("Name").no_depth_test == (mode != 0), "Label depth follows mode")
			check(player.get_node("Name").billboard == BaseMaterial3D.BILLBOARD_ENABLED, "Labels face camera")
	main.view_controls.mode.select(1)
	main.view_controls.apply_mode()
	for alpha in [1.0, 0.75, 0.5, 0.25]:
		manager.set_opacity(alpha)
		check(is_equal_approx(manager.material.albedo_color.a, alpha), "Map opacity %.2f" % alpha)
	manager.set_opacity(1)
	main.debug_overlay.selector.select(1)
	main.debug_overlay.refresh()
	check(main.debug_overlay.transform_details.text.contains("Pivot:") and main.debug_overlay.transform_details.text.contains("Map scale:"), "Transform debug panel")
	# Use actual mesh triangles for independent vertical ray tests at replay feet.
	var collision_nodes: Array[Node] = []
	for mesh in manager.model.find_children("*", "MeshInstance3D", true, false):
		var body := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var shape: ConcavePolygonShape3D = mesh.mesh.create_trimesh_shape()
		shape.backface_collision = true
		collision.shape = shape
		body.add_child(collision)
		mesh.add_child(body)
		collision_nodes.append(body)
	await physics_frame
	await physics_frame
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var sampled := 0
	var hits := 0
	var supported := 0
	var within_bounds := 0
	var gaps: Array[float] = []
	var misses: Array = []
	var spawn_samples: Array = []
	for id in controller.replay.tracks:
		var frames: Array = controller.replay.tracks[id]
		var first := true
		for i in range(0, frames.size(), 157):
			var frame: Dictionary = frames[i]
			if not frame.alive or not frame.available:
				continue
			var p: Vector3 = manager.map_transform.position_to_godot(frame.position)
			sampled += 1
			if manager.map_bounds.grow(1).has_point(p):
				within_bounds += 1
			var query := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.35, p - Vector3.UP * 8)
			query.hit_back_faces = true
			var hit := space.intersect_ray(query)
			if not hit.is_empty():
				hits += 1
				var gap: float = p.y - hit.position.y
				gaps.append(gap)
				if absf(gap) <= 0.5:
					supported += 1
				if first:
					spawn_samples.append({"player_id": id, "time": frame.time, "raw": [frame.position.x, frame.position.y, frame.position.z], "height_gap_godot": gap})
					first = false
			else:
				var high_query := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 5, p - Vector3.UP * 8)
				high_query.hit_back_faces = true
				var high_hit := space.intersect_ray(high_query)
				misses.append({"raw": [frame.position.x, frame.position.y, frame.position.z], "time": frame.time, "higher_surface_gap": p.y - high_hit.position.y if not high_hit.is_empty() else -999})
	gaps.sort()
	report.alignment = {"samples": sampled, "ray_hits": hits, "within_50_source_units": supported, "inside_map_bounds": within_bounds, "median_ground_gap": gaps[gaps.size() / 2] if not gaps.is_empty() else -999, "first_available_samples": spawn_samples, "misses": misses}
	check(sampled > 500 and float(within_bounds) / sampled > 0.98, "Real movement remains inside map boundaries")
	check(float(hits) / sampled > 0.95, "Ground found under real trajectories")
	check(float(supported) / sampled > 0.85, "Replay feet align with Ancient ground within 50 Source units")
	for body in collision_nodes:
		body.queue_free()
	controller.clock.seek(600)
	camera.set_preset(1)
	if "--visual" in OS.get_cmdline_user_args():
		await create_timer(1.2).timeout
		await screenshot("m3-ancient-top.png")
		camera.set_preset(2)
		camera.zoom(2)
		await screenshot("m3-ancient-tactical.png")
		camera.set_preset(3)
		await screenshot("m3-ancient-perspective.png")
		main.view_controls.mode.select(2)
		main.view_controls.apply_mode()
		await screenshot("m3-ancient-opacity.png")
		var elapsed := 0.0
		var frame_count := 0
		var started := Time.get_ticks_usec()
		controller.set_process(true)
		controller.clock.play()
		while elapsed < 3.0:
			await process_frame
			frame_count += 1
			elapsed = (Time.get_ticks_usec() - started) / 1000000.0
		controller.clock.pause()
		controller.set_process(false)
		report.fps = {"frames": frame_count, "seconds": elapsed, "average": frame_count / elapsed, "renderer": RenderingServer.get_video_adapter_name(), "viewport": str(root.size), "mode": "Tactical", "projection": "Perspective", "msaa": "4x"}
		# Deterministic occlusion fixture exercises the real PlayerView pass.
		manager.model.hide()
		controller.hide()
		main.get_node("WorldAxes").hide()
		main.get_node("UI").hide()
		var player = preload("res://scenes/replay/Player.tscn").instantiate()
		main.add_child(player)
		player.configure({"name": "OCCLUDED", "team": "T"})
		player.position = Vector3(0, 0, -3)
		var wall := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(8, 6, 1)
		wall.mesh = box
		wall.position = Vector3(0, 2, 0)
		main.add_child(wall)
		var camera_fixture := Camera3D.new()
		main.add_child(camera_fixture)
		camera_fixture.position = Vector3(0, 2, 10)
		camera_fixture.look_at(Vector3(0, 1, 0))
		camera_fixture.current = true
		var front_player = preload("res://scenes/replay/Player.tscn").instantiate()
		main.add_child(front_player)
		front_player.configure({"name": "IN FRONT", "team": "CT"})
		front_player.position = Vector3(2, 0, 2)
		front_player.set_view_mode(0)
		player.set_view_mode(0)
		var normal: Image = await screenshot("m3-occlusion-normal.png")
		player.set_view_mode(1)
		var xray: Image = await screenshot("m3-occlusion-xray.png")
		var changed := 0
		for y in range(200, mini(600, normal.get_height()), 2):
			for x in range(400, mini(900, normal.get_width()), 2):
				var a := normal.get_pixel(x, y)
				var b := xray.get_pixel(x, y)
				if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.08:
					changed += 1
		check(changed > 100, "X-Ray visibly reveals player behind opaque wall")
		report.occlusion_changed_pixels = changed
	report.checks = checks
	report.failures = failures
	var file := FileAccess.open("res://../artifacts/milestone-3-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("M3 REPORT: ", JSON.stringify(report))
	main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
