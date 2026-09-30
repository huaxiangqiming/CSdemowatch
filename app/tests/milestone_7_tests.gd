extends SceneTree
## Executed against the actual exported PCK. Screenshots use only real Replay facts.
var app: Node
var checks:=0
var failures:Array=[]
var report:Dictionary={"maps":{},"he":[],"burning":[]}
var output:=""
var project:=""
func _initialize() -> void:run.call_deferred()
func arg(key: String) -> String:
	var args:=OS.get_cmdline_user_args();var i:=args.find(key);return args[i+1] if i>=0 and i+1<args.size() else ""
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures.append(message);printerr("FAIL: "+message)
func snap(name: String) -> void:
	await create_timer(0.15).timeout;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("m7-"+name+".png"))
func open_demo(file: String) -> bool:
	app.open_demo(project.path_join("test_data/"+file))
	var started:=Time.get_ticks_msec()
	while app.state==app.AppState.LOADING and Time.get_ticks_msec()-started<120000:await process_frame
	check(app.state==app.AppState.REPLAY,"Direct Replay opens: "+file)
	return app.state==app.AppState.REPLAY
func focus(id: String, time: float) -> void:
	app.viewer.controller.clock.pause();app.viewer.controller.clock.seek(time)
	app.viewer.debug_overlay.show();app.viewer.debug_overlay.select_player(id);app.viewer.debug_overlay.focus_selected()
	app.viewer.debug_overlay.refresh()
func map_metrics(name: String) -> void:
	var map=app.viewer.map_manager
	report.maps[name]={"triangles":map.triangles,"bytes":map.glb_bytes,"cold_load_ms":map.loading_ms,"bounds_position":str(map.map_bounds.position),"bounds_size":str(map.map_bounds.size),"fallback":map.model==null,"open_ms":app.last_open_ms}
	var time:float=app.viewer.controller.clock.current_time
	app.viewer.reload_map();report.maps[name].warm_load_ms=map.loading_ms
	check(app.viewer.controller.clock.current_time==time,"Reload map preserves time: "+name)
func run() -> void:
	project=arg("--project");output=project.path_join("artifacts")
	root.size=Vector2i(1280,720)
	app=load("res://scenes/Application.tscn").instantiate();root.add_child(app);current_scene=app
	app.settings.set_value("auto_prepare_maps",0) # This regression exercises the explicit Ask workflow.
	await process_frame
	check(OS.get_executable_path().get_file()=="CS2TacticalReplay.exe","Actual Windows export")
	check(app.state==app.AppState.HOME,"Home startup");await snap("home")
	await transparent_icons()
	# Empty private map cache proves absent assets do not show an ErrorScreen.
	var real_cache: String=OS.get_environment("LOCALAPPDATA").path_join("CS2TacticalReplay/maps")
	OS.set_environment("CS2_MAP_CACHE_ROOT",output.path_join("m7-empty-map-cache"))
	if not await open_demo("damage-source.dem"):finish();return
	check(app.viewer.map_manager.model==null and app.map_notice.visible,"Mirage automatic fallback banner")
	app.viewer.controller.clock.seek(282.48125);await snap("mirage-fallback")
	# Preparation failure stays in Replay; never convert map errors to AppError.
	app.settings.set_value("cs2_path","C:/nonexistent-cs2")
	app.prepare_current_map()
	while app.map_service!=null:await process_frame
	check(app.state==app.AppState.REPLAY and "Could not" in app.map_panel.note.text,"Invalid CS2 preparation remains in Replay")
	OS.unset_environment("CS2_MAP_CACHE_ROOT")
	app.settings.set_value("cs2_path","")
	app.viewer.map_manager.assets.root=real_cache
	app.prepare_current_map();await snap("map-preparing")
	var frames:=0;var start:=Time.get_ticks_msec()
	while app.map_service!=null and Time.get_ticks_msec()-start<120000:await process_frame;frames+=1
	check(app.map_service==null and app.map_panel.reload_button.visible,"Real Mirage preparation succeeds")
	report.prepare_ui_frames=frames;report.prepare_wait_ms=Time.get_ticks_msec()-start
	app.map_panel.reload_requested.emit()
	check(app.viewer.map_manager.model!=null,"Fallback -> real Mirage")
	check(is_equal_approx(app.viewer.controller.clock.current_time,282.48125),"Preparation reload preserves Replay time")
	map_metrics("de_mirage")
	root.size=Vector2i(1920,1080)
	var events:Array=app.viewer.combat.index.events
	for source in ["hegrenade","inferno"]:
		var selected:Array=[];var last:=-100.0
		for event in events:
			if event.type!="player_hurt" or event.damage_source!=source or event.damage<=0 or event.time-last<1.0:continue
			focus(event.victim_player_id,event.time+0.2)
			var kind:="he_hit" if source=="hegrenade" else "burning"
			check(kind in app.viewer.combat.flashed.icons[event.victim_player_id].statuses,"Real damage icon: "+source)
			check(kind.to_upper() in app.viewer.debug_overlay.status_details.text,"Debug agrees with damage: "+source)
			selected.append({"time":event.time,"seek":event.time+0.2,"victim":event.victim_player_id,"damage":event.damage,"source":source})
			await snap(("he-real-" if source=="hegrenade" else "burning-real-")+str(selected.size()))
			if selected.size()==1:await snap("real-he-hit" if source=="hegrenade" else "real-burning")
			last=event.time
			if selected.size()==3:break
		check(selected.size()==3,"Three real scenarios: "+source)
		report["he" if source=="hegrenade" else "burning"]=selected
	var flashed:=false;var smoked:=false;var carrier:=false;var multiple:=false
	for event in events:
		if not flashed and event.type=="flash":
			for affected in event.affected_players:
				if affected.flash_duration<=0.2:continue
				focus(affected.player_id,event.time+0.1)
				if "flashed_players" in app.viewer.combat.flashed.current.get(affected.player_id,[]):await snap("real-flashed");flashed=true;break
		if not smoked and event.type=="smoke":
			for offset in [0.5,2.0,5.0,8.0]:
				app.viewer.controller.clock.seek(minf(event.time+offset,event.expire_time-0.01))
				for id in app.viewer.combat.flashed.current:
					if "in_smoke" in app.viewer.combat.flashed.current[id]:
						focus(id,app.viewer.controller.clock.current_time);await snap("real-in-smoke");smoked=true;break
				if smoked:break
		if not carrier and event.type=="bomb_pickup":
			focus(event.actor_player_id,event.time+0.1)
			if "bomb_carrier" in app.viewer.combat.flashed.current.get(event.actor_player_id,[]):
				var view=app.viewer.controller.player_views[event.actor_player_id]
				check(view.get_node("Name").modulate==Color("ff5b68"),"Carrier red name")
				check(not "bomb_carrier" in app.viewer.combat.flashed.icons[event.actor_player_id].statuses,"No carrier icon")
				check(view.get_node("Body").material_override.albedo_color!=view.get_node("Name").modulate,"Carrier mesh retains team color")
				await snap("bomb-carrier-name-only");carrier=true
		if flashed and smoked and carrier:break
	check(flashed and smoked and carrier,"Real flash/smoke/carrier screenshots")
	for event in events:
		if event.type!="player_hurt":continue
		app.viewer.controller.clock.seek(event.time+0.2)
		for id in app.viewer.combat.flashed.icons:
			if app.viewer.combat.flashed.icons[id].statuses.size()>1:
				focus(id,event.time+0.2);await snap("multiple-real");report.multiple={"time":event.time+0.2,"player":id};multiple=true;break
		if multiple:break
	if not multiple:
		var id:String=app.viewer.controller.player_views.keys()[0];focus(id,536.7)
		app.viewer.combat.flashed.icons[id].set_statuses(["flashed_players","burning","in_smoke"]);app.viewer.combat.flashed._process(0)
		await snap("multiple-layout-fixture");report.multiple="Explicit layout fixture, not a match event"
	await alignment()
	app.viewer.debug_overlay.hide();app.viewer.get_node("TacticalCamera").reset_view();await snap("mirage-map")
	var clock=app.viewer.controller.clock;clock.seek(530);clock.play()
	var fps_start:=Time.get_ticks_usec();var fps_frames:=0
	while Time.get_ticks_usec()-fps_start<5000000:await process_frame;fps_frames+=1
	clock.pause();report.mirage_fps=fps_frames/((Time.get_ticks_usec()-fps_start)/1000000.0);clock=null
	app.show_settings();await create_timer(0.7).timeout;await snap("settings-maps")
	app.go_home();events=[]
	if await open_demo("s2/s2.dem"):
		check(app.viewer.map_manager.model!=null,"Ancient map continues to load")
		app.viewer.controller.clock.seek(600);map_metrics("de_ancient");await snap("ancient-map")
		check(app.viewer.combat.flashed.resolver.damage_count==0,"Ancient no damage source remains zero")
	app.go_home()
	# M8 now prepares Vertigo. Isolate only this historical missing-map scenario.
	OS.set_environment("CS2_MAP_CACHE_ROOT",output.path_join("m7-empty-maps"))
	if await open_demo("third-map.dem"):
		check(app.viewer.controller.replay.metadata.map=="de_vertigo" and app.viewer.map_manager.model==null,"Third real map automatic fallback")
		var c=app.viewer.controller;report.maps.de_vertigo={"fallback":true,"players":c.player_views.size(),"events":app.viewer.combat.index.events.size(),"damage":app.viewer.combat.flashed.resolver.damage_count,"open_ms":app.last_open_ms}
		for time in [100.0,500.0,1000.0]:c.clock.seek(time);check(c.current_states.size()==10,"Third map sampled players")
		for speed in [0.5,1.0,2.0]:c.clock.set_speed(speed);c.clock.play();var before:float=c.clock.current_time;await create_timer(0.15).timeout;c.clock.pause();check(c.clock.current_time>before,"Third map playback speeds")
		await snap("vertigo-fallback")
	OS.set_environment("CS2_MAP_CACHE_ROOT","")
	app.go_home();app.open_demo("C:/missing/m7.dem")
	while app.state==app.AppState.LOADING:await process_frame
	check(app.state==app.AppState.ERROR,"Missing Demo remains Error");await snap("error")
	app.go_home();await snap("recent-maps")
	finish()
func alignment() -> void:
	var main=app.viewer;var map=main.map_manager;var bodies:=[]
	for mesh in map.model.find_children("*","MeshInstance3D",true,false):
		var body:=StaticBody3D.new();var collision:=CollisionShape3D.new();var shape:ConcavePolygonShape3D=mesh.mesh.create_trimesh_shape();shape.backface_collision=true;collision.shape=shape;body.add_child(collision);mesh.add_child(body);bodies.append(body)
	await physics_frame;await physics_frame
	var space:PhysicsDirectSpaceState3D=main.get_world_3d().direct_space_state
	var count:=0;var hits:=0;var supported:=0;var gaps:Array=[]
	var regions:={"T Spawn":Vector3(1300,0,0),"CT Spawn":Vector3(-1750,-2000,-200),"A Site":Vector3(-400,-2200,-180),"B Site":Vector3(-2100,650,-160),"Mid":Vector3(-500,-500,0),"Connector":Vector3(-1000,-1300,-150),"Jungle":Vector3(-1400,-1400,-150),"Short":Vector3(-1100,300,-150)}
	var closest:={}
	for id in main.controller.replay.tracks:
		var frames:Array=main.controller.replay.tracks[id]
		for i in range(0,frames.size(),97):
			var frame:Dictionary=frames[i]
			if not frame.alive or not frame.available:continue
			var p:Vector3=map.map_transform.position_to_godot(frame.position);count+=1
			var q:=PhysicsRayQueryParameters3D.create(p+Vector3.UP*0.35,p-Vector3.UP*8);q.hit_back_faces=true
			var hit:=space.intersect_ray(q)
			if not hit.is_empty():
				hits+=1;var gap:float=p.y-hit.position.y;gaps.append(gap)
				if absf(gap)<=0.5:supported+=1
			for name in regions:
				var distance:float=Vector2(frame.position.x,frame.position.y).distance_to(Vector2(regions[name].x,regions[name].y))
				if distance<closest.get(name,{}).get("distance",INF):closest[name]={"distance":distance,"player":id,"time":frame.time,"raw":str(frame.position),"godot":str(p),"ground_gap":p.y-hit.position.y if not hit.is_empty() else null}
	gaps.sort();report.alignment={"samples":count,"ray_hits":hits,"within_50_units":supported,"median_gap":gaps[gaps.size()/2],"regions":closest}
	check(count>300 and float(hits)/count>0.95,"Mirage actual mesh supports real track points")
	check(float(supported)/count>0.85,"Mirage height alignment within 50 source units")
	for name in closest:
		focus(closest[name].player,closest[name].time);main.get_node("TacticalCamera").set_preset(2);main.map_manager.set_opacity(0.5);await snap("alignment-"+name.to_lower().replace(" ","-"))
	for body in bodies:body.queue_free()
func finish() -> void:
	report.checks=checks;report.failures=failures
	var file:=FileAccess.open(output.path_join("milestone-7-report.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("M7 REPORT ",JSON.stringify(report));app.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)

func transparent_icons() -> void:
	var viewport:=SubViewport.new();viewport.size=Vector2i(64,64);viewport.transparent_bg=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var indicator=load("res://scripts/status/PlayerStatusIndicator.gd").new();viewport.add_child(indicator);indicator.position=Vector2(32,32)
	for kind in ["flashed_players","burning","he_hit","in_smoke","bomb_carrier"]:
		indicator.set_statuses([kind]);await process_frame;await RenderingServer.frame_post_draw
		var image:=viewport.get_texture().get_image()
		image.save_png(output.path_join("m7-icon-alpha-"+kind+".png"))
		var corner_alpha:=0.0;var visible_pixels:=0
		for y in range(19,45):
			for x in range(19,45):
				if image.get_pixel(x,y).a>0.1:visible_pixels+=1
				if abs(x-32)>=11 and abs(y-32)>=11:corner_alpha+=image.get_pixel(x,y).a
		check(corner_alpha==0,"No badge background: "+kind)
		check(visible_pixels==0 if kind=="bomb_carrier" else visible_pixels>10,"Transparent shape only: "+kind)
	viewport.queue_free();await process_frame
