extends Node3D
const Palette = preload("res://scripts/config/TeamVisualConfig.gd")
var lines: MeshInstance3D
var pool: Array[Node3D] = []
var render_count := 0
var trajectory_count := 0
var _empty := true
func _ready() -> void:
	lines = preload("res://scripts/rendering/TacticalLines.gd").new()
	add_child(lines)
func update_projectiles(active: Array, time: float, transform: RefCounted, bodies: bool, trajectories: bool) -> void:
	render_count = active.size() if bodies else 0
	trajectory_count = active.size() if trajectories else 0
	if active.is_empty() and _empty: return
	_empty = active.is_empty()
	if bodies:
		while pool.size() < active.size():
			var sphere = preload("res://scripts/rendering/FlashProjectileVisual.gd").new()
			add_child(sphere); pool.append(sphere)
	for i in pool.size():
		pool[i].visible = bodies and i < active.size()
		if pool[i].visible:
			pool[i].position = transform.position_to_godot(active[i].position_at(time))
			pool[i].configure(active[i].type, active[i].actor_team)
	lines.begin()
	if trajectories:
		for projectile in active:
			var color := Palette.team_color(projectile.actor_team)
			var end: int = projectile.frame_index(time)
			for i in range(end):
				lines.add_line(transform.position_to_godot(projectile.frames[i].position), transform.position_to_godot(projectile.frames[i + 1].position), color)
			lines.add_line(transform.position_to_godot(projectile.frames[end].position), transform.position_to_godot(projectile.position_at(time)), color)
	lines.finish()
