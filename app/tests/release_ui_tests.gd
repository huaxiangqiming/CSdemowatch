extends SceneTree
var checks := 0
var failures := []
var output := "res://../artifacts/m91/"
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label);printerr(label)
func screenshot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output + name + ".png")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size=Vector2i(1280,800)
	var app=load("res://scenes/Application.tscn").instantiate()
	root.add_child(app)
	await process_frame
	check(app.state==app.AppState.HOME,"Starts on Home")
	await screenshot("home")
	app.show_settings()
	await screenshot("settings")
	check(app.settings_screen.controls.has("background_tone"),"Background control available")
	app.settings.set_value("background_tone",1)
	var settings=load("res://scripts/application/SettingsStore.gd").new()
	settings.load_settings()
	check(settings.values.background_tone==1,"Background preference persists")
	app.go_home()
	var path := ProjectSettings.globalize_path("res://../artifacts/m9/ancient.replay")
	var loaded:Dictionary=load("res://scripts/core/ReplayLoader.gd").new().load_replay(path)
	check(loaded.ok,"Binary replay loads")
	if not loaded.ok:quit(1);return
	app.demo_path="Ancient review.dem"
	app.pending_result={"ok":true,"data":loaded.data,"replay_path":path,"demo_hash":"ui-test"}
	await app._commit_scene()
	app.viewer.controller.clock.seek(500)
	check(app.viewer.get_node("WorldEnvironment").environment.background_color==preload("res://scripts/config/ScenePalette.gd").preset(1).background,"Saved scene background applied")
	app.settings.set_value("background_tone",0)
	for dimensions in [Vector2i(1280,800),Vector2i(960,640),Vector2i(1440,900)]:
		root.size=dimensions
		await process_frame;await process_frame
		var panel:Rect2=app.viewer.combat_panel.get_global_rect()
		check(panel.end.y<=root.get_visible_rect().size.y-166,"Side panel stays above timeline")
		check(panel.position.x>=0 and panel.end.x<=root.get_visible_rect().size.x,"Side panel stays inside window")
		await screenshot("replay-"+str(dimensions.x))
	app.viewer.combat_panel.hide()
	check(not app.viewer.combat_panel.visible,"Panels can collapse")
	await screenshot("replay-focus")
	app.viewer.controller.clock.play()
	app.show_settings()
	check(not app.viewer.controller.clock.is_playing,"Settings pauses playback")
	app.settings.set_value("background_tone",2)
	check(app.viewer.get_node("WorldEnvironment").environment.background_color==preload("res://scripts/config/ScenePalette.gd").preset(2).background,"Background change applies immediately")
	app.settings.reset_defaults()
	check(app.viewer.get_node("WorldEnvironment").environment.background_color==preload("res://scripts/config/ScenePalette.gd").preset(0).background,"Reset restores light background")
	app.go_home()
	check(app.viewer==null and app.state==app.AppState.HOME,"Home releases replay session")
	var file:=FileAccess.open(output+"ui-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	print("M9.1 UI checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
