extends Control
const Palette = preload("res://scripts/config/TeamVisualConfig.gd")
var events: Array = []
var duration := 1.0
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
func _draw() -> void:
	for event in events:
		if event.type not in ["bomb_plant", "bomb_defuse", "bomb_explode"]: continue
		var x: float = (size.x - 12) * event.time / duration + 6
		if event.type == "bomb_plant": draw_colored_polygon(PackedVector2Array([Vector2(x, -14), Vector2(x - 4, -7), Vector2(x + 4, -7)]), Palette.BOMB)
		elif event.type == "bomb_defuse": draw_rect(Rect2(x - 3, -14, 6, 6), Palette.BOMB, false, 1.5)
		else:
			draw_line(Vector2(x - 4, -14), Vector2(x + 4, -7), Palette.BOMB, 2)
			draw_line(Vector2(x + 4, -14), Vector2(x - 4, -7), Palette.BOMB, 2)
