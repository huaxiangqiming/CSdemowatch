extends Node3D
const Palette = preload("res://scripts/config/TeamVisualConfig.gd")
const Lines = preload("res://scripts/rendering/TacticalLines.gd")
var lines: MeshInstance3D
var shot_count := 0
var _empty := true
func _ready() -> void:
	lines = Lines.new()
	add_child(lines)
func update_shots(shots: Array, time: float, transform: RefCounted) -> void:
	shot_count = shots.size()
	if shots.is_empty() and _empty: return
	_empty = shots.is_empty()
	lines.begin()
	for shot in shots:
		var color := Palette.team_color(shot.actor_team)
		color.a = clampf(1.0 - (time - shot.time) / Palette.SHOT_LIFETIME, 0.25, 1)
		var end: Vector3 = shot.impact if shot.has_impact else shot.origin + shot.direction * Palette.SHOT_LENGTH
		var start: Vector3 = transform.position_to_godot(shot.origin)
		lines.add_line(start, transform.position_to_godot(end), color)
		# Short tactical muzzle cross, driven by the replay clock (not a timer).
		if time - shot.time < 0.08:
			lines.add_line(start - Vector3.RIGHT * 0.12, start + Vector3.RIGHT * 0.12, color)
			lines.add_line(start - Vector3.UP * 0.12, start + Vector3.UP * 0.12, color)
	lines.finish()
