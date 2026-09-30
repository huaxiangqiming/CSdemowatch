extends Control
## Independent decoration attached to the existing Slider; no playback changes.
const Palette = preload("res://scripts/config/TeamVisualConfig.gd")
var kills: Array = []
var duration := 1.0
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)
func _draw() -> void:
	for event in kills:
		var x: float = event.time / duration * size.x
		draw_line(Vector2(x, -5), Vector2(x, -1), Palette.team_color(event.actor_team), 1)
