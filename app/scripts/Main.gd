extends Node3D

@onready var controller = $ReplayController
@onready var timeline = $UI/TimelineUI
var debug_overlay: PanelContainer
var file_dialog: FileDialog
var map_manager: Node3D
var view_controls: PanelContainer
var combat: Node3D
var combat_panel: TabContainer
var kill_markers: Control
var bomb_markers: Control
var load_job: RefCounted
var loading_panel: PanelContainer
var loading_label: Label
var loading_path := ""
var current_path := ""
var pending_path := ""
var loading_started := 0
var replay_loading_ms := 0
var _activity := 0.0

func _ready() -> void:
	$WorldEnvironment.environment = $WorldEnvironment.environment.duplicate()
	get_window().theme = preload("res://scripts/application/ShellStyle.gd").theme()
	controller.replay_failed.connect(func(message): timeline.show_error(message))
	map_manager = preload("res://scripts/map/MapManager.gd").new()
	map_manager.name = "MapManager"
	apply_scene_palette(0)
	add_child(map_manager)
	add_child(preload("res://scripts/world/WorldAxes.gd").new())
	debug_overlay = preload("res://scripts/ui/DebugOverlay.gd").new()
	$UI.add_child(debug_overlay)
	debug_overlay.visibility_changed.connect(func():get_node("WorldAxes").visible=debug_overlay.visible)
	debug_overlay.camera = $TacticalCamera
	debug_overlay.map_manager = map_manager
	view_controls = preload("res://scripts/ui/ViewControls.gd").new()
	$UI.add_child(view_controls)
	view_controls.bind_view($TacticalCamera, map_manager, controller)
	combat = preload("res://scripts/events/CombatController.gd").new()
	combat.name = "CombatController"
	add_child(combat)
	combat_panel = preload("res://scripts/ui/CombatPanel.gd").new()
	$UI.add_child(combat_panel)
	combat_panel.setup(view_controls, combat)
	combat_panel.inspect_player_requested.connect(func(id):debug_overlay.show();debug_overlay.select_player(id))
	debug_overlay.combat = combat
	kill_markers = preload("res://scripts/ui/KillMarkers.gd").new()
	timeline.slider.add_child(kill_markers)
	bomb_markers = preload("res://scripts/ui/BombMarkers.gd").new()
	timeline.slider.add_child(bomb_markers)
	combat.refreshed.connect(func(): kill_markers.visible = combat.layers.kill_feed; bomb_markers.visible = combat.layers.bomb)
	_create_loading_ui()
	var retry := Button.new(); retry.text = "Reload tactical map"
	retry.pressed.connect(func():
		if not current_path.is_empty():
			reload_map())
	view_controls.get_child(0).add_child(retry)
	for label in timeline.find_children("*", "Label", true, false):
		if label.text.begins_with("MILESTONE"):
			label.text = "LOCAL • OFFLINE"
	debug_overlay.open_replay_requested.connect(_open_dialog)
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.filters = PackedStringArray(["*.json,*.replay ; Replay JSON or binary"])
	file_dialog.file_selected.connect(request_replay)
	$UI.add_child(file_dialog)
	if not has_meta("shell_session"): get_window().files_dropped.connect(_files_dropped)
	var path := "res://data/mock_replay.json"
	var args := OS.get_cmdline_user_args()
	var index := args.find("--replay")
	if index >= 0 and index + 1 < args.size():
		path = args[index + 1]
	if has_meta("shell_session"): pass
	elif "--script" in OS.get_cmdline_args(): open_replay(path)
	else: request_replay(path)
	timeline.reset_camera_requested.connect($TacticalCamera.reset_view)
	var ui_theme = preload("res://scripts/application/ShellStyle.gd").theme()
	for control in $UI.get_children():
		if control is Control: control.theme = ui_theme

func apply_scene_palette(index: int) -> void:
	$WorldEnvironment.environment.background_color = preload("res://scripts/config/ScenePalette.gd").preset(index).background
	map_manager.set_palette(index)

func open_replay(path: String) -> bool:
	controller.clock.pause()
	var started := Time.get_ticks_msec()
	if controller.load_replay(path):
		_finish_scene(path, started)
		return true
	else:
		timeline.show_error(controller.load_error)
		return false

func _finish_scene(path: String, started: int) -> void:
	timeline.bind_clock(controller.clock)
	timeline.bind_rounds(controller.replay.events)
	timeline.describe_replay(controller.replay.metadata, path.get_file())
	debug_overlay.bind_controller(controller)
	map_manager.configure(controller.replay.metadata.map, controller.replay, $TestPlane)
	controller.set_map_transform(map_manager.map_transform)
	$TacticalCamera.clearance_height = map_manager.map_bounds.end.y + 1.0
	var home: Dictionary = map_manager.definition.default_camera if map_manager.definition != null else {"yaw": 38, "pitch": 45}
	$TacticalCamera.home_yaw = float(home.get("yaw", 38))
	$TacticalCamera.home_pitch = clampf(float(home.get("pitch", 45)), 15, 89.9)
	$TacticalCamera.configure_bounds(controller.bounds, controller.replay.metadata.map == "test_plane")
	view_controls.apply_mode()
	combat.bind_controller(controller)
	combat_panel.bind_replay()
	kill_markers.kills = combat.index.kills
	kill_markers.duration = controller.clock.duration
	kill_markers.queue_redraw()
	timeline.subtitle.text = "%s / %s / %s" % [path.get_file(), controller.replay.metadata.map, "Tactical map" if map_manager.model != null else "Debug Plane"]
	print("[INFO] Loaded %s: %d players in %d ms" % [path, controller.player_views.size(), Time.get_ticks_msec() - started])
	current_path = path
	replay_loading_ms = Time.get_ticks_msec() - started
	bomb_markers.events = combat.bomb.state_model.events
	bomb_markers.duration = controller.clock.duration
	bomb_markers.queue_redraw()

func _open_dialog() -> void:
	controller.clock.pause()
	file_dialog.popup_centered_ratio(0.75)

func _files_dropped(files: PackedStringArray) -> void:
	if files.size() == 1 and files[0].get_extension().to_lower() in ["json", "replay"]:
		request_replay(files[0])

func _create_loading_ui() -> void:
	loading_panel = PanelContainer.new(); $UI.add_child(loading_panel)
	loading_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new(); loading_panel.add_child(center)
	loading_label = Label.new(); loading_label.add_theme_font_size_override("font_size", 22); center.add_child(loading_label)
	loading_panel.hide()

func request_replay(path: String) -> void:
	if load_job != null:
		pending_path = path
		return
	controller.clock.pause()
	loading_path = path; loading_started = Time.get_ticks_msec()
	loading_panel.show(); loading_label.text = "Loading Replay…"
	load_job = preload("res://scripts/core/ReplayLoadJob.gd").new()
	var error: Error = load_job.start(path)
	if error != OK:
		load_job = null; loading_panel.hide(); timeline.show_error("Cannot start replay loader: %d" % error)

func _process(delta: float) -> void:
	if load_job == null: return
	_activity += delta
	loading_label.text = load_job.get_status() + [" ·", " ··", " ···"][int(_activity * 3) % 3]
	if not load_job.done(): return
	var result: Dictionary = load_job.finish()
	load_job = null
	if not pending_path.is_empty():
		var next := pending_path; pending_path = ""; request_replay(next); return
	if result.ok:
		map_manager.prepared_asset = result.get("map_asset", {})
		controller.accept_replay(result.data)
		_finish_scene(loading_path, loading_started)
	else:
		timeline.show_error(result.error)
	loading_panel.hide()

func _exit_tree() -> void:
	if load_job != null: load_job.finish()

func reload_map() -> void:
	# Preserve clock, tracks, selection and events; only replace the asset layer.
	map_manager.loaded_map=""
	map_manager.configure(controller.replay.metadata.map,controller.replay,$TestPlane)
	controller.set_map_transform(map_manager.map_transform)
	$TacticalCamera.clearance_height=map_manager.map_bounds.end.y+1.0
	view_controls.apply_mode();combat.refresh(controller.clock.current_time)
