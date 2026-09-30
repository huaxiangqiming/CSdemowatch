extends SceneTree
var failures: Array = []
var checks := 0
var output := ""
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); printerr(message)
func snap(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))
func run() -> void:
	output = ProjectSettings.globalize_path("res://../artifacts/m81")
	root.size = Vector2i(1280, 900)
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.debug_overlay.hide()
	main.controller.clock.pause()
	main.timeline.hide()
	main.combat_panel.current_tab = 0
	var caption := Label.new()
	caption.position = Vector2(20, 20)
	main.get_node("UI").add_child(caption)
	# Map-only acceptance: mock players hidden, never presented as real Demo evidence.
	for player in main.controller.player_views.values(): player.hide()
	var manager = main.map_manager
	var camera = main.get_node("TacticalCamera")
	var names := DirAccess.get_directories_at(OS.get_environment("CS2_MAP_CACHE_ROOT"))
	var results := {}
	for name in names:
		if not name.begins_with("de_"): continue
		manager.configure(name, main.controller.replay, main.get_node("TestPlane"))
		check(manager.model != null, name + " loads current cache")
		if manager.model == null: continue
		caption.text = name + " / Local geometry inspection / No Demo loaded"
		# Navigation height bands keep Vertigo's building shell out of the
		# camera target. These are map-only views, not replay alignment tests.
		var framing: AABB = manager.map_bounds
		var safety_path := output.path_join("safety/" + name + "/map.glb.safety.json")
		if FileAccess.file_exists(safety_path):
			var safety: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(safety_path))
			var heights: Array = safety.nav_height_bands_256.keys().map(func(key): return float(key) * 2.56)
			heights.sort()
			framing.position.y = heights.front()
			framing.size.y = heights.back() + 2.56 - heights.front()
		manager.set_cutaway(false, framing.end.y + 2.0)
		await process_frame
		camera.configure_bounds(framing, false)
		camera.size = maxf(manager.map_bounds.size.x * 0.9, manager.map_bounds.size.z * 1.15)
		camera.clearance_height = manager.map_bounds.end.y + 1
		camera.set_preset(1)
		await snap(name + "-top")
		camera.set_preset(2)
		await snap(name + "-tactical")
		var original_time: float = main.controller.clock.current_time
		var height: float = framing.get_center().y + 1.5
		main.view_controls.height_slider.value = height
		main.view_controls.cutaway.button_pressed = true
		check(manager.cutaway_enabled, name + " cutaway enabled from UI")
		check(is_equal_approx(manager.cutaway_material.get_shader_parameter("ceiling_height"), main.view_controls.height_slider.value), name + " shader height")
		# Slider rounds to 0.1, compare actual control value in the render path.
		manager.set_cutaway(true, height)
		await snap(name + "-cutaway")
		check(main.controller.clock.current_time == original_time, name + " cutaway preserves ReplayClock")
		for mesh in manager.model.find_children("*", "MeshInstance3D", true, false):
			check(mesh.material_override == manager.cutaway_material, name + " cutaway applies to mesh")
		manager.set_opacity(0.5)
		check(is_equal_approx(manager.cutaway_material.get_shader_parameter("map_color").a, 0.5), name + " cutaway opacity")
		manager.set_opacity(1.0)
		main.view_controls.cutaway.button_pressed = false
		check(not manager.cutaway_enabled, name + " full geometry restored")
		results[name] = {"triangles": manager.triangles, "removed": manager.roof_removed, "bounds": str(manager.map_bounds), "load_ms": manager.loading_ms}
		print("VISUAL ", name)
	var file := FileAccess.open(output.path_join("visual-report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "maps": results}, "  "))
	print("Map visibility checks: ", checks, " failures: ", failures.size())
	quit(0 if failures.is_empty() else 1)
