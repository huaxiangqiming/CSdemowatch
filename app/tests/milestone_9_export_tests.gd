extends SceneTree
var checks := 0
var failures := []
var app: Node
var project := ""
var output := ""
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr(label)
func open(path: String, hash := "") -> bool:
	app.open_demo(path,hash)
	var started := Time.get_ticks_msec()
	while app.state == app.AppState.LOADING and Time.get_ticks_msec()-started < 120000: await process_frame
	check(app.state == app.AppState.REPLAY,"Replay opens: "+path.get_file())
	return app.state == app.AppState.REPLAY
func _initialize() -> void: run.call_deferred()
func run() -> void:
	project=OS.get_environment("M9_PROJECT");output=OS.get_environment("CS2_REPLAY_DATA_ROOT")
	root.size=Vector2i(1440,900)
	app=load("res://scenes/Application.tscn").instantiate();root.add_child(app);await process_frame
	check(OS.has_feature("standalone"),"Formal Windows EXE")
	var demo:=project.path_join("test_data/dust2-short.dem")
	var hash:=FileAccess.get_sha256(demo)
	if not await open(demo):quit(1);return
	check(not app.last_cache_hit and app.viewer.controller.replay.has("stream"),"Fresh Demo creates streaming cache")
	var cache=load("res://scripts/application/ReplayCache.gd").new()
	check(cache.valid(hash) and cache.path(hash).ends_with(".replay"),"Binary cache committed")
	app.viewer.controller.clock.seek(10.1)
	app.viewer.combat_panel.current_tab=0
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("formal-replay.png"))
	app.go_home()
	await open(demo)
	check(app.last_cache_hit and app.viewer.controller.replay.has("stream"),"Second open hits binary cache")
	app.go_home()
	var damaged:=FileAccess.open(cache.path(hash),FileAccess.READ_WRITE);damaged.seek_end();damaged.store_8(0);damaged.close()
	await open(demo)
	check(not app.last_cache_hit and cache.valid(hash),"Corrupt binary rebuilt automatically")
	app.go_home()
	var legacy: String=cache.folder(hash).path_join("replay.json")
	var lines:=[]
	var exit_code:=OS.execute(project.path_join("dist/windows/cs2parser.exe"),[demo,legacy],lines,true,false)
	check(exit_code==0 and cache.commit(hash,demo,legacy),"Prepare legacy cache fixture")
	var manifest:Dictionary=cache.manifest(hash)
	manifest.parser_version="0.6.0";manifest.erase("file_name");manifest.erase("storage_version")
	var file:=FileAccess.open(cache.folder(hash).path_join("cache.json"),FileAccess.WRITE);file.store_string(JSON.stringify(manifest));file.close()
	await open(project.path_join("artifacts/m9/missing-original.dem"),hash)
	check(app.last_cache_hit and not app.viewer.controller.replay.has("stream"),"Legacy 0.6 cache opens even without source Demo")
	app.go_home()
	file=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "));file.close()
	print("M9 formal EXE: ",checks," failures=",failures.size());quit(0 if failures.is_empty() else 1)
