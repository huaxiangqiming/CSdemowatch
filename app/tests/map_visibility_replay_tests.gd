extends SceneTree
var checks := 0
var failures: Array = []
var swaps := 0
var app: Node
var output := ""
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); printerr("FAIL: " + message)
func wait_ready() -> void:
	var started := Time.get_ticks_msec()
	while app.state == app.AppState.LOADING and Time.get_ticks_msec() - started < 90000: await process_frame
	check(app.state == app.AppState.REPLAY, "Real Demo opens")
func run() -> void:
	output = OS.get_environment("CS2_REPLAY_DATA_ROOT")
	root.size = Vector2i(1440, 900)
	app = load("res://scenes/Application.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.map_swapped.connect(func(before: Dictionary, after: Dictionary):
		swaps += 1
		check(before == after, "Hot swap preserves time, speed, camera, selected player, layers and combat")
		check(app.viewer.map_manager.cutaway_enabled and is_equal_approx(app.viewer.map_manager.cutaway_height, 2.5), "Hot swap preserves custom cutaway")
	)
	var project := OS.get_environment("M81_PROJECT")
	var demo := project.path_join("test_data/dust2-short.dem")
	app.open_demo(demo)
	await wait_ready()
	if app.state != app.AppState.REPLAY: quit(1); return
	check(app.viewer.map_manager.model == null, "Empty map cache uses fallback")
	check(app.viewer.map_manager.cutaway_enabled, "Tall geometry trim enabled by default")
	app.viewer.map_manager.set_cutaway(true, 2.5)
	app.viewer.controller.clock.seek(2.0)
	app.viewer.controller.clock.set_speed(0.5)
	app.viewer.combat.set_layer("shots", false)
	var started := Time.get_ticks_msec()
	while app.map_queue.active != null and Time.get_ticks_msec() - started < 90000: await process_frame
	check(app.viewer.map_manager.model != null and swaps == 1, "Automatic preparation and hot swap")
	await process_frame
	check(is_equal_approx(app.viewer.map_manager.cutaway_height, 2.5), "UI refresh preserves cutaway height")
	app.viewer.combat_panel.current_tab = 0
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("real-dust2-cutaway.png"))
	var prepared: int = app.map_queue.prepare_counts.get("de_dust2", 0)
	app.go_home()
	app.open_demo(demo)
	await wait_ready()
	check(app.last_cache_hit, "Replay cache reused")
	check(app.viewer.map_manager.model != null and app.map_queue.prepare_counts.get("de_dust2", 0) == prepared, "Map cache reused without conversion")
	# A reload in the same scene must preserve a disabled cutaway too.
	app.viewer.map_manager.set_cutaway(false, 3.75)
	app.viewer.reload_map()
	await process_frame
	check(not app.viewer.map_manager.cutaway_enabled and is_equal_approx(app.viewer.map_manager.cutaway_height, 3.75), "Reload preserves disabled cutaway and height")
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "swaps": swaps}, "  "))
	print("Real map lifecycle: ", checks, " checks; failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
