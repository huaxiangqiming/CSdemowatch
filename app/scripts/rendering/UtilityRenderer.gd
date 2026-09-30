extends Node3D
var pool: Array[Node3D] = []
var active_ids: Array[String] = []
var options := {"smoke_tint": true, "smoke_marker": true, "smoke_opacity": 1}
var patch_count := 0
func update_effects(active: Array, time: float, transform: RefCounted) -> void:
	active_ids.clear()
	patch_count = 0
	while pool.size() < active.size():
		var view = preload("res://scripts/rendering/UtilityEffectView.gd").new()
		add_child(view); pool.append(view)
	for i in pool.size():
		pool[i].visible = i < active.size()
		if pool[i].visible:
			pool[i].options = options
			pool[i].show_event(active[i], time, transform)
			patch_count += pool[i].patch_count
			active_ids.append(active[i].id)
