extends Node
signal map_swapped(before: Dictionary, after: Dictionary)
## Owns application navigation; Main remains a replay-session scene.
enum AppState { HOME, LOADING, REPLAY, SETTINGS, ERROR }
const Info = preload("res://scripts/application/AppInfo.gd")
const Style = preload("res://scripts/application/ShellStyle.gd")
var state := AppState.HOME
var settings = preload("res://scripts/application/SettingsStore.gd").new()
var recent = preload("res://scripts/application/RecentReplays.gd").new()
var log = preload("res://scripts/application/ApplicationLog.gd").new()
var home: Control
var loading: Control
var settings_screen: Control
var error_screen: Control
var backdrop: ColorRect
var canvas: CanvasLayer
var dialog: FileDialog
var viewer: Node3D
var service: RefCounted
var demo_path := ""
var return_state := AppState.HOME
var cancel_pending := false
var stages: Array = []
var last_cache_hit := false
var open_started := 0
var last_open_ms := 0
var last_error: RefCounted
var replay_toolbar: HBoxContainer
var pending_result := {}
var map_queue = preload("res://scripts/map/MapPreparationQueue.gd").new()
var map_service: RefCounted
var map_debug_status := ""
var map_panel: Control
var map_notice: HBoxContainer
var map_notice_text: Label
func _ready() -> void:
	get_window().title=Info.TITLE
	get_window().theme=Style.theme()
	settings.load_settings();recent.load_entries();settings.changed.connect(apply_settings)
	canvas=CanvasLayer.new();canvas.layer=30;add_child(canvas)
	var base:=Control.new();base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);base.mouse_filter=Control.MOUSE_FILTER_IGNORE;base.theme=Style.theme();canvas.add_child(base)
	backdrop=ColorRect.new();backdrop.color=Style.BACKGROUND;backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);base.add_child(backdrop)
	home=preload("res://scripts/application/HomeScreen.gd").new();base.add_child(home)
	loading=preload("res://scripts/application/LoadingScreen.gd").new();base.add_child(loading)
	error_screen=preload("res://scripts/application/ErrorScreen.gd").new();base.add_child(error_screen)
	settings_screen=preload("res://scripts/application/SettingsScreen.gd").new();settings_screen.store=settings;base.add_child(settings_screen)
	home.open_requested.connect(_show_demo_dialog)
	home.settings_requested.connect(show_settings)
	home.recent_requested.connect(func(entry):open_demo(entry.demo_path,entry.demo_hash))
	loading.cancel_requested.connect(cancel_loading)
	error_screen.home_requested.connect(go_home)
	error_screen.log_requested.connect(func():OS.shell_open(log.path))
	settings_screen.back_requested.connect(func():_set_state(return_state);if is_instance_valid(viewer):viewer.process_mode=Node.PROCESS_MODE_INHERIT)
	settings_screen.map_requested.connect(request_map)
	settings_screen.log_requested.connect(func():OS.shell_open(log.path))
	settings_screen.map_delete_requested.connect(func(name):
		if map_queue.active!=null and map_queue.active.map_name==name:settings_screen.prepared_status.text="Preparation active — cancel or wait before deleting.";return
		map_queue.cancel(name)
		var cache=preload("res://scripts/map/MapAssetCache.gd").new()
		settings_screen.prepared_status.text="Cache deleted." if cache.delete_map(name) else "Could not delete map cache."
		settings_screen.refresh_maps())
	dialog=FileDialog.new();dialog.access=FileDialog.ACCESS_FILESYSTEM;dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE;dialog.filters=PackedStringArray(["*.dem ; CS2 Demo"]);dialog.file_selected.connect(open_demo);base.add_child(dialog)
	Style.configure_file_dialog(dialog,"选择 CS2 Demo · .dem")
	dialog.current_dir=OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	for entry in recent.entries:
		if DirAccess.dir_exists_absolute(entry.demo_path.get_base_dir()):
			dialog.current_dir=entry.demo_path.get_base_dir();break
	replay_toolbar=HBoxContainer.new();replay_toolbar.position=Vector2(20,16);base.add_child(replay_toolbar)
	replay_toolbar.add_child(Style.button("← Home",go_home));replay_toolbar.add_child(Style.button("Settings",show_settings))
	replay_toolbar.add_child(Style.button("Open Demo",_show_demo_dialog))
	var panels := Style.button("Panels",func():
		if is_instance_valid(viewer):viewer.combat_panel.visible=not viewer.combat_panel.visible)
	panels.tooltip_text="Show or hide viewing controls and event layers"
	replay_toolbar.add_child(panels)
	get_window().files_dropped.connect(files_dropped)
	log.record("App start",Info.VERSION);go_home()
	# Explicit developer-only JSON route remains available, never in normal UI.
	var args:=OS.get_cmdline_user_args();var i:=args.find("--replay")
	if i>=0 and i+1<args.size():
		viewer=preload("res://scenes/Main.tscn").instantiate();add_child(viewer);_set_state(AppState.REPLAY)
func _show_demo_dialog() -> void:
	if is_instance_valid(viewer):viewer.controller.clock.pause()
	dialog.popup_centered_ratio(0.85)

func _set_state(value: int) -> void:
	Engine.max_fps = 0 if value == AppState.REPLAY else 60
	state=value;home.visible=value==AppState.HOME;loading.visible=value==AppState.LOADING;settings_screen.visible=value==AppState.SETTINGS;error_screen.visible=value==AppState.ERROR;backdrop.visible=value!=AppState.REPLAY;replay_toolbar.visible=value==AppState.REPLAY
func files_dropped(files: PackedStringArray) -> void:
	if state==AppState.LOADING:return
	if files.size()!=1 or files[0].get_extension().to_lower()!="dem":
		if state==AppState.HOME:home.hint.text="Please drop one CS2 .dem file."
		else:show_error(preload("res://scripts/application/AppError.gd").new("INVALID_FILE","Please drop one CS2 .dem file."))
		return
	open_demo(files[0])
func open_demo(path: String, recent_hash := "") -> void:
	if service!=null:return
	_clear_session();demo_path=path;cancel_pending=false;open_started=Time.get_ticks_msec();stages.clear()
	_set_state(AppState.LOADING);loading.detail.text=path.get_file();loading.stage("Checking Replay Cache")
	service=preload("res://scripts/application/DemoOpenService.gd").new()
	log.record("Open demo",path)
	var err:Error=service.start(path,recent_hash)
	if err!=OK:service=null;show_error(preload("res://scripts/application/AppError.gd").new("WORKER","Cannot start the demo loader.",str(err)))
func cancel_loading() -> void:
	cancel_pending=true
	if service!=null:service.cancel();loading.stage("Returning Home after the current operation finishes…")
	else:pending_result.clear();go_home()
func _process(_delta: float) -> void:
	_poll_map_preparation()
	if service==null:return
	var stage:String=service.get_status()
	if not cancel_pending:loading.stage(stage)
	if stages.is_empty() or stages.back()!=stage:stages.append(stage)
	if not service.done():return
	var result:Dictionary=service.finish()
	for line in service.log_lines:log.record("Open pipeline",line)
	last_cache_hit=service.cache_hit;service=null
	if cancel_pending or result.get("cancelled",false):result.clear();go_home();return
	if not result.ok:show_error(result.error);return
	pending_result=result
	_commit_scene.call_deferred()
func _commit_scene() -> void:
	if pending_result.is_empty():return
	_set_state(AppState.LOADING);loading.stage("Loading Tactical Map" if pending_result.get("map_asset",{}).get("ok",false) else "Preparing Scene");stages.append("Preparing Scene")
	await get_tree().process_frame
	if cancel_pending:pending_result.clear();go_home();return
	viewer=preload("res://scenes/Main.tscn").instantiate();viewer.set_meta("shell_session",true);add_child(viewer)
	viewer.map_manager.prepared_asset=pending_result.get("map_asset",{})
	loading.stage("Preparing Scene");stages.append("Preparing Scene")
	await get_tree().process_frame
	if cancel_pending:_clear_session();pending_result.clear();go_home();return
	viewer.controller.accept_replay(pending_result.data)
	loading.stage("Loading Tactical Map")
	await get_tree().process_frame
	if cancel_pending: _clear_session();pending_result.clear();go_home();return
	viewer._finish_scene(pending_result.replay_path,open_started)
	viewer.debug_overlay.hide()
	viewer.combat_panel.hide()
	var header_row = viewer.timeline.subtitle.get_parent().get_parent()
	var space := Control.new(); space.custom_minimum_size.x = 340; header_row.add_child(space); header_row.move_child(space, 0)
	viewer.timeline.subtitle.text="%s  /  %s" % [demo_path.get_file(),viewer.controller.replay.metadata.map]
	recent.opened(demo_path,pending_result.demo_hash,viewer.controller.replay.metadata)
	log.record("Replay load",viewer.controller.replay.metadata.map);log.record("Map load",viewer.map_manager.loaded_map)
	pending_result.clear();apply_settings();last_open_ms=Time.get_ticks_msec()-open_started;_set_state(AppState.REPLAY)
	_setup_map_ui()
func _clear_session() -> void:
	map_panel=null
	if is_instance_valid(map_notice):map_notice.queue_free()
	map_notice=null
	if is_instance_valid(viewer):
		viewer.controller.clock.pause();remove_child(viewer);viewer.free()
	viewer=null
func go_home() -> void:
	if service!=null:cancel_loading();return
	_clear_session();pending_result.clear();home.hint.text=".dem files  •  Local processing  •  No account required";recent.load_entries();home.refresh(recent.entries);_set_state(AppState.HOME);log.record("Return Home")
	var old=error_screen.find_child("UseDebugPlane",true,false)
	if old!=null:old.queue_free()
func show_settings() -> void:
	return_state=state
	if is_instance_valid(viewer):viewer.controller.clock.pause();viewer.process_mode=Node.PROCESS_MODE_DISABLED
	settings_screen.sync();_set_state(AppState.SETTINGS)
func show_error(error: RefCounted) -> void:
	if is_instance_valid(viewer): viewer.controller.clock.pause()
	var old=error_screen.find_child("UseDebugPlane",true,false)
	if old!=null: old.get_parent().remove_child(old);old.queue_free()
	last_error=error;error_screen.show_error(error);log.record("Error",error.code+": "+error.message+"\n"+error.technical_details);_set_state(AppState.ERROR)
func apply_settings() -> void:
	var values:Dictionary=settings.values
	preload("res://scripts/config/TeamVisualConfig.gd").set_colors(Color(values.t_color),Color(values.ct_color))
	if not is_instance_valid(viewer):return
	viewer.apply_scene_palette(int(values.background_tone))
	var controller=viewer.controller
	for id in controller.player_views:
		var view=controller.player_views[id];view.name_size=values.name_size;view.scale=Vector3.ONE*values.player_scale
	controller._apply_time(controller.clock.current_time)
	for key in viewer.combat.layers:
		if values.has(key):viewer.combat.layers[key]=values[key]
	viewer.combat.smoke_opacity=int(values.smoke_visibility);viewer.map_manager.set_opacity(values.map_opacity)
	var camera=viewer.get_node("TacticalCamera");camera.pan_speed=values.pan_speed;camera.zoom_speed=values.zoom_speed;camera.orbit_sensitivity=values.orbit_sensitivity
	viewer.combat_panel._last_kill_ids = "!"
	viewer.combat.refresh(controller.clock.current_time)
	for key in viewer.combat_panel.toggles:viewer.combat_panel.toggles[key].set_pressed_no_signal(viewer.combat.layers[key])
	viewer.combat_panel.smoke_visibility.select(int(values.smoke_visibility))
func _exit_tree() -> void:
	map_queue.finish()
	if service!=null:service.cancel();service.finish()

func _setup_map_ui() -> void:
	map_panel=preload("res://scripts/ui/MapPreparationPanel.gd").new();viewer.view_controls.get_child(0).add_child(map_panel)
	map_panel.prepare_requested.connect(prepare_current_map)
	map_panel.reload_requested.connect(func():viewer.reload_map();_update_map_notice();map_panel.completed(false,"Tactical map loaded."))
	map_panel.cancel_requested.connect(func():map_queue.cancel(viewer.controller.replay.metadata.map);map_panel.busy("Cancelling after the current safe operation…"))
	var debug:=CheckButton.new();debug.text="Debug / Player Status";debug.toggled.connect(func(value):viewer.debug_overlay.visible=value);viewer.view_controls.get_child(0).add_child(debug)
	map_notice=HBoxContainer.new();map_notice.theme=Style.theme();map_notice.position=Vector2(20,96);viewer.get_node("UI").add_child(map_notice)
	map_notice_text=Label.new();map_notice_text.add_theme_font_size_override("font_size",13);map_notice.add_child(map_notice_text)
	map_notice.add_child(Style.button("Dismiss",func():map_notice.hide()))
	_update_map_notice()
	var name:String=viewer.controller.replay.metadata.map
	log.record("Map cache miss / fallback" if viewer.map_manager.model==null else "Map cache hit",name)
	if viewer.map_manager.model==null and int(settings.values.auto_prepare_maps)==1:
		log.record("Map auto prepare start",name);prepare_current_map()
func _update_map_notice() -> void:
	if not is_instance_valid(viewer):return
	var fallback:bool=viewer.map_manager.model==null
	map_notice.visible=fallback
	map_notice_text.text="MAP FALLBACK  •  %s — Tactical map unavailable; using fallback plane." % viewer.controller.replay.metadata.map
	map_panel.note.text="Fallback playback is ready. Prepare the local tactical map when convenient." if fallback else "Tactical map ready."
	map_panel.prepare_button.visible=int(settings.values.auto_prepare_maps)!=2
func prepare_current_map() -> void:
	if not is_instance_valid(viewer):return
	request_map(viewer.controller.replay.metadata.map,true)
func request_map(name: String, rebuild := false) -> void:
	var cache=preload("res://scripts/map/MapAssetCache.gd").new()
	if not rebuild and cache.is_map_ready(name):
		log.record("Map cache hit",name)
		if is_instance_valid(viewer) and viewer.controller.replay.metadata.map==name and viewer.map_manager.model==null:viewer.reload_map();_update_map_notice()
		settings_screen.refresh_maps();return
	log.record("Map prepare queued",name)
	map_queue.enqueue(name,settings.values.cs2_path);map_service=map_queue.active
	if is_instance_valid(map_panel):map_panel.busy(map_queue.state_for(name))
func _poll_map_preparation() -> void:
	var completed:Dictionary=map_queue.poll();map_service=map_queue.active
	if map_service!=null:
		var stage:String=map_service.get_status()
		if stage!=map_debug_status:map_debug_status=stage;log.record("Map preparation stage",stage)
		if state==AppState.HOME:home.hint.text=stage
		if settings_screen.map_status_labels.has(map_service.map_name):settings_screen.map_status_labels[map_service.map_name].text=stage
	if is_instance_valid(viewer) and viewer.controller.replay.has("metadata"):
		var name:String=viewer.controller.replay.metadata.map
		var pending_state:String=map_queue.state_for(name)
		if pending_state.begins_with("Queued") or (map_service!=null and map_service.map_name==name):
			if is_instance_valid(map_panel):map_panel.busy(pending_state)
			if is_instance_valid(map_notice_text):map_notice_text.text="Preparing Tactical Map — "+name+"  •  Replay remains available"
		viewer.map_manager.preparation_state=pending_state
	if completed.is_empty():return
	var name:String=completed.name;var result:Dictionary=completed.result
	log.record("Map preparation result",name+"\n"+str(result.get("output","")))
	settings_screen.check_delay=0.1
	if state==AppState.HOME:home.refresh(recent.entries);home.hint.text=name+" — "+map_queue.state_for(name)
	if not is_instance_valid(viewer) or not viewer.controller.replay.has("metadata") or viewer.controller.replay.metadata.map!=name:return
	if result.get("ok",false):
		if int(settings.values.auto_prepare_maps)==1:
			var before:=_map_swap_snapshot()
			viewer.reload_map();_update_map_notice();map_panel.completed(false,"Tactical Map Ready — "+name);log.record("Map hot swap",name)
			map_swapped.emit(before,_map_swap_snapshot())
		else:map_panel.completed(true,"Tactical Map Ready — Load Map without reopening Replay.")
	else:
		map_panel.completed(false,"Could not prepare tactical map. Using fallback plane.")
		map_panel.prepare_button.text="Retry"
		map_notice.show();map_notice_text.text="Tactical map preparation failed. Using fallback plane."
		if str(result.get("error","")).begins_with("CS2 installation"):map_notice_text.text="CS2 installation not found. Tactical map unavailable."
		log.record("Map fallback",str(result.get("error_code",""))+": "+str(result.get("error","")))
func _map_swap_snapshot() -> Dictionary:
	var camera=viewer.get_node("TacticalCamera");var clock=viewer.controller.clock
	return {"time":clock.current_time,"playing":clock.is_playing,"speed":clock.playback_speed,"selected":viewer.debug_overlay.selector.selected,"camera":[camera.target,camera.yaw,camera.pitch,camera.size,camera.perspective],"layers":viewer.combat.layers.duplicate(true),"players":viewer.controller.current_states.duplicate(true),"bomb":viewer.combat.bomb.state_model.at(clock.current_time),"combat":viewer.combat.counts.duplicate(true),"status":viewer.combat.flashed.current.duplicate(true),"kill_feed":viewer.combat.recent_kills.map(func(event):return event.id),"replay_id":viewer.controller.get_instance_id()}
