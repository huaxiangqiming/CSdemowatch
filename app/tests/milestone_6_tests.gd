extends SceneTree
var checks:=0
var failures:Array[String]=[]
var report:Dictionary={}
var app:Node
var artifacts:=ProjectSettings.globalize_path("res://../artifacts")
var demo:=ProjectSettings.globalize_path("res://../test_data/damage-source.dem")
func _initialize() -> void: run.call_deferred()
func check(ok:bool, text:String) -> void:
	checks+=1
	if not ok: failures.append(text);printerr("FAIL: ",text)
func snapshot(name:String) -> void:
	if not "--visual" in OS.get_cmdline_user_args():return
	await create_timer(0.15).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(artifacts.path_join("m6-"+name+".png"))
func wait_open() -> void:
	var start:=Time.get_ticks_msec()
	while app.state==app.AppState.LOADING and Time.get_ticks_msec()-start<45000:await process_frame
	check(app.state!=app.AppState.LOADING,"Open completes within timeout")
func allow_plane() -> void:
	if app.state==app.AppState.ERROR and app.last_error.code=="MAP_UNAVAILABLE":
		app._commit_scene()
		await wait_open()
func focus_player(id:String) -> void:
	var rig=app.viewer.get_node("TacticalCamera")
	rig.size=20;rig.target=app.viewer.controller.player_views[id].position;rig._update_pose()
func run() -> void:
	root.size=Vector2i(1280,720)
	app=preload("res://scenes/Application.tscn").instantiate();root.add_child(app);current_scene=app
	await process_frame
	check(app.state==app.AppState.HOME and app.viewer==null,"Boot HOME without 3D replay")
	await snapshot("home")
	app.files_dropped(PackedStringArray(["notes.txt"]))
	check(app.state==app.AppState.HOME and "dem" in app.home.hint.text,"Invalid drag is friendly")
	# Real drag/drop entry and first-open miss in isolated fresh data root.
	app.files_dropped(PackedStringArray([demo]))
	await snapshot("loading")
	await wait_open()
	check(not app.last_cache_hit,"First open is cache miss and runs parser")
	check(app.state==app.AppState.REPLAY,"M7: Missing map never blocks Replay")
	await snapshot("map-unavailable")
	await allow_plane()
	check(app.state==app.AppState.REPLAY,"Real demo pipeline enters REPLAY")
	if app.state!=app.AppState.REPLAY: finish();return
	report.first_open_ms=app.last_open_ms
	var viewer=app.viewer;var controller=viewer.controller;var combat=viewer.combat
	check(controller.player_views.size()==10,"Real damage demo 10 players")
	check(combat.index.events.size()==1831,"Damage replay event count")
	var events:Array=combat.index.events
	var hurts:=[];var counts:Dictionary={}
	for e in events:
		if e.type=="player_hurt":hurts.append(e);counts[e.damage_source]=counts.get(e.damage_source,0)+1
	check(hurts.size()==264 and counts.hegrenade==15 and counts.inferno==38,"Real HE and fire source counts")
	var resolver=combat.flashed.resolver
	# Independent full-scan truth oracle. Exercise each damage window in reverse order.
	for e in hurts:
		if e.damage_source not in ["hegrenade","inferno"]:continue
		var kind:String="he_hit" if e.damage_source=="hegrenade" else "burning"
		for time in [e.time+1.1,e.time+0.1,e.time-0.01]:
			controller.clock.seek(time)
			var expected:=false
			for source in hurts:
				var width:=0.8 if kind=="he_hit" else 0.75
				if source.victim_player_id==e.victim_player_id and source.damage_source==e.damage_source and source.damage>0 and time>=source.time and time<source.time+width:expected=true
			check((kind in resolver.resolve(time,e.victim_player_id,controller.current_states[e.victim_player_id]))==expected,"Damage status seek window")
	for i in 100:
		var time:=fmod(i*137.291,controller.clock.duration);controller.clock.seek(time)
		for id in controller.current_states:
			var expected:Dictionary={};var state:Dictionary=controller.current_states[id]
			for e in events:
				if e.type=="flash":
					for a in e.affected_players:
						if a.player_id==id and time>=e.time and time<e.time+a.flash_duration:expected.flashed_players=true
				elif e.type=="player_hurt" and e.victim_player_id==id and e.damage>0:
					if e.damage_source=="hegrenade" and time>=e.time and time<e.time+0.8:expected.he_hit=true
					if e.damage_source in ["inferno","molotov","incgrenade","incendiary"] and time>=e.time and time<e.time+0.75:expected.burning=true
				elif e.type=="smoke" and state.alive and time>=e.time and time<e.expire_time:
					if (state.position+Vector3(0,0,85)).distance_to(e.position+Vector3(0,0,116))<=145:expected.in_smoke=true
			var bomb:Dictionary=combat.bomb.state_model.at(time)
			if bomb.state=="Carried" and bomb.carrier==id:expected.bomb_carrier=true
			if not state.available:expected.clear()
			var actual:Array=resolver.resolve(time,id,state)
			check(actual.size()==expected.size() and actual.all(func(k):return expected.has(k)),"Random seek all five statuses")
	# Actual-data status screenshots.
	for pair in [["hegrenade","he-hit"],["inferno","burning"]]:
		for e in hurts:
			if e.damage_source==pair[0]:
				controller.clock.seek(e.time+0.1);focus_player(e.victim_player_id);await snapshot("status-"+pair[1]);break
	var flash_found:=false
	for e in events:
		if e.type=="flash" and not e.affected_players.is_empty():
			controller.clock.seek(e.time+0.1);focus_player(e.affected_players[0].player_id);await snapshot("status-flashed");flash_found=true;break
	check(flash_found,"Real flash screenshot")
	var smoke_found:=false
	for e in events:
		if e.type!="smoke":continue
		for offset in [0.5,2.0,5.0,8.0]:
			controller.clock.seek(minf(e.time+offset,e.expire_time-0.01))
			for id in controller.current_states:
				if "in_smoke" in combat.flashed.current.get(id,[]):
					focus_player(id);await snapshot("status-smoke");smoke_found=true;break
			if smoke_found:break
		if smoke_found:break
	check(smoke_found,"Real tactical smoke occupancy screenshot")
	var carrier_found:=false
	for e in events:
		if e.type=="bomb_pickup":
			controller.clock.seek(e.time+0.1)
			if "bomb_carrier" in combat.flashed.current.get(e.actor_player_id,[]):
				focus_player(e.actor_player_id)
				var v=controller.player_views[e.actor_player_id]
				check(v.get_node("Name").modulate==preload("res://scripts/config/TeamVisualConfig.gd").BOMB,"Carrier name red")
				check(v.get_node("Body").material_override.albedo_color==preload("res://scripts/config/TeamVisualConfig.gd").team_color(controller.current_states[e.actor_player_id].team),"Carrier body remains team color")
				await snapshot("bomb-carrier");carrier_found=true;break
	check(carrier_found,"Carrier screenshot")
	# Explicit visual-only multiple-status fixture: clearly separate from real source facts.
	var id:String=combat.bomb.state.carrier;focus_player(id)
	combat.flashed.current[id]=["flashed_players","burning","in_smoke"]
	combat.flashed.icons[id].set_statuses(combat.flashed.current[id]);combat.flashed._process(0)
	await snapshot("status-multiple")
	check(combat.flashed.icons[id].statuses.size()==3,"Three fixed-spaced icons")
	combat.set_layer("player_status",false)
	check(combat.flashed.current.values().all(func(a):return a.is_empty()),"Status master toggle")
	combat.set_layer("player_status",true)
	# Camera pose regression and playback.
	for preset in [1,2,3]:viewer.get_node("TacticalCamera").set_preset(preset);await process_frame
	for speed in [0.5,1.0,2.0]:
		controller.clock.pause();controller.clock.seek(300);controller.clock.set_speed(speed);controller.clock.play();await create_timer(0.25).timeout;controller.clock.pause();check(controller.clock.current_time>300,"Playback speed advances")
	var paused:float=controller.clock.current_time;await create_timer(0.1).timeout;check(controller.clock.current_time==paused,"Pause stable")
	root.size=Vector2i(1920,1080);controller.clock.seek(540);viewer.get_node("TacticalCamera").reset_view();await snapshot("replay")
	report.replay_memory=Performance.get_monitor(Performance.MEMORY_STATIC)
	app.show_settings();await snapshot("settings")
	app.settings.set_value("smoke_visibility",2);app.settings.set_value("map_opacity",0.5);app.settings.set_value("name_size",18)
	var store=preload("res://scripts/application/SettingsStore.gd").new();store.load_settings()
	check(store.values.smoke_visibility==2 and store.values.map_opacity==0.5 and store.values.name_size==18,"Settings persisted")
	check(viewer.map_manager.opacity==0.5 and combat.smoke_opacity==2,"Settings immediately applied")
	app.settings.reset_defaults();check(app.settings.values.name_size==14,"Reset defaults")
	# Release references before measuring home memory.
	resolver=null;events=[];hurts=[];controller=null;combat=null;viewer=null
	app.go_home();await process_frame;await process_frame
	check(app.viewer==null,"Session scene released")
	var missing_parser=preload("res://scripts/application/DemoOpenService.gd").new()
	missing_parser.cache.root=artifacts.path_join("m6-missing-parser-cache")
	missing_parser.parser_override=artifacts.path_join("does-not-exist.exe")
	missing_parser.start(demo)
	while not missing_parser.done(): await process_frame
	var missing_result:Dictionary=missing_parser.finish()
	check(not missing_result.ok and missing_result.error.code=="PARSER_MISSING","Missing parser handled")
	missing_parser=null;missing_result.clear()
	report.home_memory=Performance.get_monitor(Performance.MEMORY_STATIC)
	await snapshot("recent-replays")
	var entries=preload("res://scripts/application/RecentReplays.gd").new();entries.load_entries();check(entries.entries.size()==1,"Recent metadata persisted")
	app.home.recent_requested.emit(entries.entries[0]);await wait_open();await allow_plane()
	check(app.state==app.AppState.REPLAY and app.last_cache_hit,"Second open cache hit")
	report.second_open_ms=app.last_open_ms
	check(app.viewer.controller.clock.current_time==0 and app.viewer.controller.player_views.size()==10,"New session no old playback state")
	app.go_home()
	var missing_source=preload("res://scripts/application/DemoOpenService.gd").new()
	missing_source.start("C:/missing/damage-source.dem",FileAccess.get_sha256(demo))
	while not missing_source.done(): await process_frame
	var cached:Dictionary=missing_source.finish()
	check(cached.ok and missing_source.cache_hit,"Missing original can reopen intact replay cache")
	cached.clear();missing_source=null
	# Cache corruption repairs automatically through real parser.
	var cache=preload("res://scripts/application/ReplayCache.gd").new();var hash:=FileAccess.get_sha256(demo)
	var f:=FileAccess.open(cache.path(hash),FileAccess.WRITE);f.store_string("broken cache");f.close()
	app.open_demo(demo);await wait_open();await allow_plane();check(app.state==app.AppState.REPLAY and not app.last_cache_hit,"Corrupt cache automatically rebuilt")
	app.go_home()
	app.open_demo("C:/missing/m6.dem");await wait_open();check(app.state==app.AppState.ERROR,"Missing demo friendly error")
	await snapshot("error");app.go_home()
	var bad:=artifacts.path_join("m6-corrupt.dem");f=FileAccess.open(bad,FileAccess.WRITE);f.store_string("not a demo");f.close()
	app.open_demo(bad);await wait_open();check(app.state==app.AppState.ERROR and app.last_error.code=="PARSER_FAILED","Corrupt demo parser failure handled")
	app.go_home()
	# A -> Home -> B with different map/duration/frames.
	var ancient:=ProjectSettings.globalize_path("res://../test_data/s2/s2.dem")
	app.open_demo(ancient);await wait_open();await allow_plane()
	check(app.state==app.AppState.REPLAY and app.viewer.controller.replay.metadata.map=="de_ancient","Second different demo loads Ancient")
	check(app.viewer.controller.clock.duration>1900 and app.viewer.combat.index.events.size()==3500,"No Mirage events leak into Ancient")
	await snapshot("replay-ancient")
	app.go_home()
	app.open_demo(demo);app.cancel_loading();await wait_open();check(app.state==app.AppState.HOME and app.viewer==null,"Safe cancel discards result")
	finish()
func finish() -> void:
	report.checks=checks;report.failures=failures
	var file:=FileAccess.open(artifacts.path_join("milestone-6-report.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("M6 checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
