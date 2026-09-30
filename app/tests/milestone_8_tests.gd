extends SceneTree
var app:Node
var checks:=0
var failures:Array=[]
var report:Dictionary={"maps":{},"swaps":[]}
var project:=""
var output:=""
var dust:= ""
func _initialize()->void:run.call_deferred()
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message);printerr("FAIL: "+message)
func arg(key:String)->String:
	var args:=OS.get_cmdline_user_args();var i:=args.find(key);return args[i+1] if i>=0 and i+1<args.size() else ""
func snap(name:String)->void:
	await create_timer(0.12).timeout;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("m8-"+name+".png"))
func open_demo(path:String)->bool:
	app.open_demo(path);var start:=Time.get_ticks_msec()
	while app.state==app.AppState.LOADING and Time.get_ticks_msec()-start<120000:await process_frame
	check(app.state==app.AppState.REPLAY,"Parsed Demo opens: "+path.get_file())
	return app.state==app.AppState.REPLAY
func swapped(before:Dictionary,after:Dictionary)->void:
	for key in before:check(before[key]==after[key],"Hot swap preserves "+key)
	report.swaps.append({"time":before.time,"playing":before.playing,"speed":before.speed,"unchanged":before==after})
func wait_map()->bool:
	var start:=Time.get_ticks_msec();var frames:=0
	while app.viewer.map_manager.model==null and Time.get_ticks_msec()-start<120000:
		await process_frame;frames+=1
		if app.map_queue.active==null and app.map_queue.pending.is_empty():break
	check(app.viewer.map_manager.model!=null,"Automatic map ready: "+app.viewer.controller.replay.metadata.map)
	report.last_prepare_frames=frames
	return app.viewer.map_manager.model!=null
func run()->void:
	project=arg("--project");output=project.path_join("artifacts");if not arg("--dust").is_empty():dust=arg("--dust")
	if dust.is_empty() or not FileAccess.file_exists(dust):
		printerr("Supply --dust with a local Dust2 Demo path.");quit(2);return
	root.size=Vector2i(1920,1080)
	app=load("res://scenes/Application.tscn").instantiate();root.add_child(app);current_scene=app;await process_frame
	check(OS.has_feature("standalone"),"Formal Windows EXE")
	check(int(app.settings.values.auto_prepare_maps)==1,"Fresh settings defaults Auto")
	app.map_swapped.connect(swapped)
	var cache=load("res://scripts/map/MapAssetCache.gd").new()
	check(not cache.is_map_ready("de_dust2"),"Fresh Dust2 cache starts empty")
	if not await open_demo(dust):finish();return
	check(app.viewer.map_manager.model==null,"Dust2 immediate fallback")
	app.viewer.controller.clock.seek(500);app.viewer.controller.clock.set_speed(2);app.viewer.controller.clock.play()
	app.viewer.debug_overlay.selector.select(1);app.viewer.combat.set_layer("shots",false)
	var camera=app.viewer.get_node("TacticalCamera");camera.yaw=72;camera.set_preset(3)
	await snap("dust2-fallback");await snap("dust2-preparing")
	if not await wait_map():finish();return
	app.viewer.controller.clock.pause();await snap("dust2-ready")
	await map_acceptance("de_dust2",true)
	var count:int=app.map_queue.prepare_counts.get("de_dust2",0)
	app.go_home();await open_demo(dust)
	check(app.viewer.map_manager.model!=null,"Second Dust2 cache loads")
	check(app.map_queue.prepare_counts.get("de_dust2",0)==count,"Second Dust2 preparation count zero")
	report.dust2_second_prepare_count=app.map_queue.prepare_counts.get("de_dust2",0)-count
	# Second real, short Dust2 Demo shares the same map asset.
	app.go_home();await open_demo(project.path_join("test_data/dust2-short.dem"))
	check(app.viewer.map_manager.model!=null and app.map_queue.prepare_counts.get("de_dust2",0)==count,"Different Dust2 Demo reuses map without prepare")
	app.go_home()
	if await open_demo(project.path_join("test_data/third-map.dem")):
		await snap("vertigo-fallback")
		if await wait_map():await snap("vertigo-ready");await map_acceptance("de_vertigo",true)
	app.go_home()
	if await open_demo(project.path_join("test_data/inferno-short.dem")):
		if await wait_map():await map_acceptance("de_inferno",true)
	app.go_home()
	if await open_demo(project.path_join("test_data/inferno-spawn.dem")):
		report.inferno_spawn_alignment=await alignment("de_inferno-spawn",false)
	app.go_home()
	# No-CS2 and failed source tests use an isolated empty map cache; ready assets remain intact.
	OS.set_environment("CS2_MAP_CACHE_ROOT",output.path_join("m8-empty-maps"));app.settings.set_value("cs2_path","C:/missing-cs2-installation")
	if await open_demo(dust):
		while app.map_queue.active!=null:await process_frame
		check(app.state==app.AppState.REPLAY and app.viewer.map_manager.model==null,"No CS2 remains playable fallback")
		app.viewer.controller.clock.play();var t:float=app.viewer.controller.clock.current_time;await create_timer(0.1).timeout
		check(app.viewer.controller.clock.current_time>t,"Failed preparation does not stop playback")
		await snap("no-cs2-fallback")
	OS.unset_environment("CS2_MAP_CACHE_ROOT");app.settings.set_value("cs2_path","")
	app.viewer.map_manager.assets.root=cache.root
	app.prepare_current_map();await wait_map();check(app.last_cache_hit,"Install later keeps Replay cache")
	app.go_home();app.request_map("de_m8_missing_resource",true)
	var timeout:=Time.get_ticks_msec()
	while app.map_queue.active!=null and Time.get_ticks_msec()-timeout<120000:await process_frame
	check(not app.map_queue.results.get("de_m8_missing_resource",{}).get("ok",true),"Missing source is map capability failure")
	# Queue survives session changes and deduplicates pending requests.
	app.request_map("de_dust2",true);app.request_map("de_vertigo",true);app.request_map("de_vertigo",true)
	check(app.map_queue.pending.size()==1,"Heavy preparation serial and deduplicated")
	while app.map_queue.active!=null:await process_frame
	check(app.map_queue.results.de_dust2.ok and app.map_queue.results.de_vertigo.ok,"Queued maps finish one at a time")
	app.show_settings();await create_timer(0.5).timeout;await snap("settings-maps")
	finish()
func map_acceptance(name:String,images:bool)->void:
	var main=app.viewer;var map=main.map_manager;var metadata:Dictionary=map.source_metadata
	report.maps[name]={"triangles":map.triangles,"bytes":map.glb_bytes,"cold_load_ms":map.loading_ms,"prepare_ms":metadata.get("preparation_ms",0),"geometry_stats":metadata.get("geometry_stats",{}),"source":metadata.get("source_resource",{})}
	var time:float=main.controller.clock.current_time;main.reload_map();check(time==main.controller.clock.current_time,"Warm reload preserves time")
	report.maps[name].warm_load_ms=map.loading_ms
	report.maps[name].alignment=await alignment(name,images)
func alignment(name:String,images:bool)->Dictionary:
	var main=app.viewer;var map=main.map_manager;var bodies:=[]
	for mesh in map.model.find_children("*","MeshInstance3D",true,false):
		var body:=StaticBody3D.new();var collision:=CollisionShape3D.new();var shape:ConcavePolygonShape3D=mesh.mesh.create_trimesh_shape();shape.backface_collision=true;collision.shape=shape;body.add_child(collision);mesh.add_child(body);bodies.append(body)
	await physics_frame;await physics_frame
	var space:PhysicsDirectSpaceState3D=main.get_world_3d().direct_space_state
	var samples:=[];var gaps:Array=[];var hits:=0;var large:=0
	var stride:=37 if name.begins_with("de_inferno") else 97
	if name.begins_with("de_inferno"):stride=1
	for id in main.controller.replay.tracks:
		var frames:Array=main.controller.replay.tracks[id]
		for i in range(0,frames.size(),stride):
			var f:Dictionary=frames[i]
			if not f.alive or not f.available:continue
			var p:Vector3=map.map_transform.position_to_godot(f.position)
			var q:=PhysicsRayQueryParameters3D.create(p+Vector3.UP*0.35,p-Vector3.UP*8);q.hit_back_faces=true
			var hit:=space.intersect_ray(q);var gap:=INF
			if not hit.is_empty():hits+=1;gap=p.y-hit.position.y;gaps.append(gap);large+=int(absf(gap)>0.5)
			samples.append({"id":id,"time":f.time,"raw":f.position,"position":p,"gap":gap})
	gaps.sort();var result:={"samples":samples.size(),"hits":hits,"hit_ratio":float(hits)/maxi(1,samples.size()),"median_vertical_delta":gaps[gaps.size()/2] if not gaps.is_empty() else null,"large_error_count":large,"regions":[]}
	check(samples.size()>300,"Enough real track positions: "+name)
	check(result.hit_ratio>0.95,"Geometry hit ratio: "+name)
	if images:
		main.controller.clock.pause();main.map_manager.set_view_mode(1);main.map_manager.set_opacity(1)
		var camera=main.get_node("TacticalCamera");camera.reset_view();camera.set_preset(1);main.debug_overlay.hide();await snap(name.trim_prefix("de_")+"-top");camera.set_preset(2);await snap(name.trim_prefix("de_")+"-tactical")
		var points:={}
		if name=="de_dust2":points={"t-spawn":Vector3(0,-850,64),"ct-spawn":Vector3(200,2150,-128),"long":Vector3(1350,700,64),"short":Vector3(380,1350,64),"mid":Vector3(-350,1000,64),"b-site":Vector3(-1450,2600,0),"a-site":Vector3(1200,2500,100),"lower-tunnel":Vector3(-900,1000,-100),"upper-tunnel":Vector3(-1900,1500,0)}
		else:
			# Farthest-point sampling provides eight genuinely distinct track regions.
			var chosen:Array=[samples[0]]
			for i in 7:
				var best:Dictionary={};var distance:=-1.0
				for sample in samples:
					var nearest:=INF
					for old in chosen:nearest=minf(nearest,sample.raw.distance_squared_to(old.raw))
					if nearest>distance:distance=nearest;best=sample
				chosen.append(best)
			for i in chosen.size():points["region-"+str(i+1)]=chosen[i].raw
		for label in points:
			var closest:Dictionary={};var distance:=INF
			for sample in samples:
				var d:float=sample.raw.distance_to(points[label])
				if d<distance:distance=d;closest=sample
			main.controller.clock.seek(closest.time);main.debug_overlay.show();main.debug_overlay.select_player(closest.id);main.debug_overlay.focus_selected();camera.set_preset(2);main.debug_overlay.refresh()
			result.regions.append({"label":label,"raw":str(closest.raw),"godot":str(closest.position),"time":closest.time,"gap":closest.gap,"reference_distance":distance})
			await snap(name.trim_prefix("de_")+"-"+label)
	for body in bodies:body.queue_free()
	return result
func finish()->void:
	report.checks=checks;report.failures=failures
	var file=FileAccess.open(output.path_join("milestone-8-report.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("M8 REPORT ",JSON.stringify(report));app.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
