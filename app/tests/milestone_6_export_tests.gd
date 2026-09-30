extends SceneTree
var app:Node
var checks:=0
var failures:Array=[]
var report:Dictionary={}
var output:=""
var demo:=""
var ancient:=""
func _initialize() -> void:run.call_deferred()
func check(ok:bool,text:String)->void:
	checks+=1
	if not ok:failures.append(text);printerr("FAIL: "+text)
func arg(key:String)->String:
	var args:=OS.get_cmdline_user_args();var i:=args.find(key);return args[i+1] if i>=0 and i+1<args.size() else ""
func snap(name:String)->void:
	await create_timer(0.2).timeout;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("m6-export-"+name+".png"))
func wait_open()->void:
	var start:=Time.get_ticks_msec();var last:=Time.get_ticks_usec();var gap:=0;var frames:=0
	while app.state==app.AppState.LOADING and Time.get_ticks_msec()-start<45000:
		await process_frame
		var now:=Time.get_ticks_usec();gap=maxi(gap,now-last);last=now;frames+=1
	report.max_loading_gap_ms=maxf(report.get("max_loading_gap_ms",0),gap/1000.0);report.loading_frames=report.get("loading_frames",0)+frames
	check(app.state!=app.AppState.LOADING,"Load completes")
	if app.state==app.AppState.ERROR and app.last_error.code=="MAP_UNAVAILABLE":
		app._commit_scene();await wait_open()
func run()->void:
	output=arg("--artifacts");demo=arg("--demo");ancient=arg("--ancient")
	root.size=Vector2i(1280,720)
	app=load("res://scenes/Application.tscn").instantiate();root.add_child(app);current_scene=app
	await process_frame
	check(app.state==app.AppState.HOME,"Formal exported exe starts HOME")
	check(OS.get_executable_path().get_file()=="CS2TacticalReplay.exe","Testing actual distributed executable")
	await snap("home")
	var second:bool="--second" in OS.get_cmdline_user_args()
	if second:
		check(app.settings.values.smoke_visibility==2 and app.settings.values.map_opacity==0.5 and app.settings.values.name_size==18,"Settings survive process restart")
		check(app.recent.entries.size()>0,"Recent replays survive process restart")
		app.home.recent_requested.emit(app.recent.entries[0])
	else:
		# Invoke exact FileDialog user signal: validates the production wiring.
		app.dialog.file_selected.emit(demo)
	await snap("loading")
	await wait_open()
	check(app.state==app.AppState.REPLAY,"Export pipeline enters REPLAY")
	if app.state!=app.AppState.REPLAY:finish(second);return
	check(app.last_cache_hit==second,"Cache miss first process / hit second process")
	report.open_ms=app.last_open_ms
	root.size=Vector2i(1920,1080)
	app.viewer.controller.clock.seek(536.7)
	await snap("replay")
	if second:
		app.settings.reset_defaults()
		var clock=app.viewer.controller.clock
		var started:=Time.get_ticks_usec();var frames:=0
		clock.seek(530);clock.play()
		while Time.get_ticks_usec()-started<5000000:await process_frame;frames+=1
		clock.pause();report.fps=frames/((Time.get_ticks_usec()-started)/1000000.0)
		report.replay_memory=Performance.get_monitor(Performance.MEMORY_STATIC)
		clock=null
		app.go_home();await process_frame;await process_frame
		report.home_memory=Performance.get_monitor(Performance.MEMORY_STATIC)
		check(app.viewer==null,"Export HOME releases session")
		app.open_demo(ancient);await wait_open()
		check(app.state==app.AppState.REPLAY and app.viewer.controller.replay.metadata.map=="de_ancient","Export A -> HOME -> B")
		await snap("ancient")
		app.go_home()
	else:
		app.show_settings();app.settings.set_value("smoke_visibility",2);app.settings.set_value("map_opacity",0.5);app.settings.set_value("name_size",18);app.settings_screen.sync();await snap("settings")
		app.go_home();await snap("recent-replays")
	finish(second)
func finish(second:bool)->void:
	report.checks=checks;report.failures=failures
	var f:=FileAccess.open(output.path_join("m6-export-second.json" if second else "m6-export-first.json"),FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close()
	print("EXPORT M6 ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
