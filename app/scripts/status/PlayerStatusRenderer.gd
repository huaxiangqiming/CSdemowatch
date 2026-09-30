extends Node3D
var resolver = preload("res://scripts/status/PlayerStatusResolver.gd").new()
var icons := {}
var active_count := 0
var canvas: CanvasLayer
var controller: Node3D
var current := {}
func _ready() -> void:
	canvas = CanvasLayer.new(); canvas.layer = 0; add_child(canvas)
func build(_events: Array) -> void:
	for icon in icons.values(): icon.queue_free()
	icons.clear(); current.clear()
func update_statuses(time: float, replay: Node3D, layers: Dictionary) -> void:
	controller = replay; active_count = 0; current.clear()
	for id in replay.player_views:
		var view = replay.player_views[id]
		var statuses: Array = resolver.resolve(time,id,replay.current_states.get(id,{}))
		var shown: Array = []
		for kind in statuses:
			if layers.player_status and layers.players and layers.get(kind,true): shown.append(kind)
		if "flashed_players" in shown: active_count += 1
		current[id] = shown
		view.set_carrier("bomb_carrier" in shown)
		if not icons.has(id):
			icons[id] = preload("res://scripts/status/PlayerStatusIndicator.gd").new(); canvas.add_child(icons[id])
		icons[id].set_statuses(shown.filter(func(kind): return kind != "bomb_carrier"))
	_process(0)
func _process(_delta: float) -> void:
	if controller == null: return
	var camera := get_viewport().get_camera_3d()
	if camera == null: return
	for id in icons:
		var view = controller.player_views.get(id)
		if not is_instance_valid(view): icons[id].hide(); continue
		var anchor: Vector3 = view.get_node("Name").global_position
		icons[id].visible = view.visible and not icons[id].statuses.is_empty() and not camera.is_position_behind(anchor)
		icons[id].position = camera.unproject_position(anchor) - Vector2(0,maxf(26, view.name_size + 12))
