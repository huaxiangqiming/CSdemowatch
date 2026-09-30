extends SceneTree
var app:Node
var checks:=0
var failures:Array=[]
var report:Dictionary={}
var output:=""
var project:=""
var phase:=""
func _initialize()->void:run.call_deferred()
func arg(key: String) -> String:
	var args:=OS.get_cmdline_user_args();var i:=args.find(key);return args[i+1] if i>=0 and i+1<args.size() else ""
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures.append(message);printerr("FAIL: "+message)
func snap(name: String) -> void:
	await create_timer(0.15).timeout;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("m7-1-"+name+".png"))
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
func run()->void:
	project=arg("--project");output=project.path_join("artifacts");phase=arg("--phase")
	root.size=Vector2i(1920,1080)
	app=load("res://scenes/Application.tscn").instantiate();root.add_child(app);current_scene=app
	app.settings.set_value("auto_prepare_maps",0) # This regression exercises the explicit Ask workflow.
	await process_frame
	if phase=="after":
		var stale_root:=output.path_join("m71-stale-cache")
		var cache=load("res://scripts/map/MapAssetCache.gd").new(stale_root)
		check(not cache.is_map_ready("de_mirage"),"Old converter cache automatically stale")
		OS.set_environment("CS2_MAP_CACHE_ROOT",stale_root)
		if await open_demo("damage-source.dem"):
			check(app.viewer.map_manager.model==null,"Stale cache still opens Replay on Plane")
		app.go_home();OS.unset_environment("CS2_MAP_CACHE_ROOT")
	if not await open_demo("damage-source.dem"):finish();return
	var main=app.viewer
	check(main.map_manager.model!=null,"Mirage model loaded")
	if phase=="after": check(main.map_manager.roof_removed>0,"Runtime roof diagnostic loaded")
	main.controller.clock.seek(282.48125);main.controller.clock.pause()
	main.debug_overlay.hide();main.map_manager.set_view_mode(1);main.map_manager.set_opacity(1.0)
	var cam=main.get_node("TacticalCamera");cam.clearance_height=15;cam.target=Vector3(-11,0,9);cam.size=62;cam.set_preset(1)
	report.triangles=main.map_manager.triangles;report.bytes=main.map_manager.glb_bytes;report.load_ms=main.map_manager.loading_ms
	report.opacity=main.map_manager.material.albedo_color.a
	await snap("mirage-"+phase)
	await alignment()
	if phase=="after":
		app.go_home()
		if await open_demo("s2/s2.dem"):
			check(app.viewer.map_manager.model!=null,"Ancient model still loaded")
			check(app.viewer.map_manager.triangles==958606,"Ancient unchanged geometry")
			app.viewer.controller.clock.seek(600);await snap("ancient")
	finish()
func finish()->void:
	report.checks=checks;report.failures=failures
	var file=FileAccess.open(output.path_join("m7-1-"+phase+"-report.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("M7.1 REPORT ",JSON.stringify(report));app.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
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
	check(count>300 and hits==1099,"Mirage actual mesh supports real track points")
	check(supported>=1059,"Mirage height alignment within 50 source units")
	for name in closest:
		focus(closest[name].player,closest[name].time);main.get_node("TacticalCamera").set_preset(2);main.map_manager.set_opacity(1.0);await snap("alignment-"+name.to_lower().replace(" ","-"))
	for body in bodies:body.queue_free()
