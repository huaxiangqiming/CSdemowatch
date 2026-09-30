extends Control
## Screen-space vector icons anchored to the 3D name. Camera-facing, fixed pixel size.
var statuses: Array = []
const COLORS := {"flashed_players": Color("fff9e8"), "burning": Color("ff692e"), "he_hit": Color("ffcd68"), "in_smoke": Color("b3bcc7"), "bomb_carrier": Color("ff5b68")}
func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
func set_statuses(value: Array) -> void:
	if statuses != value: statuses = value.filter(func(kind): return kind != "bomb_carrier"); queue_redraw()
func _draw() -> void:
	for i in statuses.size():
		var kind: String = statuses[i]
		var c: Color = COLORS[kind]
		var v := Vector2((i - (statuses.size() - 1) * 0.5) * 27, 0)
		match kind:
			"flashed_players":
				var points := PackedVector2Array()
				for n in 16: points.append(v + Vector2.from_angle(n * TAU / 16) * (10 if n % 2 == 0 else 3))
				_shape(points, c)
			"burning":
				_shape(PackedVector2Array([v+Vector2(0,-10),v+Vector2(3,-3),v+Vector2(6,-6),v+Vector2(9,2),v+Vector2(5,9),v+Vector2(-5,9),v+Vector2(-9,2),v+Vector2(-4,-6),v+Vector2(-4,1)]),c)
				draw_circle(v+Vector2(0,4),3,Color("ffe095"))
			"he_hit":
				draw_circle(v,7,Color(0.04,0.05,0.06,0.8),false,3,true)
				draw_circle(v,6,c,false,2,true)
				for n in 4:
					var d := Vector2.from_angle(PI/4+n*PI/2); draw_line(v+d*8,v+d*11,c,2,true)
				draw_line(v+Vector2(-3,0),v+Vector2(3,0),c,2)
			"in_smoke":
				draw_circle(v+Vector2(-5,2),6,Color(0.04,0.05,0.06,0.8)); draw_circle(v+Vector2(0,-2),7,Color(0.04,0.05,0.06,0.8)); draw_circle(v+Vector2(6,2),5,Color(0.04,0.05,0.06,0.8));
				draw_circle(v+Vector2(-5,2),5,c); draw_circle(v+Vector2(0,-2),6,c); draw_circle(v+Vector2(6,2),4,c); draw_rect(Rect2(v+Vector2(-6,2),Vector2(13,5)),c)
func _shape(points: PackedVector2Array, color: Color) -> void:
	for i in points.size():
		draw_line(points[i], points[(i+1)%points.size()], Color(0.04,0.05,0.06,0.8), 2, true)
		draw_circle(points[i], 1, Color(0.04,0.05,0.06,0.8))
	draw_colored_polygon(points, color)
