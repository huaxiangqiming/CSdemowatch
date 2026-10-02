extends SceneTree
var failures := []
var checks := 0
var output := "res://../artifacts/m93/"
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr(label)
func screenshot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output + name + ".png")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var project: String = OS.get_environment("M9_PROJECT") if OS.has_feature("standalone") else ProjectSettings.globalize_path("res://..")
	output = project.path_join("artifacts/m93/")
	root.size = Vector2i(1280,800)
	root.gui_embed_subwindows = true
	var app = load("res://scenes/Application.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var initial: String = app.dialog.current_dir
	check(initial != OS.get_executable_path().get_base_dir(), "Picker starts outside application installation")
	app.dialog.current_dir = project.path_join("test_data")
	app._show_demo_dialog()
	await screenshot("demo-picker-1280")
	check(app.dialog.get_theme_stylebox("panel", "ItemList").bg_color.get_luminance() > 0.8, "File list has a light surface")
	check(app.dialog.get_theme_color("font_color", "ItemList").get_luminance() < 0.3, "File names have dark readable ink")
	check(app.dialog.display_mode == FileDialog.DISPLAY_LIST, "File picker uses readable list")
	app.dialog.hide()
	root.size = Vector2i(960,640)
	app._show_demo_dialog()
	await screenshot("demo-picker-960")
	check(app.dialog.size.x <= root.size.x and app.dialog.size.y <= root.size.y, "Picker fits minimum window")
	app.dialog.hide()
	root.remove_child(app); app.free()
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	main.debug_overlay.hide(); main.combat_panel.hide()
	for fixture in ["ancient", "mirage"]:
		check(main.open_replay(project.path_join("artifacts/m9/"+fixture+".replay")), "Real replay opens")
		main.controller.clock.seek(main.combat.index.kills[0].time + 0.25)
		var states: Dictionary = main.controller.current_states.duplicate(true)
		var rig = main.get_node("TacticalCamera")
		var home_size: float = rig.size
		for dimensions in [Vector2i(960,640),Vector2i(1280,800),Vector2i(1440,900)]:
			root.size = dimensions
			await process_frame; await process_frame
			await screenshot(fixture+"-larger-map-"+str(dimensions.x))
			check(root.get_visible_rect().encloses(main.timeline.slider.get_global_rect()), "Timeline stays inside window")
		var dead := 0
		for view in main.controller.player_views.values():
			if not view._alive:
				dead += 1
				check(not view.get_node("Name").visible, "Recorded death hides its label")
			else:
				check(view.get_node("Name").visible and view.get_node("Name").layers == 1, "Living names render directly at player positions")
		check(dead > 0, "Fixture includes a recorded death")
		main.combat.set_layer("dead_names", true)
		check(main.controller.player_views.values().all(func(v):return v.get_node("Name").visible), "Dead names can be restored")
		main.combat.set_layer("dead_names", false)
		main.combat.set_layer("names", false)
		check(main.controller.player_views.values().all(func(v):return not v.get_node("Name").visible), "Names toggle hides direct labels")
		main.combat.set_layer("names", true)
		main.combat.set_layer("players", false)
		check(main.controller.player_views.values().all(func(v):return not v.visible), "Player toggle hides players and their labels")
		main.combat.set_layer("players", true)
		for mode in 3:
			main.view_controls.mode.select(mode); main.view_controls.apply_mode()
			check(main.controller.player_views.values().all(func(v):return v.get_node("Name").no_depth_test == (mode != 0)), "Direct labels honor viewing mode depth")
		main.view_controls.mode.select(1); main.view_controls.apply_mode()
		rig.zoom(2)
		check(rig.size < home_size, "Wheel zoom can enlarge map further")
		rig.toggle_projection(); rig.reset_view()
		check(is_equal_approx(rig.size, home_size) and not rig.perspective, "Home restores enlarged default framing")
		check(main.controller.current_states == states, "Framing and names preserve replay facts")
	var report := FileAccess.open(output+"readability-report.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	print("Readability checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
